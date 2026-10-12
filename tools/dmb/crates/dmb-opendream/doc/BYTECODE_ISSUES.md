# Native output comparison: fix backlog

## Active residual review — 2026-09-28

The previous completed static snapshot passes 491 Rust tests (444 core), strict
Clippy, all 554 mutually accepted compiler-corpus cases, and whole-game
instruction/reference/branch audits. Its exact artifact hashes and comparison
counts are in `doc/audits/PARITY_REPORT.md`. Passing these gates does not certify every
remaining bytecode difference.

The latest completed package gate passes 564 tests (453 core), including the
constructor, readonly-reference and execution-budget repairs. Archive order matches
all 3,856 native entries. The following repairs are integrated and verified;
residual semantic classification remains in progress:

- **Map numeric constants (fixed, full-game boot checked):** negative and
  wide integral overrides were emitted with unsigned-word `PushInt`; negative
  pixel offsets became 32767 after clamping and broke lighting. The emitter
  now uses floating literals outside `0..65535`. The comparator's incorrect
  signed normalization is also repaired. Paired map tests and trusted minimal
  worlds cover negative offsets, 65535/65536, zero, and positive values; an
  intentionally corrupted initializer is detected. The full repaired trusted
  server initializes with zero translated-only runtime errors in captured logs.

- **Trusted server findings (fixed):** reserved intrinsic field IDs, readonly
  deletion, inherited appearance headers, callback flags, automatic names and
  raw text bytes now have native regressions. Expanded full-game metadata
  comparison reports zero differences. Runtime validation runs with `-trusted`;
  paired worlds complete initialization with shared baseline errors. See
  `doc/audits/SERVER_BOOT_REPORT.md`.
- **Initializer token semantics (fixed for observed inputs):** final DEBUG
  state selects unique allocation versus expression interning. All 17,456
  observed class assignment keys and 814 global keys are recognized; all
  19,617 native marker records retain their equality partition. Native
  constructor-family and DEBUG probes cover both debug-line settings.

- **Constructor expression entry (fixed):** `/proc/log_research` had a
  conditional branch that skips the inserted file constructor type operand.
  A native fixture also exposes type insertion inside conditional constructor
  arguments. Prefix placement and incoming labels now enter the whole
  constructor expression. Nineteen complete native bodies pass in both debug
  modes, including conditional named arguments, generators and dynamic paths.
- **Captured Src/World result lifetime (fixed):** an extra
  root getter before a field selector releases a managed call result earlier
  than native bytecode. Reuse is limited to the proven captured method context;
  ordinary getter-first behavior and branch joins retain fresh selection.
  Thirteen Src and seven World bodies pass exact native comparisons in both
  debug modes, with a negative getter-first control. All 352 previously
  observed adjacent retained-result selector hazards disappear in the fresh
  full game output; this bounded check does not prove every cache context.
- **Frontend constant validation (fixed):** native accepts nonnumeric `log`
  operands and emits runtime operations. Nested `initial`/`issaved` wrappers
  keep the outer selector and evaluate the underlying reference once.
  Direct local, global and class constant reads preserve readonly bindings;
  scope cleanup counts only actual runtime local slots.
- **Execution budget (fixed):** authored do/while tails use F9 on both outcomes;
  constant-true continues avoid double checks; switch defaults retain authored
  transfers; typed world iterators preserve category masks and subtype FA;
  exact mob/turf/area roots omit redundant FA; empty loops retain F8 self-edges.
  Background loops no longer insert synthetic sleeps. Across 62,318 paired
  procedure records, the conservative reachable budget-count audit has zero
  differences. Eighty-five raw count differences are unreachable F8 tails.
- **Lazy-pick constructor output (fixed):** inserted receiver/type operands
  stay outside the closed pick expression. Five complete native bodies cover
  ordinary, constant-weighted and dynamic-weighted output constructors.
- **Constant-condition cleanup (integration pending):** native omits constant
  condition evaluation, while an extra Test can release retained Eval early.
  Twelve native condition pairs pass focused tests. Skipped source declarations
  and builtin `.type` binding metadata are being checked before final integration.

