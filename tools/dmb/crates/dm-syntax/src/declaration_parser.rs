use super::*;

#[derive(Clone)]
struct Line {
    indent: usize,
    header_start: usize,
    header_end: usize,
    end: usize,
}

/// Locate an assignment outside argument lists, indexing, strings, and braces.
pub fn top_level_assignment_index(source: &str) -> Option<usize> {
    let mut depth = 0usize;
    for token in lex_spans(source).tokens {
        if !matches!(token.kind, TokenKind::Operator | TokenKind::Punctuation) {
            continue;
        }
        match token.text(source) {
            "(" | "[" | "{" => depth += 1,
            ")" | "]" | "}" => depth = depth.saturating_sub(1),
            "=" if depth == 0 => return Some(token.span.start),
            _ => {}
        }
    }
    None
}
pub(super) fn classify(header: &str, has_children: bool) -> ItemKind {
    let h = header.trim();
    let assignment = top_level_assignment_index(h);
    let boundary = lex_spans(h)
        .tokens
        .into_iter()
        .find(|token| {
            matches!(token.kind, TokenKind::Punctuation | TokenKind::Operator)
                && matches!(token.text(h), "(" | "{" | "=")
        })
        .map_or(h.len(), |token| token.span.start);
    let definition_prefix = &h[..boundary];
    if h.starts_with("set ")
        || h.starts_with("return")
        || h.starts_with("if(")
        || h.starts_with("if (")
        || h.starts_with("for(")
        || h.starts_with("for (")
        || h.starts_with("while(")
        || h.starts_with("while (")
        || h.starts_with("switch(")
        || h.starts_with("switch (")
        || h.starts_with("spawn(")
        || h.starts_with("spawn (")
        || h.starts_with("else")
        || h.starts_with("try")
        || h.starts_with("catch")
        || h.starts_with("break")
        || h.starts_with("continue")
        || h.starts_with("throw ")
        || h.starts_with(".")
    {
        return ItemKind::Statement;
    }
    if definition_prefix.starts_with("var/")
        || definition_prefix.starts_with("/var/")
        || definition_prefix.contains("/var/")
    {
        return ItemKind::Var;
    }
    if definition_prefix.starts_with("proc/")
        || definition_prefix.starts_with("/proc/")
        || definition_prefix.contains("/proc/")
    {
        return ItemKind::Proc;
    }
    if definition_prefix.starts_with("verb/")
        || definition_prefix.starts_with("/verb/")
        || definition_prefix.contains("/verb/")
    {
        return ItemKind::Verb;
    }
    if h.find('(')
        .is_some_and(|open| h.find('{').is_none_or(|brace| open < brace))
    {
        if let Some(open) = h.find('(') {
            if assignment.is_none_or(|index| index > open) {
                return ItemKind::Proc;
            }
        }
    }
    if (h.starts_with('/') && assignment.is_none())
        || (has_children && assignment.is_none())
        || (!h.is_empty() && h.chars().all(ident_continue))
    {
        return ItemKind::Type;
    }
    if h.contains('=') || h.ends_with(')') {
        return ItemKind::Statement;
    }
    ItemKind::Unknown
}

/// Parse indentation and declaration nesting, preserving all tokens for later expression parsing.
/// A malformed indentation transition produces a diagnostic and parsing continues.
pub fn parse(source: &str) -> AstFile {
    let parsed = parse_with_body_mode(source, false);
    AstFile {
        items: parsed.items,
        tokens: parsed
            .tokens
            .into_iter()
            .map(|token| Token {
                kind: token.kind,
                span: token.span,
                text: token.text(source).to_owned(),
            })
            .collect(),
        diagnostics: parsed.diagnostics,
    }
}

/// Declaration items and source-backed lexical spans. Token text remains in
/// the caller's source rather than a separately allocated string per token.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct DeclarationSkeleton {
    pub items: Vec<Item>,
    pub tokens: Vec<SpanToken>,
    pub diagnostics: Vec<Diagnostic>,
}

/// Parse declarations and exact procedure envelopes while retaining only
/// setting leaves and their structural context inside executable bodies.
/// Lexical and indentation diagnostics use the same grammar as [`parse`].
pub fn parse_declaration_skeleton(source: &str) -> DeclarationSkeleton {
    parse_with_body_mode(source, true)
}

