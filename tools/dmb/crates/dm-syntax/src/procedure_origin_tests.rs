use crate::*;
#[test]
fn opening_cursor_comes_from_the_same_primary_ast_tokens_and_absolute_binding() {
    for header in [
        "/proc/untyped()",
        "/proc/late ()",
        "/proc/late/* é漢 */()",
        "/proc/probe(x=foo(\"(\")) as /datum",
    ] {
        let source = format!("//prefix\n{header}\n    return null\n");
        let start = "//prefix\n".len();
        let span = Span::new(start, source.len());
        let with = parse_proc_with_origins_at_span(&source, span).unwrap();
        let opening = with.opening_parenthesis.unwrap();
        assert_eq!(&source[opening.range()], "(");
        assert_eq!(with.item, parse_proc_at_span(&source, span).unwrap());
        if header.contains("é漢") {
            assert_eq!(opening.start - start + 1, 22);
        }
    }
}
#[test]
fn quoted_default_parentheses_and_late_body_calls_do_not_change_signature_origin() {
    let source = "/proc/p(x=foo(\"(\"))\n    bar()\n";
    let parsed = parse_proc_with_origins_at_span(source, Span::new(0, source.len())).unwrap();
    assert_eq!(parsed.opening_parenthesis.unwrap(), Span::new(7, 8));
}
