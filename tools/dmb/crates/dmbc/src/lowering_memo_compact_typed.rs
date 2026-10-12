//! Typed transport is payload evidence, never a substitute for current issuance.
use dm_ir::{PortableResolvedAnswer, ResolveQuery, ResolvedMeaning, Resolver};
#[cfg(test)]
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

/// Request-attempt byte evidence only. Never serialized or domain authority.
#[derive(Default)]
pub(super) struct VerifiedAnswers {
    rows: Vec<(ResolveQuery, Option<dm_ir::CanonicalResolvedAnswer>)>,
}
impl VerifiedAnswers {
    pub(super) fn preflight(
        typed: &[Option<PortableResolvedAnswer>],
        reads: &[crate::lowering_memo_wire::read_wire::ReadWire<'_>],
    ) -> Result<Self, String> {
        if typed.len() != reads.len() {
            return Err("malformed compact typed answer sidecar".into());
        }
        let mut rows = Vec::with_capacity(reads.len());
        for (typed, read) in typed.iter().zip(reads) {
            let answer = typed
                .as_ref()
                .map(|typed| dm_ir::CanonicalResolvedAnswer::new(typed.restore()));
            if answer
                .as_ref()
                .is_some_and(|answer| answer.canonical() != read.answer.as_ref())
            {
                return Err("malformed compact typed answer sidecar".into());
            }
            rows.push((read.query, answer));
        }
        Ok(Self { rows })
    }
    pub(super) fn hydrate(
        &self,
        index: usize,
        query: ResolveQuery,
        original: &[u8],
        certified: bool,
        provider: &dyn Resolver,
    ) -> dm_ir::CanonicalResolvedAnswer {
        if certified {
            if let Some((issued_query, Some(answer))) = self.rows.get(index) {
                if *issued_query == query && answer.canonical() == original {
                    return answer.clone();
                }
            }
        }
        provider.resolve_with_canonical(query)
    }
}
#[cfg(test)]
mod verified_tests {
    use super::*;
    use crate::lowering_memo_wire::read_wire::ReadWire;
    use std::{
        borrow::Cow,
        sync::atomic::{AtomicUsize, Ordering},
    };
    struct Provider(AtomicUsize);
    impl Resolver for Provider {
        fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
            self.0.fetch_add(1, Ordering::Relaxed);
            ResolvedMeaning::Presence(true)
        }
    }
    #[test]
    fn compact_preflight_pair_reuse_requires_exact_original_and_current_certificate() {
        let provider = Provider(AtomicUsize::new(0));
        let query = ResolveQuery::GlobalProc(dm_ir::SymbolId::of("absent"));
        let read = ReadWire {
            query,
            answer: Cow::Owned(ResolvedMeaning::Missing.canonical_bytes()),
        };
        let typed = [Some(PortableResolvedAnswer::Missing)];
        let verified = VerifiedAnswers::preflight(&typed, std::slice::from_ref(&read)).unwrap();
        let a = verified.hydrate(0, query, &read.answer, true, &provider);
        let b = verified.hydrate(0, query, &read.answer, true, &provider);
        assert_eq!(a.canonical().as_ptr(), b.canonical().as_ptr());
        assert_eq!(provider.0.load(Ordering::Relaxed), 0);
        let _ = verified.hydrate(0, query, &read.answer, false, &provider);
        let _ = VerifiedAnswers::default().hydrate(0, query, &read.answer, true, &provider);
        let _ = verified.hydrate(0, query, b"mutated bytes", true, &provider);
        let other = ResolveQuery::GlobalProc(dm_ir::SymbolId::of("other"));
        let _ = verified.hydrate(0, other, &read.answer, true, &provider);
        assert_eq!(provider.0.load(Ordering::Relaxed), 4);
        assert!(VerifiedAnswers::preflight(
            &[Some(PortableResolvedAnswer::Presence(true))],
            std::slice::from_ref(&read)
        )
        .is_err());
        let reissued = VerifiedAnswers::preflight(&typed, std::slice::from_ref(&read)).unwrap();
        assert_eq!(
            *reissued
                .hydrate(0, query, &read.answer, true, &provider)
                .answer(),
            ResolvedMeaning::Missing
        );
    }
}
