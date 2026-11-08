use super::*;
use dm_ir::{ExpressionToken, Parameter, ProcedureSetting, ProcedureSignature};
use dm_syntax::{Span, TokenKind};
fn expression(text: &str, symbols: &mut SymbolTable) -> SymbolicExpression {
    SymbolicExpression {
        tokens: dm_syntax::lex(text)
            .tokens
            .into_iter()
            .filter(|token| {
                !matches!(
                    token.kind,
                    TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
                )
            })
            .map(|token| ExpressionToken {
                kind: token.kind,
                text: symbols.intern(&token.text).unwrap(),
                relative_span: token.span,
            })
            .collect::<Vec<_>>()
            .into(),
    }
}
fn metadata(
    settings: &[(&str, SettingOperation, &str)],
    symbols: &mut SymbolTable,
) -> ProcedureMetadata {
    ProcedureMetadata {
        signature: ProcedureSignature {
            parameters: Vec::new().into(),
            variadic: false,
            return_annotation: None,
        },
        settings: settings
            .iter()
            .map(|(name, operation, value)| {
                ProcedureSettingNode::Setting(ProcedureSetting {
                    name: symbols.intern(name).unwrap(),
                    operation: *operation,
                    value: expression(value, symbols),
                })
            })
            .collect::<Vec<_>>()
            .into(),
    }
}
fn evaluate(value: &SymbolicExpression, symbols: &SymbolTable) -> Result<SemanticValue, AbiError> {
    match expression_text(value, symbols)?.as_str() {
        "null" => Ok(SemanticValue::Null),
        "0" => Ok(SemanticValue::NumberBits(0f32.to_bits())),
        "1" => Ok(SemanticValue::NumberBits(1f32.to_bits())),
        "\"Visible\"" => Ok(SemanticValue::Text(b"Visible".as_slice().into())),
        _ => Err(fail("uncaptured constant")),
    }
}
#[test]
fn explicit_usr_centered_view_verb_matches_observed_byond_metadata() {
    let mut symbols = SymbolTable::default();
    let metadata = metadata(
        &[("src", SettingOperation::In, "view(usr, 1)")],
        &mut symbols,
    );
    let ast = dm_syntax::parse("/obj/verb/v()\n    set src in view(usr, 1)\n    return\n");
    let result = prepare_procedure(
        &metadata,
        &symbols,
        &ast.items[0].children,
        ProcedureInputs::default(),
        InheritedAbi::Fresh,
        |v| evaluate(v, &symbols),
    )
    .unwrap();
    // Frozen DeepQuarry BYOND procs #35350 and #31737 both have kind1,
    // parameter1 and flags4: an in source must not set the assignment bit.
    assert_eq!(
        (result.layout.source_kind, result.layout.source_parameter),
        (1, 1)
    );
    assert_eq!(result.layout.flags, 4);
    assert_eq!(result.executable_body.len(), 1);
    assert_eq!(
        source_mode("view(usr,1)", false).unwrap(),
        source_mode("view(1)", false).unwrap()
    );
    assert!(source_mode("view(usr,256)", false).is_err());
    assert!(source_mode("view(src,1)", false).is_err());
    assert_eq!(source_mode("view(usr,1)", true).unwrap(), None);
}
#[test]
fn null_category_and_world_source_use_pinned_metadata_policy() {
    let mut symbols = SymbolTable::default();
    let metadata = metadata(
        &[
            ("category", SettingOperation::Assign, "null"),
            ("src", SettingOperation::In, "world"),
            ("invisibility", SettingOperation::Assign, "0"),
        ],
        &mut symbols,
    );
    let ast=dm_syntax::parse("/obj/verb/v()\n    set category = null\n    set src in world\n    set invisibility = 0\n    return\n");
    let result = prepare_procedure(
        &metadata,
        &symbols,
        &ast.items[0].children,
        ProcedureInputs::default(),
        InheritedAbi::Fresh,
        |v| evaluate(v, &symbols),
    )
    .unwrap();
    assert_eq!(result.layout.category, Category::Null);
    assert_eq!(result.layout.flags, 0x2c);
    assert_eq!(
        (result.layout.source_kind, result.layout.source_parameter),
        (16, 127)
    );
    assert_eq!(result.layout.encoded_flags(), (0xac, Some((0xac, 255))));
    assert_eq!(result.executable_body.len(), 1);
}
#[test]
fn typed_parameter_and_symbolic_source_helper_keep_argument_frame() {
    let mut symbols = SymbolTable::default();
    let mut metadata = metadata(&[], &mut symbols);
    metadata.signature.parameters = vec![Parameter::new(
        symbols.intern("count").unwrap(),
        None,
        None,
        0,
        Span::new(0, 1),
    ).with_tail(dm_ir::ParameterTail {
        default: Some(expression("1", &mut symbols)),
        input_annotation: Some(expression("num | null", &mut symbols)),
        source_expression: Some(expression("list(count)", &mut symbols)),
        ..Default::default()
    })]
    .into();
    let result = prepare_procedure(
        &metadata,
        &symbols,
        &[],
        ProcedureInputs::default(),
        InheritedAbi::Fresh,
        |_| Err(fail("unused")),
    )
    .unwrap();
    assert_eq!(result.inputs.parameter_type_flags, [136]);
    assert!(result.inputs.parameter_value_sources.is_empty());
    assert_eq!(
        result.argument_sources,
        [ArgumentSource::Helper { argument: 0 }]
    );
    assert_eq!(result.inputs.parameter_defaults, [Some("1".into())]);
    assert_eq!(result.source_helpers[0].argument, 0);
    assert_eq!(result.source_helpers[0].frame_parameters, ["count"]);
}
#[test]
fn typed_list_formals_keep_lexical_list_and_authored_element_input_flags() {
    let mut symbols = SymbolTable::default();
    let mut metadata = metadata(&[], &mut symbols);
    let list = symbols.intern("/list").unwrap();
    metadata.signature.parameters = ["/atom", "/atom/movable", "/obj", "/mob", "/datum/item"]
        .into_iter()
        .enumerate()
        .map(|(index, element)| Parameter::new(
            symbols.intern(&format!("values{index}")).unwrap(),
            Some(list),
            Some(symbols.intern(element).unwrap()),
            0,
            Span::new(0, 1),
        ))
        .collect::<Vec<_>>()
        .into();
    let prepared = prepare_procedure(
        &metadata,
        &symbols,
        &[],
        ProcedureInputs::default(),
        InheritedAbi::Fresh,
        |_| Err(fail("unused")),
    )
    .unwrap();
    // Authenticated DeepQuarry structural comparison observes 0x123 for
    // try_infect_crossed(list/atom/old_locs), while the lexical type is /list.
    assert_eq!(prepared.inputs.parameter_type_flags, [0x123, 3, 2, 1, 0]);
    for name in &prepared.inputs.parameters {
        assert_eq!(prepared.inputs.parameter_types[name], "/list");
    }

    let mut parameters = metadata.signature.parameters.to_vec();
    parameters[0].input_annotation = Some(expression("num|null", &mut symbols));
    metadata.signature.parameters = parameters.into();
    let annotated = prepare_procedure(
        &metadata,
        &symbols,
        &[],
        ProcedureInputs::default(),
        InheritedAbi::Fresh,
        |_| Err(fail("unused")),
    )
    .unwrap();
    assert_eq!(annotated.inputs.parameter_type_flags[0], 0x88);
    assert_eq!(annotated.inputs.parameter_types["values0"], "/list");
}
#[test]
fn typed_unsized_formals_keep_list_lexical_type_and_element_restrictions() {
    let mut symbols = SymbolTable::default();
    let mut metadata = metadata(&[], &mut symbols);
    let list = symbols.intern("/list").unwrap();
    metadata.signature.parameters = ["/obj", "/mob", "/datum/item"]
        .into_iter()
        .enumerate()
        .map(|(index, element)| Parameter::new(
            symbols.intern(&format!("values{index}")).unwrap(),
            Some(list),
            None,
            0,
            Span::new(0, 1),
        ).with_tail(dm_ir::ParameterTail {
            array: Some(std::sync::Arc::new(dm_ir::ArrayDeclaration {
                dimensions: [None].into(),
                element_type: Some(symbols.intern(element).unwrap()),
            })),
            ..Default::default()
        }))
        .collect::<Vec<_>>()
        .into();
    let result = prepare_procedure(
        &metadata,
        &symbols,
        &[],
        ProcedureInputs::default(),
        InheritedAbi::Fresh,
        |_| Err(fail("unused")),
    )
    .unwrap();
    assert_eq!(result.inputs.parameter_type_flags, [2, 1, 0]);
    for name in &result.inputs.parameters {
        assert_eq!(
            result.inputs.parameter_types.get(name).map(String::as_str),
            Some("/list")
        );
    }
}
#[test]
fn return_annotations_preserve_header_without_return_coercion() {
    let mut symbols = SymbolTable::default();
    for annotation in ["num", "/datum/item", "anything", "num|null"] {
        let mut metadata = metadata(&[], &mut symbols);
        metadata.signature.return_annotation = Some(expression(annotation, &mut symbols));
        let result = prepare_procedure(
            &metadata,
            &symbols,
            &[],
            ProcedureInputs::default(),
            InheritedAbi::Fresh,
            |value| {
                assert_eq!(expression_text(value, &symbols)?, "/datum/item");
                Ok(SemanticValue::Type(dm_ir::SymbolId::of("/datum/item")))
            },
        )
        .unwrap();
        assert_eq!(result.layout, ProcLayout::default());
    }
    for annotation in ["mystery", "(num|text)", "num|", "void", "/datum/missing"] {
        let mut metadata = metadata(&[], &mut symbols);
        metadata.signature.return_annotation = Some(expression(annotation, &mut symbols));
        assert!(prepare_procedure(
            &metadata,
            &symbols,
            &[],
            ProcedureInputs::default(),
            InheritedAbi::Fresh,
            |_| Err(fail("unused"))
        )
        .is_err());
    }
}
#[test]
fn dynamic_radius_uses_helper_and_const_callee_formals_keep_lexical_facts() {
    assert_eq!(source_mode("oview(src)", true).unwrap(), None);
    assert!(source_mode("oview(src)", false).is_err());
    assert!(source_mode("view(256)", true).is_err());
    assert_eq!(source_mode("view(7)", true).unwrap(), Some((1, 7)));
    let mut symbols = SymbolTable::default();
    let mut metadata = metadata(&[], &mut symbols);
    metadata.signature.parameters = vec![Parameter::new(
        symbols.intern("caller").unwrap(),
        Some(symbols.intern("/callee").unwrap()),
        None,
        2,
        Span::new(0, 1),
    ).with_tail(dm_ir::ParameterTail {
        source_expression: Some(expression("oview(src)", &mut symbols)),
        ..Default::default()
    })]
    .into();
    let result = prepare_procedure(
        &metadata,
        &symbols,
        &[],
        ProcedureInputs::default(),
        InheritedAbi::Fresh,
        |_| Err(fail("unused")),
    )
    .unwrap();
    assert_eq!(result.inputs.parameter_type_flags, [0]);
    assert_eq!(result.inputs.parameter_types["caller"], "/callee");
    assert_eq!(result.inputs.readonly_parameters, [0].into());
    assert_eq!(
        result.argument_sources,
        [ArgumentSource::Helper { argument: 0 }]
    );
    assert_eq!(result.source_helpers.len(), 1);
}
#[test]
fn later_category_restores_text_and_unknown_inherited_facts_fail() {
    let mut symbols = SymbolTable::default();
    let metadata = metadata(
        &[
            ("category", SettingOperation::Assign, "null"),
            ("category", SettingOperation::Assign, "\"Visible\""),
        ],
        &mut symbols,
    );
    let ast =
        dm_syntax::parse("/proc/p()\n    set category = null\n    set category = \"Visible\"\n");
    let result = prepare_procedure(
        &metadata,
        &symbols,
        &ast.items[0].children,
        ProcedureInputs::default(),
        InheritedAbi::Fresh,
        |v| evaluate(v, &symbols),
    )
    .unwrap();
    assert_eq!(result.layout.category, Category::Text(b"Visible".to_vec()));
    assert_eq!(result.layout.flags & 0x20, 0);
    assert!(prepare_procedure(
        &metadata,
        &symbols,
        &ast.items[0].children,
        ProcedureInputs::default(),
        InheritedAbi::Unsupported,
        |v| evaluate(v, &symbols)
    )
    .is_err());
}
#[test]
fn nested_setting_is_not_silently_lost_by_incomplete_metadata() {
    let mut symbols = SymbolTable::default();
    let metadata = metadata(&[], &mut symbols);
    let ast = dm_syntax::parse("/proc/p()\n    if(1)\n        set hidden = 1\n");
    let error = prepare_procedure(
        &metadata,
        &symbols,
        &ast.items[0].children,
        ProcedureInputs::default(),
        InheritedAbi::Fresh,
        |_| Err(fail("unused")),
    )
    .err()
    .unwrap();
    assert!(error.message.contains("nested procedure settings"));
}
#[test]
fn parameter_modifiers_and_arrays_are_never_silently_erased() {
    let mut symbols = SymbolTable::default();
    let mut metadata = metadata(&[], &mut symbols);
    // Static (bit 1) still has no certified formal policy. Const (bit 2)
    // is supported by the lexical binding checks.
    let parameter = Parameter::new(
        symbols.intern("value").unwrap(), Some(symbols.intern("/datum").unwrap()),
        None, 1, Span::new(0, 1),
    );
    metadata.signature.parameters = vec![parameter.clone()].into();
    let error = prepare_procedure(
        &metadata,
        &symbols,
        &[],
        ProcedureInputs::default(),
        InheritedAbi::Fresh,
        |_| Err(fail("unused")),
    )
    .err()
    .unwrap();
    assert!(error.message.contains("modifiers"));
    let mut parameter = parameter;
    parameter.flags = 0;
    let declared_type = parameter.declared_type();
    let parameter = parameter.with_tail(dm_ir::ParameterTail {
        array: Some(std::sync::Arc::new(dm_ir::ArrayDeclaration {
            dimensions: vec![None].into(),
            element_type: declared_type,
        })),
        ..Default::default()
    });
    metadata.signature.parameters = vec![parameter].into();
    let error = prepare_procedure(
        &metadata,
        &symbols,
        &[],
        ProcedureInputs::default(),
        InheritedAbi::Fresh,
        |_| Err(fail("unused")),
    )
    .err()
    .unwrap();
    assert!(error.message.contains("array"));
}
#[test]
fn unsized_untyped_list_formal_does_not_allocate_a_default() {
    let mut symbols = SymbolTable::default();
    let mut metadata = metadata(&[], &mut symbols);
    metadata.signature.parameters = vec![Parameter::new(
        symbols.intern("values").unwrap(),
        Some(symbols.intern("/list").unwrap()),
        None,
        0,
        Span::new(0, 8),
    ).with_tail(dm_ir::ParameterTail {
        array: Some(std::sync::Arc::new(dm_ir::ArrayDeclaration {
            dimensions: vec![None].into(),
            element_type: None,
        })),
        ..Default::default()
    })]
    .into();
    let prepared = prepare_procedure(
        &metadata,
        &symbols,
        &[],
        ProcedureInputs::default(),
        InheritedAbi::Fresh,
        |_| Err(fail("no evaluation needed")),
    )
    .unwrap();
    assert_eq!(
        prepared
            .inputs
            .parameter_types
            .get("values")
            .map(String::as_str),
        Some("/list")
    );
    assert_eq!(prepared.inputs.parameter_defaults, [None]);
    assert_eq!(prepared.inputs.parameter_type_flags, [0]);
    assert!(prepared.source_helpers.is_empty());
}
#[test]
fn lexical_settings_apply_in_encounter_order_with_last_write_winning() {
    let mut symbols = SymbolTable::default();
    let metadata = metadata(
        &[
            ("hidden", SettingOperation::Assign, "1"),
            ("hidden", SettingOperation::Assign, "0"),
            ("background", SettingOperation::Assign, "1"),
        ],
        &mut symbols,
    );
    let result = prepare_verified_procedure(
        &metadata,
        &symbols,
        &[],
        ProcedureInputs::default(),
        InheritedAbi::Fresh,
        |value| evaluate(value, &symbols),
    )
    .unwrap();
    assert_eq!(result.layout.flags & 1, 0);
    assert_eq!(result.layout.flags & 0x100, 0x100);
}

