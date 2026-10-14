//! Ownership-preserving transforms over the shared statement model.
use crate::{Statement, StatementKind};

/// Retain statements in encounter order, recursively including every control
/// flow branch. Empty guards and bodies remain present.
pub fn filter_statements(
    statements: Vec<Statement>,
    keep: &mut impl FnMut(&Statement) -> bool,
) -> Vec<Statement> {
    statements
        .into_iter()
        .filter_map(|mut statement| {
            if !keep(&statement) {
                return None;
            }
            let mut filter = |body: &mut Vec<Statement>| {
                *body = filter_statements(std::mem::take(body), keep);
            };
            match &mut statement.kind {
                StatementKind::If {
                    then_branch,
                    else_branch,
                    ..
                } => {
                    filter(then_branch);
                    filter(else_branch);
                }
                StatementKind::While { body, .. }
                | StatementKind::DoWhile { body, .. }
                | StatementKind::Spawn { body, .. }
                | StatementKind::For { body, .. }
                | StatementKind::Label { body, .. } => filter(body),
                StatementKind::Switch {
                    cases, else_branch, ..
                } => {
                    for case in cases {
                        filter(&mut case.body);
                    }
                    filter(else_branch);
                }
                StatementKind::Try {
                    body, catch_body, ..
                } => {
                    filter(body);
                    filter(catch_body);
                }
                _ => (),
            }
            Some(statement)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn filter_moves_headers_and_preserves_empty_runtime_guards() {
        let source = crate::parse(
            "/proc/p()\n    if(1)\n        set waitfor = 0\n    else\n        return 7\n",
        );
        let parsed = crate::parse_body_items(&source.items[0].children);
        assert!(parsed.diagnostics.is_empty());
        let header = parsed.statements[0].raw_header.as_ptr();
        let result = filter_statements(parsed.statements, &mut |statement| {
            !matches!(statement.kind, StatementKind::Set { .. })
        });
        assert_eq!(result[0].raw_header.as_ptr(), header);
        let StatementKind::If {
            then_branch,
            else_branch,
            ..
        } = &result[0].kind
        else {
            panic!("guard lost")
        };
        assert!(then_branch.is_empty());
        assert_eq!(else_branch.len(), 1);
    }
}
