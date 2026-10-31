// Cloudflare Pages Function: /api/fetch?url=…
// Browsers block the web app from reading other sites (CORS). This forwards
// GET requests to a short allow-list of public, key-free sources the pet
// uses (Apple's song/app search, artwork, meme-api.com, Reddit images,
// itch.io feeds and covers) and adds CORS headers. Anything else is refused,
// so it can't be used as an open proxy. Nothing is logged or stored.
const ALLOWED = [
  /^itunes\.apple\.com$/,
  /^is\d+-ssl\.mzstatic\.com$/,
  /^meme-api\.com$/,
  /^i\.redd\.it$/,
  /^preview\.redd\.it$/,
  /^i\.imgur\.com$/,
  /^itch\.io$/,
  /^img\.itch\.zone$/,
];
const MAX_BYTES = 15 * 1024 * 1024;

export async function onRequest({ request }) {
  const cors = {
    'Access-Control-Allow-Origin': new URL(request.url).origin,
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Vary': 'Origin',
  };
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (request.method !== 'GET') return new Response('Method not allowed', { status: 405, headers: cors });

  let target;
  try {
    target = new URL(new URL(request.url).searchParams.get('url') || '');
  } catch {
    return new Response('Bad url', { status: 400, headers: cors });
  }
  if (target.protocol !== 'https:' || !ALLOWED.some((re) => re.test(target.hostname))) {
    return new Response('Host not allowed', { status: 403, headers: cors });
  }

  const upstream = await fetch(target.toString(), {
    headers: { 'User-Agent': 'CozyPal/1.0 (+web)', 'Accept': '*/*' },
    cf: { cacheTtl: target.hostname.endsWith('mzstatic.com') || target.hostname.includes('redd.it') || target.hostname === 'img.itch.zone' ? 86400 : 300, cacheEverything: true },
    redirect: 'follow',
  });
  const len = Number(upstream.headers.get('content-length') || 0);
  if (len > MAX_BYTES) return new Response('Too large', { status: 413, headers: cors });

  const headers = new Headers(cors);
  for (const h of ['content-type', 'cache-control', 'last-modified', 'etag']) {
    const v = upstream.headers.get(h);
    if (v) headers.set(h, v);
  }
  headers.set('X-Content-Type-Options', 'nosniff');
  return new Response(upstream.body, { status: upstream.status, headers });
}
