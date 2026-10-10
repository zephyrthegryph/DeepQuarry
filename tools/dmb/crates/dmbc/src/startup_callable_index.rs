//! One current callable index, observed against the issued frontend roster.
use crate::{driver_facts, lowering::UnitIdentity};
use dm_tree::{
    frontend::{CallableRoster, ColdFrontend},
    MemberId,
};
use std::{collections::BTreeMap, sync::Arc};
type Index = BTreeMap<UnitIdentity, MemberId>;
pub(super) struct CallableIndex {
    values: dm_session::ObservedArtifactStore<Arc<Index>, (), Arc<CallableRoster>, ()>,
}
impl Default for CallableIndex {
    fn default() -> Self {
        Self {
            values: dm_session::ObservedArtifactStore::current_revision(),
        }
    }
}
struct Host(Arc<CallableRoster>);
impl dm_session::observations::ObservationHost<(), Arc<CallableRoster>, ()> for Host {
    fn answer(&self, _: &()) -> Arc<CallableRoster> {
        Arc::clone(&self.0)
    }
}
impl CallableIndex {
    pub(super) fn clear(&self) {
        self.values.retain_current_keys(std::iter::empty::<&[u8]>());
    }

    pub(super) fn retain_tree(&self, tree: Option<&Arc<dm_tree::SemanticTree>>) {
        let mut foreign = false;
        self.values.visit_storage(|view| {
            if let dm_session::ObservedArtifactStorageView::Entry { reads, .. } = view {
                foreign |= reads
                    .iter()
                    .any(|read| tree.is_none_or(|tree| !read.answer.authenticates_tree(tree)));
            }
        });
        // Drop the visitor's store lock before pruning. Lifecycle callers hold
        // the session host exclusively; no request can install a new entry.
        if foreign {
            self.clear();
        }
    }
    pub(super) fn get(&self, frontend: &ColdFrontend) -> Result<Arc<Index>, String> {
        let roster = Arc::clone(frontend.callable_roster()?);
        let host = Host(roster);
        let key: Arc<[u8]> = Arc::from(b"startup-issued-callable-index-v1".as_slice());
        if let Some(index) = self.values.lookup(&key, &host) {
            return Ok(Arc::clone(index.as_ref()));
        }
        let value =
            Arc::new(driver_facts::unit_members(frontend).map_err(|error| error.to_string())?);
        let ledger = dm_session::observations::ObservationLedger::default();
        ledger.record((), Arc::clone(&host.0), (), None);
        // One fixed key replaces the previous current roster; no edit history.
        self.values.retain_current_keys([key.as_ref()]);
        self.values
            .insert_with_owned(key, ledger.reads(), ledger.domain_receipts(), 0, || {
                Arc::clone(&value)
            })
            .map(|owner| Arc::clone(owner.as_ref()))
            .map_or_else(|| Ok(value), Ok)
    }
    pub(super) fn visit_storage(
        &self,
        visitor: impl FnMut(
            dm_session::ObservedArtifactStorageView<'_, Arc<Index>, (), Arc<CallableRoster>, ()>,
        ),
    ) {
        self.values.visit_storage(visitor);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    fn frontend(
        state: &mut dm_tree::frontend::RetainedSemanticTree,
        source: &'static str,
    ) -> ColdFrontend {
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        dm_tree::frontend::build_with_executor_and_semantic_state(
            Path::new("index.dme"),
            &Source(source),
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
            None,
            &executor,
            Some(state),
        )
        .unwrap()
    }
    #[test]
    fn current_callable_index_reuses_body_edits_and_replaces_changed_roster() {
        let mut state = dm_tree::frontend::RetainedSemanticTree::default();
        let store = CallableIndex::default();
        let old = frontend(&mut state, "/proc/p()\n    return 1\n");
        let first = store.get(&old).unwrap();
        let current = frontend(&mut state, "// shift\n/proc/p()\n    return 2\n");
        let second = store.get(&current).unwrap();
        assert!(Arc::ptr_eq(&first, &second));
        assert_eq!(
            first.as_ref(),
            &driver_facts::unit_members(&current).unwrap()
        );
        let changed = frontend(
            &mut state,
            "/proc/p()\n    return 2\n/proc/q()\n    return 3\n",
        );
        let third = store.get(&changed).unwrap();
        assert!(!Arc::ptr_eq(&first, &third));
        assert_eq!(third.len(), 2);
        let mut entries = 0;
        store.visit_storage(|view| {
            if matches!(view, dm_session::ObservedArtifactStorageView::Entry { .. }) {
                entries += 1;
            }
        });
        assert_eq!(entries, 1);
        drop(store);
        assert_eq!(first.len(), 1);
    }
}
