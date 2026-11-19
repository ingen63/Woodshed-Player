{{flutter_js}}
{{flutter_build_config}}
// Kein Netzwerk ausser zur eigenen Seite (#34): CanvasKit liegt neben der App statt auf dem Google-CDN,
// Ersatzschriften werden nicht von fonts.gstatic.com geholt (die App bringt Inter und JetBrains Mono mit).
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
    fontFallbackBaseUrl: 'fonts/fallback/',
  },
});
