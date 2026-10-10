//! Immutable catalogue issuers; source fallback retains its own exact receipt.
use super::*;
use dm_ir::ReadDomain;
use std::sync::atomic::{AtomicU64, Ordering};
pub(super) fn issue() -> Option<u64> {
    static NEXT: AtomicU64 = AtomicU64::new(1);
    NEXT.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |value| {
        value.checked_add(1)
    })
    .ok()
}
impl<R: Resolver> EngineResolverHost<R> {
    // Outer Option distinguishes an unrelated domain from an uncertified answer.
    pub(super) fn catalog_domain(&self, domain: ReadDomain) -> Option<Option<u128>> {
        match domain {
            ReadDomain::PredefinedCatalog(name) => Some(
                (self.constants.values.contains_key(&name)
                    || self.constants.completeness == Completeness::Complete)
                    .then_some(self.constants.issuer)
                    .flatten()
                    .map(u128::from),
            ),
            ReadDomain::RuntimeCatalog(path) => Some((|| {
                let issuer = self.runtime.issuer?;
                if self.runtime.aliases.contains_key(&path) || self.runtime.ordinary.contains(&path)
                {
                    return Some(u128::from(issuer) << 64);
                }
                if self.runtime.completeness == Completeness::Partial {
                    return None;
                }
                if !matches!(self.tree.resolve(Q::Type(path)), M::Symbol(_) | M::Missing) {
                    return None;
                }
                let source =
                    u64::try_from(self.tree.domain_version(ReadDomain::OwnerHierarchy(path))?)
                        .ok()?;
                Some((u128::from(issuer) << 64) | u128::from(source))
            })()),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Source {
        token: u128,
        answer: M,
    }
    impl Resolver for Source {
        fn resolve(&self, query: Q) -> M {
            if matches!(query, Q::Type(_)) {
                self.answer.clone()
            } else {
                M::Unsupported(query)
            }
        }
        fn domain_version(&self, domain: ReadDomain) -> Option<u128> {
            matches!(domain, ReadDomain::OwnerHierarchy(_)).then_some(self.token)
        }
    }
    #[test]
    fn catalog_receipts_preserve_exact_branches_and_partial_absence() {
        let mut symbols = SymbolTable::default();
        let path = symbols.intern("/datum/probe").unwrap();
        let alias = symbols.intern("/datum/alias").unwrap();
        let value = SemanticValue::NumberBits(1f32.to_bits());
        let constants = ConstantCatalog::new(
            1,
            &mut symbols,
            vec![("TEST".into(), value)],
            Completeness::Partial,
        )
        .unwrap();
        let runtime = RuntimeAliasCatalog::new(
            1,
            &symbols,
            vec![(alias, path)],
            vec![path],
            Completeness::Complete,
        )
        .unwrap();
        let host = |token| {
            EngineResolverHost::new(
                Arc::new(Source {
                    token,
                    answer: M::Symbol(path),
                }),
                constants.clone(),
                runtime.clone(),
            )
        };
        let first = host(1);
        let changed = host(2);
        let predefined = Q::PredefinedConstant(SymbolId::of("TEST"));
        assert!(first.domain_version(predefined.domain()).is_some());
        assert_eq!(
            first.domain_version(predefined.domain()),
            changed.domain_version(predefined.domain())
        );
        let missing = Q::PredefinedConstant(SymbolId::of("UNKNOWN"));
        assert_eq!(first.domain_version(missing.domain()), None);
        assert_eq!(first.resolve(missing), M::Unsupported(missing));
        for selected in [path, alias] {
            let query = Q::RuntimeType(selected);
            assert_eq!(
                first.domain_version(query.domain()),
                changed.domain_version(query.domain())
            );
        }
        let fallback = Q::RuntimeType(SymbolId::of("/datum/fallback"));
        assert_ne!(
            first.domain_version(fallback.domain()),
            changed.domain_version(fallback.domain())
        );
        let partial =
            RuntimeAliasCatalog::new(1, &symbols, vec![], vec![], Completeness::Partial).unwrap();
        let incomplete = EngineResolverHost::new(
            Arc::new(Source {
                token: 1,
                answer: M::Symbol(path),
            }),
            constants,
            partial,
        );
        assert_eq!(incomplete.domain_version(fallback.domain()), None);
        assert_eq!(incomplete.resolve(fallback), M::Unsupported(fallback));
    }
}
