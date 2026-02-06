# WASI Preview 2 fd_close Regression — Rust 1.93.0

Minimal reproduction of a release-specific regression where `wasm32-wasip2`
components compiled by Rust 1.93.0 stable are missing the `fd_close` import,
causing file descriptor leaks.

## Key facts

- **Bug**: Missing `fd_close` in compiled WASM for wasm32-wasip2
- **Affected**: Only Rust 1.93.0 stable (254b59607, Jan 19 2026)
- **Not affected**: All nightlies, 1.92.0 and earlier, 1.94.0-beta
- **Cause**: Bad cherry-pick/backport to 1.93 release branch (never on master)
- **Symptom**: File operations fail after ~100-125 iterations with error code 48

## Build & run

```bash
# Reproduce the bug
./scripts/reproduce.sh

# Or manually:
rustup run 1.93.0 cargo build --release -p wasi-component --target wasm32-wasip2
wasmtime run --dir ./test-data::/test-data target/wasm32-wasip2/release/wasi-component.wasm

# Verify fd_close is missing:
wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | grep fd_close
```

## Project layout

- `component/` — wasm32-wasip2 component (the reproduction)
- `component-p1/` — wasm32-wasip1 module (comparison, works correctly)
- `host/` — Custom wasmtime host supporting P1 and P2
- `scripts/` — Reproduction and testing scripts
- `notes/` — Investigation history
- `.cargo/config.toml` — Sets default target to wasm32-wasip2
