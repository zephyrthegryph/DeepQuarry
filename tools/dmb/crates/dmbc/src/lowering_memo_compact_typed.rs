//! Typed transport is payload evidence, never a substitute for current issuance.
use dm_ir::{PortableResolvedAnswer, ResolveQuery, ResolvedMeaning, Resolver};
pub(super) fn hydrate(
    query: ResolveQuery,
    typed: Option<&PortableResolvedAnswer>,
    certified: bool,
    provider: &dyn Resolver,
) -> ResolvedMeaning {
    match typed {
        Some(answer) if certified => answer.restore(),
        _ => provider.resolve(query),
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    struct Provider(AtomicUsize);
    impl Resolver for Provider {
        fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
            self.0.fetch_add(1, Ordering::Relaxed);
            ResolvedMeaning::Presence(true)
        }
    }
    #[test]
    fn compact_typed_negative_requires_current_certificate_and_uncovered_answers_hydrate() {
        let provider = Provider(AtomicUsize::new(0));
        let query = ResolveQuery::GlobalProc(dm_ir::SymbolId::of("absent"));
        let typed = PortableResolvedAnswer::Missing;
        assert_eq!(
            hydrate(query, Some(&typed), true, &provider),
            ResolvedMeaning::Missing
        );
        assert_eq!(provider.0.load(Ordering::Relaxed), 0);
        assert_eq!(
            hydrate(query, Some(&typed), false, &provider),
            ResolvedMeaning::Presence(true)
        );
        assert_eq!(
            hydrate(query, None, true, &provider),
            ResolvedMeaning::Presence(true)
        );
        assert_eq!(provider.0.load(Ordering::Relaxed), 2);
    }
}
