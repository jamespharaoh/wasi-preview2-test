# How the Adapter Works - Simple Explanation

## TL;DR

**Yes, the adapter is linked into your WASM file at build time.**

Your `wasi-component.wasm` contains **TWO modules**:
1. Your Rust code (main module)
2. The adapter (bridge module)

The adapter sits between your code and wasmtime, translating P1 API calls to P2 API calls.

## Visual Architecture

```
┌─────────────────────────────────────────────────┐
│  Your Rust Code (File::open, File::read)       │
│                                                 │
│  Compiled to: wasm32-wasip2                     │
└─────────────────────────────────────────────────┘
                    ↓
        cargo build --target wasm32-wasip2
                    ↓
┌─────────────────────────────────────────────────┐
│  Component: wasi-component.wasm                 │
│  ┌─────────────────────────────────────────┐   │
│  │ Module 0: Your Code (main)             │   │
│  │                                         │   │
│  │  imports:                               │   │
│  │    - fd_read    (from P1 API)          │   │
│  │    - path_open  (from P1 API)          │   │
│  │    - fd_close   ❌ NOT imported!       │   │
│  └─────────────────────────────────────────┘   │
│                    ↓ ↑                          │
│  ┌─────────────────────────────────────────┐   │
│  │ Module 1: Adapter (bridge)             │   │
│  │                                         │   │
│  │  exports (to your code):                │   │
│  │    - fd_read    ✅                     │   │
│  │    - path_open  ✅                     │   │
│  │    - fd_close   ❌ MISSING!            │   │
│  │                                         │   │
│  │  imports (from wasmtime):               │   │
│  │    - descriptor.open-at     (P2)       │   │
│  │    - input-stream.read      (P2)       │   │
│  │    - [resource-drop]        (P2)       │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
                    ↓ ↑
┌─────────────────────────────────────────────────┐
│  Wasmtime Runtime                               │
│  - Provides P2 API implementations              │
│  - Never sees P1 APIs                           │
└─────────────────────────────────────────────────┘
```

## Proof It's Two Modules

```bash
# Extract module names from your component
$ wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | grep "core module"

# You'll see TWO modules:
(core module ...)  # Your code
(core module $wit-component:adapter:wasi_snapshot_preview1 ...)  # Adapter
```

## How Calls Flow

### When you open a file:

```
1. Your Code:
   File::open("/test-data/test.txt")
         ↓
2. Compiled to:
   call fd_open (P1 API)
         ↓
3. Adapter receives call:
   - Translates to: descriptor.open-at (P2 API)
   - Gets back P2 handle: 42
   - Maps to P1 fd: 3
   - Returns fd 3 to your code
         ↓
4. Your Code:
   Stores fd 3 in File struct
```

### When you read:

```
1. Your Code:
   file.read(&mut buffer)
         ↓
2. Compiled to:
   call fd_read(fd=3)
         ↓
3. Adapter:
   - Looks up fd 3 → P2 handle 42
   - Calls input-stream.read (P2 API)
   - Returns data to your code
```

### When File drops:

```
1. Your Code:
   // File goes out of scope
   // Rust Drop trait should call fd_close(3)
         ↓
2. Problem:
   ❌ fd_close is NOT imported by your module
   ❌ Drop implementation can't call what doesn't exist
   ✅ Drop MAY call [resource-drop]descriptor
         ↓
3. Adapter:
   ✅ P2 descriptor 42 might be dropped
   ✅ P2 stream might be dropped
   ❌ But adapter's internal "fd 3 → handle 42" mapping persists
   ❌ P1 file descriptor 3 is never cleaned up
```

## Where the Adapter Comes From

When you run:
```bash
cargo build --target wasm32-wasip2
```

Rust toolchain:
1. Compiles your code to a core WASM module
2. Automatically runs `wasm-component-ld` (component linker)
3. Links in the pre-built adapter module
4. Produces final component with both modules

The adapter is **pre-built** and shipped with Rust for the wasm32-wasip2 target.

## Key Insight

**The adapter is NOT part of wasmtime.**

It's part of your compiled WASM file. Wasmtime just runs it like any other WASM code.

Think of it like linking a library:
- Your code: `main.o`
- Adapter: `libadapter.a`
- Result: `program.wasm` (contains both)

## The Bug

The adapter's P1 API is incomplete:

```
Exports (what your code can call):
  ✅ path_open  - works
  ✅ fd_read    - works
  ❌ fd_close   - MISSING! → causes leak
  ❌ fd_write   - probably works (we don't use it)
```

Your code wants to call `fd_close` to clean up, but:
1. The adapter doesn't export it
2. So Rust can't import it
3. So the compiled WASM doesn't include it
4. So file descriptors never get closed

## Verification

See it yourself:

```bash
# Show both modules
wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm \
  | grep "core module" -A3

# Show what adapter exports
wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm \
  | grep -A50 "adapter:wasi_snapshot_preview1" \
  | grep "export"

# You'll see: fd_read, path_open, but NOT fd_close
```

## Why P1 Works

In wasm32-wasip1 (Preview 1), there's **NO adapter**:

```
Your Code
    ↓
Imports fd_read, fd_write, fd_close directly
    ↓
Wasmtime provides P1 API directly
    ↓
fd_close actually closes the file
```

P1 is complete. P2 adapter is broken.

---

**Full details:** [adapter-architecture.md](adapter-architecture.md)
