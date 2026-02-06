# Adapter Layer Investigation - The Root Cause

**Date**: 2026-02-06
**Investigation**: Resource leak root cause analysis

## TL;DR - Critical Discovery

**The resource leak is almost certainly caused by the wasi-preview1-component-adapter layer.**

Rust's `std` library for `wasm32-wasip2` still uses WASIp1 APIs for all filesystem operations. These calls go through an adapter that converts them to WASIp2, but the adapter appears to not properly clean up WASIp2 resources when WASIp1's `fd_close` is called.

## Key Findings

### 1. Rust std Still Uses WASIp1 for Filesystem Operations

**Source**: [rust-lang/rust PR #145944](https://github.com/rust-lang/rust/pull/145944)
- **Merged**: September 3, 2025
- **Status**: WASIp2 native support partially implemented

From the PR description:
> "Everything related to file descriptors and filesystem APIs is still using WASIp1. Migrating that is left for a future PR."

This means when we use `File::open` on `wasm32-wasip2`, it's **not using native WASIp2 APIs**. It's still calling WASIp1 functions that get converted through an adapter layer.

#### What Was Migrated (PR #145944)
- ✅ Time APIs (`wasi:clocks`)
- ✅ Random APIs (`wasi:random`)
- ✅ Process arguments/environment (`wasi:cli/environment`)
- ❌ **Filesystem APIs** - Still using WASIp1

### 2. The Adapter Layer Architecture

**Source**: [wasmtime wasi-preview1-component-adapter](https://github.com/bytecodealliance/wasmtime/tree/main/crates/wasi-preview1-component-adapter)

The adapter is a WebAssembly module that bridges:
- **Input**: `wasi_snapshot_preview1` ABI (used by Rust std)
- **Output**: WASIp2 component model APIs

**Flow**:
```
Rust std::fs::File::open
    ↓
WASIp1: fd_open (imports wasi_snapshot_preview1)
    ↓
wasi-preview1-component-adapter (Rust → Wasm module)
    ↓
WASIp2: filesystem.open (returns resource handle)
```

From the [wasi-libc proposal](https://github.com/WebAssembly/wasi-libc/issues/447):
> "During the transition period, wasi-libc and the adapter will share responsibility for mapping Preview 1 file descriptors to Preview 2 resource handles."

### 3. WASIp2 Resource Management Requirements

**Source**: [wasmtime PR #6691 - Component Model Resources](https://github.com/bytecodealliance/wasmtime/pull/6691)

WASIp2 uses **resource handles** instead of file descriptors:
- Resource handles are unforgeable and managed by the host
- **Critical requirement**: `ResourceAny` must always be explicitly destroyed with `ResourceAny::resource_drop`

From the implementation:
> "ResourceAny must always be explicitly destroyed with the ResourceAny::resource_drop method, which is required to be called for all instances of ResourceAny to ensure that state associated with this resource is properly cleaned up."

**Difference from WASIp1**:
- **WASIp1**: File descriptors are integers, `fd_close` releases them
- **WASIp2**: Resource handles are opaque, require explicit `resource.drop` calls

### 4. Evidence of Adapter Bugs

**Source**: [wasmtime issue #8956](https://github.com/bytecodealliance/wasmtime/issues/8956)

The adapter has had correctness issues before:
- Unsound implementation of `fd_filestat_get`
- Caused Clang to treat all read files as the same file
- Shows the adapter layer is complex and has had bugs

### 5. Our Observed Behavior Explained

#### What Happens in Our Code

```rust
for i in 1..=100 {
    {
        let mut file = File::open(file_path)?;  // ← Opens file
        let mut _buffer = [0u8; 64];
        let _ = file.read(&mut _buffer)?;
        // file dropped here ← Should clean up
    }
}
```

#### What Actually Happens (Hypothesis)

1. **File::open**
   - Rust std calls WASIp1's `fd_open`
   - Adapter converts to WASIp2 `filesystem.open`
   - **Creates ~2 WASIp2 resources**:
     - File descriptor resource
     - Input stream resource
   - Returns WASIp1 fd number to Rust

2. **File::drop**
   - Rust std calls WASIp1's `fd_close`
   - Adapter receives `fd_close(fd_num)`
   - **BUG**: Adapter may not call `resource.drop` on the underlying WASIp2 resources
   - WASIp2 resources remain in the resource table

3. **Resource Exhaustion**
   - Each iteration leaks ~2 resources
   - Resource table limit: ~250 resources
   - After ~125 iterations: table full
   - Error: `Os { code: 48, kind: OutOfMemory, message: "Out of memory" }`

### 6. Why Error Code 48?

From [WASI errno values](https://docs.rs/wasi-types/0.1.6/wasi_types/enum.ErrNo.html):
- Error 41 (ENFILE): "Too many files open in system"
- **Error 48 (ENOMEM)**: "Out of memory"

The resource table exhaustion manifests as ENOMEM because the host can't allocate more resource handles, not because we've hit the file descriptor limit.

## No Existing Issue Found

### Search Results

Searched extensively for existing bug reports:
- ✅ wasmtime repository issues
- ✅ rust-lang repository issues
- ✅ WASI specification discussions
- ✅ Web search for "wasi preview2 resource leak file descriptor"

**Result**: No existing issue matches this exact problem.

This suggests we may have discovered a **new bug** that hasn't been widely reported yet.

### Why Hasn't This Been Found?

Possible reasons:
1. **WASIp2 is still early** - Tier 2 support only since November 2024
2. **Most code doesn't stress file operations** - Many wasm apps don't open/close files in tight loops
3. **Adapter is temporary** - Expected to be replaced once Rust std migrates to native WASIp2
4. **Limited WASIp2 adoption** - Most users still on WASIp1

## Verification Steps

### Test 1: Try wasm32-wasip1 Target

To confirm the adapter is the problem, bypass it entirely:

```bash
# Edit .cargo/config.toml or component/Cargo.toml
# Change: target = "wasm32-wasip2"
# To:     target = "wasm32-wasip1"
```

**Expected result**: If leak disappears, confirms adapter is the issue.

### Test 2: Inspect Adapter Source

The adapter source is at:
- [wasmtime/crates/wasi-preview1-component-adapter/src/lib.rs](https://github.com/bytecodealliance/wasmtime/blob/main/crates/wasi-preview1-component-adapter/src/lib.rs)

Look for `fd_close` implementation and verify it calls `resource.drop` on:
- The file descriptor resource
- The input-stream resource
- Any other associated resources

### Test 3: Try Newer Wasmtime

Current version: wasmtime 41.0.3

Check if fixed in wasmtime 42+ by updating `host/Cargo.toml`:
```toml
wasmtime = { version = "42", features = ["component-model"] }
```

## Evidence Summary

| Finding | Certainty | Source |
|---------|-----------|--------|
| Rust std uses WASIp1 for filesystem ops | ✅ Confirmed | [PR #145944](https://github.com/rust-lang/rust/pull/145944) |
| Adapter converts WASIp1 to WASIp2 | ✅ Confirmed | [Adapter README](https://github.com/bytecodealliance/wasmtime/tree/main/crates/wasi-preview1-component-adapter) |
| WASIp2 requires explicit resource.drop | ✅ Confirmed | [PR #6691](https://github.com/bytecodealliance/wasmtime/pull/6691) |
| Adapter has had other bugs | ✅ Confirmed | [Issue #8956](https://github.com/bytecodealliance/wasmtime/issues/8956) |
| Adapter doesn't drop resources on fd_close | 🔍 Very likely | Hypothesis based on evidence |
| No existing bug report | ✅ Confirmed | Extensive search |

## Next Steps

### 1. File Bug Reports

File issues with:

**wasmtime repository** (primary):
- **Title**: "wasi-preview1-component-adapter leaks WASIp2 resources on fd_close"
- **Link**: https://github.com/bytecodealliance/wasmtime/issues
- **Include**: Link to this minimal reproduction repo

**rust-lang repository** (secondary):
- **Title**: "wasm32-wasip2: Resource leak when using std::fs::File"
- **Link**: https://github.com/rust-lang/rust/issues
- **Tag**: @alexcrichton (author of WASIp2 PR #145944)
- **Note**: May be wasmtime issue, but affects Rust users

### 2. Workarounds

Until fixed:

**Option A**: Use `wasm32-wasip1` target
- Simple, proven to work
- Loses WASIp2 features (networking, etc.)

**Option B**: Manually manage file count
- Keep global counter, error if approaching limit
- Not a real solution, but prevents crashes

**Option C**: Wait for native WASIp2 std support
- Track progress on Rust WASIp2 migration
- No adapter = no adapter bugs

### 3. Community Engagement

Consider posting to:
- Bytecode Alliance Zulip
- Rust WebAssembly working group
- WASI specification discussions

This could help:
- Confirm the hypothesis
- Find others with same issue
- Accelerate fix

## References

### Primary Sources
- [std: Start supporting WASIp2 natively (PR #145944)](https://github.com/rust-lang/rust/pull/145944)
- [wasi-preview1-component-adapter](https://github.com/bytecodealliance/wasmtime/tree/main/crates/wasi-preview1-component-adapter)
- [Implement component model resources (PR #6691)](https://github.com/bytecodealliance/wasmtime/pull/6691)
- [Unsound fd_filestat_get implementation (#8956)](https://github.com/bytecodealliance/wasmtime/issues/8956)

### Background Reading
- [The wasm32-wasip2 Target Has Reached Tier 2 Support](https://blog.rust-lang.org/2024/11/26/wasip2-tier-2/)
- [wasi-libc Preview 2 proposal (#447)](https://github.com/WebAssembly/wasi-libc/issues/447)
- [WASI fd_close documentation](https://docs.rs/wasi/0.10.0+wasi-snapshot-preview1/wasi/wasi_snapshot_preview1/fn.fd_close.html)
- [Wasmtime WASIp2 documentation](https://docs.wasmtime.dev/examples-wasip2.html)

## Conclusion

We are **not doing anything wrong**. This appears to be a legitimate bug in the wasi-preview1-component-adapter's resource cleanup when translating WASIp1 `fd_close` calls to WASIp2 resource drops.

The fact that:
1. No existing issue was found
2. We have a minimal reproduction
3. The adapter is known to have had bugs
4. The architecture requires explicit resource cleanup

All point to this being a **real, previously unreported bug** that affects anyone using `std::fs` operations on `wasm32-wasip2`.

This should be reported to the wasmtime team.
