#!/bin/bash
# Builds the MP3 encoder library of the export (#141) from its source: LAME (LGPL-2.0-or-later), loaded
# by the app at run time only (dlopen), never linked statically (CLAUDE.md, licences). Nothing of it is
# checked in; CI and `make lame` run this script.
#
#   macOS: universal libmp3lame.dylib (arm64 and x86_64, macOS 14), install name @rpath/libmp3lame.dylib
#   Linux: libmp3lame.so for the core tests
#
# Usage: tools/build-lame.sh [out-dir]   (default: local/lame)
# Prints the path of the library. A finished build in out-dir is reused.
set -euo pipefail

VERSION=3.100
URL="https://downloads.sourceforge.net/project/lame/lame/${VERSION}/lame-${VERSION}.tar.gz"
SHA256=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/local/lame}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

case "$(uname -s)" in
Darwin) lib="$out/libmp3lame.dylib" ;;
*) lib="$out/libmp3lame.so" ;;
esac
if [ -f "$lib" ] && [ -f "$out/VERSION" ] && [ "$(cat "$out/VERSION")" = "$VERSION" ]; then
  echo "$lib"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tarball="$work/lame-${VERSION}.tar.gz"
curl -fsSL --retry 3 -o "$tarball" "$URL"
actual="$(shasum -a 256 "$tarball" | cut -d' ' -f1)"
if [ "$actual" != "$SHA256" ]; then
  echo "build-lame: checksum mismatch: $actual" >&2
  exit 1
fi
tar -xzf "$tarball" -C "$work"
src="$work/lame-${VERSION}"
# LAME 3.100 exports a symbol it does not define; the macOS linker refuses it.
sed -i.bak '/lame_init_old/d' "$src/include/libmp3lame.sym"

build() { # build <dir> <extra configure args> <CFLAGS>
  local dir="$1" args="$2" cflags="$3"
  mkdir -p "$dir"
  (cd "$dir" && CFLAGS="-O2 $cflags" LDFLAGS="$cflags" "$src/configure" --quiet \
    --disable-static --enable-shared --disable-frontend \
    --disable-dependency-tracking --disable-gtktest $args >/dev/null &&
    make -s -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)" >/dev/null)
}

if [ "$(uname -s)" = Darwin ]; then
  min=-mmacosx-version-min=14.0
  build "$work/arm64" "--host=aarch64-apple-darwin" "-arch arm64 $min"
  build "$work/x86_64" "--host=x86_64-apple-darwin" "-arch x86_64 $min"
  lipo -create \
    "$work/arm64/libmp3lame/.libs/libmp3lame.0.dylib" \
    "$work/x86_64/libmp3lame/.libs/libmp3lame.0.dylib" \
    -output "$lib"
  install_name_tool -id @rpath/libmp3lame.dylib "$lib"
else
  build "$work/native" "" "-fPIC"
  cp "$work/native/libmp3lame/.libs/libmp3lame.so.0.0.0" "$lib"
fi
cp "$src/COPYING" "$out/COPYING"
echo "$VERSION" >"$out/VERSION"
echo "$lib"
