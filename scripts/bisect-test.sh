#!/usr/bin/env bash
# Bisect test script for cargo-bisect-rustc.
#
# Exit codes:
#   0   = Good (no leak)
#   1   = Bad (leak detected)
#   125 = Skip (build failed)

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "=== Testing: $(rustc --version) ==="

# Build the component with the version under test
echo "Building component..."
(cd component && cargo build --release --target wasm32-wasip2 2>&1) || exit 125

# Extract WIT
wasm-tools component wit target/wasm32-wasip2/release/wasi-component.wasm \
    > target/wasm32-wasip2/release/wasi-component.wit 2>/dev/null || exit 125

# Build the host with stable Rust
echo "Building host..."
(cd host && rustup run stable cargo build --release --target x86_64-unknown-linux-gnu 2>&1) || exit 125

# Run the test
echo "Running test..."
if cargo run --release --package wasi-host --target x86_64-unknown-linux-gnu 2>&1; then
    echo "GOOD: no resource leak"
    exit 0
else
    echo "BAD: resource leak detected"
    exit 1
fi
