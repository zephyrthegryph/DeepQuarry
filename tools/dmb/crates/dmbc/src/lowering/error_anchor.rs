//! Primary diagnostic cursors use the same current captured lexer issuer as warnings.
use super::*;
use dm_codegen_byond::DiagnosticAnchor;
/// The lossless header can include an inline body. Its parser-issued first
/// statement is the cursor after the control header, not the physical line end.
pub(super) fn parser_current(
    anchor: DiagnosticAnchor,
    statements: Option<&dm_tree::frontend::StatementBody>,
    header: Option<dm_codegen_byond::LowerSpan>,
) -> DiagnosticAnchor {
    let DiagnosticAnchor::LexerCursorAfterOffset(offset) = anchor else {
        return anchor;
    };
    let Some(statements) = statements else {
        return anchor;
    };
    let Some(header) = header else {
        return anchor;
    };
    struct Cursor {
        offset: usize,
        header: dm_codegen_byond::LowerSpan,
        inline: Option<usize>,
    }
    impl dm_syntax::TypedVisitor for Cursor {
        fn statement(
            &mut self,
            node: &dm_syntax::Statement,
            _: &[dm_syntax::NodeStep],
        ) -> dm_syntax::VisitDecision {
            if node.header_span.end == self.offset
                && node.header_span.start == self.header.start
                && node.header_span.end == self.header.end
            {
                if let dm_syntax::StatementKind::For { body, .. } = &node.kind {
                    if let Some(first) = body.first() {
                        let start = first.header_span.start;
                        if start > node.header_span.start && start < node.header_span.end {
                            self.inline = Some(start);
                        }
                    }
                }
            }
            dm_syntax::VisitDecision::Descend
        }
    }
    let mut cursor = Cursor {
        offset,
        header,
        inline: None,
    };
    dm_syntax::visit_statements(&statements.parsed().statements, &mut cursor);
    cursor.inline.map_or(anchor, DiagnosticAnchor::AtOffset)
}
pub(super) fn relative(
    anchor: DiagnosticAnchor,
    body: &BodyOccurrence,
) -> Option<DiagnosticAnchor> {
    let (offset, tag) = match anchor {
        DiagnosticAnchor::AtOffset(n) => (n, 0),
        DiagnosticAnchor::LexerCursorAfterOffset(n) => (n, 1),
        DiagnosticAnchor::UnresolvedCursorAtOffset(n) => (n, 2),
    };
    let offset = offset.checked_sub(body.expanded_span.start)?;
    let length = body
        .expanded_span
        .end
        .checked_sub(body.expanded_span.start)?;
    if offset > length || (tag != 1 && offset == length) || (tag == 1 && offset == 0) {
        return None;
    }
    Some(match tag {
        0 => DiagnosticAnchor::AtOffset(offset),
        1 => DiagnosticAnchor::LexerCursorAfterOffset(offset),
        _ => DiagnosticAnchor::UnresolvedCursorAtOffset(offset),
    })
}
pub(super) fn bind(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    anchor: DiagnosticAnchor,
    stored: bool,
) -> Option<SourceLocation> {
    let (offset, cursor, unknown) = match anchor {
        DiagnosticAnchor::AtOffset(n) => (n, false, false),
        DiagnosticAnchor::LexerCursorAfterOffset(n) => (n, true, false),
        DiagnosticAnchor::UnresolvedCursorAtOffset(n) => (n, false, true),
    };
    let absolute = if stored {
        body.expanded_span.start.checked_add(offset)?
    } else {
        offset
    };
    relative(
        match anchor {
            DiagnosticAnchor::AtOffset(_) => DiagnosticAnchor::AtOffset(absolute),
            DiagnosticAnchor::LexerCursorAfterOffset(_) => {
                DiagnosticAnchor::LexerCursorAfterOffset(absolute)
            }
            DiagnosticAnchor::UnresolvedCursorAtOffset(_) => {
                DiagnosticAnchor::UnresolvedCursorAtOffset(absolute)
            }
        },
        body,
    )?;
    if cursor {
        if let Some(location) = frontend.diagnostic_cursor_location_after(absolute) {
            return Some(location);
        }
    }
    let mut location = frontend.location(if cursor {
        absolute.checked_sub(1)?
    } else {
        absolute
    })?;
    if cursor || unknown {
        location.line = 0;
    }
    Some(location)
}
