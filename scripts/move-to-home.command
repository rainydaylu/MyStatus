#!/bin/bash
set -euo pipefail
STATUSDECK_SOURCE="$(cd "$(dirname "$0")/.." && pwd)"
STATUSDECK_DESTINATION="$HOME/mystatus"
if [ "$STATUSDECK_SOURCE" = "$STATUSDECK_DESTINATION" ]; then
    echo "Already in $STATUSDECK_DESTINATION"
    exit 0
fi
if [ -e "$STATUSDECK_DESTINATION" ]; then
    echo "Destination already exists: $STATUSDECK_DESTINATION"
    echo "No files were changed. Rename the existing folder and run this again."
    exit 1
fi
mkdir -p "$STATUSDECK_DESTINATION"
rsync -a --exclude=.build --exclude=build "$STATUSDECK_SOURCE/" "$STATUSDECK_DESTINATION/"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$STATUSDECK_SOURCE/Support/Info.plist")"
ARCHIVE="$STATUSDECK_SOURCE/build/MyStatus-$VERSION.zip"
if [ -f "$ARCHIVE" ]; then
    mkdir -p "$STATUSDECK_DESTINATION/build"
    ditto -x -k "$ARCHIVE" "$STATUSDECK_DESTINATION/build"
fi
echo "Source and app copied to $STATUSDECK_DESTINATION"
open -R "$STATUSDECK_DESTINATION/Package.swift"
