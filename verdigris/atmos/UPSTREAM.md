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
   - Removed `[workspace]` section — `auxmos` is now a member of the
     verdigris top-level workspace at `verdigris/Cargo.toml`. `auxcallback`
     and `auxmacros` are also workspace members there.
   - Removed `[workspace.dependencies]` — those entries (`byondapi`,
     `coarsetime`, `flume`, `eyre`, `tracing`) were hoisted to
     `verdigris/Cargo.toml [workspace.dependencies]` so the sub-crates'
     `{ workspace = true }` declarations still resolve.
   - `[lib] crate-type = ["cdylib"]` → `["rlib"]`. Auxmos links into
     `libverdigris.so` (Q4: one library).
   - Removed `mimalloc` dependency. The global allocator is set in the
     verdigris cdylib crate (or the system default applies).
   - Removed `[profile.release] panic = "abort"`. Verdigris uses the default
     `unwind` strategy so `panic_safe!` can catch panics across the FFI
     boundary.
   - Default features narrowed to `["turf_processing"]` (was
     `["turf_processing", "katmos"]`). Verdigris enables the katmos +
     katmos_slow_decompression set explicitly via its dep config.

2. **`src/lib.rs`**: removed the `#[global_allocator] static GLOBAL: mimalloc::MiMalloc`
   declaration. A cdylib can have only one global allocator; verdigris owns
   that choice.

3. **`src/turfs/katmos.rs:449`**: bugfix — `cur_mixture.clear_vol(...)` →
   `cur_mixture.clear_moles(...)`. The `clear_vol` method does not exist on
   `TurfMixture`; rustc suggests `clear_moles` and the variable name
   (`_average_moles`) confirms the intent. The branch only fires under
   `katmos_slow_decompression`, which we enable, so this previously didn't
   trip upstream's CI. Upstream this when convenient.

4. **Files removed** (vendor cleanup):
   - `.git/` — vendored, not a submodule
   - `.github/` — upstream CI not applicable to our workspace
   - `.editorconfig`, `.gitattributes` — defer to repo-root settings
   - `docs/` — not needed for vendored use
   - `Cargo.lock` — workspace produces a unified lock at `verdigris/Cargo.lock`

5. **Files kept**:
   - `LICENSE` (MIT — required by the license)
   - `README.md` — upstream context, still useful for orientation
   - `.gitignore`, `.rustfmt.toml` — local conventions
   - All source files unchanged except `src/lib.rs` (see #2)

## Updating

To bump auxmos:

1. Note the old commit hash from this file.
2. In a fresh checkout: `git clone https://github.com/Putnam3145/auxmos /tmp/auxmos-new`.
3. `rsync -a --delete /tmp/auxmos-new/ verdigris/atmos/` (excluding our
   `UPSTREAM.md`).
4. Re-apply the modifications above (or check `git diff` to spot
   regressions in already-applied modifications).
5. Update the pinned commit hash and version in this file.
6. Run the test suite: `cd verdigris && cargo test`.

The DM-side gas-mixture API is sensitive to auxmos's internal mixture
representation. After any bump, run a full atmos integration test before
merging.
