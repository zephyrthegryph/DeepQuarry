# Receiver and guarded mutation audit

The portable paired compiler fixture is `fixtures/lowering/cache_adversarial`:
DM source, DME manifest, OpenDream JSON, and native DreamMaker DMB (`.bin`).
Both compilers used version 516.1687. No DreamDaemon execution is required.

## Native rules established by the fixture

- Compound field assignment evaluates its RHS before reading the field owner.
  The RHS may replace that owner, including a child datum or an indexed list.
- A guarded chained lvalue saves the guarded base receiver. Direct field chains
  restore that base immediately before the mutation, then resolve the chain as
  nested native selector operands.
- Computed chained owners, including indexed and conditional expressions,
  retain their expression and restore the guarded cache after the mutation.
- Nested guarded mutations in an RHS need independent pending continuations;
  an inner terminal cannot replace the outer assignment's terminal.
- Three-field chains use right-nested selectors, for example
  `SetCache(Field(child), SetCache(Field(child), Field(value)))`.
- Discarded increment/decrement statements use native Inc/Dec rather than a
  retained postfix/prefix result.

The regression enumerates 60 authored globals explicitly and compares both
debug modes with native instructions after removing source markers. Missing
procedure identities fail the test. Six other authored globals retain known
equivalent cache materialization layouts and remain available for inspection.

## Confirmed corrections

Guarded chained field mutations previously emitted a field read without
consuming it as the mutation owner. Lowering now reconstructs direct selectors
or materializes computed owners, preserving guard exits and native RHS order.
Nested guards restore each saved receiver, and nested RHS mutations preserve
the outer continuation.

Computed guarded logical assignments retain the saved base until their common
join. Their short-circuit branch reaches the final cache restoration; their
null guard skips it. RHS cache restoration is independent of this base frame.

Native guarded AssignInto syntax compiles through cached receiver selectors
without a separate null-guard instruction. Its RHS precedes the base receiver;
computed chains use the native saved-cache sequence. The paired fixture records
these compile-time forms without inferring runtime null behavior.

Debug markers previously prevented direct field mutation selector folding.
The fold now ignores markers when identifying the sole executable receiver
read and removes only that read, preserving the markers themselves.

## Scope of evidence

Paired native bytecode establishes the receiver ordering and instruction forms
above. It does not establish exhaustive runtime equivalence for every remaining
cache-related difference in the full game. In particular, a global rule based
on the last cache write is invalid: nested selectors and saved cache frames
must be modeled together.

The verified static game pair was screened across all 9,022 procedures classified
as cache/reference-only differences. The read-only receiver model established
21,728 equal accesses and retained 6,371 accesses as unknown; it skips unknown
owners, effectful cache invalidations, and ambiguous local tables. Both observed
World.time/Src ownership defects disappeared after the ownership correction.
No procedure in this category was skipped for a different opcode layout. The
artifact is `D:/opendream-diagnostic/cache-owner-verified-audit.ndjson`, comparing
`deepquarry-verified.dmb` with the matched native static reference. Independent
constant initializer signatures matched for 5,702 procedures.

The bounded mixed-layout extension also admits equal numeric PushInt/PushVal
values and immediate discarded Call/CallStatement sequences, provided the Pop
is not a branch destination. Across the 24,600 cache-only and mixed-same-count
pairs, 14,817 still have unsupported layouts. The admitted pairs contain 26,742
equal accesses, 7,952 unknown accesses, and the same eleven store-order
candidates. This covers 761 additional mixed procedures; discarded-call
alignment admits no further procedure in this particular category. Artifact:
`D:/opendream-diagnostic/cache-owner-verified-call-mixed-audit.ndjson`. Null-check
rewrites remain unsupported by this audit; these counts do not prove the
skipped procedures or unknown accesses equivalent.

