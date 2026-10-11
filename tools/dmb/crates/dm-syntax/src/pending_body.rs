//! Pending loop-body context issued against the complete current lexical input.
//! A procedure envelope alone cannot certify exhaustion of its containing input.
use crate::{ItemKind, NodeStep, Span, Statement, StatementKind, TypedVisitor, VisitDecision};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BodyTermination {
    Unknown,
    ExplicitEmpty,
    FollowingStatement,
    DeclarationBoundary,
    ExhaustedInput,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PendingBody {
    pub header: Span,
    pub termination: BodyTermination,
}
impl PendingBody {
    pub fn missing_body(self) -> bool {
        matches!(
            self.termination,
            BodyTermination::DeclarationBoundary | BodyTermination::ExhaustedInput
        )
    }
}
/// Source must be the complete parser input, with the same absolute byte spans.
/// Receipts are not inferred from the end of a truncated procedure envelope.
pub fn pending_bodies(
    statements: &[Statement],
    source: &str,
    context: &dyn Fn(usize) -> Option<ItemKind>,
) -> Vec<PendingBody> {
    struct Issuer<'a> {
        source: &'a str,
        context: &'a dyn Fn(usize) -> Option<ItemKind>,
        receipts: Vec<PendingBody>,
    }
    impl TypedVisitor for Issuer<'_> {
        fn statement(&mut self, node: &Statement, _: &[NodeStep]) -> VisitDecision {
            if !matches!(&node.kind, StatementKind::For { body, .. } if body.is_empty()) {
                return VisitDecision::Descend;
            }
            if self.source.get(node.header_span.range()) != Some(node.raw_header.as_str()) {
                return VisitDecision::Descend;
            }
            let termination =
                termination_after_with_context(self.source, node.header_span.end, self.context);
            self.receipts.push(PendingBody {
                header: node.header_span,
                termination,
            });
            VisitDecision::Descend
        }
    }
    let mut issuer = Issuer {
        source,
        context,
        receipts: Vec::new(),
    };
    crate::visit_statements(statements, &mut issuer);
    issuer.receipts
}

/// Compatibility callers without a structural issuer cannot certify declarations.
pub fn termination_after(source: &str, offset: usize) -> BodyTermination {
    termination_after_with_context(source, offset, &|_| None)
}
pub fn termination_after_with_context(
    source: &str,
    offset: usize,
    context: &dyn Fn(usize) -> Option<ItemKind>,
) -> BodyTermination {
    match crate::lookahead_after(source, offset) {
        crate::LexerLookahead::Unknown => BodyTermination::Unknown,
        crate::LexerLookahead::End => BodyTermination::ExhaustedInput,
        crate::LexerLookahead::Token(token) if matches!(token.text(source), "{" | ";") => {
            BodyTermination::ExplicitEmpty
        }
        crate::LexerLookahead::Token(token) => {
            if matches!(
                context(token.span.start),
                Some(ItemKind::Proc | ItemKind::Verb | ItemKind::Type)
            ) {
                BodyTermination::DeclarationBoundary
            } else {
                BodyTermination::FollowingStatement
            }
        }
    }
}
impl BodyTermination {
    pub fn canonical_tag(self) -> u8 {
        match self {
            Self::Unknown => 4,
            Self::ExplicitEmpty => 0,
            Self::FollowingStatement => 1,
            Self::DeclarationBoundary => 2,
            Self::ExhaustedInput => 3,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn authenticated_pending_loop_controls_use_full_input_context() {
        for (source, expected) in [
            (include_str!("../../../fixtures/native/loop_local_diagnostics/bodyless_pair_eof.dm"), BodyTermination::ExhaustedInput),
            (include_str!("../../../fixtures/native/loop_local_diagnostics/bodyless_pair_empty_braces.dm"), BodyTermination::ExplicitEmpty),
            (include_str!("../../../fixtures/native/loop_local_diagnostics/bodyless_pair_semicolon.dm"), BodyTermination::ExplicitEmpty),
            (include_str!("../../../fixtures/native/loop_local_diagnostics/bodyless_pair_dedented_return.dm"), BodyTermination::FollowingStatement),
            (include_str!("../../../fixtures/native/loop_local_diagnostics/bodyless_pair_next_proc.dm"), BodyTermination::DeclarationBoundary),
        ] {
            let parsed = crate::parse(source);
            let context = |offset| parsed.items.iter().find(|item| item.header_span.start == offset).map(|item| item.kind);
            let body = crate::parse_body_items_with_context(&parsed.items[0].children, source, &context);
            assert_eq!(body.pending_bodies.len(), 1);
            assert_eq!(body.pending_bodies[0].termination, expected);
            let envelope = crate::parse_proc_at_span(source, parsed.items[0].span).unwrap();
            let body = crate::parse_body_items_with_context(&envelope.children, source, &context);
            assert_eq!(body.pending_bodies[0].termination, expected, "full context survives envelope parse");
        }
        assert_eq!(
            termination_after("\"unterminated", 0),
            BodyTermination::Unknown
        );
        assert_eq!(termination_after("x", 9), BodyTermination::Unknown);
    }
}
