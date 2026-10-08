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
    metadata.signature.parameters = vec![Parameter {
        name: symbols.intern("count").unwrap(),
        declared_type: None,
        list_element_type: None,
        flags: 0,
        array: None,
        default: Some(expression("1", &mut symbols)),
        input_annotation: Some(expression("num | null", &mut symbols)),
        source_expression: Some(expression("list(count)", &mut symbols)),
        relative_span: Span::new(0, 1),
    }]
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
fn typed_unsized_formals_keep_list_lexical_type_and_element_restrictions() {
    let mut symbols = SymbolTable::default();
    let mut metadata = metadata(&[], &mut symbols);
    let list = symbols.intern("/list").unwrap();
    metadata.signature.parameters = ["/obj", "/mob", "/datum/item"]
        .into_iter()
        .enumerate()
        .map(|(index, element)| Parameter {
            name: symbols.intern(&format!("values{index}")).unwrap(),
            declared_type: Some(list),
            list_element_type: None,
            flags: 0,
            array: Some(std::sync::Arc::new(dm_ir::ArrayDeclaration {
                dimensions: [None].into(),
                element_type: Some(symbols.intern(element).unwrap()),
            })),
            default: None,
            input_annotation: None,
            source_expression: None,
            relative_span: Span::new(0, 1),
        })
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
    metadata.signature.parameters = vec![Parameter {
        name: symbols.intern("caller").unwrap(),
        declared_type: Some(symbols.intern("/callee").unwrap()),
        list_element_type: None,
        flags: 2,
        array: None,
        default: None,
        input_annotation: None,
        source_expression: Some(expression("oview(src)", &mut symbols)),
        relative_span: Span::new(0, 1),
    }]
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
    assert!(error.0.contains("nested procedure settings"));
}
#[test]
fn parameter_modifiers_and_arrays_are_never_silently_erased() {
    let mut symbols = SymbolTable::default();
    let mut metadata = metadata(&[], &mut symbols);
    let parameter = Parameter {
        name: symbols.intern("value").unwrap(),
        declared_type: Some(symbols.intern("/datum").unwrap()),
        list_element_type: None,
        // Const (bit 2) is supported and checked by the lexical binding
        // tests. Static (bit 1) still has no certified formal policy.
        flags: 1,
        array: None,
        default: None,
        input_annotation: None,
        source_expression: None,
        relative_span: Span::new(0, 1),
    };
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
    assert!(error.0.contains("modifiers"));
    let mut parameter = parameter;
    parameter.flags = 0;
    parameter.array = Some(std::sync::Arc::new(dm_ir::ArrayDeclaration {
        dimensions: vec![None].into(),
        element_type: parameter.declared_type,
    }));
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
    assert!(error.0.contains("array"));
}
#[test]
fn unsized_untyped_list_formal_does_not_allocate_a_default() {
    let mut symbols = SymbolTable::default();
    let mut metadata = metadata(&[], &mut symbols);
    metadata.signature.parameters = vec![Parameter {
        name: symbols.intern("values").unwrap(),
        declared_type: Some(symbols.intern("/list").unwrap()),
        list_element_type: None,
        flags: 0,
        array: Some(std::sync::Arc::new(dm_ir::ArrayDeclaration {
            dimensions: vec![None].into(),
            element_type: None,
        })),
        default: None,
        input_annotation: None,
        source_expression: None,
        relative_span: Span::new(0, 8),
    }]
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
