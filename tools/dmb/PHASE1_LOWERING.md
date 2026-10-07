# Phase 1: semantic resolver and symbolic lowering migration

This is the implementation boundary audit, not a claim that production lowering has migrated. The cold frontend now has a resolved tree model; the production BYOND lowerer still uses `LowerBindings` and `SharedLowerBindings` in `dm-codegen-byond/src/simple.rs`. The new IR query and relocation interfaces provide the replacement boundary. Their consumers remain to be wired.

## Explicit procedure inputs

A lowering unit needs its procedure identity and override occurrence, owning type, typed signature, body syntax, lexical locals, current source occurrence, and compiler/ABI configuration. Current procedure/type special values are explicit unit inputs. Local scopes, parameters and body-local inference belong to this unit rather than project queries. Source spelling and absolute positions belong to the occurrence table, separately from reusable semantic code.

## Project queries discovered in the existing lowerer

| Existing read | Resolver boundary | Dependency meaning |
|---|---|---|
| `parent_types`, ancestor walks | Parent / Ancestry | Explicit parent and inherited lookup chain |
| `modified_instances` | RuntimeType | Modified instance alias versus its underlying class |
| field inventories and types | Var | Positive or negative field lookup, full declared metadata |
| global inventories and types | GlobalVar | Global declaration and declared type |
| `member_globals` | StaticVar | Shared variable slot identity, distinct from instance field spelling |
| `unique_member_global` | UniqueStaticVar | Name-specific uniqueness across types, including instance-field collisions |
| static procedure maps | Proc / GlobalProc | Resolved callable, proc versus verb namespace |
| separate declared-procedure inventory | HasMemberProc | Declaration presence even when static target selection fails |
| override implementation selection | OverrideChain | Ordered implementations and per-member meaning |
| copied formal metadata | Signature | Typed defaults, annotations and argument ordering |
| numeric/string predefined maps | PredefinedConstant | Lookup after lexical shadow checks |
| initializer expressions | Constant | Authoritative constant value or explicit unsupported result |
| resource paths / FILE_DIR | ResourceIn | Search-context identity plus resolved content or missing result |

These queries return semantic payloads rather than fingerprints alone. `Member` contains immutable `DeclarationMeaning`; fingerprints identify that meaning. `Missing` is a real negative result. `Unsupported` means the provider has not implemented the operation, and must never be treated as absence. The tree provider implements source-positive procedure presence and shared slot queries. Its explicit `with_complete_intrinsics` inventory enables authoritative negatives and name-indexed static uniqueness; absent that certification, intrinsic-dependent negatives and uniqueness remain Unsupported. Runtime aliases, predefined values and scoped resources remain Unsupported. Shared slot answers retain both structural identity and declaring owner/name for final linking.

Identifier lowering currently checks local, parameter, field and global shadowing before predefined constants (`simple.rs`, expression identifier handling). All negative checks affect the dependency record. Unqualified calls separately query a static callable and declared-procedure presence. Combining these into one digest loses a meaningful distinction. `unique_member_global` currently scans project-wide inventories; its replacement should maintain a name-indexed inventory query, including negative collision evidence. Existing ancestor walks have a fixed 64-step cap; the semantic tree already validates ancestry and should supply the authoritative chain instead.

Builtin arity/opcode policies are compiler-schema inputs. They must participate in compiler/cache version identity without being disguised as source dependencies. A synthetic resolver that reads the same complete SharedLowerBindings snapshot would retain global invalidation and would not complete this migration.

## Symbolic operands and linking

`dm-ir::SymbolicCode` owns immutable words with zero placeholders and canonical offset-ordered relocations. The linker alone assigns output indexes. `validate_sites` requires an exact whitelist from the typed ABI operand encoder: omitted references, references on immediate/tag words, duplicate sites and wrong table kinds are rejected. Storage validation alone cannot infer BYOND operand structure from integer words.

| Existing codegen operand | Symbolic representation / table |
|---|---|
| String, dynamic proc name, instance field name, static-field name | String symbol |
| Class path | Type symbol / class table |
| Static proc and static verb | Separate Proc and Verb references / proc table |
| Ordinary global or static variable | VariableSlot / variable table |
| Builtin `global.vars` | BuiltinGlobalVars / variable table |
| Modified instance value | Instance / instance table |
| Constant list | ConstantList content identity / list table |
| Resource value | Resource content identity / resource table |
| Source file and relative line | SourceFile occurrence origin and LineDelta |

Do not encode instance field names as variable-table references: the existing encoder resolves those through the string table. Builtin `global.vars` is distinct from an ordinary variable named `vars`. A modified instance is distinct from its runtime class. Procedure and verb namespace must remain distinguishable even though both link through the procedure table.

Compound `VariableWord` encodings (`Initial`, `IsSaved`, `SetCache`, and nested selectors) must be flattened by the ABI-aware encoder, preserving the existing operand widths. Labels and branches are intra-procedure word offsets: resolve them locally before freezing symbolic words; they are not external table relocations. Keep the final BYOND instruction-boundary decoder validation. The new IR does not yet replace this encoder or debug-source emission.

