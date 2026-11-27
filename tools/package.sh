#!/bin/bash
# #139: installation packages of a release, used by .github/workflows/release.yml and by hand.
#
#   tools/package.sh name <platform> <tag>               file name of the package, e.g. WoodshedPlayer-0.9.0-macos.dmg
#   tools/package.sh macos <tag> <out-dir> [app]         .dmg from the built app (default: release build of
#                                                       `flutter build macos --release`)
#   tools/package.sh web <tag> <out-dir> [build-dir]     .zip from the built web app (default: app/build/web)
#   tools/package.sh windows <tag> <out-dir> [build-dir] .zip from `flutter build windows --release` (#60)
#   tools/package.sh linux <tag> <out-dir> [bundle]      .tar.gz from `flutter build linux --release` (#60)
#
# Before packing, the build is checked: the version in the app equals the tag's version and the tag stamped
# into it is the tag (#139/AK4, «About Woodshed Player»); on macOS every binary is universal (arm64 and
# x86_64) and the ad hoc signature is valid. Each package carries LICENSE and the licence texts of fonts and
# core libraries (#139/AK3, #119) in a folder «Licenses» (macOS) or «licenses» (web). The app is not notarised
# (no Apple developer account); README «Installation» says how to open it the first time.
# #60: Windows and Linux are x64 only; the package holds the folder «WoodshedPlayer» with the program, the
# core library, the command line (WoodshedPlayer.com on Windows) and «licenses»; on Linux also
# licenses/SYSTEM-LIBRARIES.txt (GTK and the audio libraries of the system, LGPL, not in the package).
# WP_LAME_REQUIRED=1 (CI) fails the macOS package when the app carries no LAME (MP3 export, #141).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="WoodshedPlayer"

die() {
  echo "package: $*" >&2
  exit 1
}

version_of() {
  [[ "$1" =~ ^v([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?)$ ]] || die "tag '$1' is not vX.Y.Z"
  echo "${BASH_REMATCH[1]}"
}

file_name() {
  local version
  version=$(version_of "$2")
  case "$1" in
  macos) echo "$APP_NAME-$version-macos.dmg" ;;
  web) echo "$APP_NAME-$version-web.zip" ;;
  windows) echo "$APP_NAME-$version-windows.zip" ;;
  linux) echo "$APP_NAME-$version-linux.tar.gz" ;;
  *) die "unknown platform '$1' (macos, web, windows, linux)" ;;
  esac
}

# Licence texts into $1: the app's MIT licence, the fonts (SIL OFL 1.1) and the core libraries (#119);
# LAME only with $2 = with-lame (it is in the Mac app only, #141).
copy_licenses() {
  local dest=$1 lame=$2 dir name
  mkdir -p "$dest/fonts" "$dest/core"
  cp "$root/LICENSE" "$dest/LICENSE"
  cp "$root/app/assets/fonts/README.md" "$dest/fonts/README.md"
  for dir in "$root"/app/assets/fonts/*/; do
    name=$(basename "$dir")
    mkdir -p "$dest/fonts/$name"
    cp "$dir/OFL.txt" "$dest/fonts/$name/OFL.txt"
  done
  cp "$root/app/assets/licenses/README.md" "$dest/core/README.md"
  for dir in "$root"/app/assets/licenses/*/; do
    name=$(basename "$dir")
    [ "$name" != lame ] || [ "$lame" = with-lame ] || continue
    cp -R "$dir" "$dest/core/$name"
  done
}

