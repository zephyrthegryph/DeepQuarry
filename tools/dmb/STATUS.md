# Native v2 status

Phase 0 is open. The user authorized progressing through Phases 0 and 1;
Phase 1 foundation work is now underway alongside the remaining baseline evidence.
The production compiler has not switched to the new pipeline.

## Current integration checkpoint (7 October 2026)
Release probe 36 names the remaining parent-ABI blocker: the authored root type
`/procpath`, canonical index 28, has semantic parent `/`. External time was
29.691 s, sampled private memory 3,069,820,928 bytes. Initializers, all bodies and
symbolic linking passed; composition stopped before producing a pair. A native
root-type control is being captured to define the source-root record policy.
The captured controls show ordinary roots inherit `/datum`; the synthetic root
was a semantic-tree error. Shared parent resolution now uses an existing datum
for ordinary top-level types, preserving explicit engine/source parents and
unseeded trees. Its focused gate passes. No separate root-prototype writer is
needed: the native empty-root header matches the existing datum-parent writer.
Release probe 35 cleared retained-client projection and reached the next class
composition gate: an admitted source type has no physical parent ABI binding.
All bodies and symbolic linking passed again. External time was 30.657 s,
sampled private memory 3,056,427,008 bytes; no pair was produced. The precise
type/prototype is under investigation, rather than substituting a root prototype.
The exact savefile header assignment now avoids demanding a physical class;
ordinary primitive fields/callables still fail explicit admission. Its focused
gate passes. Native-backed `/callee` tag 89 classification also passes. A proposed
supplemental callee prototype was rejected by its focused check because the
pinned template already retains class 13 `/callee`; that duplicate path is removed.
Release probe 34 passed initializer codegen, all 64,964 procedure bodies and
symbolic linking (4.726 s). Composition stopped on retained engine inheritance
projection. External time was 28.639 s, sampled private memory 3,053,125,632
bytes; no DMB/RSC pair was produced. This is failed-attempt latency, not a cold
build benchmark. The next integration task is identifying and projecting the
retained class whose captured parent differs from its source-model parent.
The source explicitly reparents `/client` to `/datum`; a captured native control
shows only that edge change and its authored test field. The writer now projects
the parent edge while preserving the complete native class payload and physical
identity; its focused preservation gate passes. The next release probe is pending.
Release probe 33 stopped during initializer codegen after 16.460 s, with sampled
private memory 1,887,870,976 bytes. The exact-global correction exposed an old
initializer target check that still expected a raw root variable name. Both paths
now share the structural slot-key function. No output pair was produced.
A separate native compile control proves that `__PROC__` identifies each current
body even when the same owner/name is reopened; exact occurrence identity now
travels through lowering and the existing symbolic linker. The initializer slot
gate, two current-procedure lowering gates and repeated-body linker gate pass.
Release probe 32 lowered all 64,964 bodies successfully (6.344 s) and passed
required-type admission (0.195 s). Symbolic linking stopped on the authored
macro global `__rust_g`: ordinary global reads had omitted their exact root
storage sidecar. External time was 25.608 s, sampled private memory
2,654,552,064 bytes; no pair was produced. The global-slot producer correction
passed its four-form focused gate. Five backend receiver/context checks and 35 native-focused
checks passed before this attempt; these are focused checks, not a full suite.
Release probe 31 reached complete source analysis and attempted all procedure
bodies, reducing diagnostics from 2,195 to 522. Of those, 497 are intrinsic-name
`UniqueStaticVar` queries; the other groups are 18 storage, 3 declared-type,
3 procedure and 1 contextual `istype` failures. External time was 25.581 s;
sampled private memory 2,548,772,864 bytes. No pair was produced. This is a
failed attempt, not a completed cold benchmark. A positive-counterexample
uniqueness index now passes its focused partial-inventory gate; computed receiver,
return-annotation and additional native field fixes are being integrated.
Release probe 30 stopped in tree resolution after 8.356 s (sampled private
memory 1,021,616,128 bytes). A declaration namespace match split the owner
component `type_var` into `type_`; the component-boundary correction now has
a focused regression. No output pair was produced. The native intrinsic-field
gate and positive-procedure namespace gate pass; the next complete-project
attempt remains pending. The class readiness queue preserves the old ordering
and passes branching, deep-chain, missing-parent and cycle checks.

