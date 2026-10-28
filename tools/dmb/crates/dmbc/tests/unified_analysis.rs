use dm_query::Kind;
use dm_tree::frontend::{BodySyntax, BodySyntaxInput, BodySyntaxQueries, Diagnostic};
use dmbc::query_db::QueryDb;
use std::sync::{Arc, Mutex};
const BODY_SYNTAX: Kind = Kind(4);
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;

struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn frontend(source: &'static str, db: &Arc<QueryDb>) -> dm_tree::frontend::ColdFrontend {
    build(
        Path::new("project.dme"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap()
    .with_body_queries(db.clone())
}

#[test]
fn compiler_and_source_queries_share_one_parse_in_the_existing_graph() {
    let db = Arc::new(QueryDb::default());
    let frontend = frontend("/proc/example(x)\n    return !x & 1\n", &db);
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let archive = frontend.body_archive().unwrap();
    let from_query = archive.parse(0).unwrap();
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            assert!(std::ptr::eq(
                body.statement_body().unwrap(),
                from_query.statement_body()
            ));
        })
        .unwrap();
    let lowered = arena.take_parsed(&frontend.bodies[0]).unwrap();
    assert!(std::ptr::eq(
        lowered.statement_body().unwrap(),
        from_query.statement_body()
    ));
    drop(lowered);
    arena.renew();
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            assert!(std::ptr::eq(
                body.statement_body().unwrap(),
                from_query.statement_body()
            ));
        })
        .unwrap();
    assert_eq!(db.db().stats(BODY_SYNTAX).computed, 1);
    assert_eq!(db.db().len(), 1, "syntax uses the compiler's own query DB");
}

#[test]
fn shifted_or_edited_revision_never_reuses_absolute_spans_or_old_diagnostics() {
    let db = Arc::new(QueryDb::default());
    let old = frontend("/proc/example(x)\n    return !x & 1\n", &db);
    let old_archive = old.body_archive().unwrap();
    let old_body = old_archive.parse(0).unwrap();
    let new = frontend("// moved\n/proc/example(x)\n    return x\n", &db);
    let new_archive = new.body_archive().unwrap();
    let new_body = new_archive.parse(0).unwrap();
    assert!(!std::ptr::eq(
        old_body.statement_body(),
        new_body.statement_body()
    ));
    assert_eq!(
        new_body
            .location(new_body.occurrence().expanded_span.start)
            .unwrap()
            .line,
        2
    );
    assert_eq!(db.db().stats(BODY_SYNTAX).computed, 2);
}

#[test]
fn value_eviction_recomputes_and_dead_revisions_release_graph_metadata() {
    let db = Arc::new(QueryDb::default());
    {
        let old = frontend("/proc/example()\n    return 1\n", &db);
        let archive = old.body_archive().unwrap();
        let first = archive.parse(0).unwrap();
        assert!(db.db().evict_values(&[BODY_SYNTAX]) > 0);
        let second = archive.parse(0).unwrap();
        assert!(!std::ptr::eq(
            first.statement_body(),
            second.statement_body()
        ));
        assert_eq!(db.db().stats(BODY_SYNTAX).computed, 2);
    }
    let new = frontend("/proc/other()\n    return 2\n", &db);
    new.body_archive().unwrap().parse(0).unwrap();
    assert_eq!(
        db.db().len(),
        1,
        "dead parse inputs and metadata must not accumulate"
    );
}

