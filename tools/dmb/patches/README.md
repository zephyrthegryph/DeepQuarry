# Pinned OpenDream compiler patch

The build script applies only `opendream-combined-1362abc.patch`,
`opendream-multiple-include-1362abc.patch`, and
`opendream-savefile-version-1362abc.patch`. Earlier diagnostic patches are
kept in `archive/` for reproducing older investigations; they are not part of
the current compiler build. Some contain changes that evolved before the
combined patch, so do not apply them on top of the active three.

`archive/opendream-call-ext-opcode.patch` applies to OpenDream commit
`1362abc5accbc2037df9b45efa1de13fb1bb677f`. It preserves the
`call` versus `call_ext` distinction in compiled bytecode: `0x9e` means
ordinary `call`, and `0x9d` means `call_ext`. Both retain the original
argument encoding. Stock OpenDream encodes both as `0x23`; the Rust
translator rejects that ambiguous opcode instead of guessing.

The combined patch also emits `0xa0` for dynamic calls. Its operands are
`u8 is_ext`, `u8 target_count`, `u8 argument_mode`, and `u32 argument_stack_size`
in OpenDream's usual little-endian encoding. Targets precede arguments on the
stack, matching DreamMaker's evaluation order. Target count is one or two;
argument modes are 0 (none), 1 (positional), 2 (key/value pairs), and 3 (arglist).
Positional keys inside mode 2 are numeric one-based argument positions. The
Rust lowerer retains support for the earlier `0x9d`/`0x9e` diagnostic format.
The `call_targets` paired fixture verifies computed targets, proc paths, named
arguments, arglists, and one/two-target external calls without launching a server.

`0xa1` preserves native constructor order with operands `u8 argument_mode`
and `u32 argument_stack_size`. The type value precedes arguments; modified
types use the existing `0x9f` prototype value instead of a null/override sentinel.
The `constructor_order` fixture pairs field-selected types, conditional
arguments, named arguments, arglists, modified types, and proc/verb paths.

`0xa2` emits associative lists with native positional keys and a `u32` pair
count. Missing AST keys become one-based numeric positions; explicit null
key expressions remain null. Key and value expressions retain source evaluation
order. The `assoc_nativekeys` fixture distinguishes positional null values,
explicit null keys, named keys, and conditional or side-effecting expressions.
`0xa3` marks a normal method receiver before argument emission. It has no
operands: computed receivers are cached before arguments, while direct variable
receivers remain deferred native call operands. The matching `0x6a` closes any
receiver cache, supporting nested calls in LIFO order. Safe method calls retain
their existing short-circuit encoding. The `computed_method`, `receiver_mutation`,
and `mixed_safe_receivers` pairs verify receiver timing and nested cache use.

`0xa4` has no operands and preserves native membership evaluation order:
list first, then item. The lowerer emits `IsIn` with list mode 5 and reads the
comparison flag when used as a value. The `membership_conditional` fixture
covers conditional items/lists, nested calls, and direct branch use.
`0xa5` has no operands and consumes a native-ordered indexed assignment:
value first, then list and key. It is emitted only for discarded plain index
assignment statements whose reference has no safe operations. Compound assignments and safe references keep their existing encoding. The `indexed_order` and `indexed_conditional` pairs cover computed
keys/values and arbitrary conditional RHS expressions. Ordinary global calls
and safe method calls also preserve numeric positional keys in mixed named
argument lists (`mixed_call_keys`).
`0xa6` has no operands and duplicates the current value using native `PushTop`
(`0x13c`). Indexed assignment expressions emit their RHS, `0xa6`, the list/key
reference, then `0xa5`, retaining the assigned value for a return or enclosing
assignment. The `indexed_expression` fixture verifies side effects occur in
value/list/key order and covers chained and conditional assignments.
Build the patched compiler with .NET 10 after initializing the pinned
RobustToolbox submodule, then compile `.dme` files with an explicit
`--version=516.1687` target and a matching baseline JSON. The exporter
annotation patches used for full game translation also belong on that
same compiler commit; the diagnostic baseline and game must be built by
the same patched executable.

The diagnostic compile script uses a scratch manifest and asset junctions,
preserving `interface/skin.dmf` as a relative include. It does not require
postprocessing the JSON resource path.

Native animation extension `0xa7` carries argument mode and stack count.
Named options preserve AST numeric positional keys; scalar animate evaluates
only its first argument, while named forms evaluate all supplied values.
Native icon calls use the existing type-first constructor extension `0xa1`.
Named rgb arguments are normalized to native component slots; colorspace
calls use five components (omitted alpha is null) and native `RgbEx` 0x161.