- **Derived frozen receiver:** `OWNER.child.replace_child(other)` followed by
  `OWNER.child.read()` must retain the original child as native Cache does.
  Reloading the field selects its replacement. Three paired native probes
  establish the defect; the direct-root cache fix alone does not cover it.
  Computed parent expressions also require deferring child selection until
  after argument side effects, and nested safe-index scopes require all cache
  frames to be restored.
- **Switch frozen receiver (fixed):** case and default arms retain the proven
  pre-dispatch receiver. Twelve paired contexts pass, including independent
  keyed arm comparisons and conservative ordinary joins.
- **Frozen receiver builtins (fixed):** `initial` and `issaved` must
  inspect the retained child after a method replaces its binding. Reloading
  the child can select a different subtype and default value.
  Twenty strict paired bodies and safe-access controls pass in both debug modes.
- **Authored goto budget (fixed):** native forward and backward
  unprotected gotos use JmpLoop, including jumps to adjacent labels. Ordinary
  Jmp omits the CPU-budget check. Nine fresh native cases establish the scoped
  source annotation and lowering fix; protected gotos retain TryJmp.
- **Continue versus loop joins (fixed):** synthetic if/else
  joins near a loop tail use ordinary Jmp before the natural JmpLoop. The
  previous heuristic added an extra budget check. Current exports distinguish
  authored continue explicitly; four paired cases cover both dispatch forms.
- **Lazy multi-argument pick (fixed):** native PickSwitch evaluates only
  the selected expression. Eager NewList/Pick evaluates every candidate and
  changes side effects. Single-argument Pick keeps its list/scalar behavior;
  native probability thresholds require cumulative truncated weights.
  Twenty-two strict native cases pass, including nested/adjacent tables and
  300 candidates across packed numeric, string, resource and reference forms.
- **Pick receiver compilation context (fixed):** native candidate
  selectors can retain the pre-probability compilation context even when weights
  change the runtime cache. Eighteen paired bodies pass; this reproduces native
  selectors without claiming the runtime receiver remains unchanged.
- **Protected-loop boundary:** a native continue to the first protected
  instruction uses TryJmp, whose `target - 1` exception-range check can remove
  the active frame. Emitting ordinary JmpLoop retains that frame. Native
  compiler probes and VM dispatch tracing establish the distinction; source
  branch provenance is required where optimization removes the natural loop
  tail. Authored protected `goto` has the same requirement. Nine focused cases
  now pass; the refreshed package gate passes.
- **Resource archive order (fixed):** duplicate-content files retain distinct names.
  Native lookup chooses a node from an insertion-ordered CRC tree, and resource
  formatting exposes that node's filename. All payloads matching is insufficient
  when archive order differs. The corrected source-phase model now matches all 3,856 emitted entries
  in native order, with identical payloads, kinds, CRCs, sizes and source timestamps.
  Thirty portable fixture manifests and a 132-case native matrix preserve the rules.
- **Verb lookup namespace (fixed):** native verb and procedure calls must remain
  separate even when their display names collide. Typed and self calls preserve
  DynamicVerb selectors; eighteen strict native bodies pass in both debug modes.
  StaticVerb descriptor lookup resolves its display name through the same verb
  dispatcher, with negative wrong-name, invalid-ID and proc-namespace controls.
- **Resource timestamps (fixed):** new records use a current creation timestamp
  and the source modification timestamp with native 32-bit wrapping. Every
  source timestamp in the provisional full-game archive matches native.

The comparison and issue counts below are historical snapshots.

Static analysis of the matched Dream Maker 516.1687 build and OpenDream-to-DMB
translation, 2026-09-27. No DreamDaemon was run. Procedure IDs below refer to
these two specific artifacts, in native / translated order.

## Fix status (current iteration)

The counts below describe the original comparison, before these fixes.

