#!/bin/bash
# Builds OpenMessage.app WITH the desktop widget extension embedded.
#
# Unlike build.sh (SwiftPM only), this uses an xcodegen-generated Xcode project
# so it can produce the WidgetKit app-extension. The app is built unsigned, then
# ad-hoc signed inner-to-outer (Go binary → widget .appex → app) the same way
# build.sh signs for local use. App Group sharing needs a real provisioning
# profile to function, but the widget falls back to reading the backend over
# localhost, so ad-hoc local builds work fine.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
# Xcode target / executable name (kept stable so signing + bundle ids don't
# churn); the user-facing bundle is named GoogleRCS.app.
APP_NAME="OpenMessage"
PRODUCT_NAME="Android Message for Mac"
SYM="$BUILD_DIR/sym/Release"
APP_BUNDLE="$BUILD_DIR/$PRODUCT_NAME.app"

VERSION="${VERSION:-$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null || echo dev)}"
echo "==> Version: $VERSION"

echo "==> Building Go universal backend..."
GO_LDFLAGS="-s -w -X main.version=${VERSION}"
mkdir -p "$BUILD_DIR"
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -C "$ROOT_DIR" -trimpath -ldflags="${GO_LDFLAGS}" -o "$BUILD_DIR/openmessage-arm64" .
CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -C "$ROOT_DIR" -trimpath -ldflags="${GO_LDFLAGS}" -o "$BUILD_DIR/openmessage-amd64" .
lipo -create -output "$BUILD_DIR/openmessage" "$BUILD_DIR/openmessage-arm64" "$BUILD_DIR/openmessage-amd64"
echo "   Universal binary: $(du -h "$BUILD_DIR/openmessage" | cut -f1)"

echo "==> Generating Xcode project..."
cd "$SCRIPT_DIR"
xcodegen generate >/dev/null

echo "==> Building app + widget (unsigned)..."
rm -rf "$BUILD_DIR/sym"
xcodebuild -project OpenMessage.xcodeproj -target "$APP_NAME" -configuration Release \
    SYMROOT="$BUILD_DIR/sym" CODE_SIGNING_ALLOWED=NO >/tmp/om-xcodebuild.log 2>&1 \
    || { echo "xcodebuild failed:"; tail -40 /tmp/om-xcodebuild.log; exit 1; }

echo "==> Assembling bundle..."
rm -rf "$APP_BUNDLE"
cp -R "$SYM/$APP_NAME.app" "$APP_BUNDLE"

# Embed the Go backend the Swift app spawns at runtime.
cp "$BUILD_DIR/openmessage" "$APP_BUNDLE/Contents/Resources/openmessage"
chmod +x "$APP_BUNDLE/Contents/Resources/openmessage"

echo "==> Ad-hoc signing (inner → outer)..."
APPEX="$APP_BUNDLE/Contents/PlugIns/MessagesWidget.appex"
codesign --force --options runtime --entitlements "$SCRIPT_DIR/OpenMessage.entitlements" \
    --sign - "$APP_BUNDLE/Contents/Resources/openmessage"
codesign --force --options runtime --entitlements "$SCRIPT_DIR/Widget/Widget.entitlements" \
    --sign - "$APPEX"
codesign --force --options runtime --entitlements "$SCRIPT_DIR/OpenMessage.entitlements" \
    --sign - "$APP_BUNDLE"

xattr -cr "$APP_BUNDLE"

echo "==> Verifying signatures..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1 | tail -3

echo ""
echo "==> Built: $APP_BUNDLE"
echo "To install: cp -R \"$APP_BUNDLE\" /Applications/ && xattr -cr /Applications/OpenMessage.app"
echo "Then launch it once, pair your phone, and add the 'Messages' widget to your desktop."