Further identity analysis uses nonempty local names occurring once in each
procedure, and global names occurring once in each complete variable table.
It resolves 881 more full references without assuming matching table ordinals.
The method-call extension compares only the resolved receiver before the call;
it does not equate static and dynamic dispatch selectors, and still invalidates
cache ownership after calls. This establishes 2,618 equal method receivers
separately from 27,623 equal full references. There are 4,453 unresolved accesses
and the same eleven store-order candidates. The artifact is
`D:/opendream-diagnostic/cache-owner-method-receiver-audit.ndjson`. Unsupported
layouts remain at 14,817; this is a bounded identity proof, not a runtime proof
for skipped code or unresolved accesses.

Conditional fallthrough and immediate symbolic GetVar-to-Cache transfers add
bounded precision: Jz/Jnz/JmpOr/JmpAnd preserve ownership on the next sequential
instruction, while unproved destination joins still discard it. A known GetVar
value may feed SetVar(Cache), with only cache-frame operations intervening.
Calls continue to invalidate ownership. The final receiver screen establishes
29,071 equal full references and 2,732 equal method receivers, retaining 2,891
unknown accesses and the same eleven store-order candidates. Artifact:
`D:/opendream-diagnostic/cache-owner-value-audit.ndjson`. Two standalone auditor
tests check numeric value changes and the fallthrough/cache-transfer boundary,
including invalidation after a call and at a branch destination.

A forward conditional join may retain Cache and saved cache frames only when
every recorded incoming branch state and the sequential fallthrough agree
exactly. Missing predecessors, backward edges, unsupported branch kinds, and
different owners remain unknown; value-stack contents are always discarded
from the analysis at a join. This added no further resolved accesses in the
verified corpus (`cache-owner-forward-join-audit.ndjson`). The standalone
boundary test also checks the identical-owner join and a conflicting call edge.

The portable `fixtures/lowering/cache_call_context` native pair establishes
Src and World cache persistence across method/global calls, including a callee
assigning its own src to null. A child-receiver mutation reconstructs the chain
explicitly after the call. The auditor therefore preserves only Src/World frame
roots through calls; derived fields, arguments, locals, globals, and Usr remain
unproved at that boundary. An unknown local/index store cannot replace the
Src/World frame binding, while an explicit Src write still invalidates it.
The three auditor tests include these positive and negative boundaries.

The latest complete game pair (`deepquarry-complete.dmb` and matched native
reference) yields 29,445 equal full references and 2,874 equal method receivers,
retaining 2,375 unresolved accesses and the same eleven store-order candidates.
Of 24,600 cache-only/mixed-same-count pairs, 14,817 have unsupported layouts.
Artifact: `D:/opendream-diagnostic/cache-owner-complete-audit.ndjson`.

Discarded Call/CallStatement sequence normalization was removed: the paired
native fixture emits CallStatement followed by Pop, so opcode naming alone
does not establish different result-stack effects. Its earlier proposed
normalization admitted no extra corpus procedure. Only exact numeric push
normalization remains enabled for differing opcode layouts in this auditor.

Forward unconditional edges are now included in the cache/frame meet, with
sequential reachability ended by Jmp/Ret/End. This permits a receiver to survive
a forward diamond only when every explicit predecessor and any reachable
fallthrough agree. Unsupported or backward predecessors still invalidate the
join. Positive and conflicting-owner diamond tests pass. The latest bounded
screen (`cache-owner-forward-diamond-audit.ndjson`) establishes 29,860 equal
full references and 2,891 equal method receivers, retaining 1,943 unresolved
accesses and the same eleven store-order candidates. Field writes invalidate
all derived owners because differently rooted receivers may alias; that
additional negative test does not change these corpus counts.

The native context fixture additionally covers New/NewArgList, single-write
local receivers, non-exposed argument receivers, and stack ListSet. Argument
bindings stay unknown if their Args list or Caller/Callee context is exposed,
or the argument is assigned. Uniquely named single-write locals are eligible
only in procedures without Spawn. Unknown variable-bearing operations are
treated as potential binding writes, and ForRange/ForRangeStep/IterPairValue
explicitly invalidate affected bindings. ListSet can mutate aliased args/vars,
so it invalidates derived and unproved receivers while retaining independently
proved frame bindings. The Args-exposure, Spawn, conflicting join, and aliased
field-write negative cases remain covered by four passing auditor tests.

