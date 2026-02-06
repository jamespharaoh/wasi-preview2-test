# Missing `fd_close` in wasm32-wasip2: Rust 1.93.0 regression

Rust 1.93.0 stable produces `wasm32-wasip2` components that are missing the
`fd_close` import from `wasi_snapshot_preview1`. File descriptors are never
released, exhausting the WASI resource table after ~100-125 file operations.

The bug is **release-specific**: it only exists in 1.93.0 stable (254b59607).
Every nightly version tested (including 1.93.0-nightly) works correctly.
This points to a bad cherry-pick or backport to the 1.93 release branch.

## Quick reproduction

```bash
./scripts/reproduce.sh
```

This builds the same component with Rust 1.92.0 and 1.93.0, compares the
WASM imports, and runs both. Requires `rustup`, `wasmtime`, and `wasm-tools`.

### Manual reproduction

```bash
# Build the component with Rust 1.93.0
rustup run 1.93.0 cargo build --release -p wasi-component --target wasm32-wasip2

# The compiled WASM is missing fd_close:
wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | grep fd_close
# (no output)

# Run it - fails after ~100-125 iterations:
wasmtime run --dir ./test-data::/test-data target/wasm32-wasip2/release/wasi-component.wasm
# Error: Os { code: 48, kind: OutOfMemory, message: "Out of memory" }
```

Compare with 1.92.0:

```bash
rustup run 1.92.0 cargo build --release -p wasi-component --target wasm32-wasip2

wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | grep fd_close
# (import "wasi_snapshot_preview1" "fd_close" (func ...))  <-- present

wasmtime run --dir ./test-data::/test-data target/wasm32-wasip2/release/wasi-component.wasm
# All 1000 iterations completed successfully!
```

## The component

Both `component/` (wasm32-wasip2) and `component-p1/` (wasm32-wasip1) contain
identical code - a loop that opens a file, reads 64 bytes, and drops it:

```rust
use std::fs::File;
use std::io::{self, Read};

fn main() -> io::Result<()> {
    for i in 1..=1000 {
        {
            let mut file = File::open("/test-data/test.txt")?;
            let mut buf = [0u8; 64];
            let _ = file.read(&mut buf)?;
        } // file is dropped here
        if i % 100 == 0 { println!("Completed {} iterations", i); }
    }
    println!("All 1000 iterations completed successfully!");
    Ok(())
}
```

## Root cause

The `wasm32-wasip2` target uses a hybrid approach: Rust's std calls WASI
Preview 1 functions (`path_open`, `fd_read`) which are bridged to Preview 2
by an adapter layer embedded in the component. In working versions, `fd_close`
is also imported and called when `File` is dropped:

```
Working (1.92.0):  path_open → fd_read → fd_close → cleanup
Broken  (1.93.0):  path_open → fd_read → (no fd_close) → leak
```

Each `File::open` creates ~2 entries in the WASI resource table (a file
descriptor and an input stream). Without `fd_close`, these accumulate until
the table limit (~250 resources) is reached, causing error code 48 ("too
many open files", reported as "Out of memory").

## Affected versions

| Version | Released | Result | `fd_close` |
|---------|----------|--------|------------|
| 1.92.0 stable | Dec 8, 2025 | PASS | present |
| nightly-2025-09-18 | — | PASS | present |
| nightly-2025-11-18 (1.93.0-nightly) | — | PASS | present |
| nightly-2025-12-29 (1.94.0-nightly) | — | PASS | present |
| nightly-2026-01-18 (1.94.0-nightly) | — | PASS | present |
| **1.93.0 stable** | **Jan 19, 2026** | **FAIL** | **missing** |

All 10+ nightly versions tested across a 4-month range work correctly.
Only 1.93.0 stable is affected.

## Workaround

- Use Rust 1.92.0: `rustup default 1.92.0`
- Use nightly: `rustup default nightly`
- Wait for Rust 1.94.0 stable

## Prerequisites

- [rustup](https://rustup.rs) with Rust 1.93.0 and `wasm32-wasip2` target
- [wasmtime](https://wasmtime.dev/) (tested with 41.0)
- [wasm-tools](https://github.com/bytecodealliance/wasm-tools) (for import inspection)

## Project structure

```
component/       wasm32-wasip2 component (exhibits the bug in 1.93.0)
component-p1/    wasm32-wasip1 module (works correctly, for comparison)
host/            Custom wasmtime host supporting both P1 and P2
test-data/       Test file read by the components
scripts/
  reproduce.sh       One-command reproduction
  compare-imports.sh  Show P1 vs P2 imports side by side
  test-rust-version.sh  Test a specific Rust version
  bisect-test.sh     For use with cargo-bisect-rustc
notes/           Detailed investigation history
```

## Additional scripts

Test any Rust version:
```bash
./scripts/test-rust-version.sh 1.92.0   # PASS
./scripts/test-rust-version.sh 1.93.0   # FAIL
```

Compare P1 vs P2 imports (requires both targets built):
```bash
./scripts/compare-imports.sh
```

## System information

```
Affected:   rustc 1.93.0 (254b59607 2026-01-19), target wasm32-wasip2
Tested on:  wasmtime 41.0.1, wasm-tools 1.244.0, Linux x86_64
```

## Investigation notes

The `notes/` directory contains the full investigation trail:

1. [Version check](notes/01-version-check.md) — initial environment
2. [Adapter layer](notes/02-adapter-layer-investigation.md) — P1→P2 bridge analysis
3. [Third-party reproduction](notes/03-third-party-reproduction.md) — confirmed in independent code
4. [WASM import analysis](notes/04-wasm-import-analysis.md) — the missing `fd_close`
5. [Version regression](notes/05-rust-version-regression.md) — bisection to 1.93.0
6. [Release bisection](notes/06-rust-bisection.md) — confirmed never on master
