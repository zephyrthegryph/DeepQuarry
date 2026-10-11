//! Reflection controls use the actual pinned engine and current source issuer.
use super::*;
#[test]
fn native_computed_nameof_receivers_use_semantic_selection() {
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/obj/probe\n/proc/probe(world/W, list/L, icon/I)\n    return 1\n/datum/base/proc/known()\n    return 1\n/datum/base/child\n".into())
        }
    }
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let seed = engine.frontend_seed();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let mut semantic = dm_tree::frontend::RetainedSemanticTree::default();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state(
        Path::new("project.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
        None,
        &executor,
        Some(&mut semantic),
    )
    .unwrap();
    let mut symbols = frontend.snapshot.tree.symbols().clone();
    let constants = ConstantCatalog::native_516_1687(&mut symbols).unwrap();
    let runtime = RuntimeAliasCatalog::new(
        engine.identity(),
        &symbols,
        Vec::new(),
        frontend
            .snapshot
            .tree
            .types()
            .iter()
            .map(|node| node.path)
            .collect(),
        Completeness::Partial,
    )
    .unwrap();
    let unpinned = EngineResolverHost::new(
        frontend.snapshot.tree.clone(),
        constants.clone(),
        runtime.clone(),
    );
    let host = EngineResolverHost::new(frontend.snapshot.tree.clone(), constants, runtime)
        .with_pinned_variables(&engine, &frontend)
        .unwrap();
    let bindings = dm_codegen_byond::LowerBindings {
        parameters: vec!["W".into(), "L".into(), "I".into()],
        parameter_types: [
            ("W".into(), "/world".into()),
            ("L".into(), "/list".into()),
            ("I".into(), "/icon".into()),
        ]
        .into_iter()
        .collect(),
        ..Default::default()
    };
    for source in ["world.cpu", "W.cpu", "L.len", "/obj::icon"] {
        let expression = dm_syntax::parse_expression(source).expr.unwrap();
        let facts = dm_codegen_byond::observe_reference_source_features(
            &expression,
            &bindings,
            &symbols,
            &host,
        )
        .unwrap_or_else(|error| panic!("{source}: {error:?}"));
        assert_eq!(
            facts.world_cpu,
            source == "world.cpu" || source == "W.cpu",
            "{source}"
        );
        assert_eq!(facts.native_graphics, source == "/obj::icon", "{source}");
    }
    let bindings = dm_codegen_byond::LowerBindings {
        current_type_path: Some("/datum/base/child".into()),
        ..Default::default()
    };
    for source in [
        ".proc/known",
        "/datum/base/child.proc/known",
        "/datum/base.proc/known",
    ] {
        let expression = dm_syntax::parse_expression(source).expr.unwrap();
        let recorder = dm_session::RecordingResolver::new(&host);
        dm_codegen_byond::observe_reference_source_features(
            &expression,
            &bindings,
            &symbols,
            &recorder,
        )
        .unwrap_or_else(|error| panic!("{source}: {error:?}"));
        let reads = recorder.reads();
        assert!(
            reads
                .iter()
                .any(|read| matches!(read.query, Q::MethodProcedureValue { .. })),
            "{source}"
        );
        assert!(
            !reads
                .iter()
                .any(|read| matches!(read.query, Q::Type(path) if path == SymbolId::of(source))),
            "{source}"
        );
    }
    let root_bindings = dm_codegen_byond::LowerBindings {
        current_type_path: Some("/".into()),
        ..Default::default()
    };
    for source in [
        "/datum/actually_absent",
        "/datum/base/proc/actually_absent",
        "/datum/base::actually_absent",
        "actually_absent",
    ] {
        let expression = dm_syntax::parse_expression(source).expr.unwrap();
        let error = dm_codegen_byond::observe_reference_source_features(
            &expression,
            &root_bindings,
            &symbols,
            &host,
        )
        .unwrap_err();
        assert_eq!(
            error.kind,
            dm_codegen_byond::LowerErrorKind::SourceError,
            "{source}: {error:?}"
        );
        let error = dm_codegen_byond::observe_reference_source_features(
            &expression,
            &root_bindings,
            &symbols,
            &unpinned,
        )
        .unwrap_err();
        assert_eq!(
            error.kind,
            dm_codegen_byond::LowerErrorKind::UnsupportedModel,
            "{source}: {error:?}"
        );
    }
    assert_eq!(
        host.resolve(Q::Type(SymbolId::of("/list"))),
        M::Symbol(SymbolId::of("/list"))
    );
    assert!(
        matches!(
            host.resolve(Q::MethodProcedureValue {
                owner: SymbolId::of("/list"),
                name: SymbolId::of("Copy"),
                verb: false,
            }),
            M::Unsupported(_)
        ),
        "catalog-excluded native methods cannot become false absence"
    );
}
