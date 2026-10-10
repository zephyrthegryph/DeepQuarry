//! Retained resource hints; current filesystem/demand/archive admission remains mandatory.
use crate::{input_snapshot::InputSnapshot, resource_manifest::ResourceManifest};
use std::{
    collections::{BTreeMap, BTreeSet},
    path::PathBuf,
    sync::Arc,
};
const KEY: &[u8] = b"resource-publication-hint-v1";
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Configuration {
    pub policy: u128,
    pub project: PathBuf,
    pub defines: BTreeMap<String, String>,
    pub output: PathBuf,
    pub store: Option<PathBuf>,
    pub generated: BTreeSet<PathBuf>,
}
pub(crate) struct Hint {
    pub pair: u128,
    pub manifest: Arc<ResourceManifest>,
    pub outputs: InputSnapshot,
}
pub(crate) struct Resources {
    values: dm_session::ObservedArtifactStore<Hint, (), Configuration, ()>,
}
struct Current<'a>(&'a Configuration);
impl dm_session::ObservationHost<(), Configuration, ()> for Current<'_> {
    fn answer(&self, _: &()) -> Configuration {
        self.0.clone()
    }
}
impl Default for Resources {
    fn default() -> Self {
        Self {
            values: dm_session::ObservedArtifactStore::current_revision(),
        }
    }
}
impl Resources {
    pub(crate) fn hint(&self, configuration: &Configuration) -> Option<Arc<Hint>> {
        self.values.lookup(KEY, &Current(configuration))
    }
    pub(crate) fn remember(&self, configuration: Configuration, hint: Hint) {
        // Current-roster charge is inline bookkeeping, not a resident-memory estimate.
        self.values.insert_with_owned(
            Arc::from(KEY),
            vec![dm_session::Observation {
                query: (),
                answer: configuration,
                domain: (),
            }],
            Vec::new(),
            std::mem::size_of::<Hint>() + KEY.len(),
            || hint,
        );
    }
    pub(crate) fn census(&self) -> crate::heap_census::HeapCensusReport {
        let mut c = crate::heap_census::HeapCensus::new("retained.resources");
        self.values.visit_storage(|view| match view {
            dm_session::ObservedArtifactStorageView::Store { buckets, entries } => {
                c.observe_items("resources.index", entries);
                if buckets != 0 {
                    c.unknown(
                        "resources.index",
                        "private generic index/control allocation excluded",
                    );
                }
            }
            dm_session::ObservedArtifactStorageView::Bucket {
                address,
                len,
                capacity,
                element_size,
            } => {
                c.exposed_buffer(
                    "resources.buckets",
                    address,
                    len.saturating_mul(element_size),
                    capacity.saturating_mul(element_size),
                );
            }
            dm_session::ObservedArtifactStorageView::Entry {
                key,
                reads,
                versions,
                value,
            } => {
                c.slice("resources.key", key, true);
                c.slice("resources.reads", reads, true);
                c.slice("resources.versions", versions, true);
                for read in reads.iter() {
                    let a = &read.answer;
                    c.path("resources.configuration", &a.project);
                    c.path("resources.configuration", &a.output);
                    if let Some(path) = &a.store {
                        c.path("resources.configuration", path);
                    }
                    for path in &a.generated {
                        c.path("resources.configuration", path);
                    }
                    for (k, v) in &a.defines {
                        c.string("resources.configuration", k);
                        c.string("resources.configuration", v);
                    }
                    c.unknown(
                        "resources.configuration",
                        "private BTree node backing excluded",
                    );
                }
                if c.arc_object("resources.hint", value) {
                    if c.arc_object("resources.manifest", &value.manifest) {
                        value.manifest.census(&mut c);
                    }
                    inspect_snapshot(&value.outputs, &mut c);
                }
            }
        });
        c.finish()
    }
}
pub(crate) fn inspect_snapshot(s: &InputSnapshot, c: &mut crate::heap_census::HeapCensus) {
    c.observe_items("resources.proofs", s.files().count());
    for f in s.files() {
        c.path("resources.proof_paths", &f.path);
    }
    c.unknown(
        "resources.proofs",
        "private InputSnapshot folder/negative/index payload and BTree backing excluded",
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn retained_resources_follow_host_lifetime_and_one_shot_does_not_allocate() {
        let mut host = crate::runner_host::BuildHost::default();
        let owner = host.resources().unwrap();
        assert!(Arc::ptr_eq(&owner, &host.resources().unwrap()));
        let weak = Arc::downgrade(&owner);
        drop(owner);
        host.release_idle_compiler_artifacts();
        assert!(weak.upgrade().is_some());
        assert!(Arc::ptr_eq(
            &weak.upgrade().unwrap(),
            &host.resources().unwrap()
        ));
        drop(host);
        assert!(weak.upgrade().is_none());
        assert!(crate::runner_host::BuildHost::one_shot()
            .resources()
            .is_none());
    }
}
