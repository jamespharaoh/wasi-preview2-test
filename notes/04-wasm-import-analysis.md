# 04 - WASM Import Analysis: Missing fd_close

**Date:** 2026-02-06
**Status:** ✅ Confirmed - Additional evidence supporting adapter hypothesis

## Overview

Direct inspection of the compiled WASM bytecode reveals that **wasm32-wasip2 does not import `fd_close`**, while wasm32-wasip1 does. This provides low-level evidence of how the adapter issue manifests.

## Key Finding

### Preview 1 (Works)
```bash
$ wasm-tools print target/wasm32-wasip1/release/wasi-component-p1.wasm | grep fd_close
(import "wasi_snapshot_preview1" "fd_close" ...)
```
✅ **`fd_close` IS imported**

### Preview 2 (Leaks)
```bash
$ wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | grep fd_close
# (no output)
```
❌ **`fd_close` is NOT imported**

## Detailed Import Comparison

### P1 - Complete File Operations
```wat
(import "wasi_snapshot_preview1" "fd_read" ...)
(import "wasi_snapshot_preview1" "fd_write" ...)
(import "wasi_snapshot_preview1" "path_open" ...)
(import "wasi_snapshot_preview1" "fd_close" ...)    ← ✅ PRESENT
```

### P2 - Hybrid Incomplete File Operations

**Preview 1 Legacy Functions (via adapter):**
```wat
(import "wasi_snapshot_preview1" "fd_read" ...)
(import "wasi_snapshot_preview1" "path_open" ...)
```

**Preview 2 Resource Management:**
```wat
(import "wasi:filesystem/types@0.2.0" "[resource-drop]descriptor" ...)
(import "wasi:io/streams@0.2.0" "[resource-drop]input-stream" ...)
(import "wasi:io/streams@0.2.0" "[resource-drop]output-stream" ...)
```

**Missing:**
```
❌ No "wasi_snapshot_preview1" "fd_close" import
❌ Hybrid P1/P2 approach leaves cleanup incomplete
```

## How This Connects to Adapter Issue

Our previous investigation ([02-adapter-layer-investigation.md](02-adapter-layer-investigation.md)) found that:
1. Rust std for wasm32-wasip2 uses WASIp1 APIs
2. These go through wasi-preview1-component-adapter
3. The adapter converts P1 calls to P2 resources

This WASM analysis shows the **technical mechanism**:

```
┌─────────────────────────────────────────────────────────────┐
│ Rust std library (wasm32-wasip2 target)                    │
│ - File::open() → calls path_open (P1 API)                  │
│ - File::read() → calls fd_read (P1 API)                    │
│ - File::drop() → should call fd_close... but doesn't!      │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Compiled WASM Component                                     │
│ - Imports: path_open, fd_read (P1)                         │
│ - Imports: [resource-drop]descriptor (P2)                  │
│ - Missing: fd_close (P1)                    ← THE PROBLEM  │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ wasi-preview1-component-adapter                             │
│ - path_open  → creates P2 descriptor + input-stream         │
│ - fd_read    → reads from stream                            │
│ - fd_close   → NOT CALLED (not imported!)                   │
│ - [resource-drop] → may run but doesn't clean P1-created fds│
└─────────────────────────────────────────────────────────────┘
```

## Why fd_close is Missing

Two possibilities:

### Option 1: Rust std not emitting fd_close
The wasm32-wasip2 target's `File` drop implementation may not be calling `fd_close` at all, assuming P2 resource-drop is sufficient.

### Option 2: Compiler optimization removing it
The compiler may see that `[resource-drop]descriptor` is imported and assume that's sufficient, removing the "redundant" `fd_close` call.

**Most likely:** It's intentional - the std library is *trying* to use P2 resource management but the hybrid P1/P2 approach is broken.

## Verification

Created automated script to demonstrate this:

```bash
./scripts/compare-imports.sh
```

Output clearly shows:
```
Preview 1:
  - Imports fd_close:  ✅ (complete lifecycle)

Preview 2:
  - Imports fd_close:  ❌ (MISSING - causes leak!)
```

Full details saved to:
- `notes/wasm-inspection/imports-comparison.md` - Detailed analysis
- `notes/wasm-inspection/p1-imports.txt` - All P1 imports (9 total)
- `notes/wasm-inspection/p2-imports.txt` - All P2 imports (88 total)

## Commands Used

```bash
# Build both versions
cargo build --release --package wasi-component-p1 --target wasm32-wasip1
cargo build --release --package wasi-component --target wasm32-wasip2

# Check for fd_close in P1
wasm-tools print target/wasm32-wasip1/release/wasi-component-p1.wasm | grep fd_close
# Result: ✅ Found (1 import + multiple internal calls)

# Check for fd_close in P2
wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | grep fd_close
# Result: ❌ Not found

# View full import lists
wasm-tools print target/wasm32-wasip1/release/wasi-component-p1.wasm | \
  grep -E '^\s+\(import' > p1-imports.txt

wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | \
  grep -E '^\s+\(import' > p2-imports.txt

# View high-level component interface (P2 only)
wasm-tools component wit target/wasm32-wasip2/release/wasi-component.wasm
```

## Implications

This confirms that the bug is in one of:

1. **Rust std library** - wasm32-wasip2 target's File implementation
   - Not generating proper drop code for P1 file descriptors
   - Located in: `library/std/src/sys/pal/wasi/` in rust repo

2. **wasi-preview1-component-adapter** - The P1→P2 bridge
   - Not properly handling the P1→P2 transition
   - When P2 `[resource-drop]descriptor` is called, should close P1 fd
   - Located in: https://github.com/bytecodealliance/wasmtime/tree/main/crates/wasi-preview1-component-adapter

Both could be contributing factors - the std library isn't emitting `fd_close`, and even if it did, the adapter might not handle cleanup correctly.

## Next Steps

1. ✅ WASM import analysis complete
2. ✅ Evidence documented
3. 🔄 Check Rust std library source for wasm32-wasip2 File implementation
4. 🔄 Check adapter source code for resource cleanup
5. 🔄 Test different Rust versions (when was wasm32-wasip2 added? When did this break?)
6. 🔄 File comprehensive bug report with full evidence chain

## References

- Previous finding: [02-adapter-layer-investigation.md](02-adapter-layer-investigation.md)
- P1 comparison: [preview1-comparison.md](preview1-comparison.md)
- Third-party confirmation: [03-third-party-reproduction.md](03-third-party-reproduction.md)
- Quick evidence: [../EVIDENCE.md](../EVIDENCE.md)
- Detailed analysis: [wasm-inspection/imports-comparison.md](wasm-inspection/imports-comparison.md)
