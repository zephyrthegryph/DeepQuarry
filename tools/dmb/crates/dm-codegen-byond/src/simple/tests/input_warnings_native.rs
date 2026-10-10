//! Producer warning predicates from the authenticated pinned mask matrix.
use super::*;

#[test]
fn input_filter_warnings_match_authenticated_matrix_and_current_ordinals() {
    struct Debug;
    impl DebugSourceProvider for Debug {
        fn entry_ordinal(&self) -> Result<u32, String> {
            Ok(0)
        }
        fn ordinal(&self, offset: usize) -> Result<u32, String> {
            u32::try_from(offset).map_err(|error| error.to_string())
        }
    }
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native/input_warning_masks/matrix.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    // Exact warning lines in the authenticated receipt, including object filter ordering.
    let warning_lines = [2, 4, 6, 8, 10, 12, 14, 16, 18, 28, 30, 44, 46, 48];
    for item in &ast.items {
        let bindings = LowerBindings {
            parameters: if item.header.contains("choices") {
                vec!["choices".into()]
            } else {
                vec![]
            },
            ..LowerBindings::default()
        };
        let compiled = compile_with_lookup(&item.children, None, &bindings, None, Some(&Debug))
            .unwrap_or_else(|errors| panic!("{}: {errors:?}", item.header));
        let offset = item.children[0].header_span.start;
        let source = include_str!("../../../../../fixtures/native/input_warning_masks/matrix.dm");
        let line = source[..offset]
            .bytes()
            .filter(|byte| *byte == b'\n')
            .count()
            + 1;
        let expected = warning_lines.contains(&line);
        let object_order = [24, 26].contains(&line);
        assert_eq!(
            compiled.warnings.len(),
            usize::from(expected || object_order),
            "{} line{line}",
            item.header
        );
        if expected || object_order {
            let warning = &compiled.warnings[0];
            assert_eq!(
                warning.code,
                if object_order {
                    dm_ir::WarningCode::ObjectFilterRightmost
                } else {
                    dm_ir::WarningCode::ListWithoutFilter
                }
            );
            assert_eq!(warning.name, None);
            assert_eq!(warning.source_ordinal, Some(offset as u32));
            assert!(!warning.code.requires_name());
            if !object_order {
                assert_eq!(warning.code.message(), "it is recommended that you use an object filter or 'anything' when combining constant input types with lists");
            }
        }
    }
}

#[test]
fn ordered_input_filters_match_pinned_diagnostics_including_multiplicity() {
    struct Debug;
    impl DebugSourceProvider for Debug {
        fn entry_ordinal(&self) -> Result<u32, String> {
            Ok(0)
        }
        fn ordinal(&self, offset: usize) -> Result<u32, String> {
            u32::try_from(offset).map_err(|error| error.to_string())
        }
    }
    let source = include_str!("../../../../../fixtures/native/input_filter_order/matrix.dm");
    let ast = dm_syntax::parse(source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    // Ordered actual BYOND filter_rightmost lines in receipt.json. The distinct
    // anything_no_list warnings are outside this producer's current scope.
    let object_lines = [4, 12, 20, 28, 36, 44, 52, 68, 72, 76, 88, 88, 92];
    let anything_lines = [56, 60];
    for item in &ast.items {
        let bindings = LowerBindings {
            parameters: vec!["choices".into()],
            ..LowerBindings::default()
        };
        let compiled = compile_with_lookup(&item.children, None, &bindings, None, Some(&Debug))
            .unwrap_or_else(|errors| panic!("{}: {errors:?}", item.header));
        let offset = item.children[0].header_span.start;
        let line = source[..offset]
            .bytes()
            .filter(|byte| *byte == b'\n')
            .count()
            + 1;
        let mut expected = Vec::new();
        for _ in object_lines.iter().filter(|&&value| value == line) {
            expected.push(dm_ir::WarningCode::ObjectFilterRightmost);
        }
        for _ in anything_lines.iter().filter(|&&value| value == line) {
            expected.push(dm_ir::WarningCode::AnythingFilterRightmost);
        }
        assert_eq!(
            compiled
                .warnings
                .iter()
                .map(|warning| warning.code)
                .collect::<Vec<_>>(),
            expected,
            "{} line{line}",
            item.header
        );
        for warning in &compiled.warnings {
            assert_eq!(warning.name, None);
            assert_eq!(warning.source_ordinal, Some(offset as u32));
            assert_eq!(warning.code.name(), "filter_rightmost");
            assert!(!warning.code.requires_name());
        }
    }
}
