use super::*;
use crate::regions::prepared_source::PreparedSource;
use std::sync::Arc;
fn reference_strip(source: &str) -> Cow<'_, str> {
    let lexed = lex_spans(source);
    let comments: Vec<_> = lexed
        .tokens
        .into_iter()
        .filter(|token| token.kind == TokenKind::Comment)
        .collect();
    if comments.is_empty() {
        return Cow::Borrowed(source);
    }
    let mut bytes = source.as_bytes().to_vec();
    for token in comments {
        for byte in &mut bytes[token.span.range()] {
            if !matches!(*byte, b'\r' | b'\n') {
                *byte = b' ';
            }
        }
    }
    Cow::Owned(String::from_utf8(bytes).expect("comment removal preserves UTF-8"))
}

fn reference_state(source: &str) -> LogicalState {
    if source.is_empty() {
        return LogicalState::default();
    }
    let lexed = lex_spans(source);
    let last = lexed.tokens.last();
    let open_literal = last.is_some_and(|token| {
        token.kind == TokenKind::String
            && lexed
                .diagnostics
                .iter()
                .any(|diagnostic| diagnostic.span.start == token.span.start)
    });
    let open_block_string = last.is_some_and(|token| {
        token.kind == TokenKind::String
            && token.text(source).starts_with("{\"")
            && token.span.end == source.len()
            && !token.text(source).ends_with("\"}")
    });
    let mut depth = 0isize;
    for token in &lexed.tokens {
        match token.text(source) {
            "(" | "[" => depth += 1,
            ")" | "]" => depth -= 1,
            _ => {}
        }
    }
    LogicalState {
        open_literal,
        open_block_string,
        open_expression: depth > 0,
    }
}

fn reference_lines(source: &str) -> Vec<LogicalLine> {
    let mut lines = Vec::new();
    let mut joined = String::new();
    let mut source_lines = 0;
    let mut state = LogicalState::default();
    for physical in source.split_inclusive('\n') {
        if physical.trim_start().starts_with('#')
            && !joined.trim_start().starts_with("#define ")
            && !joined.is_empty()
            && !state.open_literal
        {
            lines.push(LogicalLine {
                text: std::mem::take(&mut joined),
                source_lines,
            });
            source_lines = 0;
            state = LogicalState::default();
        }
        source_lines += 1;
        let content = physical.trim_end_matches(['\r', '\n']);
        if !state.open_block_string {
            if let Some(prefix) = content.trim_end().strip_suffix('\\') {
                joined.push_str(prefix);
                state = reference_state(&joined);
                continue;
            }
        }
        joined.push_str(physical);
        state = reference_state(&joined);
        if state.open_literal || (!joined.trim_start().starts_with('#') && state.open_expression) {
            continue;
        }
        lines.push(LogicalLine {
            text: std::mem::take(&mut joined),
            source_lines,
        });
        source_lines = 0;
        state = LogicalState::default();
    }
    if !joined.is_empty() {
        lines.push(LogicalLine {
            text: joined,
            source_lines,
        });
    }
    lines
}

#[test]
fn streamed_preparation_preserves_comments_continuations_and_locations() {
    let fixtures = [
        "",
        "/proc/plain()\n\treturn 1\n",
        "// caf\u{e9} \u{4e2d}\r\n#define X 1 /* outer /* inner */ end */\r\n",
        "var/x = \"// literal [pick(\"/* nested */\")]\"\nvar/y = 'icons/a.dmi'\n",
        "var/x = @\"// raw /* literal */\"\n",
        "var/x = {\"first\nsecond \\\nlast\"}\n",
        "#define VALUE(x) list(x, \\\n 2, \\\n 3)\n",
        "var/x = list(\n 1,\n#define INTERRUPT 2\n 3)\n",
        "var/x = \"unterminated\n#define X 2\n",
        "/* unterminated\n#define HIDDEN 1\n",
        "var/x = list(1, [2]) // comment\nvar/y = 3",
        "#define X 1 \\  \r\n + 2\r\n#define Y 3 \\\n + 4\n",
        "\\\n#define X 2\n\\",
        "var/x = list(\r\n 1,\r\n 2)\r\n",
    ];
    for source in fixtures {
        let expected = reference_strip(source);
        let actual = strip_source_comments(source);
        assert_eq!(actual, expected, "comment bytes: {source:?}");
        assert_eq!(
            matches!(actual, Cow::Borrowed(_)),
            matches!(expected, Cow::Borrowed(_))
        );
        assert_eq!(actual.len(), source.len());
        for (offset, byte) in source.bytes().enumerate() {
            if matches!(byte, b'\r' | b'\n') {
                assert_eq!(actual.as_bytes()[offset], byte);
            }
        }
        for end in 0..=source.len() {
            if source.is_char_boundary(end) {
                assert_eq!(
                    logical_state(&source[..end]),
                    reference_state(&source[..end]),
                    "state at {end}: {source:?}"
                );
            }
        }
        let expected_lines = reference_lines(&expected);
        let actual_lines = logical_lines(&actual);
        assert_eq!(actual_lines.len(), expected_lines.len());
        let original: Arc<str> = Arc::from(source);
        let prepared = PreparedSource::new(original.clone());
        assert!(Arc::ptr_eq(prepared.original(), &original));
        let mut starts = vec![0];
        starts.extend(
            source
                .bytes()
                .enumerate()
                .filter_map(|(i, b)| (b == b'\n').then_some(i + 1)),
        );
        assert_eq!(prepared.line_starts().as_ref(), starts.as_slice());
        let mut first = 0;
        for ((actual, expected), prepared) in actual_lines
            .iter()
            .zip(&expected_lines)
            .zip(prepared.lines())
        {
            assert_eq!(actual.text, expected.text);
            assert_eq!(actual.source_lines, expected.source_lines);
            assert_eq!(prepared.text.as_ref(), expected.text);
            assert_eq!(prepared.source_line, first + 1);
            assert_eq!(prepared.source_lines, expected.source_lines);
            let next = first + expected.source_lines;
            assert_eq!(
                prepared.source_span,
                dm_syntax::Span::new(
                    starts[first],
                    starts.get(next).copied().unwrap_or(source.len())
                )
            );
            first = next;
        }
        assert_eq!(prepared.lines().len(), expected_lines.len());
    }
}
