//! DreamMaker compile errors the native pipeline would otherwise accept.
//!
//! A lexical pass over the current macro-expanded source, run after the
//! frontend and before lowering. It reports only constructs DreamMaker 516
//! rejects (pinned in `fixtures/diagnostics`), never changes lowering or
//! output bytes, and a clean DeepQuarry tree must produce nothing here.
use crate::local_warnings::{significant_lines, Line};
use dm_ir::SymbolId;
use dm_syntax::TokenKind;
use dm_tree::frontend::{
    BodyOccurrence, ColdFrontend, Diagnostic, DiagnosticKind, DiagnosticStage, SourceLocation,
};
use dm_tree::MemberKind;
use rayon::prelude::*;
use std::collections::{BTreeMap, HashSet};

/// All source errors, in authored order.
pub fn check(frontend: &ColdFrontend) -> Vec<Diagnostic> {
    let tree = &frontend.snapshot.tree;
    let var_names: HashSet<SymbolId> = tree
        .members()
        .iter()
        .filter(|member| member.kind == MemberKind::Var)
        .map(|member| member.name)
        .collect();
    let mut bodies: Vec<&BodyOccurrence> = frontend.bodies.iter().collect();
    bodies.sort_by_key(|body| (body.source.encounter_ordinal, body.expanded_span.start));
    let found: Vec<Vec<(usize, String, Option<SourceLocation>)>> = bodies
        .par_iter()
        .map(|body| {
            frontend
                .body_input(body)
                .map(|input| body_errors(frontend, body, input.source(), &var_names))
                .unwrap_or_default()
        })
        .collect();
    let mut errors = Vec::new();
    for (body, found) in bodies.iter().zip(found) {
        for (offset, message, location) in found {
            let location = location.or_else(|| frontend.location(body.expanded_span.start + offset));
            errors.push(source_error(message, location));
        }
    }
    errors.extend(text_errors(frontend));
    errors.extend(unclosed_braces(frontend));
    errors
}

/// A source file whose `{` blocks are still open at its end: DreamMaker
/// reports the line after the including directive. Directive lines (macro
/// bodies included) are not code and are skipped.
fn unclosed_braces(frontend: &ColdFrontend) -> Vec<Diagnostic> {
    let mut errors = Vec::new();
    for (index, occurrence) in frontend.plan.occurrences.iter().enumerate() {
        let Some(parent) = occurrence.parent else {
            continue;
        };
        let extension = occurrence.path.extension().and_then(|ext| ext.to_str()).unwrap_or("");
        if !extension.eq_ignore_ascii_case("dm") {
            continue;
        }
        if frontend.plan.occurrences[..index].iter().any(|earlier| earlier.path == occurrence.path) {
            continue;
        }
        let Some(text) = frontend.plan.source_texts.get(occurrence.path.as_ref()) else {
            continue;
        };
        let text = text.as_str();
        let lexed = dm_syntax::lex_spans(text);
        let mut depth = 0isize;
        let mut line_start = true;
        let mut directive = false;
        let mut continued = false;
        for token in &lexed.tokens {
            let piece = token.text(text);
            match token.kind {
                TokenKind::Newline => {
                    if !continued {
                        directive = false;
                    }
                    line_start = true;
                    continue;
                }
                TokenKind::Whitespace | TokenKind::Comment => continue,
                _ => {}
            }
            if line_start {
                directive = directive || piece == "#";
                line_start = false;
            }
            continued = piece == "\\";
            if directive || token.kind != TokenKind::Punctuation {
                continue;
            }
            match piece {
                "{" => depth += 1,
                "}" => depth -= 1,
                _ => {}
            }
        }
        if depth > 0 {
            let mut location = frontend.bodies.first().map(|body| body.source.clone());
            if let Some(location) = location.as_mut() {
                location.semantic_path = frontend.plan.occurrences[parent].semantic_path.clone();
                location.line = occurrence.directive_line + 1;
            }
            errors.push(source_error("inconsistent indentation or missing '}'".into(), location));
        }
    }
    errors
}

fn source_error(message: String, location: Option<SourceLocation>) -> Diagnostic {
    Diagnostic {
        kind: DiagnosticKind::SourceError,
        stage: DiagnosticStage::Syntax,
        message,
        location,
    }
}

type Token<'a> = (TokenKind, &'a str, usize);

fn line_text<'a>(source: &'a str, line: &Line<'a>) -> &'a str {
    let Some(first) = line.tokens.first() else {
        return "";
    };
    let end = source[first.2..].find('\n').map_or(source.len(), |at| first.2 + at);
    source[first.2..end].trim_end()
}

