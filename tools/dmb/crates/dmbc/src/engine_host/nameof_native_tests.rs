//! Reflection controls use the actual pinned engine and current source issuer.
use super::*;
#[test]
fn native_computed_nameof_receivers_use_semantic_selection() {
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/obj/probe\n/proc/probe(world/W, list/L, icon/I)\n    return 1\n".into())
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
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("project.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
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
}
