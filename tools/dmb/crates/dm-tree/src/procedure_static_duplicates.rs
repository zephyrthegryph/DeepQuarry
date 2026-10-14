//! Exact duplicate stored declarations within one typed lexical statement scope.
use super::{stored_local_modifier, Span, Statement, StatementKind};
use std::collections::HashMap;

pub struct DuplicateStaticDeclaration {
    pub name: String,
    pub current: Span,
    pub previous: Span,
}

/// This proves only a same-scope duplicate. Separate lexical scopes retain the
/// ordinary static slot policy; this query never assigns or aliases their slots.
pub fn duplicate_static_declaration(
    statements: &[Statement],
) -> Option<DuplicateStaticDeclaration> {
    walk(statements, &mut HashMap::new(), &mut 0).ok().flatten()
}
fn walk<'a>(
    statements: &'a [Statement],
    names: &mut HashMap<&'a str, (usize, Span)>,
    next_scope: &mut usize,
) -> Result<Option<DuplicateStaticDeclaration>, ()> {
    let scope = *next_scope;
    *next_scope += 1;
    for statement in statements {
        if let StatementKind::Var { declaration, .. } = &statement.kind {
            let path = declaration
                .strip_prefix("var/")
                .or_else(|| declaration.strip_prefix("var "))
                .ok_or(())?;
            let path = path.split('[').next().ok_or(())?.trim();
            let parts: Vec<_> = path.split('/').filter(|part| !part.is_empty()).collect();
            if let Some((name, prefix)) = parts.split_last() {
                if prefix.iter().any(|part| stored_local_modifier(part) != 0) {
                    if let Some((previous_scope, previous)) =
                        names.insert(*name, (scope, statement.header_span))
                    {
                        // The startup issuer stops at this first name collision.
                        // Cross-scope collisions are not a source-error proof.
                        if previous_scope != scope {
                            return Err(());
                        }
                        return Ok(Some(DuplicateStaticDeclaration {
                            name: (*name).to_owned(),
                            current: statement.header_span,
                            previous,
                        }));
                    }
                }
            }
        }
        let mut children: Vec<&[Statement]> = Vec::new();
        match &statement.kind {
            StatementKind::If {
                then_branch,
                else_branch,
                ..
            } => {
                children.push(then_branch);
                children.push(else_branch);
            }
            StatementKind::While { body, .. }
            | StatementKind::DoWhile { body, .. }
            | StatementKind::Spawn { body, .. }
            | StatementKind::Label { body, .. }
            | StatementKind::For { body, .. } => children.push(body),
            StatementKind::Switch {
                cases, else_branch, ..
            } => {
                children.extend(cases.iter().map(|case| case.body.as_slice()));
                children.push(else_branch);
            }
            StatementKind::Try {
                body, catch_body, ..
            } => {
                children.push(body);
                children.push(catch_body);
            }
            _ => (),
        }
        for child in children {
            if let Some(duplicate) = walk(child, names, next_scope)? {
                return Ok(Some(duplicate));
            }
        }
    }
    Ok(None)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn duplicate_static_requires_same_lexical_scope_and_keeps_exact_origins() {
        let ast =
            dm_syntax::parse("/proc/probe()\n    var/static/value = 1\n    var/static/value = 2\n");
        let parsed = dm_syntax::parse_body_items(&ast.items[0].children);
        let duplicate = duplicate_static_declaration(&parsed.statements).unwrap();
        assert_eq!(duplicate.name, "value");
        assert_eq!(
            duplicate.current.start,
            parsed.statements[1].header_span.start
        );
        assert_eq!(
            duplicate.previous.start,
            parsed.statements[0].header_span.start
        );
        let ast = dm_syntax::parse("/proc/probe()\n    var/static/value = 1\n    if(1)\n        var/static/value = 2\n    if(0)\n        var/static/value = 3\n");
        let parsed = dm_syntax::parse_body_items(&ast.items[0].children);
        assert!(duplicate_static_declaration(&parsed.statements).is_none());
    }
}
