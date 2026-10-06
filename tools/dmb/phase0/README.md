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

New large artifacts live under `D:/dmb-native-v2-phase0`, outside the repository.
Generated fixture DMB/RSC files are ignored. Source fixtures and compact evidence
belong in the repository; raw logs and profiles remain in the dedicated artifact
tree and are identified by receipts/hashes.

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
