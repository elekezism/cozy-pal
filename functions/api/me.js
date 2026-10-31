// GET /api/me → { kind: 'guest'|'member', email, usedSec, limitSec, remainingSec, resetsAt }
import { json, err, session, quota, publicQuota } from '../../server/cozy.js';

export async function onRequestGet({ request, env }) {
  try {
    const s = await session(request, env);
    if (!s) return err(401, 'no_session', 'Sign in or continue as a guest.');
    return json(publicQuota(await quota(env, s, request)));
  } catch (e) {
    return err(500, 'server', String(e.message || e));
  }
}
