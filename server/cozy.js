// Cozy Pal backend helpers (used by the Cloudflare Pages Functions in /functions).
//
// "AI time" quota: every request to the built-in AI is timed on the server,
// from sending it to OpenRouter until the answer is back, and that time is
// counted against the account's daily allowance:
//   guests     GUEST_SECONDS  (default 600  = 10 minutes / day)
//   registered MEMBER_SECONDS (default 1200 = 20 minutes / day)
// Days roll over at midnight in QUOTA_TZ_OFFSET_MINUTES (default 0 = UTC).
//
// Bindings / settings (Cloudflare Pages → Settings):
//   DB                  D1 database (tables are created automatically)
//   OPENROUTER_API_KEY  secret, from openrouter.ai/keys
//   AI_MODEL            optional, default nvidia/nemotron-3.5-super-vl:free

export const DEFAULT_MODEL = 'nvidia/nemotron-3.5-super-vl:free';

export function limits(env) {
  return {
    guest: Number(env.GUEST_SECONDS || 600),
    member: Number(env.MEMBER_SECONDS || 1200),
    // all guests behind one IP address together get this many times the guest allowance
    guestIpFactor: Number(env.GUEST_IP_FACTOR || 3),
    tzOffsetMin: Number(env.QUOTA_TZ_OFFSET_MINUTES || 0),
  };
}

// ---------------------------------------------------------------- http

export function json(data, status = 200, extra = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...extra },
  });
}

export const err = (status, code, message, more = {}) => json({ error: code, message, ...more }, status);

export async function body(request) {
  try {
    return await request.json();
  } catch {
    return {};
  }
}

// ---------------------------------------------------------------- db

let ready = null;
export function db(env) {
  if (!env.DB) throw new Error('No D1 database bound as DB. Add it in Pages → Settings → Bindings.');
  if (!ready) {
    ready = env.DB.batch([
      env.DB.prepare(`CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY, email TEXT UNIQUE NOT NULL, pass TEXT NOT NULL, salt TEXT NOT NULL, created INTEGER NOT NULL)`),
      env.DB.prepare(`CREATE TABLE IF NOT EXISTS sessions (
        token_hash TEXT PRIMARY KEY, user_id TEXT, guest_id TEXT, created INTEGER NOT NULL, last INTEGER NOT NULL)`),
      env.DB.prepare(`CREATE TABLE IF NOT EXISTS usage (
        subject TEXT NOT NULL, day TEXT NOT NULL, ms INTEGER NOT NULL DEFAULT 0, requests INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (subject, day))`),
      env.DB.prepare(`CREATE TABLE IF NOT EXISTS attempts (key TEXT PRIMARY KEY, n INTEGER NOT NULL, until INTEGER NOT NULL)`),
    ]).catch((e) => {
      ready = null;
      throw e;
    });
  }
  return ready.then(() => env.DB);
}

// ---------------------------------------------------------------- crypto

const enc = new TextEncoder();
const b64url = (buf) =>
  btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

export function randomToken(prefix = 'cp_') {
  const b = new Uint8Array(32);
  crypto.getRandomValues(b);
  return prefix + b64url(b);
}

export async function sha256(text) {
  return b64url(await crypto.subtle.digest('SHA-256', enc.encode(text)));
}

export async function hashPassword(password, saltB64) {
  const salt = saltB64 ? Uint8Array.from(atob(saltB64.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0)) : crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: 100000 }, key, 256);
  return { hash: b64url(bits), salt: b64url(salt) };
}

/** Constant-time string compare. */
export function sameString(a, b) {
  if (a.length !== b.length) return false;
  let x = 0;
  for (let i = 0; i < a.length; i++) x |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return x === 0;
}

export async function ipKey(request) {
  const ip = request.headers.get('cf-connecting-ip') || request.headers.get('x-forwarded-for') || 'unknown';
  return 'ip:' + (await sha256('cozypal-ip:' + ip)).slice(0, 22);
}

// ---------------------------------------------------------------- sessions

/** Creates a session for a user (member) or a guest; returns the bearer token. */
export async function newSession(env, { userId = null, guestId = null }) {
  const d = await db(env);
  const token = randomToken();
  const now = Date.now();
  await d.prepare('INSERT INTO sessions (token_hash, user_id, guest_id, created, last) VALUES (?, ?, ?, ?, ?)')
    .bind(await sha256(token), userId, guestId, now, now).run();
  return token;
}

