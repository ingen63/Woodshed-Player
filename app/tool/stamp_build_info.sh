#!/bin/sh
# Writes the latest Git tag and the build date into the built Info.plist (#50/AK6, About dialog).
# Called by a build phase of the macOS and iOS Runner targets; Dart reads the values over «woodshed/files».
# WPGitTag stays empty without a tag (the dialog then says «no tag»); WPBuildDate is YYYY-MM-DD (UTC).
set -e
plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
[ -f "$plist" ] || { echo "warning: no Info.plist at $plist"; exit 0; }
tag=$(git -C "${SRCROOT}" describe --tags --abbrev=0 2>/dev/null || true)
date=$(date -u +%Y-%m-%d)
for entry in "WPGitTag:$tag" "WPBuildDate:$date"; do
  key=${entry%%:*}
  value=${entry#*:}
  /usr/libexec/PlistBuddy -c "Delete :$key" "$plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
done
