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
        let include = frontend.plan.regions()[origin.region].occurrence;
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
    frontend.plan.ordinary_mut().unwrap().occurrences[0].semantic_path = Arc::from("changed-semantic-source-name");
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
    let source="/datum/probe\n\tvar/bare\n\tvar/array[2]\n\tvar/multi = list(\n\t\t1)\n/datum/probe\n\tmulti = null\n#define FIELD var/macro_decl\n/datum/probe\n\tFIELD\n/proc/point_tail()\n\treturn null\n";
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
    // This is a different, primary-issued token provenance API. The old strict
    // byte projection remains refused below.
    let point = archive.member_source_note_point(macro_decl).unwrap();
    assert_eq!((point.line, point.byte_column), (10, 7));
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
    // After an uninitialized variable, the original declaration lexer advances
    // to the next included token. The physical token may belong to a sibling
    // include or to a sibling of the returned parent.
    for (manifest, middle) in [
        ("#include \"part.dm\"\n#include \"next.dm\"\n", None),
        ("#include \"middle.dm\"\n#include \"next.dm\"\n", Some("#include \"part.dm\"\n")),
    ] {
        let mut files = vec![
            ("compat.dme", manifest),
            ("part.dm", "/datum/probe\n    var/item\n"),
            ("next.dm", "// genuine next source\n/datum/after\n    var/value = 1\n"),
        ];
        if let Some(middle) = middle { files.push(("middle.dm", middle)); }
        let frontend = build(&files);
        let archive = frontend.body_archive().unwrap();
        let tree = archive.tree();
        let owner = tree.lookup_type(SymbolId::of("/datum/probe")).unwrap();
        let member = tree.resolve(owner, SymbolId::of("item"), MemberKind::Var).unwrap();
        let cursor = archive.member_policy_compatibility_cursor(member).unwrap();
        assert_eq!(cursor.path.as_path(), Path::new("next.dm"));
        assert_eq!((cursor.line, cursor.byte_column, cursor.logical_boundary), (2, Some(1), false));
        if let Ok(ordinary) = archive.member_policy_point(member) {
            assert_eq!(ordinary.path.as_path(), Path::new("part.dm"),
                "continuation must not relabel the declaration's physical source");
            assert_ne!(cursor.path, ordinary.path);
        }
    }
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

#[test]fn original_checker_registered_paths_keep_entry_argument_and_strip_only_actual_environment_prefix(){
 struct Inputs{project:dm_preprocess::AcquiredSource,child:dm_preprocess::AcquiredSource}
 impl SourceProvider for Inputs{
  fn read(&self,_:&Path)->Result<String,String>{Err("requires original acquired bytes".into())}
  fn acquired_source(&self,path:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(Some(if path.file_name().unwrap()=="project.dme"{self.project.clone()}else{self.child.clone()}))}
  fn source_acquisition(&self,path:&Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{let source=if path.file_name().unwrap()=="project.dme"{&self.project}else{&self.child};source.lease().source_text().same_view(text).then(||source.clone())}
 }
 let root=std::env::current_dir().unwrap().join("checker-registration-coordinate");let project=root.join("project.dme");let child=root.join("part.dm");let source=format!("#include \"{}\"\n",child.to_string_lossy().replace('\\',"/"));
 let input=Inputs{project:dm_preprocess::AcquiredSource::from_original_bytes(source.as_bytes().to_vec(),()),child:dm_preprocess::AcquiredSource::from_original_bytes(b"/datum/point/proc/probe()\n    return 0\n".to_vec(),())};
 let absolute=build_with_config(&project,&input,&Default::default(),FrontendConfig{workers:1,engine:None,observer:None}).unwrap();let map=absolute.source_export_mapping().unwrap();assert_eq!(map.registered_checker_path(0).unwrap(),project.as_path());assert_eq!(map.registered_checker_path(1).unwrap(),Path::new("part.dm"));
 let relative=Path::new("checker-registration-coordinate/project.dme");let mut front=build_with_config(relative,&input,&Default::default(),FrontendConfig{workers:1,engine:None,observer:None}).unwrap();let map=front.source_export_mapping().unwrap();assert_eq!(map.registered_checker_path(0).unwrap(),relative);assert_eq!(map.registered_checker_path(1).unwrap(),child.as_path());
 let mut storage=Vec::new();map.original_checker_entry_storage(|p,n|storage.push((p,n)));assert_eq!(storage.len(),2);assert!(storage.iter().all(|(p,_)|*p!=0));
 front.plan.ordinary_mut().unwrap().occurrences[0]=absolute.plan.occurrences()[0].clone();assert!(front.source_export_mapping().is_none(),"same physical root/acquisition cannot relabel original FileList registration");
}

