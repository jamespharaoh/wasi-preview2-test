#!/usr/bin/env bash
# Test a specific Rust version for the fd_close leak.
#
# Usage:
#   ./scripts/test-rust-version.sh <version>
#
# Examples:
#   ./scripts/test-rust-version.sh 1.92.0
#   ./scripts/test-rust-version.sh 1.93.0
#   ./scripts/test-rust-version.sh nightly-2025-11-18

set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <rust-version>"
    echo "Examples:"
    echo "  $0 1.92.0"
    echo "  $0 1.93.0"
    echo "  $0 nightly-2025-11-18"
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "========================================="
echo "Testing Rust version: $VERSION"
echo "========================================="

# Install the version if not already installed
echo "Installing Rust $VERSION..."
rustup toolchain install "$VERSION" --profile minimal --target wasm32-wasip2

# Clean and rebuild the component
echo "Building component with Rust $VERSION..."
(cd component && cargo clean)
rustup run "$VERSION" cargo build --release --package wasi-component --target wasm32-wasip2

# Extract WIT (needed by host build)
echo "Extracting WIT..."
wasm-tools component wit target/wasm32-wasip2/release/wasi-component.wasm \
    > target/wasm32-wasip2/release/wasi-component.wit

# Build the host with stable Rust
echo "Building host..."
cargo build --release --package wasi-host --target x86_64-unknown-linux-gnu

# Check for fd_close in the compiled component
echo ""
echo "--- Import analysis ---"
WASM_TXT="$(mktemp)"
wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm > "$WASM_TXT" 2>/dev/null || true
if grep -q "fd_close" "$WASM_TXT"; then
    echo "fd_close: PRESENT"
else
    echo "fd_close: MISSING"
fi
rm -f "$WASM_TXT"

# Run the test
echo ""
echo "--- Running test (1000 iterations) ---"
TEST_RESULT=0
cargo run --release --package wasi-host --target x86_64-unknown-linux-gnu || TEST_RESULT=$?

echo ""
echo "========================================="
if [ "$TEST_RESULT" -eq 0 ]; then
    echo "PASS: Rust $VERSION - no resource leak"
else
    echo "FAIL: Rust $VERSION - resource leak detected"
fi
echo "========================================="

exit "$TEST_RESULT"
