use super::*;

#[test]
fn engine_wrapper_hierarchy_domain_tracks_current_delegated_source_only() {
    struct Source(u128);
    impl Resolver for Source {
        fn domain_version(&self, domain: dm_ir::ReadDomain) -> Option<u128> {
            matches!(domain, dm_ir::ReadDomain::OwnerHierarchy(_)).then_some(self.0)
        }
        fn resolve(&self, query: Q) -> M {
            match query {
                Q::Type(owner) => M::Symbol(owner),
                Q::Ancestry(owner) => M::Symbols(vec![owner]),
                Q::Parent(_) => M::Missing,
                _ => M::Unsupported(query),
            }
        }
    }
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/datum/probe").unwrap();
    let constants =
        ConstantCatalog::new(1, &mut symbols, Vec::new(), Completeness::Complete).unwrap();
    let runtime =
        RuntimeAliasCatalog::new(1, &symbols, Vec::new(), vec![owner], Completeness::Complete)
            .unwrap();
    let first = EngineResolverHost::new(Arc::new(Source(11)), constants.clone(), runtime.clone());
    let changed = EngineResolverHost::new(Arc::new(Source(12)), constants, runtime);
    let domain = dm_ir::ReadDomain::OwnerHierarchy(owner);
    assert_eq!(first.domain_version(domain), Some(11));
    assert_eq!(changed.domain_version(domain), Some(12));
    for query in [Q::Type(owner), Q::Parent(owner), Q::Ancestry(owner)] {
        assert_eq!(first.resolve(query), Source(11).resolve(query));
    }
    assert_eq!(
        Q::Var {
            owner,
            name: SymbolId::of("x")
        }
        .domain(),
        dm_ir::ReadDomain::Tree
    );
}

#[test]
fn callable_owner_certificate_declines_engine_fallback_and_qualifies_provider() {
    struct Source(bool);
    impl Resolver for Source {
        fn domain_version(&self, domain: dm_ir::ReadDomain) -> Option<u128> {
            matches!(domain, dm_ir::ReadDomain::OwnerCallable(_)).then_some(7)
        }
        fn resolve(&self, query: Q) -> M {
            if self.0 {
                M::Symbol(SymbolId::of("positive"))
            } else {
                M::Unsupported(query)
            }
        }
    }
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/datum/probe").unwrap();
    let name = symbols.intern("callback").unwrap();
    let constants =
        ConstantCatalog::new(1, &mut symbols, Vec::new(), Completeness::Complete).unwrap();
    let runtime =
        RuntimeAliasCatalog::new(1, &symbols, Vec::new(), vec![owner], Completeness::Complete)
            .unwrap();
    let query = Q::Proc {
        owner,
        name,
        verb: false,
    };
    let domain = query.domain();
    let mut positive =
        EngineResolverHost::new(Arc::new(Source(true)), constants.clone(), runtime.clone());
    positive.callable_absence = Some(Arc::new(HashSet::from([name])));
    positive.callable_issuer = Some(11);
    assert_eq!(positive.domain_version(domain), Some((7u128 << 64) | 11));
    positive.callable_issuer = Some(12);
    assert_eq!(positive.domain_version(domain), Some((7u128 << 64) | 12));
    positive.callable_issuer = None;
    assert_eq!(positive.domain_version(domain), None);
    let mut fallback = EngineResolverHost::new(Arc::new(Source(false)), constants, runtime);
    fallback.callable_absence = Some(Arc::new(HashSet::from([name])));
    fallback.callable_issuer = Some(11);
    assert_eq!(fallback.resolve(query), M::Missing);
    assert_eq!(fallback.domain_version(domain), None);
}
