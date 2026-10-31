// POST /api/auth/login { email, password } → { token, quota }
import { json, err, body, db, newSession, session, quota, publicQuota, hashPassword, sameString, throttle, ipKey, carryGuestUsage } from '../../../server/cozy.js';

export async function onRequestPost({ request, env }) {
  try {
    const { email: rawEmail, password } = await body(request);
    const email = String(rawEmail || '').trim().toLowerCase();
    if (!(await throttle(env, 'login:' + (await ipKey(request)), 10)) || !(await throttle(env, 'login:' + email, 10))) {
      return err(429, 'too_many', 'Too many tries. Wait 15 minutes and try again.');
    }
    const d = await db(env);
    const u = await d.prepare('SELECT id, pass, salt FROM users WHERE email = ?').bind(email).first();
    const { hash } = await hashPassword(String(password || ''), u ? u.salt : undefined);
    if (!u || !sameString(hash, u.pass)) return err(401, 'wrong', 'Wrong email or password.');
    const was = await session(request, env);
    if (was && was.kind === 'guest') {
      await carryGuestUsage(env, was.guestId, u.id);
      await d.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(was.tokenHash).run();
    }
    const token = await newSession(env, { userId: u.id });
    const q = await quota(env, { kind: 'member', userId: u.id, email }, request);
    return json({ token, quota: publicQuota(q) });
  } catch (e) {
    return err(500, 'server', String(e.message || e));
  }
}
