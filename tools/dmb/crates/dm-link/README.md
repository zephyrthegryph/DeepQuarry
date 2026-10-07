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

InitializerReferences keeps ordered symbolic reads, writes and registration
records separate from code. Validation checks all keys against the same frozen
tables. Initializer ordering/lowering remains the frontend/lowerer's contract.

This crate does not emit DMB sections, derive observable engine orders, decode
initializers, or replace production bootstrap. Metadata/RSC composition remains
outside this bounded core. No historical Ledger or global ID maps are used.
