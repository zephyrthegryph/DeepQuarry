//! Current producer-issued startup allocation order. Symbolic IDs identify keys;
//! their numeric values never determine allocation order.
use dm_ir::{InitializerTarget, InitializerWrite, SymbolId};
use dm_link::Key;
use dm_tree::initializers::InitializerPlan;
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

pub(crate) struct StartupAllocationRoster {
    writes: Arc<[InitializerWrite]>,
    keys: Vec<Key>,
    ranks: BTreeMap<Key, usize>,
}
impl StartupAllocationRoster {
    /// `source_owners` is the existing admitted fresh type allocation roster;
    /// retained engine owners are deliberately absent from this first partition.
    pub(crate) fn issue(
        plan: &InitializerPlan,
        source_owners: &[SymbolId],
    ) -> Result<Self, String> {
        let root = SymbolId::of("/");
        let mut owners = BTreeMap::new();
        for (rank, owner) in source_owners.iter().copied().enumerate() {
            if owner == root || owners.insert(owner, rank).is_some() {
                return Err("startup source allocation roster is not unique".into());
            }
        }
        let mut entries = Vec::new();
        let mut seen = BTreeSet::new();
        for (ordinal, write) in plan.writes.iter().enumerate() {
            let (owner, key, shared) = match write.target {
                InitializerTarget::Shared { owner, name, .. } => {
                    (owner, Key::Variable { owner, name }, true)
                }
                InitializerTarget::ProcedureStatic(identity) => (
                    identity.procedure.owner,
                    Key::ProcedureStatic(identity),
                    false,
                ),
                InitializerTarget::Instance { .. } => continue,
            };
            if !seen.insert(key) {
                continue;
            }
            let group = if let Some(rank) = owners.get(&owner) {
                *rank
            } else if shared && owner == root {
                owners.len()
            } else {
                owners.len() + 1
            };
            entries.push((group, ordinal, key));
        }
        entries.sort_by_key(|(group, ordinal, _)| (*group, *ordinal));
        let keys: Vec<_> = entries.into_iter().map(|(_, _, key)| key).collect();
        let ranks = keys
            .iter()
            .copied()
            .enumerate()
            .map(|(rank, key)| (key, rank))
            .collect();
        Ok(Self {
            writes: Arc::clone(&plan.writes),
            keys,
            ranks,
        })
    }
    pub(crate) fn order_runtime(
        &self,
        plan: &InitializerPlan,
        classified: &mut crate::initializer_policy::ClassifiedInitializers,
    ) -> Result<(), String> {
        if !Arc::ptr_eq(&self.writes, &plan.writes) && self.writes.as_ref() != plan.writes.as_ref()
        {
            return Err("startup allocation roster differs from current initializer writes".into());
        }
        for group in &mut classified.groups {
            if group.receiver.is_some() {
                continue;
            }
            for index in &group.writes {
                if !self
                    .ranks
                    .contains_key(&key(&classified.writes[*index].write)?)
                {
                    return Err("startup allocation roster omits executable write".into());
                }
            }
            // Existing literal allocation phase remains first. Within each phase,
            // the same current allocation producer controls execution and footer order.
            group.writes.sort_by_key(|index| {
                let write = &classified.writes[*index];
                (
                    write.phase == Some(crate::initializer_policy::Phase::Runtime),
                    self.ranks[&key(&write.write).unwrap()],
                )
            });
        }
        Ok(())
    }
    pub(crate) fn order_membership(&self, current: &mut Arc<[Key]>) -> Result<(), String> {
        let requested: BTreeSet<_> = current.iter().copied().collect();
        let ordered: Vec<_> = self
            .keys
            .iter()
            .copied()
            .filter(|key| requested.contains(key))
            .collect();
        if ordered.len() != current.len() {
            return Err("startup allocation roster omits current variable membership".into());
        }
        *current = ordered.into();
        Ok(())
    }
}
fn key(write: &InitializerWrite) -> Result<Key, String> {
    match write.target {
        InitializerTarget::Shared { owner, name, .. } => Ok(Key::Variable { owner, name }),
        InitializerTarget::ProcedureStatic(identity) => Ok(Key::ProcedureStatic(identity)),
        InitializerTarget::Instance { .. } => {
            Err("instance write in startup allocation roster".into())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/var/global/root_first = 1\n/datum/empty\n/datum/later\n/datum/later/var/static/later_first = 2\n/var/global/root_second = 3\n/datum/empty/var/static/empty_late = 4\n".into())
        }
    }
    #[test]
    fn source_owner_allocation_precedes_root_even_when_root_is_declared_first() {
        let frontend = dm_tree::frontend::build_with_config(
            std::path::Path::new("probe.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
        )
        .unwrap();
        let declarations = dm_tree::initializers::capture_declaration_plan(
            &frontend.snapshot,
            &frontend.emission_order,
        )
        .unwrap();
        let plan = declarations.plan();
        let roster = StartupAllocationRoster::issue(
            plan,
            &[SymbolId::of("/datum/empty"), SymbolId::of("/datum/later")],
        )
        .unwrap();
        let mut membership: Arc<[Key]> = plan
            .writes
            .iter()
            .map(key)
            .collect::<Result<Vec<_>, _>>()
            .unwrap()
            .into();
        roster.order_membership(&mut membership).unwrap();
        let names: Vec<_> = membership
            .iter()
            .map(|key| match key {
                Key::Variable { name, .. } => plan.symbols.text(*name).unwrap(),
                _ => panic!("unexpected procedure static"),
            })
            .collect();
        assert_eq!(
            names,
            ["empty_late", "later_first", "root_first", "root_second"]
        );
        assert!(StartupAllocationRoster::issue(
            plan,
            &[SymbolId::of("/datum/empty"), SymbolId::of("/datum/empty")]
        )
        .is_err());
        let mut omitted = membership.to_vec();
        omitted.push(Key::Variable {
            owner: SymbolId::of("/"),
            name: SymbolId::of("unissued"),
        });
        assert!(roster.order_membership(&mut omitted.into()).is_err());
    }
}
