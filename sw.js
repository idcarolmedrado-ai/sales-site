const CACHE_NAME = 'ea-sales-v34';
const ASSETS = [
  '/sales-site/',
  '/sales-site/index.html',
  '/sales-site/manifest.json',
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(ASSETS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // Always network-first for Supabase API and auth calls
  if (url.hostname.includes('supabase.co')) {
    e.respondWith(
      fetch(e.request).catch(() => new Response('{}', { status: 503, headers: { 'Content-Type': 'application/json' } }))
    );
    return;
  }

  // Cache-first + background revalidation for the app shell
  if (url.pathname.endsWith('.html') || url.pathname === '/sales-site/' || url.pathname === '/sales-site') {
    e.respondWith(
      caches.open(CACHE_NAME).then(cache =>
        cache.match(e.request).then(cached => {
          const fetchAndCache = fetch(e.request).then(resp => {
            if (resp.ok) cache.put(e.request, resp.clone());
            return resp;
          }).catch(() => cached); // network down — return stale

          // Serve stale immediately; notify clients when fresh arrives
          if (cached) {
            fetchAndCache.then(fresh => {
              if (fresh && fresh.url !== cached.url) return; // same request
              self.clients.matchAll().then(clients =>
                clients.forEach(c => c.postMessage({ type: 'SW_UPDATED' }))
              );
            }).catch(() => {});
            return cached;
          }
          return fetchAndCache;
        })
      )
    );
    return;
  }

  // Cache-first for all other static assets (fonts, CDN libs)
  e.respondWith(
    caches.match(e.request).then(cached =>
      cached || fetch(e.request).then(resp => {
        if (resp.ok) {
          const clone = resp.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(e.request, clone));
        }
        return resp;
      })
    )
  );
});
