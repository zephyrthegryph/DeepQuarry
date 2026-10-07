use crate::frontend::*;
use crate::MemberKind;
use dm_ir::SymbolId;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

struct Memory(BTreeMap<PathBuf, String>);
impl dm_preprocess::SourceProvider for Memory {
    fn read(&self, path: &Path) -> Result<String, String> {
        self.0
            .get(path)
            .cloned()
            .ok_or_else(|| "missing input".into())
    }
}
fn fixture(files: &[(&str, &str)]) -> Result<ColdFrontend, Vec<Diagnostic>> {
    let source = Memory(
        files
            .iter()
            .map(|(path, text)| (PathBuf::from(path), (*text).into()))
            .collect(),
    );
    build(Path::new("project.dme"), &source, &BTreeMap::new(), 2)
}

#[test]
fn manifest_member_context_resolves_to_real_types_with_current_origins() {
    let result = fixture(&[
        (
            "project.dme",
            "/datum/a\n#include \"a/../a/body.dm\"\n/datum/b\n#include \"b/body.dm\"\n",
        ),
        (
            "a/body.dm",
            "    var/file_value = __FILE__\n    var/line_value = __LINE__\n",
        ),
        (
            "b/body.dm",
            "    var/file_value = __FILE__\n    var/line_value = __LINE__\n",
        ),
    ])
    .unwrap();
    let tree = &result.snapshot.tree;
    let owner = tree.lookup_type(SymbolId::of("/datum/a")).unwrap();
    let member = tree
        .resolve(owner, SymbolId::of("file_value"), MemberKind::Var)
        .unwrap();
    let initializer = tree
        .member(member)
        .unwrap()
        .metadata
        .initializer
        .as_ref()
        .unwrap();
    assert_eq!(
        tree.symbols().text(initializer.tokens[0].text),
        Some("\"a/../a/body.dm\"")
    );
    let target = crate::Target::Member(member);
    let occurrence = result
        .snapshot
        .occurrences
        .get(result.snapshot.occurrences.for_target(target)[0])
        .unwrap();
    assert_eq!(
        result
            .source(occurrence.provenance.span.file)
            .unwrap()
            .path
            .as_path(),
        Path::new("a/body.dm")
    );
    assert_eq!(occurrence.provenance.include_occurrence, 1);
    assert!(result.bodies.is_empty());
}

#[test]
fn bodies_change_separately_from_semantics_and_keep_their_current_arena() {
    let make =
        |body| fixture(&[("project.dme", "#include \"body.dm\"\n"), ("body.dm", body)]).unwrap();
    let first = make("/datum/probe/proc/read(value = 3)\n    return 1\n");
    let second = make("/datum/probe/proc/read(value = 3)\n    return 222\n");
    assert_eq!(
        first.snapshot.tree.identity(),
        second.snapshot.tree.identity()
    );
    assert_eq!(first.bodies.len(), 1);
    assert_eq!(
        first.body(&first.bodies[0]).unwrap().children[0].header,
        "return 1"
    );
    assert_eq!(
        second.body(&second.bodies[0]).unwrap().children[0].header,
        "return 222"
    );
    assert_eq!(first.bodies[0].source.line, 1);
    assert_eq!(first.bodies[0].source.include_chain.as_ref(), &[0, 1]);
}

#[test]
fn source_errors_and_unimplemented_models_are_distinct() {
    let errors = fixture(&[
        ("project.dme", "#include \"child.dm\"\n"),
        ("child.dm", "#error observed_failure\n"),
    ])
    .unwrap_err();
    assert_eq!(errors[0].kind, DiagnosticKind::SourceError);
    assert_eq!(errors[0].stage, DiagnosticStage::Preprocess);
    assert_eq!(
        errors[0].location.as_ref().unwrap().include_chain.as_ref(),
        &[0, 1]
    );
    let unsupported = fixture(&[("project.dme", "#unknown_directive value\n")]).unwrap_err();
    assert_eq!(unsupported[0].kind, DiagnosticKind::UnsupportedModel);
}

