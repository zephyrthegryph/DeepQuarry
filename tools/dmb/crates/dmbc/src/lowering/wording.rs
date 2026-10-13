//! User-facing classification and wording of procedure lowering failures.
//! Source errors keep the lowerer's DreamMaker wording. A resolver gap for a
//! variable the source tree provably lacks (and that no BYOND built-in of the
//! owner could supply) is the author's undefined variable. Remaining native
//! limitations become one line naming the statement, never internal query
//! structures.
use dm_codegen_byond::{LowerError, LowerErrorKind};
use dm_ir::SymbolId;
use dm_tree::frontend::{ColdFrontend, DiagnosticKind, SourceLocation};
use dm_tree::MemberKind;

/// Classification and message for a lowering error reported at `origin`.
pub(crate) fn present(
    frontend: &ColdFrontend,
    origin: &SourceLocation,
    error: &LowerError,
) -> (DiagnosticKind, String) {
    match error.kind {
        LowerErrorKind::Internal => (DiagnosticKind::Internal, legacy_message(error)),
        LowerErrorKind::SourceError => (DiagnosticKind::SourceError, error.reason.clone()),
        LowerErrorKind::UnsupportedModel => {
            let statement = if error.statement.trim().is_empty() {
                origin_line(frontend, origin).unwrap_or_default()
            } else {
                error.statement.clone()
            };
            if let Some((owner, name)) =
                dm_codegen_byond::unresolved_variable_candidate(&error.reason, &statement)
            {
                // `global.name` asks for `name` among global variables.
                let (owner, name) = match (name, global_member(&statement)) {
                    ("global", Some(member)) => (None, member),
                    _ => (owner, name),
                };
                if undefined_variable(frontend, owner.unwrap_or("/"), name) {
                    return (
                        DiagnosticKind::SourceError,
                        dm_codegen_byond::undefined_member_message(&statement, name),
                    );
                }
            }
            (
                DiagnosticKind::UnsupportedModel,
                unsupported_message(&statement, &error.reason),
            )
        }
    }
}

fn legacy_message(error: &LowerError) -> String {
    if error.statement.is_empty() {
        error.reason.clone()
    } else {
        format!("{}: {}", error.statement, error.reason)
    }
}

/// The selector of the first `global.name` in a statement.
fn global_member(statement: &str) -> Option<&str> {
    let lexed = dm_syntax::lex_spans(statement);
    let tokens: Vec<&str> = lexed
        .tokens
        .iter()
        .filter(|token| token.kind == dm_syntax::TokenKind::Ident || token.kind == dm_syntax::TokenKind::Punctuation)
        .map(|token| token.text(statement))
        .collect();
    tokens
        .windows(3)
        .find(|window| window[0] == "global" && window[1] == ".")
        .map(|window| window[2])
}

/// The owner type exists, declares no such variable in its source ancestry,
/// and no built-in type in that ancestry could supply it.
fn undefined_variable(frontend: &ColdFrontend, owner: &str, name: &str) -> bool {
    let tree = &frontend.snapshot.tree;
    let Some(owner) = tree.lookup_type(SymbolId::of(owner)) else {
        return false;
    };
    if tree.resolve(owner, SymbolId::of(name), MemberKind::Var).is_some() {
        return false;
    }
    !dm_ir::builtin_names::is_builtin_var_in(plain_datum(tree, owner), name)
}

/// No type in the ancestry lies under a built-in root other than /datum.
pub(crate) fn plain_datum(tree: &dm_tree::SemanticTree, owner: dm_ir::TypeId) -> bool {
    // Global scope sees every built-in name.
    if tree.parent(owner).is_none() {
        return false;
    }
    let mut cursor = Some(owner);
    while let Some(id) = cursor {
        let path = tree
            .type_node(id)
            .and_then(|node| tree.symbols().text(node.path))
            .unwrap_or("/");
        if path != "/" && !dm_ir::builtin_names::is_plain_datum_path(path) {
            return false;
        }
        cursor = tree.parent(id);
    }
    true
}

/// Authored text of the origin's source line.
fn origin_line(frontend: &ColdFrontend, origin: &SourceLocation) -> Option<String> {
    let file = frontend.source(origin.span.file)?;
    let text = file.text.as_str();
    let start = *file.line_starts.get(origin.line.checked_sub(1)?)?;
    let end = file
        .line_starts
        .get(origin.line)
        .copied()
        .unwrap_or(text.len());
    Some(text.get(start..end)?.trim().to_owned())
}

pub(crate) fn unsupported_message(statement: &str, reason: &str) -> String {
    let first = statement
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or("");
    let mut subject: String = first.chars().take(60).collect();
    if first.chars().count() > 60 || statement.trim().lines().count() > 1 {
        subject.push_str("...");
    }
    let reason = reason.lines().next().unwrap_or(reason).trim();
    if subject.is_empty() {
        format!("native compiler does not support this yet ({reason})")
    } else {
        format!("{subject}: native compiler does not support this yet ({reason})")
    }
}

#[cfg(test)]
mod tests {
    use super::unsupported_message;
    #[test]
    fn unsupported_wording_is_one_line_and_bounded() {
        let message = unsupported_message(
            "foo(\n\tvar/y = 2\n\treturn y",
            "expression syntax is unsupported",
        );
        assert_eq!(
            message,
            "foo(...: native compiler does not support this yet (expression syntax is unsupported)"
        );
        assert!(!message.contains('\n'));
    }
}
