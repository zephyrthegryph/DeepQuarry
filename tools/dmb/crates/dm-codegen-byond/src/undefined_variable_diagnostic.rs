//! DreamMaker's simple return-path context, using the shared lexer.
//! Arithmetic and argument contexts identify the unresolved name alone.
use dm_syntax::TokenKind;
pub(crate) fn undefined_variable_message(statement: &str, name: &str) -> String {
    format!("{}: undefined var", reference_context(statement, name))
}
pub(crate) fn undefined_type_message(statement: &str, name: &str, path: &str) -> String {
    format!(
        "{}: undefined type: {path}",
        reference_context(statement, name)
    )
}
fn reference_context(statement: &str, name: &str) -> String {
    let lexed = dm_syntax::lex_spans(statement);
    let tokens: Vec<_> = lexed
        .tokens
        .iter()
        .copied()
        .filter(|token| {
            !matches!(
                token.kind,
                TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
            )
        })
        .collect();
    let simple_return = lexed.diagnostics.is_empty()
        && tokens.len() >= 2
        && tokens[0].text(statement) == "return"
        && tokens[1].kind == TokenKind::Ident
        && tokens[1].text(statement) == name
        && tokens[2..].chunks(2).all(|pair| {
            pair.len() == 2 && pair[0].text(statement) == "." && pair[1].kind == TokenKind::Ident
        });
    // A direct receiver call reports its callee prefix, without the return
    // keyword or argument expression. Other expression contexts stay unchanged.
    let start = usize::from(
        tokens
            .first()
            .is_some_and(|token| token.text(statement) == "return"),
    );
    let mut end = start + 1;
    if tokens
        .get(start)
        .is_some_and(|token| token.kind == TokenKind::Ident && token.text(statement) == name)
    {
        while tokens
            .get(end)
            .is_some_and(|token| token.text(statement) == ".")
            && tokens
                .get(end + 1)
                .is_some_and(|token| token.kind == TokenKind::Ident)
        {
            end += 2;
        }
    }
    let receiver_call = end > start + 1
        && tokens
            .get(end)
            .is_some_and(|token| token.text(statement) == "(");
    let context = if receiver_call {
        tokens[start..end]
            .iter()
            .map(|token| token.text(statement))
            .collect::<String>()
    } else if simple_return {
        tokens
            .iter()
            .map(|token| token.text(statement))
            .collect::<String>()
    } else {
        name.to_owned()
    };
    context
}
/// DreamMaker's subject for an undefined member variable: the receiver chain
/// as written (`src.missing`), prefixed by `return` when the statement only
/// returns that chain. Falls back to the bare name when no chain matches.
pub fn undefined_member_message(statement: &str, selector: &str) -> String {
    let lexed = dm_syntax::lex_spans(statement);
    let tokens: Vec<&str> = lexed
        .tokens
        .iter()
        .filter(|token| {
            !matches!(
                token.kind,
                TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
            )
        })
        .map(|token| token.text(statement))
        .collect();
    let is_ident = |text: &str| {
        text.chars().next().is_some_and(|ch| ch.is_alphabetic() || ch == '_')
            && text.chars().all(|ch| ch.is_alphanumeric() || ch == '_')
    };
    let separator = |text: &str| text == "." || text == ":";
    let Some(selected) = (2..tokens.len())
        .find(|&index| tokens[index] == selector && separator(tokens[index - 1]) && is_ident(tokens[index - 2]))
    else {
        return format!("{selector}: undefined var");
    };
    let mut start = selected - 2;
    while start >= 2 && separator(tokens[start - 1]) && is_ident(tokens[start - 2]) {
        start -= 2;
    }
    let mut end = selected;
    while end + 2 < tokens.len() && separator(tokens[end + 1]) && is_ident(tokens[end + 2]) {
        end += 2;
    }
    let chain: String = tokens[start..=end].concat();
    if start == 1 && tokens[0] == "return" && end + 1 == tokens.len() {
        format!("return{chain}: undefined var")
    } else {
        format!("{chain}: undefined var")
    }
}

/// Owner and name of a variable fact the resolver could not answer, recovered
/// from the stable reason text of `LowerResolver::error` (see `query_subject`).
/// A name with no declared spelling is matched against the statement's
/// identifiers by symbol hash.
pub fn unresolved_variable_candidate<'a>(
    reason: &'a str,
    statement: &'a str,
) -> Option<(Option<&'a str>, &'a str)> {
    let rest = reason.strip_prefix("unsupported semantic query: variable ")?;
    let names = rest.split_once(" (")?.1.strip_suffix(')')?;
    let (owner, name) = match names.split_once(", name=") {
        Some((owner, name)) => (Some(owner.strip_prefix("owner=")?), name),
        None => (None, names.strip_prefix("name=")?),
    };
    let Some(bits) = name.strip_prefix('#') else {
        return Some((owner, name));
    };
    let bits = u64::from_str_radix(bits, 16).ok()?;
    let lexed = dm_syntax::lex_spans(statement);
    let name = lexed
        .tokens
        .iter()
        .filter(|token| token.kind == TokenKind::Ident)
        .map(|token| token.text(statement))
        .find(|text| dm_ir::SymbolId::of(text).bits() == bits)?;
    Some((owner, name))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn simple_return_path_and_expression_contexts_preserve_pinned_wording() {
        for (statement, expected) in [
            ("return missing", "returnmissing: undefined var"),
            ("return missing.value", "returnmissing.value: undefined var"),
            (
                "return /* trivia */ missing.value",
                "returnmissing.value: undefined var",
            ),
            ("missing = 1", "missing: undefined var"),
            ("return 1 + missing", "missing: undefined var"),
            ("return foo(missing)", "missing: undefined var"),
            ("return missing.Copy()", "missing.Copy: undefined var"),
            ("missing.Copy(7)", "missing.Copy: undefined var"),
            ("return \"missing\" + missing", "missing: undefined var"),
        ] {
            assert_eq!(undefined_variable_message(statement, "missing"), expected);
            assert_eq!(
                undefined_type_message(statement, "missing", "/datum/missing"),
                expected.replace(": undefined var", ": undefined type: /datum/missing")
            );
        }
    }
    #[test]
    fn member_chain_subjects_match_dreammaker() {
        for (statement, expected) in [
            ("return src.nope", "returnsrc.nope: undefined var"),
            ("return src.nope.deeper", "returnsrc.nope.deeper: undefined var"),
            ("var/x = src.nope + 1", "src.nope: undefined var"),
            ("src.nope = 1", "src.nope: undefined var"),
            ("return T:nope", "returnT:nope: undefined var"),
            ("return global.nope + 1", "global.nope: undefined var"),
            ("return 1", "nope: undefined var"),
        ] {
            assert_eq!(undefined_member_message(statement, "nope"), expected);
        }
        assert_eq!(
            unresolved_variable_candidate(
                "unsupported semantic query: variable storage (owner=/datum/a, name=b)",
                ""
            ),
            Some((Some("/datum/a"), "b"))
        );
        let hashed = format!(
            "unsupported semantic query: variable global (name=#{:016x})",
            dm_ir::SymbolId::of("g").bits()
        );
        assert_eq!(
            unresolved_variable_candidate(&hashed, "return global.g + 1"),
            Some((None, "g"))
        );
    }
}
