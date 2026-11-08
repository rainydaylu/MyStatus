#!/bin/bash
# Builds a plugin package into build/plugins/<name>.deckplugin.
# Usage: scripts/build-plugin.sh Examples/KeepAwakePlugin
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$(cd "$1" && pwd)"
NAME="$(basename "$PACKAGE")"
source "$ROOT/scripts/swift-env.sh"

cd "$PACKAGE"
deck_swift build -c release -j 4 --scratch-path "$ROOT/.build/$NAME"
BIN_DIR="$(deck_swift build -c release -j 4 --scratch-path "$ROOT/.build/$NAME" --show-bin-path)"

OUT="$ROOT/build/plugins/$NAME.deckplugin"
rm -rf "$OUT"
mkdir -p "$OUT"
cp plugin.json "$OUT/"
LIBRARY="$(python3 -I -c "import json; print(json.load(open('plugin.json'))['library'])")"
cp "$BIN_DIR/$LIBRARY" "$OUT/$LIBRARY"
for RESOURCE in "$BIN_DIR"/*.bundle; do
    [ ! -d "$RESOURCE" ] || cp -R "$RESOURCE" "$OUT/"
done
for NOTE in LICENSE upstream.json; do
    [ ! -f "$PACKAGE/$NOTE" ] || cp "$PACKAGE/$NOTE" "$OUT/"
done

# The library must resolve StatusDeckKit to the copy inside the running app.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$OUT/$LIBRARY"
/usr/bin/strip -S "$OUT/$LIBRARY"
xattr -cr "$OUT"
codesign --force --sign - "$OUT/$LIBRARY"

echo "Built $OUT"
echo "Install it by copying the folder into:"
echo "  ~/Library/Application Support/StatusDeck/Plugins/"
