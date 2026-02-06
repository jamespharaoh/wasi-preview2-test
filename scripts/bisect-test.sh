#!/bin/bash
# Bisect test script for cargo-bisect-rustc
# This tests whether a Rust version has the fd_close resource leak bug
#
# Exit codes:
#   0 = Good (no leak - test passed)
#   1 = Bad (has leak - test failed)
# 125 = Skip (couldn't build)

set -e

echo "=== Testing Rust version: $(rustc --version) ==="

# Build the component with the Rust version being tested
echo "Building component..."
cd /home/james/projects/mine/wasi-preview2-test/component
cargo build --release --target wasm32-wasip2 2>&1 || exit 125

# Build the host with stable Rust (we're not testing the host)
echo "Building host..."
cd /home/james/projects/mine/wasi-preview2-test/host
# Use stable for host
rustup run stable cargo build --release --target x86_64-unknown-linux-gnu 2>&1 || exit 125

# Run the test
echo "Running test..."
cd /home/james/projects/mine/wasi-preview2-test
rustup run stable cargo run --release --package wasi-host --target x86_64-unknown-linux-gnu 2>&1

# Check exit code
if [ $? -eq 0 ]; then
    echo "✅ GOOD: Test passed (no resource leak)"
    exit 0
else
    echo "❌ BAD: Test failed (resource leak detected)"
    exit 1
fi
