use super::*;

#[test]
fn captured_generator_defaults_preserve_markers_and_native_equality_partition() {
    use sha2::{Digest, Sha256};
    let receipt: serde_json::Value = serde_json::from_slice(include_bytes!(
        "../../../../../fixtures/native_compiler/generator_defaults/receipt.json"
    ))
    .unwrap();
    let decode: serde_json::Value = serde_json::from_slice(include_bytes!(
        "../../../../../fixtures/native_compiler/generator_defaults/decode-receipt.json"
    ))
    .unwrap();
    let source =
        include_bytes!("../../../../../fixtures/native_compiler/generator_defaults/generator.dm");
    let manifest =
        include_bytes!("../../../../../fixtures/native_compiler/generator_defaults/generator.dme");
    let bytes = include_bytes!(
        "../../../../../fixtures/native_compiler/generator_defaults/probe.native.bin"
    );
    for (input, expected) in [
        (source.as_slice(), &receipt["inputs"]["generator.dm"]),
        (manifest.as_slice(), &receipt["inputs"]["generator.dme"]),
        (bytes.as_slice(), &receipt["outputs"]["dmb"]["sha256"]),
    ] {
        assert_eq!(
            format!("{:x}", Sha256::digest(input)),
            expected.as_str().unwrap()
        );
    }
    assert_eq!(
        format!(
            "{:x}",
            Sha256::digest(include_bytes!(
                "../../../../../fixtures/native_compiler/generator_defaults/receipt.json"
            ))
        ),
        decode["capture_receipt_sha256"].as_str().unwrap()
    );
    assert_eq!(
        receipt["compiler_sha256"],
        "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0"
    );
    assert_eq!(receipt["byond"]["exit_code"], 0);
    assert_eq!(receipt["byond"]["timed_out"], false);
    assert_eq!(receipt["version_banner_verified"], true);
    let native = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
    let class = native
        .classes
        .iter()
        .position(|class| {
            native.string(class.path_string_id()) == Some(b"/particles/token_families".as_slice())
        })
        .unwrap();
    let mut expected = std::collections::BTreeMap::new();
    for initial in native.class_initial_values(class).unwrap() {
        let variable = &native.variables[initial.variable_id as usize];
        let name = std::str::from_utf8(native.string(variable.name).unwrap()).unwrap();
        if ["position", "velocity", "drift"].contains(&name) {
            assert_eq!(initial.value.tag(), 62);
            assert_eq!(
                u64::from(initial.value.id()),
                decode["observed_defaults"][name]["data"].as_u64().unwrap()
            );
            expected.insert(name.to_owned(), initial.value.id());
        }
    }
    assert_eq!(expected.len(), 3);
    struct Source(String);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(self.0.clone())
        }
    }
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
        std::path::Path::new("generator.dme"),
        &Source(std::str::from_utf8(source).unwrap().to_owned()),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let (pinned, _scalar) =
        crate::request_runner::runner_facts::prepare(&frontend, &engine).unwrap();
    let startup = crate::startup::capture(&frontend).unwrap();
    let symbols = startup.plan().symbols.as_ref();
    let writes = &startup.plan().writes;
    assert_eq!(writes.len(), 3, "exact captured source assignments");
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &pinned,
        symbols,
    };
    let captured = crate::initializer_policy::EngineCapturedEvaluator {
        engine: &engine,
        evaluator: &evaluator,
    };
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let classified = crate::initializer_policy::classify_with_token_mode_on_executor(
        writes,
        symbols,
        captured.parallel_evaluator().unwrap(),
        false,
        &executor,
    )
    .unwrap();
    let actual: Vec<_> = classified
        .writes
        .iter()
        .map(|write| {
            assert!(write.phase.is_some() && write.runtime_value.is_some());
            let crate::initializer_policy::DefaultValue::InitializerExpression { token, .. } =
                &write.default
            else {
                panic!("generator default lost its marker")
            };
            *token
        })
        .collect();
    let names = ["position", "velocity", "drift"];
    for a in 0..3 {
        for b in 0..3 {
            assert_eq!(
                expected[names[a]] == expected[names[b]],
                actual[a] == actual[b]
            );
        }
    }
}

#[test]
fn generator_runtime_arguments_and_missing_argument_do_not_issue_markers() {
    let mut symbols = SymbolTable::default();
    let write = InitializerWrite {
        source_site: dm_ir::InitializerSite::Declaration,
        target: dm_ir::InitializerTarget::Shared {
            slot: SymbolId::of("slot"),
            owner: SymbolId::of("/"),
            name: SymbolId::of("probe"),
        },
        lexical_owner: SymbolId::of("/"),
        lexical_procedure: None,
        value: dm_ir::InitializerValue::NoAuthoredValue,
        declared_array: None,
        declaration_flags: Some(8),
    };
    symbols.intern("/list").unwrap();
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &Host,
        symbols: &symbols,
    };
    for source in ["generator()", "generator(runtime_value())"] {
        let ast = dm_syntax::parse_expression(source).expr.unwrap();
        assert!(construction_key(&ast, source, &write, &symbols, &evaluator)
            .unwrap()
            .is_none());
    }
}
