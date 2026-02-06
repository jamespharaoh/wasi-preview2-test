use anyhow::{Context, Result};
use wasmtime::component::{Component, Linker, ResourceTable};
use wasmtime::{Config, Engine, Store};
use wasmtime_wasi::{WasiCtx, WasiCtxBuilder, WasiView};

wasmtime::component::bindgen!({
    path: "../target/wasm32-wasip2/release/wasi-component.wit",
    world: "root",
});

struct Host {
    wasi: WasiCtx,
    table: ResourceTable,
}

impl WasiView for Host {
    fn ctx(&mut self) -> wasmtime_wasi::WasiCtxView<'_> {
        wasmtime_wasi::WasiCtxView {
            ctx: &mut self.wasi,
            table: &mut self.table,
        }
    }
}

fn main() -> Result<()> {
    println!("Initializing WASI Preview 2 host...");

    // Configure wasmtime engine with component model support
    let mut config = Config::new();
    config.wasm_component_model(true);
    let engine = Engine::new(&config)?;

    // Set up WASI context
    let mut wasi_ctx = WasiCtxBuilder::new();
    wasi_ctx.inherit_stdio();

    // Preopen the test-data directory (read-only)
    wasi_ctx.preopened_dir(
        "./test-data",
        "/test-data",
        wasmtime_wasi::DirPerms::READ,
        wasmtime_wasi::FilePerms::READ
    )?;

    let wasi = wasi_ctx.build();
    let table = ResourceTable::new();
    let host = Host { wasi, table };

    let mut store = Store::new(&engine, host);

    // Create linker with WASI Preview 2 support
    let mut linker = Linker::new(&engine);
    wasmtime_wasi::p2::add_to_linker_sync(&mut linker)?;

    // Load the component
    let component_path = "./target/wasm32-wasip2/release/wasi-component.wasm";
    println!("Loading component from: {}", component_path);
    let component = Component::from_file(&engine, component_path)
        .context("Failed to load component")?;

    // Instantiate the component using the generated bindings
    println!("Running component...");
    let instance = Root::instantiate(&mut store, &component, &linker)
        .context("Failed to instantiate component")?;

    // Call the run function
    instance.wasi_cli_run()
        .call_run(&mut store)
        .context("Failed to call run function")?
        .map_err(|_| anyhow::anyhow!("Component returned error"))?;

    println!("Component execution completed successfully!");

    Ok(())
}
