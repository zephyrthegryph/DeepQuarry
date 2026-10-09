use crate::frontend::*;
use crate::MemberKind;
use dm_ir::SymbolId;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

struct Memory(BTreeMap<PathBuf, String>);

#[test]
fn prepared_sources_share_capture_and_line_indexes_with_frontend() {
    use dm_preprocess::regions::prepared_source::PreparedSources;
    use std::sync::Arc;
    let text: Arc<str> =
        Arc::from("/datum/probe\n    var/a = 2\n    proc/read()\n        return a\n");
    let prepared = PreparedSources::prepare([(PathBuf::from("project.dme"), text)], 2).unwrap();
    let source = prepared.get(Path::new("project.dme")).unwrap();
    let frontend = build(Path::new("project.dme"), &prepared, &BTreeMap::new(), 2).unwrap();
    let file = frontend
        .files
        .iter()
        .find(|file| file.path.as_path() == Path::new("project.dme"))
        .unwrap();
    assert!(file.captured);
    assert!(Arc::ptr_eq(&file.text, source.original()));
    assert!(Arc::ptr_eq(&file.line_starts, source.line_starts()));
    assert_eq!(
        frontend
            .location(frontend.bodies[0].expanded_span.start)
            .unwrap()
            .line,
        3
    );
}
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
fn preprocessing_diagnostic_kind_is_independent_of_user_message_prefix() {
    let errors = match fixture(&[("project.dme",
        "#error unsupported authored message\n#include \"script.dms\"\n#unimplemented_probe\n#include not_quoted\n")]) {
        Ok(_) => panic!("preprocessing failures must reject the frontend"),
        Err(errors) => errors,
    };
    assert_eq!(errors.len(), 4);
    assert_eq!(
        errors.iter().map(|error| error.kind).collect::<Vec<_>>(),
        vec![
            DiagnosticKind::SourceError,
            DiagnosticKind::UnsupportedModel,
            DiagnosticKind::UnsupportedModel,
            DiagnosticKind::SourceError
        ]
    );
    assert_eq!(errors[0].message.trim_end(), "unsupported authored message");
    assert_eq!(errors[1].message, "unverified include extension");
    assert_eq!(
        errors[2].message,
        "unsupported preprocessor directive #unimplemented_probe"
    );
    for (index, error) in errors.iter().enumerate() {
        let origin = error
            .location
            .as_ref()
            .expect("actual directive source location");
        assert_eq!(origin.line, index + 1);
        assert_eq!(origin.semantic_path.as_ref(), "project.dme");
    }
}

