# WASI Preview 2 Resource Leak Investigation

## Project Purpose

This is a minimal reproducible example to investigate a **resource leak in WASI Preview 2** where file descriptors are not properly released when File handles are dropped, despite Rust's RAII guarantees.

This issue was discovered in a larger project and has been isolated to this minimal test case for investigation.

## The Issue

### Observed Behavior

When the WASM component opens and closes files in a loop:
- ✅ Works fine for ~100 iterations
- ❌ Fails after ~100-125 iterations with: `Os { code: 48, kind: OutOfMemory, message: "Out of memory" }`
- 💡 Error code 48 is WASI's "too many open files" error

### Expected Behavior

Each iteration should:
1. Open the file (`File::open`)
2. Read some bytes
3. Drop the `File` handle at end of scope (Rust RAII)
4. **Release underlying WASI resources** ← This is not happening

### Root Cause Hypothesis

The WASI Preview 2 resource table has a limit of **250 resources**. Each file open appears to consume **~2 resources** (likely one for the file descriptor and one for the input stream). When files are dropped in Rust, the WASM component should be calling the appropriate WASI functions to close/drop these resources, but they appear to remain in the resource table.

## Project Structure

```
wasi-preview2-test/
├── component/           # WASM component (wasm32-wasip2)
│   ├── Cargo.toml
│   └── src/main.rs     # Opens/reads file 100 times
├── host/               # Native host (x86_64)
│   ├── Cargo.toml      # wasmtime 41 with component-model
│   └── src/main.rs     # Runs the component
├── test-data/
│   └── test.txt        # File accessed by component
├── Cargo.toml          # Workspace root
└── .cargo/config.toml  # Sets default target to wasm32-wasip2
```

## Technical Details

### Component (WASM)
- **Target**: `wasm32-wasip2` (WASI Preview 2)
- **Rust**: 1.93.0 (January 2026)
- **Code**: Simple loop that opens file, reads 64 bytes, drops file
- **Interface**: Exports `wasi:cli/run@0.2.6`
- **Dependencies**: None (uses std library)

### Host (Native)
- **Target**: `x86_64-unknown-linux-gnu`
- **Wasmtime**: Version 41 with component-model feature
- **WASI**: Preview 2 (p2) in synchronous mode
- **Preopened dirs**: `./test-data` → `/test-data` (read-only)
- **Bindings**: Uses wasmtime's component bindgen macro

### Component Code Pattern

```rust
for i in 1..=100 {
    {
        let mut file = File::open(file_path)?;
        let mut _buffer = [0u8; 64];
        let _ = file.read(&mut _buffer)?;
        // file should be dropped here
    }
    // Explicit scope to ensure drop
}
```

## What We've Tried

1. ✅ **Explicit scoping** - Added explicit `{}` blocks to ensure drop
2. ✅ **Verified it's not an infinite loop** - Progress messages confirm iterations complete
3. ✅ **Reduced iterations** - Works fine with 100, fails around 125+
4. ✅ **Built minimal reproduction** - Isolated from larger project
5. ❌ **Resource cleanup** - No obvious way to force resource cleanup from component

## Build & Run

```bash
# Build component
cargo build --release --package wasi-component --target wasm32-wasip2

# Build host
cargo build --release --package wasi-host --target x86_64-unknown-linux-gnu

# Run (will succeed with 100 iterations)
cargo run --release --package wasi-host --target x86_64-unknown-linux-gnu
```

### Testing the Failure

To see the resource leak failure, edit `component/src/main.rs` and change:
```rust
for i in 1..=100 {
```
to:
```rust
for i in 1..=1000 {
```

Then rebuild and run. It will fail after ~100-125 iterations.

## Investigation Areas

### 1. Wasmtime/WASI Implementation
- Is this a known bug in wasmtime 41?
- Has this been fixed in newer versions?
- Is there a configuration option to adjust resource limits or cleanup?

### 2. Component Inspection
- Does the compiled WASM actually call `fd_close` or equivalent?
- Are drop glue functions properly implemented for wasm32-wasip2?
- Use `wasm-tools component wit` to inspect exports/imports

### 3. Host Configuration
- Is the resource table being managed correctly?
- Should we be manually managing cleanup between component calls?
- Are there wasmtime engine config options we're missing?

### 4. WASI Preview 2 Specifics
- Is this Preview 2 specific? Would Preview 1 work?
- Component model resource management differences?
- Are we missing required host-side resource cleanup?

### 5. Rust std Library
- Is wasm32-wasip2 std implementation missing drop calls?
- Should we use lower-level WASI APIs directly?
- File buffering interactions?

## Debugging Tools

```bash
# Inspect component WIT
wasm-tools component wit target/wasm32-wasip2/release/wasi-component.wasm

# Check what functions are imported/exported
wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | grep -A5 "import\|export"

# Disassemble component
wasm-tools component wit target/wasm32-wasip2/release/wasi-component.wasm > component.wit
```

## Workarounds Attempted

None successful so far. The only "workaround" is to limit file operations to <100, which isn't viable for real applications.

## Questions to Answer

1. **Where are resources leaking?** Component side (WASM) or host side (wasmtime)?
2. **What resources exactly?** File descriptors? Streams? Both?
3. **Is this reproducible across platforms?** Linux-specific or general?
4. **Version-specific?** Does wasmtime 42+ fix this? What about older versions?
5. **Is manual cleanup possible?** Can we explicitly close resources from the component?

## Desired Outcome

Figure out:
- Root cause of the resource leak
- Whether it's a bug in wasmtime, Rust std, or our code
- How to properly clean up WASI Preview 2 resources
- A fix or workaround that allows unlimited file operations

## References

- [WASI Preview 2 Spec](https://github.com/WebAssembly/WASI/tree/main/preview2)
- [Component Model](https://github.com/WebAssembly/component-model)
- [Wasmtime Documentation](https://docs.wasmtime.dev/)
- [wasm32-wasip2 Target](https://doc.rust-lang.org/nightly/rustc/platform-support/wasm32-wasip2.html)

## Git History

- Initial commit: Minimal reproduction of resource leak issue
- Each investigation attempt should be committed with clear description
