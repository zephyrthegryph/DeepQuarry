# DM health analyzer

`dm-health` is a Rust command-line checker for the DM files included by
`deepquarry.dme`. A small .NET bridge uses OpenDream's preprocessor and parser
to export its AST as JSON Lines; Rust performs the health and type analyses.
The source scanner is retained only for comments that declare access contracts
and for physical file sizes. The `ci-suite` command runs the established
repository lints, DreamChecker, OpenDream compilation, map and UI checks,
Verdigris checks, and the DM health analysis from one CI entry point.

The [static type system design](docs/type-system.md) describes the target
inference, nullability, lifecycle, and dynamic-boundary rules. Enable the new
strict pass for all source with `--strict-types`, or for a README-defined
module with `--strict-module code/modules/name` (repeatable). A strict run
requires a schema 4 OpenDream AST export with zero frontend errors, matching
included-file hashes, and the same OpenDream compiler DLL; an older, errored,
or stale export produces an error.
The strict pass reports unresolved types and dynamic calls as errors and adds
type coverage counts to saved reports. Strict mode is being adopted by module;
the existing game source does not yet pass it wholesale.
Reports also group unresolved expressions by their immediate cause, such as an
untyped local, unresolved receiver, or untyped collection value. These groups
are triage hints rather than a proof of the ultimate source of an unknown.
The saved report also contains `root_causes`: the Type roots web view follows
unknown expressions through nested AST values to a field, parameter, or return
declaration when it can identify one. Expressions with no unique declaration
root remain grouped by their first unresolved expression and are labeled as
fallbacks. The view reports both source-linked and fallback counts.
Strict declaration coverage includes fields, parameters, return types, and
local variables. An imprecise local, including a bare `list` whose element
type cannot be established, produces `unknown-local-type`.
The checker infers a parameter's storage type when the known statically resolved
call sites agree on one precise type. Calls with unknown arguments remain
separate errors against that inferred type. It repeats call, return, and field-write
analysis until the evidence stabilizes (up to eight outer rounds), without
retaining the whole AST in memory. An inferred parameter remains an error
at the open DM call boundary: dynamic or external callers may pass values
the known calls did not show. Nullability is checked separately at call sites
and on every path through the procedure.
Numeric-only operations also supply a parameter type constraint. Direct,
member, resolved dynamic, parent, and constructor calls contribute argument
evidence. The bridge preserves structured field initializers in modified
`new /type{field = value}` expressions so the checker can validate those
writes. Resource literals are classified as icon, sound, or general file
values from their extension; `get_step()` is a nullable turf result.
An untyped local declared without an initializer, or initialized to null,
can gain a storage type from every direct assignment in its procedure. This
requires precise, compatible, non-null values and rejects ambiguous source
order, shadowing, compound writes, and static locals. Source-ordered local
facts can use earlier assignments and both sides of an `if`; unsupported
control flow discards those facts. Its value still starts unassigned or null
until a particular control-flow path proves otherwise.
Constant-key list reads can carry facts from guards such as
`istext(payload["name"])`; overwriting the list clears those facts.
Collection joins preserve a common element supertype when both sides have
precise element types. Return inference accepts a base procedure only when
all descendant overrides have compatible checked results. A return with one
concrete type plus null retains that nullable type for callers, while the
unannotated return declaration remains a strict error. Builtins such as `round()` and spatial
queries keep a known result type while separately reporting unproved inputs.
For `var/list` fields, direct `+=` writes can establish a single element type
when their values agree, including fields initially assigned `list()`.
Indexed writes with proved numeric or text keys can establish a list element
or associative key/value type. A simple `/datum/New()` that assigns a required
field on every path can prove initial initialization without an annotation;
later null writes still fail the field's non-null storage check.
Return inference also follows `..()` through repeated definitions of one DM
procedure. Precise non-null parameter defaults contribute storage-type
evidence, while callers outside the analyzed graph remain a strict error.
The analyzer recognizes the generated `ADMIN_VERB` wrapper shape to connect
its arguments to the corresponding `__avd_do_verb` implementation. Built-in
`world` fields and typed `input()` expressions have explicit result models.
For DM syntax that cannot express a collection element type, put
`// dm-health: local cache list<text>` immediately above the procedure that
declares `cache`. The checker validates the local name, its initializer, and
later assignments against that storage type.
An exact `null` literal counts as a known expression value, while a declaration
whose only evidence is null still lacks a usable storage type.
The strict checker types numeric `round()` calls and homogeneous `min()`/`max()`
calls from proved arguments. A single typed list argument has an optional
result because the list may be empty. Mixed or unproved arguments remain
unresolved.
An override inherits a precise parent parameter type by position when its own
parameter is untyped. A narrower declared override parameter is an error:
calls through the parent type must remain valid for the override.
`// dm-health: no-sleep` on a proc, or the existing `SHOULD_NOT_SLEEP(TRUE)`
pragma inside one, makes a direct `sleep()` call an error at its call site.
This check does not yet prove that called procs cannot sleep transitively.
The bridge also exports `DMASTModifiedType.fields.VarOverridesAst` as name and
expression pairs. OpenDream's original `VarOverrides` display strings remain
for schema-4 compatibility; use the structured form to analyze assignments
inside expressions such as `new /datum/example{count = 7}`.
The bridge preserves OpenDream switch cases and their bodies. Strict flow joins
all case outcomes and the unmatched path when no default exists. Unlabeled
`break` and `continue` in loops stop the current path at the jump. Labeled
jumps and unsupported loop headers remain explicit control-flow findings.
Loop type facts are joined to a stable state before body diagnostics run. If
they do not converge within 12 iterations, the checker reports
`unverified-loop-fixed-point` and discards downstream value proofs.
Return inference also follows switch arms; a missing default keeps the
fallthrough return path, and a typed local without an initializer still starts
null rather than inheriting a non-null fact from its declaration.
Procedures with no value return or implicit result assignment infer `void`
even when calls in their bodies invalidate flow facts.
The built-in spatial queries `view`, `oview`, `range`, `orange`, `viewers`,
`oviewers`, `hearers`, and `ohearers` have checked distance/center arguments
and list results. Their query operations preserve earlier type guards; calls
inside their arguments still invalidate guards when they can have effects.
The bridge refuses to write an AST when OpenDream reports a frontend error.
The project's `FILE_DIR` paths use BYOND-compatible quoted values so both
Dream Maker and OpenDream can read the same manifest.
AST exports are tied to their included files and compiler DLL. If either
changes or moves, rerun the bridge before analysis; the Rust command rejects
stale exports before producing a report.
The Rust analyzer takes its source inventory from the verified OpenDream
manifest. Conditional `#include` text is not treated as a file unless the
frontend actually parsed it. OpenDream's bundled standard-library DM files are
hashed as compiler inputs but excluded from project findings and metrics.
`--reuse-if-current` checks every included file, the bridge and compiler DLLs,
and the output checksum before reusing an AST. A changed input triggers a full
OpenDream parse. `--cache-dir` also reuses a completed Rust report when the
verified AST, analyzer binary, baseline, strict selection, and relevant README
contents match. In strict mode, `--cache-dir` also stores each checked procedure
separately. A changed procedure body rechecks that procedure while unchanged
bodies can reuse findings and coverage if declarations, contracts, inferred
field and proc types, call evidence, module selection, compiler identity, and
analyzer binary are unchanged. Changes to those shared semantic facts invalidate
all procedure shards. OpenDream still reparses changed sources, and the legacy
AST and metrics passes still run in full when the whole-report cache misses.
Procedure shards use one checksummed `.shard` file each; older two-file shards
remain readable. Set `DM_HEALTH_PROFILE=1` when investigating a cold scan to
print the time spent on inference passes, finalization, procedure checks, and
procedure-cache operations. The profile output goes to stderr.

