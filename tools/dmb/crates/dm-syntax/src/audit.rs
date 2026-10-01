//! Bounded syntax inventory for large preprocessed worlds. The caller keeps
//! the source text; this module never builds a whole-project token or AST Vec.

use crate::{
    parse, parse_proc_body, quoted_end, AstFile, Diagnostic, DiagnosticKind, Item, ItemKind, Span,
    Statement, StatementKind,
};
use std::collections::BTreeMap;

const MAX_DIAGNOSTIC_GROUPS: usize = 256;

#[derive(Debug, Default)]
pub struct ChunkReport {
    pub parsed_chunks: usize,
    pub parsed_bytes: usize,
    pub skipped_declarations: usize,
    pub skipped_bytes: usize,
    pub first_skipped_span: Option<Span>,
}

/// Invoke `visit` with each bounded AST, then drop it before parsing the next
/// chunk. The callback may retain declarations, but the parser never retains
/// the complete source's tokens or procedure bodies by itself.
pub fn for_each_parsed_chunk(
    source: &str,
    max_chunk_bytes: usize,
    mut visit: impl FnMut(&AstFile, usize),
) -> ChunkReport {
    let limit = max_chunk_bytes.max(1);
    let mut report = ChunkReport::default();
    let mut chunk_start = 0usize;
    let mut chunk_end = 0usize;
    let mut declaration_start = 0usize;
    let mut parse_chunk = |start: usize, end: usize, report: &mut ChunkReport| {
        if source[start..end].trim().is_empty() {
            return;
        }
        let ast = parse(&source[start..end]);
        report.parsed_chunks += 1;
        report.parsed_bytes += end - start;
        visit(&ast, start);
    };
    let mut on_boundary = |boundary: usize| {
        if boundary <= declaration_start {
            return;
        }
        let segment_len = boundary - declaration_start;
        if segment_len > limit {
            if chunk_end > chunk_start {
                parse_chunk(chunk_start, chunk_end, &mut report);
            }
            report.skipped_declarations += 1;
            report.skipped_bytes += segment_len;
            report
                .first_skipped_span
                .get_or_insert(Span::new(declaration_start, boundary));
            chunk_start = boundary;
            chunk_end = boundary;
        } else {
            if chunk_end > chunk_start && boundary - chunk_start > limit {
                parse_chunk(chunk_start, chunk_end, &mut report);
                chunk_start = declaration_start;
            }
            chunk_end = boundary;
        }
        declaration_start = boundary;
    };
    for_each_top_level_boundary(source, &mut on_boundary);
    on_boundary(source.len());
    if chunk_end > chunk_start {
        parse_chunk(chunk_start, chunk_end, &mut report);
    }
    report
}

/// Reparse exactly one procedure from the original source when lowering it.
pub fn parse_proc_at_span(source: &str, span: Span) -> Result<Item, Diagnostic> {
    let Some(slice) = source.get(span.range()) else {
        return Err(Diagnostic {
            span,
            kind: DiagnosticKind::Unsupported,
            message: "procedure span is outside source".into(),
        });
    };
    let mut ast = parse(slice);
    if let Some(mut diagnostic) = ast.diagnostics.into_iter().next() {
        diagnostic.span.start += span.start;
        diagnostic.span.end += span.start;
        return Err(diagnostic);
    }
    if ast.items.len() != 1 || !matches!(ast.items[0].kind, ItemKind::Proc | ItemKind::Verb) {
        return Err(Diagnostic {
            span,
            kind: DiagnosticKind::Unsupported,
            message: "span does not contain one procedure".into(),
        });
    }
    let mut item = ast.items.remove(0);
    rebase_item(&mut item, span.start);
    Ok(item)
}

fn rebase_item(item: &mut Item, offset: usize) {
    item.span.start += offset;
    item.span.end += offset;
    item.header_span.start += offset;
    item.header_span.end += offset;
    for child in &mut item.children {
        rebase_item(child, offset);
    }
}

#[derive(Debug, Default)]
pub struct StreamingAudit {
    pub parsed_chunks: usize,
    pub parsed_bytes: usize,
    pub skipped_declarations: usize,
    pub skipped_bytes: usize,
    pub items: usize,
    pub procedures: usize,
    pub statements: usize,
    pub unsupported_statements: usize,
    pub diagnostic_count: usize,
    pub diagnostic_groups: BTreeMap<String, usize>,
    /// First representative of each diagnostic group, with absolute source span.
    pub diagnostic_examples: BTreeMap<String, Diagnostic>,
    /// The first diagnostics only, with spans relative to the complete source.
    pub diagnostics: Vec<Diagnostic>,
}

