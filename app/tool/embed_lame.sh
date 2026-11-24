#!/bin/sh
# #141: copies the MP3 encoder LAME (LGPL, built by tools/build-lame.sh into local/lame) into
# Woodshed Player.app/Contents/Frameworks and signs it with the app's identity. Called by a build phase
# of the macOS Runner target. The core loads it only for the export (dlopen); without it the app runs
# and the export says that MP3 is not available. WP_LAME_DIR replaces local/lame.
set -e
dir="${WP_LAME_DIR:-${SRCROOT}/../../local/lame}"
lib="$dir/libmp3lame.dylib"
if [ ! -f "$lib" ]; then
  echo "warning: no LAME at $lib (tools/build-lame.sh): the MP3 export is not available in this build"
  exit 0
fi
dest="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
mkdir -p "$dest"
cp -f "$lib" "$dest/libmp3lame.dylib"
if [ "${CODE_SIGNING_ALLOWED}" != "NO" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY}" ]; then
  stamp=--timestamp=none
  [ "${EXPANDED_CODE_SIGN_IDENTITY}" = "-" ] || [ "${CONFIGURATION}" = "Debug" ] || stamp=--timestamp
  codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" $stamp "$dest/libmp3lame.dylib"
fi