#[test]fn original_checker_registry_numbers_only_actual_dm_lexer_files_and_keeps_environment_registration_keys(){
 struct Files(std::collections::BTreeMap<PathBuf,dm_preprocess::AcquiredSource>);
 impl Files{fn key(path:&Path)->PathBuf{dm_preprocess::regions::canonical_path(&if path.is_absolute(){path.to_path_buf()}else{std::env::current_dir().unwrap().join(path)})}}
 impl SourceProvider for Files{
  fn read(&self,_:&Path)->Result<String,String>{Err("original acquisition required".into())}
  fn acquired_source(&self,path:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(self.0.get(&Self::key(path)).cloned())}
  fn source_acquisition(&self,path:&Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.get(&Self::key(path)).filter(|source|source.lease().source_text().same_view(text)).cloned()}
 }
 let root=std::env::current_dir().unwrap().join("original-file-numbering");let project=root.join("project.dme");let absolute=root.join("second.dm");
 let manifest=format!("#include \"skin.dmf\"\n#include \"world.dmm\"\n#include \"first.dm\"\n#include \"{}\"\n#include \"nested.dme\"\n",absolute.to_string_lossy().replace('\\',"/"));
 let entries=[("project.dme",manifest.as_str()),("skin.dmf",""),("world.dmm",""),("first.dm","/proc/first_registry()\n    return 0\n"),("second.dm","/proc/second_registry()\n    return 0\n"),("nested.dme","#include \"third.dm\"\n"),("third.dm","/proc/third_registry()\n    return 0\n")];
 let inputs=Files(entries.into_iter().map(|(path,text)|(dm_preprocess::regions::canonical_path(&root.join(path)),dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(),()))).collect());
 let make=|entry:&Path|build_with_config(entry,&inputs,&Default::default(),FrontendConfig{workers:1,engine:None,observer:None}).unwrap();
 let first=make(&project);let mapping=first.source_export_mapping().unwrap();
 for(actual,issued)in mapping.includes.iter().zip(first.plan.occurrences()){assert_eq!(actual.non_text_kind,issued.non_text_kind());assert_eq!(actual.logical_eof,issued.logical_eof_cursor().map(|cursor|(cursor.line(),cursor.encounter())));}
 for(name,kind)in [("world.dmm",dm_preprocess::regions::NonTextKind::Map),("skin.dmf",dm_preprocess::regions::NonTextKind::Skin)]{let row=mapping.includes.iter().find(|row|row.path.file_name().unwrap()==name).unwrap();assert_eq!(row.non_text_kind,Some(kind));assert!(row.logical_eof.is_none(),"typed nontext must not acquire a completed DM reader");}
