use super::*;
use dm_ir::SymbolId;
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

#[test]
fn primary_variable_cursor_survives_normalization_reopens_and_shifted_current_source() {
    use dm_ir::SymbolId;
    struct Bytes(dm_preprocess::AcquiredSource);
    impl SourceProvider for Bytes {
        fn read(&self, _: &Path) -> Result<String, String> {
            Err("requires original bytes".into())
        }
        fn acquired_source(
            &self,
            _: &Path,
        ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
            Ok(Some(self.0.clone()))
        }
        fn source_acquisition(
            &self,
            _: &Path,
            text: &dm_preprocess::SourceText,
        ) -> Option<dm_preprocess::AcquiredSource> {
            self.0
                .lease()
                .source_text()
                .same_view(text)
                .then(|| self.0.clone())
        }
    }
    fn build_input(source: &str) -> ColdFrontend {
        build_with_config(
            Path::new("probe.dm"),
            &Bytes(dm_preprocess::AcquiredSource::from_original_bytes(
                source.as_bytes().to_vec(),
                (),
            )),
            &Default::default(),
            FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
        )
        .unwrap()
    }
    let source="/datum/probe\n    var/\n        item = list(\n            1)\n        second\n/datum/probe\n    second = 2\n#define FIELD var/third\n/datum/probe\n    FIELD\n";
    let frontend = build_input(source);
    let archive = frontend.body_archive().unwrap();
    let tree = archive.tree();
    let owner = tree.lookup_type(SymbolId::of("/datum/probe")).unwrap();
    let item = tree
        .resolve(owner, SymbolId::of("item"), MemberKind::Var)
        .unwrap();
    let latest = tree
        .resolve(owner, SymbolId::of("second"), MemberKind::Var)
        .unwrap();
    let declared = tree
        .override_chain_iter(latest)
        .find(|id| tree.member(*id).unwrap().definition == crate::DefinitionMode::Declare)
        .unwrap();
    let third = tree
        .resolve(owner, SymbolId::of("third"), MemberKind::Var)
        .unwrap();
    assert_eq!(archive.member_policy_line(item).unwrap().line, 3);
    assert_eq!(archive.member_policy_line(declared).unwrap().line, 5);
    assert_eq!(archive.member_policy_line(latest).unwrap().line, 7);
    assert_eq!(archive.member_policy_line(third).unwrap().line, 10);
    let same = build_input(source);
    assert!(!archive.matches_tree(same.snapshot.tree.as_ref()));
    let shifted = build_input(&format!("// shifted header\n{source}"));
    assert_ne!(
        frontend.source_export_revision(),
        shifted.source_export_revision()
    );
    let current = shifted.body_archive().unwrap();
    let t = current.tree();
    let ty = t.lookup_type(SymbolId::of("/datum/probe")).unwrap();
    assert_eq!(
        current
            .member_policy_line(
                t.resolve(ty, SymbolId::of("item"), MemberKind::Var)
                    .unwrap()
            )
            .unwrap()
            .line,
        4
    );
    assert_eq!(archive.member_policy_line(item).unwrap().line, 3);
    let mut replaced = build_input(source);
    let text = dm_preprocess::SourceText::from(replaced.files[0].text.as_str().to_owned());
    Arc::make_mut(&mut replaced.files)[0].text = text;
    assert!(
        replaced.source_export_mapping().is_none(),
        "equal bytes do not mint current primary provenance"
    );
}