package_macos() {
  local tag=$1 out=$2 app=${3:-"$root/app/build/macos/Build/Products/Release/Woodshed Player.app"}
  local version plist value stage dmg lame=without-lame
  version=$(version_of "$tag")
  [ -d "$app" ] || die "$app missing, first: cd app && flutter build macos --release"
  plist="$app/Contents/Info.plist"
  value=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
  # Flutter keeps only digits and dots in the version of an Apple app: 1.0.0-beta.1 becomes 1.0.0.1
  [ "$value" = "$(printf %s "$version" | tr -cd '0-9.')" ] || die "macos: app version $value, tag $tag"
  value=$(/usr/libexec/PlistBuddy -c 'Print :WPGitTag' "$plist" 2>/dev/null || true)
  [ "$value" = "$tag" ] || die "macos: tag in the app '$value', expected $tag (git describe of the build)"
  # every Mach-O file of the bundle for both architectures
  while IFS= read -r -d '' file; do
    file -b "$file" | grep -q '^Mach-O' || continue
    archs=$(lipo -archs "$file")
    [[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]] || die "macos: not universal ($archs): ${file#"$app"/}"
  done < <(find "$app/Contents" -type f -print0)
  codesign --verify --deep --strict "$app" || die "macos: signature of the app is not valid"
  if [ -f "$app/Contents/Frameworks/libmp3lame.dylib" ]; then
    lame=with-lame
  elif [ "${WP_LAME_REQUIRED:-}" = 1 ]; then
    die "macos: no LAME in the app (tools/build-lame.sh), but WP_LAME_REQUIRED=1"
  fi
  mkdir -p "$out"
  stage=$(mktemp -d "${TMPDIR:-/tmp}/wp_package.XXXXXX")
  trap 'rm -rf "$stage"' RETURN
  ditto "$app" "$stage/Woodshed Player.app"
  ln -s /Applications "$stage/Applications"
  copy_licenses "$stage/Licenses" "$lame"
  dmg="$out/$(file_name macos "$tag")"
  rm -f "$dmg"
  hdiutil create -quiet -volname "Woodshed Player $version" -srcfolder "$stage" -fs HFS+ -format UDZO "$dmg"
  hdiutil verify -quiet "$dmg"
  echo "$dmg"
}

package_web() {
  local tag=$1 out=$2 build=${3:-"$root/app/build/web"}
  local version name stage zip
  version=$(version_of "$tag")
  [ -f "$build/index.html" ] || die "$build/index.html missing, first: cd app && flutter build web --release"
  # WP_GIT_TAG of the build (--dart-define) ends up as a string in main.dart.js
  grep -qF "\"$tag\"" "$build/main.dart.js" || die "web: tag $tag not in main.dart.js (--dart-define=WP_GIT_TAG)"
  grep -qF "\"$version\"" "$build/main.dart.js" || die "web: version $version not in main.dart.js"
  mkdir -p "$out"
  out="$(cd "$out" && pwd)"
  name="$APP_NAME-$version-web"
  stage=$(mktemp -d "${TMPDIR:-/tmp}/wp_package.XXXXXX")
  trap 'rm -rf "$stage"' RETURN
  cp -R "$build" "$stage/$name"
  copy_licenses "$stage/$name/licenses" without-lame
  zip="$out/$(file_name web "$tag")"
  rm -f "$zip"
  (cd "$stage" && zip -qr -X "$zip" "$name" -x "*.DS_Store" "*/.last_build_id")
  echo "$zip"
}

# #60: the version (in the Dart code of the app) and the tag (stamped into the program by CMake) of a
# Windows or Linux build; $1 platform, $2 tag, $3 program, $4 AOT library of the Dart code.
check_stamps() {
  local platform=$1 tag=$2 program=$3 aot=$4 version
  version=$(version_of "$tag")
  [ -f "$program" ] || die "$platform: $program missing"
  [ -f "$aot" ] || die "$platform: $aot missing (release build?)"
  grep -qaF "$tag" "$program" || die "$platform: tag $tag not in $(basename "$program") (git describe of the build)"
  grep -qaF "$version" "$aot" || die "$platform: version $version not in $(basename "$aot")"
}

# #60: the machine of a PE file (Windows): 8664 for x64.
pe_machine() {
  local offset
  offset=$(od -An -tu4 -j60 -N4 "$1" | tr -d ' ')
  od -An -tx2 -j"$((offset + 4))" -N2 "$1" | tr -d ' '
}

