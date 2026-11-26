#!/bin/bash
# #99/AK2: runs the smoke test with the real core (app/integration_test/app_smoke_test.dart) on an
# iOS simulator. The simulator is WP_IOS_DEVICE (name or UDID); unset, a booted iPhone or else the
# first available one. A simulator this script boots is shut down again afterwards, a booted one stays.
# Without an audio device (GitHub's macOS runners) set WP_AUDIO_BACKEND=null: it reaches the app in the
# simulator as SIMCTL_CHILD_WP_AUDIO_BACKEND (simctl passes SIMCTL_CHILD_* on without the prefix), so
# the core plays to miniaudio's silent null device as on macOS.
# #155: a run that hangs stops after WP_IOS_TEST_LIMIT seconds (default 600, counted from the start of
# this script, below the 15 minutes of the CI step) with an error; before that, the script prints the
# simulator's state (app installed, app running), the processes of the hanging `flutter test` and the
# system log of the app process. In CI (CI=true) `flutter test` runs with -v.
# Usage: tools/ios_sim_test.sh [flutter test options], e.g. --reporter expanded
set -u
cd "$(dirname "$0")/.."

limit=${WP_IOS_TEST_LIMIT:-600}
bundle=ch.woodshed-player-app.ios

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

# A diagnostic command must not hang the script itself: it is killed after $1 seconds.
bounded() {
  local s=$1
  shift
  perl -e 'alarm shift; exec @ARGV or die "exec: $!\n"' "$s" "$@"
}

# #155/AK2: what the simulator and the app were doing when the run hung.
diagnose() {
  echo "ios_sim_test: --- simulator state"
  bounded 30 xcrun simctl list devices | grep -F "$udid"
  local container
  if container=$(bounded 30 xcrun simctl get_app_container "$udid" "$bundle" app 2>&1); then
    echo "ios_sim_test: app installed: $container"
  else
    echo "ios_sim_test: app not installed ($container)"
  fi
  local running
  running=$(bounded 30 xcrun simctl spawn "$udid" launchctl list | grep -F "$bundle")
  echo "ios_sim_test: app running: ${running:-no}"
  echo "ios_sim_test: --- processes of flutter test"
  local pids
  pids=$(pgrep -g "$1" | paste -sd, -)
  [ -n "$pids" ] && ps -o pid,ppid,etime,command -p "$pids"
  echo "ios_sim_test: --- system log of the app process (last $((limit / 60 + 1)) min)"
  bounded 90 xcrun simctl spawn "$udid" log show --style compact --last "$((limit / 60 + 1))m" \
    --predicate "process == \"Runner\" OR (eventMessage CONTAINS \"$bundle\" AND NOT eventMessage CONTAINS \"category map\")" |
    tail -n 400
  echo "ios_sim_test: --- crash reports of the app"
  find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -iname '*runner*' -mmin "-$((limit / 60 + 1))" 2>/dev/null
}

verbose=()
[ "${CI:-}" = true ] && verbose=(-v)

# Own process group (job control), so a hanging run can be stopped with every process it started.
set -m
(cd app && exec flutter test integration_test/app_smoke_test.dart -d "$udid" ${verbose[@]+"${verbose[@]}"} "$@") &
pid=$!
while kill -0 "$pid" 2>/dev/null; do
  if [ "$SECONDS" -ge "$limit" ]; then
    echo "ios_sim_test: the smoke test did not finish within $limit s (WP_IOS_TEST_LIMIT, #155)" >&2
    diagnose "$pid"
    kill -TERM -- -"$pid" 2>/dev/null
    sleep 5
    kill -KILL -- -"$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    exit 124
  fi
  sleep 1
done
wait "$pid"
