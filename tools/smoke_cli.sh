#!/bin/sh
# #140, #60: smoke test of the command line of the built Windows or Linux app (the Mac's is checked by
# hand, #140/AK16). With no app running, the first command starts the app and waits for its socket;
# the next ones reach the running app:
#   help                      -> the help, exit code 0 (no app needed)
#   play --title <missing>    -> starts the app; it answers «No title ... in the library.», exit code 1
#   play --title <missing>    -> the running app answers the same
#   record                    -> «Recording is not supported on this platform.», exit code 1 (#162)
# Nothing in the library changes. The app is ended at the close. On Linux without a display run it
# inside xvfb-run; without an audio device set WP_AUDIO_BACKEND=null.
# Usage: tools/smoke_cli.sh <program>  (WoodshedPlayer.com on Windows, woodshed-player on Linux)
set -u
prog=${1:?usage: tools/smoke_cli.sh <program>}
if [ ! -f "$prog" ]; then
  echo "smoke_cli: $prog missing, first: cd app && flutter build windows (linux) --release"
  exit 2
fi
failed=0
out=$(mktemp "${TMPDIR:-/tmp}/wp_cli_out.XXXXXX")
err=$(mktemp "${TMPDIR:-/tmp}/wp_cli_err.XXXXXX")

# expect <name> <exit code> <text in stdout or stderr> <arguments...>
expect() {
  name=$1 code=$2 text=$3
  shift 3
  "$prog" "$@" >"$out" 2>"$err"
  rc=$?
  if [ "$rc" -eq "$code" ] && cat "$out" "$err" | tr -d '\r' | grep -qF "$text"; then
    echo "smoke_cli: ok   $name (exit code $rc)"
  else
    echo "smoke_cli: FAIL $name: exit code $rc (expected $code), output:"
    cat "$out" "$err"
    failed=1
  fi
}

expect help 0 'play' help
expect "play starts the app" 1 'No title "Smoke CLI missing" in the library.' \
  play --title "Smoke CLI missing"
expect "play reaches the running app" 1 'No title "Smoke CLI missing" in the library.' \
  play --title "Smoke CLI missing"
expect "record is not supported" 1 'Recording is not supported on this platform.' record

# end the app the command started
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) taskkill //IM WoodshedPlayer.exe //F >/dev/null 2>&1 ;;
  # by process name: the command line of this script names the program too
  *) pkill -x "$(basename "$prog")" >/dev/null 2>&1 || true ;;
esac
rm -f "$out" "$err"
if [ "$failed" -ne 0 ]; then
  echo "smoke_cli: failed"
  exit 1
fi
echo "smoke_cli: passed"