Run from the repository root after installing a matching OpenDream compiler
release and the .NET 10 SDK. On Windows, build the bridge against the Windows
OpenDream release, export the AST, then run the Rust analyzer:

```powershell
dotnet build tools/dm-health/opendream-bridge/OpenDreamBridge.csproj -c Release -p:OpenDreamDir="$PWD/DMCompiler_win-x64"
dotnet tools/dm-health/opendream-bridge/bin/Release/net10.0/OpenDreamBridge.dll deepquarry.dme tools/dm-health/target/deepquarry.ast.jsonl "$PWD/DMCompiler_win-x64" --reuse-if-current
cargo run --release --manifest-path tools/dm-health/Cargo.toml -- --root . --ast tools/dm-health/target/deepquarry.ast.jsonl --baseline tools/dm-health/baseline.json --fail-on-new --summary --report tools/dm-health/target/latest-report.json --history-dir tools/dm-health/target/history --cache-dir tools/dm-health/target/analysis-cache
```

When DM files are changing during a scan, run the Windows snapshot wrapper.
It copies the source trees to a dated directory under `target/snapshots`, runs
OpenDream and the analyzer against that fixed copy, and prints the saved JSON
report path. It requires the built Windows compiler, bridge, .NET runtime, and
release analyzer in `tools/dm-health/target`.

