# Verdigris

In-tree Rust extension for DeepQuarry (CHOMPStation2 fork). Loaded by BYOND via
[`meowtonin`](https://crates.io/crates/meowtonin)'s `call_ext`-style FFI; the DM
side calls `VERDIGRIS_CALL("name", args...)` and resolves to a `#[byond_fn]` on
this crate.

## Workspace layout

This directory is a Cargo workspace. One combined `libverdigris.so` /
`verdigris.dll` cdylib is produced; auxmos vendors in as an `rlib` (Phase 1.1b)
and re-exports through this crate so BYOND only ever loads one library.

```
verdigris/                  ← workspace root (this dir)
├── Cargo.toml              ← [workspace] + shared profiles
├── Cargo.lock              ← committed (we produce a final cdylib)
├── rust-toolchain.toml     ← stable + i686 targets
├── build-linux.sh          ← bash verdigris/build-linux.sh (from repo root)
├── build-windows.sh
├── verdigris/              ← member crate, produces the cdylib
│   ├── Cargo.toml
│   ├── build.rs
│   └── src/
│       ├── lib.rs          ← #[byond_fn]s + atmos re-exports
│       ├── panic.rs        ← panic_safe! macro + hook
│       ├── random_map.rs   ← cellular-automata cave gen
│       └── verdigris.rs    ← version/init/cleanup metadata
└── atmos/                  ← (Phase 1.1b) vendored auxmos as rlib
```

## Modules

| Module | Purpose |
|---|---|
| `verdigris` | Lifecycle: `verdigris_init`, `cleanup`, version/feature metadata. |
| `panic` | `panic_safe!` macro + global hook. **Every FFI entry point must use this** — see below. |
| `random_map` | Cellular-automata cave generator used by `SSquarry`. |

Planned (Phase 1.1b–1.1c, via the `atmos` workspace member vendored from
[auxmos](https://github.com/Putnam3145/auxmos)):

1. `atmos::gas` — gas mixture arena, mixture math, gas registry.
2. `atmos::turfs` — LINDA turf graph (`StableDiGraph`) processing, FDM share, monstermos-style equalisation.
3. `atmos::reactions` — gas reaction rules + reaction queue. Initially **disabled** in favor of a DQ-specific reaction set mirroring XGM combustion (see `modular_dq/doc/atmos_migration.md` decision §6).

See `modular_dq/doc/atmos_migration.md` for the staged plan.

## Building

```bash
# Linux (i686 — must match BYOND's 32-bit ABI)
bash verdigris/build-linux.sh

# Windows (cross-compile or native MSVC)
bash verdigris/build-windows.sh
```

Both scripts `cd` into the crate, run `cargo build --release --target i686-*`,
and copy the resulting `libverdigris.so` / `verdigris.dll` to the repo root
where DreamDaemon finds it.

### Toolchain

Pinned in `rust-toolchain.toml`: stable channel, with `rustfmt`, `clippy`, and
the two i686 targets. `rustup` reads this automatically — no manual setup
beyond installing rustup itself.

MSRV is 1.85 (edition 2024).

### Committed binaries (cleanup follow-up)

`libverdigris.so` and `verdigris.dll` are currently committed to git so
DM-only contributors don't need `rustup` installed. **CI now builds from
source on every PR**, so the committed binaries are no longer required —
remove them with `git rm --cached` once the team is ready to require rustup
locally (DM-only contributors can still run the server, they just can't
rebuild the lib).

## The rules

These exist because their absence will crash the server in production.

### Rule 1 — Wrap every `#[byond_fn]` body in `panic_safe!`

```rust
#[byond_fn]
pub fn foo(x: ByondValue) -> ByondResult<ByondValue> {
    panic_safe!({
        // your body here
    })
}
```

A Rust panic unwinding across the BYOND FFI boundary is UB — it will SIGSEGV
DreamDaemon with no DM-side stack. `panic_safe!` catches and converts to a
`ByondError` that surfaces as a DM runtime, plus logs the panic to stderr.

The hook is installed lazily on first `panic_safe!` invocation and eagerly via
`verdigris_init()` (called from `/world/New()` in `_verdigris.dm`).

### Rule 2 — No strings in hot paths

Every FFI call costs microseconds (byondapi marshalling). String allocations
across the boundary compound that. Once atmos lands:

- Gas IDs are `u8`, never strings, after one-time registration at boot.
- Turf handles are `usize` arena indices, never datum paths.
- Lists returned to DM should be `Vec<f32>` / `Vec<i32>`, not `Vec<String>`.

### Rule 3 — Cross the boundary once per batch, not once per element

DM is the loop owner; Rust is the work unit. The pattern is:

- DM gathers a batch (e.g. "these are the 47 active turfs this tick"),
- one FFI call passes the batch to Rust,
- Rust does the heavy lifting (possibly with `rayon`),
- one FFI call returns aggregate results (or queues callbacks for later drain).

Never loop in DM calling a Rust per-tile getter inside.

### Rule 4 — Destroy() discipline

Once we have an arena (gas mixtures, turf graph, etc.), every DM datum that
holds an arena handle must release it on `Destroy()`. A CI integration test
should assert `gasmix_count_live() == 0` after teardown.

### Rule 5 — Single-threaded BYOND, multi-threaded Rust

The BYOND VM is single-threaded. `rayon` is fine *inside* Rust between FFI
calls. **Never** hold a `ByondValue`, call into DM, or read DM state from a
worker thread. The pattern for "Rust needs DM to do something" is a callback
queue that DM drains on the main thread (see auxmos's `byond_callback_sender`).

## CI

- `run_integration_tests.yml` builds verdigris from source on every PR
  (`bash verdigris/build-linux.sh`), with a Swatinem rust-cache.
- `run_linters.yml` runs `cargo fmt --check`, `cargo clippy -D warnings`, and
  `cargo test`.

## Build-info

`build.rs` invokes [`bosion`](https://crates.io/crates/bosion) to capture the
git short-hash at build time; `verdigris_version()` returns `verdigris v0.1.0
(abc1234)` which DM can compare against an expected pin if needed.
