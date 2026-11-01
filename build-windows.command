#!/bin/bash
# Builds dist/Marka-Windows.zip: a folder to unzip on Windows and run build-exe.bat,
# which produces Marka-Setup.exe (see windows/README.txt).
set -euo pipefail
cd "$(dirname "$0")"
DIR="$(pwd)"
OUT="$DIR/dist/Marka"
rm -rf "$DIR/dist"
mkdir -p "$OUT/app"

# every file in the Windows package must be plain ASCII: Cyrillic got garbled there
if LC_ALL=C grep -l '[^ -~	]' app/server.py windows/* requirements.txt; then
  echo "Error: the files above contain non-ASCII characters" >&2
  exit 1
fi

echo "-> Icon .ico"
PNGS="$(mktemp -d)"
for size in 16 24 32 48 64 128 256; do
  sips -s format png -z $size $size "$DIR/marka.svg" --out "$PNGS/$size.png" >/dev/null
done
# ICO with PNG images inside (Windows Vista and later); a size byte of 0 means 256
python3 - "$PNGS" "$OUT/marka.ico" <<'PY'
import struct, sys
src, out = sys.argv[1], sys.argv[2]
sizes = [16, 24, 32, 48, 64, 128, 256]
images = [open(f"{src}/{s}.png", "rb").read() for s in sizes]
header = struct.pack("<HHH", 0, 1, len(images))
offset = 6 + 16 * len(images)
entries = b""
for s, data in zip(sizes, images):
    entries += struct.pack("<BBBBHHII", s % 256, s % 256, 0, 0, 1, 32, len(data), offset)
    offset += len(data)
with open(out, "wb") as f:
    f.write(header + entries + b"".join(images))
PY

echo "-> Files"
cp app/server.py app/index.html "$OUT/app/"
cp marka.svg requirements.txt "$OUT/"
# Windows tools expect CRLF line endings
for f in build-exe.bat build.ps1 installer.iss README.txt; do
  sed 's/$/\r/' "windows/$f" > "$OUT/$f"
done

echo "-> Archive"
(cd "$DIR/dist" && zip -qrX "Marka-Windows.zip" "Marka")
rm -rf "$OUT"
echo "Done: $DIR/dist/Marka-Windows.zip"
