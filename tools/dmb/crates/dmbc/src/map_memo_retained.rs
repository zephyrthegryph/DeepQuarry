//! Current-revision map artifacts. Locators select buckets; exact immutable
//! source/model owners and the shared read ledger authorize every admission.
use super::*;
use dm_preprocess::{RetainedText, SourceProvider};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

pub struct RetainedMaps {
    parse: Arc<dm_session::ArtifactStore<MapPlan>>,
    geometry: Arc<dm_session::ArtifactStore<GeometryArtifact>>,
    pub(super) outputs: Arc<dm_session::ArtifactStore<super::outputs::MapOutputs>>,
    sources: Mutex<BTreeMap<PathBuf, CachedSource>>,
    publication: Arc<dm_session::ArtifactPublication<MapLeases>>,
}
struct CachedSource {
    text: RetainedText,
    generation: dm_session::ArtifactGeneration,
}
pub(super) struct MapLeases {
    sources: Mutex<Vec<PathBuf>>,
    parse: dm_session::ObservedArtifactLease<
        MapPlan,
        dm_ir::ResolveQuery,
        dm_ir::ResolvedMeaning,
        dm_ir::ReadDomain,
    >,
    geometry: dm_session::ObservedArtifactLease<
        GeometryArtifact,
        dm_ir::ResolveQuery,
        dm_ir::ResolvedMeaning,
        dm_ir::ReadDomain,
    >,
    pub(super) outputs: dm_session::ObservedArtifactLease<
        super::outputs::MapOutputs,
        dm_ir::ResolveQuery,
        dm_ir::ResolvedMeaning,
        dm_ir::ReadDomain,
    >,
}
struct GeometryArtifact {
    maps: Arc<[MapPlan]>,
    value: Projection,
}
impl RetainedMaps {
    #[cfg(test)]
    pub(super) fn test_entries(&self) -> usize {
        let mut count = 0;
        self.parse.visit_storage(|view| {
            if let dm_session::ArtifactStorageView::Store { entries, .. } = view {
                count += entries;
            }
        });
        self.geometry.visit_storage(|view| {
            if let dm_session::ArtifactStorageView::Store { entries, .. } = view {
                count += entries;
            }
        });
        count
    }
    pub fn artifact_admitted_bytes(&self) -> usize {
        self.parse
            .admitted_bytes()
            .saturating_add(self.geometry.admitted_bytes())
            .saturating_add(self.outputs.admitted_bytes())
    }
    pub fn current_revision() -> Self {
        Self {
            parse: dm_session::ArtifactStore::shared_current_rosters(),
            geometry: dm_session::ArtifactStore::shared_current_rosters(),
            outputs: dm_session::ArtifactStore::shared_current_rosters(),
            sources: Mutex::new(BTreeMap::new()),
            publication: Arc::new(dm_session::ArtifactPublication::default()),
        }
    }
}
#[derive(Default)]
pub(super) struct CurrentRoster {
    pub(super) outputs: Vec<Arc<[u8]>>,
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
                .filter(|source| Arc::ptr_eq(source.text.text(), &captured.source))
            {
                return parse_key_with_identity(self.policy, captured, source.text.text_identity());
            }
        }
        parse_key(self.policy, captured)
    }
    pub fn with_resident(
        policy: u128,
        resident: Arc<RetainedMaps>,
        disk: Option<Arc<crate::runner_disk::LazyDisk>>,
    ) -> Self {
        Self::with_resident_for_request(policy, resident, disk, true)
    }
    pub fn with_resident_for_request(
        policy: u128,
        resident: Arc<RetainedMaps>,
        disk: Option<Arc<crate::runner_disk::LazyDisk>>,
        publishable: bool,
    ) -> Self {
        let mut memo = Self::empty(policy);
        let leases = MapLeases {
            sources: Mutex::new(Vec::new()),
            parse: resident.parse.lease(),
            geometry: resident.geometry.lease(),
            outputs: resident.outputs.lease(),
        };
        memo.pending_maps = Some(if publishable {
            resident.publication.begin(leases)
        } else {
            resident.publication.begin_ephemeral(leases)
        });
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
        let Some(attempt) = &self.pending_maps else {
            return provider.read(path).map(Arc::from);
        };
        attempt
            .with_pending(|leases| {
                let path = dm_preprocess::regions::canonical_path(path);
                let previous = retained
                    .sources
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .get(&path)
                    .map(|source| source.text.clone());
                let source = provider.retained_nontext(&path, previous.as_ref())?;
                leases
                    .sources
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .push(path.clone());
                if let Some(source) = source {
                    let text = source.text().clone();
                    // Advisory cache only: an older request must not replace newer bookkeeping.
                    if attempt.is_latest() {
                        retained
                            .sources
                            .lock()
                            .unwrap_or_else(|e| e.into_inner())
                            .insert(
                                path,
                                CachedSource {
                                    text: source,
                                    generation: attempt.generation().clone(),
                                },
                            );
                    }
                    Ok(text)
                } else {
                    provider.read(&path).map(Arc::from)
                }
            })
            .unwrap_or_else(|| provider.read(path).map(Arc::from))
    }
    /// Seal exact pending claims after required request publication succeeds.
    pub fn publish_successful(&self) -> bool {
        let Some(attempt) = &self.pending_maps else {
            return false;
        };
        if !attempt.publish_successful() {
            return false;
        }
        if let Some(retained) = &self.retained {
            let paths = retained
                .publication
                .with_published(|leases| {
                    leases
                        .sources
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .clone()
                })
                .unwrap_or_default();
            retained
                .sources
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .retain(|path, value| {
                    paths.contains(path) || retained.publication.is_latest(&value.generation)
                });
        }
        true
    }
    pub(super) fn with_pending_maps<T>(
        &self,
        operation: impl FnOnce(&MapLeases) -> T,
    ) -> Option<T> {
        self.pending_maps.as_ref()?.with_pending(operation)
    }
    /// Explicit successful-stage compatibility API. Drop never commits.
    pub fn finish_revision(&self) {
        self.publish_successful();
    }
    pub(super) fn retained_parse(
        &self,
        key: &Arc<[u8]>,
        captured: &CapturedMap,
    ) -> Option<MapPlan> {
        self.with_pending_maps(|retained| {
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
        })
        .flatten()
    }
    pub(super) fn admit_retained_parse(&self, key: Arc<[u8]>, plan: &MapPlan) {
        self.with_pending_maps(|retained| {
            if let Some(weight) = crate::heap_census::resident_map_plan_weight(plan, &key) {
                retained
                    .parse
                    .insert_with(key, Vec::new(), Vec::new(), weight, || plan.clone());
            }
        });
    }
    pub(super) fn retained_geometry<R: Resolver>(
        &self,
        key: &Arc<[u8]>,
        maps: &[MapPlan],
        host: &R,
    ) -> Option<Projection> {
        self.with_pending_maps(|retained| {
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
        })
        .flatten()
    }
    pub(super) fn admit_retained_geometry(
        &self,
        key: Arc<[u8]>,
        maps: &[MapPlan],
        value: &Projection,
        reads: Vec<ResolverRead>,
        versions: Vec<(dm_ir::ReadDomain, u128)>,
    ) {
        self.with_pending_maps(|retained| {
            let maps: Arc<[MapPlan]> = maps.to_vec().into();
            if let Some(weight) = crate::heap_census::resident_map_geometry_weight(
                &maps, value, &key, &reads, &versions,
            ) {
                retained
                    .geometry
                    .insert_with(key, reads, versions, weight, || GeometryArtifact {
                        maps,
                        value: value.clone(),
                    });
            }
        });
    }
}
impl Drop for MapMemo {
    fn drop(&mut self) {
        let (Some(retained), Some(attempt)) = (&self.retained, &self.pending_maps) else {
            return;
        };
        // Remove only advisory entries owned by this attempt and not needed by
        // the last successful roster. Exact artifact claims release separately.
        let published = retained
            .publication
            .with_published(|leases| {
                leases
                    .sources
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .clone()
            })
            .unwrap_or_default();
        retained
            .sources
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .retain(|path, value| {
                !value.generation.same_as(attempt.generation()) || published.contains(path)
            });
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
