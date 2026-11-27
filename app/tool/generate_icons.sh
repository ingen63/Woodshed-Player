#!/usr/bin/env bash
# Erzeugt die App-Icons aller Plattformen aus einer SVG-Vorlage.
#
# Aufruf (aus app/):  tool/generate_icons.sh [vorlage.svg]
# Standard-Vorlage:   assets/icons/concepts/icon_1_waveform_loop.svg
#
# Werkzeuge: rsvg-convert, Google Chrome oder magick zum Rendern, sips zum Skalieren,
# python3 für Contents.json und die Windows-.ico-Datei. Keine Flutter-Abhängigkeit.
#
# Ziele:
#   macOS    macos/Runner/Assets.xcassets/AppIcon.appiconset/   (transparente Ecken erlaubt)
#   iOS      ios/Runner/Assets.xcassets/AppIcon.appiconset/     (ohne Transparenz, Apple maskiert selbst)
#   Android  assets/icons/generated/android/                    (mipmap + Adaptive-Icon-Ebenen)
#   Windows  assets/icons/generated/windows/app_icon.ico
#   Linux    assets/icons/generated/linux/app_icon_<px>.png
#   Web      web/favicon.png, web/icons/Icon-{120,192,512}.png, Icon-maskable-{192,512}.png
#
# Android hat im Projekt noch keinen Ordner, die Dateien landen unter assets/icons/generated/.
# Windows und Linux (#60) bekommen ihre Icons zusätzlich in windows/runner/resources/ und
# linux/runner/.
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$APP_DIR/assets/icons/concepts/icon_1_waveform_loop.svg}"
BG="#121214"

if [[ ! -f "$SRC" ]]; then
  echo "Source SVG not found: $SRC" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
MASTER="$WORK/master.png"
FLAT="$WORK/flat.png"
GEN="$APP_DIR/assets/icons/generated"

# Renderer in Reihenfolge der Verlässlichkeit: rsvg-convert, Google Chrome (headless),
# magick. Der eingebaute SVG-Renderer von magick verschluckt Konturen und Transformationen.
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if command -v rsvg-convert >/dev/null 2>&1; then
  rsvg-convert -w 1024 -h 1024 "$SRC" -o "$MASTER"
elif [[ -x "$CHROME" ]]; then
  SRC_URL="file://$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"
  "$CHROME" --headless=new --no-sandbox --disable-gpu --hide-scrollbars \
    --user-data-dir="$WORK/chrome-profile" --default-background-color=00000000 \
    --window-size=1024,1024 --screenshot="$WORK/chrome.png" "$SRC_URL" >/dev/null 2>&1
  # Chrome füllt die Ecken außerhalb des Squircles weiss. Die Ecken werden transparent.
  magick "$WORK/chrome.png" -fuzz 10% -fill none \
    -draw "color 0,0 floodfill" -draw "color 1023,0 floodfill" \
    -draw "color 0,1023 floodfill" -draw "color 1023,1023 floodfill" "$MASTER"
elif command -v magick >/dev/null 2>&1; then
  echo "Warning: rsvg-convert and Chrome are missing, magick may render outlines incorrectly." >&2
  magick -background none -density 96 "$SRC" -resize 1024x1024 "$MASTER"
else
  echo "No SVG renderer found (brew install librsvg, Google Chrome or imagemagick)." >&2
  exit 1
fi

# Ohne Transparenz, für iOS und Android-Hintergrund.
magick "$MASTER" -background "$BG" -alpha remove -alpha off "$FLAT"

# resize <quelle> <pixel> <ziel>
resize() {
  sips -z "$2" "$2" "$1" --out "$3" >/dev/null
}

# --- macOS ---------------------------------------------------------------
MAC="$APP_DIR/macos/Runner/Assets.xcassets/AppIcon.appiconset"
for px in 16 32 64 128 256 512 1024; do
  resize "$MASTER" "$px" "$MAC/app_icon_$px.png"
done
echo "macOS: $MAC"

