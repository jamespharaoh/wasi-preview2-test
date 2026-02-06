# WASM Imports Comparison: P1 vs P2

**Date:** 2026-02-06
**Finding:** The WASI Preview 2 component does NOT import `fd_close`, confirming the resource leak hypothesis.

## Executive Summary

The compiled WASM components show a critical difference:
- ✅ **Preview 1**: Imports `fd_close` and properly closes file descriptors
- ❌ **Preview 2**: Does NOT import `fd_close`, causing file descriptor leaks

## Preview 1 (wasm32-wasip1) - Complete File Lifecycle

```wat
(import "wasi_snapshot_preview1" "path_open" ...)   ; Open file
(import "wasi_snapshot_preview1" "fd_read" ...)     ; Read from file
(import "wasi_snapshot_preview1" "fd_close" ...)    ; ✅ Close file descriptor
```

### All P1 Imports

```
wasi_snapshot_preview1::fd_read
wasi_snapshot_preview1::fd_write
wasi_snapshot_preview1::path_open
wasi_snapshot_preview1::environ_get
wasi_snapshot_preview1::environ_sizes_get
wasi_snapshot_preview1::fd_close          ← ✅ PRESENT
wasi_snapshot_preview1::fd_prestat_get
wasi_snapshot_preview1::fd_prestat_dir_name
wasi_snapshot_preview1::proc_exit
```

## Preview 2 (wasm32-wasip2) - Incomplete File Lifecycle

The P2 component uses a **hybrid approach** that causes the leak:

```wat
(import "wasi_snapshot_preview1" "path_open" ...)   ; Opens file (P1 API)
(import "wasi_snapshot_preview1" "fd_read" ...)     ; Reads from file (P1 API)
                                                     ; ❌ NO fd_close import!
```

### P2 Core Module Imports (Relevant to Files)

**Preview 1 legacy functions:**
```
wasi_snapshot_preview1::fd_read        ; ✅ Imported
wasi_snapshot_preview1::path_open      ; ✅ Imported
                                       ; ❌ fd_close NOT imported
```

**Preview 2 resource management:**
```
wasi:filesystem/types@0.2.0::[resource-drop]descriptor
wasi:io/streams@0.2.0::[resource-drop]input-stream
wasi:io/streams@0.2.0::[resource-drop]output-stream
wasi:filesystem/types@0.2.0::[method]descriptor.read-via-stream
wasi:filesystem/preopens@0.2.0::get-directories
```

## The Problem: Hybrid Approach

The wasm32-wasip2 target in Rust std appears to be using a **hybrid implementation**:

1. **Opens files** using Preview 1 `path_open` (returns an fd number)
2. **Reads files** using Preview 1 `fd_read`
3. **Should close** using Preview 1 `fd_close` - but **doesn't import it**
4. **Has resource-drop** for P2 descriptors - but these don't close P1 fds

This mismatch means:
- File descriptors opened via `path_open` create entries in WASI's fd table
- When Rust drops the `File`, it may call `[resource-drop]descriptor`
- But the P1 file descriptor is never closed with `fd_close`
- The fd leaks in the host's resource table

## Why Preview 1 Works

Preview 1 uses a complete P1 API:
```
path_open → fd_read → fd_close (all P1 APIs)
```

The Rust compiler emits drop glue that calls `fd_close`, properly cleaning up.

## Why Preview 2 Fails

Preview 2 uses an incomplete hybrid:
```
path_open → fd_read → [resource-drop]descriptor (mixed P1/P2)
                      ↑
                      Doesn't call fd_close for P1 fd
```

The `[resource-drop]descriptor` may clean up the P2 descriptor resource, but the underlying P1 file descriptor is never closed.

## Commands Used for Investigation

### Generate full import lists:

```bash
# Preview 1 imports
wasm-tools print target/wasm32-wasip1/release/wasi-component-p1.wasm | \
  grep -E '^\s+\(import' > notes/wasm-inspection/p1-imports.txt

# Preview 2 core module imports
wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | \
  grep -E '^\s+\(import' > notes/wasm-inspection/p2-imports.txt
```

### Search for specific functions:

```bash
# Check if fd_close is imported in P1
wasm-tools print target/wasm32-wasip1/release/wasi-component-p1.wasm | \
  grep fd_close
# Result: ✅ Found

# Check if fd_close is imported in P2
wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | \
  grep fd_close
# Result: ❌ Not found
```

### View component WIT interface:

```bash
# See high-level P2 component interface
wasm-tools component wit target/wasm32-wasip2/release/wasi-component.wasm
```

## Conclusion

This confirms the hypothesis: **The issue is on the WASM side**.

The Rust compiler's wasm32-wasip2 target (or the std library implementation for this target) does not emit the necessary `fd_close` calls. This is likely a bug in:

1. **Rust std library** for wasm32-wasip2 target
2. **Rust compiler codegen** for drop glue on wasm32-wasip2
3. **WASI Preview 2 adapter** that bridges P1 and P2 APIs

## Next Steps

1. ✅ Document this finding
2. Report bug to Rust/WASI team with this evidence
3. Test with different Rust versions (1.83, 1.85, etc.)
4. Check if there's a way to force use of pure P2 APIs (no P1 fallback)
5. Look at Rust std library source for wasm32-wasip2 File implementation

## References

- WASI Preview 1 Spec: https://github.com/WebAssembly/WASI/blob/main/legacy/preview1/docs.md
- WASI Preview 2 Spec: https://github.com/WebAssembly/WASI/tree/main/preview2
- Component Model: https://github.com/WebAssembly/component-model
