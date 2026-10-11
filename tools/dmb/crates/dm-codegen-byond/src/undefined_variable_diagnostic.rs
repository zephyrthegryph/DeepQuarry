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
}
