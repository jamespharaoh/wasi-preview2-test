# WASI Preview 1 vs Preview 2 Resource Leak Demo

This project demonstrates a **resource leak in WASI Preview 2** that does not occur in Preview 1, through identical file I/O operations using Rust.

⚠️ **See [COMPARISON.md](COMPARISON.md) for detailed test results and analysis.**

## Project Structure

- `component/` - WASM component (Preview 2) that demonstrates the resource leak
- `component-p1/` - WASM module (Preview 1) that works correctly
- `host/` - Native host application supporting both P1 and P2
- `test-data/` - Test file for the components to access

## What It Does

The WASM component opens and reads a test file 100 times, demonstrating:
- WASI Preview 2 filesystem access through preopened directories
- Component model instantiation and execution
- Host-to-component communication

## Quick Demo

### Run Preview 2 (Shows the Bug)

```bash
# Build and run - will FAIL after ~100 iterations
cargo build --release --package wasi-component --target wasm32-wasip2
cargo run --release --package wasi-host --target x86_64-unknown-linux-gnu -- p2
```

### Run Preview 1 (Works Correctly)

```bash
# Build and run - completes 1000 iterations successfully
cargo build --release --package wasi-component-p1 --target wasm32-wasip1
cargo run --release --package wasi-host --target x86_64-unknown-linux-gnu -- p1
```

## Expected Output

```
Initializing WASI Preview 2 host...
Loading component from: ./target/wasm32-wasip2/release/wasi-component.wasm
Running component...

Starting WASI Preview 2 file I/O test
Completed 50 iterations
Completed 100 iterations
All 100 iterations completed successfully!

Component execution completed successfully!
```

## Implementation Details

### Component (WASM)
- Target: `wasm32-wasip2` (WASI Preview 2)
- Uses standard Rust `std::fs::File` for file operations
- No external dependencies - leverages std library's WASI support
- Exports `wasi:cli/run@0.2.6` interface

### Host
- Uses wasmtime 41 with component model support
- Preopens `./test-data` directory as `/test-data` (read-only)
- Uses wasmtime's component bindgen to generate type-safe bindings
- Provides WASI Preview 2 (p2) implementations synchronously

## The Bug

**Preview 2 fails after ~100-125 iterations with:**
```
Error: Os { code: 48, kind: OutOfMemory, message: "Out of memory" }
```

Error code 48 is WASI's "too many open files" error. File descriptors are not being released when `File` handles are dropped, despite Rust's RAII guarantees.

**Preview 1 works correctly** with 1000+ iterations, proving the issue is specific to Preview 2.

## Root Cause

The resource leak is in one of:
1. wasmtime's Preview 2 resource table implementation
2. Component Model's resource cleanup semantics
3. Rust std library's `wasm32-wasip2` target

The fact that Preview 1 works proves the test code is valid and the host is capable of proper cleanup.

## Dependencies

- Rust toolchain with `wasm32-wasip2` target
- wasmtime 41+ with component-model feature
- cap-std for filesystem capabilities
- wasm-tools (for inspecting components)

## References

- [WASI Preview 2](https://github.com/WebAssembly/WASI/tree/main/preview2)
- [WebAssembly Component Model](https://github.com/WebAssembly/component-model)
- [Wasmtime](https://wasmtime.dev/)