package_windows() {
  local tag=$1 out=$2 build=${3:-"$root/app/build/windows/x64/runner/Release"}
  local version name stage zip file
  version=$(version_of "$tag")
  [ -d "$build" ] || die "$build missing, first: cd app && flutter build windows --release"
  check_stamps windows "$tag" "$build/$APP_NAME.exe" "$build/data/app.so"
  for file in "$APP_NAME.exe" "$APP_NAME.com" wp_core.dll flutter_windows.dll; do
    [ -f "$build/$file" ] || die "windows: $file missing in $build"
    [ "$(pe_machine "$build/$file")" = 8664 ] || die "windows: $file is not x64"
  done
  mkdir -p "$out"
  out="$(cd "$out" && pwd)"
  name="$APP_NAME"
  stage=$(mktemp -d "${TMPDIR:-/tmp}/wp_package.XXXXXX")
  trap 'rm -rf "$stage"' RETURN
  cp -R "$build" "$stage/$name"
  copy_licenses "$stage/$name/licenses" without-lame
  zip="$out/$(file_name windows "$tag")"
  rm -f "$zip"
  if command -v zip >/dev/null; then
    (cd "$stage" && zip -qr -X "$zip" "$name")
  else
    # GitHub's Windows runners have no zip in Git Bash; PowerShell packs the folder
    powershell -NoProfile -Command "Compress-Archive -Path '$(cygpath -w "$stage/$name")' -DestinationPath '$(cygpath -w "$zip")'"
  fi
  echo "$zip"
}

package_linux() {
  local tag=$1 out=$2 bundle=${3:-"$root/app/build/linux/x64/release/bundle"}
  local version name stage tgz file
  version=$(version_of "$tag")
  [ -d "$bundle" ] || die "$bundle missing, first: cd app && flutter build linux --release"
  check_stamps linux "$tag" "$bundle/woodshed-player" "$bundle/lib/libapp.so"
  for file in woodshed-player lib/libwp_core.so lib/libflutter_linux_gtk.so; do
    [ -f "$bundle/$file" ] || die "linux: $file missing in $bundle"
    file -b "$bundle/$file" | grep -q 'ELF 64-bit.*x86-64' || die "linux: $file is not x86-64"
  done
  mkdir -p "$out"
  out="$(cd "$out" && pwd)"
  name="$APP_NAME"
  stage=$(mktemp -d "${TMPDIR:-/tmp}/wp_package.XXXXXX")
  trap 'rm -rf "$stage"' RETURN
  cp -R "$bundle" "$stage/$name"
  copy_licenses "$stage/$name/licenses" without-lame
  cp "$root/app/linux/SYSTEM-LIBRARIES.txt" "$stage/$name/licenses/SYSTEM-LIBRARIES.txt"
  tgz="$out/$(file_name linux "$tag")"
  rm -f "$tgz"
  tar -C "$stage" -czf "$tgz" "$name"
  echo "$tgz"
}

case "${1:-}" in
name)
  [ $# -eq 3 ] || die "usage: tools/package.sh name <platform> <tag>"
  file_name "$2" "$3"
  ;;
macos)
  [ $# -ge 3 ] || die "usage: tools/package.sh macos <tag> <out-dir> [app]"
  package_macos "${@:2}"
  ;;
web)
  [ $# -ge 3 ] || die "usage: tools/package.sh web <tag> <out-dir> [build-dir]"
  package_web "${@:2}"
  ;;
windows)
  [ $# -ge 3 ] || die "usage: tools/package.sh windows <tag> <out-dir> [build-dir]"
  package_windows "${@:2}"
  ;;
linux)
  [ $# -ge 3 ] || die "usage: tools/package.sh linux <tag> <out-dir> [bundle]"
  package_linux "${@:2}"
  ;;
*) die "usage: tools/package.sh name|macos|web|windows|linux …" ;;
esac