/// Declared locals: name -> (declared type path, const).
fn locals<'a>(lines: &[Line<'a>]) -> BTreeMap<&'a str, (Option<String>, bool)> {
    let mut locals = BTreeMap::new();
    for line in lines.iter().skip(1) {
        let tokens = &line.tokens;
        if tokens.first().map(|token| token.1) != Some("var")
            || tokens.get(1).map(|token| token.1) != Some("/")
        {
            continue;
        }
        let mut parts = Vec::new();
        let mut index = 2;
        while let Some((TokenKind::Ident, text, _)) = tokens.get(index) {
            parts.push(*text);
            if tokens.get(index + 1).is_some_and(|token| token.1 == "/") {
                index += 2;
            } else {
                break;
            }
        }
        let Some(name) = parts.pop() else {
            continue;
        };
        let constant = parts.contains(&"const");
        let path: Vec<&str> = parts
            .into_iter()
            .filter(|part| !matches!(*part, "static" | "global" | "const" | "tmp"))
            .collect();
        locals
            .entry(name)
            .or_insert(((!path.is_empty()).then(|| format!("/{}", path.join("/"))), constant));
    }
    locals
}

fn parameters<'a>(header: &Line<'a>) -> HashSet<&'a str> {
    let open = header.tokens.iter().position(|token| token.1 == "(");
    header
        .tokens
        .iter()
        .skip(open.map_or(header.tokens.len(), |at| at + 1))
        .filter(|token| token.0 == TokenKind::Ident)
        .map(|token| token.1)
        .collect()
}

fn adjacent(left: &Token<'_>, right: &Token<'_>) -> bool {
    left.2 + left.1.len() == right.2
}

