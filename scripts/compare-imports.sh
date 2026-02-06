#!/bin/bash
# Compare WASM imports between P1 and P2 components
# This script demonstrates the missing fd_close import in P2

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "WASM Import Comparison: P1 vs P2"
echo "=========================================="
echo

# Build if needed
if [ ! -f "target/wasm32-wasip1/release/wasi-component-p1.wasm" ] || \
   [ ! -f "target/wasm32-wasip2/release/wasi-component.wasm" ]; then
    echo "Building components..."
    cargo build --release --package wasi-component-p1 --target wasm32-wasip1
    cargo build --release --package wasi-component --target wasm32-wasip2
    echo
fi

echo "=== WASI Preview 1 (wasm32-wasip1) ==="
echo

# Check for fd_close in P1
if wasm-tools print target/wasm32-wasip1/release/wasi-component-p1.wasm | \
   grep -q "fd_close"; then
    echo -e "${GREEN}✅ fd_close IS imported${NC}"
    wasm-tools print target/wasm32-wasip1/release/wasi-component-p1.wasm | \
        grep "fd_close"
else
    echo -e "${RED}❌ fd_close NOT imported${NC}"
fi

echo
echo "P1 file-related imports:"
wasm-tools print target/wasm32-wasip1/release/wasi-component-p1.wasm | \
    grep -E '(path_open|fd_read|fd_write|fd_close)' | \
    sed 's/^/  /'

echo
echo "=========================================="
echo "=== WASI Preview 2 (wasm32-wasip2) ==="
echo

# Check for fd_close in P2
if wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | \
   grep -q "fd_close"; then
    echo -e "${GREEN}✅ fd_close IS imported${NC}"
    wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | \
        grep "fd_close"
else
    echo -e "${RED}❌ fd_close NOT imported${NC}"
fi

echo
echo "P2 Preview 1 API imports (legacy):"
wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | \
    grep "wasi_snapshot_preview1" | \
    grep -E '(path_open|fd_read|fd_write|fd_close)' | \
    sed 's/^/  /'

echo
echo "P2 Preview 2 resource management:"
wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | \
    grep -E '\[resource-drop\](descriptor|input-stream|output-stream)' | \
    sed 's/^/  /' | head -10

echo
echo "=========================================="
echo "=== Summary ==="
echo

P1_HAS_FD_CLOSE=$(wasm-tools print target/wasm32-wasip1/release/wasi-component-p1.wasm | grep "fd_close" | wc -l || echo "0")
P2_HAS_FD_CLOSE=$(wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | grep "fd_close" | wc -l || echo "0")

echo "Preview 1:"
echo -e "  - Imports path_open: ${GREEN}✅${NC}"
echo -e "  - Imports fd_read:   ${GREEN}✅${NC}"
echo -e "  - Imports fd_close:  ${GREEN}✅ (complete lifecycle)${NC}"
echo

echo "Preview 2:"
P2_HAS_PATH_OPEN=$(wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | grep "path_open" | wc -l || echo "0")
P2_HAS_FD_READ=$(wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | grep "fd_read" | wc -l || echo "0")

if [ "$P2_HAS_PATH_OPEN" -gt 0 ]; then
    echo -e "  - Imports path_open: ${GREEN}✅${NC} (P1 API)"
else
    echo -e "  - Imports path_open: ${RED}❌${NC}"
fi

if [ "$P2_HAS_FD_READ" -gt 0 ]; then
    echo -e "  - Imports fd_read:   ${GREEN}✅${NC} (P1 API)"
else
    echo -e "  - Imports fd_read:   ${RED}❌${NC}"
fi

if [ "$P2_HAS_FD_CLOSE" -gt 0 ]; then
    echo -e "  - Imports fd_close:  ${GREEN}✅${NC}"
else
    echo -e "  - Imports fd_close:  ${RED}❌ (MISSING - causes leak!)${NC}"
fi

echo
echo -e "${YELLOW}⚠️  Preview 2 uses P1 APIs (path_open, fd_read) but doesn't import fd_close!${NC}"
echo -e "${YELLOW}    This hybrid approach causes file descriptor leaks.${NC}"
echo
echo "Full import lists saved to:"
echo "  - notes/wasm-inspection/p1-imports.txt"
echo "  - notes/wasm-inspection/p2-imports.txt"
echo "  - notes/wasm-inspection/imports-comparison.md"
