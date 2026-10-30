//! Production lower_one boundary: real prepared ABI, original source and same Db.
use super::*;
use std::path::Path;
struct Source(dm_preprocess::AcquiredSource);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("fixture requires original acquisition".into())
    }
    fn acquired_source(&self, _: &Path) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
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
macro_rules! native {
    ($source:expr, |$front:ident,$host:ident,$startup:ident,$policy:ident| $body:block) => {{
        let engine = crate::engine::EngineSnapshot::from_bytes(
            include_bytes!("../../../../fixtures/native_template.bin"),
            1,
        )
        .unwrap()
        .with_bootstrap_catalog()
        .unwrap();
        let seed = engine.frontend_seed();
        let source = Source(dm_preprocess::AcquiredSource::from_original_bytes(
            $source.as_bytes().to_vec(),
            (),
        ));
        let queries = Arc::new(crate::query_db::QueryDb::default());
        let settings = Arc::clone(&queries) as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;
        let $front = dm_tree::frontend::build_with_config(
            Path::new("original-callers.dme"),
            &source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap()
        .with_setting_expression_queries(&settings)
        .unwrap()
        .with_body_queries(queries);
        let ($host, _) = crate::request_runner::runner_facts::prepare(&$front, &engine).unwrap();
        let $startup = crate::startup::capture(&$front).unwrap();
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        let abi =
            crate::driver_facts::prepare_pinned_source_abi_with_startup_on_executor_with_artifacts(
                &$front, &engine, &$host, &$startup, None, &executor, None,
            )
            .unwrap();
        let $policy =
            crate::driver_facts::FrozenPreparedPolicy::new(&$front, &abi.prepared).unwrap();
        $body
    }};
}
#[test]
fn actual_lower_one_original_formals_cover_typed_automatic_and_warm() {
    for (source, helpers) in [
        ("/proc/p(x=1+2,y=x+4)\n    return y\n", false),
        ("/proc/p(x=1,y in list(x,2))\n    return x\n", true),
    ] {
        native!(source, |front, host, startup, policy| {
            assert_eq!(front.bodies.len(), 1);
            let occurrence = &front.bodies[0];
            let original = Arc::clone(front.parse_body(occurrence).unwrap().parameter_storage());
            let mut baseline: Option<LoweredUnit> = None;
            // BodyArena::new selects the actual automatic-body branch. Typed
            // arenas select the original statements branch, with/without refs.
            for typed in [true, false] {
                for references in [false, true] {
                    for _warm in 0..2 {
                        let arena = if typed {
                            dm_tree::frontend::BodyArena::new_typed(
                                &front,
                                dm_codegen_byond::typed_statements_supported_for_capture,
                            )
                        } else {
                            dm_tree::frontend::BodyArena::new(&front)
                        };
                        let actual = match lower_one(
                            &front,
                            occurrence,
                            &host,
                            &policy,
                            Some(&startup),
                            &arena,
                            references,
                            None,
                        ) {
                            Ok(unit) => unit,
                            Err(errors) => {
                                panic!("typed={typed} references={references}: {errors:?}")
                            }
                        };
                        assert!(actual.abi.is_some(), "must use actual prepared ABI");
                        assert_eq!(!actual.source_helpers.is_empty(), helpers);
                        assert!(
                            actual
                                .source_helpers
                                .iter()
                                .all(|helper| helper.original_root.is_some()),
                            "ordinary caller must choose original-root helpers"
                        );
                        assert!(
                            Arc::ptr_eq(
                                &original,
                                front.parse_body(occurrence).unwrap().parameter_storage()
                            ),
                            "caller/warm lookup must retain SAME original signature owner"
                        );
                        if let Some(expected) = baseline.as_ref() {
                            assert_eq!(actual.code.procedure, expected.code.procedure);
                            assert_eq!(actual.source_helpers.len(), expected.source_helpers.len());
                            for (a, b) in actual.source_helpers.iter().zip(&expected.source_helpers)
                            {
                                assert_eq!(a.code.procedure, b.code.procedure);
                                assert_eq!(a.original_root, b.original_root);
                                assert_eq!(a.debug_origins, b.debug_origins);
                            }
                        } else {
                            baseline = Some(actual);
                        }
                    }
                }
            }
        });
    }
}
#[test]
fn actual_lower_one_helper_failure_is_current_and_not_a_compatibility_retry() {
    for padding in ["", "\n\n"] {
        let source = format!("{padding}/proc/p(x in y,y)\n    return 1\n");
        native!(source, |front, host, startup, policy| {
            let occurrence = &front.bodies[0];
            let parsed = front.parse_body(occurrence).unwrap();
            let metadata = front
                .snapshot
                .tree
                .member(occurrence.member)
                .unwrap()
                .metadata
                .procedure
                .as_deref()
                .unwrap();
            let identity = source_unit_identity(&front, occurrence).unwrap().identity;
            let context = AbiContext {
                identity,
                symbols: startup.plan().symbols.as_ref(),
                origin: &occurrence.source,
                resolver: &host,
            };
            // Genuine ABI preparation succeeds and emits one argument-source
            // helper; this is not an earlier ABI/body rejection. The unchanged
            // compatibility helper independently pins its actual error wording.
            let prepared = policy
                .prepare_captured(metadata, &parsed, &context)
                .unwrap();
            assert!(prepared
                .inputs
                .parameter_defaults
                .iter()
                .all(Option::is_none));
            let abi = prepared.abi.as_ref().unwrap();
            assert_eq!(abi.source_helpers.len(), 1);
            assert_eq!(abi.source_helpers[0].argument, 0);
            let compatibility = match crate::argument_sources::lower_helpers(
                crate::argument_sources::HelperInputs {
                    frontend: &front,
                    parsed: parsed.item().into(),
                    metadata,
                    owner: identity,
                    inputs: prepared.inputs.as_ref(),
                    helpers: &abi.source_helpers,
                    symbols: context.symbols,
                },
                &host,
            )
            .err()
            .expect("independent old helper must reject later-formal read")
            {
                crate::argument_sources::HelperFailure::Diagnostics(errors) => errors,
                other => panic!("expected real old helper source diagnostic: {other:?}"),
            };
            assert_eq!(compatibility.len(), 1);
            assert_eq!(compatibility[0].kind, DiagnosticKind::SourceError);
            assert_eq!(compatibility[0].message, "invalid variable");
            for typed in [true, false] {
                let arena = if typed {
                    dm_tree::frontend::BodyArena::new_typed(
                        &front,
                        dm_codegen_byond::typed_statements_supported_for_capture,
                    )
                } else {
                    dm_tree::frontend::BodyArena::new(&front)
                };
                let errors = lower_one(
                    &front,
                    occurrence,
                    &host,
                    &policy,
                    Some(&startup),
                    &arena,
                    false,
                    None,
                )
                .err()
                .expect("later formal must remain refused");
                assert!(!errors.is_empty());
                assert!(
                    errors
                        .iter()
                        .all(|e| e.origin.line == occurrence.source.line),
                    "current original header origin: {errors:?}"
                );
                assert_eq!(errors.len(), compatibility.len());
                for (actual, old) in errors.iter().zip(&compatibility) {
                    assert_eq!(actual.kind, old.kind);
                    assert_eq!(actual.message, old.message);
                    assert_eq!(actual.identity, old.identity);
                    assert_eq!(actual.origin.path, old.origin.path);
                    assert_eq!(actual.origin.semantic_path, old.origin.semantic_path);
                    assert_eq!(actual.origin.line, old.origin.line);
                    assert_eq!(actual.origin.span, old.origin.span);
                    assert_eq!(
                        actual.origin.include_occurrence,
                        old.origin.include_occurrence
                    );
                    assert!(actual.related.is_empty() && old.related.is_empty());
                }
            }
        });
    }
}
#[test]
fn actual_lower_one_optional_default_root_refusal_does_not_fallback_to_text() {
    let source = format!("/proc/p(x={}1)\n    return x\n", "!".repeat(300));
    native!(source, |front, host, startup, policy| {
        let occurrence = &front.bodies[0];
        assert!(
            front.parse_body(occurrence).is_ok(),
            "optional root refusal must not reject body"
        );
        for typed in [true, false] {
            let arena = if typed {
                dm_tree::frontend::BodyArena::new_typed(
                    &front,
                    dm_codegen_byond::typed_statements_supported_for_capture,
                )
            } else {
                dm_tree::frontend::BodyArena::new(&front)
            };
            let errors = lower_one(
                &front,
                occurrence,
                &host,
                &policy,
                Some(&startup),
                &arena,
                false,
                None,
            )
            .err()
            .expect("unsupported original default must not retry legacy text compiler");
            assert!(
                errors
                    .iter()
                    .any(|e| matches!(e.kind, DiagnosticKind::UnsupportedModel)),
                "explicit root-admission refusal: {errors:?}"
            );
        }
    });
}

#[test]
fn actual_lower_one_absolute_header_type_declaration_preserves_heal_formal_slots() {
    let source="/mob/living\n/datum/affliction/contagion/engineered\n/datum/viral_trait/heal/proc/Heal(mob/living/M, /datum/affliction/contagion/engineered/A, actual_power = 1)\n    return 1\n";
    native!(source, |front, host, startup, policy| {
        assert_eq!(front.bodies.len(), 1);
        let occurrence = &front.bodies[0];
        assert!(front
            .snapshot
            .tree
            .lookup_type(dm_ir::SymbolId::of(
                "/datum/affliction/contagion/engineered/A"
            ))
            .is_some());
        let metadata = front
            .snapshot
            .tree
            .member(occurrence.member)
            .unwrap()
            .metadata
            .procedure
            .as_deref()
            .unwrap();
        assert_eq!(
            metadata
                .signature
                .parameters
                .iter()
                .map(|p| front.snapshot.tree.symbols().text(p.name).unwrap())
                .collect::<Vec<_>>(),
            ["M", "actual_power"]
        );
        let parsed = front.parse_body(occurrence).unwrap();
        let view = parsed.source_parameters().unwrap();
        assert_eq!(
            view.entries()
                .unwrap()
                .iter()
                .map(|p| (view.name(p).unwrap(), p.ordinal()))
                .collect::<Vec<_>>(),
            [("M", 0), ("actual_power", 1)]
        );
        assert_eq!(parsed.source_header_expressions().unwrap().len(), 2);
        assert!(parsed
            .source_header_expressions()
            .unwrap()
            .default(1)
            .unwrap()
            .is_some());
        for typed in [true, false] {
            let arena = if typed {
                dm_tree::frontend::BodyArena::new_typed(
                    &front,
                    dm_codegen_byond::typed_statements_supported_for_capture,
                )
            } else {
                dm_tree::frontend::BodyArena::new(&front)
            };
            let unit = lower_one(
                &front,
                occurrence,
                &host,
                &policy,
                Some(&startup),
                &arena,
                false,
                None,
            )
            .unwrap();
            assert_eq!(unit.code.procedure.argument_names, ["M", "actual_power"]);
            assert!(unit.abi.is_some());
        }
    });
}

#[test]
fn actual_lower_one_return_annotation_preserves_words_and_prepared_default_abi_across_modes() {
    let mut expected: Option<LoweredUnit> = None;
    for annotation in ["", " as /datum"] {
        let source = format!("/proc/p(x=1){annotation}\n    return x\n");
        native!(source, |front, host, startup, policy| {
            assert_eq!(front.bodies.len(), 1);
            let occurrence = &front.bodies[0];
            for typed in [false, true] {
                for _warm in 0..2 {
                    let arena = if typed {
                        dm_tree::frontend::BodyArena::new_typed(
                            &front,
                            dm_codegen_byond::typed_statements_supported_for_capture,
                        )
                    } else {
                        dm_tree::frontend::BodyArena::new(&front)
                    };
                    let actual = lower_one(
                        &front,
                        occurrence,
                        &host,
                        &policy,
                        Some(&startup),
                        &arena,
                        false,
                        None,
                    )
                    .unwrap_or_else(|errors| {
                        panic!("actual return annotation/default caller: {errors:?}")
                    });
                    let abi = actual.abi.as_ref().expect("actual original prepared ABI");
                    if let Some(old) = &expected {
                        assert_eq!(
                            actual.code.procedure, old.code.procedure,
                            "annotation has no return coercion or runtime body effect"
                        );
                        let old_abi = old.abi.as_ref().unwrap();
                        assert_eq!(abi.layout, old_abi.layout);
                        assert_eq!(abi.argument_sources, old_abi.argument_sources);
                        assert_eq!(abi.source_helpers, old_abi.source_helpers);
                        assert_eq!(actual.source_helpers.len(), old.source_helpers.len());
                    } else {
                        expected = Some(actual);
                    }
                }
            }
        });
    }
}
