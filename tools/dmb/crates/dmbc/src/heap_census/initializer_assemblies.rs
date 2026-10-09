//! Actual accessible owners of retained assembled initializer code.
use super::*;
use crate::initializer_lowering::InitializerAssemblies;
use dm_session::ArtifactStorageView as View;

pub(crate) fn inspect(store: &InitializerAssemblies) -> HeapCensusReport {
    let mut census = HeapCensus::new("retained_initializer_assemblies");
    store.visit_storage(|view| match view {
        View::Store { buckets, entries } => {
            census.owner("initializer_assemblies.index").observed_items += entries as u64;
            if buckets != 0 {
                census.unknown("initializer_assemblies.index", "private ArtifactStore BTree node backing and Arc control blocks excluded; exposed payload capacities counted separately");
            }
        }
        View::Bucket { address, len, capacity, element_size } => {
            census.buffer("initializer_assemblies.buckets", address, len.saturating_mul(element_size), capacity.saturating_mul(element_size));
        }
        View::Entry { key, reads, versions, value } => {
            census.slice("initializer_assemblies.keys", key, true);
            census.slice("initializer_assemblies.reads", reads, true);
            census.slice("initializer_assemblies.versions", versions, true);
            for read in reads.iter() {
                super::resident_weight::answer(&mut census, &read.answer);
            }
            if census.arc_object("initializer_assemblies.payload", value) {
                let (code, recipes, root_indexes, references) = value.retained_parts();
                census.resolver_code(code);
                census.initializer_fragment_recipes(recipes, references);
                census.vec_payload("initializer_assemblies.root_indexes", root_indexes);
            }
        }
    });
    census.finish()
}