impl StreamingAudit {
    fn diagnostic(&mut self, mut diagnostic: Diagnostic, offset: usize, sample_limit: usize) {
        self.diagnostic_count += 1;
        let mut group = diagnostic_group(&diagnostic.message);
        if !self.diagnostic_groups.contains_key(&group)
            && self.diagnostic_groups.len() >= MAX_DIAGNOSTIC_GROUPS
        {
            group = "<other>".into();
        }
        *self.diagnostic_groups.entry(group.clone()).or_default() += 1;
        if !self.diagnostic_examples.contains_key(&group) {
            let mut example = diagnostic.clone();
            example.span.start += offset;
            example.span.end += offset;
            if example.message.len() > 512 {
                example.message.truncate(512);
            }
            self.diagnostic_examples.insert(group, example);
        }
        if self.diagnostics.len() < sample_limit {
            diagnostic.span.start += offset;
            diagnostic.span.end += offset;
            if diagnostic.message.len() > 512 {
                diagnostic.message.truncate(512);
            }
            self.diagnostics.push(diagnostic);
        }
    }

    fn parse_chunk(&mut self, source: &str, offset: usize, sample_limit: usize) {
        if source.trim().is_empty() {
            return;
        }
        let ast = parse(source);
        self.parsed_chunks += 1;
        self.parsed_bytes += source.len();
        for diagnostic in ast.diagnostics {
            self.diagnostic(diagnostic, offset, sample_limit);
        }
        for item in &ast.items {
            self.visit_item(item, offset, sample_limit);
        }
    }

    fn visit_item(&mut self, item: &Item, offset: usize, sample_limit: usize) {
        self.items += 1;
        if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
            self.procedures += 1;
            let body = parse_proc_body(item);
            for diagnostic in body.diagnostics {
                self.diagnostic(diagnostic, offset, sample_limit);
            }
            for statement in &body.statements {
                self.visit_statement(statement);
            }
        } else {
            for child in &item.children {
                self.visit_item(child, offset, sample_limit);
            }
        }
    }

    fn visit_statement(&mut self, statement: &Statement) {
        self.statements += 1;
        match &statement.kind {
            StatementKind::Unsupported => self.unsupported_statements += 1,
            StatementKind::If {
                then_branch,
                else_branch,
                ..
            } => {
                for child in then_branch.iter().chain(else_branch) {
                    self.visit_statement(child);
                }
            }
            StatementKind::While { body, .. }
            | StatementKind::DoWhile { body, .. }
            | StatementKind::Spawn { body, .. }
            | StatementKind::For { body, .. } => {
                for child in body {
                    self.visit_statement(child);
                }
            }
            StatementKind::Switch {
                cases, else_branch, ..
            } => {
                for case in cases {
                    for child in &case.body {
                        self.visit_statement(child);
                    }
                }
                for child in else_branch {
                    self.visit_statement(child);
                }
            }
            StatementKind::Try {
                body, catch_body, ..
            } => {
                for child in body.iter().chain(catch_body) {
                    self.visit_statement(child);
                }
            }
            _ => {}
        }
    }

    fn skip_oversized(&mut self, start: usize, end: usize, sample_limit: usize) {
        self.skipped_declarations += 1;
        self.skipped_bytes += end - start;
        self.diagnostic(
            Diagnostic {
                span: Span::new(start, end),
                kind: DiagnosticKind::Unsupported,
                message: "top-level declaration exceeds syntax audit chunk limit".into(),
            },
            0,
            sample_limit,
        );
    }
}

fn diagnostic_group(message: &str) -> String {
    for prefix in [
        "unexpected token in expression:",
        "unexpected expression token:",
        "unsupported expression token:",
    ] {
        if message.starts_with(prefix) {
            return prefix.into();
        }
    }
    message.chars().take(160).collect()
}

/// Parse top-level declarations in bounded chunks. A declaration larger than
/// `max_chunk_bytes` is counted and skipped instead of allowing an unbounded
/// parse. `max_diagnostics` caps retained samples, not the diagnostic count.
/// 256 KiB chunks are suitable for repository-wide audits.
pub fn audit_source_streaming(
    source: &str,
    max_chunk_bytes: usize,
    max_diagnostics: usize,
) -> StreamingAudit {
    let limit = max_chunk_bytes.max(1);
    let mut result = StreamingAudit::default();
    let mut chunk_start = 0usize;
    let mut chunk_end = 0usize;
    let mut declaration_start = 0usize;
    let mut on_boundary = |boundary: usize| {
        if boundary <= declaration_start {
            return;
        }
        let segment_len = boundary - declaration_start;
        if segment_len > limit {
            if chunk_end > chunk_start {
                result.parse_chunk(
                    &source[chunk_start..chunk_end],
                    chunk_start,
                    max_diagnostics,
                );
            }
            result.skip_oversized(declaration_start, boundary, max_diagnostics);
            chunk_start = boundary;
            chunk_end = boundary;
        } else {
            if chunk_end > chunk_start && boundary - chunk_start > limit {
                result.parse_chunk(
                    &source[chunk_start..chunk_end],
                    chunk_start,
                    max_diagnostics,
                );
                chunk_start = declaration_start;
            }
            chunk_end = boundary;
        }
        declaration_start = boundary;
    };
    for_each_top_level_boundary(source, &mut on_boundary);
    on_boundary(source.len());
    if chunk_end > chunk_start {
        result.parse_chunk(
            &source[chunk_start..chunk_end],
            chunk_start,
            max_diagnostics,
        );
    }
    result
}