The latest complete corpus screen (`cache-owner-list-write-audit.ndjson`) has
30,685 equal full references and 3,089 equal method receivers, retaining 920
unresolved accesses and the same eleven store-order candidates. The scope
remains 24,600 considered pairs with 14,817 unsupported layouts. No further
concrete lowering defect was found by these extensions. A bare native Arg field
after a call receiving Args remains unproved; its live cache/argument-slot
behavior is not inferred from compiler output alone.

Duplicate local names can now be distinguished only when the complete
duplicate-name group has a unique bijection of identical, nonempty binding-write
instruction positions in the aligned native/translated pair. Unwritten or
unmatched groups remain unknown. The mapping is fixed from definitions before
reads are inspected; a negative slot-misread test remains a mismatch. This
establishes binding identity, not equivalence of all values assigned to it.
The values and other operand differences still require their own comparison.

SetVar(CacheKey) targets the dedicated key register; this fixed write target is
distinct from CacheIndex, whose computed list-element address still needs
container/key provenance. These positive and negative boundaries bring the
auditor suite to six tests. Final artifact:
`D:/opendream-diagnostic/cache-owner-definition-register-audit.ndjson`:
30,951 equal full references, 3,109 equal method receivers, 634 unresolved
accesses, and the same eleven store-order candidates. The considered/skipped
procedure counts remain 24,600/14,817. These identities do not prove runtime
equivalence of skipped instruction layouts or unresolved container/key values.

A further paired control-flow fixture exposed a cache assumption crossing an
if/else join: one edge left an argument receiver in Cache while the other read
World.time. World ownership is now invalidated at source joins and backward
loop headers discovered from the lowerer's real branch fixups. Procedures are
lowered again only when their first pass reused World and contained branch
targets. If/else, short-circuit, and backward-loop fixtures retain explicit
World selectors on the accesses requiring ownership restoration.

Shared ternary discard joins retain the value on every incoming expression
edge. Mutation statement optimizations cannot consume that common Pop, and
logical assignments use value-retaining JmpOr/JmpAnd in this context. Their
private statement Test/Jnz/Jz edges consume the tested value and may still
omit a redundant discard. Paired cases cover both logical operators, reversed
ternary arms, and indexed references without weakening native code comparisons.

Eleven candidate accesses remain in that snapshot. Four are reordered constant
stores in the guest ID card and multitype refill initializers, independently
verified by identical field/value signatures. The other seven are in
`/mob/living` (native procedure 59571, translated 54505): manual inspection shows
the same constructor prefix followed by the same seven independent empty-list
stores in a different order. This is a bounded inspection of those procedures;
the comparator deliberately keeps the effectful initializer opaque.

### Bounded loop-owner extension

The auditor can preserve an already established `Src` or `World` owner across a simple loop when every forward entry agrees and every instruction in the loop preserves that root. It rejects competing owners, context/cache binding writes, cache frames, null guards, exception/switch flow, deletion, and outside entries into the body. It never assumes an initial `Src` cache. Positive, conflicting-backedge, and unknown-preheader tests cover the inference.

The complete pair rerun is `D:/opendream-diagnostic/cache-owner-loop-invariant-audit.ndjson`: 24,600 pairs considered, 14,817 unsupported layouts, 30,951 equal references, 3,109 equal method receivers, 634 unresolved accesses, and the same 11 previously inspected store-reordering candidates. This extension resolves no additional access in that corpus; the remaining loop cases do not satisfy its proof conditions. Seven auditor tests pass and the example passes Clippy with warnings denied. No additional lowering defect was established.

### Final authored-null and call-ownership snapshot

The latest full emission completed on September 28 at 04:50 local time. The
read-only mixed audit against its freshly regenerated parity report is
`D:/opendream-diagnostic/final-cache-owner.ndjson`: 28,580 considered pairs,
17,092 unsupported layouts, 42,144 equal full references, 6,094 equal method
receivers, 862 unresolved accesses, and the same 11 inspected initializer
reordering candidates. These counts describe a different pair population than
the older snapshots above and must not be interpreted as a regression in proof
coverage.

