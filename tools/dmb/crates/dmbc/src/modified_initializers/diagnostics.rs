//! Bind modified field failures only through their current captured source ledger.
use super::*;
use crate::initializer_diagnostics::InitializerLoweringError as Error;

pub(super) fn project(
    error: dm_codegen_byond::initializer::InitializerError,
    fields: &[(String, dm_syntax::Expr)],
    source: &Origins,
    frontend: Option<&dm_tree::frontend::ColdFrontend>,
) -> Error {
    let errors = match error {
        dm_codegen_byond::initializer::InitializerError::Lowering(errors) => errors,
        dm_codegen_byond::initializer::InitializerError::Unsupported(reason) => {
            return Error::Unsupported(reason)
        }
        dm_codegen_byond::initializer::InitializerError::Invalid(reason) => {
            return Error::Invariant(reason)
        }
    };
    let Some(frontend) = frontend else {
        return Error::Unsupported(format!(
            "modified initializer lowering has no current source binding: {errors:?}"
        ));
    };
    let mut projected = Vec::with_capacity(errors.len());
    for mut error in errors {
        let Some(span) = error.span else {
            return Error::Unsupported("modified failure lacks current field span".into());
        };
        // The common modified-fields lowerer anchors a failure to the active
        // complete field RHS. Never interpret its byte offset as an ordinal.
        let mut matches = fields
            .iter()
            .enumerate()
            .filter(|(_, (_, field))| field.span.start == span.start && field.span.end == span.end);
        let Some((index, _)) = matches.next() else {
            return Error::Unsupported("modified failure is outside current field roster".into());
        };
        if matches.next().is_some() || !error.related.is_empty() || error.primary_anchor.is_some() {
            return Error::Unsupported(
                "modified failure has no unique supported field provenance".into(),
            );
        }
        let Some(issued) = source.entries.get(index + 1) else {
            return Error::Invariant("modified field source roster is incomplete".into());
        };
        let Some(location) = frontend.location(span.start) else {
            return Error::Unsupported("modified field has no current source projection".into());
        };
        if location.semantic_path != issued.semantic_path || location.line != issued.line as usize {
            return Error::Unsupported(
                "modified field source projection differs from current issued origin".into(),
            );
        }
        error.span = Some(dm_codegen_byond::LowerSpan { start: 0, end: 0 });
        match crate::initializer_diagnostics::map_lower_errors(vec![error], &[location]) {
            Ok(mut diagnostics) => projected.append(&mut diagnostics),
            Err(error) => return error,
        }
    }
    Error::Diagnostics(projected)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn modified_source_failure_requires_current_field_projection() {
        struct Source;
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &std::path::Path) -> Result<String, String> {
                Ok("/proc/probe()\n    return 1\n".into())
            }
        }
        let frontend = dm_tree::frontend::build_with_config(
            std::path::Path::new("modified-current.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
        )
        .unwrap();
        let start = frontend.expanded.text.as_str().rfind('1').unwrap();
        let mut value = dm_syntax::parse_expression("1").expr.unwrap();
        value.span = dm_syntax::Span {
            start,
            end: start + 1,
        };
        let location = frontend.location(start).unwrap();
        let origin = DebugOrigin {
            semantic_path: Arc::clone(&location.semantic_path),
            line: u32::try_from(location.line).unwrap(),
        };
        let mut source = Origins {
            entries: vec![origin.clone(), origin],
        };
        let fields = vec![("child".into(), value)];
        let error = || {
            dm_codegen_byond::initializer::InitializerError::Lowering(vec![
                dm_codegen_byond::LowerError {
                    reason: "/obj/missing: undefined type path".into(),
                    kind: dm_codegen_byond::LowerErrorKind::SourceError,
                    span: Some(dm_codegen_byond::LowerSpan {
                        start,
                        end: start + 1,
                    }),
                    ..Default::default()
                },
            ])
        };
        let Error::Diagnostics(diagnostics) = project(error(), &fields, &source, Some(&frontend))
        else {
            panic!("current source diagnostic")
        };
        assert_eq!(diagnostics[0].origin, location);
        assert_eq!(
            diagnostics[0].kind,
            dm_tree::frontend::DiagnosticKind::SourceError
        );
        assert!(matches!(
            project(error(), &fields, &source, None),
            Error::Unsupported(_)
        ));
        source.entries[1].line += 1;
        assert!(matches!(
            project(error(), &fields, &source, Some(&frontend)),
            Error::Unsupported(_)
        ));
    }
}