Artifact fingerprints now serialize explicit versioned bytes for word counts, words, relocation offsets and reference variants. They never serialize Debug output, pointer values or tree arena IDs. Input relocation order is canonicalized. Source-origin ordinals are per-unit references whose current occurrence supplies actual file spelling; they are not a claim that source debug emission is already integrated.

## Initializer and bootstrap migration

`dm-compiler/src/bootstrap.rs` constructs the shared maps and copies parameter metadata into LowerBindings. It also discovers procedure-local statics and folds initializer values while reading mutable DMB strings, classes and variable tables. Dynamic initializer ordering depends on global constructor registration. These are hidden mutable-output inputs that must leave semantic lowering.

The replacement should emit symbolic initializer values and explicit ordered registration records, retaining both formal declaration defaults and class assignment overrides. Procedure-local static slots remain distinct from explicit globals. Only final linking converts those records to DMB slots and indexes. The pure scalar constant evaluator has been extracted into dm-tree and production delegates through decoder/nameof callbacks; authoritative general list/resource/initializer evaluation is still separate work.

## Remaining integration work, in order

1. Define the actual per-procedure input object and route existing lookups directly through Resolver, preserving shadowing, negative results and inheritance semantics.
2. Implement runtime-type, shared-slot, uniqueness, declared-proc-presence and predefined-constant providers using resolved declarations and name indexes. Implement scoped resource queries in the filesystem/resource host.
3. Convert typed codegen operands to SymbolId references and emit the expected relocation-site ledger while preserving compound ABI encoding and local branch resolution.
4. Move initializer/static registration off mutable DMB reads into symbolic semantic records with explicit ordering.
5. Replace bootstrap map construction and string-key ledger binding with final table assignment from semantic identities. Remove the old shared binding snapshots once the new path handles their callers.
6. Connect dependency recording to these direct queries; cache keys include unit inputs, observed positive/negative meanings and compiler schema. No project-wide member digest should remain in procedure keys.
7. Validate narrow fixture behavior, fresh-versus-reused output equality and final operand boundaries before switching production. Parent controls focused Cargo gates and runtime validation.

No production lowerer switch, incremental performance improvement or full Phase 1 completion is asserted by this document. Query variants remain unsupported where no authoritative provider or complete intrinsic configuration has been connected.


## Engine completeness contract

Source-only tree navigation remains available through direct analysis APIs. The full-program Resolver conservatively reports Unsupported for unknown declarations and uncertified ancestry: lexical source parents alone do not establish BYOND intrinsic inheritance (`/obj` inherits `/atom/movable`, which inherits `/atom`). Complete negative queries require a caller-supplied `EngineHierarchy` with pinned schema and explicit parent rows, already merged into the tree, plus the complete intrinsic member inventory. Attachment returns structured errors for missing owners, duplicate/conflicting rows or mismatched parents. Parent and inventory configuration participate in semantic identity. Intrinsic lookups use a prebuilt owner/name/kind index; unique slots use a name index.

The bounded attachment API validates a supplied engine snapshot. Template extraction and engine-first frontend seeding are implemented; intrinsic metadata migration remains incomplete. Presence-only intrinsic records cannot fabricate typed proc/var/constant metadata and those typed queries remain Unsupported when only presence is known. Shared-slot answers include exact declaring owner/name; that tuple is authoritative for linking and the convenience hash must not choose a slot without tuple comparison.

### Pinned engine input implementation

`dmbc::engine::EngineSnapshot` now decodes exact template bytes into collision-checked class paths, explicit class parents, member presence and declaring shared-slot inventory. Raw variable/procedure records remain in an explicitly opaque metadata collection; they are not interpreted as source types/defaults/modifier flags. The snapshot hashes exact template bytes and caller schema. Its engine type skeletons seed the tree before source resolution and establish `/obj` -> `/atom/movable` -> `/atom` from the decoded parent table.

Template member lists alone are not a complete intrinsic catalog: existing bootstrap supplies additional intrinsic fields separately. Therefore the engine extractor attaches through `with_engine_intrinsics`, which certifies hierarchy but keeps unknown-member and unique-slot queries Unsupported. Full member completeness requires separately supplying the authoritative complete catalog. Source overrides needing an opaque intrinsic member base remain an explicit migration limitation; this slice does not manufacture MemberMetadata for them.

The uncached frontend accepts an explicit engine seed before source resolution.
Engine type entries never receive invented source occurrences. `dmbc analyze
--engine-template PATH` decodes that input and the JSON-lines schema records its
identity, hierarchy coverage and incomplete intrinsic metadata. It still exports
analysis rather than compiling a DMB.

### Shared ABI encoder

The existing linked encoder and symbolic freezing now share one operand emission
path. An explicit semantic binder maps old symbolic keys to `SymRef`; it does not
assign wire indexes. `SymbolicCode` relocations describe direct words or packed
24-bit values with their exact ABI tag. Both packed placeholder words, overlap,
table kind, encoding and range are checked. The shared IR linker produces private
linked words and leaves reusable code unchanged, including on failed resolution.
Production procedure lowering still needs its project reads migrated to Resolver.
