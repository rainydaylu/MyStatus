#!/bin/bash
# Builds build/MyStatus.app from source. Needs only the Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh
case "${1:-}" in
    "") STATUSDECK_LAUNCH=true ;;
    --no-launch) STATUSDECK_LAUNCH=false ;;
    *) echo "Usage: $0 [--no-launch]" >&2; exit 2 ;;
esac

deck_swift build -c release -j 4
BIN_DIR="$(deck_swift build -c release -j 4 --show-bin-path)"

mkdir -p build
STATUSDECK_PACKAGE_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/StatusDeck-package.XXXXXX")"
trap 'rm -rf "$STATUSDECK_PACKAGE_STAGE"' EXIT
APP="$STATUSDECK_PACKAGE_STAGE/MyStatus.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/StatusDeck" "$APP/Contents/MacOS/mystatus"
swiftc -O -target "$(uname -m)-apple-macos13.0" -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
    Sources/StatusDeckFanHelper/SMC.swift Sources/StatusDeckFanHelper/main.swift \
    -o "$APP/Contents/MacOS/mystatus-fan-helper"
codesign --force --sign - --identifier local.statusdeck.fan-helper "$APP/Contents/MacOS/mystatus-fan-helper"
cp "$BIN_DIR/libStatusDeckKit.dylib" "$APP/Contents/Frameworks/"
cp Support/Info.plist "$APP/Contents/Info.plist"
STATUSDECK_PREVIEW_FLAG="$(/usr/libexec/PlistBuddy -c 'Print :StatusDeckPreview' "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ "$STATUSDECK_PREVIEW_FLAG" = true ]; then
    echo "Release packaging refused: StatusDeckPreview disables real controls."
    exit 1
fi
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R LICENSES THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"

# Plugins and the app share the one library in Frameworks, found through this path.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/mystatus"
# Drop linker debug maps with absolute build paths from the distributed binaries.
/usr/bin/strip -S "$APP/Contents/MacOS/mystatus" "$APP/Contents/Frameworks/libStatusDeckKit.dylib"

# An ad-hoc signature is enough to run on this Mac. By default macOS would tie
# permissions to the exact build, asking again after every rebuild, so the designated
# requirement names the identifier instead. That is weaker than a real certificate,
# which this project does not have: another local app claiming this identifier would
# inherit the permissions. No hardened runtime, because that would stop the app from
# loading third-party plugins signed by anyone else.
xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/Frameworks/libStatusDeckKit.dylib"
codesign --force --sign - --identifier local.statusdeck.app \
    -r='designated => identifier "local.statusdeck.app"' "$APP"



# Distributable libraries, without any standalone application or duplicate SDK.
mkdir -p "$APP/Contents/Resources/BundledPlugins" "$APP/Contents/Resources/ExtensionSources" "$APP/Contents/Resources/Packages"
for EXTENSION in HangingClipboardPlugin MosPlugin CodeIslandPlugin; do
    scripts/build-plugin.sh "Extensions/$EXTENSION"
    cp -R "build/plugins/$EXTENSION.deckplugin" "$APP/Contents/Resources/BundledPlugins/"
    rsync -a --exclude=.build --exclude=.git "Extensions/$EXTENSION/" "$APP/Contents/Resources/ExtensionSources/$EXTENSION/"
done
rsync -a --exclude=.build --exclude=.git Packages/StatusDeckKit/ "$APP/Contents/Resources/Packages/StatusDeckKit/"
xattr -cr "$APP"
codesign --force --sign - --identifier local.statusdeck.app -r='designated => identifier "local.statusdeck.app"' "$APP"

codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCHIVE="build/MyStatus-$VERSION.zip"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$STATUSDECK_PACKAGE_STAGE/release.zip"
mv -f "$STATUSDECK_PACKAGE_STAGE/release.zip" "$ARCHIVE"
rm -rf build/MyStatus.app
ditto --norsrc --noextattr "$APP" build/MyStatus.app
echo "Built $PWD/$ARCHIVE"
if ! codesign --verify --deep --strict build/MyStatus.app; then
    echo "The copied app failed signature verification. Extract $ARCHIVE in a local folder and open that copy." >&2
    if [ "$STATUSDECK_LAUNCH" = true ]; then exit 1; fi
    exit 0
fi
echo "Built $PWD/build/MyStatus.app"
if [ "$STATUSDECK_LAUNCH" = true ]; then
    /usr/bin/open -n "$PWD/build/MyStatus.app" --args --replace-running-instance --open-settings
fi
