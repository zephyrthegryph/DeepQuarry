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
    pub(crate) writes: Vec<InitializerWrite>,
    pub(crate) facts: Vec<Fact>,
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
pub(crate) struct PreparedKeys {
    values: ObservedArtifactStore<Vec<Arc<[u8]>>, (), Arc<Inputs>, ()>,
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
        let current = Current(Arc::new(Inputs {
            writes: writes.to_vec(),
            facts: facts.iter().copied().map(Fact::from).collect(),
            policy: reuse.policy,
            factory_policy,
            resource_context: reuse.resource_search_context,
        }));
        let locator = b"initializer-prepared-keys-v1";
        if let Some(keys) = self.values.lookup(locator, &current) {
            return Some(keys);
        }
        let ledger = ObservationLedger::default();
        ledger.record((), current.answer(&()), (), None);
        self.values.retain_current_keys([locator.as_slice()]);
        self.values.insert_with_owned(
            Arc::from(locator.as_slice()),
            ledger.reads(),
            ledger.domain_receipts(),
            0,
            || {
                writes
                    .iter()
                    .zip(facts)
                    .map(|(write, &fact)| {
                        Arc::from(artifact::key(write, fact, reuse, factory_policy))
                    })
                    .collect()
            },
        )
    }
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(
            dm_session::ObservedArtifactStorageView<'_, Vec<Arc<[u8]>>, (), Arc<Inputs>, ()>,
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
        assert!(Arc::ptr_eq(&first, &same));
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
            assert!(!Arc::ptr_eq(&first, &changed));
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
        assert_eq!(ordered[0], reversed[1]);
        assert_eq!(ordered[1], reversed[0]);
        assert!(!Arc::ptr_eq(&ordered, &reversed));
        assert!(owner.prepare(&writes, &[], reuse, 11).is_none());
        owner.clear();
    }
}