/// `target =`, `target op=`, `target++`, `++target` from token `at`.
fn writes(tokens: &[Token<'_>], start: usize, end: usize) -> bool {
    let text = |at: usize| tokens.get(at).map(|token| token.1);
    let after = end + 1;
    let plain = text(after) == Some("=") && text(after + 1) != Some("=");
    let compound = tokens.get(after).is_some_and(|op| op.0 == TokenKind::Operator)
        && tokens
            .get(after + 1)
            .is_some_and(|eq| eq.1 == "=" && adjacent(&tokens[after], eq))
        && text(after + 2) != Some("=")
        && !matches!(text(after), Some("=" | "!" | "<" | ">"));
    let postfix = matches!((text(after), text(after + 1)), (Some("+"), Some("+")) | (Some("-"), Some("-")));
    let prefix = start >= 2
        && matches!((text(start - 2), text(start - 1)), (Some("+"), Some("+")) | (Some("-"), Some("-")));
    plain || compound || postfix || prefix
}

fn type_path(tree: &dm_tree::SemanticTree, owner: dm_ir::TypeId) -> Option<&str> {
    tree.type_node(owner).and_then(|node| tree.symbols().text(node.path))
}

fn constant_member(tree: &dm_tree::SemanticTree, owner: Option<dm_ir::TypeId>, name: &str) -> bool {
    owner
        .and_then(|owner| tree.resolve(owner, SymbolId::of(name), MemberKind::Var))
        .and_then(|member| tree.member(member))
        .is_some_and(|member| member.metadata.flags & 2 != 0)
}

const BUILTIN_TYPE_ROOTS: &[&str] = &[
    "alist", "appearance", "area", "atom", "callee", "client", "database", "datum", "exception",
    "filters", "generator", "icon", "image", "list", "matrix", "mob", "movable", "mutable_appearance",
    "obj", "particles", "pixloc", "regex", "savefile", "sound", "turf", "vector", "world",
];

pub(crate) fn known_type(tree: &dm_tree::SemanticTree, path: &str) -> bool {
    let root = path.trim_start_matches('/').split('/').next().unwrap_or("");
    tree.lookup_type(SymbolId::of(path)).is_some()
        || (BUILTIN_TYPE_ROOTS.contains(&root) && !path.trim_start_matches('/').contains('/'))
}

fn body_errors(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    source: &str,
    var_names: &HashSet<SymbolId>,
) -> Vec<(usize, String, Option<SourceLocation>)> {
    let tree = &frontend.snapshot.tree;
    let owner = tree.member(body.member).map(|member| member.owner);
    let lines = significant_lines(source);
    let Some(header) = lines.first() else {
        return Vec::new();
    };
    let locals = locals(&lines);
    let parameters = parameters(header);
    let mut errors = Vec::new();
    let mut braces = 0isize;
    let mut reported_types = HashSet::new();
    for line in lines.iter().skip(1) {
        let tokens = &line.tokens;
        for (index, token) in tokens.iter().enumerate() {
            if token.0 == TokenKind::Punctuation {
                match token.1 {
                    "{" => braces += 1,
                    "}" => braces -= 1,
                    _ => {}
                }
            }
            if token.0 != TokenKind::Ident {
                continue;
            }
            let previous = index.checked_sub(1).map(|at| tokens[at].1);
            let declaration = tokens.first().map(|first| first.1) == Some("var");
            // Constant assignment: `C`, `src.C`, `typed.C`.
            if !declaration && !matches!(previous, Some("." | ":" | "/")) {
                let member = tokens.get(index + 1).is_some_and(|dot| dot.1 == ".")
                    && tokens.get(index + 2).is_some_and(|name| name.0 == TokenKind::Ident);
                let (end, field_owner, field, subject) = if member {
                    let receiver = token.1;
                    let owner_type = if receiver == "src" {
                        owner
                    } else {
                        locals
                            .get(receiver)
                            .and_then(|(path, _)| path.as_deref())
                            .and_then(|path| tree.lookup_type(SymbolId::of(path)))
                    };
                    let field = tokens[index + 2].1;
                    (index + 2, owner_type, field, format!("{receiver}.{field}"))
                } else {
                    (index, owner, token.1, token.1.to_owned())
                };
                let local = locals.get(token.1);
                let constant = if member {
                    constant_member(tree, field_owner, field)
                } else if let Some((_, constant)) = local {
                    *constant
                } else {
                    !parameters.contains(token.1) && constant_member(tree, owner, field)
                };
                if constant && writes(tokens, index, end) {
                    errors.push((token.2, format!("{subject}: cannot change constant value"), None));
                }
            }
            // `X:name` with no type anywhere declaring `name`.
            if previous == Some(":")
                && index >= 2
                && adjacent(&tokens[index - 2], &tokens[index - 1])
                && adjacent(&tokens[index - 1], token)
                && (tokens[index - 2].0 == TokenKind::Ident || matches!(tokens[index - 2].1, ")" | "]"))
                && tokens.get(index + 1).is_none_or(|next| next.1 != "(")
                && !tokens[..index].iter().any(|earlier| earlier.1 == "?")
                && !var_names.contains(&SymbolId::of(token.1))
                && !dm_ir::builtin_names::is_builtin_var(token.1)
            {
                errors.push((
                    token.2,
                    dm_codegen_byond::undefined_member_message(line_text(source, line), token.1),
                    None,
                ));
            }
            // A read of a local whose declared type does not exist.
            if !declaration && !matches!(previous, Some("." | ":" | "/")) {
                if let Some((Some(path), _)) = locals.get(token.1) {
                    if !parameters.contains(token.1)
                        && !path.starts_with("/list")
                        && !known_type(tree, path)
                        && reported_types.insert(token.1)
                    {
                        let statement = line_text(source, line);
                        let subject = match statement.strip_prefix("return") {
                            Some(rest) if rest.trim() == token.1 => format!("return{}", token.1),
                            _ => token.1.to_owned(),
                        };
                        errors.push((token.2, format!("{subject}: undefined type: {path}"), None));
                    }
                }
            }
        }
    }
    let _ = braces;
    // A line whose indentation is neither an extension nor a prefix of the
    // previous code line's (tabs against spaces).
    let mut previous: Option<&str> = None;
    for line in lines.iter().skip(1) {
        if line.tokens.is_empty() || line.continuation {
            continue;
        }
        if let Some(previous) = previous {
            let current = line.indent_text;
            if !current.starts_with(previous) && !previous.starts_with(current) {
                errors.push((line.tokens[0].2, "inconsistent indentation".into(), None));
                break;
            }
        }
        previous = Some(line.indent_text);
    }
    errors
}

/// DreamMaker's text macros and escapes that a word after `\` may name.
const TEXT_MACROS: &[&str] = &[
    "A", "An", "His", "Hers", "He", "Roman", "She", "The", "a", "an", "b", "black", "blue", "bold",
    "c", "cyan", "f", "font", "green", "he", "hers", "herself", "him", "himself", "his", "i",
    "icon", "improper", "italic", "l", "o", "proper", "red", "ref", "roman", "s", "she", "th",
    "the", "u", "white", "yellow",
];

fn valid_escape(after: &str) -> bool {
    let mut chars = after.chars();
    let Some(first) = chars.next() else {
        return true;
    };
    match first {
        '"' | '\\' | '[' | ']' | '<' | '>' | '\'' | '&' | ' ' | '\t' | '\r' | '\n' | 'n' | 't' => true,
        'x' if after.len() >= 3 && after[1..3].chars().all(|ch| ch.is_ascii_hexdigit()) => true,
        'u' if after.len() >= 5 && after[1..5].chars().all(|ch| ch.is_ascii_hexdigit()) => true,
        ch if ch.is_ascii_alphanumeric() => {
            let word: String = after
                .chars()
                .take_while(|ch| ch.is_ascii_alphanumeric() || *ch == '_')
                .collect();
            TEXT_MACROS.contains(&word.as_str())
        }
        _ => false,
    }
}

/// Text with embedded expressions collapsed to `[]`, as DreamMaker quotes it.
fn collapsed(text: &str) -> String {
    let mut out = String::new();
    let mut depth = 0usize;
    for ch in text.chars() {
        match ch {
            '[' => {
                if depth == 0 {
                    out.push('[');
                }
                depth += 1;
            }
            ']' if depth > 0 => {
                depth -= 1;
                if depth == 0 {
                    out.push(']');
                }
            }
            _ if depth == 0 => out.push(ch),
            _ => {}
        }
    }
    out
}

/// Undefined text escapes and constant division by zero, over all code.
fn text_errors(frontend: &ColdFrontend) -> Vec<Diagnostic> {
    let text = frontend.expanded.text.as_str();
    let lexed = dm_syntax::lex_spans(text);
    let tokens: Vec<Token<'_>> = lexed
        .tokens
        .iter()
        .filter(|token| !matches!(token.kind, TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment))
        .map(|token| (token.kind, token.text(text), token.span.start))
        .collect();
    let mut errors = Vec::new();
    for (index, token) in tokens.iter().enumerate() {
        match token.0 {
            TokenKind::String | TokenKind::Interpolation if token.1.starts_with('"') || token.1.starts_with("{\"") => {
                let quote = if token.1.starts_with('{') { 2 } else { 1 };
                let body = &token.1[quote..token.1.len().saturating_sub(quote).max(quote)];
                let mut at = 0;
                while let Some(found) = body[at..].find('\\') {
                    let position = at + found;
                    let after = &body[position + 1..];
                    if after.starts_with('\\') {
                        at = position + 2;
                        continue;
                    }
                    if !valid_escape(after) {
                        let line_start = text[..token.2].rfind('\n').map_or(0, |at| at + 1);
                        let line_end = text[token.2..].find('\n').map_or(text.len(), |at| token.2 + at);
                        let statement: String = dm_syntax::lex_spans(&text[line_start..line_end])
                            .tokens
                            .iter()
                            .filter(|token| !matches!(token.kind, TokenKind::Whitespace | TokenKind::Comment))
                            .map(|token| token.text(&text[line_start..line_end]))
                            .collect();
                        let subject = if body.contains('[') {
                            format!("text\"{}\"", collapsed(body))
                        } else {
                            statement
                        };
                        errors.push(source_error(
                            format!(
                                "{subject}: undefined text macro or escape sequence: \\{}",
                                collapsed(after)
                            ),
                            frontend.location(token.2),
                        ));
                        break;
                    }
                    at = position + 1;
                }
            }
            TokenKind::Number if is_zero(token.1) && index >= 2 => {
                let operator = tokens[index - 1].1;
                let left = tokens[index - 2];
                if operator == "%" || (operator == "/" && left.0 == TokenKind::Number) {
                    errors.push(source_error(
                        format!("{}: attempted division by zero", token.1),
                        frontend.location(token.2),
                    ));
                }
            }
            _ => {}
        }
    }
    errors
}

fn is_zero(number: &str) -> bool {
    number.parse::<f64>().is_ok_and(|value| value == 0.0)
}

#[cfg(test)]
mod tests {
    use super::{collapsed, valid_escape};
    #[test]
    fn escapes_follow_dreammaker() {
        for valid in ["n", "nabc", "the", "theabc", "x41", "u0041", "\"", " ", "proper[x]", "s"] {
            assert!(valid_escape(valid), "{valid}");
        }
        for invalid in ["qdef", "abc", "x4", "1", ".", "Ref", "its"] {
            assert!(!valid_escape(invalid), "{invalid}");
        }
        assert_eq!(collapsed("a\\q[src.name] b"), "a\\q[] b");
    }
}
