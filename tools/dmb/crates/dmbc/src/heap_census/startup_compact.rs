//! Complete startup payload charges; private scalar containers get conservative
//! logical envelopes, never an assertion about allocator/private process bytes.
use super::*;
use crate::startup::{StartupAnswer, StartupArtifact};

fn map_charge<K, V>(len: usize) -> Option<usize> {
    len.checked_mul(size_of::<(K, V)>().checked_add(64)?.checked_mul(16)?)
}
fn allocation(
    c: &mut HeapCensus,
    owner: &Arc<crate::startup_allocation::AllocationReceipt>,
) -> Option<usize> {
    if !c.arc_object("compact.startup_allocation", owner) {
        return Some(0);
    }
    c.vec_payload("compact.allocation_keys", &owner.keys);
    c.vec_payload("compact.allocation_bindings", &owner.bindings);
    if let Some(input) = &owner.input {
        c.vec_payload("compact.allocation_targets", &input.targets);
        c.vec_payload("compact.allocation_owners", &input.owners);
        c.vec_payload("compact.allocation_registrations", &input.registrations);
        c.vec_payload("compact.allocation_callables", &input.callables);
    }
    map_charge::<dm_link::Key, usize>(owner.ranks.len())?
        .checked_add(map_charge::<dm_link::Key, dm_ir::SymbolId>(
            owner.registration_owners.len(),
        )?)?
        .checked_add(map_charge::<dm_ir::SymbolId, usize>(
            owner.source_owners.len(),
        )?)?
        .checked_add(map_charge::<(dm_ir::SymbolId, dm_ir::SymbolId), usize>(
            owner.callable_positions.len(),
        )?)
}
pub(crate) fn weight<Q>(
    key: &Arc<[u8]>,
    reads: &dm_session::Receipt<Q, StartupAnswer, Option<dm_ir::ReadDomain>>,
    versions: &Arc<[(Option<dm_ir::ReadDomain>, u128)]>,
    value: &Arc<StartupArtifact>,
) -> Option<usize> {
    let mut c = HeapCensus::new("compact_startup_charge");
    c.slice("compact.key", key, true);
    c.receipt("compact.reads", reads);
    c.slice("compact.versions", versions, true);
    for read in reads.iter() {
        match &read.answer {
            StartupAnswer::Static(rows) => super::declarations(&mut c, rows),
            StartupAnswer::Resolver(answer) => {
                super::super::resident_weight::answer(&mut c, answer)
            }
            StartupAnswer::Unavailable => (),
        }
    }
    c.arc_object("compact.startup_artifact", value);
    let private = match value.as_ref() {
        StartupArtifact::Syntax(receipt) => {
            if c.arc_object("compact.static_syntax", receipt) {
                c.arc_text("compact.static_source", receipt.source());
                let symbols = c.static_plan(receipt.plan());
                super::declarations(&mut c, receipt.canonical_declarations());
                symbols
            } else {
                0
            }
        }
        StartupArtifact::Layout(layout) => {
            if c.arc_object("compact.static_layout", layout) {
                super::declarations(&mut c, layout.declarations());
            }
            0
        }
        StartupArtifact::Inventory(receipt) => {
            let (rows, owner) = receipt.storage();
            c.vec_payload("compact.inventory_roster", rows);
            for (_, layout) in rows {
                if c.arc_object("compact.static_layout", layout) {
                    super::declarations(&mut c, layout.declarations());
                }
            }
            if c.arc_object("compact.static_inventory", owner) {
                let (_, capacity) = owner.procedure_storage();
                let declarations = owner.declarations().count();
                for declaration in owner.declarations() {
                    super::declaration_payload(&mut c, declaration);
                }
                for layout in owner.certificates() {
                    if c.arc_object("compact.static_layout", layout) {
                        super::declarations(&mut c, layout.declarations());
                    }
                }
                // HashSet capacity is actual exposed backing capacity; scalar
                // slots/control and BTree nodes are conservative logical models.
                capacity
                    .checked_mul(
                        size_of::<dm_ir::ProcedureIdentity>()
                            .checked_add(16)?
                            .checked_mul(2)?,
                    )?
                    .checked_add(map_charge::<
                        dm_ir::ProcedureStaticIdentity,
                        Arc<dm_ir::ProcedureStaticDeclaration>,
                    >(declarations)?)?
                    .checked_add(map_charge::<
                        dm_ir::ProcedureIdentity,
                        Arc<dm_tree::procedure_statics::StaticLayout>,
                    >(owner.certificate_count())?)?
            } else {
                0
            }
        }
        StartupArtifact::Allocation(owner) => allocation(&mut c, owner)?,
        StartupArtifact::AllocationFinal(owner) => {
            if c.arc_object("compact.allocation_final", owner) {
                let mut private = allocation(&mut c, &owner.input.allocation)?;
                c.vec_payload("compact.classifications", &owner.input.classifications);
                for (_, _, _, identity) in &owner.input.classifications {
                    identity.visit(|identity| {
                        c.arc_object("compact.classification_identity", identity);
                    });
                }
                if c.arc_object("compact.ordered", &owner.ordered) {
                    c.vec_payload("compact.ordered_keys", &owner.ordered.keys);
                    private = private.checked_add(map_charge::<dm_link::Key, usize>(
                        owner.ordered.ranks.len(),
                    )?)?;
                }
                private
            } else {
                0
            }
        }
    };
    super::super::initializer_artifacts::compact_charge(c, private)
}
