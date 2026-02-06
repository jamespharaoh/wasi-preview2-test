use anyhow::{Context, Result};
use wasmtime::component::{Component, Linker as ComponentLinker, ResourceTable};
use wasmtime::{Config, Engine, Linker, Module, Store};
use wasmtime_wasi::{WasiCtx, WasiCtxBuilder, WasiView};

wasmtime::component::bindgen!({
    path: "../target/wasm32-wasip2/release/wasi-component.wit",
    world: "root",
});

// Host struct for Preview 2 (component model)
struct HostP2 {
    wasi: WasiCtx,
    table: ResourceTable,
}

impl WasiView for HostP2 {
    fn ctx(&mut self) -> wasmtime_wasi::WasiCtxView<'_> {
        wasmtime_wasi::WasiCtxView {
            ctx: &mut self.wasi,
            table: &mut self.table,
        }
    }
}

// Host struct for Preview 1 (classic module)
struct HostP1 {
    wasi: wasmtime_wasi::p1::WasiP1Ctx,
}

fn run_preview1() -> Result<()> {
    println!("Initializing WASI Preview 1 host...");

    // Configure wasmtime engine (no component model for P1)
    let engine = Engine::default();

    // Set up WASI P1 context using the builder
    let mut wasi_builder = wasmtime_wasi::WasiCtxBuilder::new();
    wasi_builder.inherit_stdio();

    // Preopen the test-data directory (read-only)
    wasi_builder.preopened_dir(
        "./test-data",
        "/test-data",
        wasmtime_wasi::DirPerms::READ,
        wasmtime_wasi::FilePerms::READ
    )?;

    let wasi_ctx = wasi_builder.build_p1();
    let host = HostP1 { wasi: wasi_ctx };

    let mut store = Store::new(&engine, host);

    // Create linker with WASI Preview 1 support
    let mut linker = Linker::new(&engine);
    wasmtime_wasi::p1::add_to_linker_sync(&mut linker, |h: &mut HostP1| &mut h.wasi)?;

    // Load the module (not component)
    let module_path = "./target/wasm32-wasip1/release/wasi-component-p1.wasm";
    println!("Loading module from: {}", module_path);
    let module = Module::from_file(&engine, module_path)
        .context("Failed to load module")?;

    // Instantiate and run
    println!("Running module...");
    let instance = linker.instantiate(&mut store, &module)
        .context("Failed to instantiate module")?;

    // Get the _start function (WASI entry point)
    let start = instance.get_typed_func::<(), ()>(&mut store, "_start")
        .context("Failed to get _start function")?;

    start.call(&mut store, ())
        .context("Failed to call _start function")?;

    println!("Module execution completed successfully!");

    Ok(())
}

fn run_preview2() -> Result<()> {
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
    let host = HostP2 { wasi, table };

    let mut store = Store::new(&engine, host);

    // Create linker with WASI Preview 2 support
    let mut linker = ComponentLinker::new(&engine);
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

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();

    let preview = if args.len() > 1 {
        args[1].as_str()
    } else {
        "p2" // Default to Preview 2
    };

    match preview {
        "p1" | "preview1" => run_preview1(),
        "p2" | "preview2" => run_preview2(),
        _ => {
            eprintln!("Usage: {} [p1|p2|preview1|preview2]", args[0]);
            eprintln!("  p1/preview1: Run WASI Preview 1 module");
            eprintln!("  p2/preview2: Run WASI Preview 2 component (default)");
            std::process::exit(1);
        }
    }
}
