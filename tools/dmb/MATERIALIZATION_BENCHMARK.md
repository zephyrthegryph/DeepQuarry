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

This read-only audit compares complete multiline definitions against each commit's first parent. Fanout is current lexical occurrence count, including inactive source, comments, and strings; it does not claim semantic dependency coverage. The report records its revision, sample size, and method. Both game source and tracked compiler fixtures are included in the default history sample.

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
