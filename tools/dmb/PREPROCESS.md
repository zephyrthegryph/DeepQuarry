# Preprocessing contract — Phase 0

Status: proposed architecture contract with eight captured DreamMaker runtime probes;
native paired observations and human review remain pending. Reference
producer: `ac1af55d1a`. This document specifies the replacement's requirements;
it does not claim that the preserved producer already implements include regions.
Fixtures live in `fixtures/phase0/preprocess/manifest.json`. The compact DreamMaker records are in
`fixtures/phase0/preprocess/evidence/byond-runtime-observations.json`. Source
inspection and finite runtime observations are distinguished below.

## 1. Inputs and outputs

Inputs are the captured DME/DM bytes, define set, target/compiler version, canonical
project path mapping, and resource-search inventory. An include occurrence is not
identified solely by its file: two occurrences may observe different macro state.
Output is one ordered stream of expanded DM tokens and non-text items, complete
diagnostics, current token origins, and the terminal macro/search state.

The preserved producer's `preprocess_project` comment explicitly requires repeated
include expansion in occurrence order. Its `Context::visit` handles DMM includes
as ordered map items, DMF includes as read skin items, and other included files by
recursive traversal. These are source observations, not independently established
DreamMaker rules. The manifest distinguishes unsupported probes from those paths.

## 2. Ordered items and directive state

A text region is a maximal interval of one source file between include directives.
An active include splits its parent interval; the child's items appear at that exact
position before traversal resumes in the parent. Keep occurrence identity, canonical
source path, source byte/line extent, include chain, and ordinal separately from the
reusable region value. Inactive includes produce no child tokens or resource items.

The sequential directive interpreter owns conditional state: each frame carries
parent-active, branch-taken, current-active, and whether `else` was seen. It evaluates
conditional expressions with the actual macro state at that directive. A parent
conditional spanning an include remains suspended during the child and resumes with
the same frame. A child's conditionals must close in that child; unbalanced/cross-file
conditionals are a diagnostic, unless a paired fixture establishes a different rule.
The captured `conditional-boundary` probe returns after=2; it supports this
case but does not establish the unbalanced/cross-file diagnostic rule.

The directive pass computes both the active item list and exact incoming expansion
state. Parallel region expansion may begin only after that state exists. It must not
independently reevaluate a parent conditional against a child's later macro effects.
Regions receive active spans or an explicit conditional-entry snapshot; the choice
of representation cannot change which bytes are active. Structural directive reads
(`#if`, `#ifdef`, include selection) are recorded even if a text region is empty.

### Manifest text has distinct encounter and emission order

The preserved base test `manifest_dm_is_deferred_but_macros_expand_at_encounter`
asserts a special DME rule: active DM text in an included `.dme` expands using the
macro state at encounter, but is emitted after ordinary included DM text. The test
expects an ordinary body's `early` procedure before deferred manifest `late` and
`second` procedures, while `late` still contains the earlier macro value 2 rather
than the body's later value 4. `included_dme_preserves_active_startup_dm_and_cache_replay`
and `cached_dm_subtree_preserves_deferred_manifest_startup` also assert preservation
through replay. The runtime probe also observes early=1, second=3, late=2. This supports
encounter-time macro expansion for that input; it does not itself inspect
procedure table emission order.

Therefore retain both directive encounter ordinal and token emission ordinal. Macro
effects and conditionals execute at encounter; deferred text carries its already
expanded tokens and origins into the emission queue. Do not defer expansion itself,
or sort declarations by encounter ordinal afterward. The earlier ordinary-DM child
interleaving rule applies to DM text; it must not erase this manifest exception.
The exact scope of deferral for nested manifests requires the paired fixture below.

Non-text includes retain source ordinal and directive provenance. DMM and DMF bytes
do not enter the DM token parser. Their content identity and existence are captured
by their actual consuming stage. Missing active inputs are errors; missing inactive
inputs are not read. Duplicate non-text items are retained until their downstream
ordering contract explicitly permits deduplication. Unknown include extensions and
macro-computed include operands remain pending probes, not invented support.

