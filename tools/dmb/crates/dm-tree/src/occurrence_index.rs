//! Immutable target grouping; source provenance always belongs to this request.
use super::*;

#[derive(Debug)]
pub(crate) struct TargetOccurrenceIndex {
    targets: Arc<[Target]>,
    groups: HashMap<Target, Arc<[OccurrenceId]>>,
}
impl TargetOccurrenceIndex {
    fn capture(tree: &SemanticTree) -> Arc<Self> {
        let mut groups: HashMap<Target, Vec<OccurrenceId>> = HashMap::new();
        for (ordinal, target) in tree.declarations().iter().copied().enumerate() {
            groups
                .entry(target)
                .or_default()
                .push(OccurrenceId(ordinal as u32));
        }
        Arc::new(Self {
            targets: Arc::clone(&tree.declaration_targets),
            groups: groups
                .into_iter()
                .map(|(target, ids)| (target, ids.into()))
                .collect(),
        })
    }
    fn admits(&self, tree: &SemanticTree) -> bool {
        // The same immutable roster is exact; other rosters require value equality.
        // A semantic hash or tree identity is insufficient for admission.
        Arc::ptr_eq(&self.targets, &tree.declaration_targets)
            || self.targets.as_ref() == tree.declarations()
    }
    pub(crate) fn visit_storage(index: &Arc<Self>, visit: &mut dyn FnMut(usize, usize, usize)) {
        visit(Arc::as_ptr(index) as usize, 1, std::mem::size_of::<Self>());
        visit(
            index.targets.as_ptr() as usize,
            index.targets.len(),
            std::mem::size_of_val(index.targets.as_ref()),
        );
        for ids in index.groups.values() {
            visit(
                ids.as_ptr() as usize,
                ids.len(),
                std::mem::size_of_val(ids.as_ref()),
            );
        }
    }
}
impl OccurrenceTable {
    pub fn build(
        tree: &SemanticTree,
        origins: Vec<Provenance>,
    ) -> Result<Self, OccurrenceCountMismatch> {
        Self::build_with_index(tree, origins, None)
    }
    pub(crate) fn build_with_index(
        tree: &SemanticTree,
        origins: Vec<Provenance>,
        prior: Option<&Arc<TargetOccurrenceIndex>>,
    ) -> Result<Self, OccurrenceCountMismatch> {
        if origins.len() != tree.declarations().len() {
            return Err(OccurrenceCountMismatch {
                declarations: tree.declarations().len(),
                origins: origins.len(),
            });
        }
        let index = prior
            .filter(|index| index.admits(tree))
            .map_or_else(|| TargetOccurrenceIndex::capture(tree), Arc::clone);
        let occurrences = tree
            .declarations()
            .iter()
            .copied()
            .zip(origins)
            .map(|(target, provenance)| Occurrence { target, provenance })
            .collect::<Vec<_>>();
        Ok(Self {
            tree_identity: tree.identity(),
            occurrences: occurrences.into(),
            index,
        })
    }
    pub(crate) fn target_index(&self) -> Arc<TargetOccurrenceIndex> {
        Arc::clone(&self.index)
    }
    /// Actual shared allocations only; private HashMap bucket backing excluded.
    pub fn visit_target_index_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        TargetOccurrenceIndex::visit_storage(&self.index, &mut visit);
    }
    pub fn tree_identity(&self) -> u128 {
        self.tree_identity
    }
    pub fn source_order(&self) -> &[Occurrence] {
        &self.occurrences
    }
    pub fn get(&self, id: OccurrenceId) -> Option<&Occurrence> {
        self.occurrences.get(id.0 as usize)
    }
    pub fn for_target(&self, target: Target) -> &[OccurrenceId] {
        self.index
            .groups
            .get(&target)
            .map(AsRef::as_ref)
            .unwrap_or(&[])
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn tree() -> SemanticTree {
        let mut symbols = dm_ir::SymbolTable::default();
        symbols.intern("/").unwrap();
        let a = symbols.intern("/a").unwrap();
        let b = symbols.intern("/b").unwrap();
        crate::build(
            symbols,
            &[
                Skeleton::Type {
                    path: a,
                    explicit_parent: None,
                },
                Skeleton::Type {
                    path: a,
                    explicit_parent: None,
                },
                Skeleton::Type {
                    path: b,
                    explicit_parent: None,
                },
            ],
        )
        .unwrap()
    }
    fn origins(tree: &SemanticTree, shift: u32) -> Vec<Provenance> {
        (0..tree.declarations().len())
            .map(|i| Provenance {
                span: dm_ir::Span {
                    file: dm_ir::FileId(shift),
                    start: shift + i as u32,
                    end: shift + i as u32 + 1,
                },
                include_occurrence: shift,
                region: shift as u128,
                expansion_stack: Arc::from([]),
            })
            .collect()
    }
    #[test]
    fn unchanged_targets_share_index_but_issue_fresh_provenance() {
        let tree = tree();
        let first = OccurrenceTable::build(&tree, origins(&tree, 0)).unwrap();
        let current =
            OccurrenceTable::build_with_index(&tree, origins(&tree, 80), Some(&first.index))
                .unwrap();
        assert!(Arc::ptr_eq(&first.index, &current.index));
        assert!(!Arc::ptr_eq(&first.occurrences, &current.occurrences));
        let target = tree.declarations()[0];
        assert_eq!(
            current.for_target(target),
            &[OccurrenceId(0), OccurrenceId(1)]
        );
        assert_eq!(first.get(OccurrenceId(0)).unwrap().provenance.span.start, 0);
        assert_eq!(
            current.get(OccurrenceId(0)).unwrap().provenance.span.start,
            80
        );
        assert_eq!(
            current
                .get(OccurrenceId(0))
                .unwrap()
                .provenance
                .include_occurrence,
            80
        );
        assert!(OccurrenceTable::build_with_index(&tree, Vec::new(), Some(&first.index)).is_err());
    }
    #[test]
    fn changed_target_roster_rebuilds_exact_grouping_even_with_same_tree_identity() {
        let tree = tree();
        let first = OccurrenceTable::build(&tree, origins(&tree, 0)).unwrap();
        let mut changed = tree.clone();
        let mut targets = changed.declarations().to_vec();
        targets.reverse();
        changed.declaration_targets = targets.into();
        let current =
            OccurrenceTable::build_with_index(&changed, origins(&changed, 1), Some(&first.index))
                .unwrap();
        assert!(!Arc::ptr_eq(&first.index, &current.index));
        let expected = OccurrenceTable::build(&changed, origins(&changed, 1)).unwrap();
        for target in changed.declarations() {
            assert_eq!(current.for_target(*target), expected.for_target(*target));
        }
    }
}
