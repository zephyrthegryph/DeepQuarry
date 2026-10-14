use super::*;

fn whole_token_reference(source: &str) -> Result<Vec<LiteralRequest>, CaptureError> {
    let lexed = dm_syntax::lex_spans(source);
    if let Some(error) = lexed.diagnostics.first() {
        return Err(CaptureError::Source {
            span: error.span,
            reason: format!("{:?}", error.kind),
        });
    }
    let mut found = Vec::new();
    collect_tokens(source, &lexed.tokens, 0, &mut found)?;
    Ok(found)
}

#[test]
fn relevant_token_discovery_matches_full_lexer_order_spans_and_error_precedence() {
    let source = "/proc/p()\r\n\t/* 'ignored.txt' */ var/x = list('first.txt', 'first.txt')\r\n\treturn \"plain 'ignored.txt' [icon('middle.txt')] [\"nested [file('deep.txt')]\"]\" + 'last.txt'\r\n";
    let actual = discover_literals(source).unwrap();
    assert_eq!(actual, whole_token_reference(source).unwrap());
    assert_eq!(
        actual.iter().map(|r| r.path.as_str()).collect::<Vec<_>>(),
        [
            "first.txt",
            "first.txt",
            "middle.txt",
            "deep.txt",
            "last.txt"
        ]
    );
    for literal in actual {
        assert_eq!(&source[literal.span.range()], format!("'{}'", literal.path));
    }
    for source in [
        "'bad[asset].txt'\n/* unterminated",
        "\"unterminated [file('asset.txt')]",
        "'bad[asset].txt'",
        "\"[file('bad[asset].txt')]\"",
        "// 'ignored.txt'\n@\"['raw.txt']\" 'valid.txt'",
        "/* nested /* 'ignored.txt' */ comment */ 'valid.txt'",
        "'unicode-asset.txt' + \"λ [file('embedded.txt')]\"",
    ] {
        assert_eq!(
            discover_literals(source).map_err(|error| format!("{error:?}")),
            whole_token_reference(source).map_err(|error| format!("{error:?}")),
        );
    }
    // A later lexer error must outrank the earlier resource admission error.
    assert!(matches!(
        discover_literals("'bad[asset].txt'\n/* unterminated"),
        Err(CaptureError::Source { .. })
    ));
    assert!(matches!(
        discover_literals("'bad[asset].txt'"),
        Err(CaptureError::UnsupportedExpression { .. })
    ));
}
