//! DreamMaker's `unused_var` warning over the current procedure bodies.
//!
//! DreamMaker warns when a procedure-local `var` is never read. A read is any
//! reference except a plain assignment target (`x = ...`) or an increment or
//! decrement (`x++`, `--x`); compound assignments, indexing, `for(x in ...)`
//! and text embedding (`"[x]"`) are reads. `static`, `global` and `const`
//! locals and `for(var/...)` headers never warn. Scope follows indentation:
//! a declaration is visible to the lines after it until the block ends.
//! This is a lexical pass over the macro-expanded body text; it never changes
//! lowering or output bytes.
use crate::initializer_diagnostics::InitializerLoweringError;
use crate::initializer_policy::warnings::{InitializerWarning, WarningLocation};
use dm_ir::WarningCode;
use dm_syntax::TokenKind;
use dm_tree::frontend::{BodyOccurrence, ColdFrontend};
use rayon::prelude::*;

/// One physical line of significant tokens: (kind, text, offset in body).
pub(crate) struct Line<'a> {
    pub indent: usize,
    /// The leading whitespace as authored (tabs and spaces).
    pub indent_text: &'a str,
    /// Starts inside an open bracket: a continuation of the previous line,
    /// whose indentation carries no block structure.
    pub continuation: bool,
    pub tokens: Vec<(TokenKind, &'a str, usize)>,
}

/// Lex a body into physical lines of significant tokens with their indentation.
pub(crate) fn significant_lines(source: &str) -> Vec<Line<'_>> {
    let lexed = dm_syntax::lex_spans(source);
    let mut lines = vec![Line {
        indent: 0,
        indent_text: "",
        continuation: false,
        tokens: Vec::new(),
    }];
    let mut at_line_start = true;
    let mut depth = 0usize;
    for token in &lexed.tokens {
        match token.kind {
            TokenKind::Newline => {
                lines.push(Line {
                    indent: 0,
                    indent_text: "",
                    continuation: depth > 0,
                    tokens: Vec::new(),
                });
                at_line_start = true;
            }
            TokenKind::Whitespace => {
                if at_line_start {
                    let line = lines.last_mut().expect("line");
                    line.indent = token.span.range().len();
                    line.indent_text = token.text(source);
                }
            }
            TokenKind::Comment => {}
            kind => {
                at_line_start = false;
                if kind == TokenKind::Punctuation {
                    match token.text(source) {
                        "(" | "[" | "{" => depth += 1,
                        ")" | "]" | "}" => depth = depth.saturating_sub(1),
                        _ => {}
                    }
                }
                lines
                    .last_mut()
                    .expect("line")
                    .tokens
                    .push((kind, token.text(source), token.span.start));
            }
        }
    }
    lines
}

/// A procedure-local declaration at the start of a line.
struct Declaration<'a> {
    name: &'a str,
    offset: usize,
    /// Declared type path (`/datum/x` for `var/datum/x/name`), if any.
    declared_type: Option<String>,
}

/// `var/.../name` at the start of a line.
fn local_declaration<'a>(line: &Line<'a>) -> Option<Declaration<'a>> {
    let tokens = &line.tokens;
    if tokens.first()?.1 != "var" || tokens.get(1)?.1 != "/" {
        return None;
    }
    let mut index = 2;
    let mut parts = Vec::new();
    while let Some((TokenKind::Ident, text, offset)) = tokens.get(index) {
        if matches!(*text, "static" | "global" | "const") {
            return None;
        }
        parts.push((*text, *offset));
        if tokens.get(index + 1).is_some_and(|token| token.1 == "/") {
            index += 2;
        } else {
            break;
        }
    }
    let (name, offset) = parts.pop()?;
    let path: Vec<&str> = parts.iter().map(|part| part.0).filter(|part| *part != "tmp").collect();
    Some(Declaration {
        name,
        offset,
        declared_type: (!path.is_empty()).then(|| format!("/{}", path.join("/"))),
    })
}

/// Whether `owner` declares `field` as static, global or const: DreamMaker
/// reads such a field through a typed local without loading the local.
pub(crate) type SharedField<'f> = dyn Fn(&str, &str) -> bool + Sync + 'f;

