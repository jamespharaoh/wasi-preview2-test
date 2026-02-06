# WASI Preview 2 Resource Leak - Regression Summary

**Date:** 2026-02-06
**Status:** Identified and fixed in nightly

---

## TL;DR

| What | Details |
|------|---------|
| **Bug** | File descriptor leak in wasm32-wasip2 target |
| **Cause** | Missing `fd_close` import in Rust 1.93.0 |
| **Symptom** | Fails after ~100-125 file operations with "Out of memory" |
| **Broken** | Rust 1.93.0, 1.94.0-beta (and likely 1.94.0 stable) |
| **Working** | Rust 1.90.0-1.92.0, nightly 1.95.0+ |
| **Fix** | Use Rust 1.92.0 or nightly until 1.95.0 stable (~March 2026) |

---

## Quick Test

```bash
# Broken version
rustup default 1.93.0
cargo build --release --target wasm32-wasip2
cargo run --release --package wasi-host
# Error: Os { code: 48, kind: OutOfMemory, message: "Out of memory" }
# Fails after ~100 iterations

# Working version
rustup default 1.92.0  # or nightly
cargo build --release --target wasm32-wasip2
cargo run --release --package wasi-host
# All 2000 iterations completed successfully!
```

---

## Version Test Results

```
Rust 1.90.0  ✅ PASS - fd_close present
Rust 1.91.0  ✅ PASS - fd_close present
Rust 1.92.0  ✅ PASS - fd_close present
Rust 1.93.0  ❌ FAIL - fd_close MISSING (regression)
Rust 1.94.0β ❌ FAIL - fd_close MISSING
Rust 1.95.0n ✅ PASS - Pure Preview 2 (no hybrid)
```

---

## What Happened

### Rust 1.90-1.92 (Working)

Uses hybrid Preview 1 + Preview 2 approach:
```wat
✅ import "wasi_snapshot_preview1" "path_open"
✅ import "wasi_snapshot_preview1" "fd_read"
✅ import "wasi_snapshot_preview1" "fd_close"  ← Present!
```

File lifecycle: `path_open` → `fd_read` → `fd_close` → cleanup ✅

### Rust 1.93 (Broken)

Uses broken hybrid approach:
```wat
✅ import "wasi_snapshot_preview1" "path_open"
✅ import "wasi_snapshot_preview1" "fd_read"
❌ NO fd_close import!  ← Bug!
```

File lifecycle: `path_open` → `fd_read` → ❌ no cleanup → leak!

### Rust 1.95-nightly (Fixed)

Pure WASI Preview 2 implementation:
```wat
❌ NO wasi_snapshot_preview1 imports at all!
✅ Uses pure Preview 2 filesystem APIs
✅ Proper resource-drop for descriptors and streams
```

File lifecycle: P2 open → P2 read → P2 resource-drop → cleanup ✅

---

## Workaround

### Option 1: Use Rust 1.92.0 (Stable)

```bash
rustup install 1.92.0
rustup default 1.92.0
cargo build --release --target wasm32-wasip2
```

**Pros:** Stable, well-tested
**Cons:** Older toolchain

### Option 2: Use Nightly (Latest Fix)

```bash
rustup install nightly
rustup default nightly
cargo build --release --target wasm32-wasip2
```

**Pros:** Latest features, proper P2 implementation
**Cons:** Nightly instability

### Option 3: Wait for 1.95.0 Stable

Expected release: ~March 2026

---

## Files to Report

When filing bug report, reference:
- [notes/05-rust-version-regression.md](notes/05-rust-version-regression.md) - Full analysis
- [EVIDENCE.md](EVIDENCE.md) - Technical evidence
- This repo as minimal reproduction

---

## Technical Details

See detailed documentation:
- [notes/05-rust-version-regression.md](notes/05-rust-version-regression.md) - Version bisection
- [notes/04-wasm-import-analysis.md](notes/04-wasm-import-analysis.md) - WASM analysis
- [notes/index.md](notes/index.md) - Full investigation history
