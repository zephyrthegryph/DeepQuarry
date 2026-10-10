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
    // Exact warning lines in receipt.json, excluding separate filter_rightmost
    // diagnostics (not implemented by this producer slice).
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
        assert_eq!(
            compiled.warnings.len(),
            usize::from(expected),
            "{} line{line}",
            item.header
        );
        if expected {
            let warning = &compiled.warnings[0];
            assert_eq!(warning.code, dm_ir::WarningCode::ListWithoutFilter);
            assert_eq!(warning.name, None);
            assert_eq!(warning.source_ordinal, Some(offset as u32));
            assert!(!warning.code.requires_name());
            assert_eq!(warning.code.message(), "it is recommended that you use an object filter or 'anything' when combining constant input types with lists");
        }
    }
}
