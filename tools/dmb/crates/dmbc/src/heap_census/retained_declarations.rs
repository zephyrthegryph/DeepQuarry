//! Opt-in accounting of retained declaration payloads, without decoding them.
use super::*;
use dm_tree::frontend::{DeclarationStorageView, RetainedSemanticTree};

pub(crate) fn inspect(state: &RetainedSemanticTree) -> HeapCensusReport {
    let mut census = HeapCensus::new("retained_declarations");
    super::metadata_dependencies::inspect(&mut census, state);
    state.visit_declaration_storage(|view| match view {
        DeclarationStorageView::Store { buckets, entries } => {
            census.owner("retained_declarations.index").observed_items += entries as u64;
            if buckets != 0 {
                census.unknown("retained_declarations.index", "private BTree node backing and Arc control blocks are not exposed; payload capacities are counted independently");
            }
        }
        DeclarationStorageView::Bucket { address, len, capacity, element_size } => {
            census.buffer("retained_declarations.buckets", address,
                len.saturating_mul(element_size), capacity.saturating_mul(element_size));
        }
        DeclarationStorageView::Entry { key, reads, versions, contribution } => {
            let owner = "retained_declarations.payload";
            census.slice(owner, key, true);
            census.slice(owner, reads, true);
            census.slice(owner, versions, true);
            for read in reads.iter() {
                super::resident_weight::answer(&mut census, &read.answer);
            }
            if !census.buffer(owner, contribution.allocation_address,
                contribution.allocation_size, contribution.allocation_size) {
                return;
            }
            census.items(owner, contribution.items);
            census.symbol_table_storage(owner, &contribution.facts.symbols);
            census.unknown(owner, "private symbol HashMap buckets and shared Arc control blocks are not exposed; all spelling owners are counted");
            if census.vec_payload(owner, &contribution.facts.skeletons) {
                for skeleton in &contribution.facts.skeletons {
                    if let dm_tree::Skeleton::Member { metadata, .. } = skeleton {
                        if census.arc_object(owner, metadata) {
                            census.declaration(metadata);
                        }
                    }
                }
            }
            if census.vec_payload(owner, &contribution.facts.origins) {
                for origin in &contribution.facts.origins {
                    census.slice(owner, &origin.expansion_stack, true);
                }
            }
            contribution.ledger.events.visit_storage(|address, len, bytes| {
                census.owner(owner).observed_items += len as u64;
                census.buffer(owner, address, bytes, bytes);
            });
        }
    });
    census.finish()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/obj/base\n    var/list/items = list(1,2)\n/proc/p(x=1)\n    set name = \"Display\"\n    return x\n".into())
        }
    }
    #[test]
    fn retained_declaration_census_visits_payloads_without_mutating_or_serializing() {
        let mut state = RetainedSemanticTree::new();
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        let frontend = dm_tree::frontend::build_with_executor_and_semantic_state(
            Path::new("census.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
            None,
            &executor,
            Some(&mut state),
        )
        .unwrap();
        let before = state.declaration_retention_stats();
        let first = inspect(&state);
        let second = inspect(&state);
        assert!(first.unique_known_capacity_bytes > 0);
        assert!(first
            .owners
            .iter()
            .any(|owner| owner.owner == "retained_metadata_dependencies"
                && owner.unique_known_capacity_bytes > 0
                && owner.unknown.is_empty()));
        assert_eq!(
            first.unique_known_capacity_bytes,
            second.unique_known_capacity_bytes
        );
        assert_eq!(before.hits, state.declaration_retention_stats().hits);
        assert_eq!(
            before.current_keys,
            state.declaration_retention_stats().current_keys
        );
        assert!(first.owners.iter().any(
            |owner| owner.owner == "semantic_metadata" && owner.unique_known_capacity_bytes > 0
        ));
        assert!(
            first
                .owners
                .iter()
                .any(|owner| owner.owner == "retained_declarations.index"
                    && !owner.unknown.is_empty())
        );
        drop(frontend);
        state.clear();
        assert_eq!(inspect(&state).unique_known_capacity_bytes, 0);
    }
}