#[test]
fn primary_variable_points_use_exact_tokens_and_never_line_only_macro_columns() {
    use dm_ir::SymbolId;
    struct Bytes(dm_preprocess::AcquiredSource);
    impl SourceProvider for Bytes {
        fn read(&self, _: &Path) -> Result<String, String> {
            Err("requires original bytes".into())
        }
        fn acquired_source(
            &self,
            _: &Path,
        ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
            Ok(Some(self.0.clone()))
        }
        fn source_acquisition(
            &self,
            _: &Path,
            text: &dm_preprocess::SourceText,
        ) -> Option<dm_preprocess::AcquiredSource> {
            self.0
                .lease()
                .source_text()
                .same_view(text)
                .then(|| self.0.clone())
        }
    }
    let source="/datum/probe\n\tvar/bare\n\tvar/array[2]\n\tvar/multi = list(\n\t\t1)\n/datum/probe\n\tmulti = null\n#define FIELD var/macro_decl\n/datum/probe\n\tFIELD\n";
    let f = build_with_config(
        Path::new("points.dm"),
        &Bytes(dm_preprocess::AcquiredSource::from_original_bytes(
            source.as_bytes().to_vec(),
            (),
        )),
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
    )
    .unwrap();
    let archive = f.body_archive().unwrap();
    let tree = archive.tree();
    let owner = tree.lookup_type(SymbolId::of("/datum/probe")).unwrap();
    for (name, line, column) in [("bare", 2, 10), ("array", 3, 14)] {
        let id = tree
            .resolve(owner, SymbolId::of(name), MemberKind::Var)
            .unwrap();
        let point = archive.member_policy_point(id).unwrap();
        assert_eq!((point.line, point.byte_column), (line, column));
    }
    let latest = tree
        .resolve(owner, SymbolId::of("multi"), MemberKind::Var)
        .unwrap();
    let formal = tree
        .override_chain_iter(latest)
        .find(|id| tree.member(*id).unwrap().definition == crate::DefinitionMode::Declare)
        .unwrap();
    let first = archive.member_policy_point(formal).unwrap();
    assert_eq!((first.line, first.byte_column), (4, 12));
    let overridden = archive.member_policy_point(latest).unwrap();
    assert_eq!((overridden.line, overridden.byte_column), (7, 8));
    let macro_decl = tree
        .resolve(owner, SymbolId::of("macro_decl"), MemberKind::Var)
        .unwrap();
    assert_eq!(archive.member_policy_line(macro_decl).unwrap().line, 10);
    assert!(
        archive.member_policy_point(macro_decl).is_err(),
        "a proven macro line is not a proven byte column"
    );
}