Release probe 29 completed initializer classification (2.129 s) and codegen
(0.338 s), then stopped after attempting to lower all 64,964 bodies. The failure report has
2,195 diagnostics, led by 1,758 unsupported `UniqueStaticVar` queries. External
time was 26.657 s (24.379 s driver), sampled private memory 2,500,485,120 bytes.
No pair was produced. Resolver admission, builtin inference, qualified `initial`
and repeated-var parsing fixes are being gated against this broader failure set.

Release probe 28 stopped during initializer classification at `basic.dm:3`:
the token builder rejected string association keys in `new/list(...)` as ordinary
named arguments. External time was 18.569 s (16.989 s driver), sampled private
memory 1,923,665,920 bytes. No pair was produced; this is failed-attempt latency.
The primitive list and previous modified-object gaps pass their focused cold gate.
The fresh release rejects both native-invalid bare returns, with one diagnostic
each; diagnostic severity/wording still differs from DreamMaker.
The actual CLI worker gate passed four tiny-fixture runs (workers 1 and 2 twice):
identical 23,413-byte DMB, 42-byte RSC and pair identity. Times were 0.097–0.118 s.
This certifies only that fixture, not complete-project determinism or timings.
The [frozen power audit](phase0/POWER_RUNTIME_AUDIT.md) finds native raw bounds
errors with missing source locations. Apparent reference-only per-test errors
cannot establish runtime correctness while those unlocated errors remain.

Release probe 27 passed initializer classification and cleared the modified-literal
failure from probe 26. It stopped at `message_server.dm:301`, where a declaration
`var/list/datum/feedback_variable/feedback = new()` was incorrectly treated as
constructing `/list/datum/feedback_variable` rather than the `/list` container.
External time was 20.550 s (18.112 s driver); sampled private memory was
2,030,493,696 bytes. No output pair was produced. These remain failed-attempt
timings, not completed cold benchmarks. A shared declaration-type projection
now applies to fields, formal parameters and local constructor inference. Focused
backend, tree and analysis gates pass, including inherited element hints and
signature identity. The next release/full-project probe remains pending.

A bounded native/error comparison found that release probe 27 silently accepts
two native-invalid bare modified returns. Explicit pre-compaction rejection now passes;
exact native diagnostic wording and compile-error parity remain open.

The focused cold integration gate passes stored modified defaults, canonical
descriptor deduplication, repeated writes and native Src modifier operands.
Eight native receipt gates pass, including const shared-slot allocation,
resource-payload equality, and grouped-return grammar. Native evidence required
adding const bit 2 to the tree's shared-storage decision; writer flags were correct.
The scalar evaluator now lives in the neutral IR layer with a tree compatibility
facade. Modified defaults and executable operands share one nested descriptor
closure, required-type admission, freezer and composer. Resource modifiers now
retain captured payload identities; identity, recorded-query and emitted-resource
proof gates pass. The real cold fixture also passes native tag40/payload0 list
construction without inventing a class row.

