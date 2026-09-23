# auxmos (vendored)

Vendored from [Putnam3145/auxmos](https://github.com/Putnam3145/auxmos) for use
in DeepQuarry as the Rust backend for /tg/-lineage LINDA atmospherics.

## Pinned commit

- **Commit**: `7757b8eb677796fc3b184768cfe83e91f5b92cba`
- **Date**: 2025-01-04
- **Message**: "update deps"
- **Version**: 2.3.0

## DQ-specific modifications

The following changes were made when vendoring. They are tagged in the source
with `DQEdit` comments where modifications are inline.

1. **`Cargo.toml`**:
   - Removed `[workspace]` section — the crate is a member of the verdigris
     workspace at `verdigris/Cargo.toml`, as `vg-gas` in `verdigris/domains/gas`.
     Upstream's `crates/auxcallback` and `crates/auxmacros` moved to
     `verdigris/ffi/callback` and `verdigris/ffi/macros` (they are FFI plumbing).
   - Removed `[workspace.dependencies]` — those entries (`byondapi`,
     `coarsetime`, `flume`, `eyre`, `tracing`) were hoisted to
     `verdigris/Cargo.toml [workspace.dependencies]` so the sub-crates'
     `{ workspace = true }` declarations still resolve.
   - `[lib] crate-type = ["cdylib"]` → `["rlib"]`. It links into the
     verdigris DLL, so BYOND loads one library.
   - Removed `mimalloc` dependency. The global allocator is set in the
     verdigris cdylib crate.
   - Removed `[profile.release] panic = "abort"`. Verdigris uses the default
     `unwind` strategy so `panic_safe` can catch panics across the FFI
     boundary.
   - Features narrowed to `turf_processing`, `superconductivity`, `zas_hooks`
     and `tracy`. Verdigris enables `turf_processing` + `superconductivity`.

2. **`src/lib.rs`**: removed the `#[global_allocator] static GLOBAL: mimalloc::MiMalloc`
   declaration. A cdylib can have only one global allocator; verdigris owns
   that choice. Also removed the `generate_binds` test that wrote a
   `bindings.dm`; DeepQuarry never included it.

3. **Removed upstream solvers and reactions** (fixes.md DEAD1): the equalization
   solvers (`turfs/monstermos.rs`, `turfs/putnamos.rs`) and their feature flags,
   and the Rust-side reaction sets (`reaction/citadel.rs`, `reaction/yogs.rs`,
   the `reaction_hooks` feature). Turf diffusion and decompression run in
   `turfs/processing.rs`; reactions run in DM.

4. **Files removed** (vendor cleanup):
   - `.git/` — vendored, not a submodule
   - `.github/` — upstream CI not applicable to our workspace
   - `.editorconfig`, `.gitattributes` — defer to repo-root settings
   - `docs/` — not needed for vendored use
   - `Cargo.lock` — workspace produces a unified lock at `verdigris/Cargo.lock`
   - `bindings.dm` — generated, never included by DeepQuarry

5. **Files kept**:
   - `LICENSE` (MIT — required by the license)
   - `README.md` — upstream context, still useful for orientation
   - `.gitignore`, `.rustfmt.toml` — local conventions

6. **Adjacency and gas IDs (M1a)**: turf adjacency is built in Rust from
   DM air-block masks (`turfs.rs`, `AirCells`) instead of DM's per-turf
   `atmos_adjacent_turfs` lists, and gases have fixed numeric IDs
   (`gas/ids.rs`) instead of string lookups.

7. **The rewrite (M1b)**: the gas arena and its locks, the async turf worker
   (`turfs/processing.rs`), `TurfGases`/`MIX_TO_TURF` (`turfs.rs`) and
   `PipeTopology` (`pipenets.rs`) are deleted. Turf gas runs on vg-core's
   field framework (`cell.rs`), pipes on its network framework (`pipes.rs`),
   and the gas world (`world.rs`) owns every mixture. What remains from auxmos
   is the mixture maths (`gas/mixture.rs`), the gas registry (`gas/types.rs`),
   the reaction registry (`reaction.rs`) and the gas-string parser.

The source has diverged from upstream past any merge; treat it as DeepQuarry
code, not a patch set. Do not bump it from upstream.