Native field assignment extension `0xa8` carries a string-table field ID
followed by a retained-value byte. The exporter emits the assigned value,
then `0xa6` when the expression value is needed, then the receiver. The
native setter consumes its receiver and one value; the duplicated value
remains for the enclosing expression. Safe assignments and compound writes
remain separate paths. `logical_fields_nativeordered.json` preserves the
paired source receiver-mutation cases without replacing the legacy fixture.

Native field-operation extension `0xa9` carries the original operation byte,
a string-table field ID, and a discarded-value byte. Compound arithmetic
writes evaluate the RHS before the receiver; increment/decrement forms only
evaluate the receiver. The statement context is recorded by the compiler,
so the lowerer can preserve whether the operation result is requested.
Logical short-circuit assignment and safe receivers retain separate handling.

Native method-call extension `0xaa` carries the resolved OpenDream proc ID,
original identifier StringID, argument mode, and argument stack count. Typed
receivers retain their effective method declaration; unknown receivers use
the last declaration of that identifier, verified by reversed source-order
fixtures. The native resolver uses the selected proc's authored display name
(or the default underscore-to-space name). Literal dynamic `call()` targets
remain ordinary literal strings and do not use this mapping.

Native iterator extension `0xab` carries a `u32` filter mask before list
enumerator creation. It preserves untyped versus explicit `as anything` and
primitive/atom unions. Subtype-filtered list enumerators use an untyped
native iterator plus an explicit subtype guard. Typed world loops use the native
type-driven instance universe (`0x4000`), including datums and clients.
Iterator IDs are lifetime
identifiers, never native filter masks or local slots. The lowerer saves/restores
nested list iterators and unwinds list/range state on edges leaving nested loops.

The separate savefile-version patch adds the standard /savefile/byond_version declaration (default zero). This lets authored overrides survive export; native fixtures establish the corresponding world header and compatibility version. The patched-compiler build script applies it alongside the combined and repeated-include patches.

The combined patch preserves `\bold` and `\b` string controls using OpenDream's existing Bold suffix. Native interpolation controls select sentence capitalization by scanning the preceding punctuation, quotes, whitespace and tag-shaped suffixes. The portable `format_context` fixture checks 125 authored cases and 122 distinct encoded templates against DreamMaker, including bold spacing.


The pinned compiler patches also preserve native numeric constant semantics:
logarithms round their final quotient once, RGB/HSV/HSL conversion follows
native component rounding, and arithmetic/bitwise folding retains native
24-bit masks, shift clamps, remainder and zero behavior. Portable paired
fixtures verify the resulting float bits; this does not substitute for proving
runtime opcode behavior.

The separate repeated-include patch records ordered `.dms` includes in optional
`NativeClientScriptFiles` JSON metadata and includes their paths in `Resources`.
The Rust emitter writes those ResourceIDs before any explicit resource-valued
`client.script`. Exact duplicate includes are omitted, while an explicit script
can append the same resource again. Stock exports without this metadata cannot
recover script includes that their compiler discarded.

The combined patch exports optional source provenance for native header fields:
`NativeGraphicsAccess` and `NativeCpuAccess` distinguish resolved builtin
references from same-named custom fields and preserve relevant dead-code
mentions. CPU provenance excludes discarded pure field reads.
`NativeHubPassword` retains the last authored constant text assignment before
later null assignments, matching native hashing history. Prompt operand bits
31, 30, and 29 retain explicit `as anything`, authored choice presence, and an omitted `as` clause; the Rust
lowerer strips them before writing native operands. These additions retain the
pinned opcode hash and existing instruction widths.

`NativeClientSettings` preserves compiler-only client settings such as
show_map and macro_mode even when OpenDream has no corresponding runtime
class variable. Per-type metadata retains settings on actual client descendants.
The emitter applies descendants before ancestors and siblings in first type
creation order; the final authored assignment within each type wins. The older
root-only metadata remains readable. The three patch files were checked by
sequential application to a temporary index at the pinned source commit.

The native-ordered dynamic-call extension preserves external-call selection
for legacy two-target `call()` when its original first target is a string literal,
matching native CallLib/CallLibArgList. Resource, numeric and unresolved
targets retain ordinary dynamic-name dispatch. Paired fixtures assert the
actual opcodes, independently of header comparison.

