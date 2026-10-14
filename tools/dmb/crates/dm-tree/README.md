# dm-tree integration

This is a new immutable model, not a wrapper around dm-semantics. The builder
resolves forward parent declarations, materializes lexical ancestors, checks
cycles in linear graph traversal, indexes local declarations by hashed symbol,
and records inheritance/reopen chains separately from source provenance.

`Skeleton::Member.content` is the complete declaration meaning hash (including
initializers/defaults/settings), **excluding executable procedure bodies**.
Procedure body occurrence hashes belong to the lowering input. Metadata canonical
bytes must use a stable, versioned serializer from the parser adapter.

Integration steps:

1. The frontend emits skeletons in include/source order and separate Provenance
   entries in exactly the same order. All symbol references must be interned.
2. Build SemanticTree once per changed ordered skeleton sequence; hold it in Arc.
3. Rebuild OccurrenceTable for every build against the current origins. Its identity
   ensures consumers do not attach origins to an unrelated semantic snapshot.
4. dm-lower uses dm-ir::Resolver; no dense arena ID crosses the boundary.
5. The AST adapter supplies signature/default/settings tokens and literal const
   expressions. Nonliteral constant queries and resource lookup return explicit
   Unsupported. The extracted constants::evaluate_with evaluator preserves scalar
   semantics through syntax string-decoding/nameof callbacks. Its canonical_bytes
   representation can populate resolved values after authoritative evaluation.
   Runtime/list initializers remain symbolic; do not pretend they are scalars.
6. Preserve source_order for linker provenance. lexical_types and visible_verbs are
   explicitly named analysis views, not a universal BYOND ordering certification.

No legacy bootstrap or production compilation path is switched by this crate.
The parent agent owns workspace integration and builds/checks with -j1.

The adapter now handles nested var/proc/verb namespace blocks, sized/unsized arrays,
absolute declarations and field-default overrides. Namespaces are normalized
without moving their source spans. Field overrides retain inherited type/flags.
Procedure bodies are excluded while signature/default tokens and all set metadata
remain in declaration identity. `DefinitionMode::Implicit` handles bare methods.

Scalar evaluator integration: reexport dm_tree::constants::Constant from the
compiler const_eval wrapper, then delegate evaluate(source, resolve) to
`evaluate_with(source, resolve, |raw| dm_codegen_byond::decode_constant_string_literal(raw).ok().flatten(), |expr| dm_codegen_byond::nameof_reference(expr).map(str::to_owned))`.
This preserves the original decoder and nameof behavior without a BYOND dependency
in dm-tree. The extracted operator evaluator is unchanged.


The analysis API exposes `MemberMetadata.procedure` with typed ordered parameters
(name/type/default/input annotation/source selection), variadic and return
annotations, and ordered named settings with explicit assignment versus `in`.
Expressions expose interned tokens and relative spans. Fingerprints serialize
explicit semantic fields and omit positions, preserving source relocation.
`count = 3 as num` therefore has separate default `3` and annotation `num`.
The known no-category bit 0x20 remains an output concern; the model retains the actual category setting expression.

Inherited field metadata is resolved in previous-link dependency order, including
children appearing before parents and grandparents. `lexical_types` is only a
lexical path analysis view; explicit nonlexical parents can appear after children.
`from_ast_in_scope` preserves the containing scope for parsed fragments. Includes
cutting through an indented declaration require a combined encounter AST or parser
continuation; parsing each region as a root file would be incorrect.


The pure declaration/signature/expression/settings/value structures now live in
`dm-ir`; dm-tree reexports them and owns only parsing and resolution. Every
Resolver member answer shares `Arc<DeclarationMeaning>` containing actual types,
flags, typed signature/settings/defaults, initializer and evaluated scalar values,
not just a fingerprint. Numeric/null/path constants resolve through the extracted
scalar evaluator. Constants requiring external names or string-decoding callbacks
remain Unsupported until authoritative evaluation fills `resolved_constant`.
Arrays expose ordered symbolic dimensions and element type; lowerers never need
to reparse an opaque header. The shared SymbolTable resolves token spelling.

The formal declaration and class assignment are distinct. Formal methods establish
a group's base independent of encounter position, while implicit overrides chain
in encounter order. Occurrence order is never changed. `declared_initializer`
retains the formal field default alongside the effective `initializer`. Tests use
the recorded manifest-order probes rather than inventing a DME deferral rule.

Canonical expressions preserve adjacency between operator/punctuation characters,
because the parser distinguishes `++` and `+ +`. Ordinary whitespace positions
remain excluded from fingerprints. `SymbolicExpression::source_text` reconstructs
lowering input with equivalent adjacency using shared symbols.
