use super::*;
pub(super) fn inspect(census: &mut HeapCensus, store: &StartupArtifacts) {
    store.visit_callable_storage(|view| match view {
        View::Store { entries, .. } => {
            census.observe_items("startup.callable_index", entries);
            census.unknown(
                "startup.callable_index",
                "private observed-store BTree node backing excluded",
            );
        }
        View::Bucket {
            address,
            len,
            capacity,
            element_size,
        } => {
            census.buffer(
                "startup.callable_buckets",
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
            census.slice("startup.callable_keys", key, true);
            census.slice("startup.callable_reads", reads, true);
            census.slice("startup.callable_versions", versions, true);
            for read in reads.iter() {
                census.callable_roster(&read.answer);
            }
            if census.arc_object("startup.callable_owner", value)
                && census.arc_object("startup.callable_map", value.as_ref())
            {
                census.observe_items("startup.callable_map", value.len());
                census.unknown(
                    "startup.callable_map",
                    "UnitIdentity/MemberId BTreeMap node backing excluded",
                );
            }
        }
    });
}
