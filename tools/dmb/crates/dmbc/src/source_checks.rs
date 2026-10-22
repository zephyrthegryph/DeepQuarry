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
    dm_profile::request_mark("source_checks.bodies");
    let mut errors = Vec::new();
    for (body, found) in bodies.iter().zip(found) {
        for (offset, message, location) in found {
            let location = location.or_else(|| frontend.location(body.expanded_span.start + offset));
            errors.push(source_error(message, location));
        }
    }
    errors.extend(text_errors(frontend));
    errors.extend(raw_text_errors(frontend));
    dm_profile::request_mark("source_checks.text");
    errors.extend(unclosed_braces(frontend));
    dm_profile::request_mark("source_checks.braces");
    errors
}

/// A source file whose `{` blocks are still open at its end: DreamMaker
/// reports the line after the including directive. Directive lines (macro
/// bodies included) are not code and are skipped.
fn unclosed_braces(frontend: &ColdFrontend) -> Vec<Diagnostic> {
    // First occurrence of each DM file, in include order.
    let mut seen = HashSet::new();
    let candidates: Vec<(usize, usize, &str)> = frontend
        .plan
        .occurrences
        .iter()
        .enumerate()
        .filter_map(|(index, occurrence)| {
            let parent = occurrence.parent?;
            let extension = occurrence.path.extension().and_then(|ext| ext.to_str()).unwrap_or("");
            if !extension.eq_ignore_ascii_case("dm") || !seen.insert(occurrence.path.as_ref()) {
                return None;
            }
            let text = frontend.plan.source_texts.get(occurrence.path.as_ref())?;
            Some((index, parent, text.as_str()))
        })
        .collect();
    // Open-brace state per file text, cached by text digest: an edit relexes
    // only the files it changed.
    static CACHE: std::sync::OnceLock<std::sync::Mutex<std::collections::HashMap<u128, bool>>> =
        std::sync::OnceLock::new();
    let cache = CACHE.get_or_init(Default::default);
    let open: Vec<bool> = candidates
        .par_iter()
        .map(|(_, _, text)| {
            let digest = xxhash_rust::xxh3::xxh3_128(text.as_bytes());
            if let Some(&open) = cache.lock().unwrap_or_else(|e| e.into_inner()).get(&digest) {
                return open;
            }
            let open = braces_open(text);
            let mut cache = cache.lock().unwrap_or_else(|e| e.into_inner());
            if cache.len() > 1 << 18 {
                cache.clear();
            }
            cache.insert(digest, open);
            open
        })
        .collect();
    let mut errors = Vec::new();
    for ((index, parent, _), open) in candidates.into_iter().zip(open) {
        if open {
            let occurrence = &frontend.plan.occurrences[index];
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

/// Whether a file's `{` blocks are still open at its end.
fn braces_open(text: &str) -> bool {
    {
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
        depth > 0
    }
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

/// Words DreamMaker will not take as a formal's name (`if = null`, `set = null`).
const RESERVED_FORMAL_NAMES: &[&str] = &[
    "if", "else", "while", "var", "set", "for", "do", "switch", "spawn",
];

/// Operator words that cannot be the left side of `=`: `f(to = 1)` and `proc/f(to = null)` are
/// `missing left-hand argument to to.` and `... to =.` in DreamMaker, which reads them as the
/// operator. Reserved statement words are rejected as formal names only (pinned 516.1687,
/// fixtures/diagnostics/cases/keyword_*).
fn keyword_argument_errors(lines: &[Line<'_>], errors: &mut Vec<(usize, String, Option<SourceLocation>)>) {
    for (line_index, line) in lines.iter().enumerate() {
        let tokens = &line.tokens;
        let mut depth = 0usize;
        for (index, token) in tokens.iter().enumerate() {
            if token.0 == TokenKind::Punctuation {
                match token.1 {
                    "(" => depth += 1,
                    ")" => depth = depth.saturating_sub(1),
                    _ => {}
                }
            }
            if token.0 != TokenKind::Ident || depth == 0 {
                continue;
            }
            let opens = index
                .checked_sub(1)
                .map(|at| tokens[at].1)
                .is_some_and(|previous| matches!(previous, "(" | ","));
            if !opens {
                continue;
            }
            let next = tokens.get(index + 1).map(|next| next.1);
            let assigned = next == Some("=") && tokens.get(index + 2).map(|n| n.1) != Some("=");
            if assigned && matches!(token.1, "to" | "in") {
                errors.push((token.2, format!("missing left-hand argument to {}.", token.1), None));
                errors.push((token.2, "missing left-hand argument to =.".to_owned(), None));
            } else if line_index == 0
                && RESERVED_FORMAL_NAMES.contains(&token.1)
                && matches!(next, Some("=" | "," | ")"))
            {
                errors.push((token.2, format!("{}: invalid variable name: reserved word", token.1), None));
            }
        }
    }
}

/// `var/to`, `var/to = 1` and `var/obj/to = x`: the operator words cannot name a local. DreamMaker reports the bare form on the
/// word (`missing left-hand argument to to.`) and the typed form on the assignment (`... to =.`); pinned 516.1687.
fn keyword_local_errors(lines: &[Line<'_>], errors: &mut Vec<(usize, String, Option<SourceLocation>)>) {
    for line in lines.iter().skip(1) {
        let tokens = &line.tokens;
        if tokens.first().map(|token| token.1) != Some("var") || tokens.get(1).map(|token| token.1) != Some("/") {
            continue;
        }
        let mut index = 2;
        let mut parts = Vec::new();
        while let Some((TokenKind::Ident, text, _)) = tokens.get(index) {
            parts.push((*text, tokens[index].2));
            if tokens.get(index + 1).is_some_and(|token| token.1 == "/") {
                index += 2;
            } else {
                break;
            }
        }
        let Some(&(name, offset)) = parts.last() else {
            continue;
        };
        if !matches!(name, "to" | "in") {
            continue;
        }
        let assigned = tokens.get(index + 1).is_some_and(|token| token.1 == "=");
        if parts.len() == 1 {
            errors.push((offset, format!("missing left-hand argument to {name}."), None));
        } else if assigned {
            errors.push((offset, "missing left-hand argument to =.".to_owned(), None));
        }
    }
}

/// `typesof(/T/verb)` and `typesof(/T/proc)` name a path that exists only when `/T` itself declares such a member (inherited ones do
/// not count), and `typesof(/world)` is not a prototype. DreamMaker: `<path>: undefined type path`, `/world: not a prototype`; pinned
/// 516.1687 (fixtures/diagnostics/cases/typesof_*). Only `verb` is checked here: the engine's own procs are not in the tree.
fn typesof_errors(
    tree: &dm_tree::SemanticTree,
    lines: &[Line<'_>],
    errors: &mut Vec<(usize, String, Option<SourceLocation>)>,
) {
    for line in lines {
        let tokens = &line.tokens;
        for (index, token) in tokens.iter().enumerate() {
            if token.1 != "typesof" || tokens.get(index + 1).map(|next| next.1) != Some("(") {
                continue;
            }
            let mut at = index + 2;
            let start = at;
            let mut path = String::new();
            while tokens.get(at).map(|token| token.1) == Some("/") {
                match tokens.get(at + 1) {
                    Some((TokenKind::Ident, name, _)) => {
                        path.push('/');
                        path.push_str(name);
                        at += 2;
                    }
                    _ => break,
                }
            }
            if path.is_empty() || !matches!(tokens.get(at).map(|token| token.1), Some(")" | ",")) {
                continue;
            }
            let offset = tokens[start].2;
            if path == "/world" {
                errors.push((offset, "/world: not a prototype".to_owned(), None));
            } else if let Some(owner) = path.strip_suffix("/verb") {
                let declares = tree
                    .lookup_type(SymbolId::of(owner))
                    .is_some_and(|owner| tree.members().iter().any(|member| member.owner == owner && member.kind == MemberKind::Verb));
                if !declares {
                    errors.push((offset, format!("{path}: undefined type path"), None));
                }
            }
        }
    }
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
    keyword_argument_errors(&lines, &mut errors);
    keyword_local_errors(&lines, &mut errors);
    typesof_errors(tree, &lines, &mut errors);
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
/// Per-piece screen for `text_errors`, cached by the piece's text digest.
/// Pieces are the expanded text cut at body boundaries (a body is a complete
/// statement block, so no token crosses a cut). A piece with any possible
/// error, or a boundary that could complete one, sends the request to the
/// exact whole-text pass; a clean tree never does.
#[derive(Clone)]
struct PieceScreen {
    candidate: bool,
    /// First two and last two significant tokens, for cross-cut lookbehind.
    head: Vec<(TokenKind, String)>,
    tail: Vec<(TokenKind, String)>,
}

/// A plain `"text"` literal that runs over a line break. DreamMaker ends the literal at the newline (`unterminated text
/// (expecting ")`); only `{"..."}` is multi-line, and a backslash before the break continues the literal. Pinned 516.1687.
fn unterminated_plain_text(token: &str) -> bool {
    unterminated_break(token).is_some()
}

/// The byte offset (in the token) of the first line break DreamMaker ends the literal at. A backslash before a break continues the
/// literal and also skips the whitespace that follows, blank lines included (pinned 516.1687).
fn unterminated_break(token: &str) -> Option<usize> {
    if !token.starts_with('"') {
        return None;
    }
    scan_text(token.as_bytes(), 0).1
}

/// Scans the literal opening at `bytes[start]`: the index after it, and the first bare break inside the text itself. Breaks inside
/// an embedded `[expression]` are code, and its own literals are scanned the same way.
fn scan_text(bytes: &[u8], start: usize) -> (usize, Option<usize>) {
    let mut at = start + 1;
    while at < bytes.len() {
        match bytes[at] {
            b'\\' => {
                // Only a backslash directly before LF continues the literal; before CR LF it does not (pinned 516.1681).
                let next = at + 1;
                if bytes.get(next) == Some(&b'\n') {
                    at = next + 1;
                    while bytes.get(at).is_some_and(|byte| matches!(byte, b' ' | b'\t' | b'\r' | b'\n')) {
                        at += 1;
                    }
                } else {
                    at += 2;
                }
            }
            b'\n' => return (at, Some(at)),
            b'[' => {
                let mut depth = 1;
                at += 1;
                while at < bytes.len() && depth > 0 {
                    match bytes[at] {
                        b'"' => {
                            let (end, bad) = scan_text(bytes, at);
                            if bad.is_some() {
                                return (end, bad);
                            }
                            at = end;
                            continue;
                        }
                        b'[' => depth += 1,
                        b']' => depth -= 1,
                        _ => {}
                    }
                    at += 1;
                }
            }
            b'"' => return (at + 1, None),
            _ => at += 1,
        }
    }
    (at, None)
}

/// Offsets of every unterminated literal one lexer token causes. DreamMaker ends the literal at the break and lexes the next line
/// afresh, so a leftover `"` on a following line (the old literal's closing quote) opens a literal of its own that the line never
/// closes: one more error at that quote (pinned 516.1681, fixtures/diagnostics/cases/string_backslash_crlf).
fn literal_break_errors(text: &str, start: usize, end: usize, token: &str) -> Vec<usize> {
    let Some(at) = unterminated_break(token) else {
        return Vec::new();
    };
    let mut found = vec![start + at];
    let mut line = start + at + 1;
    while line < text.len() && line <= end {
        let line_end = text[line..].find('\n').map_or(text.len(), |next| line + next);
        let bytes = text[line..line_end].as_bytes();
        let mut open = None;
        let mut index = 0;
        while index < bytes.len() {
            match bytes[index] {
                b'\\' => index += 1,
                b'/' if bytes.get(index + 1) == Some(&b'/') => break,
                b'"' => open = if open.is_some() { None } else { Some(line + index) },
                _ => {}
            }
            index += 1;
        }
        if let Some(quote) = open {
            found.push(quote);
        }
        line = line_end + 1;
    }
    found
}

/// Offsets of plain `"text"` literals that run over a line break in one source file, cached by content.
fn unterminated_text_offsets(text: &str) -> Vec<usize> {
    static CACHE: std::sync::OnceLock<std::sync::Mutex<std::collections::HashMap<u128, Vec<usize>>>> =
        std::sync::OnceLock::new();
    let cache = CACHE.get_or_init(Default::default);
    let digest = xxhash_rust::xxh3::xxh3_128(text.as_bytes());
    if let Some(found) = cache.lock().unwrap_or_else(|e| e.into_inner()).get(&digest) {
        return found.clone();
    }
    let found: Vec<usize> = if text.contains('"') {
        dm_syntax::lex_spans(text)
            .tokens
            .iter()
            .filter(|token| matches!(token.kind, TokenKind::String | TokenKind::Interpolation))
            .flat_map(|token| literal_break_errors(text, token.span.start, token.span.end, token.text(text)))
            .collect()
    } else {
        Vec::new()
    };
    let mut cache = cache.lock().unwrap_or_else(|e| e.into_inner());
    if cache.len() > 1 << 16 {
        cache.clear();
    }
    cache.insert(digest, found.clone());
    found
}

/// `"text"` over a line break, read from the source files themselves: in expanded text a backslash continuation has already become
/// a break, so only the original bytes tell the two apart. DreamMaker: `unterminated text (expecting ")` at the opening line.
fn raw_text_errors(frontend: &ColdFrontend) -> Vec<Diagnostic> {
    let found: Vec<(usize, Vec<usize>)> = frontend
        .files
        .par_iter()
        .enumerate()
        .filter(|(_, file)| file.captured && file.path.extension().is_some_and(|extension| extension == "dm"))
        .map(|(index, file)| (index, unterminated_text_offsets(file.text.as_str())))
        .filter(|(_, offsets)| !offsets.is_empty())
        .collect();
    let mut errors = Vec::new();
    for (index, offsets) in found {
        let file = &frontend.files[index];
        let Some(occurrence) = frontend
            .plan
            .occurrences
            .iter()
            .position(|include| !include.suppressed && include.path == file.path)
        else {
            continue;
        };
        let include = &frontend.plan.occurrences[occurrence];
        let mut chain = vec![occurrence];
        let mut parent = include.parent;
        while let Some(next) = parent {
            chain.push(next);
            parent = frontend.plan.occurrences[next].parent;
        }
        chain.reverse();
        let encounter_ordinal = frontend
            .plan
            .regions
            .iter()
            .find(|region| region.occurrence == occurrence)
            .map_or(0, |region| region.encounter_ordinal);
        for offset in offsets {
            let line = file.line_starts.partition_point(|start| *start <= offset);
            errors.push(source_error(
                "unterminated text (expecting \")".to_owned(),
                Some(SourceLocation {
                    span: dm_ir::Span {
                        file: file.id,
                        start: offset as u32,
                        end: offset as u32,
                    },
                    path: std::sync::Arc::clone(&include.path),
                    semantic_path: std::sync::Arc::clone(&include.semantic_path),
                    line,
                    encounter_ordinal,
                    include_occurrence: occurrence,
                    include_chain: chain.clone().into(),
                    macro_expansions: std::sync::Arc::new(Vec::new()),
                }),
            ));
        }
    }
    errors
}

fn screen_piece(text: &str) -> PieceScreen {
    let lexed = dm_syntax::lex_spans(text);
    let tokens: Vec<Token<'_>> = lexed
        .tokens
        .iter()
        .filter(|token| !matches!(token.kind, TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment))
        .map(|token| (token.kind, token.text(text), token.span.start))
        .collect();
    let mut candidate = false;
    for (index, token) in tokens.iter().enumerate() {
        match token.0 {
            TokenKind::String | TokenKind::Interpolation if token.1.starts_with('"') || token.1.starts_with("{\"") => {
                if unterminated_plain_text(token.1) {
                    // DreamMaker reports the unterminated literal and never reads its escapes.
                    continue;
                }
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
                        candidate = true;
                        break;
                    }
                    at = position + 1;
                }
            }
            TokenKind::Number if index >= 2 => {
                let operator = tokens[index - 1].1;
                let left = tokens[index - 2];
                candidate |= zero_divisor(token.1, operator, left.1)
                    && (operator == "%" || left.0 == TokenKind::Number);
            }
            _ => {}
        }
        if candidate {
            break;
        }
    }
    let owned = |token: &Token<'_>| (token.0, token.1.to_owned());
    PieceScreen {
        candidate,
        head: tokens.iter().take(2).map(owned).collect(),
        tail: tokens.iter().rev().take(2).rev().map(owned).collect(),
    }
}

fn piece_cache() -> &'static std::sync::Mutex<std::collections::HashMap<u128, PieceScreen>> {
    static CACHE: std::sync::OnceLock<std::sync::Mutex<std::collections::HashMap<u128, PieceScreen>>> =
        std::sync::OnceLock::new();
    CACHE.get_or_init(Default::default)
}

/// Whether the exact text pass could report anything.
fn text_may_error(frontend: &ColdFrontend) -> bool {
    let text = frontend.expanded.text.as_str();
    let mut spans: Vec<_> = frontend.bodies.iter().map(|body| body.expanded_span.range()).collect();
    spans.sort_by_key(|span| (span.start, span.end));
    let mut cuts = vec![0];
    for span in spans {
        let (start, end) = (span.start.min(text.len()), span.end.min(text.len()));
        if start >= *cuts.last().unwrap() && end >= start {
            cuts.push(start);
            cuts.push(end);
        }
    }
    cuts.push(text.len());
    cuts.dedup();
    let pieces: Vec<&str> = cuts
        .windows(2)
        .filter_map(|pair| text.get(pair[0]..pair[1]))
        .collect();
    let digests: Vec<u128> = pieces
        .par_iter()
        .map(|piece| xxhash_rust::xxh3::xxh3_128(piece.as_bytes()))
        .collect();
    let cached: Vec<Option<PieceScreen>> = {
        let cache = piece_cache().lock().unwrap_or_else(|e| e.into_inner());
        digests.iter().map(|digest| cache.get(digest).cloned()).collect()
    };
    let screens: Vec<PieceScreen> = pieces
        .par_iter()
        .zip(cached)
        .map(|(piece, cached)| cached.unwrap_or_else(|| screen_piece(piece)))
        .collect();
    {
        let mut cache = piece_cache().lock().unwrap_or_else(|e| e.into_inner());
        if cache.len() > 1 << 20 {
            cache.clear();
        }
        for (digest, screen) in digests.iter().zip(&screens) {
            cache.entry(*digest).or_insert_with(|| screen.clone());
        }
    }
    let mut previous: Vec<(TokenKind, String)> = Vec::new();
    for screen in &screens {
        if screen.candidate {
            return true;
        }
        // A zero among a piece's first two tokens may complete `% 0` or
        // `number / 0` with tokens of the preceding pieces.
        let mut window = previous.clone();
        window.extend(screen.head.iter().cloned());
        let base = previous.len();
        for index in base..window.len() {
            if index >= 2 && window[index].0 == TokenKind::Number {
                let operator = window[index - 1].1.as_str();
                if zero_divisor(&window[index].1, operator, &window[index - 2].1)
                    && (operator == "%" || window[index - 2].0 == TokenKind::Number)
                {
                    return true;
                }
            }
        }
        if !screen.tail.is_empty() {
            let mut last = previous;
            last.extend(screen.tail.iter().cloned());
            let keep = last.len().saturating_sub(2);
            previous = last.split_off(keep);
        }
    }
    false
}

fn text_errors(frontend: &ColdFrontend) -> Vec<Diagnostic> {
    if !text_may_error(frontend) {
        return Vec::new();
    }
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
            TokenKind::Number if index >= 2 => {
                let operator = tokens[index - 1].1;
                let left = tokens[index - 2];
                if zero_divisor(token.1, operator, left.1)
                    && (operator == "%" || left.0 == TokenKind::Number)
                {
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

/// A literal divisor DreamMaker rejects: `/ 0`, and `% n` where n truncates to 0 (`% 0.5` is `attempted division by zero`).
/// `%%` is the real-valued modulo, which accepts a fraction. Pinned 516.1687 (fixtures/diagnostics/cases/mod_fractional_divisor).
fn zero_divisor(number: &str, operator: &str, before_operator: &str) -> bool {
    let Ok(value) = number.parse::<f64>() else {
        return false;
    };
    match operator {
        "/" => value == 0.0,
        "%" => before_operator != "%" && value.trunc() == 0.0,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::{collapsed, keyword_argument_errors, unterminated_plain_text, valid_escape, RESERVED_FORMAL_NAMES};
    use crate::local_warnings::significant_lines;
    fn keyword_errors(source: &str) -> Vec<String> {
        let lines = significant_lines(source);
        let mut errors = Vec::new();
        keyword_argument_errors(&lines, &mut errors);
        errors.into_iter().map(|error| error.1).collect()
    }

    #[test]
    fn operator_words_are_not_argument_names() {
        // Pinned 516.1687: fixtures/diagnostics/cases/keyword_named_arg_to, keyword_formal_to.
        for word in ["to", "in"] {
            let expected = vec![
                format!("missing left-hand argument to {word}."),
                "missing left-hand argument to =.".to_owned(),
            ];
            assert_eq!(keyword_errors(&format!("/proc/f(a = 1, {word} = null)
    return a
")), expected);
            assert_eq!(keyword_errors(&format!("/proc/g()
    return f(1, {word} = 2)
")), expected);
        }
        for fine in [
            "/proc/f(a = 1, step = 2)
    return f(a, step = 3)
",
            "/proc/f(a)
    for(var/x in a)
        return x
",
            "/proc/f(list/a)
    return f(a, a == 2)
",
            "/proc/f(mob/M in view())
    return M
",
            "/proc/f(a = 1)
    var/to = 3
    return to
",
        ] {
            assert!(keyword_errors(fine).is_empty(), "{fine}");
        }
    }

    #[test]
    fn reserved_words_are_rejected_as_formal_names_only() {
        // Pinned 516.1687: fixtures/diagnostics/cases/keyword_formal_if, keyword_formal_set, keyword_arg_if_ok.
        for word in RESERVED_FORMAL_NAMES {
            assert_eq!(
                keyword_errors(&format!("/proc/f(a = 1, {word} = null)
    return a
")),
                vec![format!("{word}: invalid variable name: reserved word")]
            );
            assert!(keyword_errors(&format!("/proc/g()
    return f(1, {word} = 2)
")).is_empty());
        }
    }

    #[test]
    fn operator_words_cannot_name_a_local() {
        // Pinned 516.1687: fixtures/diagnostics/cases/keyword_local_*.
        let local_errors = |source: &str| {
            let lines = significant_lines(source);
            let mut errors = Vec::new();
            super::keyword_local_errors(&lines, &mut errors);
            errors.into_iter().map(|error| error.1).collect::<Vec<_>>()
        };
        assert_eq!(local_errors("/proc/f()\n    var/to = 1\n    return 1\n"), vec!["missing left-hand argument to to."]);
        assert_eq!(local_errors("/proc/f()\n    var/in\n    return 1\n"), vec!["missing left-hand argument to in."]);
        assert_eq!(local_errors("/proc/f()\n    var/obj/to = null\n    return 1\n"), vec!["missing left-hand argument to =."]);
        assert!(local_errors("/proc/f()\n    var/obj/tool = null\n    var/to_chat = 1\n    return 1\n").is_empty());
    }

    #[test]
    fn literal_divisors_follow_dreammaker() {
        use super::zero_divisor;
        // Pinned 516.1687: `% 0.5` truncates the divisor to 0; `/ 0.5` and `%% 0.5` are fine.
        assert!(zero_divisor("0", "/", "5") && zero_divisor("0", "%", "5") && zero_divisor("0.5", "%", "5"));
        assert!(!zero_divisor("0.5", "/", "5") && !zero_divisor("1", "%", "5") && !zero_divisor("2.5", "%", "5"));
        assert!(!zero_divisor("0.5", "%%", "5"));
    }

    #[test]
    fn plain_text_cannot_span_a_line_break() {
        // Pinned 516.1687: a break inside "..." is `unterminated text (expecting ")`; {"..."} and a backslash continuation are fine.
        assert!(unterminated_plain_text("\"one\ntwo\""));
        assert!(!unterminated_plain_text("\"one two\""));
        assert!(!unterminated_plain_text("\"one\\\ntwo\""));
        assert!(!unterminated_plain_text("{\"one\ntwo\"}"));
        // The continuation skips the whitespace after it, blank lines included; a later bare break still ends the literal.
        assert!(!unterminated_plain_text("\"one\\\n\n   two\""));
        assert!(unterminated_plain_text("\"one\\\r\n  two\""));
        assert_eq!(super::unterminated_break("\"ab\\\r\ncd\""), Some(5));
        assert!(unterminated_plain_text("\"one\\\n   two\n  three\""));
        assert_eq!(super::unterminated_break("\"ab\ncd\""), Some(3));
        // Breaks inside an embedded [expression] are code, nested literals included.
        assert!(!unterminated_plain_text("\"x [pick(\n\"a\",\n\"b\")] y\""));
        assert!(unterminated_plain_text("\"x [pick(\"a\nb\")] y\""));
        assert!(unterminated_plain_text("\"x [1]\ny\""));
    }

    #[test]
    fn leftover_quote_after_a_break_opens_another_unterminated_literal() {
        // Pinned 516.1681: errors at lines 2 and 3 for `"ab\<CR><LF>\t\tcd"`, and for a bare break.
        for text in ["x\n\"ab\\\r\n\t\tcd\"\n", "x\n\"ab\n\t\tcd\"\n"] {
            let start = text.find('"').unwrap();
            let end = text.rfind('"').unwrap() + 1;
            let found = super::literal_break_errors(text, start, end, &text[start..end]);
            assert_eq!(found.len(), 2, "{text:?}");
            assert_eq!(found[1], end - 1);
        }
        assert_eq!(super::literal_break_errors("\"a\\\nb\"\n", 0, 6, "\"a\\\nb\"").len(), 0);
    }

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
