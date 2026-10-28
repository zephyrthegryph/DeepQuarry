use dm_query::Kind;
use dm_tree::frontend::{BodySyntax, BodySyntaxInput, BodySyntaxQueries, Diagnostic};
use dmbc::query_db::QueryDb;
use std::sync::{Arc, Mutex};
const BODY_SYNTAX: Kind = Kind(4);
use dm_tree::frontend::BodyArena;
#[path = "../../dm-analysis/examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
fn build<P: dm_preprocess::SourceProvider>(
    project: &std::path::Path,
    provider: &P,
    defines: &std::collections::BTreeMap<String, String>,
    workers: usize,
) -> Result<dm_tree::frontend::ColdFrontend, Vec<dm_tree::frontend::Diagnostic>> {
    dm_tree::frontend::build_with_config(
        project,
        provider,
        defines,
        dm_tree::frontend::FrontendConfig {
            workers,
            engine: Some(&reference_hierarchy::seed()),
            observer: None,
        },
    )
}

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
    let _compiler_storage = resolver.resolve(ResolveQuery::VarStorage {
        owner: SymbolId::of("/datum/example"),
        name: SymbolId::of("saved"),
    });
    assert_eq!(resolver.stats().misses, 2);
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
        2,
        "analysis must not resolve the same prerequisite again"
    );
    assert!(resolver.stats().hits > 0);
}

#[test]
fn whole_program_policy_checker_and_compiler_demand_share_issued_bodies() {
    use dm_analysis::{
        checks::{BodyView, Severity},
        untyped_native,
        value_program::Values,
        value_schemas::Schemas,
    };
    use dm_ir::{MemoResolver, ResolveQuery, Resolver, SymbolId};
    let db = Arc::new(QueryDb::default());
    let frontend = frontend("/datum/example\n    var/safe\n    var/unsafe\n    proc/scalar()\n        return 3\n    proc/entity()\n        return new /datum\n    proc/apply()\n        safe = scalar()\n        unsafe = entity()\n    proc/render(a, b)\n        return \"[!a & b]\"\n", &db);
    let resolver = MemoResolver::new(frontend.snapshot.tree.as_ref(), 1024);
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let archive = frontend.body_archive().unwrap();
    // Compilation and source tooling first demand each authored executable body.
    let issued: Vec<_> = (0..archive.len())
        .map(|i| archive.parse(i).unwrap())
        .collect();
    let count = frontend.bodies.len() as u64;
    assert_eq!(db.db().stats(BODY_SYNTAX).computed, count);
    for name in ["safe", "unsafe"] {
        let _ = resolver.resolve(ResolveQuery::Var {
            owner: SymbolId::of("/datum/example"),
            name: SymbolId::of(name),
        });
        let _ = resolver.resolve(ResolveQuery::VarStorage {
            owner: SymbolId::of("/datum/example"),
            name: SymbolId::of(name),
        });
    }
    let values = Values::build(&frontend, &arena, &resolver, &[]).unwrap();
    let mut findings = Vec::new();
    let mut diagnostics = Vec::new();
    for (ordinal, occurrence) in frontend.bodies.iter().enumerate() {
        arena
            .with_parsed(occurrence, |body| {
                assert!(std::ptr::eq(
                    body.statement_body().unwrap(),
                    issued[ordinal].statement_body()
                ));
                findings.extend(
                    untyped_native::body_evidence(
                        &frontend,
                        body,
                        &values,
                        &Schemas::default(),
                        &[],
                    )
                    .unwrap(),
                );
                diagnostics.extend(
                    BodyView::new(&frontend, body)
                        .unwrap()
                        .ambiguous_not_bitwise(Severity::Warning),
                );
            })
            .unwrap();
    }
    assert_eq!(findings.len(), 1);
    assert_eq!(findings[0].name, SymbolId::of("unsafe"));
    assert_eq!(findings[0].rule, untyped_native::Rule::Call);
    assert_eq!(diagnostics.len(), 1);
    assert_eq!(
        db.db().stats(BODY_SYNTAX).computed,
        count,
        "no policy may reparse the shared executable syntax"
    );
    let before = resolver.stats();
    let _ = resolver.resolve(ResolveQuery::Var {
        owner: SymbolId::of("/datum/example"),
        name: SymbolId::of("unsafe"),
    });
    assert_eq!(resolver.stats().misses, before.misses);
    assert!(resolver.stats().hits > before.hits);
}

