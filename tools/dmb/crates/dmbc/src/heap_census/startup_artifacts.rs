//! Borrowed exact startup syntax/layout owners; private map nodes excluded.
use super::*;
use crate::startup::{StartupArtifact, StartupArtifacts};
use dm_session::ObservedArtifactStorageView as View;
#[path = "startup_compact.rs"]
pub(crate) mod compact;
pub(super) fn declarations(
    census: &mut HeapCensus,
    rows: &Arc<[Arc<dm_ir::ProcedureStaticDeclaration>]>,
) {
    census.slice("startup.static_declarations", rows, true);
    for declaration in rows.iter() {
        declaration_payload(census, declaration);
    }
}
pub(super) fn declaration_payload(
    census: &mut HeapCensus,
    declaration: &Arc<dm_ir::ProcedureStaticDeclaration>,
) {
    if census.arc_object("startup.static_declaration", declaration) {
        census.slice("startup.lexical_locals", &declaration.lexical_locals, true);
        if let Some(array) = &declaration.declared_array {
            census.array("startup.static_array", array);
        }
        match &declaration.initializer {
            dm_ir::InitializerValue::Expression(value) => {
                census.expression("startup.static_expression", value)
            }
            dm_ir::InitializerValue::ArrayAllocation(array) => {
                census.array("startup.static_array", array)
            }
            dm_ir::InitializerValue::NoAuthoredValue => (),
        }
    }
}
#[path = "startup_callable_census.rs"]
mod callable;
pub(crate) fn inspect(census: &mut HeapCensus, store: &StartupArtifacts) {
    callable::inspect(census, store);
    store.visit_storage(|view| match view {
        View::Store { entries, .. } => {
            census.observe_items("startup.artifact_store", entries);
            census.unknown(
                "startup.artifact_store",
                "private BTree node and allocator overhead excluded",
            );
        }
        View::Bucket {
            address,
            len,
            capacity,
            element_size,
        } => {
            census.buffer(
                "startup.artifact_buffers",
                address,
                len.saturating_mul(element_size),
                capacity.saturating_mul(element_size),
            );
        }
        View::Entry {
            key,
            reads,
            versions,
            value,
            ..
        } => {
            census.slice("startup.artifact_keys", key, true);
            census.receipt("startup.artifact_reads", reads);
            census.slice("startup.artifact_versions", versions, true);
            for read in reads.iter() {
                match &read.answer {
                    crate::startup::StartupAnswer::Static(rows) => declarations(census, rows),
                    crate::startup::StartupAnswer::Resolver(answer) => {
                        super::resident_weight::answer(census, answer)
                    }
                    crate::startup::StartupAnswer::Unavailable => (),
                }
            }
            census.arc_object("startup.artifact_owner", value);
            match value.as_ref() {
                StartupArtifact::Syntax(receipt) => {
                    if census.arc_object("startup.syntax", receipt) {
                        census.arc_text("startup.syntax_source", receipt.source());
                        census.static_plan(receipt.plan());
                        declarations(census, receipt.canonical_declarations());
                    }
                }
                StartupArtifact::Layout(layout) => {
                    if census.arc_object("startup.layout", layout) {
                        declarations(census, layout.declarations());
                    }
                }
                StartupArtifact::Inventory(receipt) => {
                    let (rows, owner) = receipt.storage();
                    census.vec_payload("startup.inventory_roster", rows);
                    for (_, layout) in rows {
                        if census.arc_object("startup.layout", layout) {
                            declarations(census, layout.declarations());
                        }
                    }
                    inventory(census, owner);
                }
                StartupArtifact::Allocation(owner) => allocation(census, owner),
                StartupArtifact::AllocationFinal(owner) => {
                    if census.arc_object("startup.allocation_final", owner) {
                        allocation(census, &owner.input.allocation);
                        census.vec_payload(
                            "startup.allocation_classifications",
                            &owner.input.classifications,
                        );
                        for (_, _, _, classification) in &owner.input.classifications {
                            classification.visit(|owner| {
                                census.arc_object("initializer_classification.identity", owner);
                            });
                        }
                        if census.arc_object("startup.allocation_ordered", &owner.ordered) {
                            census.vec_payload("startup.allocation_keys", &owner.ordered.keys);
                            census.observe_items(
                                "startup.allocation_ranks",
                                owner.ordered.ranks.len(),
                            );
                            census.unknown(
                                "startup.allocation_ranks",
                                "private BTree node backing unavailable",
                            );
                        }
                    }
                }
            }
        }
    });
}
fn allocation(census: &mut HeapCensus, owner: &Arc<crate::startup_allocation::AllocationReceipt>) {
    if !census.arc_object("startup.allocation", owner) {
        return;
    }
    census.vec_payload("startup.allocation_keys", &owner.keys);
    census.vec_payload("startup.allocation_bindings", &owner.bindings);
    if let Some(input) = &owner.input {
        census.vec_payload("startup.allocation_targets", &input.targets);
        census.vec_payload("startup.allocation_source_owners", &input.owners);
        census.vec_payload("startup.allocation_registrations", &input.registrations);
        census.vec_payload("startup.allocation_callables", &input.callables);
    }
    for (label, len) in [
        ("startup.allocation_ranks", owner.ranks.len()),
        (
            "startup.allocation_registration_owners",
            owner.registration_owners.len(),
        ),
        ("startup.allocation_owner_ranks", owner.source_owners.len()),
        (
            "startup.allocation_callable_positions",
            owner.callable_positions.len(),
        ),
    ] {
        census.observe_items(label, len);
        census.unknown(label, "private BTree node backing unavailable");
    }
}

pub(super) fn inventory(
    census: &mut HeapCensus,
    inventory: &Arc<dm_tree::procedure_statics::StaticInventory>,
) {
    if !census.arc_object("startup.static_inventory", inventory) {
        return;
    }
    let (len, capacity) = inventory.procedure_storage();
    census.observe_items("startup.static_inventory", len);
    census.observe_items("startup.static_certificates", inventory.certificate_count());
    census.unknown("startup.static_inventory", &format!("private procedure HashSet backing: {len} entries, {capacity} capacity; declaration/certificate BTreeMap node backing unavailable"));
    for declaration in inventory.declarations() {
        if census.arc_object("startup.static_declaration", declaration) {
            census.slice("startup.lexical_locals", &declaration.lexical_locals, true);
            if let Some(array) = &declaration.declared_array {
                census.array("startup.static_array", array);
            }
            match &declaration.initializer {
                dm_ir::InitializerValue::Expression(value) => {
                    census.expression("startup.static_expression", value)
                }
                dm_ir::InitializerValue::ArrayAllocation(array) => {
                    census.array("startup.static_array", array)
                }
                dm_ir::InitializerValue::NoAuthoredValue => (),
            }
        }
    }
    for layout in inventory.certificates() {
        if census.arc_object("startup.layout", layout) {
            declarations(census, layout.declarations());
        }
    }
}
