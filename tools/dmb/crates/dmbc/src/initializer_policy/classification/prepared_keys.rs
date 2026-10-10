//! Reuse canonical key buffers only after exact current producer-input replay.
//! This does not authorize a classified result or replace its resolver ledger.
use super::artifact::{self, InitializerReuse};
use super::*;
use dm_session::{ObservationHost, ObservationLedger, ObservedArtifactStore};

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum Fact {
    Header(&'static str),
    Known(u32),
    MutableInstance,
}
impl From<ModifierFact> for Fact {
    fn from(value: ModifierFact) -> Self {
        match value {
            ModifierFact::Header(domain) => Self::Header(domain.label()),
            ModifierFact::Known(flags) => Self::Known(flags),
            ModifierFact::MutableInstance => Self::MutableInstance,
        }
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Inputs {
    pub(crate) write: InitializerWrite,
    fact: Fact,
    policy: u128,
    factory_policy: u128,
    resource_context: Option<u128>,
}
struct Current(Arc<Inputs>);
impl ObservationHost<(), Arc<Inputs>, ()> for Current {
    fn answer(&self, _: &()) -> Arc<Inputs> {
        Arc::clone(&self.0)
    }
}
pub(crate) struct PreparedKey {
    pub(crate) bytes: Arc<[u8]>,
}
pub(crate) struct PreparedKeys {
    values: ObservedArtifactStore<PreparedKey, (), Arc<Inputs>, ()>,
}
impl Default for PreparedKeys {
    fn default() -> Self {
        Self {
            values: ObservedArtifactStore::current_revision(),
        }
    }
}
impl PreparedKeys {
    pub(super) fn clear(&self) {
        self.values.retain_current_keys(std::iter::empty::<&[u8]>());
    }
    pub(super) fn prepare(
        &self,
        writes: &[InitializerWrite],
        facts: &[ModifierFact],
        reuse: InitializerReuse<'_>,
        factory_policy: u128,
    ) -> Option<Arc<Vec<Arc<[u8]>>>> {
        if writes.len() != facts.len() {
            return None;
        }
        let mut duplicates = std::collections::HashMap::<Vec<u8>, usize>::new();
        let mut locators = Vec::with_capacity(writes.len());
        let mut keys = Vec::with_capacity(writes.len());
        for (write, &fact) in writes.iter().zip(facts) {
            let mut locator = b"initializer-prepared-write-v1".to_vec();
            locator.push(u8::from(
                write.source_site == dm_ir::InitializerSite::Declaration,
            ));
            locator.extend_from_slice(&crate::initializer_lowering::receipts::fragment_locator(
                write,
            ));
            let duplicate = duplicates.entry(locator.clone()).or_default();
            locator.extend_from_slice(&(*duplicate as u128).to_le_bytes());
            *duplicate += 1;
            let current = Current(Arc::new(Inputs {
                write: write.clone(),
                fact: fact.into(),
                policy: reuse.policy,
                factory_policy,
                resource_context: reuse.resource_search_context,
            }));
            let admitted = self.values.lookup(&locator, &current).or_else(|| {
                let ledger = ObservationLedger::default();
                ledger.record((), current.answer(&()), (), None);
                self.values.insert_with_owned(
                    Arc::from(locator.as_slice()),
                    ledger.reads(),
                    ledger.domain_receipts(),
                    0,
                    || PreparedKey {
                        bytes: artifact::key(write, fact, reuse, factory_policy).into(),
                    },
                )
            })?;
            keys.push(Arc::clone(&admitted.bytes));
            locators.push(locator);
        }
        // Prune only after the entire current ordered roster is admitted.
        self.values
            .retain_current_keys(locators.iter().map(Vec::as_slice));
        Some(Arc::new(keys))
    }

    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(
            dm_session::ObservedArtifactStorageView<'_, PreparedKey, (), Arc<Inputs>, ()>,
        ),
    ) {
        self.values.visit_storage(visitor);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn prepared_keys_reuse_only_exact_complete_producer_inputs() {
        struct Host;
        impl dm_ir::Resolver for Host {
            fn resolve(&self, _: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
                dm_ir::ResolvedMeaning::Missing
            }
        }
        let artifacts = artifact::InitializerArtifacts::default();
        assert!(artifacts.prepared_keys.is_some());
        assert!(artifact::InitializerArtifacts::with_limit(1024)
            .prepared_keys
            .is_none());
        let owner = PreparedKeys::default();
        let host = Host;
        let reuse = InitializerReuse {
            store: &artifacts,
            resolver: &host,
            policy: 7,
            resource_search_context: Some(9),
        };
        let mut symbols = SymbolTable::default();
        let root = symbols.intern("/").unwrap();
        let name = symbols.intern("output").unwrap();
        let write = InitializerWrite {
            source_site: dm_ir::InitializerSite::Declaration,
            target: InitializerTarget::Shared {
                slot: name,
                owner: root,
                name,
            },
            lexical_owner: root,
            lexical_procedure: None,
            value: InitializerValue::Expression(
                crate::initializer_policy::expression("1 + 2", &mut symbols).unwrap(),
            ),
            declared_array: None,
            declaration_flags: Some(8),
        };
        let writes = [write.clone()];
        let facts = [ModifierFact::Known(8)];
        let first = owner.prepare(&writes, &facts, reuse, 11).unwrap();
        assert_eq!(
            first[0].as_ref(),
            artifact::key(&write, facts[0], reuse, 11)
        );
        let same = owner.prepare(&writes, &facts, reuse, 11).unwrap();
        assert!(Arc::ptr_eq(&first[0], &same[0]));
        for (facts, policy, context, factory) in [
            ([ModifierFact::Known(10)], 7, Some(9), 11),
            (facts, 8, Some(9), 11),
            (facts, 7, None, 11),
            (facts, 7, Some(9), 12),
        ] {
            let changed = owner
                .prepare(
                    &writes,
                    &facts,
                    InitializerReuse {
                        policy,
                        resource_search_context: context,
                        ..reuse
                    },
                    factory,
                )
                .unwrap();
            assert!(!Arc::ptr_eq(&first[0], &changed[0]));
        }
        let mut changed_write = write;
        changed_write.value = InitializerValue::Expression(
            crate::initializer_policy::expression("1 + 3", &mut symbols).unwrap(),
        );
        let changed = owner.prepare(&[changed_write], &facts, reuse, 11).unwrap();
        assert_ne!(first[0], changed[0]);
        let mut sibling = writes[0].clone();
        sibling.lexical_owner = SymbolId::of("/datum/sibling");
        let ordered = owner
            .prepare(
                &[writes[0].clone(), sibling.clone()],
                &[facts[0], facts[0]],
                reuse,
                11,
            )
            .unwrap();
        let reversed = owner
            .prepare(
                &[sibling, writes[0].clone()],
                &[facts[0], facts[0]],
                reuse,
                11,
            )
            .unwrap();
        assert!(Arc::ptr_eq(&ordered[0], &reversed[1]));
        assert!(Arc::ptr_eq(&ordered[1], &reversed[0]));
        assert_eq!(ordered[0], reversed[1]);
        assert_eq!(ordered[1], reversed[0]);
        assert!(!Arc::ptr_eq(&ordered, &reversed));
        let mut edited = writes[0].clone();
        edited.lexical_owner = SymbolId::of("/datum/sibling");
        edited.value = InitializerValue::Expression(
            crate::initializer_policy::expression("9 + 3", &mut symbols).unwrap(),
        );
        let default_edit = owner
            .prepare(
                &[edited.clone(), writes[0].clone()],
                &[facts[0], facts[0]],
                reuse,
                11,
            )
            .unwrap();
        assert!(Arc::ptr_eq(&reversed[1], &default_edit[1]));
        assert!(!Arc::ptr_eq(&reversed[0], &default_edit[0]));
        // An unrelated earlier write has a separate local duplicate namespace.
        let mut earlier = writes[0].clone();
        earlier.lexical_owner = SymbolId::of("/datum/earlier");
        let inserted = owner
            .prepare(
                &[earlier, edited, writes[0].clone()],
                &[facts[0], facts[0], facts[0]],
                reuse,
                11,
            )
            .unwrap();
        assert!(Arc::ptr_eq(&default_edit[0], &inserted[1]));
        assert!(Arc::ptr_eq(&default_edit[1], &inserted[2]));
        let single = owner.prepare(&writes, &facts, reuse, 11).unwrap();
        assert!(Arc::ptr_eq(&inserted[2], &single[0]));
        let mut entries = 0;
        owner.visit_storage(|view| {
            if matches!(view, dm_session::ObservedArtifactStorageView::Entry { .. }) {
                entries += 1;
            }
        });
        assert_eq!(entries, 1, "deleted placement candidates must be pruned");
        // Same-target duplicates retain separate exact fact answers.
        let duplicates = owner
            .prepare(
                &[writes[0].clone(), writes[0].clone()],
                &[facts[0], ModifierFact::Known(10)],
                reuse,
                11,
            )
            .unwrap();
        assert_ne!(duplicates[0], duplicates[1]);
        let swapped = owner
            .prepare(
                &[writes[0].clone(), writes[0].clone()],
                &[ModifierFact::Known(10), facts[0]],
                reuse,
                11,
            )
            .unwrap();
        assert_eq!(duplicates[0], swapped[1]);
        assert_eq!(duplicates[1], swapped[0]);
        assert!(!Arc::ptr_eq(&duplicates[0], &swapped[0]));
        for (index, fact) in [ModifierFact::Known(10), facts[0]].into_iter().enumerate() {
            assert_eq!(
                swapped[index].as_ref(),
                artifact::key(&writes[0], fact, reuse, 11)
            );
        }
        assert!(owner.prepare(&writes, &[], reuse, 11).is_none());
        owner.clear();
    }
}