#[test]
fn value_proof_query_reuses_equations_and_records_real_syntax_edges() {
    use dm_analysis::value_program::{Key, Values};
    use dm_analysis::value_query::ArchiveValueInput;
    use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver, SymbolId};
    let db = Arc::new(QueryDb::default());
    let frontend = frontend("/datum/probe\n    var/saved\n    proc/read()\n        return 4\n    proc/use()\n        saved = read()\n", &db);
    let input = ArchiveValueInput::new(frontend.body_archive().unwrap(), &[]);
    let first = input.obtain(db.as_ref()).unwrap();
    let again = input.obtain(db.as_ref()).unwrap();
    assert!(Arc::ptr_eq(&first, &again));
    assert_eq!(db.db().stats(Kind(5)).computed, 1);
    assert_eq!(db.db().stats(BODY_SYNTAX).computed, 2);
    for syntax in input.archive().syntax_inputs().unwrap() {
        assert!(db
            .db()
            .dependants(&[dm_query::Key::new(BODY_SYNTAX, syntax.key().into())])
            .contains(&dm_query::Key::new(Kind(5), input.key().into())));
    }
    let values = Values::from_archive_input(&input, first.clone()).unwrap();
    let ResolvedMeaning::Members(rows) = Resolver::resolve(
        frontend.snapshot.tree.as_ref(),
        ResolveQuery::SourceDeclarationChain {
            owner: SymbolId::of("/datum/probe"),
            name: SymbolId::of("read"),
            verb: false,
        },
    ) else {
        panic!("selected source chain");
    };
    let ResolvedMeaning::Declaration { identity, .. } = &rows[0] else {
        panic!("selected declaration");
    };
    assert!(values.is_value(&Key::Return(*identity)));
    assert!(db.db().evict_values(&[Kind(5)]) > 0);
    let recomputed = input.obtain(db.as_ref()).unwrap();
    assert!(!Arc::ptr_eq(&first, &recomputed));
    assert_eq!(db.db().stats(Kind(5)).computed, 2);
    assert_eq!(
        db.db().stats(BODY_SYNTAX).computed,
        2,
        "proof eviction does not reparse issued bodies"
    );
}

#[test]
fn value_proof_query_rejects_a_second_graph_and_collects_dead_issuances() {
    use dm_analysis::value_query::ArchiveValueInput;
    let db = Arc::new(QueryDb::default());
    let foreign = QueryDb::default();
    {
        let frontend = frontend("/proc/read()\n    return 1\n", &db);
        let input = ArchiveValueInput::new(frontend.body_archive().unwrap(), &[]);
        assert!(input.obtain(&foreign).is_err());
        input.obtain(db.as_ref()).unwrap();
        assert_eq!(db.db().len(), 2);
    }
    // Issuing the next compiler revision prunes both expired parser inputs and
    // derived proof metadata. The proof's private evidence retains them weakly.
    let next = frontend("/proc/other()\n    return 2\n", &db);
    assert_eq!(db.db().len(), 0);
    next.body_archive().unwrap().parse(0).unwrap();
    assert_eq!(db.db().len(), 1);
}

#[test]
fn value_proof_query_retracts_body_only_edits_without_rebinding_old_results() {
    use dm_analysis::{
        value_program::{Key, Values},
        value_query::ArchiveValueInput,
    };
    use dm_ir::ProcedureIdentity;
    let db = Arc::new(QueryDb::default());
    let old = frontend("/proc/read()\n    return 4\n", &db);
    let old_input = ArchiveValueInput::new(old.body_archive().unwrap(), &[]);
    let old_proof = old_input.obtain(db.as_ref()).unwrap();
    let old_values = Values::from_archive_input(&old_input, old_proof.clone()).unwrap();
    let id: ProcedureIdentity = old_input.archive().callables().identity(0).unwrap();
    assert!(old_values.is_value(&Key::Return(id)));
    let edited = frontend("/proc/read()\n    return new /datum\n", &db);
    assert_eq!(
        old.snapshot.tree.identity(),
        edited.snapshot.tree.identity(),
        "executable edit is not a declaration change"
    );
    let input = ArchiveValueInput::new(edited.body_archive().unwrap(), &[]);
    let proof = input.obtain(db.as_ref()).unwrap();
    let values = Values::from_archive_input(&input, proof).unwrap();
    assert!(!values.is_value(&Key::Return(id)));
    assert!(
        old_values.is_value(&Key::Return(id)),
        "old pinned result remains internally consistent"
    );
    assert!(Arc::ptr_eq(
        &old_proof,
        &old_input.obtain(db.as_ref()).unwrap()
    ));
    assert_eq!(db.db().stats(Kind(5)).computed, 2);
    assert_eq!(db.db().stats(BODY_SYNTAX).computed, 2);
}
