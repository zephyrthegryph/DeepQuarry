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

The first lane-ready run compiled production code with zero errors and zero
DreamChecker diagnostics, and passed analyzer checks and ratchets. It passed
46 of 51 focused tests, including both requirement/conversion pins and the
incremental appearance pins. No pins have been blessed. The branch is not yet
stamped: dependency and fixture repairs require current-commit verification.

Native records are hydrated before their registry identity is published. Subsequent
Rust ledger samples use a synchronous state-publication batch: actual setters
write the complete sample before exact changed keys are delivered. Nested batches
deduplicate keys, weak receiver handles avoid extending lifetimes, and completed
mutations still publish when a writer throws. This prevents an intermediate
supply/load pair from falsely canceling an otherwise allowed pending operation.
The real native adoption and atomic-publication regression passed that run:
a completed allowed sample retains the pending operation, while a completed
insufficient-supply sample cancels it. Nested batches, writer faults, dead
receivers and purity checks also passed. A subsequent repair run passed the
target/held-context and delivery-fault tests. The remaining static-lookup and
inherited-stat failures were traced to membership-expression precedence and
lexical rather than declared-parent traversal. Their retry passed lookup lifetime,
output invalidation and reentrant delivery. The remaining periodic fixture needs
an explicit real drain before measuring its one-second interval: parked work
starts that interval when its queued wake hook drains. The fixture now checks
arming, the actual edge, parking and resumption separately; its retry passed on
`b62b84e3b6` (one test, zero failures, clean boot). All five original failures
have now passed targeted repair runs. A fresh lane-ready gate remains required.
None of these result sets substitutes for a lane-ready stamp.
