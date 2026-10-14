use super::*;
/// Issued scalar outcomes without historical occurrence or source-binding ownership.
#[derive(Clone, Debug)]
pub struct ScalarFacts {
    domain: ScalarDomain,
    requested: Arc<[ScalarQuery]>,
    dependencies: Arc<BTreeMap<ScalarQuery, Arc<[ScalarQuery]>>>,
    predefined_reads: Arc<BTreeMap<SymbolId, PredefinedOutcome>>,
}
impl ScalarFacts {
    /// Only the exact immutable declaration allocation can reissue these answers.
    pub fn bind_current(&self, source: &TreeSnapshot) -> Option<ScalarSnapshot> {
        if !Arc::ptr_eq(&self.domain.source, &source.tree)
            || source.occurrences.tree_identity() != source.tree.identity()
        {
            return None;
        }
        Some(ScalarSnapshot {
            issued_domain: self.domain.clone(),
            source: source.clone(),
            identity: self.domain.identity,
            backend_identity: self.domain.backend,
            requested: Arc::clone(&self.requested),
            outcomes: Arc::clone(&self.domain.outcomes),
            dependencies: Arc::clone(&self.dependencies),
            predefined_reads: Arc::clone(&self.predefined_reads),
        })
    }
    pub fn outcomes(&self) -> &Arc<BTreeMap<ScalarQuery, ScalarOutcome>> {
        &self.domain.outcomes
    }
    pub fn dependencies(&self) -> &Arc<BTreeMap<ScalarQuery, Arc<[ScalarQuery]>>> {
        &self.dependencies
    }
    pub fn predefined_reads(&self) -> &Arc<BTreeMap<SymbolId, PredefinedOutcome>> {
        &self.predefined_reads
    }
}
impl ScalarFacts {
    /// Issued process-local receipts; map node overhead is not exposed.
    pub fn certificates(&self) -> &Arc<BTreeMap<ScalarQuery, u64>> {
        &self.domain.certificates
    }
    pub fn requested(&self) -> &Arc<[ScalarQuery]> {
        &self.requested
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn scalar_facts_rebind_current_occurrences_and_reject_public_projection_changes() {
        let source = super::super::tests::snapshot("/datum/a\n    var/const/value = 3\n");
        let query = ScalarQuery::Const {
            owner: SymbolId::of("/datum/a"),
            name: SymbolId::of("value"),
        };
        let original = resolve(&source, &[query], &super::super::tests::backend_disabled());
        let facts = original.retain_facts().unwrap();
        let current = TreeSnapshot {
            tree: Arc::clone(&source.tree),
            occurrences: Arc::new((*source.occurrences).clone()),
        };
        let rebound = facts.bind_current(&current).unwrap();
        assert!(Arc::ptr_eq(
            &rebound.source.occurrences,
            &current.occurrences
        ));
        assert!(!Arc::ptr_eq(
            &rebound.source.occurrences,
            &original.source.occurrences
        ));
        assert!(Arc::ptr_eq(&rebound.outcomes, &original.outcomes));
        assert_eq!(rebound.identity, original.identity);
        assert_eq!(
            rebound.resolve(ResolveQuery::Constant {
                owner: SymbolId::of("/datum/a"),
                name: SymbolId::of("value")
            }),
            original.resolve(ResolveQuery::Constant {
                owner: SymbolId::of("/datum/a"),
                name: SymbolId::of("value")
            })
        );
        let independent = super::super::tests::snapshot("/datum/a\n    var/const/value = 3\n");
        assert!(facts.bind_current(&independent).is_none());
        let mut changed = original.clone();
        changed.dependencies = Arc::new(BTreeMap::new());
        assert!(changed.retain_facts().is_none());
        let mut changed = original.clone();
        changed.requested = Arc::from([]);
        assert!(changed.retain_facts().is_none());
        let mut changed = original;
        changed.predefined_reads = Arc::new(BTreeMap::new());
        assert!(changed.retain_facts().is_none());
    }
}

impl ScalarSnapshot {
    /// Refuse public projections whose issued immutable authority was replaced.
    pub fn retain_facts(&self) -> Option<ScalarFacts> {
        self.domain_version(dm_ir::ReadDomain::Tree)?;
        if !Arc::ptr_eq(&self.requested, &self.issued_domain.requested)
            || !Arc::ptr_eq(&self.dependencies, &self.issued_domain.dependencies)
            || !Arc::ptr_eq(&self.predefined_reads, &self.issued_domain.predefined_reads)
        {
            return None;
        }
        Some(ScalarFacts {
            domain: self.issued_domain.clone(),
            requested: Arc::clone(&self.requested),
            dependencies: Arc::clone(&self.dependencies),
            predefined_reads: Arc::clone(&self.predefined_reads),
        })
    }
}
