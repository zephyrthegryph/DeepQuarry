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
