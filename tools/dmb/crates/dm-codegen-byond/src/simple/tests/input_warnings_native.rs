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
fn anything_without_list_matches_authenticated_pure_null_and_duplicate_masks() {
    struct Debug;
    impl DebugSourceProvider for Debug {
        fn entry_ordinal(&self) -> Result<u32, String> {
            Ok(0)
        }
        fn ordinal(&self, offset: usize) -> Result<u32, String> {
            u32::try_from(offset).map_err(|error| error.to_string())
        }
    }
    let source =
        include_str!("../../../../../fixtures/native/diagnostic_anchor_cursor/type_masks.dm");
    let log = include_str!(
        "../../../../../fixtures/native/diagnostic_anchor_cursor/type-masks-compile.log"
    );
    let ast = dm_syntax::parse(source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    // Pinned BYOND lookahead coordinates and multiplicity, independently of
    // the native current-statement origin (exact token-cursor parity is open).
    let captured = [5, 7, 9, 9, 11, 13, 15, 17, 19];
    let observed = log
        .lines()
        .filter(|line| line.contains("warning (anything_no_list)"))
        .map(|line| line.split(':').nth(1).unwrap().parse::<usize>().unwrap())
        .collect::<Vec<_>>();
    assert_eq!(observed, captured);
    let mut total = 0;
    for item in &ast.items {
        let compiled = compile_with_lookup(
            &item.children,
            None,
            &LowerBindings::default(),
            None,
            Some(&Debug),
        )
        .unwrap_or_else(|errors| panic!("{}: {errors:?}", item.header));
        let expected = if item.header.contains("pure_anything")
            || item.header.contains("null_only")
            || item.header.contains("after(")
        {
            0
        } else if item.header.contains("anything_anything") {
            2
        } else {
            1
        };
        assert_eq!(compiled.warnings.len(), expected, "{}", item.header);
        for warning in compiled.warnings {
            assert_eq!(warning.code, dm_ir::WarningCode::AnythingWithoutList);
            assert_eq!(
                warning.code.message(),
                "'anything' has no meaning without a list"
            );
            assert_eq!(warning.name, None);
            assert_eq!(
                warning.source_ordinal, None,
                "standalone provider has no cursor authority"
            );
            total += 1;
        }
    }
    assert_eq!(total, captured.len());
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
    // Ordered actual BYOND filter_rightmost and anything_no_list lines in receipt.json.
    let object_lines = [4, 12, 20, 28, 36, 44, 52, 68, 72, 76, 88, 88, 92];
    let anything_lines = [56, 60];
    // BYOND reports its lookahead token (the following procedure header), not
    // the expression. Keep those authenticated coordinates distinct from the
    // current statement ordinal that this producer is licensed to issue.
    let without_list_locations = [(50, 51), (54, 55), (58, 59), (62, 63)];
    // Use the committed capture; compile.log is a generated, ignored artifact
    // and is absent from an immutable Git snapshot or fresh checkout.
    let capture: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../../fixtures/native/input_filter_order/receipt.json"
    ))
    .unwrap();
    assert_eq!(capture["status"], "captured");
    assert_eq!(
        capture["compiler_sha256"],
        "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0"
    );
    let captured = capture["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| case["name"] == "matrix")
        .unwrap();
    assert_eq!(captured["byond"]["exit_code"], 0);
    let diagnostics = captured["byond"]["diagnostics"].as_array().unwrap();
    for (expression_line, byond_line) in without_list_locations {
        let expression = source.lines().nth(expression_line - 1).unwrap();
        let lookahead = source.lines().nth(byond_line - 1).unwrap();
        assert!(expression.contains("input(\"prompt\")") && expression.contains("anything"));
        assert!(!expression.contains(" in choices"));
        assert!(lookahead.starts_with("/proc/"));
        assert!(diagnostics.iter().any(|row| row["file"] == "matrix.dm"
            && row["line"] == byond_line
            && row["severity"] == "warning (anything_no_list)"
            && row["message"] == "'anything' has no meaning without a list"));
    }
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
        let without_list = without_list_locations
            .iter()
            .any(|(expression, _)| *expression == line);
        if without_list {
            expected.push(dm_ir::WarningCode::AnythingWithoutList);
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
            assert_eq!(
                warning.source_ordinal,
                if without_list {
                    None
                } else {
                    Some(offset as u32)
                }
            );
            assert_eq!(
                warning.code.name(),
                if without_list {
                    "anything_no_list"
                } else {
                    "filter_rightmost"
                }
            );
            if without_list {
                assert_eq!(
                    warning.code.message(),
                    "'anything' has no meaning without a list"
                );
            }
            assert!(!warning.code.requires_name());
        }
    }
}
