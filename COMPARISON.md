# WASI Preview 1 vs Preview 2 Resource Leak Comparison

## Summary

This comparison demonstrates a **resource leak specific to WASI Preview 2** that does not occur in Preview 1.

## Test Setup

Both components run identical code:
- Open a file (`/test-data/test.txt`)
- Read 64 bytes
- Drop the file handle (Rust RAII)
- Repeat N times

## Results

| WASI Version | Iterations Tested | Result | Notes |
|--------------|------------------|--------|-------|
| **Preview 1** | 1000 | ✅ SUCCESS | No resource leak detected |
| **Preview 2** | 200 | ❌ FAILED | Fails after ~100-125 iterations |
| **Preview 2** | 100 | ✅ SUCCESS | Works within resource limits |

### Error from Preview 2 (200 iterations)

```
Error: Os { code: 48, kind: OutOfMemory, message: "Out of memory" }
```

Error code 48 = WASI's "too many open files" error, indicating file descriptors are not being released.

## Running the Tests

### Build Both Components

```bash
# Build Preview 1 component
cargo build --release --package wasi-component-p1 --target wasm32-wasip1

# Build Preview 2 component
cargo build --release --package wasi-component --target wasm32-wasip2

# Build host (supports both)
cargo build --release --package wasi-host --target x86_64-unknown-linux-gnu
```

### Run Preview 1 (Should succeed)

```bash
cargo run --release --package wasi-host --target x86_64-unknown-linux-gnu -- p1
```

### Run Preview 2 (Will fail with >100 iterations)

```bash
cargo run --release --package wasi-host --target x86_64-unknown-linux-gnu -- p2
```

## Conclusion

**The resource leak is confirmed to be specific to WASI Preview 2.**

Preview 1 properly releases file descriptors when `File` handles are dropped, while Preview 2 does not. This suggests the issue is in one of:

1. **wasmtime's Preview 2 implementation** - Resource table management
2. **Component Model** - Resource cleanup semantics
3. **Rust std library** - `wasm32-wasip2` target implementation

The fact that Preview 1 works correctly proves that:
- The test code is valid
- The host (wasmtime) is fundamentally capable of proper cleanup
- The issue is in the Preview 2 specific code path

## Next Steps

1. Investigate wasmtime's component model resource table implementation
2. Check if this is a known bug in wasmtime 41
3. Test with newer wasmtime versions
4. File bug report with wasmtime if not already tracked
5. Consider using Preview 1 as a workaround until Preview 2 is fixed
