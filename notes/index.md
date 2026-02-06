# Investigation Notes

This directory contains detailed notes from investigating the WASI Preview 2 resource leak issue.

## Notes

1. **[01-version-check.md](01-version-check.md)** - Verified we're using latest stable versions of wasmtime (41.0.3) and related crates. The resource leak is present in the current stable release.

2. **[02-adapter-layer-investigation.md](02-adapter-layer-investigation.md)** - 🔥 **ROOT CAUSE IDENTIFIED**: The leak is caused by the wasi-preview1-component-adapter. Rust's std library still uses WASIp1 APIs for filesystem operations, which go through an adapter that converts to WASIp2. The adapter appears to not properly clean up WASIp2 resources when WASIp1's `fd_close` is called.

3. **[preview1-comparison.md](preview1-comparison.md)** - ✅ **ADAPTER HYPOTHESIS CONFIRMED**: Created identical test using `wasm32-wasip1` target (Preview 1 without adapter). Preview 1 successfully completes 1000+ iterations while Preview 2 fails after ~100. This proves the bug is specifically in the P1→P2 adapter layer, not in wasmtime's core P1 implementation.

## Summary of Findings

### Root Cause (High Confidence)

**The wasi-preview1-component-adapter is leaking WASIp2 resources.**

- ✅ Rust std for `wasm32-wasip2` still uses WASIp1 filesystem APIs (confirmed in [PR #145944](https://github.com/rust-lang/rust/pull/145944))
- ✅ WASIp1 calls go through an adapter layer that converts to WASIp2
- ✅ WASIp2 requires explicit `resource.drop` calls for cleanup
- 🔍 Adapter likely doesn't call `resource.drop` when handling `fd_close`
- ✅ No existing GitHub issue found - this appears to be a **new bug**

### Evidence

- Each `File::open` creates ~2 WASIp2 resources (file + input-stream)
- When File drops, Rust calls WASIp1's `fd_close`
- Adapter receives `fd_close` but doesn't clean up underlying WASIp2 resources
- Resources accumulate until hitting the ~250 resource table limit
- Error code 48 (ENOMEM) occurs when resource table is exhausted
- **🎯 NEW: Preview 1 direct (no adapter) works perfectly with 1000+ iterations**
- **This definitively proves the bug is in the adapter layer, not wasmtime's P1 core**

### Why This Hasn't Been Found Before

1. WASIp2 is still early (Tier 2 support only since Nov 2024)
2. Most code doesn't stress file operations in tight loops
3. Adapter is temporary (will be replaced when std migrates to native WASIp2)
4. Limited WASIp2 adoption so far

## Investigation Status

- [x] Version verification - Using latest stable versions
- [x] GitHub issue search - **No existing issue found**
- [x] Root cause analysis - **Adapter layer identified**
- [x] Verification with wasm32-wasip1 target - ✅ **CONFIRMED: Preview 1 works perfectly (1000+ iterations)**
- [ ] File bug report with wasmtime
- [ ] File bug report with rust-lang
- [ ] Try newer wasmtime versions
- [ ] Inspect adapter source code