Native-proven allocation defaults now carry kind-62 identity tokens. Four focused
gates pass native equality partitions across scopes and DEBUG, constant folding,
and runtime global list null defaults. Execution phase remains independent of
token identity. This is not established as the cause of power-bridge errors.
Three publication fault-boundary gates pass authenticated-generation recovery.
Cross-file conditional support passes all seven pinned native controls.
Phase 0 and Phase 1 remain open; complete DeepQuarry output is not yet certified.
Release probe 26 cleared the builtin-world receiver and RGB scalar classification.
It stopped in initializer code generation on a modified object literal at
`code/datums/outfits/horror_killers.dm:45`, with no output pair. External time
was 17.422 s (15.880 s driver), sampled private memory 2,047,799,296 bytes.
Initializer classification completed in 1.657 s; initializer codegen failed
in 1.008 s. These are failed-attempt timings, not completed cold benchmarks.
The missing descriptor producer, initializer lowering and symbolic linking
contract is being implemented together. Native compile-only controls establish
modified-instance tag 41, descriptor deduplication, canonical distinct-field
ordering and preserved repeated writes. They also establish that modifier writes
to static/const fields use Src field operands, and bare scoped constants are
rejected; ordinary source assignment policy cannot be reused indiscriminately.
Full-project output, worker determinism and Phase 0/1 exit gates remain open.
Release probe 25 passed initializer classification (1.586 s), then stopped in
initializer codegen on the builtin `world` receiver in `world.Genesis()` at
`code/genesis_call.dme:52`. It failed in 17.512 s externally (15.928 s driver),
sampled 2,007,588,864 private bytes, and produced no pair. Startup capture was
0.968 s; ABI preparation was 0.326 s. Exact procedure-value defaults, runtime
callback lists, constant aliases, and 21 native call ownership cases passed
focused gates before this run. The next cohort fixes builtin-world inference
without inventing host absence answers, folds positively certified RGB defaults
through one shared pure-call policy, and removes success-path diagnostic copies.
Completed full-project cold timing and Phase 0/1 exit gates remain open.

Latest release probe 24 cleared initial SDK macros and reached the procedure-path
initializer `/proc/default_pathfinding_adjacency` at
`code/_helpers/pathfinding/common.dm:53`. It failed in 16.457 s externally
(15.128 s driver clock), sampled 1,870,815,232 private bytes, and produced no pair.
Startup capture took 1.145 s versus probe 23's 3.730 s after avoiding full parsing
of bodies without stored local declarations. ABI preparation took 0.320 s and
initializer classification 1.094 s. The stop points differ; no completed cold
compiler benchmark or Phase 1 exit is claimed. Native macro values, 21 native
expression-precedence cases, and emitted inherited-static shared-slot operands
passed focused gates. The procedure-path initializer fix is in progress.

Additional semantic investigation found a frozen old-output mismatch in
`Master.random_seed`: BYOND accesses the declared static through shared storage,
while the old native output uses an instance selector. The current v2 emitted-code
regression passes shared reads/writes for inherited static declarations; this
does not establish the cause of the power-bridge runtime errors. Current v2
discarded direct calls also need native managed-result lifetime handling, which
is being implemented with the preserved call ownership controls. Explicit
procedure literals must distinguish formal declarations from effective overrides
in both scalar defaults and runtime list expressions; both paths are under repair.

Release probe 23 cleared the vision macros and reached a missing `NORTH`
initializer at `code/_helpers/game.dm:621`. It failed in 20.579 s externally
(18.752 s driver clock), sampled 2,038,902,784 private bytes, and produced no pair.
Native compile-only controls now bind 148 initial SDK macros to decoded binary
receipts. Their value gate passed, but the new unary-minus/exponentiation
precedence gate exposed a parser mismatch; that correction is in progress.
These remain failed compile attempts, not successful cold-build measurements.

Release probe 22 reached a single missing `SEE_BLACKNESS` initializer fact
and failed in 20.527 s externally (18.838 s driver clock), with no pair. This
cleared the 47 intrinsic-field errors: classification/error mapping took 1.229 s
instead of the previous 70.272 s. Stop points differ, so this is diagnostic-path
progress, not a completed cold-build comparison. Native controls subsequently
proved eight initial vision macros, including `SEE_BLACKNESS=1024`; undef leaves
a runtime global read. The macro precedence/undef/shadow focused gate passed and
the release rebuild is underway. Completed full-project output remains pending.

Earlier admission checkpoints follow:

Probe 16 cleared the native callback ABI boundary and reached the complete
ordered procedure-admission diagnostics batch. It stopped after 64.171 s,
sampled 1,988,460,544 private bytes and published no pair. Most diagnostics were
960 unsupported return annotations, 425 downstream predecessor ABI failures,
368 missing boolean constant queries, 12 parameter-modifier cases, four source
radius settings and one parameter type. These are failed debug-attempt figures,
not completed cold compiler benchmarks. Resource ordering took 3.230 s; full
frontend capture took 34.852 s.

