//! Independently issued pending-body grammar failures follow ordinary errors.
use dm_codegen_byond::{DiagnosticAnchor, LowerError, LowerErrorKind, LowerSpan};
pub(super) fn append<T>(
    result: Result<T, Vec<LowerError>>,
    body: Option<&dm_tree::frontend::StatementBody>,
) -> Result<T, Vec<LowerError>> {
    let Some(body) = body else {
        return result;
    };
    let mut grammar = body
        .parsed()
        .pending_bodies
        .iter()
        .filter(|receipt| receipt.missing_body())
        .map(|receipt| LowerError {
            statement: String::new(),
            reason: ": invalid expression".into(),
            span: Some(LowerSpan {
                start: receipt.header.start,
                end: receipt.header.end,
            }),
            primary_anchor: Some(DiagnosticAnchor::LexerCursorAfterOffset(receipt.header.end)),
            kind: LowerErrorKind::SourceError,
            related: Vec::new(),
        })
        .peekable();
    if grammar.peek().is_none() {
        return result;
    }
    let mut errors = match result {
        Ok(_) => Vec::new(),
        Err(errors) => errors,
    };
    errors.extend(grammar);
    Err(errors)
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Source(String);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, path: &std::path::Path) -> Result<String, String> {
            if path.extension().is_some_and(|extension| extension == "dme") {
                Ok("#include \"probe.dm\"\n".into())
            } else {
                Ok(self.0.clone())
            }
        }
    }
    #[test]
    fn issued_grammar_failure_follows_duplicate_and_rebinds_current_include_eof() {
        let source =
            include_str!("../../../../fixtures/native/loop_local_diagnostics/pair_value_eof.dm");
        for shift in [0, 2] {
            let frontend = dm_tree::frontend::build(
                std::path::Path::new("cursor.dme"),
                &Source("\n".repeat(shift) + source),
                &Default::default(),
                1,
            )
            .unwrap();
            let body = &frontend.bodies[0];
            let arena = dm_tree::frontend::BodyArena::new_typed(
                &frontend,
                dm_codegen_byond::typed_statements_supported,
            );
            let issued = arena
                .with_parsed(body, |parsed| parsed.shared_statement_body().unwrap())
                .unwrap();
            let item =
                dm_syntax::parse_proc_at_span(&frontend.expanded.text, body.expanded_span).unwrap();
            let ordinary = dm_codegen_byond::compile_simple_proc(&item.children);
            let errors = append(ordinary, Some(&issued)).unwrap_err();
            assert_eq!(errors.len(), 2);
            assert_eq!(errors[0].reason, "value: duplicate definition");
            assert_eq!(errors[1].reason, ": invalid expression");
            assert!(errors
                .iter()
                .all(|error| error.kind == LowerErrorKind::SourceError));
            let mut relative = errors.clone();
            for error in &mut relative {
                error.primary_anchor = error
                    .primary_anchor
                    .map(|anchor| super::super::error_anchor::relative(anchor, body).unwrap());
                if let Some(span) = &mut error.span {
                    span.start -= body.expanded_span.start;
                    span.end -= body.expanded_span.start;
                }
                for related in &mut error.related {
                    related.span.start -= body.expanded_span.start;
                    related.span.end -= body.expanded_span.start;
                }
            }
            let bound = super::super::replay_errors(
                &frontend,
                body,
                dm_ir::ProcedureIdentity {
                    owner: dm_ir::SymbolId::of(""),
                    name: dm_ir::SymbolId::of("probe"),
                    verb: false,
                    occurrence: 0,
                },
                relative,
            )
            .unwrap();
            assert_eq!(bound[1].origin.semantic_path.as_ref(), "cursor.dme");
            assert_eq!(bound[1].origin.line, 2);
            assert_eq!(bound[1].origin.include_occurrence, 0);
        }
    }
}
