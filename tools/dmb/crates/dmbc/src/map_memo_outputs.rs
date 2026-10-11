//! Map emission artifacts retain immutable symbolic code, never current table
//! slots. Current source provenance and dependency answers license each reuse.
use super::*;
use crate::{initialization_artifact::InitializationArtifact, map_output::DescriptorPlan};
use dm_tree::frontend::ColdFrontend;

pub struct MapOutputInputs<'a, R> {
    pub frontend: &'a ColdFrontend,
    pub maps: &'a [MapPlan],
    pub projection: &'a Projection,
    pub host: &'a R,
    pub resource_search_context: Option<u128>,
}

#[path = "map_memo_outputs/units.rs"]
pub(crate) mod units;
pub(super) enum MapOutputs {
    Bundle(MapBundle),
    Unit(units::RetainedUnit),
}
pub(super) struct MapBundle {
    maps: Arc<[MapPlan]>,
    projection: Projection,
    paths: Arc<[Arc<str>]>,
    descriptors: DescriptorPlan,
    artifacts: Arc<[InitializationArtifact]>,
    unit_keys: Vec<Arc<[u8]>>,
}
pub(super) fn current_paths(
    frontend: &ColdFrontend,
    maps: &[MapPlan],
) -> Result<Arc<[Arc<str>]>, String> {
    maps.iter()
        .map(|map| {
            let include = frontend
                .plan
                .occurrences
                .get(map.captured.include_occurrence as usize)
                .ok_or("map initializer include occurrence absent")?;
            if include.path != map.captured.path {
                return Err("map initializer source differs from include capture".into());
            }
            Ok(include.semantic_path.clone())
        })
        .collect::<Result<Vec<_>, _>>()
        .map(Arc::from)
}
fn same_projection(left: &Projection, right: &Projection) -> bool {
    left.dimensions == right.dimensions
        && (Arc::ptr_eq(&left.grid, &right.grid) || left.grid == right.grid)
        && (Arc::ptr_eq(&left.objects, &right.objects) || left.objects == right.objects)
        && (Arc::ptr_eq(&left.instances, &right.instances)
            || (left.instances.len() == right.instances.len()
                && left
                    .instances
                    .iter()
                    .zip(right.instances.iter())
                    .all(|(a, b)| a.kind == b.kind && a.atom == b.atom && a.origin == b.origin)))
}
fn key(
    policy: u128,
    maps: &[MapPlan],
    projection: &Projection,
    paths: &[Arc<str>],
    context: Option<u128>,
) -> Arc<[u8]> {
    let mut key = b"dmbc-map-outputs-resident-v1\0".to_vec();
    key.extend_from_slice(&policy.to_le_bytes());
    key.push(u8::from(context.is_some()));
    if let Some(context) = context {
        key.extend_from_slice(&context.to_le_bytes());
    }
    for axis in projection.dimensions {
        key.extend_from_slice(&axis.to_le_bytes());
    }
    key.extend_from_slice(&(maps.len() as u64).to_le_bytes());
    for (map, path) in maps.iter().zip(paths) {
        frame(&mut key, path.as_bytes());
        key.extend_from_slice(&map.source_identity.to_le_bytes());
        key.extend_from_slice(&map.semantic_identity.to_le_bytes());
    }
    key.into()
}
impl MapMemo {
    pub fn output_artifacts<R: Resolver>(
        &self,
        inputs: MapOutputInputs<'_, R>,
        prepare_descriptors: impl FnOnce(Option<&DescriptorPlan>) -> Result<DescriptorPlan, String>,
        prepare_initializers: impl FnOnce(
            Option<&[InitializationArtifact]>,
            &DescriptorPlan,
            &RecordingResolver<'_, R>,
        ) -> Result<Vec<InitializationArtifact>, String>,
    ) -> Result<(DescriptorPlan, Vec<InitializationArtifact>), String> {
        let MapOutputInputs {
            frontend,
            maps,
            projection,
            host,
            resource_search_context: context,
        } = inputs;
        let recording = RecordingResolver::new(host);
        let paths = match current_paths(frontend, maps) {
            Ok(paths) => paths,
            Err(_) => {
                // Refused retention must preserve the original descriptor-first
                // diagnostic, including malformed synthetic compatibility inputs.
                let descriptors = prepare_descriptors(None)?;
                let artifacts = prepare_initializers(None, &descriptors, &recording)?;
                return Ok((descriptors, artifacts));
            }
        };
        let key = key(self.policy, maps, projection, &paths, context);
        if let Some(retained) = &self.retained {
            self.current
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .outputs
                .push(key.clone());
            let (hit, _) = retained
                .outputs
                .visit_explained(&key, host, &mut |artifact| {
                    let MapOutputs::Bundle(artifact) = artifact.as_ref() else {
                        return false;
                    };
                    artifact.paths == paths
                        && same_projection(&artifact.projection, projection)
                        && artifact.maps.len() == maps.len()
                        && artifact.maps.iter().zip(maps).all(|(old, new)| {
                            old.captured.path == new.captured.path
                                && (Arc::ptr_eq(&old.captured.source, &new.captured.source)
                                    || old.captured.source == new.captured.source)
                                && (Arc::ptr_eq(&old.model, &new.model) || old.model == new.model)
                                && old.template_origins == new.template_origins
                                && old.block_origins == new.block_origins
                        })
                });
            if let Some(hit) = hit {
                let MapOutputs::Bundle(hit) = hit.as_ref() else {
                    unreachable!()
                };
                self.current
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .outputs
                    .extend(hit.unit_keys.iter().cloned());
                self.counts.output_hits.fetch_add(1, Ordering::Relaxed);
                let descriptors = prepare_descriptors(Some(&hit.descriptors))?;
                let artifacts =
                    prepare_initializers(Some(&hit.artifacts), &descriptors, &recording)?;
                return Ok((descriptors, artifacts));
            }
        }
        self.counts.outputs_prepared.fetch_add(1, Ordering::Relaxed);
        let descriptors = prepare_descriptors(None)?;
        let artifacts = prepare_initializers(None, &descriptors, &recording)?;
        if let Some(retained) = &self.retained {
            let maps: Arc<[MapPlan]> = maps.to_vec().into();
            let reads = recording.reads();
            let versions = recording.domain_receipts();
            let artifacts: Arc<[InitializationArtifact]> = artifacts.into();
            let unit_keys: Vec<_> = self
                .current
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .outputs
                .iter()
                .filter(|key| key.starts_with(units::PREFIX))
                .cloned()
                .collect();
            // Current descriptor ASTs never enter bundle history. Their units
            // are retained only as source-neutral recipes below this same store.
            if artifacts
                .iter()
                .all(|artifact| artifact.code.modified_instances.is_empty())
            {
                if let Some(weight) = crate::heap_census::resident_map_outputs_weight(
                    &maps,
                    projection,
                    &paths,
                    &descriptors,
                    &artifacts,
                    &key,
                    &reads,
                    &versions,
                    &unit_keys,
                ) {
                    retained
                        .outputs
                        .insert_with(key, reads, versions, weight, || {
                            MapOutputs::Bundle(MapBundle {
                                maps,
                                projection: projection.clone(),
                                paths,
                                descriptors: descriptors.clone(),
                                artifacts: artifacts.clone(),
                                unit_keys,
                            })
                        });
                }
            }
            return Ok((descriptors, artifacts.to_vec()));
        }
        Ok((descriptors, artifacts))
    }
}