- Fixed iterator filter masks, nested iterator save/restore and labelled-loop cleanup, including range/list mixtures and world datum enumeration. Native paired fixtures cover ten loop forms.
- Fixed equality value materialization and inequality condition testing. Eighteen native comparison forms cover conditions, returns and compound expressions.
- Fixed inherited mob darkness, world procedure membership and mutable-appearance subtype prototypes.
- Fixed savefile version provenance: this game explicitly assigns /savefile/byond_version = MIN_COMPILER_VERSION in code/__byond_version_compat.dm. The exporter previously omitted that standard variable. Native fixtures cover default, zero, 513 and 516, including header compatibility.
- Added selector-family, switch-target and modified-instance normalization without hiding unknown identities. Native call fixtures establish tested renamed, inherited and alias lookup behavior; broader cache/call equivalence remains unproven.
- Audited seven fewer generated procedures: all are duplicate constant initializers. The unused overwritten carpet prototype is harmless. See doc/audits/GENERATED_PROC_AUDIT.md.
- Compacted unreachable and duplicate immutable lists, with reference remapping and round-trip checks.
- Fixed debug markers disrupting receiver timing, stack-expression scanning, comparison conditions, dynamic initial/issaved and field-output analysis. Full debug lowering verification passes all 59,982 exported procedures.

No DreamDaemon execution is used. Static checks do not establish runtime parity for every remaining mixed bytecode difference.

## Final validation after fixes

- cargo test --all-targets: 371 passed, zero failures.
- cargo clippy --all-targets -- -D warnings: passes.
- Full debug audit: 59,982 procedures, zero lowering errors.
- Complete debug DMB/RSC emitted successfully. All 62,318 procedure records decode, typed operands validate, and instruction reassembly preserves every word.
- Every translated Teq now precedes Pop (11,981 occurrences); no bare Teq reaches return, logical operators or negation. Conditional Tne uses Test (3,392 occurrences).
- Native/translated iterator saves both total 1,179; restores are 1,202/1,204, with cleanup trampolines accounting for alternative control flow. Count agreement is supporting evidence, not an equivalence proof.
- Final debug DMB is 47,498,366 bytes; native is 45,526,112. List count is 122,519 versus native 125,539, down from the old translated 360,414.
- Final comparison pairs all 59,465 named/initializer procedures: 13,280 normalized matches, 46,185 differences, zero unmatched. Maps have zero semantic differences; resource identities match (3,835). All 3,856 named RSC payloads are byte-identical; only timestamp/source_timestamp and entry order differ.

Remaining structural candidates are 8,857 cache/reference, 7,240 call-result encoding, 36 branch/switch, 30 comparison/short-circuit, 360 other-operand, and 29,662 mixed pairs. These are not confirmed defects, and they are not certified harmless. Broader stack/cache and control-flow equivalence analysis is still required to certify the entire program.

Artifacts: D:/opendream-diagnostic/deepquarry-fixed-debug.dmb, matching .rsc, ixed-parity-summary.txt, ixed-parity.ndjson, ixed-equality-contexts.txt, ixed-opcode-audit.txt, inal-debug-audit.txt, inal-tests-stable.txt, inal-clippy-stable.txt.

## Original confirmed correctness issues

### 1. P0: list enumeration encodes a slot number as a filter mask

`src/od_lower.rs`, OpenDream `CreateListEnumerator` (`0x3a`, around line 2642),
emits `IterLoad [5, local_count + iterator_id]`. The second operand is a native
type/filter mask, not a local slot. Filtered-list enumeration has the same
problem; client enumeration also mixes an iterator ID into its mask.

Evidence: `/atom/movable/proc/ledger_apply_drop_policies`, IDs 19175 / 40237.
Both source loops use `as anything`. Native emits `[5, 4096]` for both loops;
translation emits `[5, 6]` and `[5, 7]`. These select different filtering rules.
Native mode-5 masks across this build are 0, 1, 2, 3, 32, 256, 291, 4096 and
16384; translated masks also contain many local-derived values through 212.
Not every native list loop should use 4096: untyped and typed loops need their
own correct masks.

