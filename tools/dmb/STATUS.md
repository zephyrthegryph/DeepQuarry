# Native compiler status

Updated 2026-10-12. Ownership moved to Claude on 2026-10-12. The user closed Phase 1 the same day
(decision D31 in [DESIGN.md](DESIGN.md)). History through 2026-10-12: `archive/STATUS_through_20261012.md`.
This file is a current-state summary and stays under 120 lines; per-cohort numbers belong in
`bench/receipts/` and `phase0/*.json`, narrative in `archive/`.

## What exists

- `dmbc compile` (CLI and daemon share `request_runner`) compiles the captured DeepQuarry snapshot
  through preprocess, tree, resolve, lower, link, encode and pair publication (`PUBLISH.md`).
- Retained host (`runner_host`) keeps frontend revisions, owner artifacts and procedure candidates
  across edits; a disk cache and `PairStore` back the no-daemon path.
- All DMB/RSC pairs produced by every recorded cohort matched independently fresh native builds
  byte for byte. This is container and table identity, not BYOND runtime parity.
- Workspace layout: `byond-dmb` (codec only), `dmb-opendream` (old OpenDream translator,
  `dmb-inspect`, structural comparator, format examples), the `dm-*` pipeline crates, `dmbc` (driver).

## Latest measured numbers (with configuration)

| Scenario | Config | Result |
| --- | --- | --- |
| Cold, release | 8 workers, DeepQuarry snapshot | about 11 s critical path, 12.5-15 s wall |
| Peak memory, cold release | same | 1.55 GB against the 1.5 GB budget (accepted by user, D31) |
| Cohort `3ede538f96` (not release) | dmbc opt0, tree/codegen opt2, 2 workers | fresh 101.9 s; retained initial 171.8 s; unchanged 3.06 s; body edit 78.1 s; leaf-variable edit 103.2 s |
| Same cohort, daemon job peak commit | same | 6.13 GB |

The release row is the user's phase-1 acceptance figure; the opt0 cohort is the latest recorded
incremental run and is not a release-profile claim. Receipts: `phase0/deepquarry_iteration_20261012_3ede.json`,
`bench/receipts/`. No controlled alternating-run improvement is claimed.

## Open gates

1. Release-profile measurement of unchanged, body-edit, new-procedure and leaf edits (retained vs fresh),
   with a trustworthy memory column (owned-job peak, one worker count per row).
2. Retained memory: the daemon job peaked at 6.13 GB in the last incremental cohort; target is below the
   4 GB daemon limit with the retained core surviving between edits (it was lost before edits).
3. Incremental short-circuits: unchanged is 3 s; body and leaf edits still recompute 50-68 s of
   compilation despite 48,680 disk hits. Body edit should only relower the edited procedure and relink.
4. BYOND structural parity: 539,365 unexplained discrepancies in the last baseline (413,153 bytecode,
   122,318 strings by use, 3,894 procedure table). Admission is open.
5. Not yet done: compile-error parity, history replay, six-worktree concurrency acceptance,
   full runtime suite (deferred to Phase 5), production readiness.
6. Cleanup (this lane, pass 1 done): translator moved out of the codec crate. Pending for the dmbc pass:
   split `dmbc` (dm-lower), consolidate wire formats, delete receipt/proof modules.

## Lanes in flight (2026-10-12)

| Lane | Branch | Scope |
| --- | --- | --- |
| Memory | `dmb/mem` | soft memory, housekeeping, heap census, retention and eviction |
| Incremental | `dmb/incr` | lowering memo, initializer reuse, request runner, composition, frontend reuse |
| Measurement | (bench) | release profile cohorts, receipts, benchmark protocol (D27) |
| Cleanup | `dmb/clean` | crate boundaries, docs, dead tools, source shape |

Lanes do not edit each other's files; `crates/dmbc` internals belong to memory and incremental until
both merge.

## Source shape

`python tools/dmb/check_source_shape.py` enforces the 1000-line cap. Open violations (both in `dmbc`,
owned by the memory and incremental lanes): `crates/dmbc/src/request_runner.rs` (1046) and
`crates/dmbc/src/heap_census.rs` (1004). New splits should follow topic, not numbered `suite_N` files.

## Known failing tests

`cargo test -p dm-codegen-byond lower_resolver` fails three tests on the cleanup base
(`assignment_type_is_demanded_only_by_contextual_constructors`,
`args_receiver_type_preserves_lexical_shadows_without_outer_variable_queries`,
`opaque_intrinsic_field_read_uses_presence_and_storage_only`); not caused by the cleanup moves.

## Commands

```
python tools/dmb/check_source_shape.py
cargo test --manifest-path tools/dmb/Cargo.toml -p byond-dmb -p dmb-opendream
cargo run --manifest-path tools/dmb/Cargo.toml -p dmbc -- compile deepquarry.dme --workers 8 -DCITESTING=1 --progress
cargo run --manifest-path tools/dmb/Cargo.toml -p dmb-opendream --bin dmb-inspect -- structural-diff EXPECTED.dmb ACTUAL.dmb REPORT.json ID
```

Wrap every cargo build or test on this machine with `tools/dq_machine_slots.sh run cargo`.