#[test]
fn terminal_resource_domain_and_ordered_map_inputs_are_retained() {
    let result = fixture(&[
        ("project.dme", "#define FILE_DIR \"early\"\n#include \"child.dm\"\n#undef FILE_DIR\n#include \"world.dmm\"\n#include \"skin.dmf\"\n"),
        ("child.dm", "#define FILE_DIR \"late\"\nvar/asset = 'asset.txt'\n"),
    ]).unwrap();
    assert_eq!(result.plan.file_dirs, vec![PathBuf::from("early")]);
    assert_eq!(
        result.maps().collect::<Vec<_>>(),
        vec![Path::new("world.dmm")]
    );
    assert_eq!(
        result.skins().collect::<Vec<_>>(),
        vec![Path::new("skin.dmf")]
    );
    let world = result
        .files
        .iter()
        .find(|file| file.path.as_path() == Path::new("world.dmm"))
        .unwrap();
    assert!(!world.captured);
}

#[test]
fn captured_manifest_overrides_keep_encounter_precedence() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures/phase0/preprocess/manifest-order/proc-two-overrides/project.dme");
    let result = build(&root, &dm_preprocess::FileSystem, &BTreeMap::new(), 2).unwrap();
    let owner = result
        .snapshot
        .tree
        .lookup_type(SymbolId::of("/datum/probe"))
        .unwrap();
    let current = result
        .snapshot
        .tree
        .resolve(owner, SymbolId::of("read"), MemberKind::Proc)
        .unwrap();
    let chain = result.snapshot.tree.override_chain(current);
    let returns: Vec<_> = chain
        .iter()
        .map(|member| {
            let occurrence = result
                .bodies
                .iter()
                .find(|occurrence| occurrence.member == *member)
                .unwrap();
            result.body(occurrence).unwrap().children[0].header.clone()
        })
        .collect();
    assert_eq!(returns, vec!["return 2", "return 1", "return 0"]);
    assert_eq!(
        result.emission_order.len(),
        result.snapshot.occurrences.source_order().len()
    );
}

#[test]
fn bounded_parallel_chunks_preserve_declarations_bodies_and_diagnostics() {
    let mut text = String::new();
    for index in 0..140 {
        text.push_str(&format!(
            "/datum/probe/proc/read_{index}()\n    // {}\n    return {index}\n",
            "padding".repeat(150)
        ));
    }
    let provider = Memory(BTreeMap::from([(PathBuf::from("project.dme"), text)]));
    let serial = build(Path::new("project.dme"), &provider, &BTreeMap::new(), 1).unwrap();
    let parallel = build(Path::new("project.dme"), &provider, &BTreeMap::new(), 3).unwrap();
    assert_eq!(
        serial.snapshot.tree.identity(),
        parallel.snapshot.tree.identity()
    );
    assert_eq!(serial.emission_order, parallel.emission_order);
    assert_eq!(serial.bodies.len(), 140);
    for (left, right) in serial.bodies.iter().zip(parallel.bodies.iter()) {
        assert_eq!(left.expanded_span, right.expanded_span);
        assert_eq!(
            serial.body(left).unwrap().children.last().unwrap().header,
            parallel
                .body(right)
                .unwrap()
                .children
                .last()
                .unwrap()
                .header
        );
        assert_eq!(
            serial.location(left.expanded_span.start).unwrap().span,
            parallel.location(right.expanded_span.start).unwrap().span
        );
    }
    // One terminal quote cannot be closed by a later test declaration. Ordinary
    // quoted DM strings may span physical lines, so paired opening quotes would
    // accidentally create one legal multiline literal.
    let broken = Memory(BTreeMap::from([(
        PathBuf::from("project.dme"),
        "/datum/a/proc/read()\n    return \"unterminated".into(),
    )]));
    let errors = |workers| match build(Path::new("project.dme"), &broken, &BTreeMap::new(), workers)
    {
        Err(errors) => errors,
        Ok(_) => panic!("unterminated terminal string was accepted"),
    };
    let serial = errors(1);
    let parallel = errors(3);
    assert!(serial
        .iter()
        .any(|error| error.kind == DiagnosticKind::SourceError
            && error.stage == DiagnosticStage::Syntax
            && error.message.contains("unterminated")));
    assert_eq!(
        serial
            .iter()
            .map(|error| (
                &error.message,
                error.location.as_ref().map(|location| location.line)
            ))
            .collect::<Vec<_>>(),
        parallel
            .iter()
            .map(|error| (
                &error.message,
                error.location.as_ref().map(|location| location.line)
            ))
            .collect::<Vec<_>>()
    );
}