**Fix:** preserve declared iterator filtering/type semantics in compiler export
and lowering. Verify untyped, typed, `as anything`, associative and client loops
against native compiled fixtures, including null and mixed-type entries.

### 2. P0: nested iterator state is not saved/restored

Native output contains 1,179 `IterPush` and 1,202 `IterPop` instructions;
translation contains zero of either. In the same `ledger_apply_drop_policies`
pair, native saves the outer iterator before the inner loop and restores it
afterward. Translation uses the same native iterator machinery without those
operations. `DestroyEnumerator` (`0x3c`) only removes bookkeeping in the lowerer.

**Fix:** model native iterator lifetime/stack state separately from OpenDream
iterator IDs. Cover nested loops and every exit route: exhaustion, break,
continue and return. Exact opcode totals need not match if another valid
strategy is used, but outer iteration must survive inner enumeration.

### 3. P0: equality results are not materialized in value contexts

Native `Teq` (`0x37`, `==`) is followed by `Pop; GetFlag` when its result is
needed as a value. The lowerer emits bare `Teq` for OpenDream CompareEquals
(`0x0f`, around line 5365).

Examples:

- `/area/proc/flag_check`, IDs 46562 / 46978: native
  `Teq; Pop; GetFlag; Ret`, translated `Teq; Ret`.
- `/area/Entered`, IDs 46592 / 46966: native
  `Teq; Pop; GetFlag; JmpAnd`, translated `Teq; JmpAnd`.
- Native `/proc/contract_evidence_compare`, ID 1540, contains both
  `Teq; Pop; GetFlag; Ret` and `Tne; Ret`, demonstrating the different contracts.

Across all decoded procedures, translated `Teq` directly precedes 162 returns,
1,201 `JmpOr`, 1,482 `JmpAnd` and 163 `Not` instructions. Native has zero of
those four adjacency patterns: its 12,125 `Teq` instructions all precede `Pop`.
These are instruction occurrences, not distinct procedures or independent bugs.

**Fix:** materialize equality values for returns, assignments, arguments,
arithmetic, negation and short-circuit expressions. Preserve native flag-branch
handling when the comparison feeds a direct condition. Update stack-effect
assumptions used by constructor argument scanning too.

### 4. P0: inequality conditions discard the result instead of testing it

`Tne` (`0x38`, `!=`) produces a value. Native bare `Tne; Ret`, `Tne; JmpOr`
and `Tne; Not` are legitimate and must not receive the equality conversion.
The JumpIfFalse lowering around line 6804 treats both `Teq` and `Tne` as
requiring `Pop`.

Evidence: `/proc/get_turf_pixel`, IDs 391 / 309, terminal inequality condition:
native `Tne; Test; Jz`, translated `Tne; Pop; Jz`. Native has 3,489
`Tne; Test` adjacencies; translation has zero and instead 3,392 `Tne; Pop`.
Counts are a census, not a one-to-one alignment of those sites.

**Fix:** distinguish comparison result contracts in conditional lowering.
Verify standalone and compound `!=` conditions, especially the final term of
an `||`/`&&` chain. Do not apply the equality fix to every comparison opcode.

### 5. P1: implicit mob darkness defaults are lost

829 mob records have native `see_in_dark = 2`, translated `0`. In
`src/od_emit.rs` around line 1594, compact sight records without an explicitly
stored darkness field use `unwrap_or(0)` when promoted to extended records.
The effective built-in default is 2. Updating another sight field therefore
overwrites an inherited darkness default.

**Fix:** carry effective defaults when expanding compact records. Verify
inheritance, an override of only `see_invisible`, large sight flags, and explicit
darkness values including 0 and 2.

### 6. P1: authored savefile version is omitted

Native `world.savefile_byond_version` is 516; translated is 0. Other compared
world numeric settings agree. This is a confirmed field discrepancy; its
runtime consequences have not been tested.

**Resolved provenance:** the authored /savefile/byond_version override supplies this value; it is not a compiler default. The patched standard declaration preserves it in export.

## Validation and comparison issues

### 7. P1: prove static-to-dynamic call selector equivalence