pub(super) fn parse_with_body_mode(source: &str, skeleton: bool) -> DeclarationSkeleton {
    let lexed = lex_spans(source);
    // Comments remain in `tokens`, but cannot introduce declarations or alter indentation.
    // A byte-for-byte mask keeps the original source spans valid, including UTF-8 offsets.
    let mut visible = source.as_bytes().to_vec();
    for token in &lexed.tokens {
        if token.kind == TokenKind::Comment
            || (token.kind == TokenKind::String && token.text(source).contains('\n'))
        {
            for byte in &mut visible[token.span.range()] {
                if !matches!(*byte, b'\r' | b'\n') {
                    *byte = b' ';
                }
            }
        }
    }
    let visible = String::from_utf8(visible).expect("comment mask preserves UTF-8");
    let mut delimiters = visible.as_bytes().to_vec();
    for token in &lexed.tokens {
        if matches!(token.kind, TokenKind::String | TokenKind::Resource) {
            for byte in &mut delimiters[token.span.range()] {
                if !matches!(*byte, b'\r' | b'\n') {
                    *byte = b' ';
                }
            }
        }
    }
    let multiline_literals: Vec<Span> = lexed
        .tokens
        .iter()
        .filter(|token| token.kind == TokenKind::String && token.text(source).contains('\n'))
        .map(|token| token.span)
        .collect();
    let lines = split_inline_blocks(
        source,
        &structural_lines(&visible, &delimiters, &multiline_literals),
        &delimiters,
    );
    let mut diagnostics = lexed.diagnostics;
    let (items, _) = parse_level(
        source,
        &lines,
        0,
        0,
        ParseContext {
            in_body: false,
            skeleton,
        },
        &mut diagnostics,
    );
    DeclarationSkeleton {
        items,
        tokens: lexed.tokens,
        diagnostics,
    }
}

fn structural_lines(visible: &str, delimiters: &[u8], multiline_literals: &[Span]) -> Vec<Line> {
    let mut lines = Vec::new();
    let mut offset = 0;
    let mut pending: Option<Line> = None;
    let mut depth = 0usize;
    let mut literal_cursor = 0usize;
    for raw in visible.split_inclusive('\n') {
        while multiline_literals
            .get(literal_cursor)
            .is_some_and(|literal| literal.end <= offset)
        {
            literal_cursor += 1;
        }
        let leading = raw
            .bytes()
            .take_while(|b| *b == b' ' || *b == b'\t')
            .count();
        let trimmed = raw[leading..].trim_end_matches(['\r', '\n', ' ', '\t']);
        for byte in &delimiters[offset..offset + raw.len()] {
            match byte {
                b'(' | b'[' => depth += 1,
                b')' | b']' => depth = depth.saturating_sub(1),
                _ => {}
            }
        }
        if !trimmed.is_empty() && !trimmed.starts_with("//") {
            if let Some(line) = pending.as_mut() {
                line.header_end = offset + leading + trimmed.len();
                line.end = offset + raw.len();
            } else {
                // An included file's first line can inherit spaces left by
                // the expanded #include directive. Absolute DM paths declare
                // from the root regardless of that textual indentation.
                let indent = if trimmed.starts_with('/') {
                    0
                } else {
                    raw[..leading]
                        .bytes()
                        .map(|b| if b == b'\t' { 4 } else { 1 })
                        .sum()
                };
                pending = Some(Line {
                    indent,
                    header_start: offset + leading,
                    header_end: offset + leading + trimmed.len(),
                    end: offset + raw.len(),
                });
            }
        } else if let Some(line) = pending.as_mut() {
            line.end = offset + raw.len();
        }
        let mut inside_literal = false;
        for literal in multiline_literals[literal_cursor..]
            .iter()
            .take_while(|literal| literal.start < offset + raw.len())
        {
            if let Some(line) = pending.as_mut() {
                line.header_end = line.header_end.max(literal.end.min(offset + raw.len()));
            }
            inside_literal |= literal.end > offset + raw.len();
        }
        if depth == 0 && !inside_literal {
            if let Some(line) = pending.take() {
                lines.push(line);
            }
        }
        offset += raw.len();
    }
    if let Some(line) = pending {
        lines.push(line);
    }
    lines
}

