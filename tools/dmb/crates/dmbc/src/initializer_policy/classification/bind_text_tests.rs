//! Binding still authenticates current tokens before sharing relative syntax.
use super::*;

#[test]
fn runtime_binding_preserves_current_tokens_ordinals_and_exact_syntax() {
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/").unwrap();
    let name = symbols.intern("output").unwrap();
    let source = "list(1, list(2, 3))";
    let expression = Arc::new(dm_syntax::parse_expression(source).expr.unwrap());
    let payload = SemanticClassification {
        identity: Arc::new(0),
        source_features: Default::default(),
        input: None,
        default: DefaultValue::Scalar(SemanticValue::Null),
        phase: None,
        runtime: Some(RuntimeRecipe::Expression(
            shared_expression::SharedExpression::capture(source.into(), &expression).unwrap(),
        )),
        key: None,
    };
    let mut current = InitializerWrite {
        source_site: dm_ir::InitializerSite::Declaration,
        target: InitializerTarget::Shared {
            slot: name,
            owner,
            name,
        },
        lexical_owner: owner,
        lexical_procedure: None,
        value: InitializerValue::Expression(
            crate::initializer_policy::expression(source, &mut symbols).unwrap(),
        ),
        declared_array: None,
        declaration_flags: Some(8),
    };
    let bound = payload.bind(&current, &symbols, 83).unwrap();
    assert_eq!(bound.write.source_ordinal, 83);
    assert_eq!(bound.write.write, current);
    let Some(RuntimeValue::Expression(actual)) = bound.write.runtime_value else {
        panic!("runtime expression fixture");
    };
    assert!(Arc::ptr_eq(&actual, &expression));
    current.value = InitializerValue::Expression(
        crate::initializer_policy::expression("list(1, list(2, 4))", &mut symbols).unwrap(),
    );
    assert!(payload.bind(&current, &symbols, 0).is_none());
    current.value = InitializerValue::Expression(
        crate::initializer_policy::expression(source, &mut symbols).unwrap(),
    );
    let InitializerValue::Expression(tokens) = &mut current.value else {
        unreachable!()
    };
    Arc::make_mut(&mut tokens.tokens)[0].relative_span.end += 1;
    assert!(payload.bind(&current, &symbols, 0).is_none());
    let payload = Arc::new(payload);
    let weak = Arc::downgrade(&payload);
    let identity = ClassificationOwner::new(Arc::clone(&payload));
    let same = ClassificationOwner::new(Arc::clone(&payload));
    assert_eq!(identity, same);
    let other = ClassificationOwner::from_identity(Arc::new(0));
    assert_ne!(
        identity, other,
        "equal marker bytes do not license another result"
    );
    drop(payload);
    assert!(
        weak.upgrade().is_none(),
        "placement identities must not pin recreatable classification payloads"
    );
    assert_eq!(identity, same);
}