The earlier detail report contains 1,447 rows replacing a native static proc
selector with a translated dynamic selector. This is not yet a confirmed bug.
Example `/atom/movable/screen/combat_mode/Click`, IDs 19507 / 40589: native calls
static `/mob/proc/set_combat_mode`; translation calls `Usr` with the dynamic
name `set combat mode`.

**Work:** compare effective callee resolution with overrides, renamed verbs,
aliases and inherited methods. Preserve static selector provenance where those
semantics differ. The comparator currently folds DynamicProc/DynamicVerb into
Field; give them separate normalized representations to expose selector issues.

### 8. P2: track cache state before declaring receiver changes equivalent

8,408 procedure pairs have identical opcode sequences and only cache/reference
operand differences. Inspected examples are redundant cache reloads:
`/area/Destroy` (46586 / 46935), `/area/proc/check_static_power`
(46553 / 46965), and `/area/proc/adjust_mob` (46572 / 46990).

**Work:** add cache-state dataflow comparison across branches and effectful
arguments. Removing every explicit cache receiver syntactically would hide
real receiver-selection errors. These pairs are candidates, not 8,408 proofs.

### 9. P2: normalize switch operands and align alternative instruction sequences

219 pairs differ only in branch/switch operands; some complex switch operands
still contain raw string IDs or offsets in the comparator. Normalize those
before treating the differences as lowering defects. Also align proven
`SetVar; GetVar` versus `SetVarExpr` fusions and discarded call-result forms.
Example assignment fusion: `/area/proc/main_air_alarm_is_operating`.

6,857 pairs have only CallStatement/Call opcode changes, although operands may
also differ. Validate result-discard and selector semantics before accepting
the whole family. Debug markers and supported branch targets are already
normalized.

### 10. P2: investigate remaining generated records and world membership

Canonicalizing `/proc/` and `/verb/` spelling and matching duplicate signatures
eliminates all 30 apparent missing records on each side in the original report.
The earlier ten argument/local mismatches were reversed override pairings;
the owner-aware table audit reports zero discrepancies. Do not fix those as
compiler bugs.

Total procedure tables still contain 62,325 native versus 62,318 translated
records. Audit anonymous/generated argument-source records and the one world
procedure-membership discrepancy separately. Named-pair coverage does not
prove those remaining records equivalent.

### 11. P2: reduce output growth after correctness fixes

Lists grow from 125,539 to 360,414; DMB grows by 9,930,009 bytes (21.8%).
Investigate duplicate list/code/metadata allocation and interning. This is an
output-size issue, not evidence by itself of incorrect execution.

## Classification coverage

The expanded audit matches 59,465 named/initializer records, with zero unmatched
records in that scope. 10,704 normalized pairs match; 48,761 differ.

| Structural family | Pairs |
| --- | ---: |
| Cache/reference operands only | 8,408 |
| CallStatement/Call encoding | 6,857 |
| Branch/switch operands only | 219 |
| Broad comparison/short-circuit candidate | 2,608 |
| Other operands only | 2,155 |
| Mixed, same instruction count | 16,827 |
| Mixed, different instruction count | 11,687 |

Categories are mutually exclusive structural buckets, not semantic verdicts.
The broad comparison bucket includes both equality and inequality; the separate
opcode census above supplies the refined evidence. Mixed and other-operand
families remain unresolved. Strict matching is not a runtime parity percentage.

Reproduction tools: `dev-scripts/output_parity.rs --classify` compares and writes
per-pair classification rows; `dev-scripts/equality_contexts.rs` counts comparison
followers separately by opcode and prints example contexts.

Local evidence files:

- `D:\opendream-diagnostic\bytecode-classification-summary.txt`
- `D:\opendream-diagnostic\bytecode-classification.ndjson`
- `D:\opendream-diagnostic\equality-contexts.txt`
- Native: `D:\dmb-matched-reference-0996c651\deepquarry-static-ref.dmb`
- Translation: `D:\opendream-diagnostic\deepquarry-translated.dmb`