## 3. Macro dependencies and effects

Every macro-table lookup records positive or negative answers, including recursive
expansion, function-like macro argument expansion, and conditional tests. Definition
identity must include parameter order and replacement tokens, not physical IDs.
Effects are the ordered successful define/undef operations actually performed.

An incoming dependency is a lookup whose answer originated outside this region.
A lookup after an internal definition is not an incoming read of that defined name,
but external names reached through its replacement still are. For example:

```dm
#define LOCAL EXTERNAL
var/value = LOCAL
```

`LOCAL` is internal; `EXTERNAL` is incoming. A local definition selected by `#if FLAG`
also depends on the incoming `FLAG` test. A local `#undef X` makes subsequent absence
of X internal; it does not erase earlier incoming reads of X. Do not collapse distinct
incoming answers at different lookup sites when intervening effects can change them.

The cache key is region bytes plus the reviewed preprocessor/lexer contract version.
Variants contain dependency answers, output tokens, relative origins, diagnostics,
and ordered effects. Reuse requires every external state dependency to match. Effects
are replayed only from a validated variant and in their original order. A speculative
parallel validation result beyond the first failed region is discarded/rechecked
after that region's new effects have established the real following state.

The delta-name optimization is permitted only when matching occurrence lists and
previous per-position states exist. It represents differences at that exact boundary,
including removal/reconvergence, not a monotonic set of everything changed anywhere.
Fresh processes and changed item lists validate all dependencies directly.

## 4. FILE_DIR is a stack and a search domain

In the preserved source, an object-like `#define FILE_DIR value` with nonempty value
pushes a directory and its macro definition. `#undef FILE_DIR` pops one directory and
restores the previous definition; on an empty stack it leaves the name absent.
Command-line FILE_DIR initialization also enters the stack. A child include's push/pop
effects persist after returning to its parent. Do not model this as ordinary last-write
macro assignment. Empty definitions, function-like definitions, and unmatched pops
are probes whose runtime results must be recorded before claiming parity.

The entire ordered incoming stack is an external dependency when a region pops or
observes a stack entry not pushed inside that region. Tracking only the top definition
is insufficient: two equal tops can reveal different predecessors after one pop.
Internal pushes can be replayed; a pop's effect must operate on the validated incoming
stack rather than caching the old revealed directory as an unconditional assignment.

Resource lookup is a separate domain from declaration-tree identity. Capture ordered
search roots, root existence, directory inventory, failed earlier candidates, and the
selected path/content according to the resource contract. Adding `early/icon.dmi`
must invalidate a lookup formerly selecting `late/icon.dmi`, even with an unchanged
tree and unchanged literal. Expansion records FILE_DIR macro reads; lowering records
actual resource-search queries. Neither may substitute the other's narrower proof.

## 5. Paths and portability

Use two representations: host access paths and semantic paths. Semantic paths use `/`
separators and a stable project-relative form for in-project files. Normalize `.` and
resolvable `..` lexically without discarding unresolved leading `..` or escaping the
root silently. Preserve spelling/case unless target filesystem equivalence has been
established; do not lowercase string literals or resource names globally. Host paths
may retain drive/UNC prefixes; those prefixes are not silently inserted into reusable
semantic values. External inputs need an explicit stable mount mapping or must decline
cross-root sharing. Symlink/junction identity and case aliasing require captured policy.

Text includes resolve relative to the containing file, as observed in the base source.
FILE_DIR resource roots resolve against the project directory. Canonicalization is
shared by fresh directive execution and cached effect replay. `__FILE__` uses the same
semantic form as provenance. `__LINE__` is the current consuming line. These expansions
are position dependencies; regions not observing them may share values across files.
The base's simple `normalize` implementation drops parent components by popping; this
document does not treat that implementation as proof for unresolved/external paths.

