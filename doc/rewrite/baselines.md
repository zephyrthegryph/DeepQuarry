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

## Incremental engine (2026-10)

What ran: `analyze check` (every lint but nothing excluded) on a worktree of master after the semantic layer gained handlers (65
declared handlers, so the full model parses on every cold run), Windows 11, Ryzen 7 5800X (8 cores, 16 threads), warm OS file
cache, a game running on the same machine (read the spread, not the digit). Wall time of the whole process, `cpu` is process CPU.

| Run | Before (master) | After |
|---|---|---|
| Cold (no cache directory) | 14.3 to 17.4 s wall, 69 to 72 s cpu | 17.0 to 18.1 s wall, 80 s cpu |
| Warm (nothing changed) | 0.74 to 0.97 s wall, 4.1 s cpu | 0.19 to 0.21 s wall, 0.57 s cpu |
| One `.dm` file edited, comment (20 runs, appended line each) | 15.1 to 17.0 s wall, 44 to 49 s cpu | average 0.73 s, median 0.73 s, range 0.57 to 1.20 s; 3.2 s cpu |
| One `.dm` file edited, code (a proc body expression; a var's initial value; 16 runs) | about 16 s | 0.56 to 0.84 s |
| A proc or var added or removed (declarations change) | about 16 s | 11.7 to 12.9 s (the full semantic model runs) |

A run on a loaded machine shows outliers (1.4 to 5 s) that are disk stalls writing the cache (about 23 MB in 148 files per edit),
not engine work. The cold run is about 20 % slower than before: it parses once, then also writes the per-file stores, the
semantic record and the generator output. The `check_ratchets.sh` end to end is 5.6 s warm (the two Python generator checks take
most of it) and 35 s cold; `analyze gen --check` is 3.5 s warm instead of 8 to 27 s.

How a one-file edit is now answered: every whole-tree lint is facts (per file, cached by content) plus a merge plus a per-file
judgement cached under the key of what was merged (`src/incr.rs`), so the edited file is re-read and re-judged and a lint whose
facts did not change re-judges nothing else. The semantic lints reuse their stored results (and the `reads` generator its stored
text) when the edited file is outside the 18-file footprint of the handler analysis and leaves the structure (declarations,
parameter lists, written names) alone, or only changes comments (`src/sem/incremental.rs`: no parse), or is parsed alone with the
defines (about 0.15 s). Details and the exact reuse rule are in `tools/analyze/README.md`.

Not achieved: an edit that changes the structure (adds or removes a var or proc, renames a parameter), touches a footprint file, or
changes a `#define` still runs the full 8 to 12 s model; the cold run is not faster; sem results are reused whole, not
merged from per-file parse fragments (dreammaker's `ObjectTree` has no per-file form).

Repeat it: `bash` with `tools/analyze/target/release/analyze.exe` built (`cargo build --release --manifest-path tools/analyze/Cargo.toml`):
`rm -rf data/analyze-cache; analyze check` (cold), `analyze check` twice (warm), then `echo "// x" >> <a .dm file with no #define>; analyze check` repeatedly.
`DQ_ANALYZE_TRACE=1` prints the phase times, `DQ_ANALYZE_TRACE_SPANS=1` each lint's span.

## Semantic layer (E5, 2026-10)

What ran: `tools/analyze` with the E5 semantic layer (`src/sem/`, three `sem/*` lints, two generators) against the same
tree without it, 4 interleaved rounds each, Windows 11, other agents' builds running on the machine (so read the spread,
not the digit). `bash tools/ci/check_ratchets.sh` is unchanged in shape and runs `analyze gen --check` after the lints (since October 2026 it runs `analyze gen` before them: the output is not committed, doc/rewrite/agent_workflow.md).

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

