# Numeric power-grid dependencies

Power grids retain their Rust numeric identities. Domain-owned grid records
publish tracked field changes; their registry publishes the exact numeric
identity on creation, deletion and replacement.

`READ_LOOKUP` describes the real lookup, registry, identity key and result type.
Generated bindings follow actual argument fields, the per-ID registry key and
the selected record. Holder reads belong to the holder's lifecycle. Contextual
reads belong to the actual menu, pending operation or window lifetime, using
weak handles rather than retaining pooled action contexts. Pure providers do
not register dependencies or create grid records.

The system's write step adopts genuinely watched positive Rust regions and
publishes their identity and subsequent field changes. Missing negative test
IDs remain absent. Virtual argument aliases are rejected until typed descriptors
can express them; genuine tracked fields on related profile records are supported.

Source and focused regressions are prepared. Compilation, analyzer checks and
runtime verification remain pending; no pins have been blessed.