fn for_each_top_level_boundary(source: &str, mut visit: impl FnMut(usize)) {
    let mut at_line_start = true;
    let mut indented = false;
    let mut delimiter_depth = 0usize;
    let mut pos = 0usize;
    while pos < source.len() {
        let rest = &source[pos..];
        if rest.starts_with("//") {
            pos += rest.find('\n').unwrap_or(rest.len());
            continue;
        }
        if rest.starts_with("/*") {
            let mut depth = 1usize;
            let mut cursor = 2usize;
            while depth > 0 && cursor + 1 < rest.len() {
                if rest[cursor..].starts_with("/*") {
                    depth += 1;
                    cursor += 2;
                } else if rest[cursor..].starts_with("*/") {
                    depth -= 1;
                    cursor += 2;
                } else {
                    cursor += rest[cursor..].chars().next().unwrap().len_utf8();
                }
            }
            let end = if depth == 0 { cursor } else { rest.len() };
            (at_line_start, indented) =
                after_token_line_start(&rest[..end], at_line_start, indented, true);
            pos += end;
            continue;
        }
        let string = if rest.starts_with("@{\"") {
            quoted_end(&rest[1..], true, true).map(|end| end + 1)
        } else if rest.starts_with("{\"") {
            quoted_end(rest, true, false)
        } else if rest.starts_with("@\"") {
            quoted_end(&rest[1..], false, true).map(|end| end + 1)
        } else if rest.starts_with('"') {
            quoted_end(rest, false, false)
        } else {
            None
        };
        if let Some(end) = string {
            (at_line_start, indented) =
                after_token_line_start(&rest[..end], at_line_start, indented, false);
            pos += end;
            continue;
        }
        if rest.starts_with('\'') {
            let mut escaped = false;
            let mut end = rest.len();
            for (at, ch) in rest.char_indices().skip(1) {
                if escaped {
                    escaped = false;
                } else if ch == '\\' {
                    escaped = true;
                } else if ch == '\'' {
                    end = at + 1;
                    break;
                }
            }
            (at_line_start, indented) =
                after_token_line_start(&rest[..end], at_line_start, indented, false);
            pos += end;
            continue;
        }
        let ch = rest.chars().next().unwrap();
        if ch == '\n' {
            at_line_start = true;
            indented = false;
        } else if matches!(ch, ' ' | '\t') && at_line_start {
            indented = true;
        } else if !matches!(ch, ' ' | '\t' | '\r') {
            // Expanded #include directives can leave spaces before the first
            // absolute declaration path of an included file.
            if at_line_start && delimiter_depth == 0 && (!indented || ch == '/') {
                visit(pos);
            }
            at_line_start = false;
        }
        match ch {
            '(' | '[' | '{' => delimiter_depth += 1,
            ')' | ']' | '}' => delimiter_depth = delimiter_depth.saturating_sub(1),
            _ => {}
        }
        pos += ch.len_utf8();
    }
}