#[test]
fn checker_metadata_has_no_runtime_abi_or_constant_evaluation() {
    let mut symbols = SymbolTable::default();
    let metadata = metadata(
        &[(
            "SpacemanDMM_should_be_pure",
            SettingOperation::Assign,
            "unknown_value",
        )],
        &mut symbols,
    );
    let prepared = prepare_verified_procedure(
        &metadata,
        &symbols,
        &[],
        ProcedureInputs::default(),
        InheritedAbi::Fresh,
        |_| panic!("checker annotation must not evaluate a runtime constant"),
    )
    .unwrap();
    assert_eq!(prepared.layout, ProcLayout::default());
    assert!(prepared.executable_body.is_empty());
}

#[test]
fn original_formal_tokens_match_compatibility_policy_without_formal_relex() {
    for (default, annotation, source) in [
        ("null", "mob", "world"),
        ("(null)", "mob", "world"),
        ("n ull", "mob", "world"),
        ("nu/*gone*/ll", "mob", "world"),
        ("\"null\"", "text", "usr.contents"),
        ("null", "mob|text", "view(2)"),
        ("null", "mob", "range(256)"),
        ("null", "not_an_input", "world"),
        ("null", "num", "list(arg,2)"),
        ("null", "num", "view(arg)"),
    ] {
        let mut symbols = SymbolTable::default();
        let mut data = metadata(&[], &mut symbols);
        data.signature.parameters = vec![Parameter::new(
            symbols.intern("arg").unwrap(),
            None,
            None,
            0,
            Span::new(0, 1),
        ).with_tail(dm_ir::ParameterTail {
            default: Some(expression(default, &mut symbols)),
            input_annotation: Some(expression(annotation, &mut symbols)),
            source_expression: Some(expression(source, &mut symbols)),
            ..Default::default()
        })]
        .into();
        FORMAL_RELEX_CALLS.with(|count| count.set(0));
        let old = prepare_verified_procedure(
            &data,
            &symbols,
            &[],
            ProcedureInputs::default(),
            InheritedAbi::Fresh,
            |_| Err(fail("unused")),
        );
        assert!(FORMAL_RELEX_CALLS.with(|count| count.get()) > 0);
        FORMAL_RELEX_CALLS.with(|count| count.set(0));
        let native = prepare_verified_procedure_original_tokens(
            &data,
            &symbols,
            &[],
            ProcedureInputs::default(),
            InheritedAbi::Fresh,
            |_| Err(fail("unused")),
        );
        assert_eq!(
            FORMAL_RELEX_CALLS.with(|count| count.get()),
            0,
            "native classification must not call the formal renderer/relexer"
        );
        match (old, native) {
            (Ok(old), Ok(native)) => {
                assert_eq!(old.layout, native.layout);
                assert_eq!(old.argument_sources, native.argument_sources);
                assert_eq!(old.source_helpers, native.source_helpers);
                assert_eq!(old.inputs.parameters, native.inputs.parameters);
                assert_eq!(old.inputs.parameter_types, native.inputs.parameter_types);
                assert_eq!(
                    old.inputs.parameter_defaults,
                    native.inputs.parameter_defaults
                );
                assert_eq!(
                    old.inputs.parameter_type_flags,
                    native.inputs.parameter_type_flags
                );
                assert_eq!(
                    old.inputs.parameter_value_sources,
                    native.inputs.parameter_value_sources
                );
                assert_eq!(
                    old.inputs.readonly_parameters,
                    native.inputs.readonly_parameters
                );
                if matches!(default, "null" | "(null)" | "\"null\"") {
                    struct Host;
                    impl dm_ir::Resolver for Host {
                        fn resolve(&self, q: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
                            dm_ir::ResolvedMeaning::Unsupported(q)
                        }
                    }
                    let syntax = dm_syntax::parse("/proc/p()\n    return arg\n");
                    let body = dm_syntax::parse_proc_body(&syntax.items[0]);
                    let old_words = crate::compile_statement_view_with_resolver(
                        dm_syntax::StatementView::from_parsed(&body),
                        &old.inputs,
                        &symbols,
                        &Host,
                        None,
                    )
                    .unwrap();
                    let native_words = crate::compile_statement_view_with_resolver(
                        dm_syntax::StatementView::from_parsed(&body),
                        &native.inputs,
                        &symbols,
                        &Host,
                        None,
                    )
                    .unwrap();
                    assert_eq!(old_words.procedure, native_words.procedure);
                }
                if annotation == "mob" && source == "world" {
                    assert_eq!(
                        native.inputs.parameter_type_flags[0] & 0x80,
                        if matches!(default, "null" | "n ull" | "nu/*gone*/ll") {
                            0x80
                        } else {
                            0
                        }
                    );
                }
            }
            (Err(old), Err(native)) => assert_eq!(old, native),
            _ => {
                panic!("native ABI acceptance differs for {default:?} as {annotation} in {source}")
            }
        }
    }
}
#[test]
fn original_formal_compaction_keeps_string_spelling_and_checks_current_token_geometry() {
    let mut symbols = SymbolTable::default();
    for source in [
        "\"a b\"",
        "view ( 2 )",
        "usr . contents",
        "n ull",
        "nu/*gone*/ll",
        "(null)",
    ] {
        let original = expression(source, &mut symbols);
        assert_eq!(
            original_formal_spelling(&original, &symbols),
            compatibility_formal_spelling(&original, &symbols)
        );
        let mut copied = original.tokens.to_vec();
        copied[0].relative_span.end += 1;
        assert!(original_formal_spelling(
            &SymbolicExpression {
                tokens: copied.into()
            },
            &symbols
        )
        .is_err());
    }
}
#[test]
fn standalone_compatibility_still_lexes_unissued_symbolic_token_contents() {
    let mut symbols = SymbolTable::default();
    let text = "null/*standalone*/";
    let unissued = SymbolicExpression {
        tokens: vec![ExpressionToken {
            kind: TokenKind::Ident,
            text: symbols.intern(text).unwrap(),
            relative_span: Span::new(0, text.len()),
        }]
        .into(),
    };
    assert_eq!(
        compatibility_formal_spelling(&unissued, &symbols).unwrap(),
        "null"
    );
    // Such a record is not a native token receipt. The actual driver admits
    // exact selected ORIGINAL frontend metadata, never this standalone copy.
}

