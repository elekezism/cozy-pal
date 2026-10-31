// POST /api/auth/logout → { ok }
import { json, err, db, session } from '../../../server/cozy.js';

export async function onRequestPost({ request, env }) {
  try {
    const s = await session(request, env);
    if (s) await (await db(env)).prepare('DELETE FROM sessions WHERE token_hash = ?').bind(s.tokenHash).run();
    return json({ ok: true });
  } catch (e) {
    return err(500, 'server', String(e.message || e));
  }
}
