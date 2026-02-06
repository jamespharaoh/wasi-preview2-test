<!--
Title: wasm32-wasip2: fd_close missing from compiled component in 1.93.0, causing file descriptor leak
-->

Rust 1.93.0 stable produces `wasm32-wasip2` components that are missing the `fd_close` import from `wasi_snapshot_preview1`. File descriptors are never released when `File` is dropped, exhausting the WASI resource table after ~100–125 file operations.

The regression is **release-branch-specific**: every nightly version tested — including 1.93.0-nightly — works correctly. The bug was never on master, pointing to a bad cherry-pick or backport to the 1.93 release branch.

### Code

I tried this code (compiled with `--target wasm32-wasip2`):

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

I expected to see this happen: All 1000 iterations complete successfully. Dropping a `File` should release the underlying WASI file descriptor, as it does when compiled with 1.92.0 or any nightly.

Instead, this happened: The program fails after ~100–125 iterations with:

```
Error: Os { code: 48, kind: OutOfMemory, message: "Out of memory" }
```

Error code 48 is WASI's "too many open files". Inspecting the compiled WASM confirms that the `fd_close` import is absent:

```bash
# 1.93.0 — missing
$ wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | grep fd_close
# (no output)

# 1.92.0 — present
$ wasm-tools print target/wasm32-wasip2/release/wasi-component.wasm | grep fd_close
(import "wasi_snapshot_preview1" "fd_close" (func $__imported_wasi_snapshot_preview1_fd_close ...))
```

The `wasm32-wasip2` std uses a hybrid approach where Rust calls Preview 1 functions (`path_open`, `fd_read`, `fd_close`) which are bridged to Preview 2 by an adapter embedded in the component. In 1.93.0 the `fd_close` import is absent, so dropping a `File` never closes the underlying descriptor. Each open accumulates ~2 resource table entries until the ~250-entry limit is hit.

### Version it worked on

It most recently worked on: Rust 1.92.0

Every nightly version tested across a 4-month range (September 2025 – January 2026) also works, including 1.93.0-nightly (`nightly-2025-11-18`). The bug was never on master.

### Version with regression

`rustc --version --verbose`:

```
rustc 1.93.0 (254b59607 2026-01-19)
binary: rustc
commit-hash: 254b59607d4417e9dffbc307138ae5c86280fe4c
commit-date: 2026-01-19
host: x86_64-unknown-linux-gnu
release: 1.93.0
LLVM version: 21.1.8
```

### Backtrace

Not applicable — this is not a compiler crash. The compiler succeeds but produces a component with a missing import.

### Tested versions

| Version | `fd_close` | Runtime |
| --- | --- | --- |
| 1.92.0 stable | present | pass |
| nightly-2025-09-18 (1.92.0) | present | pass |
| nightly-2025-11-18 (1.93.0) | present | pass |
| nightly-2025-12-29 (1.94.0) | present | pass |
| nightly-2026-01-18 (1.94.0) | present | pass |
| **1.93.0 stable** | **missing** | **fail** |

### Reproduction repository

Full reproduction case with one-command script, automated comparison, and detailed investigation notes:

https://github.com/TODO/wasi-preview2-test

```bash
git clone https://github.com/TODO/wasi-preview2-test
cd wasi-preview2-test
./scripts/reproduce.sh    # builds with 1.92.0 and 1.93.0, compares imports, runs both
```

### Workaround

Use Rust 1.92.0, any nightly, or wait for 1.94.0 stable.

@rustbot modify labels: +regression-from-stable-to-stable -regression-untriaged
