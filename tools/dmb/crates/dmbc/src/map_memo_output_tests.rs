use super::*;
use crate::{initialization_artifact::InitializationArtifact, map_output::DescriptorPlan};
use dm_ir::{ResolveQuery, ResolvedMeaning, SymbolId};
use std::path::Path;
#[path = "map_memo_outputs/unit_tests.rs"]
mod unit_tests;
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
            ResolveQuery::RuntimeType(path) => ResolvedMeaning::Symbol(path),
            ResolveQuery::Ancestry(owner) => ResolvedMeaning::Symbols(vec![owner].into()),
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
            None => crate::map_artifacts::lower_with_memo(
                frontend,
                maps,
                projection,
                descriptors,
                &maps[0].symbols,
                recording,
                context,
                Some(memo),
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
    assert!(Arc::ptr_eq(
        code[0].code.code_owner(),
        hit[0].code.code_owner()
    ));
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

#[test]
fn retained_modified_map_outputs_match_fresh_and_decline_source_or_dependency_changes() {
    struct ModifiedSource(&'static str);
    impl dm_preprocess::SourceProvider for ModifiedSource {
        fn read(&self, path: &Path) -> Result<String, String> {
            match path.extension().and_then(|s| s.to_str()) {
                Some("dme") => Ok("#include \"probe.dmm\"\n".into()),
                Some("dmm") => Ok(self.0.into()),
                _ => Err("missing".into()),
            }
        }
    }
    let owner = Arc::new(RetainedMaps::current_revision());
    let mut previous = None;
    for (index, source) in [
        "\"a\"=(/obj{x=(/obj/item{amount=1})},/turf,/area)\n(1,1,1)={\"a\"}",
        "\"a\"=(/obj{x=(/obj/item{amount=1})},/turf,/area)\n(1,1,1)={\"a\"}",
        "// shifted map source\n\"a\"=(/obj{x=(/obj/item{amount=1})},/turf,/area)\n(1,1,1)={\"a\"}",
        "// shifted map source\n\"a\"=(/obj{x=(/obj/item{amount=2})},/turf,/area)\n(1,1,1)={\"a\"}",
    ]
    .into_iter()
    .enumerate()
    {
        let source = ModifiedSource(source);
        let frontend = dm_tree::frontend::build(
            Path::new("game/project.dme"),
            &source,
            &Default::default(),
            1,
        )
        .unwrap();
        let captured = crate::non_text::capture(&frontend, &source).unwrap();
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
        let memo = MapMemo::with_resident(1, owner.clone(), None);
        let (_, current) = prepare(
            &memo,
            &frontend,
            &captured.maps,
            &projection,
            &Facts { shared: false },
        )
        .unwrap();
        let mut retained_units = 0;
        owner.outputs.visit_storage(&mut |view| {
            if let dm_session::ArtifactStorageView::Entry { value, .. } = view {
                if matches!(value.as_ref(), outputs::MapOutputs::Unit(_)) {
                    retained_units += 1;
                }
            }
        });
        assert!(
            retained_units > 0,
            "modified unit did not populate the existing output store"
        );
        assert_eq!(memo.counts.output_hits.load(Ordering::Relaxed), 0);
        assert_eq!(
            memo.counts.unit_hits.load(Ordering::Relaxed),
            u64::from(index == 1 || index == 2)
        );
        let (_, fresh) = prepare(
            &MapMemo::new(1, 0),
            &frontend,
            &captured.maps,
            &projection,
            &Facts { shared: false },
        )
        .unwrap();
        assert_eq!(current.len(), 1);
        assert_eq!(current[0].code.procedure, fresh[0].code.procedure);
        assert_eq!(current[0].debug_origins, fresh[0].debug_origins);
        let actual = current[0].code.modified_instances.values().next().unwrap();
        let expected = fresh[0].code.modified_instances.values().next().unwrap();
        assert_eq!(
            actual.descriptor.canonical_bytes(),
            expected.descriptor.canonical_bytes()
        );
        assert_eq!(actual.descriptor.fields(), expected.descriptor.fields());
        assert_eq!(actual.source_span, expected.source_span);
        assert_eq!(actual.field_origins, expected.field_origins);
        if let Some(code) = previous.as_ref() {
            // Descriptor sidecars are reissued from the current source even
            // when the retained symbolic program is admitted.
            assert!(!Arc::ptr_eq(code, current[0].code.code_owner()));
        }
        previous = Some(Arc::clone(current[0].code.code_owner()));
        // Failed requests prune their partial roster on Drop. Keep that
        // independent rejection control from deleting the successful owner's
        // units before the next identical/shifted-source admission above.
        let changed = MapMemo::with_resident(1, Arc::new(RetainedMaps::current_revision()), None);
        prepare(
            &changed,
            &frontend,
            &captured.maps,
            &projection,
            &Facts { shared: false },
        )
        .unwrap();
        assert!(prepare(
            &changed,
            &frontend,
            &captured.maps,
            &projection,
            &Facts { shared: true }
        )
        .is_err());
        assert_eq!(changed.counts.output_hits.load(Ordering::Relaxed), 0);
    }
}
