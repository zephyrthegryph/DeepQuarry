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
            &MapMemo::new(1, 0),
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
            memo.finish_revision();
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
            unchanged.finish_revision();
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
