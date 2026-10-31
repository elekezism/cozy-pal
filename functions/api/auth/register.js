// POST /api/auth/register { email, password } → { token, quota }   (20 minutes a day)
// Send the current guest token as Authorization to carry over today's usage.
import { json, err, body, db, newSession, session, quota, publicQuota, hashPassword, validEmail, carryGuestUsage, throttle, ipKey } from '../../../server/cozy.js';

export async function onRequestPost({ request, env }) {
  try {
    const { email: rawEmail, password } = await body(request);
    const email = String(rawEmail || '').trim().toLowerCase();
    if (!validEmail(email)) return err(400, 'bad_email', 'That email address doesn\'t look right.');
    if (typeof password !== 'string' || password.length < 8 || password.length > 200) {
      return err(400, 'weak_password', 'Use a password of at least 8 characters.');
    }
    if (!(await throttle(env, 'reg:' + (await ipKey(request)), 10, 3600e3))) {
      return err(429, 'too_many', 'Too many sign-ups from this network. Try again later.');
    }
    const d = await db(env);
    if (await d.prepare('SELECT 1 FROM users WHERE email = ?').bind(email).first()) {
      return err(409, 'exists', 'There\'s already an account with that email. Sign in instead.');
    }
    const { hash, salt } = await hashPassword(password);
    const id = crypto.randomUUID();
    await d.prepare('INSERT INTO users (id, email, pass, salt, created) VALUES (?, ?, ?, ?, ?)').bind(id, email, hash, salt, Date.now()).run();
    const was = await session(request, env);
    if (was && was.kind === 'guest') {
      await carryGuestUsage(env, was.guestId, id);
      await d.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(was.tokenHash).run();
    }
    const token = await newSession(env, { userId: id });
    const q = await quota(env, { kind: 'member', userId: id, email }, request);
    return json({ token, quota: publicQuota(q) });
  } catch (e) {
    return err(500, 'server', String(e.message || e));
  }
}
