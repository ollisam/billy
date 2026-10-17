#!/bin/bash
# Builds "Billy.app" into ./build
#   ./build.sh           your build (includes Sources/Billy/Invoicing if it's there)
#   ./build.sh --public  only the files git would publish -> "build/Billy Public.app"
set -euo pipefail
cd "$(dirname "$0")"

# Override with your own, e.g. BUNDLE_ID=com.yourname.Billy ./build.sh
BUNDLE_ID="${BUNDLE_ID:-app.billy.Billy}"

if [ "${1:-}" = "--public" ]; then
    # Copy exactly what's tracked or would be committed, nothing that's git-ignored.
    SRC="build/public-src"
    rm -rf "$SRC"; mkdir -p "$SRC"
    git ls-files --cached --others --exclude-standard -z | while IFS= read -r -d '' f; do
        [ -e "$f" ] || continue
        mkdir -p "$SRC/$(dirname "$f")"; cp "$f" "$SRC/$f"
    done
    swift build -c release --package-path "$SRC"
    BIN="$SRC/.build/release/Billy"
    APP="build/Billy Public.app"
else
    swift build -c release
    BIN=".build/release/Billy"
    APP="build/Billy.app"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Billy"

# The icon is drawn by scripts/make-icon.swift; regenerate it if it's missing.
[ -f Resources/Billy.icns ] || swift scripts/make-icon.swift
cp Resources/Billy.icns "$APP/Contents/Resources/Billy.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Billy</string>
    <key>CFBundleDisplayName</key><string>Billy</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>Billy</string>
    <key>CFBundleIconFile</key><string>Billy</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