The 862 explicit unresolved rows comprise 384 field references, 377 call
receivers, 37 bare Cache references, 17 CacheIndex references, and 47 other
references. Native resolution alone is unknown at 493 rows; both sides are
unknown at 369. None is automatically classified equivalent. No additional
known-owner mismatch was found.

The largest repeated unknown procedure is paicard `setEmotion` (native 27964,
translated 1189), with 32 accesses inside 16 switch arms. Manual inspection
shows an established Src owner before the switch, followed in each arm by the
same icon read, image construction, and screen-layer assignment; the translated
code explicitly selects Src. The generic auditor invalidates ownership at
switch entries and therefore retains these rows as unknown. This inspection
is bounded to these arm accesses and does not expand generic switch or image
constructor cache proofs.

Later native interpreter tracing established that discarded Call and
CallStatement have different managed-result lifetimes. The earlier discussion
above records the historical reason a proposed normalization was rejected;
it is not a current claim that the opcodes have equal ownership effects.
Lowering now preserves native direct versus computed receiver call modes,
and keeps each CallStatement's skipped Pop word immediately adjacent even with
debug events. The fresh parity report has no call-statement candidate category.
Authored equality-to-null loads also preserve the native Null reader's Eval
release through explicit compiler provenance; see `NULL_EQUALITY_AUDIT.md`.

## Frozen mutable root bindings

A new native paired witness establishes a real defect outside the auditor's
known-owner proofs: `OWNER.replace_owner(other) + OWNER.read()` uses the saved
old object for the second call even when the first call replaces the global
OWNER binding. The native SetCache reader copies the receiver value into the
frame's cache (10131086/10131089); it does not retain a live binding locator.
Reselecting OWNER changes the receiver and therefore changes semantics.

The lowerer now retains proven direct-root selection through paired method
calls, field operations and list access. It resets knowledge at branch targets,
explicit writes to the selected binding, computed cache writes, global or
self calls, and unknown effects. Native inherited calls and New preserve the
copied owner in the paired fixtures. Opaque args/global.vars indexed writes
preserve the frozen receiver, unlike direct binding assignment. Derived owner
chains are not inferred equal.

The portable `fixtures/translation/cache_binding_freeze/` fixture covers 38
native bodies; the translation regression enumerates 35 authored callers and
boundary methods, with three auxiliary method bodies also checked by standalone
preflight. Complete bodies match native in both debug modes when source markers
are excluded. The preflight also exposed assignment-result receiver fusion:
SetVarExpr followed by a method receiver is now emitted as native SetVar plus
its deferred direct reference. The three Arg/local assignment witnesses then
match native. No blanket reference or call normalization was introduced.

Additional conditional and switch witnesses prove frozen receiver reuse within case arms and conditional fallthrough. Encoded branch operand positions are obtained from the typed decoder and relocated with selector width changes; table keys and probabilities are not treated as addresses. Conditional field writes retain native explicit selectors until a fresh direct receiver selection or proven retained method call establishes the arm receiver. Two additional branch-write witnesses ensure a callee that replaces OWNER is followed by a write to the native frozen object. Nested selector chains and Src/World field shapes remain outside this direct-root elimination proof.

This is static compiler/bytecode evidence. DreamDaemon was not run. The remaining
862 unknown accesses in the previous full-game audit remain unknown until a
fresh emission and bounded ownership analysis establish their identities.
## Authored deletion and bounded Src receiver reuse

`NativeDeleteSrcOffsets` and `NativeDeleteClearOffsets` distinguish direct
`del(src)` termination from synthetic mutable-lvalue clearing after optimization.
The shared resolver reads these optional unsigned offsets for ordinary procedures
and global initializers. Native direct `del(src)` emits Del followed immediately
by End. Mutable deletion retains the original value while clearing its storage
before Del, including repeated effectful receiver evaluation and conditional
receiver joins. Generic assignments do not acquire deletion semantics.

