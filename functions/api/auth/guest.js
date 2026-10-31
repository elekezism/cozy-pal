// POST /api/auth/guest → { token, quota }   (a new guest: 10 minutes of AI a day)
import { json, err, newSession, quota, publicQuota, randomToken, throttle, ipKey } from '../../../server/cozy.js';

export async function onRequestPost({ request, env }) {
  try {
    if (!(await throttle(env, 'guest:' + (await ipKey(request)), 20, 3600e3))) {
      return err(429, 'too_many', 'Too many new guests from this network. Try again later or sign in.');
    }
    const guestId = randomToken('g_').slice(0, 26);
    const token = await newSession(env, { guestId });
    const q = await quota(env, { kind: 'guest', guestId }, request);
    return json({ token, quota: publicQuota(q) });
  } catch (e) {
    return err(500, 'server', String(e.message || e));
  }
}
