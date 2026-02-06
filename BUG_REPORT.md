# Bug Report: Resource Leak in Rust 1.93.0 Stable (wasm32-wasip2)

## Summary

Rust 1.93.0 stable has a critical regression causing file descriptor leaks in the `wasm32-wasip2` target. The bug is **release-specific** - it only exists in 1.93.0 stable and was never present on master.

## Issue

When using `std::fs::File` with the `wasm32-wasip2` target in Rust 1.93.0 stable, file descriptors are not properly released when `File` handles are dropped. This causes the WASI resource table to fill up, eventually resulting in "Out of memory" errors after ~100-125 file operations.

## Root Cause

The compiled WASM component is **missing the `fd_close` import** from WASI Preview 1. The component uses a hybrid P1/P2 approach but fails to import the cleanup function.

**Evidence:**
```bash
# Rust 1.92.0 (works) - has fd_close
$ wasm-tools print component.wasm | grep "fd_close"
(import "fd_close" (func $fd_close ...))

# Rust 1.93.0 stable (broken) - missing fd_close
$ wasm-tools print component.wasm | grep "fd_close"
# (no output - not imported)

# Rust 1.93.0-nightly (works) - has fd_close
$ wasm-tools print component.wasm | grep "fd_close"
(import "fd_close" (func $fd_close ...))
```

## Reproduction

### Minimal Example

```rust
use std::fs::File;
use std::io::Read;

fn main() -> std::io::Result<()> {
    let file_path = "/test-data/test.txt";

    for i in 1..=200 {
        let mut file = File::open(file_path)?;
        let mut buffer = [0u8; 64];
        let _ = file.read(&mut buffer)?;
        // File drops here but fd_close is not called

        if i % 50 == 0 {
            println!("Completed {} iterations", i);
        }
    }

    println!("Success!");
    Ok(())
}
```

### Build & Test

```bash
# Build with Rust 1.93.0 stable
rustup override set 1.93.0
cargo build --release --target wasm32-wasip2

# Run with wasmtime
wasmtime run --dir ./test-data::/test-data target/wasm32-wasip2/release/component.wasm

# Fails after ~100-125 iterations with:
# Error: Os { code: 48, kind: OutOfMemory, message: "Out of memory" }
```

## Affected Versions

### ❌ Broken
- **Rust 1.93.0 stable** (released Jan 19, 2026, commit 254b59607)

### ✅ Working
- **Rust 1.92.0 stable** (released Dec 8, 2025)
- **ALL nightly versions tested** (Sept 2025 → Jan 2026), including:
  - nightly-2025-11-18 (1.93.0-nightly, commit 0df64c578)
  - nightly-2025-12-29 (1.94.0-nightly, commit 21cf7fb3f)
  - nightly-2026-01-18 (1.94.0-nightly, commit fe98ddcfc)

## Analysis

This is a **release branch-specific regression**. The bug was never present on master, which suggests:

1. A bad cherry-pick or backport was applied to the 1.93 stable branch
2. The change affected how `fd_close` is imported for wasm32-wasip2
3. The bug was introduced during the release process, not during normal development

## Evidence

Full investigation available at: https://github.com/[your-repo]/wasi-preview2-test

Key findings:
- Comprehensive bisection of 10+ nightly versions (all pass)
- WASM bytecode analysis showing missing `fd_close` import
- Automated comparison script: `scripts/compare-imports.sh`
- Third-party reproduction in independent codebase

## Impact

- Makes `wasm32-wasip2` target **unusable for file I/O** in Rust 1.93.0
- Affects any WASM component that performs multiple file operations
- Resource table exhaustion occurs after ~100-125 file opens

## Workaround

Users should:
- ✅ Downgrade to Rust 1.92.0 stable
- ✅ Upgrade to any nightly version
- ✅ Wait for Rust 1.94.0 stable release
- ❌ Avoid Rust 1.93.0 stable

## Reproduction Repository

Complete reproduction case with investigation notes:
- Repository: [link to your repo]
- Minimal test case: `component/src/main.rs`
- Test script: `scripts/test-rust-version.sh`
- Comparison tool: `scripts/compare-imports.sh`

## System Information

```
rustc 1.93.0 (254b59607 2026-01-19)
target: wasm32-wasip2
wasmtime: 41.0.3
OS: Linux (tested on multiple platforms)
```

## Request

1. Investigate what changed on the 1.93 release branch between nightly and stable
2. Identify the bad backport/cherry-pick that removed `fd_close` import
3. Consider if 1.93.1 patch release is warranted
4. Document this as a known issue for users on 1.93.0

---

**Category:** Regression, Critical
**Component:** std::fs, wasm32-wasip2 target
**Labels:** A-wasm, O-wasi, regression-from-stable-to-stable, T-libs