#[test]
fn checker_and_assignment_facts_borrow_the_compilers_retained_syntax() {
    let db = Arc::new(QueryDb::default());
    let frontend = frontend("/datum/example\n    var/saved\n    proc/run(datum/value, x)\n        saved = value\n        return !x & 1\n", &db);
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let view = dm_analysis::checks::BodyView::new(&frontend, body).unwrap();
            assert_eq!(
                view.ambiguous_not_bitwise(dm_analysis::checks::Severity::Warning)
                    .len(),
                1
            );
            let assignments = dm_analysis::untyped::contributions(
                &frontend,
                body,
                frontend.snapshot.tree.as_ref(),
                &[],
            )
            .unwrap();
            assert_eq!(assignments.len(), 1);
            assert_eq!(assignments[0].rule, dm_analysis::untyped::Rule::Typed);
        })
        .unwrap();
    let archive = frontend.body_archive().unwrap();
    let queried = archive.parse(0).unwrap();
    let compiled = arena.take_parsed(&frontend.bodies[0]).unwrap();
    assert!(std::ptr::eq(
        compiled.statement_body().unwrap(),
        queried.statement_body()
    ));
    assert_eq!(db.db().stats(BODY_SYNTAX).computed, 1);
}

#[test]
fn a_host_cannot_rebind_equal_syntax_to_a_foreign_issuance() {
    #[derive(Debug)]
    struct RebindingHost(Mutex<Option<Arc<BodySyntax>>>);
    impl BodySyntaxQueries for RebindingHost {
        fn syntax(&self, input: &Arc<BodySyntaxInput>) -> Result<Arc<BodySyntax>, Diagnostic> {
            let mut first = self.0.lock().unwrap();
            if first.is_none() {
                *first = Some(Arc::new(input.parse()?));
            }
            Ok(first.as_ref().unwrap().clone())
        }
    }
    let host = Arc::new(RebindingHost(Mutex::new(None)));
    let input = Source("/proc/example()\n    return 1\n");
    let first = build(Path::new("project.dme"), &input, &Default::default(), 1)
        .unwrap()
        .with_body_queries(host.clone());
    first.body_archive().unwrap().parse(0).unwrap();
    let foreign = build(Path::new("project.dme"), &input, &Default::default(), 1)
        .unwrap()
        .with_body_queries(host);
    let error = foreign
        .parse_body(&foreign.bodies[0])
        .err()
        .expect("foreign syntax must be rejected");
    assert!(error.message.contains("foreign parser issuance"));
}

#[test]
fn concurrent_readers_execute_the_common_body_query_once() {
    let db = Arc::new(QueryDb::default());
    let frontend = frontend("/proc/example(x)\n    return x + 1\n", &db);
    let archive = frontend.body_archive().unwrap();
    let bodies = std::thread::scope(|scope| {
        let workers = (0..4)
            .map(|_| scope.spawn(|| archive.parse(0).unwrap()))
            .collect::<Vec<_>>();
        workers
            .into_iter()
            .map(|worker| worker.join().unwrap())
            .collect::<Vec<_>>()
    });
    for body in &bodies[1..] {
        assert!(std::ptr::eq(
            bodies[0].statement_body(),
            body.statement_body()
        ));
    }
    assert_eq!(db.db().stats(BODY_SYNTAX).computed, 1);
}

#[test]
fn assignment_analysis_reuses_the_same_memoized_compiler_resolution() {
    use dm_ir::{MemoResolver, ResolveQuery, Resolver, SymbolId};
    let db = Arc::new(QueryDb::default());
    let frontend = frontend(
        "/datum/example\n    var/saved\n    proc/run(datum/value)\n        saved = value\n",
        &db,
    );
    let resolver = MemoResolver::new(frontend.snapshot.tree.as_ref(), 32);
    let query = ResolveQuery::Var {
        owner: SymbolId::of("/datum/example"),
        name: SymbolId::of("saved"),
    };
    let _compiler_answer = resolver.resolve(query);
    assert_eq!(resolver.stats().misses, 1);
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            assert_eq!(
                dm_analysis::untyped::contributions(&frontend, body, &resolver, &[])
                    .unwrap()
                    .len(),
                1
            );
        })
        .unwrap();
    assert_eq!(
        resolver.stats().misses,
        1,
        "analysis must not resolve the same prerequisite again"
    );
    assert!(resolver.stats().hits > 0);
}
