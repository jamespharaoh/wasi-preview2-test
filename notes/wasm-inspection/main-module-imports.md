# What Our Module Actually Imports

**Date:** 2026-02-06
**Module:** Core Module 0 ($main) - Our compiled Rust code

## TL;DR

**Our code uses BOTH P1 and P2 APIs simultaneously** (hybrid approach).

This is NOT the adapter's fault - this is what **Rust std library compiles to** for wasm32-wasip2.

## Complete Import List

### Preview 1 APIs (Legacy)

```wat
(import "wasi_snapshot_preview1" "fd_read" ...)
(import "wasi_snapshot_preview1" "path_open" ...)
```

❌ **Missing:** `fd_close`

### Preview 2 APIs (New)

#### Filesystem
```wat
(import "wasi:filesystem/types@0.2.0" "[resource-drop]descriptor" ...)
(import "wasi:filesystem/types@0.2.0" "[method]descriptor.read-via-stream" ...)
(import "wasi:filesystem/types@0.2.0" "[method]descriptor.write-via-stream" ...)
(import "wasi:filesystem/types@0.2.0" "[method]descriptor.append-via-stream" ...)
(import "wasi:filesystem/types@0.2.0" "[method]descriptor.get-flags" ...)
(import "wasi:filesystem/types@0.2.0" "[method]descriptor.stat" ...)
(import "wasi:filesystem/types@0.2.0" "[method]descriptor.metadata-hash" ...)
(import "wasi:filesystem/preopens@0.2.0" "get-directories" ...)
```

#### Streams
```wat
(import "wasi:io/streams@0.2.0" "[resource-drop]input-stream" ...)
(import "wasi:io/streams@0.2.0" "[resource-drop]output-stream" ...)
(import "wasi:io/streams@0.2.4" "[resource-drop]output-stream" ...)  (duplicate version)
```

#### I/O & CLI
```wat
(import "wasi:io/error@0.2.4" "[resource-drop]error" ...)
(import "wasi:io/error@0.2.4" "[method]error.to-debug-string" ...)
(import "wasi:io/streams@0.2.4" "[method]output-stream.blocking-write-and-flush" ...)
(import "wasi:cli/stderr@0.2.4" "get-stderr" ...)
(import "wasi:cli/stdout@0.2.4" "get-stdout" ...)
(import "wasi:cli/stdin@0.2.0" "get-stdin" ...)
(import "wasi:cli/environment@0.2.0" "get-environment" ...)
(import "wasi:cli/exit@0.2.0" "exit" ...)
```

#### Other
```wat
(import "wasi:io/poll@0.2.0" "[resource-drop]pollable" ...)
(import "wasi:cli/terminal-input@0.2.0" "[resource-drop]terminal-input" ...)
(import "wasi:cli/terminal-output@0.2.0" "[resource-drop]terminal-output" ...)
(import "wasi:cli/terminal-stdin@0.2.0" "get-terminal-stdin" ...)
(import "wasi:cli/terminal-stdout@0.2.0" "get-terminal-stdout" ...)
(import "wasi:cli/terminal-stderr@0.2.0" "get-terminal-stderr" ...)
```

## The Hybrid Problem

Our compiled code imports:

```
File Operations:
✅ path_open (P1)                      - Opens file, returns fd number
✅ fd_read (P1)                        - Reads from fd number
❌ fd_close (P1) - NOT IMPORTED!       - Should close fd number

✅ [resource-drop]descriptor (P2)      - Drops P2 descriptor handle
✅ [resource-drop]input-stream (P2)    - Drops P2 stream handle
✅ descriptor.read-via-stream (P2)     - Gets stream from descriptor
```

## What This Means

When `File::open()` is called, **our code** (not the adapter!) calls:
1. P1 `path_open` → gets an fd number (e.g., fd 3)
2. P2 `descriptor.read-via-stream` → maybe also gets a P2 handle?

When `File::read()` is called, our code calls:
- P1 `fd_read` → reads using fd number

When `File` drops, our code calls:
- P2 `[resource-drop]descriptor` → drops P2 handle
- **Does NOT call P1 `fd_close`** → fd number leaks!

## Who's Responsible?

This hybrid approach comes from **Rust std library** for wasm32-wasip2.

The Rust std `File` implementation for this target:
- Still uses P1 APIs internally (path_open, fd_read)
- Also uses some P2 APIs (descriptors, streams)
- But doesn't import P1 fd_close
- Assumes P2 resource-drop is sufficient

**Location in Rust source:**
```
rust/library/std/src/sys/pal/wasi/
```

## Verification

```bash
# Extract main module imports
wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | \
  sed -n '/^  (core module $main /,/^  (core module \|^  (/p' | \
  grep "import"

# Check for fd_close
wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | \
  sed -n '/^  (core module $main /,/^  (core module \|^  (/p' | \
  grep "fd_close"
# Result: NOT FOUND
```

## Comparison with P1

In wasm32-wasip1, our code imports:
```wat
(import "wasi_snapshot_preview1" "fd_read" ...)
(import "wasi_snapshot_preview1" "path_open" ...)
(import "wasi_snapshot_preview1" "fd_close" ...)  ← ✅ PRESENT
```

Complete P1 API, no P2 APIs. Clean and works.

## Conclusion

**The bug is in Rust std library's wasm32-wasip2 target.**

The compiled code uses an incomplete hybrid of P1 and P2 APIs:
- Uses P1 for opening/reading (legacy)
- Uses P2 for resource management (new)
- But doesn't provide a way to close P1 file descriptors
- P2 resource-drop doesn't clean up P1 fds

The adapter then tries to bridge these two worlds, but it can't fix what the Rust compiler didn't emit.

## Next Step

We should check the Rust std library source to see exactly how `File` is implemented for wasm32-wasip2 and why it doesn't emit `fd_close` calls.
