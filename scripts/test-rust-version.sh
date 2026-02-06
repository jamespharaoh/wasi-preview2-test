#!/bin/bash
# Test a specific Rust version (stable or nightly) for the fd_close leak
# Usage: ./test-rust-version.sh <version>
#   Examples:
#     ./test-rust-version.sh 1.92.0
#     ./test-rust-version.sh nightly-2025-10-01

VERSION=$1
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <rust-version>"
    echo "Examples:"
    echo "  $0 1.92.0"
    echo "  $0 nightly-2025-10-01"
    exit 1
fi

echo "========================================="
echo "Testing Rust version: $VERSION"
echo "========================================="

# Install the version if not already installed
echo "Installing Rust $VERSION..."
rustup toolchain install "$VERSION" --profile minimal --target wasm32-wasip2

# Clean only the component build
echo "Cleaning component build..."
cd /home/james/projects/mine/wasi-preview2-test/component
cargo clean

# Build component with the test version
echo "Building component with Rust $VERSION..."
rustup run "$VERSION" cargo build --release --target wasm32-wasip2
COMPONENT_BUILD=$?

if [ $COMPONENT_BUILD -ne 0 ]; then
    echo "❌ Failed to build component with Rust $VERSION"
    exit 1
fi

# Extract WIT from the component
echo "Extracting WIT from component..."
cd /home/james/projects/mine/wasi-preview2-test
wasm-tools component wit target/wasm32-wasip2/release/wasi-component.wasm > target/wasm32-wasip2/release/wasi-component.wit

# Build host with stable
echo "Building host with stable Rust..."
cd /home/james/projects/mine/wasi-preview2-test/host
cargo build --release --target x86_64-unknown-linux-gnu
HOST_BUILD=$?

if [ $HOST_BUILD -ne 0 ]; then
    echo "❌ Failed to build host"
    exit 1
fi

# Run the test (make sure we're in the project root)
echo ""
echo "Running test (200 iterations)..."
echo "---"
cd /home/james/projects/mine/wasi-preview2-test
cargo run --release --package wasi-host --target x86_64-unknown-linux-gnu
TEST_RESULT=$?

echo ""
echo "========================================="
if [ $TEST_RESULT -eq 0 ]; then
    echo "✅ PASS: Rust $VERSION - No resource leak"
    echo "========================================="
else
    echo "❌ FAIL: Rust $VERSION - Resource leak detected"
    echo "========================================="
fi

exit $TEST_RESULT
