//! Primary diagnostic cursors use the same current captured lexer issuer as warnings.
use super::*;
use dm_codegen_byond::DiagnosticAnchor;
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