Probes 17 and 18 cleared procedure ABI preparation and stopped during initializer
classification. They took 59.776 s and 67.830 s respectively, sampled about
1.90 GB private memory, and published no pair. Probe 18 located the first failure
at `/savefile::byond_version`, which is encoded in the DMB header. Its finite
projection and complete ordered modifier diagnostics are now implemented; focused
initializer (7), savefile (1), and world-header (3) checks and the CLI build passed.
The next full compile attempt is pending. These figures are incomplete debug
attempts, not successful cold compiler benchmarks.

The production CLI now uses bounded parallel preparation of literal manifest
include candidates. Only files actually requested by the ordered directive pass
enter the semantic model; speculative preparations are released before resources
and lowering. Required-read errors preserve ordinary source diagnostics, while
worker failures remain internal errors. Three input-preparation and four shared
preparation checks passed. ABI preparation still reparses full bodies despite
retained settings; removing that duplicate pass is in progress.

Probe 19 passed resources/maps but expired at the 285 s watchdog while compiling
and published no pair (285.403 s externally; 1,915,981,824 sampled private bytes).
It used the binary before the subsequent initializer indexing fixes. Two
quadratic source paths were identified: receiver-group lookup per runtime write,
and full shared initializer reference scanning per target slot. Both now use
request-local indexes while retaining source order and exact slot conflict checks;
both focused gates passed. Compact settings reuse also removes the ABI-preparation
body parse and retained executable ASTs. More granular cold-stage reporting is
now records entry, success and failure durations. Compact settings/foreign
occurrence rejection, untyped lexical shadowing and predecessor ABI ordering
checks passed, and the CLI build passed. Probe 20 is running with these changes.
Probe 20 also expired during initializer processing (286.025 s external;
1,873,899,520 sampled private bytes; no pair). Startup capture completed in
6.286 s and ABI preparation in 1.610 s; neither explains the remaining delay.
Initializer classification/codegen reporting is now separated for the next run.
The subsequent immutable expanded arena and private parsed-body receipt removes
the last duplicate production body parse while retaining strict arbitrary-AST
validation and custom policy behavior. Thirteen preprocessing checks, receipt
rejection, two scalar AST equivalence checks, client-header behavior and inherited
ABI ordering all passed, along with the CLI build. A serial release build is
underway to establish target-relevant timings. No completed full build or cold
performance improvement is claimed yet.

Release probe 21 completed its failure diagnostics in 151.242 s externally,
sampled 1,824,755,712 private bytes, and published no pair. Input preparation
took 1.458 s, frontend 7.430 s, resource/map capture 4.695 s, startup capture
4.018 s, and ABI preparation 0.377 s. Classification plus error mapping took
70.272 s. The failed-stage report was emitted at 88.649 s; external completion
includes the subsequent large diagnostic output. This is a failed release
attempt, not a cold compiler acceptance result.

The error batch consists of missing intrinsic modifier facts (for example
15,677 `/atom::name` and 14,237 `/atom::icon_state` writes). Its location mapper
performed a full expanded-origin scan per error: a concrete quadratic reporting
path, now replaced with one request-local reverse provenance index. Diagnostic
output is also buffered while preserving format/order and propagating flush
errors. Both changes are awaiting integration gates. Intrinsic admission is being
split into positively evidenced mutable instance semantics and unknown wire
modifier bits; those bits must not be invented as zero.

The entries below describe the new uncached path. Older measurements later in
this document belong to the preserved original compiler unless explicitly labeled.

- `dmbc compile` now connects source capture, scalar resolution, pinned ABI
  preparation, ordinary/class/helper initialization, symbolic linking, map and
  resource composition, full DMB encoding, immutable pair publication and
  conventional `.dmb`/`.rsc` installation. Unsupported stages fail before publication.
  A tiny class/field/procedure project completed through this command with the
  default pinned template and bootstrap catalog (0.334 s in the latest smoke).
  This is a smoke result, not a DeepQuarry benchmark.
