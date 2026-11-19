// Service worker of the web app (#41/AK2), registered by index.html with scope './' (…/app/).
// GitHub Pages does not allow custom headers, so this worker sets COOP/COEP on every same-origin
// response. The app is then "cross-origin isolated" and gets SharedArrayBuffer. Same procedure as the
// W0 test page (web/w0/sw.js, #32).
// This is the app's only service worker: the offline start of the PWA (#39) extends it here
// (precache on install, cache fallback in respond()) instead of registering a second one.
// The app loads only files from its own origin; requests to other origins are not touched.

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

/** Copies a response and adds the headers for cross-origin isolation. */
function isolate(response) {
  if (response.status === 0) return response;  // opaque or opaque-redirect response, cannot be changed
  const headers = new Headers(response.headers);
  headers.set('Cross-Origin-Opener-Policy', 'same-origin');
  headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
  headers.set('Cross-Origin-Resource-Policy', 'same-origin');
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

/** Network first. #39 adds the cache fallback for the offline start here. */
async function respond(request) {
  // network-free: own origin, the fetch listener passes only same-origin requests (#58)
  return isolate(await fetch(request));
}

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.cache === 'only-if-cached' && req.mode !== 'same-origin') return;
  if (new URL(req.url).origin !== self.location.origin) return;
  e.respondWith(respond(req));
});
