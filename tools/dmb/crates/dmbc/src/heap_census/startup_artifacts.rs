//! Borrowed exact startup syntax/layout owners; private map nodes excluded.
use super::*;
use crate::startup::{StartupArtifact, StartupArtifacts};
use dm_session::ObservedArtifactStorageView as View;
fn declarations(census: &mut HeapCensus, rows: &Arc<[Arc<dm_ir::ProcedureStaticDeclaration>]>) {
    census.slice("startup.static_declarations", rows, true);
    for declaration in rows.iter() {
        if census.arc_object("startup.static_declaration", declaration) {
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
            census.slice("startup.artifact_reads", reads, true);
            census.slice("startup.artifact_versions", versions, true);
            for read in reads.iter() {
                declarations(census, &read.answer);
            }
            census.arc_object("startup.artifact_owner", value);
            match value.as_ref() {
                StartupArtifact::Syntax(receipt) => {
                    if census.arc_object("startup.syntax", receipt) {
                        census.arc_text("startup.syntax_source", receipt.source());
                        census.static_plan(receipt.plan());
                    }
                }
                StartupArtifact::Layout(layout) => {
                    if census.arc_object("startup.layout", layout) {
                        declarations(census, layout.declarations());
                    }
                }
            }
        }
    });
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
