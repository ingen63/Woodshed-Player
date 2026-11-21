#!/bin/bash
# #99/AK2: runs the smoke test with the real core (app/integration_test/app_smoke_test.dart) on an
# iOS simulator. The simulator is WP_IOS_DEVICE (name or UDID); unset, a booted iPhone or else the
# first available one. A simulator this script boots is shut down again afterwards, a booted one stays.
# Without an audio device (GitHub's macOS runners) set WP_AUDIO_BACKEND=null: it reaches the app in the
# simulator as SIMCTL_CHILD_WP_AUDIO_BACKEND (simctl passes SIMCTL_CHILD_* on without the prefix), so
# the core plays to miniaudio's silent null device as on macOS.
# Usage: tools/ios_sim_test.sh [flutter test options], e.g. --reporter expanded
set -u
cd "$(dirname "$0")/.."

devices=$(xcrun simctl list devices available) || exit 2
want=${WP_IOS_DEVICE:-}
if [ -z "$want" ]; then
  line=$(printf '%s\n' "$devices" | grep -E '^ +iPhone .*\(Booted\)' | head -1)
  [ -n "$line" ] || line=$(printf '%s\n' "$devices" | grep -E '^ +iPhone ' | head -1)
else
  # exact name («iPhone 17» is not «iPhone 17e») or UDID
  line=$(printf '%s\n' "$devices" | grep -F -e " $want (" -e "($want)" | head -1)
fi
udid=$(printf '%s\n' "$line" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)
if [ -z "$udid" ]; then
  echo "ios_sim_test: no available iOS simulator${want:+ «$want»} (xcrun simctl list devices available)"
  exit 2
fi
name=$(printf '%s\n' "$line" | sed -E 's/^ +//; s/ \([0-9A-F-]{36}\).*//')

booted_here=0
if ! printf '%s\n' "$line" | grep -q '(Booted)'; then
  echo "ios_sim_test: booting $name"
  xcrun simctl boot "$udid" || exit 2
  booted_here=1
fi
shutdown() {
  if [ "$booted_here" -eq 1 ]; then
    echo "ios_sim_test: shutting $name down again"
    xcrun simctl shutdown "$udid"
  fi
}
trap shutdown EXIT
xcrun simctl bootstatus "$udid" >/dev/null || exit 2

if [ -n "${WP_AUDIO_BACKEND:-}" ]; then
  export SIMCTL_CHILD_WP_AUDIO_BACKEND="$WP_AUDIO_BACKEND"
fi
echo "ios_sim_test: $name ($udid)${WP_AUDIO_BACKEND:+, WP_AUDIO_BACKEND=$WP_AUDIO_BACKEND}"
cd app && flutter test integration_test/app_smoke_test.dart -d "$udid" "$@"
