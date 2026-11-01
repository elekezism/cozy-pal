// Cozy Pal offline cache. Keeps the app's own files so it opens without a
// connection and counts as installable. The app's code always comes from the
// network first, so a new deploy shows up on the next load; the cache is only
// the fallback. /api/* (AI, accounts, fetch proxy) is never cached.
const CACHE = 'cozy-pal-v1';
const SHELL = ['./', 'index.html', 'flutter_bootstrap.js', 'main.dart.js', 'manifest.json', 'favicon.png', 'icons/Icon-192.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // Flutter's drawing engine and fonts: versioned URLs, so cache first
  if (url.host === 'www.gstatic.com' || url.host === 'fonts.gstatic.com') {
    event.respondWith(
      caches.match(req).then((hit) => hit || fetch(req).then((res) => {
        if (res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      })),
    );
    return;
  }

  if (url.origin !== self.location.origin || url.pathname.startsWith('/api/') || url.pathname === '/oauth.html') return;

  // the app's own files: network first, cache as the offline fallback
  event.respondWith(
    fetch(req)
      .then((res) => {
        if (res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      })
      .catch(() => caches.match(req).then((hit) => hit || (req.mode === 'navigate' ? caches.match('index.html') : Response.error()))),
  );
});
