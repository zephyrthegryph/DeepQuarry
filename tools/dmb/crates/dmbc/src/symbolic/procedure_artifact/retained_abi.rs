//! Source-neutral ABI values retained by the existing executable artifact.
use super::*;
#[derive(Clone, Eq, PartialEq)]
pub(in crate::symbolic) struct RetainedAbi {
    pub(super) layout: dm_codegen_byond::procedure_abi::ProcLayout,
    pub(super) argument_sources: Vec<dm_codegen_byond::procedure_abi::ArgumentSource>,
    canonical: Arc<[u8]>,
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn retained_abi_preserves_exact_helper_meaning_without_retaining_tokens() {
        use dm_codegen_byond::procedure_abi::{ArgumentSource, ArgumentSourceHelper};
        let tokens: Arc<[dm_ir::ExpressionToken]> = vec![dm_ir::ExpressionToken {
            kind: dm_syntax::TokenKind::Ident,
            text: SymbolId::of("current_helper_value"),
            relative_span: dm_syntax::Span { start: 0, end: 20 },
        }]
        .into();
        let weak_tokens = Arc::downgrade(&tokens);
        let mut issued = crate::procedure_policy::PreparedAbi {
            layout: Default::default(),
            argument_sources: vec![ArgumentSource::Helper { argument: 0 }],
            source_helpers: vec![ArgumentSourceHelper {
                argument: 0,
                expression: dm_ir::SymbolicExpression { tokens },
                frame_parameters: vec!["value".into()],
            }],
        };
        let exact = issued.canonical_bytes();
        let retained = RetainedAbi::capture(&issued);
        issued.source_helpers[0]
            .frame_parameters
            .push("changed".into());
        assert_ne!(retained.canonical_bytes(), issued.canonical_bytes());
        drop(issued);
        assert!(weak_tokens.upgrade().is_none());
        assert_eq!(retained.canonical_bytes(), exact);
        assert_eq!(
            retained.argument_sources,
            vec![ArgumentSource::Helper { argument: 0 }]
        );
    }
}
impl RetainedAbi {
    pub(super) fn capture(abi: &crate::procedure_policy::PreparedAbi) -> Self {
        Self {
            layout: abi.layout.clone(),
            argument_sources: abi.argument_sources.clone(),
            canonical: abi.canonical_bytes().into(),
        }
    }
    pub(super) fn canonical_bytes(&self) -> Vec<u8> {
        self.canonical.to_vec()
    }
    pub(in crate::symbolic) fn census(
        owner: &Arc<Self>,
        census: &mut crate::heap_census::HeapCensus,
    ) {
        if !census.arc_object("session_symbolic.retained_abi", owner) {
            return;
        }
        let label = "session_symbolic.retained_abi";
        census.slice(label, &owner.canonical, true);
        census.vec_payload(label, &owner.argument_sources);
        if let Some(bytes) = &owner.layout.display_name {
            census.vec_payload(label, bytes);
        }
        if let Some(bytes) = &owner.layout.description {
            census.vec_payload(label, bytes);
        }
        if let dm_codegen_byond::procedure_abi::Category::Text(bytes) = &owner.layout.category {
            census.vec_payload(label, bytes);
        }
    }
}