let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let admission=dm_syntax::SettingAdmission::new(&counter,4*1024*1024,&poll);
 let registry=mapping.original_checker_source_registry(&admission).unwrap();
 assert!(registry.matches_mapping(mapping));assert!(counter.load(std::sync::atomic::Ordering::Acquire)>dm_syntax::SettingChargeCounter::root_allocation_bytes());
 assert_eq!(registry.files[0],1);
 for (name,id) in [("first.dm",2),("second.dm",3),("nested.dme",4),("third.dm",5)]{let ordinal=mapping.includes.iter().position(|row|row.path.file_name().unwrap()==name).unwrap();assert_eq!(registry.files[ordinal],id,"non-DM includes must not consume original FileId slots");}
 for origin in mapping.origins.iter(){let point=mapping.borrowed_source_note_point(origin.output_span.start).unwrap();let located=registry.location(origin.output_span.start).unwrap();assert_eq!((located.line as usize,located.byte_column as usize),(point.line,point.byte_column));}
 let same_bytes=make(&project);assert!(!registry.matches_mapping(same_bytes.source_export_mapping().unwrap()));
 drop(registry);assert_eq!(counter.load(std::sync::atomic::Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 let tiny=dm_syntax::SettingAdmission::new(&counter,dm_syntax::SettingChargeCounter::root_allocation_bytes() + (1),&poll);assert_eq!(mapping.original_checker_source_registry(&tiny).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(counter.load(std::sync::atomic::Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 let stopped=||Err(std::io::Error::from_raw_os_error(1450));let admission=dm_syntax::SettingAdmission::new(&counter,4*1024*1024,&stopped);assert_eq!(mapping.original_checker_source_registry(&admission).err().unwrap().raw_os_error(),Some(1450));assert_eq!(counter.load(std::sync::atomic::Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 let relative=PathBuf::from("original-file-numbering/project.dme");let other=make(&relative);let map=other.source_export_mapping().unwrap();assert_eq!(map.registered_checker_path(0).unwrap(),relative);let absolute_row=map.includes.iter().position(|row|row.path.file_name().unwrap()=="second.dm").unwrap();assert_eq!(map.registered_checker_path(absolute_row).unwrap(),absolute);
}

#[test]fn original_checker_relative_dot_registration_matches_actual_prepare_include_strip_boundary(){
 struct Files(std::collections::BTreeMap<PathBuf,dm_preprocess::AcquiredSource>);
 impl Files{fn key(path:&Path)->PathBuf{dm_preprocess::regions::canonical_path(&if path.is_absolute(){path.to_owned()}else{std::env::current_dir().unwrap().join(path)})}}
 impl SourceProvider for Files{fn read(&self,_:&Path)->Result<String,String>{Err("original acquisitions only".into())}fn acquired_source(&self,path:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(self.0.get(&Self::key(path)).cloned())}fn source_acquisition(&self,path:&Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.get(&Self::key(path)).filter(|source|source.lease().source_text().same_view(text)).cloned()}}
 let cwd=std::env::current_dir().unwrap();
 for entry in[cwd.join("checker-dot-registration/project.dme"),PathBuf::from("checker-dot-registration/project.dme"),PathBuf::from("./checker-dot-registration/project.dme"),PathBuf::from("checker-dot-entry.dme")]{
  let environment=entry.parent().unwrap();let operand=Path::new("./second.dm");let joined=environment.join(operand);let original=joined.strip_prefix(environment).unwrap_or(&joined);
  let inputs=Files([(Files::key(&entry),dm_preprocess::AcquiredSource::from_original_bytes(b"#include \"./second.dm\"\n".to_vec(),())),(Files::key(&joined),dm_preprocess::AcquiredSource::from_original_bytes(b"/proc/registry_dot_probe()\n    return 0\n".to_vec(),()))].into_iter().collect());
  let front=build_with_config(&entry,&inputs,&Default::default(),FrontendConfig{workers:1,engine:None,observer:None}).unwrap();let mapping=front.source_export_mapping().unwrap();assert_eq!(mapping.registered_checker_path(0).unwrap(),entry);assert_eq!(mapping.registered_checker_path(1).unwrap().as_os_str(),original.as_os_str(),"exact original registration spelling for {entry:?}");
 }
}

#[test]fn borrowed_callable_physical_path_keeps_owned_policy_origin_identity_without_arc_clone(){
 struct Original(dm_preprocess::AcquiredSource);impl SourceProvider for Original{fn read(&self,_:&Path)->Result<String,String>{Err("original bytes required".into())}fn acquired_source(&self,_:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(Some(self.0.clone()))}fn source_acquisition(&self,_:&Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.lease().source_text().same_view(text).then(||self.0.clone())}}
 let source=Original(dm_preprocess::AcquiredSource::from_original_bytes(b"/datum/probe/proc/read()\n    return 7\n".to_vec(),()));let front=build_with_config(Path::new("probe.dm"),&source,&Default::default(),FrontendConfig{workers:1,engine:None,observer:None}).unwrap();let archive=front.body_archive().unwrap();let tree=archive.tree();let owner=tree.lookup_type(SymbolId::of("/datum/probe")).unwrap();let member=tree.resolve(owner,SymbolId::of("read"),MemberKind::Proc).unwrap();let headers=archive.callable_header_source();let borrowed=headers.reported_point(member).unwrap();let(_,line,column)=borrowed.reported_coordinates();let owned=archive.callable_header_policy_origin(member).unwrap();assert_eq!(borrowed.physical_path(),owned.path.as_path());assert_eq!((line,column),(owned.line,owned.byte_column));assert_eq!(line,1);
}

#[test]fn actual_completed_reader_facts_participate_in_mapping_reuse_and_fingerprint(){
 struct Completed{extra:bool}impl SourceProvider for Completed{fn read(&self,path:&Path)->Result<String,String>{match path.file_name().and_then(|name|name.to_str()){Some("fixture.dme")=>Ok(if self.extra{"#include \"part.dm\"\n\n"}else{"#include \"part.dm\"\n"}.to_owned()),Some("part.dm")=>Ok("/datum/eof_reader/proc/read()\n    return 0\n".to_owned()),_=>Err("unexpected actual EOF fixture".into())}}}
 let make=|extra|build_with_config(Path::new("fixture.dme"),&Completed{extra},&Default::default(),FrontendConfig{workers:1,engine:None,observer:None}).unwrap();let mut first=make(false);let other=make(true);let mapping=Arc::clone(first.source_export_mapping().unwrap());let other_mapping=other.source_export_mapping().unwrap();assert!(mapping.admits(&first));assert_ne!(mapping.includes[0].logical_eof,other_mapping.includes[0].logical_eof);assert_ne!(mapping.coordinate_fingerprint(),other_mapping.coordinate_fingerprint());let old=&first.plan.occurrences()[0];let new=&other.plan.occurrences()[0];assert_eq!(old.path,new.path);assert_eq!(old.semantic_path,new.semantic_path);assert_eq!(old.parent,new.parent);assert_eq!(old.original_entry_path(),new.original_entry_path());assert_eq!(old.non_text_kind(),new.non_text_kind());first.plan.ordinary_mut().unwrap().occurrences[0]=new.clone();assert!(!mapping.admits(&first),"same original path cannot reuse coordinates after actual completed reader changes");assert!(first.source_export_mapping().is_none());
}
