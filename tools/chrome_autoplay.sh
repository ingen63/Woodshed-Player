#!/bin/sh
# #13/AK4: Chrome for `flutter test --platform chrome` with sound allowed without a user gesture. The web
# core's AudioContext only runs after a click, which a test cannot give; with this flag it starts at once.
# Usage: CHROME_EXECUTABLE="$PWD/tools/chrome_autoplay.sh" flutter test --platform chrome ...
# WP_CHROME names another Chrome; otherwise the usual places on macOS and Linux are tried.
for c in "${WP_CHROME:-}" "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  google-chrome google-chrome-stable chromium chromium-browser; do
  if [ -n "$c" ] && command -v "$c" >/dev/null 2>&1; then
    exec "$c" --autoplay-policy=no-user-gesture-required "$@"
  fi
done
echo "chrome_autoplay: no Chrome found (set WP_CHROME)" >&2
exit 1
