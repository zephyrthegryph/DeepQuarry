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
    top_level_assignment_index_from_span_tokens(source, &lex_spans(source).tokens)
}
/// The SAME assignment partition over already-issued primary tokens.
pub fn top_level_assignment_index_from_span_tokens(
    source: &str,
    tokens: &[SpanToken],
) -> Option<usize> {
    let mut depth = 0usize;
    for token in tokens {
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

#[cfg(test)]
thread_local! {static WHOLE_LEX_CALLS:std::cell::Cell<usize>=const {std::cell::Cell::new(0)};}
pub(super) fn parse_with_body_mode(source: &str, skeleton: bool) -> DeclarationSkeleton {
    #[cfg(test)]
    WHOLE_LEX_CALLS.with(|n| n.set(n.get() + 1));
    let lexed = lex_spans(source);
    let (items, mut diagnostics) =
        parse_original_span_range(source, Span::new(0, source.len()), &lexed.tokens, skeleton);
    let mut lexical = lexed.diagnostics;
    lexical.append(&mut diagnostics);
    DeclarationSkeleton {
        items,
        tokens: lexed.tokens,
        diagnostics: lexical,
    }
}
/// Internal grammar over borrowed ORIGINAL primary spans. Does not certify a
/// source acquisition, current semantic owner, or completeness on its own.
pub(super) fn parse_original_span_range(
    source: &str,
    range: Span,
    tokens: &[SpanToken],
    skeleton: bool,
) -> (Vec<Item>, Vec<Diagnostic>) {
    // Comments remain in `tokens`, but cannot introduce declarations or alter indentation.
    // A byte-for-byte mask keeps the original source spans valid, including UTF-8 offsets.
    let range_source = &source[range.range()];
    let mut visible = range_source.as_bytes().to_vec();
    for token in tokens {
        if token.kind == TokenKind::Comment
            || (token.kind == TokenKind::String && token.text(source).contains('\n'))
        {
            for byte in &mut visible[token.span.start - range.start..token.span.end - range.start] {
                if !matches!(*byte, b'\r' | b'\n') {
                    *byte = b' ';
                }
            }
        }
    }
    let visible = String::from_utf8(visible).expect("comment mask preserves UTF-8");
    let mut delimiters = visible.as_bytes().to_vec();
    for token in tokens {
        if matches!(token.kind, TokenKind::String | TokenKind::Resource) {
            for byte in
                &mut delimiters[token.span.start - range.start..token.span.end - range.start]
            {
                if !matches!(*byte, b'\r' | b'\n') {
                    *byte = b' ';
                }
            }
        }
    }
    let multiline_literals: Vec<Span> = tokens
        .iter()
        .filter(|token| token.kind == TokenKind::String && token.text(source).contains('\n'))
        .map(|token| Span::new(token.span.start - range.start, token.span.end - range.start))
        .collect();
    let mut lines = split_inline_blocks(
        range_source,
        &structural_lines(&visible, &delimiters, &multiline_literals),
        &delimiters,
    );
    for line in &mut lines {
        line.header_start += range.start;
        line.header_end += range.start;
        line.end += range.start;
    }
    let mut diagnostics = Vec::new();
    let (items, _) = parse_level(
        source,
        &lines,
        0,
        0,
        ParseContext {
            in_body: false,
            skeleton,
            tokens,
        },
        &mut diagnostics,
    );
    (items, diagnostics)
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

/// Only borrowed tokens from THIS primary lex pass participate. Normalized
/// header strings and offsets from another source are never consulted.
/// Reissue only lexical header facts over an existing native declaration roster.
/// This is the SAME primary lexer and cursor rule used during initial parsing;
/// no declaration/body parser, adapter, or semantic model is reconstructed.
pub fn primary_header_cursors(
    source: &str,
    headers: impl IntoIterator<Item = Span>,
) -> Result<Vec<(usize, Option<usize>)>, Vec<Diagnostic>> {
    let lexed = lex_spans(source);
    if !lexed.diagnostics.is_empty() {
        return Err(lexed.diagnostics);
    }
    Ok(headers
        .into_iter()
        .map(|header| {
            (
                header.start,
                source
                    .get(header.range())
                    .and_then(|_| primary_declaration_cursor(source, &lexed.tokens, header)),
            )
        })
        .collect())
}
/// Existing native roster plus its ORIGINAL parent links; no new syntax tree.
#[derive(Clone, Copy)]
pub struct PrimaryHeaderInput {
    pub span: Span,
    pub parent: Option<usize>,
    pub has_children: bool,
}
/// One shared primary lexical query issues cursor AND scoped qualifier facts.
/// Parent indices must refer strictly backward to the borrowed roster.
pub fn primary_header_facts(
    source: &str,
    headers: &[PrimaryHeaderInput],
) -> Result<Vec<(usize, Option<usize>, u8)>, Vec<Diagnostic>> {
    let lexed = lex_spans(source);
    if !lexed.diagnostics.is_empty() {
        return Err(lexed.diagnostics);
    }
    let mut rows = Vec::with_capacity(headers.len());
    let mut contexts = Vec::with_capacity(headers.len());
    for (index, header) in headers.iter().enumerate() {
        let parent = match header.parent {
            Some(parent) if parent < index => contexts[parent],
            Some(_) => None,
            None => None,
        };
        let local = if header.parent.is_some_and(|parent| parent >= index) {
            crate::UNKNOWN_HEADER_QUALIFIERS
        } else {
            crate::declaration_qualifiers::primary_header_qualifiers(
                source,
                &lexed.tokens,
                header.span,
                header.has_children,
            )
        };
        let (flags, context) = crate::inherit_header_qualifiers(local, parent);
        contexts.push(context);
        rows.push((
            header.span.start,
            primary_declaration_cursor(source, &lexed.tokens, header.span),
            flags,
        ));
    }
    Ok(rows)
}
fn primary_declaration_cursor(source: &str, tokens: &[SpanToken], header: Span) -> Option<usize> {
    let first = tokens.partition_point(|token| token.span.end <= header.start);
    let end = tokens.partition_point(|token| token.span.start < header.end);
    let mut depth = 0usize;
    let mut last = None;
    let mut last_end = None;
    for token in tokens.get(first..end)? {
        if matches!(
            token.kind,
            TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
        ) {
            continue;
        }
        // Raw preprocessing syntax (notably backslash continuation) has no
        // primary declaration meaning before the existing preprocess pass.
        // Never turn its following newline into an invented declaration token.
        if token.kind == TokenKind::Unknown {
            return None;
        }
        match token.text(source) {
            "=" if depth == 0 => return Some(token.span.start),
            "(" | "[" | "{" => depth += 1,
            ")" | "]" | "}" => depth = depth.checked_sub(1)?,
            _ => (),
        }
        last = Some(token.span.start);
        last_end = Some(token.span.end);
    }
    if depth != 0 {
        return None;
    }
    // Pinned declarations without an initializer observe their terminator.
    // A multiline comment/doc cursor remains unsupported, rather than guessed.
    for token in tokens.iter().skip(end) {
        match token.kind {
            TokenKind::Whitespace => continue,
            TokenKind::Comment => {
                if token.text(source).contains(['\r', '\n']) {
                    return None;
                }
                continue;
            }
            TokenKind::Newline => return Some(token.span.start),
            _ if matches!(token.text(source), ";" | "}") => return Some(token.span.start),
            _ => return None,
        }
    }
    // Pinned IndentProcessor's final synthetic semicolon uses last_input_loc,
    // not EOF end. A final significant token proves that cursor only if it
    // reaches EOF; trailing whitespace/comments have another token policy.
    if last_end == Some(source.len()) {
        last
    } else {
        None
    }
}

#[derive(Clone, Copy)]
struct ParseContext<'a> {
    in_body: bool,
    skeleton: bool,
    tokens: &'a [SpanToken],
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
    context: ParseContext<'_>,
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
                    tokens: context.tokens,
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
                    declaration_cursor: None,
                    checker_qualifiers: crate::UNKNOWN_HEADER_QUALIFIERS,
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
            declaration_cursor: (!context.in_body
                && !matches!(kind, ItemKind::Proc | ItemKind::Verb))
            .then(|| {
                primary_declaration_cursor(
                    source,
                    context.tokens,
                    Span::new(line.header_start, line.header_end),
                )
            })
            .flatten(),
            checker_qualifiers: if !context.in_body
                && !matches!(kind, ItemKind::Proc | ItemKind::Verb)
            {
                crate::declaration_qualifiers::primary_header_qualifiers(
                    source,
                    context.tokens,
                    Span::new(line.header_start, line.header_end),
                    has_children,
                )
            } else {
                crate::UNKNOWN_HEADER_QUALIFIERS
            },
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

#[cfg(test)]
mod primary_declaration_cursor_tests {
    use super::*;
    fn vars(items: &[Item], out: &mut Vec<usize>) {
        for item in items {
            if item.kind == ItemKind::Var && !item.header.trim_end().ends_with('/') {
                if let Some(at) = item.declaration_cursor {
                    out.push(at);
                }
            }
            vars(&item.children, out);
        }
    }
    #[test]
    fn assignment_cursor_is_the_original_primary_equal_before_normalization() {
        let source = "/datum/probe\n    var/item = list(\n        1)\n";
        let parsed = parse_declaration_skeleton(source);
        assert!(parsed.diagnostics.is_empty(), "{parsed:?}");
        let mut cursors = Vec::new();
        vars(&parsed.items, &mut cursors);
        assert_eq!(cursors, [source.find('=').unwrap()]);
        assert_ne!(cursors[0], parsed.items[0].children[0].header_span.start);
    }
    #[test]
    fn semicolon_and_eof_are_real_primary_terminator_cursors() {
        let source = "var/first;var/second";
        let parsed = parse_declaration_skeleton(source);
        assert!(parsed.diagnostics.is_empty(), "{parsed:?}");
        assert_eq!(
            parsed.items[0].declaration_cursor,
            Some(source.find(';').unwrap())
        );
        assert_eq!(
            parsed.items[1].declaration_cursor,
            Some(source.find("second").unwrap())
        );
    }
    #[test]
    fn raw_preprocessor_continuation_has_no_primary_cursor_before_preprocessing() {
        let source = "/datum/probe\n    var/item \\\n        = 1\n";
        let parsed = parse_declaration_skeleton(source);
        assert!(parsed.diagnostics.is_empty(), "{parsed:?}");
        assert_eq!(parsed.items[0].children[0].declaration_cursor, None);
    }

    #[test]
    fn balanced_multiline_array_suffix_uses_actual_equal_on_later_line() {
        let source = "/datum/probe\n    var/items[\n        3] = 1\n";
        let parsed = parse_declaration_skeleton(source);
        assert!(parsed.diagnostics.is_empty(), "{parsed:?}");
        assert_eq!(
            parsed.items[0].children[0].declaration_cursor,
            Some(source.find('=').unwrap())
        );
        assert_eq!(parsed.items[0].children.len(), 1);
    }
    #[test]
    fn unknown_multiline_trailing_comment_never_invents_a_suffix_cursor() {
        let source = "var/item /* comment\n remaining */\n";
        let parsed = parse_declaration_skeleton(source);
        assert!(parsed
            .items
            .iter()
            .all(|item| item.declaration_cursor.is_none()));
    }
}

#[cfg(test)]
mod declaration_eof_policy_tests {
    use super::*;
    #[test]
    fn bare_and_array_eof_use_actual_last_token_but_unproved_tail_refuses() {
        for (source, expected) in [
            ("var/value", Some(4)),
            ("var/items[3]", Some(11)),
            ("var/value ", None),
            ("var/value // tail", None),
        ] {
            let parsed = parse_declaration_skeleton(source);
            assert!(parsed.diagnostics.is_empty());
            assert_eq!(parsed.items[0].declaration_cursor, expected, "{source:?}");
        }
    }
}

#[cfg(test)]
mod shared_original_body_tests {
    use super::*;
    fn proc(items: &[Item]) -> &Item {
        for i in items {
            if matches!(i.kind, ItemKind::Proc | ItemKind::Verb) {
                return i;
            }
            if !i.children.is_empty() {
                return proc(&i.children);
            }
        }
        panic!("original procedure")
    }
    #[test]
    fn cold_tokens_feed_body_and_formal_grammar_without_another_whole_lex() {
        for source in [
            "/datum/prefix\n/proc/p(obj/item/x = list(1,2))\n    var/y[6 / 2]\n    return x\n",
            "/datum/holder\n    proc/check(datum/x)\n        if(x) { return x; }\n",
            "/proc/p(value=\"é,()\")\r\n    // comment ([])\r\n    return \"text\"\r\n",
        ] {
            let cold = parse_declaration_skeleton(source);
            assert!(cold.diagnostics.is_empty(), "{:?}", cold.diagnostics);
            let span = proc(&cold.items).span;
            let before = WHOLE_LEX_CALLS.with(|n| n.get());
            let shared =
                crate::parse_proc_with_origins_from_spans(source, span, &cold.tokens, 0).unwrap();
            assert_eq!(
                WHOLE_LEX_CALLS.with(|n| n.get()),
                before,
                "shared body/formal grammar cannot lex full procedure again"
            );
            let old = crate::parse_proc_with_origins_at_span(source, span).unwrap();
            assert_eq!(
                WHOLE_LEX_CALLS.with(|n| n.get()),
                before + 1,
                "compatibility path independently exercises original lexical entry"
            );
            assert_eq!(shared.item, old.item);
            assert_eq!(shared.opening_parenthesis, old.opening_parenthesis);
            assert_eq!(shared.parameters, old.parameters);
        }
    }
    #[test]
    fn original_body_error_locations_and_foreign_range_denial_are_not_empty_success() {
        let source = "/datum/prefix\n/proc/p()\n    return\n        broken()\n";
        let cold = parse_declaration_skeleton(source);
        let span = proc(&cold.items).span;
        let old = crate::parse_proc_with_origins_at_span(source, span)
            .err()
            .unwrap();
        let current = crate::parse_proc_with_origins_from_spans(source, span, &cold.tokens, 0)
            .err()
            .unwrap();
        assert_eq!(current, old);
        let wrong = Span::new(span.start + 1, span.end);
        assert!(crate::parse_proc_with_origins_from_spans(source, wrong, &cold.tokens, 0).is_err());
    }
}