#[test]
fn abi_expression_site_adapter_preserves_unique_policy_order_and_skipped_token_settings() {
    let mut symbols = SymbolTable::default();
    let mut metadata = metadata(
        &[
            (
                "SpacemanDMM_should_be_pure",
                SettingOperation::Assign,
                "unavailable_checker_value",
            ),
            ("src", SettingOperation::In, "world"),
            ("waitfor", SettingOperation::Assign, "1"),
        ],
        &mut symbols,
    );
    metadata.signature.return_annotation = Some(expression("/datum", &mut symbols));
    metadata.settings = vec![ProcedureSettingNode::Conditional {
        condition: expression("1", &mut symbols),
        then_branch: metadata.settings.clone(),
        else_branch: Vec::new().into(),
    }]
    .into();
    let scalar = |value: &SymbolicExpression| match expression_text(value, &symbols)?.as_str() {
        "/datum" => Ok(SemanticValue::Type(dm_ir::SymbolId::of("/datum"))),
        _ => evaluate(value, &symbols),
    };
    let compatibility = prepare_verified_procedure_original_tokens(
        &metadata,
        &symbols,
        &[],
        ProcedureInputs::default(),
        InheritedAbi::Fresh,
        scalar,
    )
    .unwrap();
    let mut sites = Vec::new();
    let tagged = prepare_verified_procedure_original_tokens_with_sites(
        &metadata,
        &symbols,
        &[],
        ProcedureInputs::default(),
        InheritedAbi::Fresh,
        |site, value| {
            sites.push(site);
            scalar(value)
        },
    )
    .unwrap();
    assert_eq!(
        sites,
        vec![
            AbiExpressionSite::SettingCondition,
            AbiExpressionSite::ReturnAnnotation,
            AbiExpressionSite::Setting
        ]
    );
    assert_eq!(tagged.layout, compatibility.layout);
    assert_eq!(
        tagged.inputs.procedure_identity,
        compatibility.inputs.procedure_identity
    );
    assert_eq!(
        tagged.inputs.current_proc_path,
        compatibility.inputs.current_proc_path
    );
    assert_eq!(
        tagged.inputs.current_type_path,
        compatibility.inputs.current_type_path
    );
    assert_eq!(tagged.inputs.parameters, compatibility.inputs.parameters);
    assert_eq!(
        tagged.inputs.parameter_type_flags,
        compatibility.inputs.parameter_type_flags
    );
    assert_eq!(
        tagged.inputs.parameter_value_sources,
        compatibility.inputs.parameter_value_sources
    );
    assert_eq!(
        tagged.inputs.parameter_defaults,
        compatibility.inputs.parameter_defaults
    );
    assert_eq!(
        tagged.inputs.parameter_types,
        compatibility.inputs.parameter_types
    );
    assert_eq!(
        tagged.inputs.readonly_parameters,
        compatibility.inputs.readonly_parameters
    );
    assert_eq!(
        tagged.inputs.resource_search_context,
        compatibility.inputs.resource_search_context
    );
    assert_eq!(tagged.argument_sources, compatibility.argument_sources);
    assert_eq!(tagged.source_helpers, compatibility.source_helpers);
    assert_eq!(tagged.executable_body, compatibility.executable_body);
}