- Shared retained-engine validation exposed and fixed implicit constructor paths
  and qualified `operator/=` name extraction. The actual class/field/procedure
  composition fixture passed before the subsequent reachability/static additions.
- Skin attachment passed two source-bound checks. Resource encounter collection
  passed 31 native archive control cases. Additional raw formats have fresh
  compile-only controls; the nine-format comparison and interpolation-discovery
  focused gates passed. Qualified resource aliases also passed frozen-table binding.
- Raw regex strings no longer treat `[` as DM interpolation. The actual project
  now parses 1,370 chunks and 326,543 declarations instead of swallowing the final
  39 MB inside one statement. Probe 12 completed the frontend model: 43,921
  types, 281,789 members and 64,964 procedure bodies. It failed later in resource
  discovery on an interpolation expression. Total failed attempt: 46.198 s,
  sampled maximum private memory 1,216,241,664 bytes. This is an incomplete
  compile attempt, not a successful cold-build latency. The frontend-completion
  audit preserves the original receipt and corrects its old analyze-only flag.
- Probe 13 passed frontend capture and resource discovery, then failed during map
  initializer lowering on an unsupported declared-variable-type query. The failed
  end-to-end attempt took 91.858 s with sampled maximum private memory
  1,775,841,280 bytes. No complete output pair was published. Semantic repair and
  map-origin diagnostics are in progress; this is not a cold-build benchmark.
- Probe 14 completed resource capture, map projection, descriptors and common
  map-initializer lowering. It then stopped on an uncertified procedure ABI.
  The failed attempt took 109.756 s and sampled 2,041,708,544 private bytes.
  Nontext parsing took 0.080 s, asset capture 6.937 s, resource order 6.435 s,
  resource projection 4.450 s, symbol binding 4.119 s, map projection 0.216 s,
  descriptors 0.085 s and map initializer lowering 0.187 s. These debug timings
  locate current work; no executable pair or acceptance benchmark is claimed.
- Probe 15 passed the inherited-verb namespace boundary and stopped at the
  uncertified native `Crossed` callback. The external attempt took 57.404 s,
  sampled 1,943,654,400 private bytes, and published no pair. Driver timings:
  frontend 30.779 s, captured facts 0.427 s, resources/maps 12.880 s,
  link inputs 0.137 s and compilation through the ABI stop 11.175 s.
  Resource projection was 0.212 s after reusing validated resource identities.
  These are debug failed-attempt observations with different stop points and
  uncontrolled filesystem cache state, not successful build latency or parity.
- Production startup facts are captured once, privately sealed and borrowed from
  the immutable frontend. ABI preparation and initializer lowering reuse them;
  detached generic plans retain strict content validation. Procedure occurrence
  lookup is indexed rather than a full scan per body. Two startup and three cold
  integration checks passed. Parallel capture and AST-clone reductions are next.
- A tiny source containing a resource-valued field and inline client stylesheet
  completed actual CLI composition and publication in 0.718 s. Its DMB was
  21,969 bytes and RSC 64 bytes; this is only an integration smoke.
- Authored `/client parent_type = /datum` now overrides the captured engine's
  default parent. A regression proves authored parent conflicts and cycles still
  fail. Source error locations and ABI failure details are being tightened.
- Procedure-local statics have exact structural identities, typed producer and
  resolver, and shared variable-slot relocation. Two producer tests and the
  codegen tuple/parameter-shadowing test passed. Their startup and final footer
  integration passed focused cold and admitted-lowering checks with one and two
  workers. Full-project admission remains guarded until complete.
- Absolute root proc/var declarations no longer inherit the preceding type owner.
  Global procedures are separate from the instance inheritance namespace. The
  focused adapter gate passed 14 checks. The combined cold gate passed its class
  fixture and procedure-static checks passed after separating root globals from
  instance inheritance. Full-project lowering coverage is still being established.
- Six frozen runtime observations are finalized in `phase0/BASELINE_REPLAY_REPORT.md`:
  40 stable test differences, 79 variable test observations, no missing tests.
  BYOND crashed after complete results in two repetitions; native exited normally
  in all three. Source/ownership coverage remains incomplete and parity is not claimed.
