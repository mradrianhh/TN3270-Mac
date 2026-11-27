#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(< "$ROOT/VERSION")"
if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    printf 'Invalid VERSION: expected major.minor.patch, got "%s"\n' "$VERSION" >&2
    exit 1
fi
IFS=. read -r MAJOR MINOR PATCH <<< "$VERSION"
VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
RELEASES="$ROOT/releases"
ARCHIVE="$RELEASES/TN3270Mac-v$VERSION-$(uname -m).zip"
if [[ -e "$ARCHIVE" ]]; then
    printf 'Release archive already exists: %s\n' "$ARCHIVE" >&2
    exit 1
fi

swift build --package-path "$ROOT" --configuration release --product TN3270Mac
BIN_DIR="$(swift build --package-path "$ROOT" --configuration release --show-bin-path)"
APP="$BIN_DIR/TN3270Mac.app"
ICONSET="$BIN_DIR/AppIcon.iconset"

# Recreate the bundle so stale build files cannot enter the release archive.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"
cp "$BIN_DIR/TN3270Mac" "$APP/Contents/MacOS/TN3270Mac"

for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$ROOT/Resources/AppIcon.png" \
        --out "$ICONSET/icon_${SIZE}x${SIZE}.png" > /dev/null
    RETINA_SIZE=$((SIZE * 2))
    sips -z "$RETINA_SIZE" "$RETINA_SIZE" "$ROOT/Resources/AppIcon.png" \
        --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" > /dev/null
done
iconutil --convert icns "$ICONSET" --output "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TN3270Mac</string>
    <key>CFBundleIdentifier</key>
    <string>com.mradrianhh.TN3270Mac</string>
    <key>CFBundleName</key>
    <string>TN3270Mac</string>
    <key>CFBundleDisplayName</key>
    <string>TN3270Mac</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

mkdir -p "$RELEASES"
PACKAGE_DIR="$(mktemp -d "$RELEASES/.package.XXXXXX")"
trap 'rm -f "$PACKAGE_DIR/release.zip"; rmdir "$PACKAGE_DIR"' EXIT
ditto -c -k --keepParent --norsrc "$APP" "$PACKAGE_DIR/release.zip"
mv "$PACKAGE_DIR/release.zip" "$ARCHIVE"
printf '%s\n' "$VERSION" > "$ROOT/VERSION"

printf '\nBuilt app: %s\nRelease ZIP: %s\nVersion: v%s\nDrag TN3270Mac.app into Applications to install it.\n' \
    "$APP" "$ARCHIVE" "$VERSION"
