//! Optional request-local reuse beneath dependency-recording consumers.
use crate::{ResolveQuery, ResolvedMeaning, Resolver, SemanticValue};
use std::collections::HashMap;
#[cfg(test)]
use std::sync::Mutex;
use std::sync::{
    atomic::{AtomicU64, AtomicUsize, Ordering},
    RwLock,
};

/// Aggregate request-local observations; concurrent snapshots are approximate.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct MemoStats {
    pub hits: u64,
    /// Calls that reached the original host, including nonretained answers.
    pub misses: u64,
    pub retained_entries: usize,
}

/// Borrows one immutable resolver snapshot for the complete memo lifetime.
/// Place caller read/diagnostic recording outside this wrapper: a hit still
/// answers the caller's exact query and must still be recorded by that caller.
/// Admission failure and poisoned optimization state fall back to the host.
pub struct MemoResolver<'a, R: Resolver + ?Sized> {
    host: &'a R,
    entry_budget: usize,
    hits: AtomicU64,
    misses: AtomicU64,
    retained_entries: AtomicUsize,
    entries: RwLock<HashMap<ResolveQuery, ResolvedMeaning>>,
}
impl<'a, R: Resolver + ?Sized> MemoResolver<'a, R> {
    /// The budget is fixed for this request. At capacity, existing hits remain
    /// available and new queries use ordinary resolution without retention.
    pub fn new(host: &'a R, entry_budget: usize) -> Self {
        Self {
            host,
            entry_budget,
            hits: AtomicU64::new(0),
            misses: AtomicU64::new(0),
            retained_entries: AtomicUsize::new(0),
            entries: RwLock::new(HashMap::new()),
        }
    }
    pub fn stats(&self) -> MemoStats {
        MemoStats {
            hits: self.hits.load(Ordering::Relaxed),
            misses: self.misses.load(Ordering::Relaxed),
            retained_entries: self.retained_entries.load(Ordering::Relaxed),
        }
    }
}
// Bounds cover newly copied sequence descriptors, not shared metadata payloads
// already admitted by the original fixed-answer policy.
const SEQUENCE_BYTES: usize = 4096;
const SEQUENCE_NODES: usize = 64;
const SEQUENCE_DEPTH: usize = 16;
fn retainable(meaning: &ResolvedMeaning) -> bool {
    fn sequence(
        value: &ResolvedMeaning,
        bytes: &mut usize,
        nodes: &mut usize,
        depth: usize,
    ) -> bool {
        if depth > SEQUENCE_DEPTH || *nodes == 0 {
            return false;
        }
        *nodes -= 1;
        match value {
            ResolvedMeaning::Symbols(values) => {
                let Some(charge) = values
                    .len()
                    .checked_mul(std::mem::size_of::<crate::SymbolId>())
                else {
                    return false;
                };
                let Some(left) = bytes.checked_sub(charge) else {
                    return false;
                };
                *bytes = left;
                true
            }
            ResolvedMeaning::Members(values) => {
                let Some(charge) = values
                    .len()
                    .checked_mul(std::mem::size_of::<ResolvedMeaning>())
                else {
                    return false;
                };
                let Some(left) = bytes.checked_sub(charge) else {
                    return false;
                };
                *bytes = left;
                values.iter().all(|v| sequence(v, bytes, nodes, depth + 1))
            }
            _ => fixed_retainable(value),
        }
    }
    let mut bytes = SEQUENCE_BYTES;
    let mut nodes = SEQUENCE_NODES;
    sequence(meaning, &mut bytes, &mut nodes, 0)
}
fn fixed_retainable(meaning: &ResolvedMeaning) -> bool {
    matches!(
        meaning,
        ResolvedMeaning::Missing
            | ResolvedMeaning::Presence(_)
            | ResolvedMeaning::DeclaredType(_)
            | ResolvedMeaning::InstanceField { .. }
            | ResolvedMeaning::Slot { .. }
            | ResolvedMeaning::Symbol(_)
            | ResolvedMeaning::IntrinsicProc { .. }
            | ResolvedMeaning::RetainedProc { .. }
            | ResolvedMeaning::Resource { .. }
            | ResolvedMeaning::Member { .. }
            | ResolvedMeaning::ProcedureStatic(_)
            | ResolvedMeaning::Value(
                SemanticValue::Null
                    | SemanticValue::NumberBits(_)
                    | SemanticValue::Type(_)
                    | SemanticValue::Procedure(_)
                    | SemanticValue::ModifiedInstance(_)
                    | SemanticValue::Resource(_)
            )
    )
}
impl<R: Resolver + ?Sized> Resolver for MemoResolver<'_, R> {
    fn domain_version(&self, domain: crate::ReadDomain) -> Option<u128> {
        self.host.domain_version(domain)
    }
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        if self.entry_budget == 0 {
            self.misses.fetch_add(1, Ordering::Relaxed);
            return self.host.resolve(query);
        }
        if let Ok(entries) = self.entries.read() {
            if let Some(meaning) = entries.get(&query) {
                self.hits.fetch_add(1, Ordering::Relaxed);
                return meaning.clone();
            }
        }
        // Never resolve while holding a cache lock, and never wait on in-flight
        // queries. Concurrent misses may duplicate work; recursion stays free.
        self.misses.fetch_add(1, Ordering::Relaxed);
        let meaning = self.host.resolve(query);
        // Admission is monotonic. Once full, avoid millions of exclusive-lock
        // attempts for uncached queries while preserving all existing hits.
        if self.retained_entries.load(Ordering::Relaxed) < self.entry_budget && retainable(&meaning)
        {
            if let Ok(mut entries) = self.entries.write() {
                if entries.len() < self.entry_budget
                    && !entries.contains_key(&query)
                    && entries.try_reserve(1).is_ok()
                {
                    entries.insert(query, meaning.clone());
                    self.retained_entries.fetch_add(1, Ordering::Relaxed);
                }
            }
        }
        meaning
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{ProcedureIdentity, SymbolId};
    #[test]
    fn memo_forwards_domain_issuer_without_certifying_custom_hosts() {
        struct Issued;
        impl Resolver for Issued {
            fn resolve(&self, q: ResolveQuery) -> ResolvedMeaning {
                ResolvedMeaning::Unsupported(q)
            }
            fn domain_version(&self, d: crate::ReadDomain) -> Option<u128> {
                (d == crate::ReadDomain::Tree).then_some(42)
            }
        }
        let host = Issued;
        let memo = MemoResolver::new(&host, 0);
        assert_eq!(memo.domain_version(crate::ReadDomain::Tree), Some(42));
        assert_eq!(memo.domain_version(crate::ReadDomain::ResourceSearch), None);
        let custom = Host(Mutex::new(Vec::new()));
        assert_eq!(
            MemoResolver::new(&custom, 1).domain_version(crate::ReadDomain::Tree),
            None
        );
    }
    #[test]
    fn shared_override_sequence_survives_memo_hits_without_backing_copies() {
        struct Host(AtomicUsize);
        impl Resolver for Host {
            fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
                self.0.fetch_add(1, Ordering::Relaxed);
                ResolvedMeaning::Members(
                    vec![ResolvedMeaning::Symbol(SymbolId::of("/datum"))].into(),
                )
            }
        }
        let host = Host(AtomicUsize::new(0));
        let memo = MemoResolver::new(&host, 1);
        let query = ResolveQuery::OverrideChain {
            owner: SymbolId::of("/datum"),
            name: SymbolId::of("read"),
            verb: false,
        };
        let ResolvedMeaning::Members(first) = memo.resolve(query) else {
            panic!()
        };
        let ResolvedMeaning::Members(second) = memo.resolve(query) else {
            panic!()
        };
        assert!(std::sync::Arc::ptr_eq(&first, &second));
        assert_eq!(host.0.load(Ordering::Relaxed), 1);
        drop(memo);
        assert_eq!(first, second);
    }
    struct Host(Mutex<Vec<ResolveQuery>>);
    #[test]
    fn bounded_sequence_answers_reuse_exact_meanings_and_decline_oversized_payloads() {
        struct Answer(ResolvedMeaning, AtomicUsize);
        impl Resolver for Answer {
            fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
                self.1.fetch_add(1, Ordering::Relaxed);
                self.0.clone()
            }
        }
        let id = SymbolId::of("/probe");
        let retained = ResolvedMeaning::RetainedProc {
            declaring_owner: id,
            name: SymbolId::of("work"),
            verb: true,
            engine_identity: 123,
            wire_proc: 9,
        };
        let mut deep = ResolvedMeaning::Missing;
        for _ in 0..=SEQUENCE_DEPTH {
            deep = ResolvedMeaning::Members(vec![deep].into());
        }
        for (answer, admitted) in [
            (ResolvedMeaning::Symbols(vec![id; 4].into()), true),
            (retained.clone(), true),
            (
                ResolvedMeaning::Members(
                    vec![ResolvedMeaning::Symbols(vec![id].into()), retained].into(),
                ),
                true,
            ),
            (
                ResolvedMeaning::Symbols(
                    vec![id; SEQUENCE_BYTES / std::mem::size_of::<SymbolId>() + 1].into(),
                ),
                false,
            ),
            (
                ResolvedMeaning::Members(vec![ResolvedMeaning::Missing; SEQUENCE_NODES].into()),
                false,
            ),
            (deep, false),
            (
                ResolvedMeaning::Members(
                    vec![ResolvedMeaning::Value(SemanticValue::Text(
                        std::sync::Arc::from(&b"opaque"[..]),
                    ))]
                    .into(),
                ),
                false,
            ),
        ] {
            let host = Answer(answer.clone(), AtomicUsize::new(0));
            let memo = MemoResolver::new(&host, 8);
            let query = ResolveQuery::Ancestry(id);
            // Outer consumers still receive/record every exact query answer.
            let observations: Vec<_> = (0..2).map(|_| (query, memo.resolve(query))).collect();
            assert_eq!(observations, vec![(query, answer.clone()), (query, answer)]);
            assert_eq!(host.1.load(Ordering::Relaxed), if admitted { 1 } else { 2 });
            assert_eq!(memo.stats().retained_entries, usize::from(admitted));
        }
    }
    impl Resolver for Host {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            self.0.lock().unwrap().push(query);
            match query {
                ResolveQuery::ResourceIn {
                    path,
                    search_context,
                } => ResolvedMeaning::Resource {
                    path,
                    content: search_context,
                },
                ResolveQuery::Proc { owner, .. } => ResolvedMeaning::Symbol(owner),
                ResolveQuery::ProcedureStatic { procedure, .. } => {
                    ResolvedMeaning::Symbol(procedure.name)
                }
                ResolveQuery::Type(id) => ResolvedMeaning::Symbol(id),
                ResolveQuery::Parent(_) => ResolvedMeaning::Missing,
                ResolveQuery::Ancestry(id) => ResolvedMeaning::Symbols(vec![id].into()),
                ResolveQuery::PredefinedConstant(_) => {
                    ResolvedMeaning::Value(SemanticValue::Text(std::sync::Arc::from(&b"text"[..])))
                }
                _ => ResolvedMeaning::Unsupported(query),
            }
        }
    }
    #[test]
    fn memo_preserves_exact_queries_and_outer_dependency_reads() {
        let host = Host(Mutex::new(Vec::new()));
        let memo = MemoResolver::new(&host, 16);
        let owner = SymbolId::of("/datum/a");
        let other = SymbolId::of("/datum/b");
        let name = SymbolId::of("work");
        let queries = [
            ResolveQuery::ResourceIn {
                path: name,
                search_context: 1,
            },
            ResolveQuery::ResourceIn {
                path: name,
                search_context: 2,
            },
            ResolveQuery::Proc {
                owner,
                name,
                verb: false,
            },
            ResolveQuery::Proc {
                owner: other,
                name,
                verb: false,
            },
            ResolveQuery::Proc {
                owner,
                name,
                verb: true,
            },
            ResolveQuery::ProcedureStatic {
                procedure: ProcedureIdentity {
                    owner,
                    name,
                    verb: false,
                    occurrence: 0,
                },
                name,
            },
            ResolveQuery::ProcedureStatic {
                procedure: ProcedureIdentity {
                    owner,
                    name,
                    verb: false,
                    occurrence: 1,
                },
                name,
            },
            ResolveQuery::Parent(owner),
        ];
        let mut reads = Vec::new();
        for _ in 0..2 {
            for query in queries {
                // Consumer recording occurs on every call, including memo hits.
                let answer = memo.resolve(query);
                reads.push((query, answer));
            }
        }
        assert_eq!(&reads[..queries.len()], &reads[queries.len()..]);
        assert_eq!(*host.0.lock().unwrap(), queries);
        assert_eq!(memo.entries.read().unwrap().len(), queries.len());
        assert_eq!(
            memo.stats(),
            MemoStats {
                hits: queries.len() as u64,
                misses: queries.len() as u64,
                retained_entries: queries.len()
            }
        );
    }
    #[test]
    fn memo_budget_and_nonretained_answers_use_original_host() {
        let host = Host(Mutex::new(Vec::new()));
        let memo = MemoResolver::new(&host, 1);
        let first = ResolveQuery::Type(SymbolId::of("/datum"));
        let second = ResolveQuery::Type(SymbolId::of("/obj"));
        assert_eq!(memo.resolve(first), memo.resolve(first));
        for query in [
            second,
            ResolveQuery::Signature(SymbolId::of("unknown")),
            ResolveQuery::Ancestry(SymbolId::of("/datum")),
            ResolveQuery::PredefinedConstant(SymbolId::of("text")),
        ] {
            assert_eq!(memo.resolve(query), memo.resolve(query));
        }
        assert_eq!(memo.entries.read().unwrap().len(), 1);
        assert_eq!(host.0.lock().unwrap().len(), 9);
        let disabled = MemoResolver::new(&host, 0);
        disabled.resolve(first);
        disabled.resolve(first);
        assert!(disabled.entries.read().unwrap().is_empty());
    }
    #[test]
    fn memo_excluded_answers_are_not_retained_with_room_available() {
        let host = Host(Mutex::new(Vec::new()));
        let memo = MemoResolver::new(&host, 16);
        let name = SymbolId::of("name");
        for query in [
            ResolveQuery::Signature(name),
            ResolveQuery::PredefinedConstant(name),
        ] {
            assert_eq!(memo.resolve(query), memo.resolve(query));
        }
        assert_eq!(
            memo.stats(),
            MemoStats {
                hits: 0,
                misses: 4,
                retained_entries: 0
            }
        );
        assert!(memo.entries.read().unwrap().is_empty());
    }

    #[test]
    fn memo_concurrent_misses_and_hits_complete_without_inflight_waits() {
        let host = Host(Mutex::new(Vec::new()));
        let memo = MemoResolver::new(&host, 4);
        let query = ResolveQuery::Type(SymbolId::of("/datum"));
        std::thread::scope(|scope| {
            let handles = (0..8)
                .map(|_| {
                    scope.spawn(|| {
                        for _ in 0..100 {
                            assert_eq!(
                                memo.resolve(query),
                                ResolvedMeaning::Symbol(SymbolId::of("/datum"))
                            );
                        }
                    })
                })
                .collect::<Vec<_>>();
            for handle in handles {
                handle.join().unwrap();
            }
        });
        assert_eq!(memo.entries.read().unwrap().len(), 1);
        assert!((1..=8).contains(&host.0.lock().unwrap().len()));
    }
}
