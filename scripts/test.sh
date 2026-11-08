#!/bin/bash
# Runs the tests. Swift Testing ships with the Command Line Tools but outside the
# default search path, so without full Xcode it has to be pointed at explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh

package="$STATUSDECK_ROOT"
scratch="$STATUSDECK_ROOT/.build/tests"
if [[ "${1:-}" == --mos ]]; then
  package="$STATUSDECK_ROOT/Extensions/MosPlugin"
  scratch="$STATUSDECK_ROOT/.build/mos-tests"
  shift
fi

flags=()
if ! xcode-select -p | grep -q Xcode.app; then
  TOOLS="$(xcode-select -p)"
  FW="$TOOLS/Library/Developer/Frameworks"
  # Testing.framework depends on lib_TestingInterop.dylib, kept in a separate folder.
  INTEROP="$TOOLS/Library/Developer/usr/lib"
  flags=(-Xswiftc -F -Xswiftc "$FW" -Xlinker -F -Xlinker "$FW" -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$INTEROP")
fi
deck_swift test --package-path "$package" --scratch-path "$scratch" -j 4 --disable-xctest --enable-swift-testing "${flags[@]}" "$@"