fn is_read(
    tokens: &[(TokenKind, &str, usize)],
    index: usize,
    declared_type: Option<&str>,
    shared_field: &SharedField<'_>,
) -> bool {
    let text = |offset: isize| -> Option<&str> {
        usize::try_from(index as isize + offset)
            .ok()
            .and_then(|at| tokens.get(at))
            .map(|token| token.1)
    };
    if text(-1) == Some(".") {
        return false;
    }
    // `T:name` is a member; `cond ? a : name` (spaced) is a ternary operand.
    if text(-1) == Some(":") && tokens[index - 1].2 + 1 == tokens[index].2 {
        return false;
    }
    // A type path segment (`/obj/name`), unlike a division operand.
    if text(-1) == Some("/") {
        let before = usize::try_from(index as isize - 2).ok().and_then(|at| tokens.get(at));
        if !before.is_some_and(|token| {
            matches!(token.0, TokenKind::Ident | TokenKind::Number) || matches!(token.1, ")" | "]")
        }) {
            return false;
        }
    }
    // `typed.shared_field` never loads the local (`typed?.field` does: it
    // tests the local for null first).
    // A further member (`typed.shared.len`) is a read again.
    if let (Some(owner), Some("."), Some(field)) = (declared_type, text(1), text(2)) {
        if text(3) != Some(".") && shared_field(owner, field) {
            return false;
        }
    }
    let assignment = text(1) == Some("=") && text(2) != Some("=");
    // `x++` or `--x` alone is not a read; inside a larger expression it is.
    let statement_end = |at: isize| matches!(text(at), None | Some(";"));
    let postfix = matches!((text(1), text(2)), (Some("+"), Some("+")) | (Some("-"), Some("-")))
        && statement_end(-1)
        && statement_end(3);
    let prefix = matches!((text(-2), text(-1)), (Some("+"), Some("+")) | (Some("-"), Some("-")))
        && statement_end(-3)
        && statement_end(1);
    !(assignment || postfix || prefix)
}

fn embeds(text: &str, name: &str) -> bool {
    let Some(open) = text.find('[') else {
        return false;
    };
    let bytes = text.as_bytes();
    let ident = |byte: u8| byte.is_ascii_alphanumeric() || byte == b'_';
    text[open..].match_indices(name).any(|(at, _)| {
        let start = open + at;
        let end = start + name.len();
        (start == 0 || !ident(bytes[start - 1])) && (end >= bytes.len() || !ident(bytes[end]))
    })
}

/// Offsets (in body text) of locals declared but never read.
pub(crate) fn unused_locals(source: &str, shared_field: &SharedField<'_>) -> Vec<(String, usize)> {
    unused_locals_typed(source, shared_field, &|_| true)
}

/// As `unused_locals`; a local whose declared type does not exist is never
/// used (DreamMaker rejects each read of it).
pub(crate) fn unused_locals_typed(
    source: &str,
    shared_field: &SharedField<'_>,
    known_type: &(dyn Fn(&str) -> bool + Sync),
) -> Vec<(String, usize)> {
    let lines = significant_lines(source);
    let mut unused = Vec::new();
    // Line 0 is the procedure header; parameters are not locals.
    for (number, line) in lines.iter().enumerate().skip(1) {
        if line.continuation {
            continue;
        }
        let Some(Declaration {
            name,
            offset,
            declared_type,
        }) = local_declaration(line)
        else {
            continue;
        };
        let reads = |tokens: &[(TokenKind, &str, usize)], from: usize| {
            tokens.iter().enumerate().skip(from).any(|(index, (kind, text, _))| match kind {
                TokenKind::Ident => {
                    *text == name
                        && is_read(tokens, index, declared_type.as_deref(), shared_field)
                }
                TokenKind::String | TokenKind::Interpolation => embeds(text, name),
                _ => false,
            })
        };
        // Statements after `;` on the declaration line (macro expansions)
        // share its scope.
        let same_line = line
            .tokens
            .iter()
            .position(|token| token.1 == ";")
            .is_some_and(|end| reads(&line.tokens, end + 1));
        let undefined = declared_type
            .as_deref()
            .is_some_and(|path| !path.starts_with("/list") && !known_type(path));
        let used = !undefined
            && (same_line
                || lines[number + 1..]
                .iter()
                .take_while(|later| {
                    later.tokens.is_empty() || later.continuation || later.indent >= line.indent
                })
                .any(|later| reads(&later.tokens, 0)));
        if !used {
            unused.push((name.to_owned(), offset));
        }
    }
    unused
}

/// `if(x = 1)` / `while(x = 1)`: a plain assignment as the whole condition.
pub(crate) fn accidental_assignments(source: &str) -> Vec<usize> {
    let mut found = Vec::new();
    for line in significant_lines(source).iter().skip(1) {
        if line.continuation {
            continue;
        }
        let tokens = &line.tokens;
        let start = match tokens.iter().map(|token| token.1).collect::<Vec<_>>().as_slice() {
            ["if" | "while", "(", ..] => 1,
            ["else", "if", "(", ..] => 2,
            _ => continue,
        };
        let mut depth = 0usize;
        for index in start..tokens.len() {
            match tokens[index].1 {
                "(" | "[" | "{" => depth += 1,
                ")" | "]" | "}" => {
                    depth = depth.saturating_sub(1);
                    if depth == 0 {
                        break;
                    }
                }
                "=" if depth == 1 => {
                    let previous = tokens[index - 1];
                    let operator_before = previous.0 == TokenKind::Operator
                        && previous.2 + previous.1.len() == tokens[index].2;
                    let equals_after = tokens.get(index + 1).is_some_and(|next| next.1 == "=");
                    if !operator_before && !equals_after {
                        found.push(line.tokens[0].2);
                        break;
                    }
                }
                _ => {}
            }
        }
    }
    found
}

