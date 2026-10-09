//! Current-revision map artifacts. Locators select buckets; exact immutable
//! source/model owners and the shared read ledger authorize every admission.
use super::*;
use std::collections::BTreeMap;
use dm_preprocess::{RetainedText, SourceProvider};
use std::path::{Path, PathBuf};

pub struct RetainedMaps {
    parse: dm_session::ArtifactStore<MapPlan>,
    geometry: dm_session::ArtifactStore<GeometryArtifact>,
    pub(super) outputs: dm_session::ArtifactStore<super::outputs::MapOutputs>,
    sources: Mutex<BTreeMap<PathBuf, RetainedText>>,
    revision: AtomicU64,
}
struct GeometryArtifact {
    maps: Arc<[MapPlan]>,
    value: Projection,
}
impl RetainedMaps {
    pub fn artifact_admitted_bytes(&self) -> usize {
        self.parse
            .admitted_bytes()
            .saturating_add(self.geometry.admitted_bytes())
            .saturating_add(self.outputs.admitted_bytes())
    }
    pub fn current_revision() -> Self {
        Self {
            parse: dm_session::ArtifactStore::current_revision(),
            geometry: dm_session::ArtifactStore::current_revision(),
            outputs: dm_session::ArtifactStore::current_revision(),
            sources: Mutex::new(BTreeMap::new()),
            revision: AtomicU64::new(0),
        }
    }
}
#[derive(Default)]
pub(super) struct CurrentRoster {
    parse: Vec<Arc<[u8]>>,
    geometry: Vec<Arc<[u8]>>,
    pub(super) outputs: Vec<Arc<[u8]>>,
    sources: Vec<PathBuf>,
}
struct NoReads;
impl Resolver for NoReads {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        dm_ir::ResolvedMeaning::Unsupported(query)
    }
}
impl MapMemo {
    pub(super) fn parse_locator(&self, captured: &CapturedMap) -> Vec<u8> {
        if let Some(retained) = &self.retained {
            let path = dm_preprocess::regions::canonical_path(&captured.path);
            let sources = retained.sources.lock().unwrap_or_else(|e| e.into_inner());
            if let Some(source) = sources
                .get(&path)
                .filter(|source| Arc::ptr_eq(source.text(), &captured.source))
            {
                return parse_key_with_identity(self.policy, captured, source.text_identity());
            }
        }
        parse_key(self.policy, captured)
    }
    pub fn with_resident(
        policy: u128,
        resident: Arc<RetainedMaps>,
        disk: Option<Arc<crate::runner_disk::LazyDisk>>,
    ) -> Self {
        let mut memo = Self::new(policy, 0);
        memo.retained_revision = resident
            .revision
            .fetch_add(1, Ordering::AcqRel)
            .wrapping_add(1);
        memo.retained = Some(resident);
        memo.disk = disk;
        memo
    }
    pub fn capture_source<P: SourceProvider>(
        &self,
        provider: &P,
        path: &Path,
    ) -> Result<Arc<str>, String> {
        let Some(retained) = &self.retained else {
            return provider.read(path).map(Arc::from);
        };
        let path = dm_preprocess::regions::canonical_path(path);
        let previous = retained
            .sources
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(&path)
            .cloned();
        let source = provider.retained_nontext(&path, previous.as_ref())?;
        self.current
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .sources
            .push(path.clone());
        if let Some(source) = source {
            let text = source.text().clone();
            retained
                .sources
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .insert(path, source);
            Ok(text)
        } else {
            // A provider that cannot certify this receipt must perform its read.
            retained
                .sources
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .remove(&path);
            provider.read(&path).map(Arc::from)
        }
    }
    pub fn finish_revision(&self) {
        let Some(retained) = &self.retained else {
            return;
        };
        if retained.revision.load(Ordering::Acquire) != self.retained_revision {
            return;
        }
        let current = self.current.lock().unwrap_or_else(|e| e.into_inner());
        retained
            .parse
            .retain_current_keys(current.parse.iter().map(|k| k.as_ref()));
        retained
            .geometry
            .retain_current_keys(current.geometry.iter().map(|k| k.as_ref()));
        retained
            .outputs
            .retain_current_keys(current.outputs.iter().map(|k| k.as_ref()));
        retained
            .sources
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .retain(|path, _| current.sources.contains(path));
    }
    pub(super) fn retained_parse(
        &self,
        key: &Arc<[u8]>,
        captured: &CapturedMap,
    ) -> Option<MapPlan> {
        let retained = self.retained.as_ref()?;
        self.current
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .parse
            .push(key.clone());
        let (hit, _) = retained.parse.visit_explained(key, &NoReads, &mut |plan| {
            (Arc::ptr_eq(&plan.captured.source, &captured.source)
                || plan.captured.source == captured.source)
                && plan.captured.path == captured.path
        });
        hit.map(|plan| {
            let mut plan = (*plan).clone();
            plan.captured = captured.clone();
            plan
        })
    }
    pub(super) fn admit_retained_parse(&self, key: Arc<[u8]>, plan: &MapPlan) {
        let Some(retained) = &self.retained else {
            return;
        };
        if let Some(weight) = crate::heap_census::resident_map_plan_weight(plan, &key) {
            retained
                .parse
                .insert_with(key, Vec::new(), Vec::new(), weight, || plan.clone());
        }
    }
    pub(super) fn retained_geometry<R: Resolver>(
        &self,
        key: &Arc<[u8]>,
        maps: &[MapPlan],
        host: &R,
    ) -> Option<Projection> {
        let retained = self.retained.as_ref()?;
        self.current
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .geometry
            .push(key.clone());
        let (hit, _) = retained
            .geometry
            .visit_explained(key, host, &mut |artifact| {
                artifact.maps.len() == maps.len()
                    && artifact.maps.iter().zip(maps).all(|(old, new)| {
                        old.captured.path == new.captured.path
                            && (Arc::ptr_eq(&old.captured.source, &new.captured.source)
                                || old.captured.source == new.captured.source)
                            && (Arc::ptr_eq(&old.model, &new.model) || old.model == new.model)
                    })
            });
        hit.map(|artifact| artifact.value.clone())
    }
    pub(super) fn admit_retained_geometry(
        &self,
        key: Arc<[u8]>,
        maps: &[MapPlan],
        value: &Projection,
        reads: Vec<ResolverRead>,
        versions: Vec<(dm_ir::ReadDomain, u128)>,
    ) {
        let Some(retained) = &self.retained else {
            return;
        };
        let maps: Arc<[MapPlan]> = maps.to_vec().into();
        if let Some(weight) =
            crate::heap_census::resident_map_geometry_weight(&maps, value, &key, &reads, &versions)
        {
            retained
                .geometry
                .insert_with(key, reads, versions, weight, || GeometryArtifact {
                    maps,
                    value: value.clone(),
                });
        }
    }
}
impl Drop for MapMemo {
    fn drop(&mut self) {
        // Failed or cancelled requests must not accumulate historical map keys.
        // A partial current roster may evict reusable work, never authorize it.
        self.finish_revision();
    }
}
pub(super) fn geometry_locator(
    policy: u128,
    maps: &[MapPlan],
    defaults: WorldDefaults,
) -> Arc<[u8]> {
    let mut key = b"dmbc-map-geometry-resident-v1\0".to_vec();
    key.extend_from_slice(&policy.to_le_bytes());
    key.extend_from_slice(&defaults.turf.bits().to_le_bytes());
    key.extend_from_slice(&defaults.area.bits().to_le_bytes());
    for axis in defaults.minimum_dimensions {
        key.extend_from_slice(&axis.to_le_bytes());
    }
    key.extend_from_slice(&(maps.len() as u64).to_le_bytes());
    for map in maps {
        frame(
            &mut key,
            dm_preprocess::regions::canonical_path(&map.captured.path)
                .to_string_lossy()
                .as_bytes(),
        );
        key.extend_from_slice(&map.source_identity.to_le_bytes());
        key.extend_from_slice(&map.semantic_identity.to_le_bytes());
    }
    key.into()
}