fn after_token_line_start(
    token: &str,
    previous: bool,
    previously_indented: bool,
    trivia: bool,
) -> (bool, bool) {
    match token.rfind('\n') {
        Some(at) => {
            let tail = &token[at + 1..];
            (
                tail.bytes()
                    .all(|byte| matches!(byte, b' ' | b'\t' | b'\r')),
                tail.bytes().any(|byte| matches!(byte, b' ' | b'\t')),
            )
        }
        None if trivia => (previous, previously_indented),
        None => (false, previously_indented),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chunks_procs_without_retaining_project_ast() {
        let source = "/proc/a()\n    return 1\n/proc/b()\n    return 2\n/proc/c()\n    return 3\n";
        let audit = audit_source_streaming(source, 25, 5);
        assert_eq!(audit.procedures, 3);
        assert_eq!(audit.statements, 3);
        assert_eq!(audit.parsed_chunks, 3);
        assert_eq!(audit.parsed_bytes, source.len());
        assert_eq!(audit.skipped_declarations, 0);
    }

    #[test]
    fn oversized_declaration_is_skipped_and_diagnostics_capped() {
        let source = format!(
            "/proc/big()\n    return \"{}\"\n/proc/small()\n    return 2\n",
            "x".repeat(200)
        );
        let audit = audit_source_streaming(&source, 80, 1);
        assert_eq!(audit.skipped_declarations, 1);
        assert_eq!(audit.procedures, 1);
        assert_eq!(audit.diagnostic_count, 1, "{audit:?}");
        assert_eq!(audit.diagnostics.len(), 1);
    }

    #[test]
    fn block_string_and_nested_comment_do_not_split_chunks() {
        let source = "/proc/a()\n    var/text = {\"line\n/proc/not_real()\nend\"}\n/* outer /* inner */ still comment\n/proc/not_real_either()\n*/\n/proc/b()\n    return 2\n";
        let audit = audit_source_streaming(source, 256, 5);
        assert_eq!(audit.procedures, 2);
        assert_eq!(audit.skipped_declarations, 0);
    }

    #[test]
    fn callback_chunks_and_reparses_proc_at_absolute_span() {
        let source = "/proc/a()\n    return 1\n/proc/b()\n    return 2\n";
        let mut spans = Vec::new();
        let report = for_each_parsed_chunk(source, 25, |ast, offset| {
            for item in &ast.items {
                spans.push(Span::new(item.span.start + offset, item.span.end + offset));
            }
        });
        assert_eq!(report.parsed_chunks, 2);
        assert_eq!(report.skipped_declarations, 0);
        let proc_b = parse_proc_at_span(source, spans[1]).unwrap();
        assert_eq!(proc_b.header, "/proc/b()");
        assert_eq!(proc_b.span, spans[1]);
        assert_eq!(proc_b.children[0].header, "return 2");
        assert!(proc_b.children[0].span.start > spans[1].start);
    }

    #[test]
    fn reparses_implicit_override_from_nested_type() {
        let source = "/datum/example\n    run()\n        return 7\n";
        let ast = parse(source);
        let original = &ast.items[0].children[0];
        assert_eq!(original.kind, ItemKind::Proc);
        let reparsed = parse_proc_at_span(source, original.span).unwrap();
        assert_eq!(reparsed.span, original.span);
        assert_eq!(reparsed.header, "run()");
        assert_eq!(reparsed.children[0].header, "return 7");
    }

    #[test]
    fn raw_block_string_does_not_create_declaration_boundary() {
        let source = "/proc/a()\n    var/text = @{\"line\n/proc/not_real()\nend\"}\n/proc/b()\n    return 2\n";
        let audit = audit_source_streaming(source, 256, 5);
        assert_eq!(audit.procedures, 2);
        assert_eq!(audit.skipped_declarations, 0);
    }

    #[test]
    fn column_zero_lines_inside_macro_proc_and_call_do_not_split_chunks() {
        let source = "/datum/globals/var/list/x; /datum/globals/proc/InitX(){x =list(\nNORTHEAST,\nNORTHWEST\n); order += \"x\";}\n/proc/next()\n    return 2\n";
        let mut starts = Vec::new();
        let report = for_each_parsed_chunk(source, 105, |ast, offset| {
            starts.push(offset);
            assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        });
        assert_eq!(report.skipped_declarations, 0, "{report:?}");
        assert_eq!(starts.len(), 2, "{starts:?}");
        assert_eq!(starts[1], source.find("/proc/next()").unwrap());
    }

    #[test]
    fn include_footprint_absolute_declaration_is_chunk_boundary() {
        let source = "/proc/a()\n    return 1\n                                        /var/from_include\n/proc/b()\n    return 2\n";
        let mut boundaries = Vec::new();
        for_each_top_level_boundary(source, |offset| boundaries.push(offset));
        assert!(boundaries.contains(&source.find("/var/from_include").unwrap()));
        let report = for_each_parsed_chunk(source, 100, |_, _| {});
        assert_eq!(report.skipped_declarations, 0);
        assert_eq!(report.parsed_chunks, 2);
    }

    #[test]
    fn dynamic_diagnostics_share_a_bounded_group() {
        let mut audit = StreamingAudit::default();
        for index in 0..300 {
            audit.diagnostic(
                Diagnostic {
                    span: Span::new(0, 1),
                    kind: DiagnosticKind::Expression,
                    message: format!("unexpected token in expression: {index}"),
                },
                0,
                2,
            );
        }
        assert_eq!(audit.diagnostic_count, 300);
        assert_eq!(audit.diagnostics.len(), 2);
        assert_eq!(
            audit.diagnostic_groups["unexpected token in expression:"],
            300
        );
        assert_eq!(audit.diagnostic_examples.len(), 1);
        assert_eq!(
            audit.diagnostic_examples["unexpected token in expression:"]
                .span
                .start,
            0
        );
    }
}