The frozen receiver pass preserves a direct owner across Del only after a marked
SetVar whose cache owner is proven. Src field elimination is restricted to a
verified getter, null, marked-clear window and later direct Src reads; unrelated
Src selections can establish owner knowledge without being removed. Unknown
operations, derived owners and branch target entries still invalidate knowledge.
The native mixed fixtures prove reuse across unrelated fields and a conditional
clear followed by a self method call. World and nested initializer selectors are
outside this extension.

The portable `fixtures/translation/delete_lvalue/` fixture contains 23 authored
delete procedures. Their complete bodies match native in both debug modes.
Five existing cache regressions and the frozen mutable-root fixture pass unchanged
against the same standalone library. These checks compile bytecode only; no
DreamDaemon execution was used.

## Derived receiver values and computed field timing

The next paired witness found a second frozen-value defect:
`OWNER.child.replace_child(other); return OWNER.child.read()` calls the old
child twice in native output even when the first method replaces OWNER.child.
The lowerer had read the child again. The scoped pass now tracks the entire
direct-root, field-only receiver chain and removes its whole repeated selection,
never just its outer root. Explicit root/child assignments, other receiver
selections, branch entries and unsupported effects invalidate that knowledge.
Nested Src initializer selectors and computed owners are not inferred equal.
Increment/decrement invalidates the derived reuse proof: the paired
`box.child.value = box.child.value++` body explicitly reselects the receiver for
the following store. Direct nested safe indexes use their existing frame
unwind path; the extra parent-frame path applies only when that path has not
already recorded the same guard.

Computed parents require a different ordering. Native
`(new /datum/holder()).child.read(rebind_child(other))` saves the parent before
arguments and reads child after arguments. Reading child early can select null
or the old child. The lowerer defers a terminal field-only method reference
while preserving the parent cache frame. Safe child and safe parent guards have
separate paired coverage. Nested safe indexes retain both required cache frames;
the proof follows native cache operations rather than assuming a source-level
receiver after an argument changes the cache.

`fixtures/translation/cache_derived_freeze/` contains 32 explicitly enumerated
native bodies. Complete bodies match in both debug modes, excluding only debug
markers. Cases cover field/argument roots, two child levels, root and child
replacement, explicit binding writes, reads/writes/compound/index operations,
branches and joins, repeated computed owners, mutating arguments, constructors,
safe parent/child guards and nested safe indexes. The debug-mode checks also
exposed a setter fusion that incorrectly depended on marker adjacency; the
fold now preserves markers while removing only the paired owner getter.

The same standalone library passes the five earlier cache regressions, direct
frozen-root fixture, 23 deletion procedures and eight const-null manifests.
This is compiler and complete-bytecode evidence; no DreamDaemon was run.

The preceding full-game audit considered 27,360 pairs: 39,386 known equal
references, 4,847 equal method receivers, 802 unresolved accesses and 11
candidate accesses. The 11 candidates are bounded, manually inspected constant
initializer reorderings (seven mob empty-list stores and two stores each in
guest-id and multitype-refill initializers), not a general reorder proof.
16,686 layouts remained unsupported by that auditor. Those counts precede the
derived receiver fixes above and must not be presented as post-fix coverage.

## Switch entry receiver preservation

The next emitted game audit reduced unresolved accesses from 802 to 734. It
considered 26,776 pairs, with 39,178 known equal references, 4,738 equal method
receivers, 16,148 unsupported layouts and the same 11 bounded initializer
reorder candidates. These counts describe the pre-switch-fix snapshot
`deepquarry-latest-core.dmb` against the fresh native reference.

A paired counterexample then established that clearing frontend owner knowledge
at every branch entry was unsafe. After an opaque method replaces OWNER.child,
native switch arms retain the old child receiver; reselecting OWNER.child in a
case chooses the replacement. Direct mutable global roots have the same issue.
Switch and range-switch dispatch now save the current proven owner, after
discriminant evaluation. Each case/default entry restores that snapshot only
when the dispatch is its unique incoming branch source. Ordinary branches,
shared joins and conflicting entry edges retain conservative invalidation.
Selections made in one arm do not leak into another arm's frontend state.