```powershell
pwsh -NoProfile -File tools/dm-health/scripts/scan-snapshot.ps1 -StrictModule code/modules/medical
```

Use `-StrictTypes` for a full repository type coverage snapshot.

On the CI runner, `tools/dm-health/target/release/dm-health ci-suite` runs the
whole lint suite. It continues after individual checks fail and reports the
failed check names at the end. The suite includes generated object-model
bindings, Rust consolidation, analyzer formatting/Clippy/tests, and the
host-buildable Verdigris checks. Per-check status and duration are saved in
`tools/dm-health/target/ci-checks.json` and added to the report.

Use `--json` for machine-readable findings. `--write-baseline PATH` records
current finding fingerprints. `--baseline PATH --fail-on-new` fails only when
new findings appear. The checked-in baseline records existing findings by
rule, path, and message, with counts, so unrelated line shifts do not fail
CI. CI verifies the OpenDream compiler DLL hash used for the baseline.

## Reports and viewer

On Windows, launch the local viewer with:

```powershell
cargo run --release --manifest-path tools/dm-health/Cargo.toml -- serve --history-dir tools/dm-health/target/history
```

Open `http://127.0.0.1:8765/`; the newest saved snapshots load automatically.
You can also open `tools/dm-health/viewer/index.html` directly and import JSON
files. The viewer has findings and code-line timelines, rule and severity
filters, procedure metrics, a unified Explorer with modules, folders, files,
and source with inline diagnostics, resolved cross-module coupling, global field
usage, CI check results, and a saved report selector. The Explorer puts modules
first, then folders with subfolders, then folders containing files, then files.
Findings and procedures can be filtered and sorted by module and category. Click a finding,
procedure, or file to open its source. Source text is served only by the local loopback viewer and
is not embedded in saved reports. It keeps
imported reports in the browser's IndexedDB and lets you download any selected
snapshot. `--history-dir` writes dated snapshots on disk; importing several
snapshots shows trends. CI uploads its latest JSON report as a build artifact.

Each report contains every finding plus procedure, file, and module metrics:
physical, code, comment, and blank lines; procedure size,
statement count, branches, maximum nesting, parameters, locals, calls, global
reads and writes, type references, dynamic calls, and project totals. New reports
use schema version 2. The viewer can still load version 1 reports.
Saved reports also identify whether the Rust result was reused from a verified
cache entry; a reused snapshot keeps the same findings and metrics and receives
a fresh report timestamp. `analysis_phases_ms` records source-contract loading,
symbol collection, legacy diagnostics, strict typing, metrics, root-cause
grouping, and report finalization separately. Strict reports also count
procedure checks reused and recomputed from the incremental shard cache.

## Module boundaries

