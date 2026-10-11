//! Bind proven duplicate stored declarations to the current issued source.
use super::{ColdError, ColdFrontend};
use crate::lowering::{LoweringDiagnostic, RelatedDiagnostic};
use dm_tree::frontend::DiagnosticKind;

pub(super) fn capture_error(
    frontend: &ColdFrontend,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    error: String,
) -> ColdError {
    // Only the existing static-capture refusal enters this classifier. Other
    // startup failures retain their original ordering and error classification.
    if error != "same-name scoped procedure statics require a certified lexical slot policy" {
        return ColdError::Initializer(error);
    }
    let Ok(roster) = frontend.callable_roster() else {
        return ColdError::Initializer(error);
    };
    for body in frontend.bodies.iter() {
        let Some(identity) = roster.identity_for_member(body.member) else {
            return ColdError::Initializer(error);
        };
        let capture =
            bodies.with_parsed(body, |parsed| parsed.capture_stored_declarations(identity));
        match capture {
            Ok(Ok(_)) => continue,
            Ok(Err(reason)) if reason == error => (),
            _ => return ColdError::Initializer(error),
        }
        let duplicate = bodies.with_parsed(body, |parsed| {
            let fallback;
            let statements = if let Some(statements) = parsed.statement_body() {
                statements.parsed()
            } else {
                fallback = dm_syntax::parse_body_items(&parsed.item().children);
                &fallback
            };
            if !statements.diagnostics.is_empty() {
                return None;
            }
            dm_tree::procedure_statics::duplicate_static_declaration(&statements.statements)
        });
        let Ok(Some(duplicate)) = duplicate else {
            return ColdError::Initializer(error);
        };
        let (Some(origin), Some(previous)) = (
            frontend.location(duplicate.current.start),
            frontend.location(duplicate.previous.start),
        ) else {
            return ColdError::Initializer(error);
        };
        return ColdError::Lowering(vec![LoweringDiagnostic {
            kind: DiagnosticKind::SourceError,
            identity: None,
            origin,
            message: format!("{}: duplicate definition", duplicate.name),
            related: vec![RelatedDiagnostic {
                origin: previous,
                message: format!("{}: previous definition", duplicate.name),
            }],
        }]);
    }
    ColdError::Initializer(error)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    struct Text(&'static str);
    impl dm_preprocess::SourceProvider for Text {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    fn frontend(source: &'static str) -> ColdFrontend {
        dm_tree::frontend::build(
            Path::new("static-duplicate.dme"),
            &Text(source),
            &Default::default(),
            1,
        )
        .unwrap()
    }
    #[test]
    fn duplicate_local_static_binds_current_primary_and_previous_definition() {
        for typed in [false, true] {
            let front = frontend("/proc/probe()\n    var/static/value = 1\n    var/static/value = 2\n    return value\n");
            let bodies = if typed {
                dm_tree::frontend::BodyArena::new_typed(
                    &front,
                    dm_codegen_byond::typed_statements_supported_for_capture,
                )
            } else {
                dm_tree::frontend::BodyArena::new(&front)
            };
            let pool = dm_exec::BuildExecutor::new(1).unwrap();
            let error =
                crate::startup::capture_with_executor_and_bodies(&front, &[], &pool, &bodies)
                    .err()
                    .expect("duplicate static refused");
            let ColdError::Lowering(errors) = capture_error(&front, &bodies, error) else {
                panic!("source error");
            };
            assert_eq!(errors[0].kind, DiagnosticKind::SourceError);
            assert_eq!(errors[0].message, "value: duplicate definition");
            assert_eq!(errors[0].origin.line, 3);
            assert_eq!(errors[0].related[0].message, "value: previous definition");
            assert_eq!(errors[0].related[0].origin.line, 2);
        }
    }
    #[test]
    fn separate_scope_static_slots_remain_uncertified_not_duplicate_errors() {
        let front = frontend("/proc/probe()\n    var/static/value = 1\n    if(1)\n        var/static/value = 2\n    var/static/other = 1\n    var/static/other = 2\n");
        let bodies = dm_tree::frontend::BodyArena::new(&front);
        let pool = dm_exec::BuildExecutor::new(1).unwrap();
        let error = crate::startup::capture_with_executor_and_bodies(&front, &[], &pool, &bodies)
            .err()
            .expect("uncertified scope refused");
        assert!(matches!(
            capture_error(&front, &bodies, error),
            ColdError::Initializer(_)
        ));
    }
}
