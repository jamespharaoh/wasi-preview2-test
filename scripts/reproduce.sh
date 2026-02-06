#!/usr/bin/env bash
# Reproduce the fd_close regression in Rust 1.93.0 for wasm32-wasip2.
#
# This script demonstrates that Rust 1.93.0 produces a wasm32-wasip2
# component that is missing the fd_close import, causing file descriptor
# leaks after ~100-125 file operations.
#
# Prerequisites:
#   - rustup (https://rustup.rs)
#   - wasm-tools (cargo install wasm-tools)
#   - wasmtime >= 29 (cargo install wasmtime-cli)
#
# Usage:
#   ./scripts/reproduce.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# --- Colours ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Check prerequisites ---

missing=()
command -v rustup    >/dev/null 2>&1 || missing+=(rustup)
command -v wasmtime  >/dev/null 2>&1 || missing+=(wasmtime)
command -v wasm-tools >/dev/null 2>&1 || missing+=(wasm-tools)

if [ ${#missing[@]} -ne 0 ]; then
    echo -e "${RED}Missing prerequisites: ${missing[*]}${NC}"
    echo "Install with:"
    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    echo "  cargo install wasm-tools wasmtime-cli"
    exit 1
fi

# --- Track results for the summary ---

V92_HAS_FD_CLOSE=""   # "yes" or "no"
V93_HAS_FD_CLOSE=""
V92_RUN_OK=""         # "yes" or "no"
V93_RUN_OK=""

echo ""
echo -e "${BOLD}============================================${NC}"
echo -e "${BOLD} Rust 1.93.0 wasm32-wasip2 fd_close regression${NC}"
echo -e "${BOLD}============================================${NC}"
echo ""

# --- Step 1: Install toolchains ---

echo -e "${BOLD}--- Step 1: Installing Rust 1.92.0 and 1.93.0 with wasm32-wasip2 ---${NC}"
echo ""
rustup toolchain install 1.92.0 --profile minimal --target wasm32-wasip2 2>&1 | tail -1
rustup toolchain install 1.93.0 --profile minimal --target wasm32-wasip2 2>&1 | tail -1
echo ""

# --- Step 2: Build with both versions ---

echo -e "${BOLD}--- Step 2: Build component with each version ---${NC}"
echo ""

echo -e "Building with Rust 1.92.0...${DIM}"
(cd component && cargo clean --quiet 2>/dev/null || true)
rustup run 1.92.0 cargo build --release --package wasi-component --target wasm32-wasip2 --quiet
cp target/wasm32-wasip2/release/wasi-component.wasm /tmp/wasi-component-1.92.wasm
echo -ne "${NC}"

echo -e "Building with Rust 1.93.0...${DIM}"
(cd component && cargo clean --quiet 2>/dev/null || true)
rustup run 1.93.0 cargo build --release --package wasi-component --target wasm32-wasip2 --quiet
cp target/wasm32-wasip2/release/wasi-component.wasm /tmp/wasi-component-1.93.wasm
echo -ne "${NC}"

echo ""

# --- Step 3: Compare imports ---

echo -e "${BOLD}--- Step 3: Check fd_close import in compiled WASM ---${NC}"
echo ""

# Dump to temp files to avoid SIGPIPE issues with large wasm-tools output
wasm-tools print /tmp/wasi-component-1.92.wasm 2>/dev/null > /tmp/wasm-print-1.92.txt || true
wasm-tools print /tmp/wasi-component-1.93.wasm 2>/dev/null > /tmp/wasm-print-1.93.txt || true

echo "Rust 1.92.0:"
if grep -q '"fd_close"' /tmp/wasm-print-1.92.txt; then
    V92_HAS_FD_CLOSE="yes"
    echo -e "  fd_close: ${GREEN}PRESENT${NC}"
    grep '(import.*"fd_close"' /tmp/wasm-print-1.92.txt | sed 's/^[[:space:]]*/    /'
else
    V92_HAS_FD_CLOSE="no"
    echo -e "  fd_close: ${RED}MISSING${NC}"
fi

echo ""
echo "Rust 1.93.0:"
if grep -q '"fd_close"' /tmp/wasm-print-1.93.txt; then
    V93_HAS_FD_CLOSE="yes"
    echo -e "  fd_close: ${GREEN}PRESENT${NC}"
    grep '(import.*"fd_close"' /tmp/wasm-print-1.93.txt | sed 's/^[[:space:]]*/    /'
else
    V93_HAS_FD_CLOSE="no"
    echo -e "  fd_close: ${RED}MISSING${NC}  <-- this is the bug"
fi

rm -f /tmp/wasm-print-1.92.txt /tmp/wasm-print-1.93.txt

echo ""

# --- Step 4: Run both versions ---

echo -e "${BOLD}--- Step 4: Run the component (1000 iterations of open/read/close) ---${NC}"
echo ""

echo "Rust 1.92.0:"
if wasmtime run --dir ./test-data::/test-data /tmp/wasi-component-1.92.wasm 2>&1; then
    V92_RUN_OK="yes"
    echo -e "  ${GREEN}PASS${NC}"
else
    V92_RUN_OK="no"
    echo -e "  ${RED}FAIL${NC}"
fi

echo ""
echo "Rust 1.93.0:"
if wasmtime run --dir ./test-data::/test-data /tmp/wasi-component-1.93.wasm 2>&1; then
    V93_RUN_OK="yes"
    echo -e "  ${GREEN}PASS${NC}"
else
    V93_RUN_OK="no"
    echo -e "  ${RED}FAIL${NC} — file descriptors leaked until resource table exhaustion"
fi

# Clean up temp wasm files
rm -f /tmp/wasi-component-1.92.wasm /tmp/wasi-component-1.93.wasm

# --- Summary ---

echo ""
echo -e "${BOLD}============================================${NC}"
echo -e "${BOLD} Summary${NC}"
echo -e "${BOLD}============================================${NC}"
echo ""

if [ "$V92_HAS_FD_CLOSE" = "yes" ] && [ "$V92_RUN_OK" = "yes" ] \
   && [ "$V93_HAS_FD_CLOSE" = "no" ] && [ "$V93_RUN_OK" = "no" ]; then
    # Expected outcome — the bug reproduces cleanly
    echo -e "${GREEN}Bug reproduced successfully.${NC}"
    echo ""
    echo "  Rust 1.92.0: fd_close PRESENT  — all 1000 iterations completed"
    echo "  Rust 1.93.0: fd_close MISSING  — failed after ~100-125 iterations"
    echo ""
    echo "The wasm32-wasip2 component compiled by Rust 1.93.0 is missing"
    echo "the fd_close import. Without it, file descriptors are never"
    echo "released, exhausting the WASI resource table."
else
    # Something didn't match expectations — report what actually happened
    echo -e "${YELLOW}Results did not match expected outcome.${NC}"
    echo ""
    echo "  Expected: 1.92.0 has fd_close and passes; 1.93.0 lacks fd_close and fails."
    echo "  Got:"
    echo ""

    if [ "$V92_HAS_FD_CLOSE" = "yes" ]; then
        echo -e "    Rust 1.92.0 fd_close: ${GREEN}present${NC}"
    else
        echo -e "    Rust 1.92.0 fd_close: ${RED}missing (unexpected)${NC}"
    fi
    if [ "$V92_RUN_OK" = "yes" ]; then
        echo -e "    Rust 1.92.0 runtime:  ${GREEN}pass${NC}"
    else
        echo -e "    Rust 1.92.0 runtime:  ${RED}fail (unexpected)${NC}"
    fi

    if [ "$V93_HAS_FD_CLOSE" = "yes" ]; then
        echo -e "    Rust 1.93.0 fd_close: ${GREEN}present (unexpected — bug may be fixed)${NC}"
    else
        echo -e "    Rust 1.93.0 fd_close: ${RED}missing${NC}"
    fi
    if [ "$V93_RUN_OK" = "yes" ]; then
        echo -e "    Rust 1.93.0 runtime:  ${GREEN}pass (unexpected — bug may be fixed)${NC}"
    else
        echo -e "    Rust 1.93.0 runtime:  ${RED}fail${NC}"
    fi

    echo ""
    echo "This may indicate the bug has been patched (e.g. a 1.93.x point"
    echo "release), or that something else is different in your environment."
    echo "Check 'rustc +1.93.0 -vV' and 'wasmtime --version' for details."
fi
echo ""
