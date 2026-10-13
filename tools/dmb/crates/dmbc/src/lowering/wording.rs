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
            if let Some(message) = undefined_procedure(frontend, &error.reason, &statement) {
                return (DiagnosticKind::SourceError, message);
            }
            (
                DiagnosticKind::UnsupportedModel,
                unsupported_message(&statement, &error.reason),
            )
        }
    }
}

/// `(owner=X, name=Y)` of an unanswered procedure query; a hashed name
/// (`#bits`) is matched against the statement's identifiers.
fn procedure_candidate<'a>(reason: &'a str, statement: &'a str) -> Option<(&'a str, bool, &'a str)> {
    let rest = reason.strip_prefix("unsupported semantic query: procedure")?;
    let reference = rest.starts_with(" reference");
    let names = rest.split_once(" (")?.1.strip_suffix(')')?;
    let (owner, name) = names.split_once(", name=")?;
    let owner = owner.strip_prefix("owner=")?;
    let name = match name.strip_prefix('#') {
        None => name,
        Some(bits) => {
            let bits = u64::from_str_radix(bits, 16).ok()?;
            let lexed = dm_syntax::lex_spans(statement);
            lexed
                .tokens
                .iter()
                .filter(|token| token.kind == dm_syntax::TokenKind::Ident)
                .map(|token| token.text(statement))
                .find(|text| SymbolId::of(text).bits() == bits)?
        }
    };
    Some((owner, reference, name))
}

/// DreamMaker's undefined proc / undefined proc path, when the owner exists,
/// neither it nor its ancestry declares the name, and no built-in could.
fn undefined_procedure(frontend: &ColdFrontend, reason: &str, statement: &str) -> Option<String> {
    let (owner, reference, name) = procedure_candidate(reason, statement)?;
    let tree = &frontend.snapshot.tree;
    let owner_id = tree.lookup_type(SymbolId::of(owner))?;
    let symbol = SymbolId::of(name);
    if tree.resolve(owner_id, symbol, MemberKind::Proc).is_some()
        || tree.resolve(owner_id, symbol, MemberKind::Verb).is_some()
        || dm_ir::builtin_names::is_builtin_proc_in(plain_datum(tree, owner_id), name)
    {
        return None;
    }
    let lexed = dm_syntax::lex_spans(statement);
    let tokens: Vec<&str> = lexed
        .tokens
        .iter()
        .filter(|token| {
            !matches!(
                token.kind,
                dm_syntax::TokenKind::Whitespace
                    | dm_syntax::TokenKind::Newline
                    | dm_syntax::TokenKind::Comment
            )
        })
        .map(|token| token.text(statement))
        .collect();
    let at = tokens.iter().position(|token| *token == name)?;
    if reference {
        // The authored path ending in the name: `/datum/x/proc/name`.
        let mut start = at;
        while start >= 3 && tokens[start - 1] == "/" && tokens[start - 3] == "/" {
            start -= 2;
        }
        if start >= 1 && tokens[start - 1] == "/" {
            start -= 1;
        }
        let path: String = tokens[start..=at].concat();
        let whole = start == 1 && tokens[0] == "return" && at + 1 == tokens.len();
        return Some(format!(
            "{}{path}: undefined type path",
            if whole { "return" } else { "" }
        ));
    }
    let mut start = at;
    while start >= 2 && matches!(tokens[start - 1], "." | ":") {
        start -= 2;
    }
    Some(format!("{}: undefined proc", tokens[start..=at].concat()))
}

fn legacy_message(error: &LowerError) -> String {
    if error.statement.is_empty() {
        error.reason.clone()
    } else {
        format!("{}: {}", error.statement, error.reason)
    }
}

/// Apply the lowerer's placement markers: `\u{1}+K\u{1}` moves the message K
/// lines down; each further `\n` line is another diagnostic; a line starting
/// with `\u{2}` belongs at end of file when the statement ends its file.
pub(crate) fn place(
    frontend: &ColdFrontend,
    origin: SourceLocation,
    message: String,
) -> (SourceLocation, String, Vec<crate::lowering::RelatedDiagnostic>) {
    let (shift, body) = match message
        .strip_prefix('\u{1}')
        .and_then(|rest| rest.split_once('\u{1}'))
        .and_then(|(shift, rest)| Some((shift.strip_prefix('+')?.parse::<usize>().ok()?, rest)))
    {
        Some((shift, rest)) => (shift, rest.to_owned()),
        None => (0, message),
    };
    let mut shifted = origin;
    shifted.line += shift;
    let mut lines = body.split('\n').map(|line| match line.strip_prefix('\u{2}') {
        Some(line) => (end_of_file(frontend, &shifted).unwrap_or_else(|| shifted.clone()), line.to_owned()),
        None => (shifted.clone(), line.to_owned()),
    });
    let (primary, text) = lines.next().unwrap_or_else(|| (shifted.clone(), String::new()));
    let related = lines
        .map(|(origin, message)| crate::lowering::RelatedDiagnostic { origin, message })
        .collect();
    (primary, text, related)
}

/// DreamMaker's end-of-file position when nothing but blank lines follows
/// `origin` in its file: the line after the including directive.
fn end_of_file(frontend: &ColdFrontend, origin: &SourceLocation) -> Option<SourceLocation> {
    let file = frontend.source(origin.span.file)?;
    let text = file.text.as_str();
    let next = *file.line_starts.get(origin.line).unwrap_or(&text.len());
    if !text.get(next..)?.trim().is_empty() {
        return None;
    }
    let occurrence = frontend.plan.occurrences.get(origin.include_occurrence)?;
    let mut location = origin.clone();
    match occurrence.parent {
        Some(parent) => {
            location.semantic_path = frontend.plan.occurrences[parent].semantic_path.clone();
            location.line = occurrence.directive_line + 1;
        }
        None => location.line = file.line_starts.len() + 1,
    }
    Some(location)
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