Assets and maps retain the previous audit results: all 3,856 named RSC payloads
match byte for byte; map semantic discrepancies are zero. RSC order and metadata
differ. This audit identifies concrete fixes; it does not establish full runtime
translation parity.

## Additional defects found during iteration

Native paired probes identified three further cases after the first rebuilt comparison:

- Compound conditions: a short-circuit edge could bypass the final producer and reach its flag-based cleanup. The lowerer now preserves the boolean value and tests it at a merge, matching native equality, membership and intrinsic conditions. Direct single-predecessor conditions retain their native flag optimization.
- Preserved standard-library relocation: nested static procedure/verb selectors were not remapped after authored procedures moved the table. Global calls also remapped their argument count instead of their procedure operand. Both are corrected; regressions check database construction and independent call-count/selector relocation.
- Builtin type constants: class reordering changed singleton list/file/savefile payload zero into a class ID. These singleton values now retain zero, including `/sound/New`.
- Ordinary interpolation: native FF01/FF02 selection depends on sentence context, including punctuation, quotes, whitespace and tag-shaped suffixes. The former whitespace-only rule is replaced by a paired backwards context scan. All 122 distinct templates in a 125-case fixture match native bytes; the compiler patch also preserves bold controls.

- Bare self calls now resolve display names from the current type and its ancestors, including underscore conversion, explicit aliases and inherited overrides. This prevents unrelated same-name declarations from changing the binding.
- The earlier 32 pairs in the branch-only structural bucket were checked for destination equivalence; they differ through same-operation short-circuit chains or numeric switch case order. The evidence is D:/opendream-diagnostic/branch-chain-audit.ndjson.

The final compound-condition audit finds zero short-circuit branches whose join consumes a boolean via Pop then Jz/Jnz (previous translation: 2,007; native: zero). All 18 paired comparison fixture procedures match native words exactly.

All 30 final comparison/short-circuit candidates are accounted for by null-check simplification: 39 native GetVarNull/Teq patterns become IsNull, and four GetVarNull/Tne patterns become IsNull/Not. This resolves their comparison component; unrelated cache/call differences retain their existing status. Evidence: D:/opendream-diagnostic/remaining-comparison-null-candidates.json.

The final branch-only bucket contains 36 pairs. The expanded audit also resolves string-case identities and checks variable-width switch values; all 36 have zero unexplained destinations after same-operation short-circuit chain chasing and switch-case ordering. The report at `D:/opendream-diagnostic/branch-chain-audit.ndjson` now describes this final output.

## Debug-boundary follow-up

- Formatted output fusion previously assumed the format instruction occupied the last three words. A debug line inserted before output made that calculation overwrite its argument count and omit the output instruction. Fusion now locates the last executable instruction by decoded offset. The regression preserves the debug markers and compares executable words with native output.
- Method receiver analysis now ignores debug markers when identifying formatted, arglist and zero-argument receiver expressions, and when locating a conditional's initial test. Reconstruction retains the markers and their original offsets.
- A native receiver-mutation fixture checks ordinary field calls, safe calls and conditional receiver expressions with debug information enabled and disabled. Ordinary field calls read the receiver after arguments; safe and computed receivers preserve the previously captured receiver.

The remaining other-operand audit found no string-identity or static-call-identity discrepancies. Numeric iterator operand differences reflect manual filtering versus native filters. Sample initializer differences reorder independent assignments; sample switch differences reorder blocks with matching targets. Larger mixed groups still need equivalence analysis.

## Global variable-list intrinsic

OpenDream's `PushGlobalVars` now lowers to native `GetVar(Global VariableID)`
through a dedicated `vars` record of kind 82, outside the global declaration
footer. It previously emitted `PushVal(82, 0)`, which did not match the native
intrinsic representation. Native paired fixtures cover direct reads, indexed
reads and writes, aliases and enumeration. A conservative allocation hint is
pruned using decoded native operands, so a constant containing byte `0x5f`
cannot leave an unused intrinsic record in executable output. Direct assignment
to `global.vars` is rejected by Dream Maker as assignment to a constant.