#[test]
fn explicit_engine_seed_keeps_intrinsic_metadata_and_source_origins_separate() {
    use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver};
    let mut symbols = dm_ir::SymbolTable::default();
    for name in [
        "/",
        "/datum",
        "/engine",
        "/engine/base",
        "engine_call",
        "native_value",
    ] {
        symbols.intern(name).unwrap();
    }
    let seed = EngineSeed {
        identity: 0x1234,
        symbols,
        hierarchy: crate::EngineHierarchy {
            schema: 0x516,
            parents: vec![
                (SymbolId::of("/"), None),
                (SymbolId::of("/datum"), Some(SymbolId::of("/"))),
                (SymbolId::of("/engine"), Some(SymbolId::of("/"))),
                (SymbolId::of("/engine/base"), Some(SymbolId::of("/datum"))),
            ],
        },
        fields: Arc::from([]),
        intrinsics: vec![
            crate::IntrinsicMember {
                owner: SymbolId::of("/engine/base"),
                name: SymbolId::of("engine_call"),
                kind: MemberKind::Proc,
                shared_owner: None,
                instance_storage_proven: false,
            },
            crate::IntrinsicMember {
                owner: SymbolId::of("/engine/base"),
                name: SymbolId::of("native_value"),
                kind: MemberKind::Var,
                shared_owner: None,
                instance_storage_proven: false,
            },
        ]
        .into(),
    };
    let provider = Memory(BTreeMap::from([(PathBuf::from("project.dme"),
        "/custom\n    parent_type = /engine/base\n    var/value = 3\n    proc/read()\n        return value\n".into())]));
    let result = build_with_config(
        Path::new("project.dme"),
        &provider,
        &BTreeMap::new(),
        FrontendConfig {
            workers: 2,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let tree = &result.snapshot.tree;
    let custom = tree.lookup_type(SymbolId::of("/custom")).unwrap();
    assert_eq!(
        tree.type_node(tree.parent(custom).unwrap()).unwrap().path,
        SymbolId::of("/engine/base")
    );
    assert_eq!(tree.members().len(), 2);
    assert_eq!(
        tree.declarations().len(),
        result.snapshot.occurrences.source_order().len()
    );
    assert!(result
        .snapshot
        .occurrences
        .source_order()
        .iter()
        .all(|occurrence| result
            .source(occurrence.provenance.span.file)
            .unwrap()
            .path
            .as_path()
            == Path::new("project.dme")));
    assert_eq!(result.bodies.len(), 1);
    assert_eq!(
        result.body(&result.bodies[0]).unwrap().children[0].header,
        "return value"
    );
    let known = ResolveQuery::HasMemberProc {
        owner: SymbolId::of("/custom"),
        name: SymbolId::of("engine_call"),
    };
    assert_eq!(
        Resolver::resolve(tree.as_ref(), known),
        ResolvedMeaning::Presence(true)
    );
    let typed = ResolveQuery::Proc {
        owner: SymbolId::of("/custom"),
        name: SymbolId::of("engine_call"),
        verb: false,
    };
    assert!(matches!(
        Resolver::resolve(tree.as_ref(), typed),
        ResolvedMeaning::Unsupported(_)
    ));
    let status = result.engine.unwrap();
    assert_eq!(status.identity, seed.identity);
    assert!(!status.member_catalog_complete);
    assert!(!status.typed_member_metadata_decoded);
    let override_source = Memory(BTreeMap::from([(
        PathBuf::from("project.dme"),
        "/engine/base\n    native_value = 9\n".into(),
    )]));
    let errors = match build_with_config(
        Path::new("project.dme"),
        &override_source,
        &BTreeMap::new(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    ) {
        Err(errors) => errors,
        Ok(_) => panic!("opaque intrinsic override acquired fabricated typed metadata"),
    };
    assert_eq!(errors[0].kind, DiagnosticKind::UnsupportedModel);
}

#[test]
fn opaque_intrinsic_field_bases_preserve_authored_values_without_inventing_metadata() {
    use dm_ir::{DeclaredTypeKnowledge, OpaqueFieldBase, ResolveQuery, ResolvedMeaning, Resolver};
    let mut symbols = dm_ir::SymbolTable::default();
    for text in ["/", "/datum", "/engine", "/engine/base", "native_value"] {
        symbols.intern(text).unwrap();
    }
    let base = OpaqueFieldBase {
        owner: SymbolId::of("/engine/base"),
        name: SymbolId::of("native_value"),
        declared_type: DeclaredTypeKnowledge::Known(SymbolId::of("/datum")),
    };
    let seed = EngineSeed {
        identity: 11,
        symbols,
        hierarchy: crate::EngineHierarchy {
            schema: 22,
            parents: vec![
                (SymbolId::of("/"), None),
                (SymbolId::of("/datum"), Some(SymbolId::of("/"))),
                (SymbolId::of("/engine"), Some(SymbolId::of("/"))),
                (SymbolId::of("/engine/base"), Some(SymbolId::of("/datum"))),
            ],
        },
        intrinsics: vec![crate::IntrinsicMember {
            owner: base.owner,
            name: base.name,
            kind: MemberKind::Var,
            shared_owner: None,
            instance_storage_proven: false,
        }]
        .into(),
        fields: vec![base.clone()].into(),
    };
    let source=Memory(BTreeMap::from([(PathBuf::from("project.dme"),
        "/custom\n    parent_type = /engine/base\n    native_value = 9\n/custom/child\n    native_value = 10\n".into())]));
    let model = build_with_config(
        Path::new("project.dme"),
        &source,
        &BTreeMap::new(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    assert_eq!(model.snapshot.tree.members().len(), 2);
    for (owner, value) in [("/custom", "9"), ("/custom/child", "10")] {
        let ty = model
            .snapshot
            .tree
            .lookup_type(SymbolId::of(owner))
            .unwrap();
        let member = model
            .snapshot
            .tree
            .resolve(ty, base.name, MemberKind::Var)
            .unwrap();
        let metadata = &model.snapshot.tree.member(member).unwrap().metadata;
        assert_eq!(metadata.inherited_opaque.as_ref(), Some(&base));
        assert_eq!(metadata.declared_type, Some(SymbolId::of("/datum")));
        assert_eq!(
            metadata
                .initializer
                .as_ref()
                .unwrap()
                .source_text(model.snapshot.tree.symbols())
                .as_deref(),
            Some(value)
        );
        let query = ResolveQuery::Var {
            owner: SymbolId::of(owner),
            name: base.name,
        };
        assert_eq!(
            Resolver::resolve(model.snapshot.tree.as_ref(), query),
            ResolvedMeaning::Unsupported(query)
        );
        let query = ResolveQuery::StaticVar {
            owner: SymbolId::of(owner),
            name: base.name,
        };
        assert_eq!(
            Resolver::resolve(model.snapshot.tree.as_ref(), query),
            ResolvedMeaning::Unsupported(query)
        );
    }
    assert_eq!(
        model.snapshot.occurrences.source_order().len(),
        model.snapshot.tree.declarations().len()
    );
}

#[test]
fn progress_observer_reports_actual_uncached_stage_order() {
    let events = std::cell::RefCell::new(Vec::new());
    let observer = |event: FrontendProgress| events.borrow_mut().push(event);
    let source = Memory(BTreeMap::from([(
        PathBuf::from("project.dme"),
        "/datum/probe\n    var/value = 3\n".into(),
    )]));
    let model = build_with_config(
        Path::new("project.dme"),
        &source,
        &BTreeMap::new(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: Some(&observer),
        },
    )
    .unwrap();
    assert!(model.engine.is_none());
    let stages = events
        .borrow()
        .iter()
        .filter(|event| event.kind == ProgressKind::Started)
        .map(|event| event.stage)
        .collect::<Vec<_>>();
    assert_eq!(
        stages,
        vec![
            FrontendStage::DirectivePlanning,
            FrontendStage::Expansion,
            FrontendStage::SourceIndexing,
            FrontendStage::DeclarationParsing,
            FrontendStage::DeclarationOrigins,
            FrontendStage::TreeResolution,
            FrontendStage::BodyIndexing
        ]
    );
    assert_eq!(
        events
            .borrow()
            .iter()
            .filter(|event| event.kind == ProgressKind::Completed)
            .count(),
        stages.len()
    );
    assert!(events
        .borrow()
        .iter()
        .any(|event| event.stage == FrontendStage::DeclarationParsing
            && event.kind == ProgressKind::Advanced));
}
