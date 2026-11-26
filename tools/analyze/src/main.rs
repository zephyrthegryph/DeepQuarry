//! `analyze`: the one lint engine. Usage: `analyze --help`.

/// The model, the walk store and every walk allocate millions of small values.
#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

fn main() -> std::process::ExitCode {
    dq_analyze::cli::main()
}