The portable `cache_switch_freeze` fixture covers 12 explicit caller contexts
in both debug modes. Tests compare full opcode and typed-operand paths keyed by
numeric, string, null, range and default cases. They cover field reads, mutable
roots and children, arm receiver changes, shared joins, goto paths, ordinary if,
foreign-field discriminants and a global helper that mutates the child before
dispatch. Native and OD default layout order differs, so paths are compared by
their keys. An authored goto outside try uses native TryJmp versus emitted Jmp;
this receiver test follows those edges and explicitly requires no try frame,
without declaring general cleanup equivalence. Ordinary if and the mutating
helper also retain strict complete-body assertions.

After the scoped fix, all 444 core tests, derived receiver 32-body checks and
23 deletion bodies pass against the standalone library. The full-game counts
above have not yet been refreshed after this fix.

## Initial and IsSaved on frozen derived receivers

An additional native witness showed that unguarded
`OWNER.child.replace_child(other); initial(OWNER.child.value)` uses the old
cached child. The computed-owner fallback had reloaded the replaced field.
Native paired types with different initial values and saved/tmp flags make the
receiver choice observable. The handler now folds an adjacent pure field
reference into the complete nested Initial/IsSaved selector. The whole-chain
pass can remove that selector only when its exact frozen receiver is known.
The bare-field readers preserve that owner for a subsequent method read.

Safe child forms deliberately select the current field again in native output;
they remain on their separate explicit-owner path. Legal safe IsSaved now uses
the same paired path as safe Initial. Writes to the child, a different receiver
selection, a global helper call and ordinary branch entries require the native
fresh selector. The portable `cache_initial_freeze` fixture checks 20 complete
bodies in both debug modes, two keyed switch-arm Initial reads and metadata for
the differing-default and tmp-variable witness types. Computed factories and
two child levels have paired coverage. Seven additional scratch probes of
identity/null/ref/type/constructor/type-initial/type-saved reads match native;
they did not establish another defect. Full-game receiver counts have not yet
been refreshed after this change.

## Bounded Usr callee-assignment proof

A native pair `usr.change_usr(other); return usr.read()` (and a field-read
variant) uses the frozen cache. Receiver identity agrees because `usr=other` in the ordinary called method changes the callee's
context, not the caller's Usr binding. This does not establish that Usr is
immutable or permit general unknown-receiver normalization.

The FFCD reader jump-table entry at 10131918 resolves to 10131244, reading the
value pair at +8/+c of the current frame's context. The FFCD setter resolves
through selector table 10130e54/index0 to 10130b62, writing that same current
context pair. Dynamic method dispatch at 101313cc/101313d1 passes the caller
Usr value pair by value through 10133020 to 10157010. The executor copies it
into a new local context at 101570c4/101570ca and passes that context to
1013e720. Frame setup stores the prior frame at +4 (10164997), the new context
at frame +0 (101649a0), and return restores the prior frame pointer at
10153c3b/10153c3e. The native fixture and translated source both compile with
zero warnings; artifacts are `cache-usr-frozen/probe.*` in the diagnostic folder.

Current-frame assignment, other dispatch paths, suspension and external
context changes are outside this proof. The lowerer and conservative audit
continue to exclude assumptions of general Usr stability. No production change
or broad comparison equivalence was introduced for this pair.

## Pick candidate frontend cache context

Native PickSwitch (79) and PickProb (B1) dispatch entries retain the frontend
receiver selection context used to compile their candidate bodies. The frozen
cache pass now restores that context only at a uniquely entered dispatch arm;
ordinary joins retain the conservative reset.

Dynamic probabilities require a separate distinction. Native compiles candidate
selectors using the context before probability expressions, although the VM
executes the probabilities before entering a candidate. A probability global
helper does not force a fresh candidate selector. More strikingly, a probability
`other.value` or `other.read()` selects `other` into the actual VM cache, while a
candidate written `OWNER.child.read()` can still have a bare method selector.
That bare native candidate consequently calls the weight-selected object.
Explicitly assigning OWNER inside a probability similarly leaves the native
candidate selector compiled from its earlier context. Matching these encodings
must not be reported as proof that the original runtime receiver is unchanged.

