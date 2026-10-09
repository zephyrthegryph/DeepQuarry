# Frozen DeepQuarry trace input

This configuration reuses the preserved private project at
`E:/dmb-native-v2-phase0/review-benchmark-inputs/project`, not the current game checkout.
No benchmark was run while preparing this configuration.

## Provenance

`preparation.json` records source commit
`1bd7e59f5d8e1936312a693973ee96c8b5300dc6`, 20,085 files and
1,128,865,791 exact project bytes. Assets were linked from the preserved E-drive
profile-source only after SHA256 equality with the source checkout; 247 differing
files were privately copied. The manifest, probe and template are private files.
`origins.json` identifies every source and storage mode. `snapshot.json` pins all
prepared positive inputs. Its SHA256 is
`debee8e467b5b19f8dac2c9cb951856e7b98dd3e1ac4ecf9720b2520f6d8f1ac`.
The pinned engine SHA256 is
`9221528efb715be5b8df23020989e0c2a53ea32bff9894747166dbe04d785540`.
These are recorded preparation receipts, not a claim that a compiler has validated
this mirror. The harness and snapshot-fed verifier must validate actual dependencies.

The private `.dmbc/phase2-probe-a.dm` contains one root proc returning 101.
The body scenario uniquely replaces `return 101` with `return 102`. The harness
restores original bytes in finally and between repetitions. Do not edit linked assets.

## Coordinator invocation

After building the frozen profiler-enabled compiler with allocation counting, from
`E:/projects/dq-wt/dmb-review`, substitute its actual executable for FROZEN_EXE and
choose a previously nonexistent evidence directory:

```text
python tools/dmb/bench/dmb-bench.py --compiler FROZEN_EXE --project-root E:/dmb-native-v2-phase0/review-benchmark-inputs/project --snapshot E:/dmb-native-v2-phase0/review-benchmark-inputs/snapshot.json --scenarios tools/dmb/bench/deepquarry-scenarios.json --stage-map tools/dmb/bench/deepquarry-stage-map.json --cache E:/dq-cache/dmb/review-bench --output E:/dmb-native-v2-phase0/review-traces-NEW --watchdog 285
```

The existing harness supplies --trace automatically, runs three repetitions at eight
workers and then three at two, and creates isolated repetition caches. Cold is explicitly
--no-cache. Its separate unmeasured --verify populates the baseline cache before the
first body edit in each repetition; body edit is therefore warm, not a cold-build claim.
It preserves prior input-sessions in repetition archives. Verification, snapshot checking
and preparation times must not be reported as measured compiler time.

No output evidence directory or cache is created by this document. Existing C/E probes
and preserved receipts are untouched. This invocation explicitly keeps run caches under E:/dq-cache. The compiler's
default is E:/dq-cache/dmbd/cache; DMB_CACHE_DIR still overrides it.

## Stage mapping

`deepquarry-stage-map.json` is copied from the preserved mapping and was checked against
`crates/dmbc/src/main.rs`'s explicit sequential_stages list: exactly 23 unique stages.
Input has engine_input, engine_capture, session_validation and input_scan. Frontend
has six sequential directive/expansion/index/parse/origin/body stages. Tree contains
frontend.tree_resolution and captured_facts. Resource/maps is one stage. ABI contains
startup capture, ABI preparation and initializers. Lowering is procedure_lowering.
Link contains linking_inputs, required_type_admission and symbolic_linking. Composition
contains composition, cache_flush and publication. Aggregate frontend/build spans and
nested resource spans are excluded so their CPU is not counted twice.

Recheck the mapping if instrumentation changes. The unchanged shortcut has only
engine_input and session_validation. Acceptance requires the profiler's declared exact
critical sequence, measured thread CPU and process crosscheck, usable clock calibration,
observed allocations, authenticated output and diagnostic parity. Partial annotated I/O
calls are not complete blocked I/O, so I/O acceptance remains not_evaluable without
explicit complete coverage. Wall times alone cannot satisfy the revision-5 CPU gate.