fn split_inline_blocks(source: &str, lines: &[Line], delimiters: &[u8]) -> Vec<Line> {
    let mut result = Vec::new();
    let mut brace_depth = 0usize;
    let mut initializer_depth = 0usize;
    for line in lines {
        let mut segment_start = line.header_start;
        let mut paren_depth = 0usize;
        let mut inline_do_if = false;
        for at in line.header_start..line.header_end {
            match delimiters[at] {
                b'(' | b'[' => paren_depth += 1,
                b')' | b']' => paren_depth = paren_depth.saturating_sub(1),
                b'{' if paren_depth == 0
                    && (initializer_depth > 0
                        || is_object_initializer(&source[segment_start..at])) =>
                {
                    initializer_depth += 1;
                }
                b'}' if paren_depth == 0 && initializer_depth > 0 => {
                    initializer_depth -= 1;
                }
                b'{' | b'}' | b';' if paren_depth == 0 && initializer_depth == 0 => {
                    let segment = &source[segment_start..at];
                    if let Some(do_at) = (delimiters[at] == b'{' && !inline_do_if)
                        .then(|| inline_if_do_suffix(segment))
                        .flatten()
                    {
                        push_inline_segment(
                            &mut result,
                            source,
                            segment_start,
                            segment_start + do_at,
                            line.indent + brace_depth * 4,
                        );
                        push_inline_segment(
                            &mut result,
                            source,
                            segment_start + do_at,
                            at,
                            line.indent + brace_depth * 4 + 4,
                        );
                        inline_do_if = true;
                    } else {
                        push_inline_segment(
                            &mut result,
                            source,
                            segment_start,
                            at,
                            line.indent + brace_depth * 4 + usize::from(inline_do_if) * 4,
                        );
                    }
                    if delimiters[at] == b'{' {
                        brace_depth += 1;
                    } else if delimiters[at] == b'}' {
                        brace_depth = brace_depth.saturating_sub(1);
                    } else if brace_depth == 0
                        && inline_do_if
                        && segment.trim_start().starts_with("while")
                    {
                        inline_do_if = false;
                    }
                    segment_start = at + 1;
                }
                _ => {}
            }
        }
        let indent = line.indent + brace_depth * 4 + usize::from(inline_do_if) * 4;
        if let Some(body_start) =
            inline_proc_body_start(source, delimiters, segment_start, line.header_end)
        {
            push_inline_segment(&mut result, source, segment_start, body_start, indent);
            push_inline_segment(&mut result, source, body_start, line.header_end, indent + 4);
        } else {
            push_inline_segment(&mut result, source, segment_start, line.header_end, indent);
        }
    }
    result
}

fn inline_proc_body_start(
    source: &str,
    delimiters: &[u8],
    start: usize,
    end: usize,
) -> Option<usize> {
    let segment = source[start..end].trim_start();
    let opening = segment.find('(')?;
    let prefix = segment[..opening].trim();
    if !(prefix.starts_with("proc/")
        || prefix.starts_with("verb/")
        || prefix.starts_with("/proc/")
        || prefix.starts_with("/verb/")
        || prefix.contains("/proc/")
        || prefix.contains("/verb/")
        || (prefix.starts_with('/')
            && !prefix.chars().any(char::is_whitespace)
            && top_level_assignment_index(prefix).is_none()))
    {
        return None;
    }
    let absolute_open = start + source[start..end].find('(')?;
    let mut depth = 0usize;
    for at in absolute_open..end {
        match delimiters[at] {
            b'(' => depth += 1,
            b')' => {
                depth = depth.saturating_sub(1);
                if depth == 0 {
                    let body_start =
                        at + 1 + source[at + 1..end].len() - source[at + 1..end].trim_start().len();
                    let body = &source[body_start..end];
                    if !body.is_empty() && !body.starts_with("as ") {
                        return Some(body_start);
                    }
                    return None;
                }
            }
            _ => {}
        }
    }
    None
}

fn inline_if_do_suffix(segment: &str) -> Option<usize> {
    let trimmed = segment.trim();
    if !(trimmed.starts_with("if(") || trimmed.starts_with("if (")) || !trimmed.ends_with("do") {
        return None;
    }
    let at = segment.rfind("do")?;
    segment[..at]
        .chars()
        .next_back()
        .filter(|ch| ch.is_whitespace())
        .map(|_| at)
}

fn is_object_initializer(prefix: &str) -> bool {
    let token = prefix.split_whitespace().next_back().unwrap_or("");
    token.contains('/')
        && !token.ends_with(')')
        && !token.ends_with(']')
        && (prefix.contains('=')
            || lex_spans(prefix)
                .tokens
                .iter()
                .any(|token| token.kind == TokenKind::Ident && token.text(prefix) == "new")
            || prefix.contains('(')
            || prefix.contains(','))
}

fn push_inline_segment(
    lines: &mut Vec<Line>,
    source: &str,
    start: usize,
    end: usize,
    indent: usize,
) {
    let segment = &source[start..end];
    let trimmed_start = segment.len() - segment.trim_start().len();
    let trimmed_end = segment.trim_end().len();
    if trimmed_end <= trimmed_start {
        return;
    }
    lines.push(Line {
        indent,
        header_start: start + trimmed_start,
        header_end: start + trimmed_end,
        end: start + trimmed_end,
    });
}

