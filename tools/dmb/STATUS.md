# Native v2 status

Phase 0 is open. The user authorized progressing through Phases 0 and 1;
Phase 1 foundation work is now underway alongside the remaining baseline evidence.
The production compiler has not switched to the new pipeline.

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
- Preserved daemon baseline completed in 244.960 s; the single-procedure edit
  completed in 6.523 s. The first independent fresh comparison timed out at the
  285-second watchdog while lowering procedures, without producing comparable
  output. A second isolated comparison passed in 220.448 s: exact DMB, RSC and
  ordered diagnostic equality. The original 6.523-second edit is now qualified.
  Receipt: `E:/dmb-native-v2-phase0/oracles/body-built-in-2/oracle.json`.
- Corrected distinguishing preprocessing captures establish same-file include
  suppression (macro effects included), distinct-file expansion, and terminal
  FILE_DIR resolution for the tested cases. Three additional linker worlds
  capture map startup, explicit/reopened inheritance and procedure metadata.
  The map startup observations match; ordering and metadata divergences remain.

## Phase 1 foundations (not production migration completion)

- `dm-ir` now exposes content-derived xxh3 symbol IDs and a collision-checking
  text table, plus a resolver boundary without output-table or tree-arena IDs.
- `dm-tree` is being built as an independent immutable declaration model with a
  separate current-source occurrence table. Unsupported resolver queries are
  explicit errors/unsupported answers, never invented negative lookups.
- `dm-preprocess` is gaining a directive/region pass and parallel expansion,
  following the captured include and resource-search semantics, without caching.
- `dmbc::publish` implements an OS store lock, authenticated immutable pairs,
  shared RSC identity, last-three session records, writable acquired run copies
  and conventional installation with the pair marker written last. An identity-only
  composition API lets a new DMB reuse a stored archive without an RSC-sized input
  allocation or rewrite. Eviction, orphan cleanup and the complete crash matrix
  remain pending; publication is not wired into the production compiler yet.
- The scalar constant evaluator has moved from `dm-compiler` to `dm-tree`, with
  the compiler supplying the existing string decoder and `nameof` interpretation.
  Lists and runtime expressions are still explicit unresolved results; this is
  one extracted semantic rule, not a migrated initializer pipeline.
- An uncached frontend connects directive planning, bounded parallel expansion,
  declaration parsing and the semantic tree. Procedure bodies are parsed on
  demand from retained expansion ranges, with current include/macro provenance.
  It does not invoke the historical session, graph or cache machinery. Production
  lowering, linking and the command-line compiler still await migration.
- The frontend now lexes/parses grammar-safe chunks with bounded parallel workers,
  discarding executable AST children before the source-order merge. Include
  context remains joined; chunk sizes never select another semantic algorithm.
- The captured resource host answers qualified resource queries from validated
  payloads and explicit lookup outcomes, forwarding declaration queries to the
  tree. It performs no filesystem reads during resolution. Resource discovery
  and cold-driver integration remain unfinished.
- Procedure presence and structural shared-slot queries now have tree providers.
  Unknown intrinsic-dependent negatives remain unsupported. Explicit engine
  hierarchy/inventory attachment validates parent agreement and owner presence,
  indexes intrinsic names and includes the configuration in tree identity. The
  actual engine snapshot extraction/merge remains unfinished.
- Shared DMM parsing now lives in `dm-syntax::map`: one-pass ordered records and
  borrowed source spans. Existing compiler helpers delegate there; semantic map
  resolution and dense-ID emission have not migrated.
- `dm-analysis` streams source-only declarations and separate current occurrences
  using structural hexadecimal IDs and canonical metadata. `dmbc analyze
  --no-daemon` consumes this actual frontend/export path without the old compiler.
  Complete executable references and general lint-engine replacement remain open.
- Foundation checks passed: analysis (2), IR (9), syntax/maps (75), tree/frontend
  (31), preprocessing (64), resources (4) and publication (5), totaling 190.
  Strict Clippy passed across these seven crates; the legacy compiler library
  integration check passed after the scalar/map extraction and frontend reexport.
  The CLI exported the captured three-implementation procedure fixture successfully.
  This is a focused integration gate, not a fresh full-workspace test suite or a
  full cold-build oracle for Phase 1. Check log:
  `E:/dmb-native-v2-phase0/foundation-tests.log`.

### Subsequent migration slices

- The encoder now has one shared direct/packed operand path for existing linked
  output and immutable symbolic freezing. Packed references carry exact tags,
  cover both placeholder words and reject values outside 24 bits.
- Procedure lowering has an explicit per-procedure input and direct Resolver
  entry. It queries project/resource meanings without a copied SharedLowerBindings
  snapshot, preserves exact shared-slot tuples, and fails on unsupported meanings.
  The historical compiler entry remains available during migration.
