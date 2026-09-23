# Verdigris

In-tree Rust extension for DeepQuarry. BYOND loads it through `call_ext`
([`byondapi`](https://crates.io/crates/byondapi)); the DM side calls
`VERDIGRIS_CALL("name", args...)`, which resolves to a bound function in this
crate.

## Workspace layout

This directory is a Cargo workspace that produces one `libverdigris.so` /
`verdigris.dll`, so BYOND only ever loads one library. The target structure is
described in `doc/rewrite/rust_core.md`.

```
verdigris/                  <- workspace root (this dir)
├── Cargo.toml              <- [workspace] + shared deps and profiles
├── Cargo.lock              <- committed (we produce a final cdylib)
├── rust-toolchain.toml     <- stable + i686 targets
├── build-linux.sh / build-windows.sh
├── core/                   <- vg-core: domain-agnostic primitives (grid, ...).
│                              Host-buildable, no byondapi, no global statics.
├── domains/
│   ├── gas/                <- vg-gas: vendored auxmos (gas arena, turf diffusion,
│   │                          heat); i686 only until its binds move to vg-ffi.
│   │                          See domains/gas/UPSTREAM.md.
│   └── layout/             <- vg-layout: station layout planner, cave generator,
│                              and the offline station-layout tools (src/bin/)
├── ffi/                    <- vg-ffi: BYOND binds (lifecycle, layout, cave gen)
│   │                          and the tracking allocator; i686 only
│   ├── macros/             <- auxmacros: #[panic_safe] bind attribute
│   └── callback/           <- auxcallback: deferred callbacks to the main thread
├── verdigris/              <- the DLL: links vg-ffi + vg-gas, sets the global
│                              allocator; still holds material_power.rs
└── tools/bench/            <- vg-bench: criterion benchmarks
```

## Modules

| Crate / module | Purpose |
|---|---|
| `vg-ffi` `lifecycle` | `verdigris_init`, `cleanup`, version/feature metadata, allocator diagnostics. |
| `vg-layout` `random_map` | Cellular-automata cave generator used by expedition sites. |
| `vg-layout` `station_layout` | Generated-station layout planner and its planning jobs. |
| `verdigris` `material_power` | Double-precision electrical solve for material-engineering power networks. |
| `vg-ffi` `allocator` | Tracking allocator that reports live Rust memory to the profiler. |
| `vg-gas` | Gas arena, turf diffusion, decompression and heat conduction. Reactions stay in DM; see `code/ATMOSPHERICS/README.md`. |
| `vg-core` `grid` | Bounds-checked turf-index neighbour arithmetic. |

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

### Binaries

`libverdigris.so` and `verdigris.dll` are build outputs and are gitignored.
`bin/build.cmd` and `tools/build/build.sh` build them, and CI builds them from
source.

### Tests

```bash
cd verdigris
cargo fmt --all --check
cargo test                                            # host crates, in parallel
cargo test --target i686-pc-windows-msvc -p vg-gas    # gas (or i686-unknown-linux-gnu)
cargo bench -p vg-bench                               # criterion benchmarks
```

A plain `cargo test` builds the default members (`vg-core`, `vg-layout`,
`verdigris`, `vg-bench`) for the host. `vg-gas`, `vg-ffi` and `auxcallback`
depend on byondapi, which is 32-bit only, so they build and test on the i686
targets only.

## The rules

These exist because their absence will crash the server in production.

### Rule 1 — Mark every bind `#[auxmacros::panic_safe]`

```rust
#[byondapi::bind("/proc/foo")]
#[auxmacros::panic_safe]
fn foo(x: ByondValue) -> eyre::Result<ByondValue> {
    // body
}
```

A Rust panic unwinding across the BYOND FFI boundary is undefined behaviour and
crashes DreamDaemon with no DM-side stack. The attribute wraps the body in
`catch_unwind` and turns a panic into an error that surfaces as a DM runtime.
The bound function must return `eyre::Result<ByondValue>`. Every bind in this
workspace uses the same attribute.

### Rule 2 — No strings in hot paths

Every FFI call costs microseconds (byondapi marshalling). String allocations
across the boundary compound that:

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

Every DM datum that holds an arena handle (gas mixtures, material power
graphs) must release it on `Destroy()`.

### Rule 5 — Single-threaded BYOND, multi-threaded Rust

The BYOND VM is single-threaded. `rayon` is fine *inside* Rust between FFI
calls. **Never** hold a `ByondValue`, call into DM, or read DM state from a
worker thread. The pattern for "Rust needs DM to do something" is a callback
queue that DM drains on the main thread (see `auxcallback::byond_callback_sender`).

## CI

- `run_integration_tests.yml` builds verdigris from source on every PR
  (`bash verdigris/build-linux.sh`), with a Swatinem rust-cache.
- `run_linters.yml` runs `cargo fmt --check`, `cargo clippy -D warnings`, and
  `cargo test`.

## Build-info

`ffi/build.rs` invokes [`bosion`](https://crates.io/crates/bosion) to capture the
git short-hash at build time; `verdigris_version()` returns `verdigris v0.1.0
(abc1234)` which DM can compare against an expected pin if needed.