## 6. Parsing and provenance

Concatenate expanded tokens in item order. A declaration chunk entirely contained in
one region may reuse its parsed fragment. A chunk spanning regions is parsed from the
joined stream each build; it must retain indentation, token boundary, continuation,
and enclosing declaration context. Never parse each included file as an independent
top-level program when it appears inside an expression or type declaration.

Reusable values store relative origins. Each token origin identifies its source span
and macro expansion chain; each macro origin preserves both invocation and definition
locations. The current occurrence table binds them to actual files/include chains.
Sharing identical text does not share absolute diagnostic locations. Moving a region
without changing its bytes refreshes provenance, body handles, debug lines, and analysis
locations. Metadata `set` statements remain in the semantic declaration projection;
only executable bodies are excluded from skeleton identity.

Diagnostics are part of the cached result and are replayed on every hit, in current
source order. A cached error must appear on a second identical build, then disappear
after correction. Source/read errors are not represented as absent dependencies or
successful empty expansion. No output is published while errors remain.

## 7. Evidence and fixture protocol

Each manifest case has separate source-support, preserved-producer execution, and
paired DreamMaker status. `pending` means no receipt exists. A successful parser run
does not establish macro semantics or DMB behavior. Record exact compiler binaries,
target/defines, input hashes, stdout/stderr, and observable output for each execution.
Paired receipts compare expanded/diagnostic behavior where observable and game-visible
results otherwise. Unsupported probes may legitimately diagnose, but neither accept
nor reject outcomes are predetermined by these fixtures.

Apply each listed mutation and revert it: compare incremental versus cold results
using the same captured snapshot. The fixture scripts are input data, not a test runner.
`phase0_preprocess.dme` wrappers intentionally avoid station includes to isolate the
specified behavior. The contract remains reviewable before implementation proceeds.

### Existing base assertion inventory

Inspected at `ac1af55d1a`, `dm-preprocess/src/lib.rs`:

| Contract | Existing assertion |
| --- | --- |
| Repeated include sees current macro state | `include_order_and_macro_environment` |
| Inactive map includes omitted | `map_includes_follow_active_conditional_branches` |
| Child origins/effects survive replay | `nested_cache_replays_child_origins_macro_effects_and_rejects_child_edit` |
| FILE_DIR ordered roots and restored definition | `file_dirs_keep_active_order_through_leaf_disk_replay`, `undef_file_dir_restores_previous_definition`, `cached_undef_file_dir_restores_previous_macro` |
| Recursive macros disabled without infinite recursion | `recursive_macro_names_are_disabled_without_copying_the_table` |
| Continuation origin is first physical source line | `continued_source_line_origin_is_first_physical_line` |
| Variadic macros and token pasting | `deepquarry_token_paste_and_variadic_macros` |
| Deferred DME text expands at encounter | `manifest_dm_is_deferred_but_macros_expand_at_encounter` |

`dm-preprocess/tests/native_semantics.rs` additionally asserts nested macros,
conditionals/location literals and CRLF continuation line numbers. Its comment
reports a historical 516.1687 compilation; Phase 0 must preserve or locate the raw
receipt before marking a new paired comparison validated. The root's active base
gate will provide separate execution evidence; this inventory does not predict it.

## 8. Captured DreamMaker observations and corrected predictions

Eight observation wrappers compiled and ran with exit0 under BYOND516.1687 in
`D:/dmb-native-v2-phase0/preprocess-observations-byond`. Compact evidence preserves
the original actual/expected/equality records, commands, log hashes, input hashes,
tool receipt, and outcome timings. The six child-effects, incoming-internal,
conditional-boundary, joined-expression, paths-origins and deferred-manifest
cases matched their source-derived predictions. This is finite DreamMaker
evidence; native runtime parity remains pending. File observations normalize
only final suffixes, so they do not certify complete provenance.

### Repeated inclusion: observed1, previous prediction2

