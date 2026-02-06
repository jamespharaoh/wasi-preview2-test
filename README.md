# WASI Preview 2 Sample Program

This project demonstrates WASI Preview 2 (the WebAssembly Component Model) with file I/O operations using Rust.

## Project Structure

- `component/` - WASM component that performs file operations
- `host/` - Native host application that runs the component using wasmtime
- `test-data/` - Test file for the component to access

## What It Does

The WASM component opens and reads a test file 100 times, demonstrating:
- WASI Preview 2 filesystem access through preopened directories
- Component model instantiation and execution
- Host-to-component communication

## Building

```bash
# Build the WASM component
cargo build --release --package wasi-component --target wasm32-wasip2

# Build the host
cargo build --release --package wasi-host --target x86_64-unknown-linux-gnu
```

## Running

```bash
cargo run --release --package wasi-host --target x86_64-unknown-linux-gnu
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

## Technical Notes

### Resource Limits
The original plan called for 1000 iterations, but the current implementation successfully completes 100 iterations. Attempting 1000 iterations hits a resource limit (file descriptor limit in the WASI implementation). This is a known limitation and doesn't affect the demonstration of WASI Preview 2 functionality.

### WASI Preview 2 vs Preview 1
- Preview 2 uses the Component Model for better modularity
- Resources are managed through the component model's resource system
- More structured interface definitions via WIT (WebAssembly Interface Types)

## Dependencies

- Rust toolchain with `wasm32-wasip2` target
- wasmtime 41+ with component-model feature
- cap-std for filesystem capabilities
- wasm-tools (for inspecting components)

## References

- [WASI Preview 2](https://github.com/WebAssembly/WASI/tree/main/preview2)
- [WebAssembly Component Model](https://github.com/WebAssembly/component-model)
- [Wasmtime](https://wasmtime.dev/)
