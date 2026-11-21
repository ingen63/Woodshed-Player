#!/bin/sh
# #13/AK5: smoke test of the built macOS app. Starts the app with WP_SMOKE=1: it opens its window,
# imports a sine file it generates itself into a temporary library, plays it offline (local file, no
# network) until the position has moved, pauses and quits. Passed when the app ends with exit code 0
# and prints «smoke: ok»; nothing needs a click. Flow in app/lib/app/smoke.dart.
# Without an audio device (GitHub's macOS runners) set WP_AUDIO_BACKEND=null: the core then plays to
# its silent null device at real-time pace.
# Usage: tools/smoke_app.sh [path to the .app], default the release build of `flutter build macos`.
set -u
cd "$(dirname "$0")/.."
app=${1:-"app/build/macos/Build/Products/Release/Woodshed Player.app"}
bin="$app/Contents/MacOS/Woodshed Player"
if [ ! -x "$bin" ]; then
  echo "smoke_app: $bin missing, first: cd app && flutter build macos --release"
  exit 2
fi
log=$(mktemp "${TMPDIR:-/tmp}/wp_smoke.XXXXXX")
WP_SMOKE=1 "$bin" >"$log" 2>&1
rc=$?
grep '^smoke:' "$log" || tail -20 "$log"
ok=$(grep -c '^smoke: ok$' "$log")
rm -f "$log"
if [ "$rc" -ne 0 ] || [ "$ok" -ne 1 ]; then
  echo "smoke_app: failed, exit code $rc"
  exit 1
fi
echo "smoke_app: passed, exit code 0"