/** Reads "Authorization: Bearer cp_…". Returns {kind, userId, guestId, email, tokenHash} or null. */
export async function session(request, env) {
  const m = (request.headers.get('authorization') || '').match(/^Bearer\s+(cp_[A-Za-z0-9_-]{20,})$/);
  if (!m) return null;
  const d = await db(env);
  const th = await sha256(m[1]);
  const row = await d.prepare(
    `SELECT s.user_id, s.guest_id, s.last, u.email FROM sessions s LEFT JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?`,
  ).bind(th).first();
  if (!row) return null;
  const now = Date.now();
  if (now - row.last > 6 * 3600e3) {
    await d.prepare('UPDATE sessions SET last = ? WHERE token_hash = ?').bind(now, th).run();
  }
  return row.user_id
    ? { kind: 'member', userId: row.user_id, email: row.email, tokenHash: th }
    : { kind: 'guest', guestId: row.guest_id, tokenHash: th };
}

// ---------------------------------------------------------------- quota

export function dayKey(env, t = Date.now()) {
  const off = limits(env).tzOffsetMin * 60e3;
  return new Date(t + off).toISOString().slice(0, 10);
}

/** Next midnight (in the quota time zone) as an ISO time. */
export function resetsAt(env, t = Date.now()) {
  const off = limits(env).tzOffsetMin * 60e3;
  const local = new Date(t + off);
  const next = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate() + 1) - off;
  return new Date(next).toISOString();
}

export const subjectOf = (s) => (s.kind === 'member' ? 'u:' + s.userId : 'g:' + s.guestId);

async function usedMs(d, subject, day) {
  const r = await d.prepare('SELECT ms FROM usage WHERE subject = ? AND day = ?').bind(subject, day).first();
  return r ? r.ms : 0;
}

/** How much AI time this session has today. */
export async function quota(env, s, request) {
  const d = await db(env);
  const L = limits(env);
  const day = dayKey(env);
  const limitMs = (s.kind === 'member' ? L.member : L.guest) * 1000;
  let used = await usedMs(d, subjectOf(s), day);
  let ipBlocked = false;
  if (s.kind === 'guest' && request) {
    const ipUsed = await usedMs(d, await ipKey(request), day);
    ipBlocked = ipUsed >= L.guest * L.guestIpFactor * 1000;
  }
  return {
    kind: s.kind,
    email: s.email || null,
    usedSec: Math.round(used / 100) / 10,
    limitSec: limitMs / 1000,
    remainingSec: Math.max(0, Math.round((limitMs - used) / 100) / 10),
    resetsAt: resetsAt(env),
    ipBlocked,
    _usedMs: used,
    _limitMs: limitMs,
  };
}

export const publicQuota = ({ _usedMs, _limitMs, ...q }) => q;

export async function charge(env, s, request, ms) {
  const d = await db(env);
  const day = dayKey(env);
  const subjects = [subjectOf(s)];
  if (s.kind === 'guest' && request) subjects.push(await ipKey(request));
  await d.batch(subjects.map((sub) =>
    d.prepare(`INSERT INTO usage (subject, day, ms, requests) VALUES (?, ?, ?, 1)
               ON CONFLICT(subject, day) DO UPDATE SET ms = ms + excluded.ms, requests = requests + 1`).bind(sub, day, ms)));
}

/** Registering mid-day keeps what the guest already used today (no double allowance). */
export async function carryGuestUsage(env, guestId, userId) {
  const d = await db(env);
  const day = dayKey(env);
  const g = await usedMs(d, 'g:' + guestId, day);
  if (g > 0) {
    await d.prepare(`INSERT INTO usage (subject, day, ms, requests) VALUES (?, ?, ?, 0)
                     ON CONFLICT(subject, day) DO UPDATE SET ms = MAX(ms, excluded.ms)`).bind('u:' + userId, day, g).run();
  }
}

// ---------------------------------------------------------------- brute-force guard

/** Allows [max] tries per [windowMs] for a key (e.g. login per IP). */
export async function throttle(env, key, max = 10, windowMs = 15 * 60e3) {
  const d = await db(env);
  const now = Date.now();
  const r = await d.prepare('SELECT n, until FROM attempts WHERE key = ?').bind(key).first();
  if (r && r.until > now && r.n >= max) return false;
  if (!r || r.until <= now) {
    await d.prepare('INSERT OR REPLACE INTO attempts (key, n, until) VALUES (?, 1, ?)').bind(key, now + windowMs).run();
  } else {
    await d.prepare('UPDATE attempts SET n = n + 1 WHERE key = ?').bind(key).run();
  }
  return true;
}

export const validEmail = (e) => typeof e === 'string' && e.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e);