#[derive(Clone, Copy)]
struct ParseContext {
    in_body: bool,
    skeleton: bool,
}

fn body_keyword(header: &str, keyword: &str) -> bool {
    header
        .trim_start()
        .strip_prefix(keyword)
        .is_some_and(|tail| {
            tail.is_empty() || tail.starts_with(char::is_whitespace) || tail.starts_with('(')
        })
}

pub(crate) const RETURN_BLOCK_UNSUPPORTED: &str = ": missing expression";
pub(crate) fn return_has_block(header: &str, has_children: bool) -> bool {
    has_children && body_keyword(header, "return")
}

fn retain_setting_chains(items: Vec<Item>) -> Vec<Item> {
    fn has_setting(item: &Item) -> bool {
        body_keyword(&item.header, "set") || item.children.iter().any(has_setting)
    }
    let mut input = items.into_iter().peekable();
    let mut result = Vec::new();
    while let Some(item) = input.next() {
        if body_keyword(&item.header, "if") {
            let mut chain = vec![item];
            while input
                .peek()
                .is_some_and(|item| body_keyword(&item.header, "else"))
            {
                chain.push(input.next().unwrap());
            }
            if chain.iter().any(has_setting) {
                result.extend(chain);
            }
        } else if has_setting(&item) {
            result.push(item);
        }
    }
    result
}

fn parse_level(
    source: &str,
    lines: &[Line],
    mut index: usize,
    indent: usize,
    context: ParseContext,
    diagnostics: &mut Vec<Diagnostic>,
) -> (Vec<Item>, usize) {
    let mut items = Vec::new();
    let mut saw_item = false;
    while index < lines.len() {
        let line = &lines[index];
        if line.indent < indent {
            break;
        }
        if line.indent > indent && saw_item {
            break;
        }
        if line.indent > indent {
            diagnostics.push(Diagnostic {
                span: Span::new(line.header_start, line.header_end),
                kind: DiagnosticKind::Indentation,
                message: "unexpected indentation".into(),
            });
        }
        let mut end = line.end;
        let mut children = Vec::new();
        let has_children = index + 1 < lines.len() && lines[index + 1].indent > line.indent;
        let header = &source[line.header_start..line.header_end];
        let kind = if context.in_body {
            ItemKind::Statement
        } else {
            classify(header, has_children)
        };
        if context.in_body && return_has_block(header, has_children) {
            // DreamMaker rejects the first indented line under `return`.
            let child = &lines[index + 1];
            diagnostics.push(Diagnostic {
                span: Span::new(child.header_start, child.header_end),
                kind: DiagnosticKind::Statement,
                message: RETURN_BLOCK_UNSUPPORTED.into(),
            });
        }
        if has_children {
            let (parsed, next) = parse_level(
                source,
                lines,
                index + 1,
                lines[index + 1].indent,
                ParseContext {
                    in_body: context.in_body
                        || matches!(kind, ItemKind::Proc | ItemKind::Verb | ItemKind::Statement),
                    skeleton: context.skeleton
                        && (context.in_body || !matches!(kind, ItemKind::Statement)),
                },
                diagnostics,
            );
            children = parsed;
            index = next;
            end = if context.skeleton {
                lines[next - 1].end
            } else {
                children.last().map_or(end, |child| child.span.end)
            };
        } else {
            index += 1;
        }
        saw_item = true;
        if context.skeleton
            && context.in_body
            && children.is_empty()
            && !["set", "if", "else"]
                .iter()
                .any(|keyword| body_keyword(header, keyword))
        {
            // A discarded executable sibling still separates conditional
            // chains. Retain a zero-allocation delimiter until compaction so
            // a later `else` cannot attach across that original sibling.
            if items.last().is_some_and(|item: &Item| {
                body_keyword(&item.header, "if") || body_keyword(&item.header, "else")
            }) {
                items.push(Item {
                    kind,
                    header: String::new(),
                    span: Span::new(line.header_start, end),
                    header_span: Span::new(line.header_start, line.header_end),
                    indent: line.indent,
                    children,
                });
            }
            continue;
        }
        items.push(Item {
            kind,
            header: header.to_owned(),
            span: Span::new(line.header_start, end),
            header_span: Span::new(line.header_start, line.header_end),
            indent: line.indent,
            children,
        });
    }
    if context.skeleton && context.in_body {
        (retain_setting_chains(items), index)
    } else {
        (items, index)
    }
}