# --- iOS -----------------------------------------------------------------
IOS="$APP_DIR/ios/Runner/Assets.xcassets/AppIcon.appiconset"
python3 - "$IOS/Contents.json" > "$WORK/ios.txt" <<'PY'
import json, sys
for entry in json.load(open(sys.argv[1]))["images"]:
    points = float(entry["size"].split("x")[0])
    scale = int(entry["scale"].rstrip("x"))
    print(entry["filename"], round(points * scale))
PY
while read -r name px; do
  resize "$FLAT" "$px" "$IOS/$name"
done < "$WORK/ios.txt"
echo "iOS: $IOS"

# --- Android ---------------------------------------------------------------
AND="$GEN/android"
# density:mipmap-px:adaptive-canvas-px
for row in mdpi:48:108 hdpi:72:162 xhdpi:96:216 xxhdpi:144:324 xxxhdpi:192:432; do
  density="${row%%:*}"
  rest="${row#*:}"
  px="${rest%%:*}"
  canvas="${rest##*:}"
  inner=$(( canvas * 2 / 3 ))   # Sicherheitszone: 72 von 108 dp
  mkdir -p "$AND/mipmap-$density"
  resize "$FLAT" "$px" "$AND/mipmap-$density/ic_launcher.png"
  magick "$MASTER" -resize "${inner}x${inner}" -background none -gravity center -extent "${canvas}x${canvas}" \
    "$AND/mipmap-$density/ic_launcher_foreground.png"
  magick -size "${canvas}x${canvas}" "xc:$BG" "$AND/mipmap-$density/ic_launcher_background.png"
done
mkdir -p "$AND/mipmap-anydpi-v26"
cat > "$AND/mipmap-anydpi-v26/ic_launcher.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
XML
echo "Android: $AND (the project needs android/ from flutter create)"

# --- Windows ---------------------------------------------------------------
WIN="$GEN/windows"
mkdir -p "$WIN"
for px in 16 32 48 256; do
  resize "$MASTER" "$px" "$WORK/win-$px.png"
done
python3 - "$WIN/app_icon.ico" "$WORK" <<'PY'
import struct, sys
out, work = sys.argv[1], sys.argv[2]
sizes = [16, 32, 48, 256]
blobs = [open(f"{work}/win-{s}.png", "rb").read() for s in sizes]
header = struct.pack("<HHH", 0, 1, len(sizes))
offset = 6 + 16 * len(sizes)
entries = b""
for s, blob in zip(sizes, blobs):
    dim = 0 if s == 256 else s
    entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(blob), offset)
    offset += len(blob)
open(out, "wb").write(header + entries + b"".join(blobs))
PY
cp "$WIN/app_icon.ico" "$APP_DIR/windows/runner/resources/app_icon.ico"  # #60
echo "Windows: $WIN/app_icon.ico, windows/runner/resources/app_icon.ico"

# --- Linux -----------------------------------------------------------------
LIN="$GEN/linux"
mkdir -p "$LIN"
for px in 64 128 256 512; do
  resize "$MASTER" "$px" "$LIN/app_icon_$px.png"
done
cp "$LIN/app_icon_256.png" "$APP_DIR/linux/runner/app_icon.png"  # #60, window icon
echo "Linux: $LIN, linux/runner/app_icon.png"

# --- Web -------------------------------------------------------------------
WEB="$APP_DIR/web"
resize "$FLAT" 16 "$WEB/favicon.png"
resize "$FLAT" 192 "$WEB/icons/Icon-192.png"
resize "$FLAT" 512 "$WEB/icons/Icon-512.png"
resize "$FLAT" 120 "$WEB/icons/Icon-120.png"
# Maskable: Motiv innerhalb der Sicherheitszone (80 %), voller Hintergrund ohne Rundung.
for px in 192 512; do
  magick "$FLAT" -resize 820x820 -gravity center -background "$BG" -extent 1024x1024 \
    -resize "${px}x${px}" "$WEB/icons/Icon-maskable-$px.png"
done
echo "Web: $WEB (favicon.png, icons/)"
