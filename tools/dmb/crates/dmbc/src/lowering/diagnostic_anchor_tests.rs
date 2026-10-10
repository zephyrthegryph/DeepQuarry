use super::*;
use crate::debug_sources::RelativeDebugAnchor;
struct Source(String);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, path: &std::path::Path) -> Result<String, String> {
        if path.extension().is_some_and(|ext| ext == "dme") {
            Ok("#include \"probe.dm\"\n".into())
        } else {
            Ok(self.0.clone())
        }
    }
}

#[test]
fn current_lexer_cursor_rebinds_shared_and_wire_recipes_without_stale_next_offsets() {
    for (source, expected) in [
        (
            include_str!("../../../../fixtures/native/diagnostic_anchor_cursor/blank_comments.dm"),
            Some(6),
        ),
        (
            include_str!("../../../../fixtures/native/diagnostic_anchor_cursor/same_line.dm"),
            Some(2),
        ),
        (
            include_str!(
                "../../../../fixtures/native/diagnostic_anchor_cursor/following_statement.dm"
            ),
            Some(3),
        ),
        (
            include_str!(
                "../../../../fixtures/native/diagnostic_anchor_cursor/nested_expression.dm"
            ),
            Some(2),
        ),
        (
            include_str!("../../../../fixtures/native/diagnostic_anchor_cursor/eof.dm"),
            Some(2),
        ),
    ] {
        let terminal_include =
            source == include_str!("../../../../fixtures/native/diagnostic_anchor_cursor/eof.dm");
        let source = source.replace(" as anything", " as text|anything");
        let mut first: Option<Vec<RelativeDebugAnchor>> = None;
        for shift in [0, 2] {
            let current = "\n".repeat(shift) + &source;
            let frontend = dm_tree::frontend::build(
                std::path::Path::new("cursor.dme"),
                &Source(current),
                &Default::default(),
                1,
            )
            .unwrap();
            let body = &frontend.bodies[0];
            let parsed = frontend.parse_body(body).unwrap();
            let capture = RefCell::new(MemoCapture::default());
            let provider = MemoDebugProvider {
                original: FrontendDebugProvider::new(&frontend, parsed.item().header_span.start),
                base: body.expanded_span.start,
                entry: parsed.item().header_span.start,
                capture: Some(&capture),
            };
            let code = compile_simple_proc_with_resolver_and_debug(
                &parsed.item().children,
                &Default::default(),
                frontend.snapshot.tree.symbols(),
                frontend.snapshot.tree.as_ref(),
                Some(&provider),
            )
            .unwrap();
            let origins = provider.original.finish();
            assert_eq!(code.procedure.warnings.len(), 1);
            let warning = &code.procedure.warnings[0];
            let origin = &origins.entries[warning.source_ordinal.unwrap() as usize];
            assert_eq!(
                origin.line,
                expected
                    .map(|line| line as u32 + if terminal_include { 0 } else { shift as u32 })
                    .unwrap_or(0)
            );
            if terminal_include {
                assert_eq!(origin.semantic_path.as_ref(), "cursor.dme");
            }
            let anchors = capture.borrow().debug.clone();
            assert!(anchors.iter().any(|anchor| matches!(
                anchor,
                RelativeDebugAnchor::LexerCursorAfterBodyOffset(_)
            )));
            assert_eq!(
                crate::lowering_memo::rebase_debug(&frontend, body, &anchors),
                Some(origins.clone())
            );
            let encoded = dm_wire::encode(0x0d1a_0001, &anchors).unwrap();
            let decoded: Vec<RelativeDebugAnchor> =
                dm_wire::decode(0x0d1a_0001, &encoded, encoded.len()).unwrap();
            assert_eq!(
                crate::lowering_memo::rebase_debug(&frontend, body, &decoded),
                Some(origins.clone())
            );
            if let Some(previous) = &first {
                assert_eq!(
                    crate::lowering_memo::rebase_debug(&frontend, body, previous),
                    Some(origins.clone())
                );
            } else {
                first = Some(anchors);
            }
            let frozen: crate::debug_sources::FrozenDebugOrigins = origins.into();
            let bound = crate::procedure_warnings::bind(
                &code.procedure.warnings,
                &frozen,
                frontend.snapshot.tree.symbols(),
                &code.procedure.local_names,
            )
            .unwrap();
            assert_eq!(
                bound[0].location.line,
                expected
                    .map(|line| line as usize + if terminal_include { 0 } else { shift as usize })
            );
            let rendered = crate::initializer_policy::warnings::render(&bound).unwrap();
            assert!(rendered[0]
                .contains("warning (anything_no_list): 'anything' has no meaning without a list"));
            if expected.is_none() {
                assert!(!rendered[0].contains(":0:"));
            }
        }
    }
}
