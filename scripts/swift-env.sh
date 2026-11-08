#!/bin/bash
# Keep build caches inside the project, including on restricted developer hosts.
STATUSDECK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="$STATUSDECK_ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
deck_swift() {
  swift "$1" --disable-sandbox --cache-path "$STATUSDECK_ROOT/.build/cache" --config-path "$STATUSDECK_ROOT/.build/config" --security-path "$STATUSDECK_ROOT/.build/security" "${@:2}"
}
