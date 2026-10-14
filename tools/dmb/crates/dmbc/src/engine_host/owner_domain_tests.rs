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
                Q::Ancestry(owner) => M::Symbols(vec![owner].into()),
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
    let variable = Q::Var {
        owner,
        name: SymbolId::of("x"),
    };
    assert_eq!(variable.domain(), dm_ir::ReadDomain::OwnerScalar(variable));
    // This fake source issues hierarchy receipts only and has no positive
    // scalar answer; the new family must not borrow hierarchy authority.
    assert_eq!(first.domain_version(variable.domain()), None);
    assert_eq!(first.resolve(variable), M::Unsupported(variable));
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
#[test]
fn variable_owner_certificate_requires_current_source_and_provider_issuer() {
    struct Source(bool);
    impl Resolver for Source {
        fn domain_version(&self, domain: dm_ir::ReadDomain) -> Option<u128> {
            matches!(domain, dm_ir::ReadDomain::OwnerVariable(_)).then_some(9)
        }
        fn resolve(&self, query: Q) -> M {
            if self.0 {
                M::Presence(true)
            } else {
                M::Unsupported(query)
            }
        }
    }
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/").unwrap();
    let name = symbols.intern("value").unwrap();
    let constants =
        ConstantCatalog::new(1, &mut symbols, Vec::new(), Completeness::Complete).unwrap();
    let runtime =
        RuntimeAliasCatalog::new(1, &symbols, Vec::new(), vec![owner], Completeness::Complete)
            .unwrap();
    let query = Q::HasMemberVar { owner, name };
    let mut host =
        EngineResolverHost::new(Arc::new(Source(true)), constants.clone(), runtime.clone());
    struct Authored;
    impl dm_preprocess::SourceProvider for Authored {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/var/value = 1\n".into())
        }
    }
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
        std::path::Path::new("variable-domain.dme"),
        &Authored,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let providers = PinnedEngineProviders::capture(&engine).unwrap();
    let payload = EngineResolverHost::<dm_tree::SemanticTree>::capture_variable_coverage(
        &frontend, &providers, &constants,
    );
    assert!(payload.names.contains(&name));
    // This fixture still isolates wrapper issuer qualification with a synthetic
    // delegated domain, but its source-neutral payload uses the actual producer.
    host.variable_absence = Some(Arc::new(VariableAbsence {
        issuer: Some(11),
        payload,
        identity: 1,
        source: Arc::clone(&frontend.snapshot.tree),
    }));
    assert_eq!(
        host.domain_version(query.domain()),
        Some((9u128 << 64) | 22)
    );
    Arc::make_mut(host.variable_absence.as_mut().unwrap()).issuer = Some(12);
    assert_eq!(
        host.domain_version(query.domain()),
        Some((9u128 << 64) | 24)
    );
    Arc::make_mut(host.variable_absence.as_mut().unwrap()).issuer = None;
    assert_eq!(host.domain_version(query.domain()), None);
    let fallback = EngineResolverHost::new(Arc::new(Source(false)), constants, runtime);
    assert_eq!(fallback.domain_version(query.domain()), None);
    assert_eq!(fallback.resolve(query), M::Unsupported(query));
}