A `README.md` or `readme.md` in a source folder defines a module. Files belong
to the nearest marked ancestor; files with no marked ancestor are unassigned.
Folders without a README remain visible for size and finding drilldown, but
they are not module boundaries. The repository has marker READMEs for major
subsystems. Expand these with ownership, public API, dependencies, and lifecycle
details as the systems are reviewed.

The coupling view counts cross-boundary references with a unique resolved
target: explicit DM type paths and reads or writes of `GLOB` fields with one
declaration module. Ambiguous names and dynamic dispatch are excluded, so the
counts are a lower bound rather than a complete call graph.

The `raw-global-state` diagnostic identifies direct `var/global` declarations.
`GLOBAL_REAL` is reserved for the known bootstrap and singleton references;
new uses outside them produce `raw-global-declaration` warnings. These rules
make state outside `GLOB` visible before it spreads.

Nullability is a flow property. An uninitialized local begins null; a `new`
assignment makes it non-null. Branches merge the possible states, and guards
such as `if(!M) return` narrow the remaining path. Short-circuit `&&` and `||`
conditions narrow the branch where the right side runs. Direct local aliases
share a tracked identity until reassignment. Proc calls and reflection with
unknown targets remain unknown; called proc effects, mutable fields, and
changes across suspension points need review. Health
signals include large files and procs, branch/global/type coupling, broadly
written globals, high fan-out, deep nesting, many parameters or locals,
unreachable statements, self-assignment, division by literal zero, dynamic
call hotspots, and `sleep` or `spawn` in lifecycle procs.

Untyped locals acquire a flow type from a known initializer or assignment;
conflicting branch types merge to unknown. An untyped proc receives an inferred
non-null return type only when its body is one direct return of a literal,
list, or fixed `new /path`, and no subtype overrides that proc. Mutable fields
and parameters are not made non-null from their initializer, default, or
observed callers alone: other writes and dynamic callers can change them.
Typed `for(var/type/name in values)` loops use DM's runtime type filter to
narrow the loop variable. `as anything` disables that filter, so the checker
requires a proven list element type instead. Unknown loop sources and elements
remain visible as strict diagnostics.

## Source contracts

Put an exact annotation on the line immediately before an absolute member
declaration:

```dm
// dm-health: private
/datum/vault/var/key

// dm-health: public
/datum/vault/proc/Inspect()

// dm-health: protected
/datum/vault/proc/Reset()

// dm-health: nonnull
/datum/vault/var/owner

// dm-health: nonnull
/datum/vault/proc/GetOwner()

// dm-health: nullable
/datum/vault/var/optional_owner

// dm-health: initialized-by New
/datum/vault/var/number

// dm-health: nonnull(item)
/datum/vault/proc/Take(obj/item)

// dm-health: readonly
GLOBAL_VAR_INIT(configured_value, 42)

// dm-health: tracked(setter=set_charge)
/datum/cell/var/charge

// dm-health: type list</obj/item>?
/datum/vault/var/list/items

// dm-health: param item /obj/item
// dm-health: returns num
/datum/vault/proc/Take(item)

// dm-health: parent-always
/datum/vault/Initialize()
    return ..()

// dm-health: parent-first
/datum/vault/Refresh()
    return ..()
```

The short forms `// public`, `// private`, `// protected`, `// nonnull`, `// nullable`, and `// readonly`
are also accepted. Annotations only attach to the next declaration, with no
blank or unrelated comment line between them. Multiple annotations may be
stacked directly above the declaration.

