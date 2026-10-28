use super::*;

fn line_column(source: &str, offset: usize) -> (usize, usize) {
    let prefix = &source[..offset];
    (
        prefix.bytes().filter(|c| *c == b'\n').count() + 1,
        prefix.rsplit('\n').next().unwrap().chars().count() + 1,
    )
}

#[test]
fn primary_control_delimiters_survive_whitespace_else_if_and_multiline_headers() {
    let source = include_str!("../../../fixtures/unified_checks/bitwise_control_origins.dm");
    let syntax = parse(source);
    assert!(syntax.diagnostics.is_empty(), "{:?}", syntax.diagnostics);
    let body = parse_proc_body(&syntax.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    let actual: Vec<_> = body
        .control_origins
        .iter()
        .map(|origin| {
            assert_eq!(&source[origin.opening.start..origin.opening.end], "(");
            assert_eq!(body.control_origin(origin.condition), Some(origin.opening));
            (
                line_column(source, origin.opening.start),
                line_column(source, origin.condition.start),
            )
        })
        .collect();
    assert_eq!(
        actual,
        [
            ((2, 10), (2, 14)),
            ((4, 13), (4, 15)),
            ((6, 8), (7, 9)),
            ((12, 14), (12, 17)),
            ((13, 8), (13, 9))
        ]
    );
    assert!(body.control_origin(Span::new(0, 0)).is_none());
}

#[test]
fn bodies_without_control_origins_retain_no_origin_allocation() {
    let syntax = parse("/proc/test()\n    return 1\n");
    let body = parse_proc_body(&syntax.items[0]);
    assert_eq!(body.control_origins.capacity(), 0);
}