The lowerer records private, relocation-tracked probability region labels. The
cache pass analyzes the probability instructions normally, then restores the
pre-probability frontend context at the dispatch. This is scoped to native
weighted-Pick lowering; ordinary global helper statements continue to invalidate
frontend reuse. Field/Initial candidates, different candidate owners, two
probabilities, explicit binding writes, nested helper arguments and conditional
probability branches have paired native coverage. All eighteen callers currently pass complete native body comparison in both debug modes. The portable `cache_pick_freeze` fixture includes nested weighted candidates and conditional probability branches; their private context labels survive expression relocation. No general cache-owner equivalence was added to the comparer/auditor.


## Classified next-core audit and bounded body proofs

The classified `deepquarry-next-core.dmb` snapshot (503-test production gate)
was compared with the fresh native reference. With typed table-dispatch snapshots,
known immediate-getter safe-guard fallthrough and adjacent constant-string index
setup, the read-only auditor considers 26,838 pairs and skips 16,206 unsupported
layouts. It proves 39,569 reference accesses and 4,880 method receivers equal;
267 accesses remain unknown. Eleven candidate differences remain the previously
reviewed independent initializer-store reorder cases. These counts predate the
association and branch-entry fixes below; they are not a claim that the remaining
unknown accesses are equivalent.

For 9,419 of the 9,631 cache-only procedure pairs, every reference and receiver
is known equal, and each method's actual display name and proc/verb mode also
match. This is a bounded complete-body proof restricted to that classification,
whose remaining instruction/operand semantics already match. Invalid names and
unresolved receivers disqualify a body. The separate constant-initializer
signature proves 11,301 pairs; 5,692 overlap the cache-only proof, giving a union
of 15,028 procedure pairs. Artifacts are `next-core-cache-owner-bodies.*` in the
diagnostic folder. Eleven focused auditor tests include changed list/key,
interrupted getter, null-path join, conflicting table-arm receiver and changed
method-name/mode negative controls. The comparer does not normalize these results.

## Field-chain association and statement mutation boundaries

`/client/mark_datum` exposed a receiver capture gap: a left-associated
`SetCache(SetCache(Src, holder), marked_datum)` was not recognized as the same
ordered owner reads/cache writes as native's right-associated field chain.
Following a condition and callback, translation could re-read a replaced holder
where native uses the captured holder. The helper now extracts only direct-root,
field-only chains in either association and emits native's right-associated form.
Computed/indexed/Initial-owner chains remain outside this transformation.

Native statement field assignment and augmented field mutation invalidate the
frontend context for a following derived receiver read. Ordinary SetVarExpr
assignment expressions retain it; storing an Initial result into a local does
not invalidate the receiver. Thirteen complete paired bodies in both debug modes
cover Src conditions, callback rebinding, explicit child writes, two child levels,
different receiver selection, joins and statement/expression mutation boundaries.
The portable fixture is `cache_association_freeze`.

## External expression entries and skipped safe RHS frames

Indexed augmented-assignment lowering rotates the RHS before list/key evaluation.
An incoming branch to the old expression head must enter the whole new expression,
not the moved list getter. A private entry label now preserves that branch entry
without changing internal operand joins. The observed contracts/unsubscribe shape
previously skipped its RHS getter and reached the indexed store with a missing
value.

Logical and conditional expression branches can skip a guarded RHS entirely.
Their join must skip only PopCache cleanup frames the edge did not acquire;
inner guards can still require enclosing receiver cleanup. Eight complete paired
bodies in both debug modes cover indexed add/subtract statement/expression forms,
And/Or, a method-argument parent frame, nested logic and ternary bypass. Authored
goto remains separate from conditional-expression cleanup. The portable fixture
is `cache_branch_entries`. No DreamDaemon execution was used.

## Usr selector managed-result lifetime correction

Receiver identity does not prove managed-result lifetime parity. The native
Usr reader at 10131244..10131251 assigns through 102247b0 into frame Eval(+2c).
That assignment saves the old value at 102247bd/102247c1, retains the new value
at 102247ca, and releases the old value at 102247d1. SetCache then copies the
owner into Cache(+1c/+20), releases the old cache at 1013108c, and clears Eval at
1013109a/101310a0. An extra Usr selector therefore releases a retained managed
CallStatement result before entering the next method.