- The static frozen-output debug inspector decoded both images without errors.
  BYOND has 73,108 file and 467,499 line instructions; the preserved native image
  has zero of either. `phase0/DEBUG_COVERAGE.md` records this attribution limit;
  it does not certify runtime ownership or explain behavioral divergence.
- Four orphan prototype crates (`dm-compile`, `dm-compiled`, `dm-output`, `dm-host`)
  were removed in `ca5011d813`. Their command documentation and runtime smoke
  script are archived for the original checkout. The new CLI uses shared per-drive
  output stores; the focused store-selection gate passed.
- Full encoding of the preserved 47,843,708-byte DMB took 0.161 s and reproduced
  the input exactly in the recorded sample. That measurement excludes linking,
  resource output and publication; it supports keeping full encoding in this design.

Phase 0 and Phase 1 remain open. No successful complete DeepQuarry build, new
runtime parity result, cold-build acceptance timing, incremental cache or daemon
completion is claimed by this checkpoint. No new DreamDaemon or external profiler
was launched for these integration checks.

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

## Current integration follow-up

- Checked ABI/debug migration is committed as `8e8f0ee8f6`. Ordered initializer
  IR/planning, root global storage, inherited engine ABI capture and bounded DMB
  composition are committed as `20d05a4c4e`. The second focused gate passed 96
  tests (IR 10, linker 4, tree 56, client 26); its subsequent CLI build passed.
- Source-only probe 5 exited after 29.711 s, with 1,602,334,720 bytes sampled
  maximum private memory. Declaration parsing completed; tree resolution rejected
  `world.cache_lifespan`, which the partial catalog omitted. The positive field
  entry is now saved, supported by the pinned declaration_metadata fixture; no
  default/type is invented. Receipt:
  `E:/dmb-native-v2-phase0/source-analysis-probe-20261006-5/receipt.json`.

- Source-only probe 4 exited with a declaration error after 21.600 s, with
  1,654,022,144 bytes maximum private memory in one-second samples. It rejected
  the legal argument declaration `obj/instance/`. The trailing separator parser
  fix is saved with a regression check; a successful real-project model has not
  yet been demonstrated. Receipt:
  `E:/dmb-native-v2-phase0/source-analysis-probe-20261006-4/receipt.json`.
- Procedure ABI preparation now preserves guarded settings, argument modifiers
  and arrays. Current debug emission uses typed source relocations. Integration
  checking caught decimal versus hexadecimal debug opcode values; the correction
  preserves bytecode-boundary validation. These changes are awaiting the current
  focused check gate.
- Parallel implementation continues on root global storage, ordered symbolic
  initializer plans, inherited ABI capture and bounded DMB composition. The new
  CLI still exposes analysis only. No full Phase 1 compile or performance target
  is claimed from these frontend measurements.

## Artifact location and limits

### Active Phase 1 integration

Full DMB encoding is now measured on the frozen reference image: 47,843,708
bytes encoded byte-identically in 0.161128 s. Decode was 0.157183 s and reference
validation 0.020041 s. This one in-process sample used the development profile
with the binary-format package optimized at level 2. Input OS cache state was
uncontrolled. It excludes symbolic linking, resources, and publication; it is
not a compiler benchmark. Receipt: `fixtures/phase0/dmb_encoding.json`.

The latest focused gate passed linker (5), resources (11), and tree (62)
checks. The client passed 43 of 44 checks; the remaining regression concerns
the identity of the effective procedure when an implicit definition precedes
its formal declaration. That is being investigated against the selected body,
rather than assuming that source order and occurrence numbering coincide.

Current uncommitted integration includes typed initializer lowering, map
projection and initializer units, class projection, world directives, and
argument-source helpers. Complete class/map/resource orchestration and a
compilation CLI remain work in progress. These are not completed Phase 1 gates.

Fresh DreamMaker compile-only controls certify raw RSC payloads for DMI, PNG,
OGG, TTF, text, HTML, CSS, JavaScript, JSON, and DMF. Evidence and limits are in
`fixtures/phase0/resources/`. Other resource transformations remain unproven.

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
