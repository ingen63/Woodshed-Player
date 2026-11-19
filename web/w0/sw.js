// Machbarkeitstest W0 (#32): Service Worker.
// 1. Setzt COOP/COEP auf alle Antworten, damit die Seite «cross-origin isolated» ist und
//    SharedArrayBuffer bekommt (GitHub Pages erlaubt keine eigenen Header).
// 2. Hält die Seite offline verfügbar (erst Netz, sonst Cache).
// Die Seite lädt nur Dateien vom eigenen Ursprung; fremde Anfragen gibt es nicht.

const CACHE = 'w0-v2';

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

function isolate(response) {
  if (response.status === 0) return response;  // undurchsichtige Antwort, nicht veränderbar
  const headers = new Headers(response.headers);
  headers.set('Cross-Origin-Opener-Policy', 'same-origin');
  headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
  headers.set('Cross-Origin-Resource-Policy', 'same-origin');
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.cache === 'only-if-cached' && req.mode !== 'same-origin') return;
  if (new URL(req.url).origin !== self.location.origin) return;
  e.respondWith((async () => {
    const cache = await caches.open(CACHE);
    try {
      // Am HTTP-Cache vorbei nachfragen, sonst liefert Pages bis zu 10 min alte Dateien.
      const res = req.method === 'GET'
        ? await fetch(req.url, { cache: 'no-cache', credentials: 'same-origin' })
        : await fetch(req);
      if (req.method === 'GET' && res.ok) cache.put(req, res.clone());
      return isolate(res);
    } catch (err) {
      const hit = await cache.match(req, { ignoreSearch: true });
      if (hit) return isolate(hit);
      throw err;
    }
  })());
});
