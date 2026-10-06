# Native v2 status

Phase 0 is open. Phase 1 implementation has not started.

## Implemented

- Reference checkout `codex/native-v2` starts at `ac1af55d1a`.
- Release instrumentation profile, frozen original comparison pairs/compiler,
  source/runtime inventory, recovered compiled resource payloads, pinned engine
  executable/library hashes and original 1,089-test selection.
- `PREPROCESS.md`, `LINK.md`, `PUBLISH.md` and their source fixtures.
- Serial, isolated runtime replay with preserved controls, raw evidence,
  resumable receipts and explicit incomplete-run handling.
- Streaming normalization of both raw and structured logs, independent per-test
  results and stable/variable identity classification. No automatic parity claim.
- Bounded cold/body sampling harness, stage receipts and named-frame analysis.

## Evidence collected

- Twenty Python harness checks passed, including failed-suite completion policy
  and independent sampled-child exit/diagnostic preservation.
- Focused Rust archive portability test passed after fixing the test's LF/CRLF
  input preparation. Native content-ID, payload and opcode assertions remain exact.
- Eleven preprocessing fixture compilation cases captured against DreamMaker
  516.1687 and preserved native Build 50, including active map/skin imports.
- Four paired linker worlds captured. List observations match. Type/verb order,
  static/global initializer order and equal-content resource alias identity differ.
  See the compact paired receipts under `fixtures/phase0/link`.
- Writable runtime copies passed the publication probe. Read-only hardlinks failed
  static resource loading with exit code zero and unchanged pair hashes.
- Eight DreamMaker preprocessing observation wrappers captured. Repeated includes
  and `FILE_DIR` exposed incorrect predicted expectations; distinguishing probes
  now establish the rules before the contract is finalized.
- Strict workspace Clippy passed. The full Rust workspace passes: 1,199 tests,
  zero failures across 96 result targets. Fixture preparation restores only proven
  checkout line-ending differences, preserving exact IDs, payloads and order checks.
- The original instrumented release and its matching PDBs are preserved separately
  for profiling. The saved lint/fixture changes also build in release (4m24s).
- The power-bridge source uses encoded handles as numeric list positions. Both
  frozen outputs retain the retired branch's nested indexing; native silence is
  unresolved and is not treated as a correctness advantage.
- Unprivileged reference cold build completed in 265.015 s (48,681 lowering
  candidates, two bounded compiler workers, no compiler memory cap). Independent
  fresh build passed full DMB/RSC byte and ordered diagnostic equality. Input
  preparation took a separate 84.078 s; it is evidence staging, not compilation.
- Corrected BYOND repetition 1 produced all 1,089 results: 984 passed, 47 failed,
  58 skipped. After suite/shutdown completion it exited with an access violation.
  Complete observations and abnormal exit are both retained; the normal-exit gate
  fails. The original receipt is preserved beside its proof-backed classification.

## In progress / remaining gates

- Three selected full runtime replays per original output and normalization of all
  six, including stable versus variable differences and per-test runtime counts.
- Real release cold/body builds with built-in stage/end-to-end timing rows.
- External sampling and ten named hot frames are deferred: the user stopped the
  profiler because it repeatedly requested administrator permission. The harness
  now defaults to built-in timing and does not launch a sampler or xperf.
- Human review of the three contracts after the evidence is assembled.
- Requested-access tracing is deferred at the user's instruction. The probe's
  functional failure is known; its requested-access cause is not established.

The first unfiltered replay was stopped because it selected 1,113 tests instead of
the original 1,089-test intersection. A selected replay completed all 1,089 tests,
but is excluded because its runtime overlay omitted an external constraint JSON
fixture. That fixture is now restored and hash-checked before launching. The clean
marker means a failure-free suite, not completion; completion independently checks
selected results, suite/shutdown messages and normal exit. Original receipts remain
available. Replacement runs pin the original selection and external fixture hashes.
No new timing, parity or
completion percentage is claimed while those gates remain open.

## Artifact location and limits

Raw evidence: `D:/dmb-native-v2-phase0`. That drive is an HDD. Profile working trees
use `E:/dmb-native-v2-phase0/profiles` on SSD; the frozen source relocation is
authenticated against its inventory and recorded separately from compiler latency.
The one-time HDD-to-SSD source relocation took 282.18 s and is not a compiler build.
Every imported resource remains included. Release build
artifacts use `E:/dmb-native-v2-phase0/cargo-target`, outside repository checkouts.
Cargo uses one job. Runtime replays are serial with the preserved 2 GiB private
memory and 3,600-second controls. Compiler profiles use a five-minute external
watchdog and no new compiler memory cap. Procmon is stopped.

Recovered RSC payloads establish the profiling input bytes; transformed resource
formats do not establish original source encodings/timestamps. Preserved runtime
pairs are replayed independently. Raw events lack reliable per-event test ownership,
so normalized reports retain that coverage limitation.
