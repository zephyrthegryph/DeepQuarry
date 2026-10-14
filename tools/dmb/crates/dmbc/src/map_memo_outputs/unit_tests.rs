use super::*;

struct MapSource(&'static str);
impl dm_preprocess::SourceProvider for MapSource {
    fn read(&self, path: &Path) -> Result<String, String> {
        match path.extension().and_then(|s| s.to_str()) {
            Some("dme") => Ok("#include \"probe.dmm\"\n".into()),
            Some("dmm") => Ok(self.0.into()),
            _ => Err("missing".into()),
        }
    }
}
#[test]
fn one_changed_map_unit_keeps_other_program_with_current_origins_and_fresh_order() {
    let owner = Arc::new(RetainedMaps::current_revision());
    let mut previous = None;
    for (step, text) in [
        "\"a\"=(/obj{x=1},/obj{x=2},/obj{},/obj,/turf,/area)\n(1,1,1)={\"a\"}",
        "// shift\n\"a\"=(/obj{x=3},/obj{x=2},/obj{},/obj,/turf,/area)\n(1,1,1)={\"a\"}",
    ]
    .into_iter()
    .enumerate()
    {
        let source = MapSource(text);
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
        let (_, actual) = prepare(
            &memo,
            &frontend,
            &captured.maps,
            &projection,
            &Facts { shared: false },
        )
        .unwrap();
        let (_, fresh) = prepare(
            &MapMemo::request(1),
            &frontend,
            &captured.maps,
            &projection,
            &Facts { shared: false },
        )
        .unwrap();
        assert_eq!(actual.len(), 3); // empty authored block present; absent block omitted
        assert_eq!(
            actual.iter().map(|a| a.identity).collect::<Vec<_>>(),
            fresh.iter().map(|a| a.identity).collect::<Vec<_>>()
        );
        for (actual, fresh) in actual.iter().zip(&fresh) {
            assert_eq!(actual.code.procedure, fresh.code.procedure);
            assert_eq!(actual.debug_origins, fresh.debug_origins);
        }
        if step == 0 {
            assert!(memo.publish_successful());
            let unchanged = MapMemo::with_resident(1, owner.clone(), None);
            prepare(
                &unchanged,
                &frontend,
                &captured.maps,
                &projection,
                &Facts { shared: false },
            )
            .unwrap();
            assert_eq!(unchanged.counts.output_hits.load(Ordering::Relaxed), 1);
            // An unchanged bundle must keep its per-unit claims, otherwise the
            // subsequent structural edit would lose the unchanged program.
            assert!(unchanged.publish_successful());
        }
        if let Some(previous) = previous {
            assert_eq!(memo.counts.unit_hits.load(Ordering::Relaxed), 2);
            assert!(Arc::ptr_eq(&previous, actual[1].code.code_owner()));
            let changed_context = MapMemo::with_resident(1, owner.clone(), None);
            prepare_context(
                &changed_context,
                &frontend,
                &captured.maps,
                &projection,
                &Facts { shared: false },
                Some(7),
            )
            .unwrap();
            assert_eq!(changed_context.counts.unit_hits.load(Ordering::Relaxed), 0);
            let changed_policy = MapMemo::with_resident(2, owner.clone(), None);
            prepare(
                &changed_policy,
                &frontend,
                &captured.maps,
                &projection,
                &Facts { shared: false },
            )
            .unwrap();
            assert_eq!(changed_policy.counts.unit_hits.load(Ordering::Relaxed), 0);
            assert!(prepare(
                &memo,
                &frontend,
                &captured.maps,
                &projection,
                &Facts { shared: true }
            )
            .is_err());
        }
        previous = Some(actual[1].code.code_owner().clone());
    }
}

#[test]
fn aborted_prepared_output_roster_preserves_successful_bundle_and_releases_new_units() {
    fn output_entries(owner: &RetainedMaps) -> usize {
        let mut count = 0;
        owner.outputs.visit_storage(|view| {
            if let dm_session::ArtifactStorageView::Store { entries, .. } = view {
                count = entries;
            }
        });
        count
    }
    let owner = Arc::new(RetainedMaps::current_revision());
    let mut baseline = 0;
    let mut original = None;
    for (step, text) in [
        "\"a\"=(/obj{x=1},/obj{x=2},/turf,/area)\n(1,1,1)={\"a\"}",
        "\"a\"=(/obj{x=3},/obj{x=2},/turf,/area)\n(1,1,1)={\"a\"}",
        "\"a\"=(/obj{x=1},/obj{x=2},/turf,/area)\n(1,1,1)={\"a\"}",
    ]
    .into_iter()
    .enumerate()
    {
        let source = MapSource(text);
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
        let request = MapMemo::with_resident(1, owner.clone(), None);
        let (_, actual) = prepare(
            &request,
            &frontend,
            &captured.maps,
            &projection,
            &Facts { shared: false },
        )
        .unwrap();
        match step {
            0 => {
                original = Some(actual[0].code.code_owner().clone());
                assert!(request.publish_successful());
                baseline = output_entries(&owner);
                assert_eq!(baseline, 3); // two units plus the bundle
            }
            1 => {
                assert_eq!(request.counts.unit_hits.load(Ordering::Relaxed), 1);
                assert!(output_entries(&owner) > baseline);
                // The map stage succeeded, but a later required request stage
                // failed: dropping the attempt must not publish its roster.
                drop(request);
                assert_eq!(output_entries(&owner), baseline);
                continue;
            }
            _ => {
                assert_eq!(request.counts.output_hits.load(Ordering::Relaxed), 1);
                assert!(Arc::ptr_eq(
                    original.as_ref().unwrap(),
                    actual[0].code.code_owner()
                ));
                assert!(request.publish_successful());
                assert_eq!(output_entries(&owner), baseline);
            }
        }
    }
}

#[test]
fn verified_map_units_shadow_current_producer_even_when_bundle_matches() {
    let source = MapSource("\"a\"=(/obj{x=1},/obj{x=2},/turf,/area)\n(1,1,1)={\"a\"}");
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
    let owner = Arc::new(RetainedMaps::current_revision());
    let first = MapMemo::with_resident(1, owner.clone(), None);
    let (_, baseline) = prepare(
        &first,
        &frontend,
        &captured.maps,
        &projection,
        &Facts { shared: false },
    )
    .unwrap();
    assert!(first.publish_successful());
    let mut current = MapMemo::with_resident(1, owner, None);
    current.verification = crate::lowering_memo::VerifyPolicy::all();
    let (_, actual) = prepare(
        &current,
        &frontend,
        &captured.maps,
        &projection,
        &Facts { shared: false },
    )
    .unwrap();
    assert_eq!(current.counts.output_hits.load(Ordering::Relaxed), 0);
    assert_eq!(current.counts.unit_hits.load(Ordering::Relaxed), 2);
    assert_eq!(current.map_verification_counts(), (2, 0));
    assert_eq!(actual[0].debug_origins, baseline[0].debug_origins);
    let key = current
        .current
        .lock()
        .unwrap()
        .outputs
        .iter()
        .find(|key| key.starts_with(outputs::units::PREFIX))
        .unwrap()
        .clone();
    let original = current
        .with_pending_maps(|leases| {
            leases
                .outputs
                .visit_explained_accepted(&key, &Facts { shared: false }, &mut |value| {
                    matches!(value.as_ref(), outputs::MapOutputs::Unit(_))
                })
                .0
                .unwrap()
                .reads
                .iter()
                .cloned()
                .collect::<Vec<_>>()
        })
        .unwrap();
    assert!(!original.is_empty());
    let mut omitted = original.clone();
    omitted.pop();
    let error = current
        .verify_map_unit(&actual[0].code, &actual[0].debug_origins, &omitted, || {
            Ok((
                actual[0].code.as_ref().clone(),
                actual[0].debug_origins.clone(),
                original.clone(),
            ))
        })
        .unwrap_err();
    assert!(error.contains("ledger"));
    let error = current
        .verify_map_unit(&actual[0].code, &actual[0].debug_origins, &original, || {
            Ok((
                actual[1].code.as_ref().clone(),
                actual[0].debug_origins.clone(),
                original.clone(),
            ))
        })
        .unwrap_err();
    assert!(error.contains("symbolic initializer output"));
    assert!(!current.publish_successful());
}