#[test]
fn parent_resolution_errors_point_to_authored_cause_not_later_reopen() {
    let errors = fixture(&[
        (
            "project.dme",
            "#include \"first.dm\"\n#include \"second.dm\"\n#include \"reopen.dm\"\n",
        ),
        (
            "first.dm",
            "/datum/a\n/datum/b\n/datum/child\n    parent_type = /datum/a\n",
        ),
        ("second.dm", "/datum/child\n    parent_type = /datum/b\n"),
        ("reopen.dm", "/datum/child\n    var/example\n"),
    ])
    .unwrap_err();
    let error = errors
        .iter()
        .find(|error| error.message.contains("ConflictingParent"))
        .unwrap();
    assert_eq!(
        error.location.as_ref().unwrap().path.as_path(),
        Path::new("second.dm")
    );
    let errors = fixture(&[
        ("project.dme", "#include \"child.dm\"\n"),
        (
            "child.dm",
            "/datum/child\n    parent_type = /not_declared\n",
        ),
    ])
    .unwrap_err();
    let error = errors
        .iter()
        .find(|error| error.message.contains("MissingParent"))
        .unwrap();
    assert_eq!(
        error.location.as_ref().unwrap().path.as_path(),
        Path::new("child.dm")
    );
}
#[test]
fn nested_settings_lexical_identity_and_include_origins_survive_body_compaction() {
    let make = |guard: &str, body: &str| {
        let text = format!("    if ({guard})\n        set waitfor = 0\n        return {body}\n    else\n        set background = 1\n");
        fixture(&[
            ("project.dme", "/proc/p()\n#include \"settings.dm\"\n"),
            ("settings.dm", &text),
        ])
        .unwrap_or_else(|errors| panic!("{errors:?}"))
    };
    let first = make("1", "1");
    let body_edit = make("1", "222");
    let guard_edit = make("0", "1");
    assert_eq!(
        first.snapshot.tree.identity(),
        body_edit.snapshot.tree.identity()
    );
    assert_eq!(
        first.snapshot.tree.identity(),
        guard_edit.snapshot.tree.identity()
    );
    let procedure = first
        .snapshot
        .tree
        .members()
        .iter()
        .find_map(|member| member.metadata.procedure.as_ref())
        .unwrap();
    assert_eq!(procedure.settings.len(), 2);
    assert!(procedure
        .settings
        .iter()
        .all(|node| matches!(node, dm_ir::ProcedureSettingNode::Setting(_))));
    let origins = &first.bodies[0].setting_context_origins;
    assert_eq!(origins.len(), 4);
    assert!(origins
        .iter()
        .all(|origin| origin.path.as_path() == Path::new("settings.dm")
            && origin.include_occurrence == 1));
    assert_eq!(
        origins.iter().map(|origin| origin.line).collect::<Vec<_>>(),
        vec![1, 2, 4, 5]
    );
    let compact = &first.syntax.items[0].children;
    assert_eq!(compact.len(), 2);
    assert_eq!(compact[0].children.len(), 1);
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
#[test]
fn declaration_skeleton_matches_full_grammar_and_setting_compaction() {
    for source in [
        "/datum/x\n    var/list/a = list(1, 2)\n    proc/read(a = 1)\n        if(a)\n            return 1\n        else if(2)\n            set name = \"Other\"\n        else\n            return 3\n        while(a)\n            set hidden = 1\n        return a\n/datum/y\n    parent_type = /datum/x\n",
        "/proc/p() { if(1) { return 2; } else { set name = \"A\"; } return 3; }\n",
        "/proc/p()\n    // set name = fake\n    var/text = {\"multi\nset name = fake\n\"}\n    if(1)\n        if(2)\n            set desc = \"real\"\n        else\n            return 3\n    else\n        return 4\n    return 5\n",
        "/datum/x { var/list/x = list(/datum/y {name = \"Y\"}); proc/read() {return 1;} }\n",
        "/datum/x\n    proc/read()\n        for(var/x in list(1, 2))\n            x++\n        try\n            return 1\n        catch(var/exception/e)\n            set name = \"Error\"\n",
        "/proc/p()\n    if(1)\n        return 1\n    return 2\n    else\n        set name = \"Unattached\"\n",
        "/datum/é\n    var/icon = 'résource.dmi'\n    proc/p()\n        set name = @\"raw [not interpolation]\"\n        return \"quoted [list(\"nested\")]\"\n",
        "/proc/p()\n    return \"unterminated\n",
    ] {
        let full = dm_syntax::parse(source);
        let skeleton = dm_syntax::parse_declaration_skeleton(source);
        assert_eq!(skeleton.diagnostics, full.diagnostics, "{source}");
        assert_eq!(
            skeleton.tokens,
            full.tokens.iter().map(|token| dm_syntax::SpanToken {kind: token.kind, span: token.span}).collect::<Vec<_>>(),
            "{source}"
        );
        for (span, owned) in skeleton.tokens.iter().zip(&full.tokens) {
            assert_eq!(span.text(source), owned.text);
        }
        assert_eq!(
            super::compact_declarations(skeleton.items, 0),
            super::compact_declarations(full.items, 0),
            "{source}"
        );
    }
}

#[test]
fn compact_body_preserves_setting_inputs_and_rejects_foreign_occurrences() {
    let frontend = fixture(&[("project.dme", "/proc/probe()\n    if(1)\n        set name = \"display\"\n        return 7\n    else\n        set desc = \"fallback\"\n    return 9\n")]).unwrap();
    let occurrence = &frontend.bodies[0];
    let compact = frontend.compact_body(occurrence).unwrap();
    let full = frontend.body(occurrence).unwrap();
    let mut compact_symbols = dm_ir::SymbolTable::default();
    let mut full_symbols = dm_ir::SymbolTable::default();
    assert_eq!(
        crate::settings::extract_settings(&compact.children, &mut compact_symbols).unwrap(),
        crate::settings::extract_settings(&full.children, &mut full_symbols).unwrap(),
    );
    let stripped = crate::settings::strip_setting_items(compact.children.clone());
    assert_eq!(stripped.len(), 2);
    assert_eq!(stripped[0].header, "if(1)");
    assert_eq!(stripped[1].header, "else");
    assert!(stripped.iter().all(|item| item.children.is_empty()));
    assert!(!crate::settings::strip_setting_items(full.children).is_empty());
    assert!(!occurrence.setting_context_origins.is_empty());
    let mut forged = occurrence.clone();
    forged.expanded_span.end -= 1;
    assert!(frontend.compact_body(&forged).is_err());
}

#[test]
fn parsed_body_receipts_reject_other_issuers_and_public_capture_replacement() {
    let make = || fixture(&[("project.dme", "/proc/probe()\n    return 7\n")]).unwrap();
    let frontend = make();
    let input = frontend.body_input(&frontend.bodies[0]).unwrap();
    assert_eq!(input.source(), "/proc/probe()\n    return 7");
    assert_eq!(
        input.compact(),
        frontend.compact_body(&frontend.bodies[0]).unwrap()
    );
    frontend
        .validate_body_input(&input, &frontend.bodies[0])
        .unwrap();
    let parsed = frontend.parse_body(&frontend.bodies[0]).unwrap();
    assert_eq!(parsed.item(), &frontend.body(&frontend.bodies[0]).unwrap());
    frontend
        .validate_parsed_body(&parsed, &frontend.bodies[0])
        .unwrap();
    let foreign = make();
    assert!(foreign
        .validate_body_input(&input, &foreign.bodies[0])
        .is_err());
    assert!(foreign
        .validate_parsed_body(&parsed, &foreign.bodies[0])
        .is_err());
    let mut changed_arena = frontend.clone();
    changed_arena.expanded.text = Arc::from("/proc/probe()\n    return 9\n");
    assert!(changed_arena.parse_body(&changed_arena.bodies[0]).is_err());
    assert!(changed_arena.body_input(&changed_arena.bodies[0]).is_err());
    let mut changed_syntax = frontend.clone();
    changed_syntax.syntax = Arc::new((*frontend.syntax).clone());
    assert!(changed_syntax
        .body_input(&changed_syntax.bodies[0])
        .is_err());
    assert!(changed_syntax
        .compact_body(&changed_syntax.bodies[0])
        .is_err());
}

#[test]
fn procedure_literals_issue_exact_formal_and_effective_occurrences() {
    use dm_ir::{
        ProcedureIdentity, ResolveQuery as Q, ResolvedMeaning as M, Resolver, SemanticValue,
    };
    let provider = Memory(BTreeMap::from([(PathBuf::from("project.dme"),
        "/proc/callback()\n    return 1\nvar/const/cb = /proc/callback\n/datum/base/proc/callback()\n    return 1\n/datum/base/callback()\n    return 2\n/datum/child\n    parent_type = /datum/base\n".into())]));
    let frontend = build(Path::new("project.dme"), &provider, &BTreeMap::new(), 2).unwrap();
    let tree = frontend.snapshot.tree.as_ref();
    let name = SymbolId::of("callback");
    let owner = SymbolId::of("/datum/base");
    for (formal, occurrence) in [(true, 0), (false, 1)] {
        assert_eq!(
            Resolver::resolve(
                tree,
                Q::ProcedureValue {
                    owner,
                    name,
                    verb: false,
                    formal
                }
            ),
            M::Value(SemanticValue::Procedure(ProcedureIdentity {
                owner,
                name,
                verb: false,
                occurrence
            }))
        );
    }
    // Native controls reject child/proc/callback even with an own implicit override.
    let query = Q::ProcedureValue {
        owner: SymbolId::of("/datum/child"),
        name,
        verb: false,
        formal: true,
    };
    assert!(!matches!(Resolver::resolve(tree, query), M::Value(_)));
    let scalar = crate::constant_resolution::resolve(
        &frontend.snapshot,
        &[crate::constant_resolution::ScalarQuery::Const {
            owner: SymbolId::of("/"),
            name: SymbolId::of("cb"),
        }],
        &crate::constant_resolution::ScalarBackend {
            identity: 1,
            decode_string: &|_| None,
            nameof: &|_| None,
        },
    );
    assert_eq!(
        scalar.outcome(crate::constant_resolution::ScalarQuery::Const {
            owner: SymbolId::of("/"),
            name: SymbolId::of("cb")
        }),
        Some(&crate::constant_resolution::ScalarOutcome::Value(
            SemanticValue::Procedure(ProcedureIdentity {
                owner: SymbolId::of("/"),
                name,
                verb: false,
                occurrence: 0
            })
        ))
    );
}

#[path = "frontend_parser_tests.rs"]
mod parser_receipts;

#[test]
fn borrowed_executor_reuses_frontend_workers_across_requests() {
    let mut text = String::new();
    for index in 0..140 {
        text.push_str(&format!(
            "/datum/probe/proc/read_{index}()\n    // {}\n    return {index}\n",
            "padding".repeat(150)
        ));
    }
    let provider = Memory(BTreeMap::from([(PathBuf::from("project.dme"), text)]));
    let reference = build(Path::new("project.dme"), &provider, &BTreeMap::new(), 1).unwrap();
    let executor = dm_exec::BuildExecutor::new(3).unwrap();
    for _ in 0..2 {
        let result = build_with_executor(
            Path::new("project.dme"),
            &provider,
            &BTreeMap::new(),
            FrontendConfig {
                workers: 99,
                engine: None,
                observer: None,
            },
            None,
            &executor,
        )
        .unwrap();
        assert_eq!(
            reference.snapshot.tree.identity(),
            result.snapshot.tree.identity()
        );
        assert_eq!(reference.emission_order, result.emission_order);
        assert_eq!(reference.bodies.len(), result.bodies.len());
        for (left, right) in reference.bodies.iter().zip(result.bodies.iter()) {
            assert_eq!(left.expanded_span, right.expanded_span);
            assert_eq!(
                reference.location(left.expanded_span.start).unwrap().span,
                result.location(right.expanded_span.start).unwrap().span
            );
        }
    }
    assert_eq!(executor.workers(), 3);
}
