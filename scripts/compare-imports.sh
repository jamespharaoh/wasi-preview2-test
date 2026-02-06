#!/usr/bin/env bash
# Compare WASM imports between wasm32-wasip1 and wasm32-wasip2 components.
# Shows whether fd_close is present in each build.
#
# Note: The P2 component must be built with Rust 1.93.0 to show the bug.
# Use ./scripts/reproduce.sh for the full comparison across Rust versions.
#
# Usage: ./scripts/compare-imports.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

P1_WASM="target/wasm32-wasip1/release/wasi-component-p1.wasm"
P2_WASM="target/wasm32-wasip2/release/wasi-component.wasm"

# Build if needed
if [ ! -f "$P1_WASM" ] || [ ! -f "$P2_WASM" ]; then
    echo "Building components..."
    cargo build --release --package wasi-component-p1 --target wasm32-wasip1 --quiet
    cargo build --release --package wasi-component    --target wasm32-wasip2 --quiet
    echo ""
fi

# Dump disassembly, filter to import lines only
P1_IMPORTS="$(mktemp)"
P2_IMPORTS="$(mktemp)"
trap 'rm -f "$P1_IMPORTS" "$P2_IMPORTS"' EXIT

wasm-tools print "$P1_WASM" | grep '(import ' > "$P1_IMPORTS" || true
wasm-tools print "$P2_WASM" | grep '(import ' > "$P2_IMPORTS" || true

echo "=========================================="
echo "WASM Import Comparison: P1 vs P2"
echo "=========================================="

check() {
    local label="$1" file="$2" pattern="$3"
    if grep -q "$pattern" "$file"; then
        echo -e "  $label: ${GREEN}present${NC}"
    else
        echo -e "  $label: ${RED}MISSING${NC}"
    fi
}

echo ""
echo "Preview 1 (wasm32-wasip1):"
check "path_open" "$P1_IMPORTS" "path_open"
check "fd_read"   "$P1_IMPORTS" "fd_read"
check "fd_close"  "$P1_IMPORTS" "fd_close"

echo ""
echo "Preview 2 (wasm32-wasip2):"
check "path_open" "$P2_IMPORTS" "path_open"
check "fd_read"   "$P2_IMPORTS" "fd_read"
check "fd_close"  "$P2_IMPORTS" "fd_close"
echo ""