#[test]
fn declaration_policy_cursor_uses_issued_include_eof_without_fabricating_byte_points() {
    struct Files(std::collections::BTreeMap<PathBuf, dm_preprocess::AcquiredSource>);
    impl SourceProvider for Files {
        fn read(&self, _: &Path) -> Result<String, String> {
            Err("original acquisition required".into())
        }
        fn acquired_source(
            &self,
            path: &Path,
        ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
            Ok(self.0.get(path).cloned())
        }
        fn source_acquisition(
            &self,
            path: &Path,
            text: &dm_preprocess::SourceText,
        ) -> Option<dm_preprocess::AcquiredSource> {
            self.0
                .get(path)
                .filter(|source| source.lease().source_text().same_view(text))
                .cloned()
        }
    }
    fn build_mode(project: &str, files: &[(&str, &str)], active: bool) -> ColdFrontend {
        let files = Files(
            files
                .iter()
                .map(|(path, text)| {
                    (
                        PathBuf::from(path),
                        dm_preprocess::AcquiredSource::from_original_slice(text.as_bytes(), ()),
                    )
                })
                .collect(),
        );
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        super::super::build_with_executor_and_semantic_state_for_policy(
            Path::new(project),
            &files,
            &Default::default(),
            FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
            None,
            &executor,
            None,
            active,
        )
        .unwrap()
    }
    fn build(files: &[(&str, &str)]) -> ColdFrontend {
        build_mode("compat.dme", files, true)
    }
    for tail in [
        "var/item",
        "var/item[3]",
        "var/item // tail",
        "var/item\n",
        "#define DECL var/item\n/datum/probe\n    DECL\n",
    ] {
        let source = if tail.starts_with('#') {
            tail.to_owned()
        } else {
            format!("/datum/probe\n    {tail}")
        };
        let frontend = build(&[
            ("compat.dme", "#include \"part.dm\"\n"),
            ("part.dm", &source),
        ]);
        let archive = frontend.body_archive().unwrap();
        let tree = archive.tree();
        let owner = tree.lookup_type(SymbolId::of("/datum/probe")).unwrap();
        let member = tree
            .resolve(owner, SymbolId::of("item"), MemberKind::Var)
            .unwrap();
        let cursor = archive.member_policy_compatibility_cursor(member).unwrap();
        assert_eq!(cursor.path.as_path(), Path::new("compat.dme"));
        assert_eq!(
            (cursor.line, cursor.byte_column, cursor.logical_boundary),
            (2, Some(1), true)
        );
        if !tail.ends_with('\n') {
            assert!(
                archive.member_policy_point(member).is_err(),
                "logical boundary cannot become an original byte point"
            );
        }
    }
    let ordinary = build_mode(
        "compat.dme",
        &[
            ("compat.dme", "#include \"part.dm\"\n"),
            ("part.dm", "/datum/probe\n    var/item = 1\n"),
        ],
        false,
    );
    let archive = ordinary.body_archive().unwrap();
    let tree = archive.tree();
    let owner = tree.lookup_type(SymbolId::of("/datum/probe")).unwrap();
    let member = tree
        .resolve(owner, SymbolId::of("item"), MemberKind::Var)
        .unwrap();
    assert!(
        archive.member_policy_point(member).is_ok(),
        "ordinary strict physical API still works"
    );
    assert!(archive
        .member_policy_compatibility_cursor(member)
        .err()
        .unwrap()
        .contains("not requested"));
    for (project, files) in [
        ("root.dm", vec![("root.dm", "/datum/probe\n    var/item")]),
        (
            "compat.dme",
            vec![
                ("compat.dme", "#include \"part.dm\""),
                ("part.dm", "/datum/probe\n    var/item\n"),
            ],
        ),
    ] {
        let frontend = build_mode(project, &files, true);
        let archive = frontend.body_archive().unwrap();
        let tree = archive.tree();
        let owner = tree.lookup_type(SymbolId::of("/datum/probe")).unwrap();
        let member = tree
            .resolve(owner, SymbolId::of("item"), MemberKind::Var)
            .unwrap();
        assert!(
            archive.member_policy_compatibility_cursor(member).is_err(),
            "unterminated root does not prove next-line column1"
        );
    }
    let assigned = build(&[
        ("compat.dme", "#include \"part.dm\"\n"),
        ("part.dm", "/datum/probe\n    var/item = 1"),
    ]);
    let archive = assigned.body_archive().unwrap();
    let tree = archive.tree();
    let owner = tree.lookup_type(SymbolId::of("/datum/probe")).unwrap();
    let member = tree
        .resolve(owner, SymbolId::of("item"), MemberKind::Var)
        .unwrap();
    let cursor = archive.member_policy_compatibility_cursor(member).unwrap();
    assert_eq!(cursor.path.as_path(), Path::new("part.dm"));
    assert!(!cursor.logical_boundary);
    for (manifest, middle) in [
        ("#include \"middle.dm\"\n", "#include \"part.dm\"\n"),
        (
            "#include \"middle.dm\"\n#include \"middle.dm\"\n",
            "#ifndef ONCE\n#define ONCE 1\n#include \"part.dm\"\n#endif\n",
        ),
    ] {
        let frontend = build(&[
            ("compat.dme", manifest),
            ("middle.dm", middle),
            ("part.dm", "/datum/probe\n    var/item\n"),
        ]);
        let archive = frontend.body_archive().unwrap();
        let tree = archive.tree();
        let owner = tree.lookup_type(SymbolId::of("/datum/probe")).unwrap();
        let member = tree
            .resolve(owner, SymbolId::of("item"), MemberKind::Var)
            .unwrap();
        let cursor = archive.member_policy_compatibility_cursor(member).unwrap();
        assert_eq!(cursor.path.as_path(), Path::new("compat.dme"));
        assert_eq!(
            (cursor.line, cursor.byte_column),
            (manifest.lines().count() + 1, Some(1))
        );
    }
}
