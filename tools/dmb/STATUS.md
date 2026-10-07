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
  after 158.403 s at about 11.5 GiB private memory. It produced no completed
  model; it is neither a successful frontend timing nor a compiler benchmark.
  Evidence: `E:/dmb-native-v2-phase0/source-analysis-probe-20261006/receipt.json`.
  Static investigation found full macro-table deep clones per text segment when
  conservative token-pasting dependencies are encountered. The shared-binding
  fix and a fresh bounded rerun are in progress.

## In progress / remaining gates

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
