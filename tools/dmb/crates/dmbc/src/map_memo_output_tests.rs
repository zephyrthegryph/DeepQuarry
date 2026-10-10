use super::*;
use crate::{initialization_artifact::InitializationArtifact, map_output::DescriptorPlan};
use dm_ir::{ResolveQuery, ResolvedMeaning, SymbolId};
use std::path::Path;
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, path: &Path) -> Result<String, String> {
        match path.extension().and_then(|s| s.to_str()) {
            Some("dme") => Ok("#include \"probe.dmm\"\n".into()),
            Some("dmm") => Ok("\"a\"=(/obj{x=1},/turf,/area)\n(1,1,1)={\"a\"}".into()),
            _ => Err("missing".into()),
        }
    }
}
struct Facts {
    shared: bool,
}
impl Resolver for Facts {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        match query {
            ResolveQuery::VarStorage { owner, name } if self.shared => ResolvedMeaning::Slot {
                symbol: SymbolId::of("slot"),
                owner,
                name,
            },
            ResolveQuery::VarStorage { name, .. } => ResolvedMeaning::InstanceField {
                declaring_owner: SymbolId::of("/obj"),
                name,
            },
            ResolveQuery::HasMemberVar { .. } => ResolvedMeaning::Presence(true),
            ResolveQuery::DeclaredVarType { .. } => ResolvedMeaning::DeclaredType(None),
            _ => ResolvedMeaning::Missing,
        }
    }
}
struct Kinds;
impl crate::map_projection::InstanceClassifier for Kinds {
    fn classify(&self, path: SymbolId) -> Result<crate::map_projection::InstanceKind, String> {
        use crate::map_projection::InstanceKind::*;
        Ok(if path == SymbolId::of("/turf") {
            Turf
        } else if path == SymbolId::of("/area") {
            Area
        } else {
            Object
        })
    }
}
fn prepare_context(
    memo: &MapMemo,
    frontend: &dm_tree::frontend::ColdFrontend,
    maps: &[MapPlan],
    projection: &Projection,
    host: &Facts,
    context: Option<u128>,
) -> Result<(DescriptorPlan, Vec<InitializationArtifact>), String> {
    memo.output_artifacts(
        MapOutputInputs {
            frontend,
            maps,
            projection,
            host,
            resource_search_context: context,
        },
        |cached| match cached {
            Some(value) => Ok(value.clone()),
            None => crate::map_output::descriptors(frontend, projection, maps)
                .map_err(|e| format!("{e:?}")),
        },
        |cached, descriptors, recording| match cached {
            Some(value) => Ok(value.to_vec()),
            None => crate::map_artifacts::lower(
                frontend,
                maps,
                projection,
                descriptors,
                &maps[0].symbols,
                recording,
                context,
            ),
        },
    )
}
fn prepare(
    memo: &MapMemo,
    frontend: &dm_tree::frontend::ColdFrontend,
    maps: &[MapPlan],
    projection: &Projection,
    host: &Facts,
) -> Result<(DescriptorPlan, Vec<InitializationArtifact>), String> {
    prepare_context(memo, frontend, maps, projection, host, None)
}
#[test]
fn retained_map_outputs_share_code_match_fresh_and_invalidate_storage_reads() {
    let frontend = dm_tree::frontend::build(
        Path::new("game/project.dme"),
        &Source,
        &Default::default(),
        1,
    )
    .unwrap();
    let captured = crate::non_text::capture(&frontend, &Source).unwrap();
    let projection = crate::map_projection::project(
        &captured.maps,
        WorldDefaults {
            turf: SymbolId::of("/turf"),
            area: SymbolId::of("/area"),
            minimum_dimensions: [1; 3],
        },
        &Kinds,
    )
    .unwrap();
    let owner = Arc::new(RetainedMaps::current_revision());
    let first = MapMemo::with_resident(1, owner.clone(), None);
    let (descriptors, code) = prepare(
        &first,
        &frontend,
        &captured.maps,
        &projection,
        &Facts { shared: false },
    )
    .unwrap();
    let second = MapMemo::with_resident(1, owner.clone(), None);
    let (hit_descriptors, hit) = prepare(
        &second,
        &frontend,
        &captured.maps,
        &projection,
        &Facts { shared: false },
    )
    .unwrap();
    assert_eq!(second.counts.output_hits.load(Ordering::Relaxed), 1);
    assert!(Arc::ptr_eq(&descriptors.entries, &hit_descriptors.entries));
    assert_eq!(code.len(), 1);
    assert!(Arc::ptr_eq(code[0].code.code_owner(), hit[0].code.code_owner()));
    assert!(Arc::ptr_eq(&code[0].debug_origins, &hit[0].debug_origins));
    let (_, fresh) = prepare(
        &MapMemo::new(1, 0),
        &frontend,
        &captured.maps,
        &projection,
        &Facts { shared: false },
    )
    .unwrap();
    assert_eq!(hit[0].code.procedure, fresh[0].code.procedure);
    assert_eq!(hit[0].debug_origins, fresh[0].debug_origins);
    let (_, context_changed) = prepare_context(
        &second,
        &frontend,
        &captured.maps,
        &projection,
        &Facts { shared: false },
        Some(0),
    )
    .unwrap();
    assert_eq!(second.counts.outputs_prepared.load(Ordering::Relaxed), 1);
    assert_eq!(hit[0].code.procedure, context_changed[0].code.procedure);
    assert!(prepare(
        &second,
        &frontend,
        &captured.maps,
        &projection,
        &Facts { shared: true }
    )
    .is_err());
    assert_eq!(second.counts.outputs_prepared.load(Ordering::Relaxed), 2);
}
#[test]
fn current_semantic_path_binding_checks_include_authority() {
    let frontend = dm_tree::frontend::build(
        Path::new("game/project.dme"),
        &Source,
        &Default::default(),
        1,
    )
    .unwrap();
    let captured = crate::non_text::capture(&frontend, &Source).unwrap();
    let paths = outputs::current_paths(&frontend, &captured.maps).unwrap();
    assert_eq!(paths.len(), 1);
    let mut shifted = captured.maps[0].clone();
    shifted.captured.include_occurrence = u32::MAX;
    assert!(outputs::current_paths(&frontend, &[shifted]).is_err());
}
