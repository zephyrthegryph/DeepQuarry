//! Opt-in actual prepared-key payload accounting; private index layout stays unknown.
use super::*;
use dm_session::ObservedArtifactStorageView as View;
pub(super) fn inspect(c: &mut HeapCensus, store: &crate::initializer_policy::InitializerArtifacts) {
    let owner = "initializer_prepared_keys";
    store.visit_prepared_key_storage(|view| match view {
        View::Store { entries, buckets } => {
            c.observe_items(owner, entries);
            if buckets != 0 {
                c.unknown(
                    owner,
                    "private observed-store index nodes and control blocks excluded",
                );
            }
        }
        View::Bucket {
            address,
            len,
            capacity,
            element_size,
        } => {
            c.buffer(
                owner,
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
        } => {
            c.slice(owner, key, true);
            c.slice(owner, versions, true);
            if c.receipt(owner, reads) {
                for read in reads.iter() {
                    if c.arc_object(owner, &read.answer) {
                        let write = &read.answer.write;
                        match &write.value {
                            dm_ir::InitializerValue::Expression(expr) => c.expression(owner, expr),
                            dm_ir::InitializerValue::ArrayAllocation(array) => {
                                c.array(owner, array)
                            }
                            dm_ir::InitializerValue::NoAuthoredValue => (),
                        }
                        if let Some(array) = &write.declared_array {
                            c.array(owner, array);
                        }
                    }
                }
            }
            if c.arc_object(owner, value) {
                c.slice(owner, &value.bytes, true);
            }
        }
    });
}
