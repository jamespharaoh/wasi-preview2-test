# How the WASI Preview 1 Component Adapter Works

**Date:** 2026-02-06

## Quick Answer

**Yes, the adapter is linked into the WASM file at build time**, not managed by wasmtime at runtime.

The component contains **TWO core modules**:
1. Your application code (main module)
2. The adapter module (acts as a P1→P2 bridge)

## Component Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ WASM Component (wasi-component.wasm)                            │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ Core Module 0: Main Application (__main_module__)     │    │
│  │                                                        │    │
│  │  Your Rust Code                                       │    │
│  │  - File::open(), File::read(), etc.                   │    │
│  │                                                        │    │
│  │  Imports from "wasi_snapshot_preview1":               │    │
│  │    - fd_read                                          │    │
│  │    - path_open                                        │    │
│  │    (these are fulfilled by the adapter module ↓)     │    │
│  └────────────────────────────────────────────────────────┘    │
│                            ↓                                    │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ Core Module 1: Adapter                                │    │
│  │ (wit-component:adapter:wasi_snapshot_preview1)        │    │
│  │                                                        │    │
│  │  Exports (P1 API - to main module):                   │    │
│  │    - fd_read      ← main module calls these           │    │
│  │    - path_open                                        │    │
│  │    (but NOT fd_close! ❌)                             │    │
│  │                                                        │    │
│  │  Imports (P2 API - from wasmtime):                    │    │
│  │    - wasi:filesystem/types@0.2.6                      │    │
│  │      - [method]descriptor.open-at                     │    │
│  │      - [method]descriptor.read-via-stream             │    │
│  │      - [resource-drop]descriptor                      │    │
│  │    - wasi:io/streams@0.2.6                            │    │
│  │      - [method]input-stream.blocking-read             │    │
│  │      - [resource-drop]input-stream                    │    │
│  │    - wasi:filesystem/preopens@0.2.6                   │    │
│  │      - get-directories                                │    │
│  └────────────────────────────────────────────────────────┘    │
│                            ↓                                    │
│  Component-level Imports (fulfilled by wasmtime):              │
│    - wasi:filesystem/types@0.2.6                               │
│    - wasi:io/streams@0.2.6                                     │
│    - wasi:cli/*@0.2.6                                          │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Wasmtime Runtime                                                │
│  - Provides P2 API implementations                              │
│  - Manages resource table                                       │
│  - Never sees P1 APIs directly                                  │
└─────────────────────────────────────────────────────────────────┘
```

## How Linking Works

### At Build Time (cargo build)

1. **Rust compiles your code** to a core WASM module
   - Uses `std::fs::File` which internally uses P1 APIs
   - Generates imports for `wasi_snapshot_preview1::fd_read`, `path_open`, etc.

2. **`wasm-component-ld` (the component linker) runs**
   - Automatically included by the Rust wasm32-wasip2 target
   - Takes your core module + the pre-built adapter module
   - Links them together into a component

3. **Result:** Single `.wasm` file containing both modules

### Verification

```bash
# See both modules in the component
$ wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | grep "core module"

# Output shows TWO modules:
# (core module ...) - Your application code (module 0)
# (core module $wit-component:adapter:wasi_snapshot_preview1 ...) - Adapter (module 1)
```

## Adapter Module Details

### What the Adapter Exports (P1 API)

```wat
(core module $wit-component:adapter:wasi_snapshot_preview1
  (export "fd_read" (func $fd_read))
  (export "path_open" (func $path_open))
  ;; ❌ NO export for "fd_close"!
)
```

### What the Adapter Imports (P2 API)

```wat
(core module $wit-component:adapter:wasi_snapshot_preview1
  ;; Filesystem operations
  (import "wasi:filesystem/types@0.2.6" "[method]descriptor.open-at" ...)
  (import "wasi:filesystem/types@0.2.6" "[method]descriptor.read-via-stream" ...)
  (import "wasi:filesystem/types@0.2.6" "[resource-drop]descriptor" ...)

  ;; Stream operations
  (import "wasi:io/streams@0.2.6" "[method]input-stream.blocking-read" ...)
  (import "wasi:io/streams@0.2.6" "[resource-drop]input-stream" ...)
  (import "wasi:io/streams@0.2.6" "[resource-drop]output-stream" ...)

  ;; Preopens
  (import "wasi:filesystem/preopens@0.2.6" "get-directories" ...)
)
```

## Call Flow Example

### Opening and Reading a File

```
Your Rust Code:
  File::open("/test-data/test.txt")
         ↓
  (compiled to core module call)
         ↓
Main Module (Module 0):
  call $path_open  (import from "wasi_snapshot_preview1")
         ↓
  (component model wiring connects this to adapter)
         ↓
Adapter Module (Module 1):
  func $path_open:
    1. Parse P1 path_open arguments
    2. Look up preopen descriptor
    3. Call P2 [method]descriptor.open-at
    4. Get back P2 descriptor handle (e.g., handle 42)
    5. Create P2 input-stream via read-via-stream
    6. Get back P2 stream handle (e.g., handle 43)
    7. Map these to a P1 file descriptor number (e.g., fd 3)
    8. Store mapping: fd 3 → {descriptor: 42, stream: 43}
    9. Return fd 3 to main module
         ↓
Main Module:
  Receives fd 3, stores it in File struct
         ↓
  call $fd_read (fd 3, buffer, length)
         ↓
Adapter Module:
  func $fd_read:
    1. Look up fd 3 in mapping → {descriptor: 42, stream: 43}
    2. Call P2 [method]input-stream.blocking-read on stream 43
    3. Return data to main module
         ↓
Main Module:
  File goes out of scope, Drop trait runs
  ⚠️  EXPECTS to call fd_close(3)
  ❌  BUT fd_close is NOT IMPORTED!
  ✅  DOES call [resource-drop]descriptor (P2)
         ↓
Adapter Module:
  func [resource-drop]descriptor maybe runs?
  ❌  But fd 3 mapping is never cleaned up!
  ❌  P2 descriptor 42 might be dropped
  ❌  P2 stream 43 might be dropped
  ❌  But the adapter's internal fd→handle mapping persists
  ❌  P1 file descriptor number is leaked
```

## The Bug

The adapter has a **broken API surface**:

```rust
// What it exports (P1 API):
✅ path_open  - Opens file, creates fd
✅ fd_read    - Reads from fd
❌ fd_close   - NOT EXPORTED! (should close fd)

// What it imports (P2 API):
✅ descriptor.open-at           - Creates P2 descriptor
✅ input-stream.blocking-read   - Reads from stream
✅ [resource-drop]descriptor    - Drops P2 descriptor
✅ [resource-drop]input-stream  - Drops P2 stream
```

The adapter provides **incomplete P1 API** (no fd_close), so:
- Main module can't explicitly close file descriptors
- Main module assumes Drop is sufficient
- But Drop doesn't call fd_close (because it's not imported)
- P2 resource-drops may run, but don't clean up adapter's internal fd mappings
- File descriptors leak until exhaustion

## Where the Adapter Comes From

### Build-time Inclusion

When you compile with `wasm32-wasip2` target:

```bash
cargo build --target wasm32-wasip2
```

The Rust toolchain:
1. Compiles your code to a core module
2. Runs `wasm-component-ld` (component linker)
3. Links in the pre-built adapter from the Rust sysroot

### Adapter Source Location

The adapter itself is built from:
- **Source:** https://github.com/bytecodealliance/wasmtime/tree/main/crates/wasi-preview1-component-adapter
- **Pre-built binary:** Included in Rust installation at:
  ```
  ~/.rustup/toolchains/1.93.0-x86_64-unknown-linux-gnu/lib/rustlib/wasm32-wasip2/lib/
  ```

### Verification

```bash
# Find adapter in Rust installation
$ find ~/.rustup -name "*adapter*" -name "*.wasm"

# Example output:
# ~/.rustup/toolchains/1.93.0-.../lib/rustlib/wasm32-wasip2/lib/wasi_snapshot_preview1.*.wasm
```

## Component Model Wiring

The component model handles connecting the modules:

```wat
;; Main module imports P1 API
(core module $main
  (import "wasi_snapshot_preview1" "fd_read" (func ...))
)

;; Adapter module exports P1 API
(core module $adapter
  (export "fd_read" (func $fd_read))
)

;; Component wiring connects them
(core instance $adapter-instance (instantiate $adapter ...))
(alias core export $adapter-instance "fd_read" (core func $adapter-fd-read))
(core instance $main-instance
  (instantiate $main
    (with "wasi_snapshot_preview1" (instance
      (export "fd_read" (func $adapter-fd-read))
    ))
  )
)
```

This is all **statically linked at build time**, not dynamically at runtime.

## Why You See P1 Symbols

When you inspect the WASM:

```bash
$ wasm-tools print wasi-component.wasm | grep "wasi_snapshot_preview1"
```

You see P1 imports because:
1. Your main module imports them
2. The adapter module uses them as its export namespace

But these imports are **fulfilled by the adapter**, not by wasmtime.

Wasmtime only sees the component-level P2 imports:
```
wasi:filesystem/types@0.2.6
wasi:io/streams@0.2.6
etc.
```

## Summary

- ✅ **Linked at build time** - Two modules bundled into one component
- ✅ **Adapter is statically included** - From Rust sysroot, not wasmtime
- ✅ **P1 API is internal** - Between main module and adapter
- ✅ **P2 API is external** - Between adapter and wasmtime
- ❌ **Adapter has incomplete P1 API** - Missing fd_close export
- ❌ **This causes the leak** - No way for main module to close fds

The adapter is essentially a **shim library** that translates between two APIs, but it has a bug where it doesn't provide a complete P1 API surface.
