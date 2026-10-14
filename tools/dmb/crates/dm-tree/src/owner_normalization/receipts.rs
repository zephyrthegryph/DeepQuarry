//! Physical sharing of common parent reads; exact replay remains authoritative.
use super::*;
use dm_session::{Observation, Receipt, ReceiptGroupPool};
type Read = Observation<SourceQuery, SourceAnswer, SourceDomain>;
pub(super) type Pool = ReceiptGroupPool<SourceQuery, SourceAnswer, SourceDomain>;

/// Only branching paths are pooled. Unique local parent reads stay in flat runs,
/// avoiding an extra allocation and control block for every type declaration.
pub(super) fn branching_paths(tree: &SemanticTree) -> HashSet<SymbolId> {
    let mut children = HashMap::<SymbolId, usize>::new();
    for node in tree.types.iter() {
        if let Some(parent) = node.parent {
            *children.entry(tree.types[parent.index()].path).or_default() += 1;
        }
    }
    children
        .into_iter()
        .filter_map(|(path, count)| (count > 1).then_some(path))
        .collect()
}

pub(super) fn share(
    reads: Vec<Read>,
    pool: &Pool,
    branching: &HashSet<SymbolId>,
) -> Receipt<SourceQuery, SourceAnswer, SourceDomain> {
    if !reads
        .iter()
        .any(|read| matches!(read.query, SourceQuery::Parent { path } if branching.contains(&path)))
    {
        return reads.into();
    }
    let mut groups = Vec::<Arc<[Read]>>::new();
    let mut flat = Vec::new();
    for read in reads {
        if matches!(read.query, SourceQuery::Parent { path } if branching.contains(&path)) {
            if !flat.is_empty() {
                groups.push(std::mem::take(&mut flat).into());
            }
            groups.push(pool.intern(vec![read]));
        } else {
            flat.push(read);
        }
    }
    if !flat.is_empty() {
        groups.push(flat.into());
    }
    Receipt::from_groups(groups.into()).expect("canonical ledger order is preserved by splitting")
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn production_normalization_shares_common_parent_observations() {
        use crate::frontend::{
            build_with_executor_and_semantic_state, FrontendConfig, RetainedSemanticTree,
        };
        use std::{collections::BTreeMap, path::Path};
        struct Source;
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &Path) -> Result<String, String> {
                Ok("/datum/base\n/datum/base/a\n    var/first = 1\n/datum/base/b\n    var/second = 2\n/datum/base/c\n    var/third = 3\n".into())
            }
        }
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        let mut state = RetainedSemanticTree::default();
        let _built = build_with_executor_and_semantic_state(
            Path::new("shared_parent.dme"),
            &Source,
            &BTreeMap::new(),
            FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
            None,
            &executor,
            Some(&mut state),
        )
        .unwrap();
        let path = SymbolId::of("/datum/base");
        let mut occurrences = 0;
        let mut backing = HashSet::new();
        state.visit_normalization_storage(|view| {
            if let NormalizationStorageView::Entry { reads, .. } = view {
                reads.visit_storage(|view| {
                    if let dm_session::ReceiptStorageView::Flat(leaf) = view {
                        if leaf.len() == 1 && leaf[0].query == (SourceQuery::Parent { path }) {
                            occurrences += 1;
                            backing.insert(leaf.as_ptr() as usize);
                        }
                    }
                });
            }
        });
        assert!(
            occurrences >= 3,
            "all sibling normalization receipts retain their parent read"
        );
        assert_eq!(
            backing.len(),
            1,
            "equal reads use one actual shared allocation"
        );
    }
    #[test]
    fn shared_parent_leaves_preserve_exact_order_and_changed_answers() {
        let path = SymbolId::of("/datum/base");
        let parent = SymbolId::of("/datum");
        let branching = HashSet::from([path]);
        let pool = Pool::default();
        let read = |answer| Read {
            query: SourceQuery::Parent { path },
            domain: SourceDomain::ParentGraph,
            answer: SourceAnswer::Parent(Some(answer)),
        };
        let original = vec![read(Some(parent))];
        let first = share(original.clone(), &pool, &branching);
        let second = share(original.clone(), &pool, &branching);
        assert_eq!(first.iter().cloned().collect::<Vec<_>>(), original);
        assert_eq!(first, second);
        let leaves = |value: &Receipt<SourceQuery, SourceAnswer, SourceDomain>| {
            let mut leaves = Vec::new();
            value.visit_storage(|view| {
                if let dm_session::ReceiptStorageView::Flat(leaf) = view {
                    leaves.push(Arc::clone(leaf));
                }
            });
            leaves
        };
        assert!(Arc::ptr_eq(&leaves(&first)[0], &leaves(&second)[0]));
        let changed = share(vec![read(None)], &pool, &branching);
        assert_ne!(first, changed);
        assert!(!Arc::ptr_eq(&leaves(&first)[0], &leaves(&changed)[0]));
        let unpooled = share(original, &pool, &HashSet::new());
        assert!(unpooled.flat().is_some());
        assert_eq!(unpooled, first);
    }
}