`public` documents unrestricted access and can override an inherited access
annotation on a subtype member. `private` permits access only from procs on the declaring type. `protected`
also permits subtype procs. `nonnull` requires a field initializer, rejects a
known null assignment through a typed receiver, and rejects a known null
return from an annotated proc. `nonnull(parameter_name)` requires a non-null
argument at statically resolved positional call sites and rejects a null
default or assignment to the parameter. `nullable` documents an optional
field. These are CI contracts, not DM runtime visibility. `readonly` on a
`GLOBAL_*` declaration rejects direct rebinding of the corresponding `GLOB`
field. It is shallow: mutating a referenced list or datum is still allowed.
Globals are not all read-only because this codebase uses many of them as
mutable shared state.
Strict flow analysis begins each proc parameter as possibly null, even when
its declared storage type is non-null. A checked call site cannot establish
the invariant for omitted arguments or external callers; a guard inside the
proc can narrow the parameter before dereference.
`tracked(setter=...)` opts a field into checked writes. The named setter must
be a proc on the declaring type. Statically resolved direct writes to that
field from another proc, including subtype procs and writes through typed
parameters or locals, are errors. Constant `vars["field"]` writes are checked
the same way; computed `vars[key]` writes on a typed receiver are errors when
that type has tracked fields. The setter must call the framework change mark
after a value-changing assignment; the annotation does not generate the
setter or track writes by itself. Untyped receivers and aliases hidden by
dynamic calls still require a separate ban or explicit review.
The checker currently recognizes statically typed receivers, `src`, and direct
constant proc paths in `call(/path/to/proc/Name)(...)`; computed proc references
remain unresolved. It checks the arguments of a resolved `call()` against the
target signature. A ternary of literal method names also resolves when its
condition has no unknown effect and every possible method has the same checked
signature. Other computed names, reflection, ambiguous dynamic calls, named
arguments, and mutation through untracked references remain unresolved. An unannotated field remains
nullable by default in the legacy analyzer. The strict pass instead requires
`nullable` or a `?` type for null values. `parent-always` requires a
`..()` call on every normal path through the annotated override, while allowing
work before that call. `parent-first` requires the first
executable statement to call `..()` directly, through `return ..()` or `. =
..()`, or as the condition of the first `if`. This guarantees a parent call
before other work on every reachable path. The strict type pass excludes
`Destroy` and `Del` bodies and their writes from storage-type inference.
The existing `SHOULD_CALL_PARENT(TRUE)` pragma now supplies the inherited
`parent-always` requirement to overrides; `SHOULD_CALL_PARENT(FALSE)` exempts
that override and its descendants. Teardown procs are excluded from this new
path requirement.

`initialized-by New` is currently proved only for a leaf datum type whose
parameterless `New()` uses direct constant assignments to its own fields,
including a compatible assignment to the annotated field on every path.
The supported constants are numbers, text, and literal type paths.
Atom subtypes are excluded from this narrow proof. Their `New()` and
`Initialize()` lifecycle can defer initialization during map loading, so a
direct assignment in an atom override alone does not establish the requested
post-initialization guarantee.
Simple `if/else` branches with literal-only conditions and returns after
assignment are checked path by path. Literal declaration initializers on
other fields are allowed. Calls, effectful initializers, unsupported control
flow, inherited overrides, and other lifecycle phases produce
`unproven-initialization`; the annotation never suppresses the error by itself.
Strict analysis reports `conflicting-type-contract` when a declaration has
incompatible `nonnull`/`nullable` comments, `initialized-by` combined with
nullable storage, different `initialized-by` phases, or different explicit type contracts for the same field,
parameter, or result. The analyzer does not silently take the last comment.
Existing literal `RETURN_TYPE(/path)` pragmas are also read from DM source,
because preprocessing removes them from the OpenDream AST. Generated Verdigris
bindings carry return metadata from their Rust export declarations where the
generic `ByondValue` FFI signature cannot express a DM result type.
`invalid-contract` also reports a `dm-health` comment on the wrong kind of
declaration or one separated from its declaration. Type comments on `GLOBAL_*`
macros retain their type text and bind to `GLOB` even inside a type block.