/// Current `unused_var` warnings in authored body order.
pub(crate) fn capture(
    frontend: &ColdFrontend,
) -> Result<Vec<InitializerWarning>, InitializerLoweringError> {
    let tree = &frontend.snapshot.tree;
    let shared_field = |owner: &str, field: &str| {
        tree.lookup_type(dm_ir::SymbolId::of(owner))
            .and_then(|owner| tree.resolve(owner, dm_ir::SymbolId::of(field), dm_tree::MemberKind::Var))
            .and_then(|member| tree.member(member))
            // static (1), const (2) and global (8) declaration flags.
            .is_some_and(|member| member.metadata.flags & (1 | 2 | 8) != 0)
    };
    let mut bodies: Vec<&BodyOccurrence> = frontend.bodies.iter().collect();
    bodies.sort_by_key(|body| (body.source.encounter_ordinal, body.expanded_span.start));
    let found: Vec<Vec<(WarningCode, Option<String>, usize)>> = bodies
        .par_iter()
        .map(|body| {
            frontend
                .body_input(body)
                .map(|input| {
                    let source = input.source();
                    let mut found: Vec<_> = accidental_assignments(source)
                        .into_iter()
                        .map(|offset| (WarningCode::AccidentalAssign, None, offset))
                        .collect();
                    found.extend(
                        unused_locals_typed(source, &shared_field, &|path| {
                            crate::source_checks::known_type(tree, path)
                        })
                            .into_iter()
                            .map(|(name, offset)| (WarningCode::UnusedVar, Some(name), offset)),
                    );
                    found
                })
                .unwrap_or_default()
        })
        .collect();
    // `#warn` directives in active code come first, as DreamMaker reports
    // them while preprocessing.
    let mut warnings: Vec<InitializerWarning> = frontend
        .plan
        .warnings
        .iter()
        .map(|warning| {
            let semantic_path = frontend
                .plan
                .occurrences
                .iter()
                .find(|occurrence| *occurrence.path == warning.path)
                .map_or_else(
                    || std::sync::Arc::from(warning.path.to_string_lossy().as_ref()),
                    |occurrence| occurrence.semantic_path.clone(),
                );
            InitializerWarning {
                source_ordinal: 0,
                code: WarningCode::WarnDirective,
                name: Some(warning.message.clone()),
                location: WarningLocation {
                    semantic_path,
                    line: Some(warning.line),
                },
            }
        })
        .collect();
    for (body, found) in bodies.iter().zip(found) {
        for (code, name, offset) in found {
            let location = frontend
                .location(body.expanded_span.start + offset)
                .ok_or_else(|| {
                    InitializerLoweringError::Invariant("local warning has no source origin".into())
                })?;
            warnings.push(InitializerWarning {
                source_ordinal: location.encounter_ordinal,
                code,
                name,
                location: WarningLocation::from(location),
            });
        }
    }
    Ok(warnings)
}

#[cfg(test)]
mod tests {
    use super::unused_locals;
    fn names(source: &str) -> Vec<String> {
        let shared = |owner: &str, field: &str| owner == "/datum/svc" && field == "table";
        unused_locals(source, &shared).into_iter().map(|(name, _)| name).collect()
    }
    #[test]
    fn accidental_assignment_is_top_level_only() {
        let source = "/proc/a(x)
	while(x = 1)
		return
	if((x = 2))
		return
	if(x <= 7 || x != 7)
		return
	else if(x = 5)
		return
";
        assert_eq!(super::accidental_assignments(source).len(), 2);
    }
    #[test]
    fn shared_field_reads_and_ternaries_follow_dreammaker() {
        let source = "/proc/s()
	var/datum/svc/a = new
	world.log << a.table
	var/datum/svc/b = new
	world.log << b.other
	var/c = 1
	return 1 ? 2 : c
";
        assert_eq!(names(source), ["a"]);
    }
    #[test]
    fn reads_and_writes_follow_dreammaker() {
        // Pinned against DreamMaker 516.1687 (fixtures/diagnostics/cases).
        let source = "/proc/a()\n\tvar/x1 = 0\n\tx1 += 3\n\tvar/x2 = 0\n\tfor(x2 in list(1))\n\t\tworld.log << 1\n\tvar/x3 = \"a\"\n\tworld.log << \"v [x3]\"\n\tvar/list/x4 = list()\n\tx4[1] = 2\n\tvar/x5\n\tx5 = x5\n\tvar/x7\n\t--x7\n\tvar/x9 = 1\n\tvar/x10 = 2\n\tx10 = x9\n\tvar/x13\n\tfor(var/i in 1 to 3)\n\t\tx13 = i\n\tvar/w = 1\n\tw++\n\tvar/static/s\n\tvar/const/k = 3\n\tvar/list/m[5]\n\treturn\n";
        assert_eq!(names(source), ["x7", "x10", "x13", "w", "m"]);
        let source = "/proc/b()
	var/i = 3
	if(i-- > 0)
		return
	var/j = 1; world.log << j
	var/k = list(1
, 2)
	return k
";
        assert!(names(source).is_empty());
    }
    #[test]
    fn nested_scope_ends_at_dedent() {
        let source = "/proc/c()\n\tif(1)\n\t\tvar/inner = 1\n\tvar/outer = 2\n\treturn inner + outer\n";
        assert_eq!(names(source), ["inner"]);
    }
}
