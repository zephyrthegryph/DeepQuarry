#[test]
fn block_string_and_nested_interpolation_are_single_tokens() {
    let source = "var/message = {\"A [time2text(entry[\"time\"], \"MMM DD\")]\n/obj/not_a_declaration\nB\"}\n/obj/real\n";
    let tokens = lex_spans(source);
    assert!(tokens.diagnostics.is_empty(), "{:?}", tokens.diagnostics);
    let literal = tokens
        .tokens
        .iter()
        .find(|token| token.kind == TokenKind::String)
        .unwrap();
    assert!(literal.text(source).contains("/obj/not_a_declaration"));
    assert!(literal.text(source).ends_with("\"}"));
    let ast = parse(source);
    assert_eq!(ast.items.len(), 2);
    assert_eq!(ast.items[1].header, "/obj/real");
}

#[test]
fn nested_string_interpolation_can_contain_quoted_nested_arguments() {
    let source = r#""outer [flag ? " inner [name ? "yes" : "no"]" : ""] tail""#;
    let lexed = lex(source);
    assert!(lexed.diagnostics.is_empty(), "{:?}", lexed.diagnostics);
    assert_eq!(lexed.tokens.len(), 1);
    assert_eq!(lexed.tokens[0].kind, TokenKind::String);
    assert_eq!(lexed.tokens[0].text, source);
}

#[test]
fn span_lexer_matches_owned_tokens() {
    let source = "/obj/proc/test() // comment\n return \"[src.name]\"\n";
    let owned = lex(source);
    let borrowed = lex_spans(source);
    assert_eq!(owned.diagnostics, borrowed.diagnostics);
    assert_eq!(owned.tokens.len(), borrowed.tokens.len());
    for (owned, borrowed) in owned.tokens.iter().zip(borrowed.tokens) {
        assert_eq!(owned.kind, borrowed.kind);
        assert_eq!(owned.span, borrowed.span);
        assert_eq!(owned.text, borrowed.text(source));
    }
}

#[test]
fn signed_decimal_exponents_do_not_consume_hex_subtraction() {
    for source in ["1e-4", "1E+6", "0.125e-3"] {
        let tokens = lex_spans(source);
        assert_eq!(tokens.tokens.len(), 1, "{source}");
        assert_eq!(tokens.tokens[0].kind, TokenKind::Number);
        assert_eq!(tokens.tokens[0].text(source), source);
        assert!(parse_expression(source).diagnostics.is_empty(), "{source}");
    }
    assert_eq!(lex_spans("0x1e-4").tokens.len(), 3);
}

#[test]
fn raw_single_quoted_patterns_are_strings_not_resources() {
    let source = r#"@'^"[A-z]*"[\s]*=[\s]*\([\s]*\n'"#;
    let lexed = lex_spans(source);
    assert!(lexed.diagnostics.is_empty());
    assert_eq!(lexed.tokens.len(), 1);
    assert_eq!(lexed.tokens[0].kind, TokenKind::String);
}

#[test]
fn deepquarry_declaration_shapes_preserve_order_and_paths() {
    let source = "/datum/example\n    var/static/list/cache\n    proc/Initialize(mapload)\n        return ..()\n/datum/example/var/global/count = 1\n/datum/example/proc/Initialize(mapload)\n    return 2\n";
    let ast = parse(source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    assert_eq!(ast.items.len(), 3);
    assert_eq!(ast.items[0].kind, ItemKind::Type);
    assert_eq!(ast.items[0].children[0].kind, ItemKind::Var);
    assert_eq!(ast.items[0].children[1].kind, ItemKind::Proc);
    assert_eq!(ast.items[1].kind, ItemKind::Var);
    assert_eq!(ast.items[2].kind, ItemKind::Proc);
    assert_eq!(
        ast.items[2].header,
        "/datum/example/proc/Initialize(mapload)"
    );
}

#[test]
fn unterminated_block_string_has_typed_lexical_diagnostic() {
    let lexed = lex_spans("var/x = {\"unfinished\ntext\n");
    assert_eq!(lexed.diagnostics.len(), 1);
    assert_eq!(lexed.diagnostics[0].kind, DiagnosticKind::Lexical);
}
