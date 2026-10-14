# Phase 0 evidence harness

Reference branch: `codex/native-v2`, based on
`ac1af55d1a9a8e023e46bd058be59ed82c503f52`. The previous architecture branch is
preserved for reference. This phase does not implement Phase 1.

## Reproduction

1. Build/test the reference workspace with one Cargo job. The release profile
   includes line-table debug information for sampling; it does not change the
   compiler pipeline. Do not overlap compiler benchmarks with Cargo jobs.
2. `freeze_baseline.py` pins retained comparison binaries and raw records,
   restores compiled resource payload bytes from the original RSC into a private
   source tree, and inventories all captured inputs. Its hashes are provenance
   checks, not changes to the compiler's cache identity. These payloads pin the
   profiling input; resource formats transformed by DreamMaker do not prove exact
   original source encodings or timestamps. Preserved runtime pairs are replayed
   directly, independently of that reconstruction.
3. `run_contracts.py` captures DreamMaker fixture compilation and linker runtime
   observations, optionally comparing the preserved native compiler. Preprocessor
   fixtures include compile-only cases and optional `--observe-preprocess` runtime
   wrappers that expose macro, include and resource behavior.
   Included DME fragments are selected through the fixture manifest, not discovered
   as independent worlds. Every invocation requires a fresh evidence directory.
4. `replay-runtime.ps1` executes three serial runs of each preserved output. See
   [REPLAY.md](REPLAY.md). `normalize_runtime.py` compares the untouched records;
   [NORMALIZE_RUNTIME.md](NORMALIZE_RUNTIME.md) explains coverage and ownership limits.
5. See [PROFILE.md](PROFILE.md) for cold and body-edit sampling with an external
   watchdog and separate stage/end-to-end evidence.

Current large artifacts live under `E:/dmb-native-v2-phase0`, outside the repository;
older receipts retain their original drive paths. Build caches live under
`E:/dq-cache/`, and compiler worktrees under `E:/projects/dq-wt/`.
Generated fixture DMB/RSC files are ignored. Source fixtures and compact evidence
belong in the repository; raw logs and profiles remain in the dedicated artifact
tree and are identified by receipts/hashes.

The captured one-procedure variant prepared on 8 October changes only the
`power_key_owner` guard literal in a private replay journal. Its manifest and
integrity receipt are under `E:/dmb-native-v2-phase0/body-edit-variant-20261008-a/`.
It is a cold-after-edit profiling input, not a warm incremental-latency result
or a runtime-parity candidate. Never replace the preserved BYOND comparison
input or run that intentionally changed program as the original runtime oracle.

## Publication probe

The writable-copy control passed on BYOND 516.1687. The read-only hardlink case
failed to read its static resource despite exiting with code zero. Pair hashes
were unchanged. Requested-access tracing is deferred at the user's instruction;
no write-access conclusion is claimed. Publication therefore uses writable
private copies. See [../PUBLISH.md](../PUBLISH.md).

## Completion gates

Phase 0 is complete only after the complete workspace test run is green, all six
runtime replays are classified, cold/body profiles include the ten hot frames,
and the three contract documents have been reviewed by the human. Preparing a
harness or compiling fixtures alone does not satisfy those gates. The requested
file-access trace remains an explicitly deferred gate.

## Power-bridge divergence: partial diagnosis

[power-rootcause.json](power-rootcause.json) records hashed reference/native
bytecode evidence. The source indexes a DM list by numeric raw region handles
without a demonstrated dense-position bound. Both retired-event branches retain
the same nested list-index operations and event constant3; this is not evidence
of an omitted native index/bounds operation. Native silence remains unresolved
(event timing, dispatch or upstream execution). Background runtime attribution
to an active unit test does not establish that test caused the power failure.
No game/compiler semantic change is made by this Phase0 classification.

## Provenance and pending evidence gates

The corrected replay session `replay-86cd8c1d305f43bca1de876bc9341fb6`
started its first BYOND child at `2026-10-06T21:42:12.7769748Z`. That loaded
runner records dd.exe and the corrected constraint-fixture hashes but predates
the twelve-file per-launch engine-closure field. `frozen-engine.json` pins the
closure; it has no recorded check timestamp and cannot itself establish a check
immediately before this child. A later matching audit is labelled **post-run**
with its actual time. Separately retained, timestamped pre-run evidence can be
linked if available, but no field is retroactively described as a runner preflight.
Missing closure audit reduces provenance coverage; it does not erase valid raw
observations or automatically reject this run. An observed hash mismatch rejects
the comparison. Future runner invocations record per-launch closure checks.

The earlier selected BYOND run completed the suite, but lacked the external
constraint JSON. It is **baseline-ineligible**, despite normal exit and complete
results. The interrupted native setup is not a runtime observation. Keep both
artifacts; neither substitutes for the six corrected replays. Completion means
exact selected-test coverage, suite-finished and shutdown markers, normal exit
and no watchdog stop. `clean_run.lk` means zero test/runtime failures, not completion.

Runtime parity classification, provenance coverage and compiler performance are
separate gates. Three observations do not prove equivalence. Cold/body timing
remains provisional until the captured-snapshot oracle passes and profiles identify
the ten hot frames. A completed runtime replay is not a compiler build oracle.
The deferred requested-access trace is disclosed; writable copies are the supported
publication choice, with no claim about the precise DreamDaemon access mask.

## Complete observations with abnormal terminal exits

A complete-results-abnormal-exit observation retains exact selection coverage,
results, suite-finished and shutdown evidence, an observed terminal exit code,
and no watchdog/runner stop. It is eligible as one of three observations, and
resume skips it after the same pinned-input checks. It is **not** a healthy run:
normal_exit_gate_passed remains false, and finalization reports all three exit
codes per producer plus stable/variable exit outcomes. A crash after complete
results is not erased by a zero-failure marker or excluded to manufacture a
healthy-only baseline. Truncated, timeout, memory-limited, unknown-exit and
clean-marker-grace forced-stop runs remain incomplete. Existing receipts are
reclassified only by coordinator append-only proof/audit, preserving originals.
This explicit contract supersedes earlier text requiring normal exit for result
observation completeness; the normal-exit/reproduction gate remains separate.
