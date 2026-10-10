# Bounded runtime suites

`runtime-suite.py` enters the existing build runner. It neither discovers tests
nor creates a second runtime runner. Windows is required. Supply a new output
directory below `E:/dq-cache`; existing directories are refused. Resolved output
and Cargo cache paths must remain below that root and have no existing reparse
ancestors. The runner never recursively deletes them.

## Pins and scope

Supply SHA256 pins for the actual Bash executable, DreamMaker executable, and
**`dreamdaemon.exe` frontend beside DreamMaker**. Do not supply the smaller
`dd.exe` worker used by tiny standalone fixtures. Native mode additionally needs
the native compiler and engine template pins. There are no executable defaults.

These pins authenticate the named files only. They do not certify the spawned
worker, Verdigris, the complete source/resource closure, or an accepted runtime
baseline. Existing runtime evidence carries its own observed frontend and DLL
identity. The receipt retains errors and cleanup evidence even when no test
result is produced.

The Windows Job limits aggregate owned-tree commit to 4,000,000,000 bytes. Job
commit counters are not private-byte or working-set peaks. Compilation has a
300-second deadline until actual compiler evidence appears; the existing build
runner bounds each DreamDaemon to 300 seconds; the cohort stops at 1800 seconds.
The owned Job is terminated and reaped on every exit. No foreign PID/name-wide
termination is used.

## Invocation templates

Replace every placeholder with an explicit absolute path or SHA256. No example
identifies an existing generation or claims that a run has passed.

```text
python tools/dmb/bench/runtime-suite.py --checkout CHECKOUT --output NEW_E_CACHE_DIRECTORY --backend byond --bash-exe BASH --bash-sha256 BASH_SHA --byond-exe DREAMMAKER --byond-sha256 DM_SHA --dd-exe DREAMDAEMON_FRONTEND --dd-sha256 DD_FRONTEND_SHA --security trusted --tier all --batch-size 32
```

For native mode, change `--backend` to `native` and add
`--native-exe NATIVE_COMPILER --native-sha256 NATIVE_SHA --template ENGINE_TEMPLATE
--template-sha256 TEMPLATE_SHA --workers 2`. Use `--focus /datum/unit_test/NAME`
(repeat for multiple names) instead of tier/batch arguments for focused runs.
Optional `--cargo-home` and `--cargo-target` reuse explicitly named caches under
`E:/dq-cache`; otherwise new run-local caches are used. Extra `--define NAME`
arguments preserve their supplied order.

## Stopped-generation continuation

1. Wait for the owning guardian to exit and verify its cleanup receipt. Pin the
   final suite evidence bytes. Never checkpoint a file still being written.
2. For BYOND, preserve its actual conventional DMB/RSC pair and run:
   `bun tools/build/seed_suite_checkpoint.ts byond EVIDENCE EVIDENCE_SHA DMB RSC NEW_CHECKPOINT`.
3. For native, retain the actual `nativeOutput` generation through the existing
   pinned compiler `acquire --output-store STORE --pair-id PAIR_ID --slots NEW_OWNED_ROOT
   --result-file ACQUISITION` command. Pin that acquisition receipt, then run:
   `bun tools/build/seed_suite_checkpoint.ts native EVIDENCE EVIDENCE_SHA ACQUISITION ACQUISITION_SHA NEW_CHECKPOINT`.
   Native evidence must pin a completed matching BYOND reference plan. Acquisition
   files must remain present; do not substitute conventional BYOND output metadata.
4. Run the same backend, tier, batch size, defines and pins with
   `--resume CHECKPOINT --resume-sha256 CHECKPOINT_SHA`. No compiler is invoked on
   this path. The original reference plan pin and completed prefix are preserved.
5. After each stopped interval, extend with
   `bun tools/build/checkpoint_suite.ts PRIOR PRIOR_SHA FINAL_EVIDENCE FINAL_SHA BATCH_SIZE NEW_CHECKPOINT`.

Historical schema-1 normal checkpoints retain the existing normal continuation
path. New all/exhaustive checkpoints have an explicit tier and schema-2 kind.
`--plan REFERENCE --plan-sha256 REFERENCE_SHA` binds a new run to the exact
runtime-issued roster/order; it cannot be combined with resume.

Compare complete evidence with `compare_normal_suites.ts --suite` and explicit
reference/native receipt SHA256 arguments. Add `--require-clean` to require
passed, unskipped rows and clean worlds as well as equivalence. Default exit zero
means equivalent results, including identical failures. Comparison remains
preliminary; neither matching rows nor a completed normal tier proves all DM
tests or full source closure.
