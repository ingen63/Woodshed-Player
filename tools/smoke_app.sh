#!/bin/sh
# #13/AK5: smoke test of the built app. Starts the app with WP_SMOKE=1: it opens its window, imports a
# sine file it generates itself into a temporary library, plays it offline (local file, no network)
# until the position has moved, pauses and quits. Passed when the app ends with exit code 0 and prints
# «smoke: ok»; nothing needs a click. Flow in app/lib/app/smoke.dart.
# Without an audio device (GitHub's runners) set WP_AUDIO_BACKEND=null: the core then plays to its
# silent null device at real-time pace.
# Usage: tools/smoke_app.sh [app], default the release build of `flutter build macos`. #60: [app] may
# also be the program of the Windows or Linux build (WoodshedPlayer.exe, woodshed-player); on Linux
# without a display run it inside xvfb-run.
# #161: [mode] «google» runs the smoke test of the Google sign-in instead (WP_SMOKE=google,
# app/lib/sync/providers/google_smoke.dart): sign-in in the «browser» of a simulated Google on 127.0.0.1,
# the token in the token store of the system (Credential Manager, libsecret, keychain), found again,
# removed on sign-out. Only loopback connections; on Linux it needs a running Secret Service.
# Usage: tools/smoke_app.sh [app [mode]]
set -u
cd "$(dirname "$0")/.." || exit 2
app=${1:-"app/build/macos/Build/Products/Release/Woodshed Player.app"}
mode=${2:-1}
case "$mode" in
  1 | google) ;;
  *) echo "smoke_app: unknown mode $mode (google)"; exit 2 ;;
esac
case "$app" in
  *.app | *.app/) bin="$app/Contents/MacOS/Woodshed Player" ;;
  *) bin="$app" ;;
esac
if [ ! -f "$bin" ]; then
  echo "smoke_app: $bin missing, first: cd app && flutter build macos --release (windows, linux)"
  exit 2
fi
log=$(mktemp "${TMPDIR:-/tmp}/wp_smoke.XXXXXX")
WP_SMOKE=$mode "$bin" >"$log" 2>&1
rc=$?
grep '^smoke:' "$log" || tail -20 "$log"
ok=$(tr -d '\r' <"$log" | grep -c '^smoke: ok$')
rm -f "$log"
if [ "$rc" -ne 0 ] || [ "$ok" -ne 1 ]; then
  echo "smoke_app: failed, exit code $rc"
  exit 1
fi
echo "smoke_app: passed, exit code 0"
