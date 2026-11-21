{{flutter_js}}
{{flutter_build_config}}
// No network except the own site (#34): CanvasKit lies next to the app instead of on Google's CDN,
// fallback fonts are not fetched from fonts.gstatic.com (the app bundles Inter and JetBrains Mono).
//
// #82: characters Inter lacks (CJK, emoji) make the web engine ask for Noto fallback fonts under
// fontFallbackBaseUrl. None are bundled and none are loaded: such requests are answered here with
// 410 Gone without reaching the network (no request, no 404). The engine then gives up on the font
// and draws a replacement glyph (tofu) instead.
(() => {
  const fallbackBase = new URL('fonts/fallback/', document.baseURI).href;
  const fetch = window.fetch.bind(window);
  window.fetch = (input, init) => {
    let url = '';
    try {
      url = new URL(input instanceof Request ? input.url : String(input), document.baseURI).href;
    } catch (_) {
      // Not a URL the browser could resolve: fetch reports that itself.
    }
    if (url.startsWith(fallbackBase)) {
      return Promise.resolve(new Response(null, { status: 410, statusText: 'Not bundled' }));
    }
    // network-free: own origin, forwards the page's own calls unchanged and adds none (#82)
    return fetch(input, init);
  };
})();
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
    fontFallbackBaseUrl: 'fonts/fallback/',
  },
});