- Pinned engine extraction and explicit engine-first frontend seeding are wired
  into `dmbc analyze --engine-template PATH`. The optional `--bootstrap-catalog`
  requires the exact pinned template. Unnamed engine procedures remain opaque;
  native `/world` and `/list` semantic roots are separate from class-table identity.
  The catalog preserves proven types beside opaque defaults/modifiers. Source
  overrides retain an explicit opaque base, without invented engine source rows.
- Demand-driven scalar constant resolution returns an immutable overlay, with
  explicit backend decoding identity, actual forward dependencies/cycles and
  separate declared/effective defaults. Unsupported meanings remain explicit.
- `dm-link` independently assigns tables under canonical or caller-supplied
  observable orders and fixed engine bindings. Relocation encoding delegates to
  shared IR. Initializer reference sidecars are supported; full initializer
  emission, metadata policy and the production DMB driver are not migrated yet.
- The latest backend gate passed 216 tests. Subsequent tree/analysis/link/client
  gates passed 39/2/4/11 tests; IR passed 10. Strict Clippy passed these six crates
  and the legacy compiler library check passed. These are focused checks, not
  the Phase 1 full-workspace/oracle gates. The engine-seeded CLI fixture passed.
- A real DeepQuarry source-only integration probe was stopped for PC headroom
  after 158.403 s at about 12.0 GiB private memory. It produced no completed
  model; it is neither a successful frontend timing nor a compiler benchmark.
  Evidence: `E:/dmb-native-v2-phase0/source-analysis-probe-20261006/receipt.json`.
  Static investigation found full macro-table deep clones per text segment when
  conservative token-pasting dependencies are encountered. Persistent macro
  bindings now share immutable snapshots and expansion borrows them directly.
  The bounded rerun reached declaration diagnostics in 37.305 s (exit 1):
  directive planning 19.152 s, expansion 2.264 s, source indexing 1.533 s;
  descriptor parsing reached 150/150 at 12.401 s, then adaptation failed.
  A sampled private footprint was 0.626 GiB;
  this is not a peak measurement. Qualified field assignments were rejected;
  their owner-path adapter fix is awaiting its combined focused gate.
  Evidence: `E:/dmb-native-v2-phase0/source-analysis-probe-20261006-2/receipt.json`.
  This failed source-only probe is not an end-to-end compiler benchmark.
- The bounded lazy-body lowering driver accepts an explicit ABI policy and
  preserves current source diagnostics. Three focused tests passed, including
  actual tree global storage and worker-count equivalence. Full production ABI
  policy, symbolic composition and output emission remain incomplete.
- The subsequent integration gate passed 220 backend, 10 IR, 44 tree and 16
  client tests, strict Clippy and the executable build. Actual lowering results
  now freeze through the shared encoder and canonical linker tables; required
  external payloads and ordering facts stay explicit. Full DMB generation is
  still absent from the new driver. Granular field facts and modified-instance
  RuntimeType classification are covered by focused checks.

## In progress / remaining gates

- Phase 0 raw-log investigation found 3,068,028 native bounds errors and
  3,087,060 reference bounds errors. Native origins are blank and the decoded
  output has no DbgFile/DbgLine instructions. The error handler's file+line
  cooldown merges blank-origin failures, so per-test failure counts cannot
  establish runtime parity. Exact attribution of native power events remains
  unproven. Pinned FFI wrapper/static initialization sequences match; the
  preserved DLL interface differs from the Rust source previously cited.
  Evidence and hashes: `phase0/power-rootcause.json`. Source-aware debug
  emission is now a required backend migration slice.
- Corrected reference repetition 2 completed normally: 984 passed, 47 failed,
  58 skipped, 2,586.222 s runtime, 1,994,874,880 peak private bytes. These match
  repetition 1's counts; its abnormal exit remains separately recorded.
- The next source-only probe reached tree construction in 24.737 s, then
  rejected `/savefile/byond_version` because its intrinsic base was absent.
  Sampled maximum private memory was 1,568,952,320 bytes (one-second samples).
  Input/OS cache state was uncontrolled; this is a failed frontend probe,
  not a cold compiler build. Savefile presence and all observed opaque engine
  variable bases are now awaiting the focused gate.
  Receipt: `E:/dmb-native-v2-phase0/source-analysis-probe-20261006-3/receipt.json`.

- Corrected native repetition 1 completed all 1,089 selected results, suite and
  shutdown markers, and exited normally: 996 passed, 35 failed, 58 skipped.
  Runtime elapsed was 3,081.973 s, with 1,991,770,112 peak private bytes. This
  is a runtime replay, not compilation latency. Receipt/result hashes are in
  `phase0/native-replay-1.json`. The other repetitions and normalization remain
  necessary; the original 997/34 count is not being substituted for this run.

- Three selected full runtime replays per original output and normalization of all
  six, including stable versus variable differences and per-test runtime counts.
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
