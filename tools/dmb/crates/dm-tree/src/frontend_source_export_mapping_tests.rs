use super::*;
struct Source;
impl SourceProvider for Source {
    fn read(&self, path: &Path) -> Result<String, String> {
        match path.file_name().and_then(|name|name.to_str()) {
            Some("fixture.dme")=>Ok("#include \"part.dm\"\n".into()),
            Some("part.dm")=>Ok("#define OWNER /datum/example\n#define VALUE 7\nOWNER\n    proc/read()\n        return VALUE\n".into()),
            _=>Err("unexpected fixture input".into()),
        }
    }
}
#[test]
fn current_source_mapping_is_lazy_shared_and_keeps_exact_macro_include_coordinates() {
    let mut frontend = build_with_config(
        Path::new("fixture.dme"),
        &Source,
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
    )
    .unwrap();
    let mapping = Arc::clone(frontend.source_export_mapping().unwrap());
    assert!(mapping.locations_if_issued().is_none());
    assert!(Arc::ptr_eq(
        &mapping,
        frontend.source_export_mapping().unwrap()
    ));
    let mut expected = HashMap::new();
    for origin in frontend.expanded.origins.iter() {
        let include = frontend.plan.regions[origin.region].occurrence;
        expected
            .entry((include, origin.source_span.start))
            .or_insert(origin.output_span.start);
    }
    for (index, occurrence) in frontend
        .snapshot
        .occurrences
        .source_order()
        .iter()
        .enumerate()
    {
        let provenance = &occurrence.provenance;
        let old = expected
            .get(&(
                provenance.include_occurrence as usize,
                provenance.span.start as usize,
            ))
            .and_then(|offset| frontend.location(*offset));
        assert_eq!(mapping.location(OccurrenceId(index as u32)), old.as_ref());
    }
    let locations = Arc::clone(mapping.locations_if_issued().unwrap());
    assert!(locations
        .iter()
        .flatten()
        .any(|location| location.include_chain.len() == 2));
    assert!(locations
        .iter()
        .flatten()
        .any(|location| !location.macro_expansions.is_empty()));
    assert!(Arc::ptr_eq(
        &locations,
        mapping.locations_if_issued().unwrap()
    ));
    frontend.plan.occurrences[0].semantic_path = Arc::from("changed-semantic-source-name");
    assert!(frontend.source_export_mapping().is_none());
    // An old admitted reader owns its exact immutable coordinates; current
    // compatibility mutation cannot edit or relabel that captured projection.
    drop(frontend);
    assert!(Arc::ptr_eq(
        &locations,
        mapping.locations_if_issued().unwrap()
    ));
    assert!(mapping.files.upgrade().is_none());
    assert!(mapping.tree.upgrade().is_none());
    let current = build_with_config(
        Path::new("fixture.dme"),
        &Source,
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
    )
    .unwrap();
    let lazy = Arc::clone(current.source_export_mapping().unwrap());
    assert!(lazy.locations_if_issued().is_none());
    drop(current);
    assert!(lazy.location(OccurrenceId(0)).is_some());
    let mut replaced = build_with_config(
        Path::new("fixture.dme"),
        &Source,
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
    )
    .unwrap();
    replaced.expanded.text = "different current expanded input".into();
    assert!(replaced.source_export_mapping().is_none());
}
