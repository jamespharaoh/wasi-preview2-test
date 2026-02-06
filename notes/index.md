# Investigation Notes

This directory contains detailed notes from investigating the WASI Preview 2 resource leak issue.

## Notes

1. **[01-version-check.md](01-version-check.md)** - Verified we're using latest stable versions of wasmtime (41.0.3) and related crates. The resource leak is present in the current stable release.

2. **[02-adapter-layer-investigation.md](02-adapter-layer-investigation.md)** - 🔥 **ROOT CAUSE IDENTIFIED**: The leak is caused by the wasi-preview1-component-adapter. Rust's std library still uses WASIp1 APIs for filesystem operations, which go through an adapter that converts to WASIp2. The adapter appears to not properly clean up WASIp2 resources when WASIp1's `fd_close` is called.

3. **[preview1-comparison.md](preview1-comparison.md)** - ✅ **ADAPTER HYPOTHESIS CONFIRMED**: Created identical test using `wasm32-wasip1` target (Preview 1 without adapter). Preview 1 successfully completes 1000+ iterations while Preview 2 fails after ~100. This proves the bug is specifically in the P1→P2 adapter layer, not in wasmtime's core P1 implementation.

4. **[03-third-party-reproduction.md](03-third-party-reproduction.md)** - ✅ **THIRD-PARTY CONFIRMATION**: Reproduced the resource leak in [wasip2_plugins](https://github.com/benwis/wasip2_plugins) (completely independent codebase). Bug confirmed across multiple wasmtime versions (29, 41) and multiple codebases. **NEW FINDING**: Resources persist across component invocations - 100 iterations succeeded, then 2nd call failed at iteration 25 (125 total = resource table limit).

5. **[04-wasm-import-analysis.md](04-wasm-import-analysis.md)** - 🔍 **WASM BYTECODE EVIDENCE**: Direct inspection of compiled WASM shows that `wasm32-wasip2` does **not import `fd_close`**, while `wasm32-wasip1` does. This provides low-level evidence of how the adapter issue manifests - the component uses P1 APIs (`path_open`, `fd_read`) but doesn't import the corresponding cleanup function (`fd_close`). Created automated comparison script at `scripts/compare-imports.sh`.
   - See also: [wasm-inspection/ADAPTER-EXPLAINED.md](wasm-inspection/ADAPTER-EXPLAINED.md) - Simple explanation of adapter architecture
   - See also: [wasm-inspection/adapter-architecture.md](wasm-inspection/adapter-architecture.md) - Detailed adapter architecture
   - See also: [wasm-inspection/main-module-imports.md](wasm-inspection/main-module-imports.md) - **🎯 KEY FINDING**: Our main module uses BOTH P1 and P2 APIs (hybrid approach). The bug is in Rust std, not the adapter!

6. **[05-rust-version-regression.md](05-rust-version-regression.md)** - 🐛 **REGRESSION IDENTIFIED**: Bug was **introduced in Rust 1.93.0** (2026-01-19) and **fixed in nightly 1.95.0** (2026-02-05). Version bisection shows:
   - Rust 1.90.0-1.92.0: ✅ **Works** (has `fd_close` import)
   - Rust 1.93.0: ❌ **Broken** (missing `fd_close` - regression)
   - Rust 1.94.0-beta: ❌ **Broken** (still missing)
   - Rust 1.95.0-nightly: ✅ **Fixed** (migrated to pure P2, eliminates hybrid approach)

   **Workaround:** Use Rust 1.92.0 or nightly 1.95.0+ until stable fix releases.

## Summary of Findings

### Root Cause (Confirmed)

**Regression in Rust 1.93.0 where `fd_close` import was removed from wasm32-wasip2 target.**

- ✅ **Bug introduced:** Rust 1.93.0 (2026-01-19)
- ✅ **Bug fixed:** Rust 1.95.0-nightly (2026-02-05) via pure P2 migration
- ✅ Rust std for `wasm32-wasip2` uses hybrid P1/P2 approach (in 1.93.0)
- ✅ Missing `fd_close` import causes file descriptor leaks
- ✅ Nightly 1.95.0 eliminates hybrid approach entirely (pure P2)
- ✅ No existing GitHub issue found - this appears to be a **new bug**

### Evidence

- Each `File::open` creates ~2 WASIp2 resources (file + input-stream)
- When File drops, Rust calls WASIp1's `fd_close`
- Adapter receives `fd_close` but doesn't clean up underlying WASIp2 resources
- Resources accumulate until hitting the ~250 resource table limit
- Error code 48 (ENOMEM) occurs when resource table is exhausted
- **🎯 Preview 1 direct (no adapter) works perfectly with 1000+ iterations**
- **This definitively proves the bug is in the adapter layer, not wasmtime's P1 core**
- **🎯 Bug reproduced in third-party code (wasip2_plugins) with wasmtime 29**
- **Confirms issue exists across wasmtime versions 29 → 41**
- **🔥 Resources persist across component invocations** - not cleaned up between async calls
- **🔍 WASM bytecode analysis**: P2 component imports `path_open` and `fd_read` (P1 APIs) but does NOT import `fd_close`
- **P1 component DOES import all three**: `path_open`, `fd_read`, `fd_close`
- **This explains the mechanism**: Rust std is trying to use P2 resource-drop but still uses P1 file APIs, creating an incomplete hybrid

### Why This Hasn't Been Found Before

1. WASIp2 is still early (Tier 2 support only since Nov 2024)
2. Most code doesn't stress file operations in tight loops
3. Adapter is temporary (will be replaced when std migrates to native WASIp2)
4. Limited WASIp2 adoption so far

## Investigation Status

- [x] Version verification - Using latest stable versions
- [x] GitHub issue search - **No existing issue found**
- [x] Root cause analysis - **Missing fd_close in Rust 1.93.0**
- [x] Verification with wasm32-wasip1 target - ✅ **CONFIRMED: Preview 1 works perfectly (1000+ iterations)**
- [x] Third-party reproduction - ✅ **CONFIRMED: Bug reproduced in wasip2_plugins (wasmtime 29)**
- [x] WASM bytecode analysis - ✅ **CONFIRMED: fd_close not imported in P2, IS imported in P1**
- [x] Test different Rust versions - ✅ **CONFIRMED: Regression in 1.93.0, fixed in nightly 1.95.0**
- [ ] File bug report with rust-lang (prepared evidence)
- [ ] Track fix landing in stable (expected 1.95.0 ~March 2026)
- [ ] Inspect Rust std library source (identify exact PR that caused regression)
