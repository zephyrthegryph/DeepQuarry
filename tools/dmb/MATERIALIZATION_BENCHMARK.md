# Compiler materialization measurements

`materialization_bench` measures frontend preparation, DMB construction from symbolic lowering artifacts, reference validation, binary encoding, DMB/RSC pair validation, and durable publication separately. It intentionally bypasses coordinator output receipts and retained linked worlds. Repeated identical cases must produce identical output hashes.

From `tools/dmb`:

```powershell
cargo run -j1 -p dm-compile --example materialization_bench -- --output E:/temp/dmb-materialization-new --byond 'C:/Program Files (x86)/BYOND/bin/dm.exe'
cargo run -j1 -p dm-compile --example materialization_bench -- --output E:/temp/dmb-six-new --six-worktrees
```

Output directories must be new. The default uses a small fixture and exercises add-procedure, add-variable, and changed-default cases. Six-worktree mode uses six fixtures with at most two concurrent jobs and a shared cache. Real-project runs require explicit `--project` paths; use isolated worktrees, since native compilation writes adjacent outputs. For six real worktrees, supply six `--project` arguments. Defines use `-DNAME` or `-DNAME=value`. Omit `--byond` to report native timings as unavailable. This never launches DreamDaemon.

Cache hit/miss counts are measured, not assumed: bounded namespace snapshots may omit historical records. A nonzero cached-baseline miss count is reported with a warning rather than interpreted as a correctness failure.

## Macro history

```powershell
./scripts/audit-macro-history.ps1 -ProjectRoot ../.. -CommitLimit 50 -FanoutLimit 20 -Output ./target/macro-history.json
```

This read-only audit compares complete multiline definitions against each commit's first parent. Fanout is current lexical occurrence count, including inactive source, comments, and strings; it does not claim semantic dependency coverage. The report records its revision, sample size, and method. The default history sample follows first-parent game commits and excludes tooling; pass `-IncludeTooling` to include compiler fixtures.

Every measurement also performs a separate catalog reuse pass: it reconstructs
canonical DMB from symbolic artifacts while publishing the independently verified
existing RSC. The report distinguishes this from the full archive rebuild pass.
The catalog pass must produce the identical DMB and no new RSC payload.

For a real project, prepare a private input mirror first:

```powershell
./scripts/prepare-materialization-mirror.ps1 -ProjectRoot ../.. -MirrorRoot ./target/materialization-input -GeneratedIcons E:/projects/CHOMPStation2/icons/gen
```

This copies the manifest, creates read-only input links, and keeps map/interface
directories separate. No build/repack helper should write into its linked inputs.
Pass its manifest explicitly to the benchmark with the project's normal defines.

## Recorded fixture run (2026-10-01)

The development profile uses optimization level 2 for compiler/codegen/output
crates. These are small-fixture measurements, not real-project estimates.
Every case also passed a repeated byte-identity check and catalog/full assembly
identity check. Native comparison used BYOND 516's `dm.exe` on identical source.

| Case | Complete Rust pipeline | Catalog reuse pass | Symbolic hits/misses | Native compile |
|---|---:|---:|---:|---:|
| Cold baseline | 0.715 s | 0.067 s | 0 / 64 | 0.308 s |
| Cached baseline | 0.119 s | 0.072 s | 64 / 0 | 0.295 s |
| Add procedure | 0.229 s | 0.084 s | 64 / 1 | 0.318 s |
| Add variable | 0.133 s | 0.106 s | 64 / 0 | 0.308 s |
| Change default | 0.128 s | 0.068 s | 64 / 0 | 0.308 s |

Cached-baseline assembly took 0.057 s, explicit encoding 0.00018 s and durable
publication 0.022 s. Six independent fixture roots with two concurrent jobs ran
18 baseline/cached/add-procedure measurements plus catalog passes in 3.687 s.
Reports are under `target/materialization-tiny-dev` and
`target/materialization-six-dev`; each records the executable SHA-256.

Use `--cases baseline,cached-baseline,add-proc --skip-repeat` for a bounded first
real-project measurement. The default runs every structural case and repeats
full materialization for determinism. A failed compiler run is not reported as a
successful latency result.

Game-only history sample on 2026-10-01: 4 of 10 recent first-parent game
commits changed macros (40%). Current lexical fanout for sampled changed macros
included `DECLARE_LOGIN_VERB` (120 occurrences in 36 files), `SEQ_TEST` (88 in
one file), and `SEQ_TARGET_STATIC` (7 in three files). This small sample is
recorded in `target/macro-history-game-architecture.json`; it does not measure
active expansion dependencies or predict full recompilation cost.
