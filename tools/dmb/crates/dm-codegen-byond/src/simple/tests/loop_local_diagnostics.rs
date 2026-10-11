use super::*;

#[test]
fn authenticated_same_pair_name_rejection_keeps_both_current_header_receipts() {
    let source =
        include_str!("../../../../../fixtures/native/loop_local_diagnostics/same_pair_name.dm");
    let parsed = dm_syntax::parse(source);
    let errors = compile_simple_proc(&parsed.items[0].children).unwrap_err();
    assert_eq!(errors[0].kind, LowerErrorKind::SourceError);
    assert_eq!(errors[0].reason, "value: duplicate definition");
    let header = source.find("for(").unwrap();
    assert_eq!(errors[0].span.unwrap().start, header);
    assert_eq!(errors[0].related.len(), 1);
    assert_eq!(errors[0].related[0].span.start, header);
    assert_eq!(errors[0].related[0].message, "value: previous definition");
}

#[test]
fn authenticated_loop_duplicates_are_source_errors_with_current_declaration_spans() {
    for (source, name) in [
        (
            include_str!("../../../../../fixtures/native/loop_local_diagnostics/enclosing_each.dm"),
            "x",
        ),
        (
            include_str!(
                "../../../../../fixtures/native/loop_local_diagnostics/enclosing_pair_key.dm"
            ),
            "x",
        ),
        (
            include_str!(
                "../../../../../fixtures/native/loop_local_diagnostics/enclosing_pair_value.dm"
            ),
            "value",
        ),
        (
            include_str!(
                "../../../../../fixtures/native/loop_local_diagnostics/enclosing_range.dm"
            ),
            "x",
        ),
    ] {
        let parsed = dm_syntax::parse(source);
        let errors = compile_simple_proc(&parsed.items[0].children).unwrap_err();
        assert_eq!(errors[0].kind, LowerErrorKind::SourceError);
        assert_eq!(errors[0].reason, format!("{name}: duplicate definition"));
        assert_eq!(errors[0].span.unwrap().start, source.find("for(").unwrap());
        assert_eq!(errors[0].related.len(), 1);
        assert_eq!(
            errors[0].related[0].span.start,
            source.find("var/").unwrap()
        );
    }
}

#[test]
fn authenticated_sibling_loops_and_existing_bindings_remain_accepted() {
    for source in [
        include_str!("../../../../../fixtures/native/loop_local_diagnostics/sibling_each.dm"),
        include_str!("../../../../../fixtures/native/loop_local_diagnostics/sibling_range.dm"),
        include_str!("../../../../../fixtures/native/loop_local_diagnostics/existing_each.dm"),
        include_str!("../../../../../fixtures/native/loop_local_diagnostics/existing_range.dm"),
    ] {
        let parsed = dm_syntax::parse(source);
        compile_simple_proc(&parsed.items[0].children).unwrap();
    }
}
