// Service worker of the web app (#41/AK2), registered by index.html with scope './' (…/app/).
// GitHub Pages does not allow custom headers, so this worker sets COOP/COEP on every same-origin
// response. The app is then "cross-origin isolated" and gets SharedArrayBuffer. Same procedure as the
// W0 test page (web/w0/sw.js, #32).
// #39/AK1: it is also the app's offline start, the app's only service worker. app/tool/stamp_sw.dart
// writes the build's version and file list into SHELL below after `flutter build web`. On install the
// worker stores these files in the cache «wp-shell-<version>»; once active it deletes the caches of
// older versions. A new build changes this file, so the browser installs the new worker, which fetches
// the new files; the old cache is removed when it takes over. Files of the shell come from the cache
// first; pages and everything else from the network, falling back to the cache when offline.
// The app loads only files from its own origin; requests to other origins are not touched.

// Replaced by app/tool/stamp_sw.dart; unstamped (flutter run, test builds) the worker caches what it fetches.
const SHELL = { version: 'dev', files: [] }; // @shell

const PREFIX = 'wp-shell-';
const CACHE = PREFIX + SHELL.version;

/** Absolute URL of a file of the app (paths are relative to the worker's scope). */
const url = (path) => new URL(path, self.registration.scope).href;

/** Renderer files the browser picks at run time (CanvasKit variants): kept if the old cache had them. */
const RENDERER = 'canvaskit/';

self.addEventListener('install', (e) => {
  e.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    const wanted = new Set(SHELL.files.map(url));
    // The CanvasKit variant this browser uses is not in the list (it depends on the browser); take the
    // same files again if an older version had cached them, so the next offline start finds them.
    for (const name of await caches.keys()) {
      if (!name.startsWith(PREFIX) || name === CACHE) continue;
      for (const req of await (await caches.open(name)).keys()) {
        if (req.url.startsWith(url(RENDERER))) wanted.add(req.url);
      }
    }
    // A file that fails does not stop the install (COOP/COEP must work in any case); it is cached
    // when the app fetches it.
    await Promise.allSettled([...wanted].map(async (u) => {
      // network-free: own origin, files of this app listed by stamp_sw.dart (#39/AK1)
      const response = await fetch(u, { cache: 'no-cache' });
      if (response.ok) await cache.put(u, isolate(response));
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (e) => e.waitUntil((async () => {
  for (const name of await caches.keys()) {
    if (name.startsWith(PREFIX) && name !== CACHE) await caches.delete(name);
  }
  await self.clients.claim();
})()));

/** Copies a response and adds the headers for cross-origin isolation. */
function isolate(response) {
  if (response.status === 0) return response;  // opaque or opaque-redirect response, cannot be changed
  const headers = new Headers(response.headers);
  headers.set('Cross-Origin-Opener-Policy', 'same-origin');
  headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
  headers.set('Cross-Origin-Resource-Policy', 'same-origin');
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

/** The page itself (…/app/ or …/app/index.html) is cached as index.html. */
function cacheKey(request) {
  return request.mode === 'navigate' ? url('index.html') : request.url;
}

/** Stamped build: files come from the cache first. Unstamped (development) always from the network. */
const CACHE_FIRST = SHELL.version !== 'dev';

/** Files: cache first (stamped build). Pages and unstamped builds: network first, the cache when offline. */
async function respond(request) {
  const cache = await caches.open(CACHE);
  const key = cacheKey(request);
  if (request.method !== 'GET') {
    // network-free: own origin, the fetch listener passes only same-origin requests (#58)
    return isolate(await fetch(request));
  }
  if (CACHE_FIRST && request.mode !== 'navigate' && !request.headers.has('range')) {
    const hit = await cache.match(key);
    if (hit) return hit;
  }
  try {
    // network-free: own origin, the fetch listener passes only same-origin requests (#58)
    const response = isolate(await fetch(request));
    if (response.ok && response.status === 200) await cache.put(key, response.clone());
    return response;
  } catch (err) {
    const hit = await cache.match(key);
    if (hit) return hit;
    throw err;
  }
}

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.cache === 'only-if-cached' && req.mode !== 'same-origin') return;
  if (new URL(req.url).origin !== self.location.origin) return;
  e.respondWith(respond(req));
});
