//! Opt-in accounting of retained declaration payloads, without decoding them.
use super::*;
use dm_tree::frontend::{DeclarationStorageView, RetainedSemanticTree};

pub(crate) fn inspect(state: &RetainedSemanticTree) -> HeapCensusReport {
    let mut census = HeapCensus::new("retained_declarations");
    if state.declaration_retention_stats().shared_census_scope {
        census.unknown("retained_declarations.scope", "contribution storage is engine-wide across host leases; shared allocations counted once in this census, not per-host retained bytes");
    }
    let mut has_index = false;
    state.visit_occurrence_index_storage(|pointer, _, bytes| {
        has_index = true;
        census.buffer("semantic_occurrence_index", pointer, bytes, bytes);
    });
    if has_index {
        census.unknown(
            "semantic_occurrence_index",
            "private target HashMap bucket backing and shared Arc control blocks excluded",
        );
    }
    super::grammar_roster::inspect(&mut census, state);
    super::metadata_dependencies::inspect(&mut census, state);
    super::retained_normalization::inspect(&mut census, state);
    super::effective_metadata::inspect(&mut census, state);
    super::local_shape::inspect(&mut census, state);
    super::lexical_callable::inspect(&mut census, state);
    super::storage_inventory::inspect(&mut census, state);
    state.visit_declaration_storage(|view| match view {
        DeclarationStorageView::AuthoredLeafRoster { leaves } => {
            let owner = "retained_declarations.authored_leaf_roster";
            if census.vec_payload(owner, leaves) {
                for leaf in leaves {
                    skeleton_leaf(&mut census, owner, leaf);
                }
            }
        }
        DeclarationStorageView::SymbolCatalog { symbols, counts, contributions } => {
            census.symbol_table_storage("retained_declarations.active_symbols", symbols);
            census.owner("retained_declarations.symbol_refcounts").observed_items += counts as u64;
            census.owner("retained_declarations.active_contributions").observed_items += contributions as u64;
            if counts != 0 || contributions != 0 {
                census.unknown("retained_declarations.symbol_catalog", "logical BTree refcount and shared contribution roster entry counts are not allocated-capacity estimates; private BTree backing excluded");
            }
        }
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
        DeclarationStorageView::SharedEntry { key, reads, versions, contribution } => {
            let owner = "retained_declarations.payload";
            census.slice(owner, key, true);
            census.receipt(owner, reads);
            census.slice(owner, versions, true);
            for read in reads.iter() {
                match &read.answer {
                    dm_tree::frontend::ChunkSourceAnswer::Owned(source) => census.arc_text(owner, source),
                    dm_tree::frontend::ChunkSourceAnswer::Live(_) => census.unknown(owner, "live source marker is not a retained owned-source receipt"),
                }
            }
            contribution_payload(&mut census, contribution);
        }
        DeclarationStorageView::Entry { key, reads, versions, contribution } => {
            let owner = "retained_declarations.payload";
            census.arc_text(owner, contribution.source);
            census.slice(owner, key, true);
            census.receipt(owner, reads);
            census.slice(owner, versions, true);
            for read in reads.iter() {
                super::resident_weight::answer(&mut census, &read.answer);
            }
            contribution_payload(&mut census, contribution);
        }
    });
    census.finish()
}

fn contribution_payload(
    census: &mut HeapCensus,
    contribution: dm_tree::frontend::DeclarationContributionView<'_>,
) {
    let owner = "retained_declarations.payload";
    census.arc_text(owner, contribution.source);
    if !census.buffer(
        owner,
        contribution.allocation_address,
        contribution.allocation_size,
        contribution.allocation_size,
    ) {
        return;
    }
    census.relative_syntax(owner, contribution.syntax);
    if census.arc_object(owner, contribution.facts_owner) {
        census.symbol_table_storage(owner, &contribution.facts.symbols);
        census.unknown(owner, "private symbol HashMap buckets and shared Arc control blocks are not exposed; all spelling owners are counted");
        if census.vec_payload(owner, &contribution.facts.origins) {
            for origin in &contribution.facts.origins {
                census.slice(owner, &origin.expansion_stack, true);
            }
        }
    }
    skeleton_leaf(census, owner, contribution.skeletons);
    contribution.visit_allocation_storage(|address, len, bytes| {
        census.owner(owner).observed_items += len as u64;
        census.buffer(owner, address, bytes, bytes);
    });
}

fn skeleton_leaf(
    census: &mut HeapCensus,
    owner: &'static str,
    leaf: &std::sync::Arc<Vec<dm_tree::Skeleton>>,
) {
    if census.arc_object(owner, leaf) && census.vec_payload(owner, leaf.as_ref()) {
        for skeleton in leaf.iter() {
            if let dm_tree::Skeleton::Member { metadata, .. } = skeleton {
                if census.arc_object(owner, metadata) {
                    census.declaration(metadata);
                }
            }
        }
    }
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
        let host = crate::runner_host::BuildHost::default();
        let memo = host
            .expansion_memo(None)
            .expect("retained host enables expansion receipts");
        let frontend = dm_tree::frontend::build_with_executor_and_semantic_state(
            Path::new("census.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
            Some(&memo),
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
            .any(|owner| owner.owner == "retained_grammar.descriptors"
                && owner.unique_known_capacity_bytes > 0));
        assert!(
            first
                .owners
                .iter()
                .any(|owner| owner.owner == "retained_grammar.expansions"
                    && !owner.unknown.is_empty())
        );
        assert!(first.owners.iter().any(|owner| owner.owner
            == "retained_normalization.current_roster"
            && owner.unique_known_capacity_bytes > 0));
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