The portable `cache_usr_ownership` fixture proves six complete native bodies
in both debug modes: consecutive managed calls, subsequent field read,
current-frame Usr assignment, callee-only Usr assignment, another selected
owner, and an intervening global helper. Direct Usr selections now participate
in bounded frozen-root retention; current-frame Usr writes invalidate them.
Derived Usr paths remain excluded. The global-helper exception applies only to
an already captured direct Usr receiver. Branch joins remain conservative.
Reference/dispatch identity audit counts alone are not full lifetime proofs.
## Captured Src and World method-result ownership

The Usr lifetime review exposed the same extra-selector hazard for a captured
Src or World method followed by a direct field operation. The portable
`cache_src_ownership` fixture has thirteen complete native bodies in both debug
modes plus a getter-only negative assertion; `cache_world_ownership` has seven.
Native retains the selected method owner for field reads, writes, compound
operations and a following global helper. Selecting another owner, a derived
receiver, a safe other owner, or reaching a branch target invalidates this
bounded frontend context. Simple branch fallthrough retains it.

The lowerer tracks this eligibility separately from general cache owner identity.
Only a proven direct Src/World method selection enables these field rewrites.
Unrelated field-only procedures and class initializers are not enabled. Native
and patched OpenDream compile both fixtures with zero warnings. The direct
full-body comparisons also preserve branch targets and operand ordering; no
broad reference normalization is used to pass these tests.

## Bounded captured method-return identity audit

The read-only auditor recognizes an immediately captured ordinary Call29 result
only when its receiver is known and its sole argument is a literal string.
Symbol identity includes the aligned call-site index, receiver, actual selector
name, proc/verb mode, and string bytes. It is lost at an intervening operation or
value-stack join. Changed method, receiver, argument, nonliteral input, skipped
capture and a branch-target capture have negative tests; twelve auditor tests
pass. This resolves the paired GetEquippedItem return→Cache→screen_loc pattern
without assuming two separate calls return the same object.

On the historical final snapshot before the latest Src/World lifetime fixes,
this resolves 37 additional accesses: 46,240 resolved equal references, 5,429
method receivers, 330 unresolved accesses, and fourteen candidates. The candidate
set is unchanged: eleven independent initializer stores and three differently
ordered switch-arm indexed additions in service_invoice_summary. These are
receiver/dispatch identity results, not a managed-lifetime equivalence claim.
Artifacts: `final-cache-result-owner.ndjson` and `.txt` in the diagnostic folder.
## Statement store/reload ownership (new paired counterexample)

The portable `statement_store_reload` fixture and integration test distinguish native statement SetVar34/GetVar33 from expression SetVarExpr35. Both source forms previously became the same optimized OpenDream Assign instruction. The new optional NativeStoreReloadOffsets provenance marks only the optimizer-created statement fusion; the lowerer emits the native pair for marked Arg/Local references and preserves authored expression35.

This is an ownership difference, even though the returned value and final local binding match. SetVarExpr retains a copied RHS while the original remains stack-owned during release of the old local. A synchronous old-local Del reading refcount(globalRHS) observes the extra reference. The fixture README records the native setter, retain/release, RefCount and Del dispatch addresses. Static inspection and paired compilation establish this without DreamDaemon execution.

Historical conservative-pattern local_store_reload counts therefore describe structural value/binding correspondence only, not full runtime equivalence. They must not be treated as a managed-lifetime proof.

The follow-up `setter_cache_boundaries` matrix compares 14 complete native bodies in both debug modes. Direct Src/World field setters establish owner context; captured context survives a flag-only conditional fallthrough, while joins and explicit Src binding replacement require a fresh first getter. Immediately consecutive direct getters reuse that fresh owner. These exact pairs cover other/derived owner changes and a managed old field's Del callback. Getter-only context is not propagated across intervening operations. The earlier Src getter-first assertion inspected only translated output; it was replaced by complete native parity after the native pair proved first fresh getter followed by bare Field.
