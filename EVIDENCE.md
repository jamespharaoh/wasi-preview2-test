# 🔍 Evidence: WASI Preview 2 Resource Leak Root Cause

**Status:** ✅ ROOT CAUSE IDENTIFIED
**Date:** 2026-02-06
**Issue:** File descriptors leak after ~100-125 file operations in wasm32-wasip2

---

## The Smoking Gun

The compiled WASM shows **Preview 2 does not import `fd_close`**:

```bash
# Preview 1 - Has fd_close ✅
$ wasm-tools print target/wasm32-wasip1/release/wasi-component-p1.wasm | grep fd_close
(import "wasi_snapshot_preview1" "fd_close" ...)

# Preview 2 - Missing fd_close ❌
$ wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | grep fd_close
# (no output - fd_close is NOT imported)
```

---

## Why This Causes the Leak

### Preview 1 (Works) - Complete Lifecycle

```
1. path_open → creates fd 3
2. fd_read   → reads from fd 3
3. fd_close  → closes fd 3 ✅
```

All three functions from the same API (wasi_snapshot_preview1).

### Preview 2 (Leaks) - Incomplete Hybrid

```
1. path_open           → creates fd 3 (P1 API)
2. fd_read             → reads from fd 3 (P1 API)
3. [resource-drop]     → drops P2 resource (P2 API)
   BUT fd 3 is never closed! ❌
```

The component uses **Preview 1 APIs for opening/reading** but doesn't import the corresponding **Preview 1 close function**.

While it has Preview 2 `[resource-drop]descriptor`, this doesn't close the underlying Preview 1 file descriptor.

---

## Quick Verification

Run the automated comparison:

```bash
./scripts/compare-imports.sh
```

**Expected Output:**
```
Preview 1:
  - Imports path_open: ✅
  - Imports fd_read:   ✅
  - Imports fd_close:  ✅ (complete lifecycle)

Preview 2:
  - Imports path_open: ✅ (P1 API)
  - Imports fd_read:   ✅ (P1 API)
  - Imports fd_close:  ❌ (MISSING - causes leak!)
```

---

## Detailed Analysis

See [notes/wasm-inspection/imports-comparison.md](notes/wasm-inspection/imports-comparison.md) for:
- Full import lists for both versions
- Technical explanation of the hybrid approach
- Component model vs core module imports
- Commands used for investigation

---

## Implications

This is a **compiler/standard library bug** in the wasm32-wasip2 target, not a wasmtime bug or user code issue.

**Likely culprits:**
1. Rust std library's `File` drop implementation for wasm32-wasip2
2. Missing drop glue generation in rustc for wasm32-wasip2
3. WASI Preview 2 adapter/shim layer not bridging P1 cleanup

---

## Update: Version Regression Identified (2026-02-06)

**Regression:** Bug introduced in **Rust 1.93.0** (2026-01-19)
**Fix:** Merged in **Rust 1.95.0-nightly** (2026-02-05) via pure P2 migration

See [notes/05-rust-version-regression.md](notes/05-rust-version-regression.md) for full version bisection results.

| Rust Version | Status | Notes |
|-------------|--------|-------|
| 1.90.0-1.92.0 | ✅ Works | Has `fd_close` import |
| 1.93.0 | ❌ **Broken** | Missing `fd_close` - **regression** |
| 1.94.0-beta | ❌ **Broken** | Still missing `fd_close` |
| 1.95.0-nightly | ✅ **Fixed** | Pure P2 implementation, no P1 hybrid |

**Workaround:** Use Rust 1.92.0 or nightly 1.95.0+

## Next Steps

1. ✅ Evidence documented (this file + detailed notes)
2. ✅ Test different Rust versions - **Regression found in 1.93.0**
3. ✅ Confirmed fix in nightly 1.95.0 (pure P2 migration)
4. 🔄 Report bug to Rust team with evidence
5. 🔄 Track fix landing in stable (1.95.0 expected ~March 2026)

---

## How to Reproduce

```bash
# Clone and build
git clone <this-repo>
cd wasi-preview2-test

# Build both versions
cargo build --release --package wasi-component-p1 --target wasm32-wasip1
cargo build --release --package wasi-component --target wasm32-wasip2

# Compare imports
./scripts/compare-imports.sh

# Run the leak test (fails after ~100-125 iterations)
# Edit component/src/main.rs: change loop to 1..=1000
cargo run --release --package wasi-host
```

---

## References

- **Rust Version:** 1.93.0 (January 2025)
- **Wasmtime:** 41.0.0 with component-model
- **wasm32-wasip2 target:** https://doc.rust-lang.org/nightly/rustc/platform-support/wasm32-wasip2.html
- **WASI Preview 2 Spec:** https://github.com/WebAssembly/WASI/tree/main/preview2