Authored runtime `== null` and `!= null` comparisons retain equality operators
instead of being rewritten as `isnull()`. Native null operand loading clears the
evaluation register, which can release a retained managed call result; the
explicit `isnull()` builtin has different cleanup behavior. Runtime literal comparisons also retain their null loads; native compilation
does not fold them away. Ordinary numeric constant folding remains available.

Optional per-procedure `NativeNullOffsets` records optimized byte offsets of
authored null loads. The Rust lowerer uses the native Null reader at those
positions and keeps synthetic padding distinct. This source distinction is
needed for reversed and conditional comparisons as well as ordinary null
returns; a lookahead for only right-hand null comparisons is insufficient.

Implicit local and iterator defaults have internal source locations, so they
do not enter `NativeNullOffsets`. Authored null initializers keep their source
locations. This preserves the distinction between synthetic null values and
native null reads that release a retained evaluation result.

### Literal Unicode and format controls

Before string interning, literal source characters U+FF00 through U+FF5E are
prefixed with U+FF5E. A literal U+FF5E is therefore doubled. The Rust native
string encoder consumes these escaped pairs as literal UTF-8, while unescaped
markers retain their formatting meaning. Raw strings, Unicode escapes and
debug filenames use the same literal encoding. Legacy unpaired U+FF5E remains
literal. Source `\\...` emits an unescaped U+FF21 marker, mapped to native
FF12; a literal fullwidth A (U+FF21) remains UTF-8.

The standard `md5` constant initializer folds literal strings after decoding
these literal pairs to UTF-8. Unescaped formatting controls are excluded from
that fold. The paired `literal_format_unicode`, `escaped_ellipsis` and
`null_initializers` fixtures validate these contracts without running a server.

Optional `Globals.ConstGlobalIds` and `Globals.ConstFieldGlobalIds` preserve
native const-null binding references instead of folding them to anonymous nulls.
Reference discriminator 17 has no extra operands and denotes native receiver
Cache (`0xffd8`) for receiver evaluation; it is distinct from DM's return value
and the interpreter's Eval scratch.
These annotations retain the pinned opcode hash. See `FORMAT.md` for the binding
and owner-resolution contract.

World view parsing is implemented in Rust from native parser/validator/writer
and loader evidence; it requires no exporter extension. The public raw view word
remains unchanged, while `WorldViewEncoding` exposes the signed loader's radius
versus packed-dimension dispatch. The 30 native paired fixtures and Rust
regressions are under `fixtures/translation/world_view_shapes`.

Optional per-procedure `NativeDeleteClearOffsets` marks optimized safe guards
and stores generated while clearing a mutable deletion target. The compiler
captures the original value, pushes a synthetic literal null, reevaluates the
lvalue, clears it, and deletes the captured value. Synthetic nulls preserve
native assignment and reference-read ordering through optimization. Readonly
bindings and temporary values omit the clear. `NativeDeleteSrcOffsets` marks
direct `del(src)`, which requires native procedure termination after deletion.
These annotations retain the existing opcode hash and instruction widths.
Native paired probes cover safe, indexed, effectful, conditional and readonly
targets in `fixtures/translation/delete_lvalue`.

## Native authored branch provenance

`NativeGotoOffsets` records all authored goto branches, including forward and
adjacent-label jumps. Unprotected gotos use native JmpLoop for its CPU-budget
check; protected gotos retain TryJmp and its exception-frame behavior.

`NativeContinueOffsets` is present even when empty. The lowerer uses it to
distinguish authored continues from synthetic if/else joins near a loop tail.
Those joins use ordinary Jmp; adding JmpLoop there performs an extra budget
check. Legacy missing metadata retains the previous bounded heuristic. Source
marks survive optimization without changing opcode widths or the opcode hash.
Fresh paired fixtures are in `goto_budget` and `continue_budget`.

## Native resource archive order

The combined exporter patch adds optional program `NativeResourceArchiveOrder`,
exported as an array even when empty. Names use native archive spelling, including
case aliases, normalized path separators and the generated-icon prefix mapping.
Included DMS and interface phase tokens are part of the array. The emitter expands
an interface token into skin imports before the interface itself.

Resource literals are retained from the source AST, including overwritten and
optimized-away expressions, and grouped by native source-created type hierarchy.
The exporter distinguishes explicitly created groups from implicit parent groups,
and preserves source positions for authored builtin-root groups. Switch-case
containers and weighted-pick structs are traversed as well as AST nodes.
Fresh native probes and exact ordered signatures are in
`fixtures/translation/resource_archive_order`; resource kind collisions are in
`resource_cross_kind_order`. Incremental native RSC reuse is excluded from these
fixtures because retained entries can misrepresent registration order.

