use super::*;
struct Empty;
impl dm_ir::Resolver for Empty {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        dm_ir::ResolvedMeaning::Unsupported(query)
    }
}
#[test]
fn explicit_sized_list_and_null_keep_both_current_input_receipts() {
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/").unwrap();
    let name = symbols.intern("value").unwrap();
    for (source, assigned) in [("list(1,2)", true), ("null", false)] {
        let value = expression(source, &mut symbols).unwrap();
        let mut input = write(owner, name, InitializerValue::Expression(value));
        input.declared_array = Some(Arc::new(dm_ir::ArrayDeclaration {
            dimensions: Arc::from([Some(expression("2", &mut symbols).unwrap())]),
            element_type: None,
        }));
        let evaluator = crate::driver_facts::DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &Empty,
            symbols: &symbols,
        };
        let result = classify(&[input.clone()], &symbols, &evaluator).unwrap();
        let current = &result.writes[0];
        let Some(RuntimeValue::SizedArrayExplicit {
            dimensions,
            expression,
        }) = &current.runtime_value
        else {
            panic!("combined array receipt missing")
        };
        assert_eq!(dimensions.as_ref(), &[2]);
        assert_eq!(expression.is_some(), assigned);
        assert_eq!(current.write, input);
        assert_eq!(current.phase, Some(Phase::LiteralAllocation));
    }
}

#[test]
fn inherited_null_override_has_no_new_array_allocation() {
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/datum/probe").unwrap();
    let name = symbols.intern("value").unwrap();
    let mut input = write(
        owner,
        name,
        InitializerValue::Expression(expression("null", &mut symbols).unwrap()),
    );
    input.target = InitializerTarget::Instance {
        declaring_owner: owner,
        receiver_owner: owner,
        name,
    };
    input.source_site = dm_ir::InitializerSite::Assignment;
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &Empty,
        symbols: &symbols,
    };
    let result = classify(&[input], &symbols, &evaluator).unwrap();
    assert!(result.writes[0].phase.is_none());
    assert!(result.writes[0].runtime_value.is_none());
    assert!(result.groups.is_empty());
}