The repeated fixture includes the same `body.dm` twice under VALUE1 then VALUE2.
DreamMaker's final global result is1. The prior prediction2 is preserved as a
failed equality record. The wrapper now expects1 for this exact input. This
observation cannot distinguish suppression of the second same-file include from
first-initializer behavior on repeated declarations. The preserved native source
expands repeated occurrences, but that implementation is not an oracle for
DreamMaker declaration behavior. A distinct-file equivalent and two separately
named occurrence values are needed before generalizing either explanation.
Thus ordered include occurrences remain necessary architecture state; emitting
all repeated tokens as a universal DreamMaker rule is not yet certified.

### FILE_DIR: archived payload versus search-state ambiguity

The original wrapper read four characters from `during`; actual `earl` differed
from predicted `late`. `after` read `early` as predicted. Both fixture assets have
different bytes (`early\n`, `late\n`) but the same literal archive name
`marker.txt`. The captured RSC is39 bytes with one named marker.txt entry whose
payload is `early\n`; its complete bytes/hash are preserved in the compact
evidence. This is not an equal-content alias collision. It demonstrates the
selected archived payload, without proving when either reference resolved.
Possible same-name archive convergence and final search-domain resolution are
not separated by this fixture. The preserved native resolver searches final
FILE_DIR roots in reverse order; after the pop that list contains only early.
That explains native-source behavior but does not establish DreamMaker's
encounter-time search rule.

The updated wrapper reads five characters for both references and expects
`early`; the old four-character mismatch remains immutable evidence. Its new
wrapper hash/runtime capture is pending. The FILE_DIR stack description in §4
is preserved-source evidence and a proposed state representation, not a proven
per-reference search/alias rule. Future disambiguation must use different archive
names or independently inspect selected payload identities at each occurrence.

### Distinguishing probes pending capture

- `repeat-same-include` versus `repeat-distinct-include`: identical body bytes
  under VALUE1/2, but the latter uses a second filename. Unique first/second
  declarations and SAW_ONE/SAW_TWO macro flags disclose whether the second
  occurrence was interpreted. Shared result discloses duplicate initializer
  precedence independently when both occurrence flags/declarations are present.
- `file-dir-unique-pop`: separate before/during/after resource names exist in
  both early and late roots with distinct payloads. Macro string values disclose
  encounter state; payloads disclose whether resource resolution follows that
  state or the final domain after pop. Different archive names prevent the
  same-name explanation from masking the observation.
- `file-dir-unique-retained`: keeps both roots active; separate payloads establish
  search priority for this captured inventory, independently of a pop.
- `file-dir-same-name`: explicit before/during/after shared.txt references retain
  aliases, payloads and reference equality. Read its RSC beside the unique-name
  results to distinguish archive convergence from search selection.

These wrappers emit actual values without expected/equality fields until capture.
The DME roots contain directives only; observation declarations live in included
DM files, keeping manifest-text emission behavior separate from these questions.
No fixture was launched while preparing these probes.

### First distinguishing capture and repairs

The initial run is retained in `evidence/distinguishing-first-capture.json`,
including complete compile/runtime logs and hashes. Same-file inclusion observed
result1, first1, second_present0, then the observer itself errored on an absent
global. Dynamic global reads now explicitly check membership and return null
when absent, allowing a complete record and shutdown. Distinct-file inclusion
reported duplicate definition of result. That diagnostic is now isolated in
`repeat-distinct-duplicate` (expected compile error); the positive distinct-file
probe keeps unique declarations and macro flags without a duplicate result.

The unique FILE_DIR cases failed because FILE_DIR expanded to an unquoted host
path when used as a DM expression. Those invalid expression observations were
removed; define/pop directives and unique resource payload checks remain. The
same-name case ran successfully, yielding early-shared newline at all three
references, shared.txt alias text and equal references. These observations remain
finite evidence; repaired positive cases require fresh successful capture before
assigning a general search/inclusion rule.
