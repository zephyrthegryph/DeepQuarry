use super::*;
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver, SymbolId};
use std::{path::Path, sync::Arc};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
struct Host(u128);
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        ResolvedMeaning::Unsupported(query)
    }
    fn domain_version(&self, domain: dm_ir::ReadDomain) -> Option<u128> {
        (domain == dm_ir::ReadDomain::Tree).then_some(self.0)
    }
}
fn capture(
    source: &'static str,
    store: Option<&StartupArtifacts>,
    executor: &dm_exec::BuildExecutor,
) -> (dm_tree::frontend::FrontendRevision, Arc<StartupFacts>) {
    let frontend = dm_tree::frontend::FrontendRevision::new(
        dm_tree::frontend::build(
            Path::new("static.dme"),
            &Source(source),
            &Default::default(),
            1,
        )
        .unwrap(),
    );
    let bodies = dm_tree::frontend::BodyArena::new(&frontend);
    let facts = capture_revision_facts_with_executor_and_bodies_and_artifacts(
        &frontend,
        &[],
        executor,
        &bodies,
        store,
    )
    .unwrap();
    drop(bodies);
    (frontend, facts)
}
#[test]
fn admitted_static_layout_reuses_across_body_changes_and_certifies_exact_absence() {
    let store = StartupArtifacts::default();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let (first, a) = capture(
        "/proc/p()\n    var/static/cache=3\n    return cache\n",
        Some(&store),
        &executor,
    );
    let procedure = a
        .view_revision(&first)
        .unwrap()
        .procedures()
        .next()
        .unwrap()
        .1
        .procedure;
    let query = ResolveQuery::ProcedureStatic {
        procedure,
        name: SymbolId::of("cache"),
    };
    let absent = ResolveQuery::ProcedureStatic {
        procedure,
        name: SymbolId::of("absent"),
    };
    let host_a = Host(1);
    let host_b = Host(2);
    let first_view = a.view_revision(&first).unwrap();
    let first_resolver = first_view.resolver(&first, &host_a).unwrap();
    let token = first_resolver.domain_version(query.domain()).unwrap();
    assert_eq!(first_resolver.domain_version(absent.domain()), Some(token));
    assert_eq!(first_resolver.resolve(absent), ResolvedMeaning::Missing);
    let (second, b) = capture(
        "/proc/p()\n    var/static/cache=3\n    return cache+1\n/proc/q()\n    return 0\n",
        Some(&store),
        &executor,
    );
    let second_view = b.view_revision(&second).unwrap();
    let second_resolver = second_view.resolver(&second, &host_b).unwrap();
    assert_eq!(second_resolver.domain_version(query.domain()), Some(token));
    assert_eq!(
        first_resolver.resolve(query),
        second_resolver.resolve(query)
    );
    let (fresh_front, fresh) = capture(
        "/proc/p()\n    var/static/cache=3\n    return cache+1\n/proc/q()\n    return 0\n",
        None,
        &executor,
    );
    let fresh_view = fresh.view_revision(&fresh_front).unwrap();
    let fresh_resolver = fresh_view.resolver(&fresh_front, &host_b).unwrap();
    assert_eq!(
        second_resolver.resolve(query),
        fresh_resolver.resolve(query)
    );
    assert_eq!(fresh_resolver.domain_version(query.domain()), None);
    let (changed, c) = capture(
        "/proc/p()\n    var/static/cache=4\n    return cache\n",
        Some(&store),
        &executor,
    );
    let changed_view = c.view_revision(&changed).unwrap();
    let changed_resolver = changed_view.resolver(&changed, &host_b).unwrap();
    assert_ne!(changed_resolver.domain_version(query.domain()), Some(token));
    let unknown = ResolveQuery::ProcedureStatic {
        procedure: dm_ir::ProcedureIdentity {
            name: SymbolId::of("uncaptured"),
            ..procedure
        },
        name: SymbolId::of("cache"),
    };
    assert_eq!(changed_resolver.domain_version(unknown.domain()), None);
    assert!(matches!(
        changed_resolver.resolve(unknown),
        ResolvedMeaning::Unsupported(_)
    ));
    assert_eq!(first_resolver.domain_version(query.domain()), Some(token));
    let (empty, empty_facts) = capture("/proc/p()\n    return 0\n", Some(&store), &executor);
    let empty_view = empty_facts.view_revision(&empty).unwrap();
    let empty_resolver = empty_view.resolver(&empty, &host_b).unwrap();
    assert!(empty_resolver.domain_version(query.domain()).is_some());
    assert_ne!(empty_resolver.domain_version(query.domain()), Some(token));
    assert_eq!(empty_resolver.resolve(query), ResolvedMeaning::Missing);
    let (added, added_facts) = capture(
        "/proc/p()\n    var/static/absent=1\n    return absent\n",
        Some(&store),
        &executor,
    );
    let added_view = added_facts.view_revision(&added).unwrap();
    let added_resolver = added_view.resolver(&added, &host_b).unwrap();
    assert_ne!(
        added_resolver.domain_version(absent.domain()),
        empty_resolver.domain_version(absent.domain())
    );
    assert!(matches!(
        added_resolver.resolve(absent),
        ResolvedMeaning::ProcedureStatic(_)
    ));
    assert!(store.retention_census().unique_known_capacity_bytes > 0);
}
