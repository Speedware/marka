#!/bin/bash
# Installs the dependencies and builds Marka.app in this folder.
set -euo pipefail
cd "$(dirname "$0")"
DIR="$(pwd)"
APP="$DIR/Marka.app"

echo "-> Python environment"
[ -x .venv/bin/python ] || python3 -m venv .venv
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install -q --only-binary=:all: -r requirements.txt

echo "-> App"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Marka</string>
  <key>CFBundleDisplayName</key><string>Marka</string>
  <key>CFBundleIdentifier</key><string>local.marka.converter</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>marka</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

cat > "$APP/Contents/MacOS/marka" <<SCRIPT
#!/bin/bash
cd "$DIR"
# on Apple Silicon, Finder may start the script under Rosetta, but the libraries are built for arm64
ARCH=""
[ "\$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ] && ARCH="arch -arm64"
nohup \$ARCH "$DIR/.venv/bin/python" "$DIR/app/server.py" >"$DIR/marka.log" 2>&1 &
SCRIPT
chmod +x "$APP/Contents/MacOS/marka"

echo "-> Icon"
ICONSET="$(mktemp -d)/icon.iconset"
mkdir -p "$ICONSET"
# sips renders SVG with macOS itself; PyMuPDF does not support gradients and fills them black
for size in 16 32 128 256 512; do
  sips -s format png -z $size $size "$DIR/marka.svg" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -s format png -z $((size * 2)) $((size * 2)) "$DIR/marka.svg" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/icon.icns"
touch "$APP"

echo "Done: $APP"
echo "Drag Marka into the Dock or the Applications folder and launch it with a click."
