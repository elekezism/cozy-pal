// POST /api/ai/chat { system, user, maxTokens } → { text, quota }
// The built-in AI: calls OpenRouter with the server's key and counts how long
// the call took against the account's daily AI time.
import { json, err, body, session, quota, publicQuota, charge, DEFAULT_MODEL } from '../../../server/cozy.js';

const MAX_CHARS = 24000; // keep prompts small (time is the budget)

export async function onRequestPost({ request, env }) {
  try {
    if (!env.OPENROUTER_API_KEY) return err(503, 'not_configured', 'The built-in AI isn\'t set up on this server yet.');
    const s = await session(request, env);
    if (!s) return err(401, 'no_session', 'Sign in or continue as a guest.');
    const q = await quota(env, s, request);
    if (q._usedMs >= q._limitMs || q.ipBlocked) {
      return err(429, 'out_of_time', s.kind === 'guest'
        ? 'That\'s all the free AI time for today. Make an account for 20 minutes a day, or come back tomorrow.'
        : 'That\'s all your AI time for today. It resets at midnight.', { quota: publicQuota(q) });
    }
    const { system = '', user = '', maxTokens = 400 } = await body(request);
    if (!user || typeof user !== 'string') return err(400, 'bad_request', 'Nothing to ask.');
    if (String(system).length + user.length > MAX_CHARS) return err(413, 'too_long', 'That\'s too much text for one question.');

    const payload = (withReasoningOff) => ({
      model: env.AI_MODEL || DEFAULT_MODEL,
      max_tokens: Math.min(800, Math.max(32, Number(maxTokens) || 400)),
      temperature: 0.6,
      messages: [
        ...(system ? [{ role: 'system', content: String(system) }] : []),
        { role: 'user', content: user },
      ],
      // answers are short: skip long "thinking", it would eat the user's time
      ...(withReasoningOff ? { reasoning: { enabled: false, exclude: true } } : {}),
    });
    const site = new URL(request.url).origin;
    const call = (p) => fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'authorization': 'Bearer ' + env.OPENROUTER_API_KEY,
        'content-type': 'application/json',
        'http-referer': site,
        'x-title': 'Cozy Pal',
      },
      body: JSON.stringify(p),
      signal: AbortSignal.timeout(45000),
    });

    const t0 = Date.now();
    let res = await call(payload(true));
    if (res.status === 400) res = await call(payload(false)); // model didn't like the reasoning switch
    const ms = Math.max(1000, Date.now() - t0); // at least 1 second per request
    const data = await res.json().catch(() => ({}));

    if (!res.ok) {
      // upstream problems aren't charged
      const busy = res.status === 429 || res.status === 503;
      return err(busy ? 503 : 502, busy ? 'busy' : 'upstream',
        busy ? 'The free AI is busy right now. Try again in a minute.' : 'The AI had a problem: ' + (data?.error?.message || res.status),
        { quota: publicQuota(q) });
    }
    const msg = data?.choices?.[0]?.message || {};
    let text = (typeof msg.content === 'string' ? msg.content : Array.isArray(msg.content) ? msg.content.map((c) => c.text || '').join(' ') : '').trim();
    // some models put everything in "reasoning" when cut short: keep its last paragraph rather than nothing
    if (!text && typeof msg.reasoning === 'string') text = msg.reasoning.trim().split(/\n\s*\n/).pop().slice(-600);
    await charge(env, s, request, ms);
    const after = await quota(env, s, request);
    return json({ text, model: data.model || env.AI_MODEL || DEFAULT_MODEL, chargedSec: Math.round(ms / 100) / 10, quota: publicQuota(after) });
  } catch (e) {
    const timeout = e && (e.name === 'TimeoutError' || e.name === 'AbortError');
    return err(timeout ? 504 : 500, timeout ? 'timeout' : 'server', timeout ? 'The AI took too long. Try again.' : String(e.message || e));
  }
}