#[test]
fn original_return_annotation_policy_uses_original_tokens_without_relex_and_preserves_errors() {
    for text in [
        "num",
        "/datum/known",
        " /datum/known | text | /datum/other ",
        "n um",
        "/da tum",
        "wrong+1",
        "",
    ] {
        let mut symbols = SymbolTable::default();
        let mut value = metadata(&[], &mut symbols);
        value.signature.return_annotation = Some(expression(text, &mut symbols));
        let run = |native: bool| {
            let evaluate = |expression: &SymbolicExpression| {
                let spelling = expression.source_text(&symbols).unwrap();
                if spelling.starts_with("/datum/") {
                    Ok(SemanticValue::Type(dm_ir::SymbolId::of(spelling.trim())))
                } else {
                    Err(AbiError::unsupported("actual unchanged scalar refusal"))
                }
            };
            if native {
                prepare_verified_procedure_original_tokens(
                    &value,
                    &symbols,
                    &[],
                    ProcedureInputs::default(),
                    InheritedAbi::Fresh,
                    evaluate,
                )
            } else {
                prepare_verified_procedure(
                    &value,
                    &symbols,
                    &[],
                    ProcedureInputs::default(),
                    InheritedAbi::Fresh,
                    evaluate,
                )
            }
        };
        FORMAL_RELEX_CALLS.with(|n| n.set(0));
        let native = run(true);
        assert_eq!(
            FORMAL_RELEX_CALLS.with(|n| n.get()),
            0,
            "native original return tokens never render/relex"
        );
        let old = run(false);
        assert!(
            FORMAL_RELEX_CALLS.with(|n| n.get()) > 0,
            "independent compatibility classifier remains real"
        );
        match (native, old) {
            (Ok(native), Ok(old)) => {
                assert_eq!(
                    native.inputs.procedure_identity,
                    old.inputs.procedure_identity
                );
                assert_eq!(
                    native.inputs.current_proc_path,
                    old.inputs.current_proc_path
                );
                assert_eq!(
                    native.inputs.current_type_path,
                    old.inputs.current_type_path
                );
                assert_eq!(native.inputs.parameters, old.inputs.parameters);
                assert_eq!(
                    native.inputs.parameter_type_flags,
                    old.inputs.parameter_type_flags
                );
                assert_eq!(
                    native.inputs.parameter_value_sources,
                    old.inputs.parameter_value_sources
                );
                assert_eq!(
                    native.inputs.parameter_defaults,
                    old.inputs.parameter_defaults
                );
                assert_eq!(native.inputs.parameter_types, old.inputs.parameter_types);
                assert_eq!(
                    native.inputs.readonly_parameters,
                    old.inputs.readonly_parameters
                );
                assert_eq!(
                    native.inputs.resource_search_context,
                    old.inputs.resource_search_context
                );
                assert_eq!(native.layout, old.layout);
                assert_eq!(native.argument_sources, old.argument_sources);
                assert_eq!(native.source_helpers, old.source_helpers);
            }
            (Err(native), Err(old)) => {
                assert_eq!(native.kind, old.kind);
                assert_eq!(native.message, old.message);
            }
            _ => panic!("original/compat annotation acceptance mismatch for {text:?}"),
        }
    }
}