Computed call argument keys cannot be assigned to a known parameter. Strict
analysis reports `unresolved-argument-key` and keeps call-site parameter
evidence unresolved instead of treating such a key as a positional argument.
Effects in an earlier binary operand or call argument invalidate later null and
type facts within the same expression; a later dereference or argument binding
must be proved again.
Unknown element or key types inside a list or association remain unresolved at
assignments and call sites. They are not reported as a proved concrete mismatch.
Reports split unresolved assignments into unknown source types, unknown
destination contracts, and flows where both sides are unknown.
Return flow can retain a bounded numeric-or-text result when the source really
returns both, as timer IDs do. This does not satisfy the single-type rule for
fields, locals, or parameters; mixed storage still receives a conflict.
An empty `list()` can take a declared list or association type at an assignment.
Without that context its element type stays unresolved. A fresh local list can
acquire a checked element or key/value shape through indexed writes while it
remains unaliased. Passing or aliasing it, or writing an unproved value, drops
that shape. The same rule applies to a fresh implicit result list.
The checker models `/alist` separately from ordinary associative `list()`
values. OpenDream's `IsAList` flag preserves numeric keys and the distinct
`alist()` runtime type; empty `alist()` needs an alist destination to establish
its key and value types.
Numeric unary operators now require a proved `num` operand. The `in` operator
has a numeric result even when its right side is null, matching DM's membership
semantics.

The strict pass models `typesof()` and `subtypesof()` as lists of type paths
when every argument is itself a proved type path. Dynamic or unproved arguments
remain unknown. This gives `for` loops a precise element type without assuming
the contents of arbitrary helper procs or mutable lists.
`ispath(value, /datum/subtype)` narrows `value` to a subtype path on the true
branch. Dynamic `new value()` then has that bounded datum type. A path to a proc,
verb, or non-datum root cannot be used as a proved datum constructor; a dynamic
second `ispath` argument remains unresolved.
`text2path(text)` produces an optional, otherwise unbounded type path. It still
needs a subtype check such as `ispath(value, /datum)` before dynamic datum
construction can receive a type.
Literal `vars["field"]` and `receiver.vars["field"]` use the declared field type
for reads and writes when the receiver resolves. Visibility, tracked-write,
nonnull-write, and readonly-global rules also inspect those literal keys.
Computed reflection keys remain unresolved.
One-argument `isnum()` and `istext()` checks narrow a local or field on the
true branch. Their false branches do not claim a complementary type, and calls
with unsupported argument shapes remain unresolved.
Non-null checks can also prove that a value of unknown nominal type is
non-null. The checker then suppresses only the null warning: member reads and
calls still report unresolved receivers until a type check proves the type.
Project procs named `isnull`, `islist`, `isnum`, `istext`, or `QDELETED` are
rejected in strict analysis because they can shadow the type-test operations
used by guard narrowing. OpenDream permits type-local proc names that match
standard global procs, so this is an enforced analysis contract.
Uninitialized `var/static` locals are treated as nullable retained storage on
later calls, so reading them is a nullability question rather than a local
read-before-assignment error. Return inference also applies proved branch
guards before joining branch results.
Successful `islist(value)` and `istype(value, /list)` guards prove only that the
value is a list; they do not prove its element type.
Unknown calls invalidate element and association schemas for mutable collection
references, including nullable collections and fields reachable through aliases.
A later null guard cannot restore their element type without a validated schema.
For variables declared with a DM subtype, a successful `istype(variable)` guard
restores that declared subtype. The checker applies the guard before inspecting
the right side of `&&` (or the false guard before the right side of `||`), so
guarded subtype-only member calls can be checked in short-circuit expressions.
Repeated proc definitions on the same DM type are tracked in OpenDream AST order.
For such a definition, `..()` uses the preceding version's signature; if the
AST passes disagree on definition order, the checker reports the version as
unresolved. `arglist()` packs generated by `ADMIN_VERB` remain unresolved until
their runtime argument shape can be validated.
`+` now derives `num` from numeric operands, `text` from two text operands,
and a collection element type only for compatible list concatenation or a
fresh empty list literal plus one proved value. Mixed or unproved operands stay
unknown; `+=` mutation still requires a checked collection boundary.
Compound addition checks numeric, text, and compatible list operands. An
untyped destination emits `unresolved-append-target`. List mutation invalidates
alias-sensitive collection facts; proved scalar mutation keeps unrelated facts.
