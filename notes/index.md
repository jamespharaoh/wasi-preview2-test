# Investigation Notes

This directory contains detailed notes from investigating the WASI Preview 2 resource leak issue.

## Notes

1. **[01-version-check.md](01-version-check.md)** - Verified we're using latest stable versions of wasmtime (41.0.3) and related crates. The resource leak is present in the current stable release.

## Summary of Findings So Far

- ✅ Using latest stable: wasmtime 41.0.3, Rust 1.93.0
- ❌ Resource leak confirmed: Files exhaust ~250 resource limit after ~100-125 iterations
- 🔍 Issue persists despite proper Rust RAII (files dropped at end of scope)

## Investigation Status

- [x] Version verification - Using latest stable versions
- [ ] GitHub issue search
- [ ] WASM inspection for cleanup calls
- [ ] Resource table debugging
- [ ] Alternative patterns testing
