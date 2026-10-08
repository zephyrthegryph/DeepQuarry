# dm-link

Independent Phase 1 core for immutable table assignment and relocatable words.

`LinkInventory` supplies exact semantic entries and collision-checked symbol
spellings, explicit pinned engine bindings, optional full observable table orders,
and structural shared-slot aliases. Keys distinguish proc/verb and builtin global
vars even when they share a wire table. Unordered tables use canonical key order;
this is deterministic, not a claim that those orders match all BYOND metadata.

`LinkTables::build` rejects inconsistent content, slot tuple collisions, unknown
order entries and conflicting fixed bindings. Reserved holes below fixed indexes
are preserved. `link` returns fresh immutable procedure words with direct or
explicit packed index fields and current source occurrence rebasing. Unknown
references and overflow are errors. The producer must still supply ABI-validated
relocation sites: this crate does not infer opcodes from integers.

Final wire-domain admission is part of shared linking. A semantic class symbol
does not always denote a VM class-table index: packed value tag 8 (`MobPath`)
denotes a mob-table index. Composition materializes the exact shared mob roster
after classes exist, then `admit_type_path_words` converts only certified tag-8
`SymRef::Type` sites while checking their original class binding. Other tags,
retained engine words and already-native defaults are untouched. Missing mob
bindings fail. The final output bytecode validator still runs.
Root `/client` packed tag 59 is likewise admitted to singleton payload zero;
unsupported nonroot client paths carrying that tag fail rather than being
silently collapsed to the root singleton. Other class-path tags remain unchanged.
Future direct-ID lowering must preserve these explicit wire-domain distinctions; a
numeric ID without its wire domain is insufficient.

InitializerReferences keeps ordered symbolic reads, writes and registration
records separate from code. Validation checks all keys against the same frozen
tables. Initializer ordering/lowering remains the frontend/lowerer's contract.

This crate does not emit DMB sections, derive observable engine orders, decode
initializers, or replace production bootstrap. Metadata/RSC composition remains
outside this bounded core. No historical Ledger or global ID maps are used.
