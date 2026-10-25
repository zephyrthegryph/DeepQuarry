//! Typed transport is payload evidence, never a substitute for current issuance.
use dm_ir::{PortableResolvedAnswer, ResolveQuery, Resolver};
#[cfg(test)]
use dm_ir::ResolvedMeaning;
#[cfg(test)]
pub(super) fn hydrate(
    query: ResolveQuery,
    typed: Option<&PortableResolvedAnswer>,
    certified: bool,
    provider: &dyn Resolver,
) -> ResolvedMeaning {
    match typed {
        Some(answer) if certified => answer.restore().unwrap_or_else(|| provider.resolve(query)),
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

/// Whether a typed answer is one `PortableResolvedAnswer::capture` would have produced.
pub(super) fn is_scalar(answer: &PortableResolvedAnswer) -> bool {
    use PortableResolvedAnswer as A;
    !matches!(
        answer,
        A::Symbols(_) | A::Members(_) | A::Member { .. } | A::Declaration { .. }
    )
}

/// Request-attempt byte evidence only. Never serialized or domain authority. A typed answer is
/// restored the first time a certified read asks for it, and only trusted when its canonical
/// bytes equal the stored ones: the compound forms (declaration chains) cost more to restore than
/// a record that is never certified would ever use.
#[derive(Default)]
pub(super) struct VerifiedAnswers {
    rows: Vec<(ResolveQuery, std::sync::OnceLock<Option<dm_ir::CanonicalResolvedAnswer>>)>,
}
impl VerifiedAnswers {
    pub(super) fn preflight(
        typed: &[Option<PortableResolvedAnswer>],
        reads: &[crate::lowering_memo_wire::read_wire::ReadWire<'_>],
    ) -> Result<Self, String> {
        if typed.len() != reads.len() {
            return Err("malformed compact typed answer sidecar".into());
        }
        // Scalar answers are cheap to restore and are checked now, so a record whose sidecar
        // disagrees with its canonical reads never decodes. Compound ones (declaration chains)
        // wait for the first certified read that uses them.
        let mut rows = Vec::with_capacity(reads.len());
        for (typed, read) in typed.iter().zip(reads) {
            let cell = std::sync::OnceLock::new();
            if let Some(typed) = typed.as_ref().filter(|typed| is_scalar(typed)) {
                let answer = typed
                    .restore()
                    .map(dm_ir::CanonicalResolvedAnswer::new)
                    .filter(|answer| answer.canonical() == read.answer.as_ref())
                    .ok_or("malformed compact typed answer sidecar")?;
                let _ = cell.set(Some(answer));
            }
            rows.push((read.query, cell));
        }
        Ok(Self { rows })
    }
    pub(super) fn hydrate(
        &self,
        index: usize,
        query: ResolveQuery,
        original: &[u8],
        certified: bool,
        typed: &[Option<PortableResolvedAnswer>],
        provider: &dyn Resolver,
    ) -> dm_ir::CanonicalResolvedAnswer {
        if certified {
            if let Some((issued_query, cell)) = self.rows.get(index) {
                if *issued_query == query {
                    let answer = cell.get_or_init(|| {
                        let restored = typed.get(index)?.as_ref()?.restore()?;
                        let answer = dm_ir::CanonicalResolvedAnswer::new(restored);
                        (answer.canonical() == original).then_some(answer)
                    });
                    if let Some(answer) = answer.as_ref().filter(|a| a.canonical() == original) {
                        return answer.clone();
                    }
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
        let typed = &typed[..];
        let a = verified.hydrate(0, query, &read.answer, true, typed, &provider);
        let b = verified.hydrate(0, query, &read.answer, true, typed, &provider);
        assert_eq!(a.canonical().as_ptr(), b.canonical().as_ptr());
        assert_eq!(provider.0.load(Ordering::Relaxed), 0);
        let _ = verified.hydrate(0, query, &read.answer, false, typed, &provider);
        let _ = VerifiedAnswers::default().hydrate(0, query, &read.answer, true, typed, &provider);
        let _ = verified.hydrate(0, query, b"mutated bytes", true, typed, &provider);
        let other = ResolveQuery::GlobalProc(dm_ir::SymbolId::of("other"));
        let _ = verified.hydrate(0, other, &read.answer, true, typed, &provider);
        assert_eq!(provider.0.load(Ordering::Relaxed), 4);
        assert!(VerifiedAnswers::preflight(
            &[Some(PortableResolvedAnswer::Presence(true))],
            std::slice::from_ref(&read)
        )
        .is_err());
        // A compound sidecar that disagrees is only found when a certified read asks for it, and
        // then the read resolves instead of trusting it.
        let wrong = [Some(PortableResolvedAnswer::Symbols(vec![dm_ir::SymbolId::of("/x")]))];
        let before = provider.0.load(Ordering::Relaxed);
        let fresh = VerifiedAnswers::preflight(&wrong, std::slice::from_ref(&read)).unwrap();
        let _ = fresh.hydrate(0, query, &read.answer, true, &wrong, &provider);
        assert_eq!(provider.0.load(Ordering::Relaxed), before + 1);
        let reissued = VerifiedAnswers::preflight(typed, std::slice::from_ref(&read)).unwrap();
        assert_eq!(
            *reissued
                .hydrate(0, query, &read.answer, true, typed, &provider)
                .answer(),
            ResolvedMeaning::Missing
        );
    }
}
