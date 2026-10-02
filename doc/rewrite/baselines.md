# Measured baselines

Numbers other work is compared against. Each section says what was measured and how to repeat it.

## Lint run time: the analyze engine versus the Python lints (2026-10)

What ran: every ratchet lint and `check_grep.sh`, on a clean worktree of `origin/master`, Windows 11, 16
logical cores, warm OS file cache.

| Run | Before (Python + shell) | After (`analyze check`) |
|---|---|---|
| `check_ratchets.sh` (about 40 scripts, each re-reading ~5,800 `.dm` files) | about 495 s | |
| `check_grep.sh` (about 70 rg/grep pipelines in sequence) | about 146 s | |
| **Total** | **about 641 s** | |
| Engine, cold (no cache directory, every file read and hashed) | | 4.5 to 4.9 s |
| Engine, warm (nothing changed; no file is read) | | 0.57 s |
| Engine, one `.dm` file changed | | 2.9 to 3.3 s |
| `check_ratchets.sh` end to end (engine, plus the generator checks beside it) | | about 5 s |
| `check_grep.sh` | | 1 to 2 s |

The cold run includes everything: 68 lints (about 1,100 rules), the lint selftests, the
unused-ALLOW check, tree load and cache writes. Cold is 130 times faster than the old total.

Why the incremental run is seconds and not milliseconds: a per-file lint (`scan_file`) re-scans only
the changed file, but the whole-tree lints (cross-file indexes: ownership, schema, the dx family,
`ui_actions`, ...) re-run in full when any file in their scope changes. A run with one file changed does
about 30 CPU-seconds of that work across 16 cores. Getting under a second needs those lints split into
a cached per-file fact pass and a cheap merge; the heaviest are ownership, sys/fields, api,
derived_reads, sys/appearance, sys/sfx, tracked, sys/ui. `analyze timing` lists the cost per lint.

Repeat it:

```text
cargo build --release --manifest-path tools/analyze/Cargo.toml
rm -rf data/analyze-cache && tools/analyze/target/release/analyze check --timing    # cold
tools/analyze/target/release/analyze check --timing                                 # warm
echo "// x" >> code/_helpers/logging/_logging.dm && tools/analyze/target/release/analyze check --timing   # incremental (revert the file)
```

Per-lint wall times of the old run (seconds): sys_lint 139, api_lints 61, ownership 42, state_schema 39,
lifecycle 33, scheduler 30, lifecycle_counts 23, containment 21, system_boundary 20, spatial 19,
base_vars 18, dcs 18, tracked 18, qdel_src 17, and about 25 more between 1 and 15.

## Semantic layer (E5, 2026-10)

What ran: `tools/analyze` with the E5 semantic layer (`src/sem/`, three `sem/*` lints, two generators) against the same
tree without it, 4 interleaved rounds each, Windows 11, other agents' builds running on the machine (so read the spread,
not the digit). `bash tools/ci/check_ratchets.sh` is unchanged in shape and runs `analyze gen --check` after the lints.

| Run (`analyze check --ci --lint -check_grep`) | Before (master) | After (E5) |
|---|---|---|
| Cold (no cache directory) | 3.8 to 4.2 s | 4.1 to 4.3 s |
| Warm (nothing changed) | 0.67 to 0.74 s | 0.67 to 0.80 s |
| One `.dm` file changed | 3.3 to 3.6 s | 3.5 to 3.8 s |

The semantic lints cost a scan, never a parse, until a declaration names a handler (the tree declares none yet):

| Piece | Time |
|---|---|
| `sem/keys`, `sem/handlers`, `sem/reads` after a one-file edit (alone, with the tree load) | 0.66 s wall (keys 0.12 s, handlers 0.15 s, reads 0.11 s) |
| `Decls::get` (markers, relations, tracked vars, `#define` names; per file, parallel) | 0.17 s |
| `Sem::build_partial` (10 files plus `code/__defines/**`) | 0.15 s |
| `Sem::build` (the whole tree with proc bodies, once a declaration names a handler) | 7 to 8 s |
| `analyze sem oracle` / `cargo test --test oracle` (full model plus 20 handlers) | 8 to 10 s |

The target of section 19, "one-file incremental analysis within 5 s", holds for the new checks alone (0.7 s) and for the whole
engine (3.5 to 3.8 s). Until content converts and the full model is needed, nothing here parses. When it is, a one-file edit
re-parses (7 to 8 s) unless the handler result cache lands: the incremental compiler's front end is the intended fix
(it replaces dreammaker behind `Sem`), not a cache of dreammaker's tree. The stretch goal of splitting the heaviest cross-file
lints into a cached per-file pass plus a merge is not done: the one-file engine run is still about 25 CPU-seconds in
ownership (2.4 s alone), sys/fields (1.2 s), sys/ui (1.0 s), api, system_boundary, derived_reads (0.7 to 0.9 s each).

**The reads spike.** 20 real handlers (4 tgui_data, 5 conditions, 5 draws, 6 Rust pushes): the generated reads contain every
read in the hand-written lists for 20 of 20; no handler needs a `READS_AS`. Five atmos push lists also name the token
`rust_device_rev`, which is not a read (reported apart in `tools/analyze/oracle/spike.toml`). Twelve of the 20 bodies call 27 global
helpers with no `READS_FROM`; the final design makes each one an `unannotated_global` error. The list is pinned as a shrink-only
ratchet in `spike.toml`.

