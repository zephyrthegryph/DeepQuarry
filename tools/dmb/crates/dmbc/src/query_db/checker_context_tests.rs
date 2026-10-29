//! Host integration: borrowed checker context keeps primary syntax, source owner
//! and existing scalar answer world. This is not a second query database.
use super::*;
use dm_analysis::{checker_context::CheckerContext, checks::Severity};
use dm_ir::{ResolveQuery as Q, Resolver, SymbolId};
use dm_tree::frontend::{build_with_config, ColdFrontend, FrontendConfig};
#[path = "../../../dm-analysis/examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn build(source: &'static str, db: &Arc<QueryDb>) -> ColdFrontend {
    let seed = reference_hierarchy::seed();
    build_with_config(
        std::path::Path::new("checker-context.dme"),
        &Source(source),
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap()
    .with_body_queries(db.clone())
}
const SOURCE: &str = "/datum/example/proc/probe()\n    return ..()\n";

#[test]
fn original_owner_and_answer_world_survive_checker_queries_and_primary_eviction() {
    let db = Arc::new(QueryDb::default());
    let frontend = build(SOURCE, &db);
    let tree = &frontend.snapshot.tree;
    let identity = tree.identity();
    let world = tree.answer_world();
    let normal = Q::Ancestry(SymbolId::of("/datum/example"));
    let expected = Resolver::resolve(tree.as_ref(), normal);
    let resolve = |query: &Q| Resolver::resolve(tree.as_ref(), *query);
    db.next_request();
    db.begin_answers(tree, world, &resolve);
    db.request_answers(&resolve)
        .current(query_id(&normal), &normal);
    let held = db.answer_counts().2;
    let archive = frontend.body_archive().unwrap();
    assert!(archive.matches_tree(tree));
    let profile = tree.checker_builtin_profile().unwrap();
    let context = CheckerContext::archived(&archive, db.as_ref(), tree.as_ref(), profile).unwrap();
    assert!(std::ptr::eq(context.tree(), tree.as_ref()));
    assert!(std::ptr::eq(context.resolver(), tree.as_ref()));
    let first = archive.parse(0).unwrap();
    let first_rows = context.parent_archived(&first, Severity::Error).unwrap();
    assert_eq!(first_rows.len(), 1);
    assert_eq!(
        first_rows[0].message,
        "proc has no parent: /datum/example/proc/probe"
    );
    db.db.evict_values(&[body_syntax::BODY_SYNTAX]);
    let rebuilt = archive.parse(0).unwrap();
    assert!(!std::ptr::eq(
        first.statement_body(),
        rebuilt.statement_body()
    ));
    let rows = context.parent_archived(&rebuilt, Severity::Error).unwrap();
    assert_eq!(rows[0].message, first_rows[0].message);
    assert_eq!(rows[0].span, first_rows[0].span);
    assert_eq!(tree.identity(), identity);
    assert_eq!(tree.answer_world(), world);
    assert_eq!(Resolver::resolve(tree.as_ref(), normal), expected);
    // Re-enter the SAME native answer world: fixed catalog selection did not
    // invalidate/re-key any common source answer or change the held normal key.
    db.next_request();
    db.begin_answers(tree, world, &resolve);
    db.request_answers(&resolve)
        .current(query_id(&normal), &normal);
    assert_eq!(db.answer_counts().2, held);
    assert!(db.answer_counts().1 >= 1);
}

#[test]
fn equal_bytes_cannot_rebind_foreign_archive_or_compiler_query_graph() {
    let db = Arc::new(QueryDb::default());
    let a = build(SOURCE, &db);
    let b = build(SOURCE, &db);
    let archive = a.body_archive().unwrap();
    let foreign = b.body_archive().unwrap();
    let profile = archive.tree().checker_builtin_profile().unwrap();
    let context = CheckerContext::archived(&archive, db.as_ref(), archive.tree(), profile).unwrap();
    // Equal source/answers do not authenticate a different native owner.
    assert_eq!(a.snapshot.tree.identity(), b.snapshot.tree.identity());
    assert!(
        CheckerContext::archived(&archive, db.as_ref(), b.snapshot.tree.as_ref(), profile)
            .err()
            .unwrap()
            .contains("provenance")
    );
    assert!(CheckerContext::live(&a, b.snapshot.tree.as_ref(), profile)
        .err()
        .unwrap()
        .contains("provenance"));
    let copied_tree = a.snapshot.tree.as_ref().clone();
    assert!(CheckerContext::live(&a, &copied_tree, profile).is_err());
    assert!(context
        .parent_archived(&foreign.parse(0).unwrap(), Severity::Error)
        .unwrap_err()
        .contains("another compiler archive"));
    let other_db = QueryDb::default();
    assert!(CheckerContext::archived(&archive, &other_db, archive.tree(), profile).is_err());
    assert!(CheckerContext::archived(
        &archive,
        db.as_ref(),
        archive.tree(),
        dm_ir::PackedU128::new(profile.get() ^ 1)
    )
    .is_err());
}

#[test]
fn body_edit_retracts_parent_result_without_rebinding_old_archive() {
    let db = Arc::new(QueryDb::default());
    let old = build(SOURCE, &db);
    let new = build("/datum/example/proc/probe()\n    return 1\n", &db);
    let old_archive = old.body_archive().unwrap();
    let new_archive = new.body_archive().unwrap();
    let profile = old_archive.tree().checker_builtin_profile().unwrap();
    let old_context =
        CheckerContext::archived(&old_archive, db.as_ref(), old_archive.tree(), profile).unwrap();
    let new_context =
        CheckerContext::archived(&new_archive, db.as_ref(), new_archive.tree(), profile).unwrap();
    assert_eq!(
        old_context
            .parent_archived(&old_archive.parse(0).unwrap(), Severity::Error)
            .unwrap()
            .len(),
        1
    );
    assert!(new_context
        .parent_archived(&new_archive.parse(0).unwrap(), Severity::Error)
        .unwrap()
        .is_empty());
    assert!(new_context
        .parent_archived(&old_archive.parse(0).unwrap(), Severity::Error)
        .is_err());
}

#[test]
fn transparent_answers_without_compiler_owner_provenance_are_not_authority() {
    struct Unproven<'a>(&'a dm_tree::SemanticTree);
    impl Resolver for Unproven<'_> {
        fn answer_world(&self) -> Option<u128> {
            self.0.answer_world()
        }
        fn resolve(&self, query: Q) -> dm_ir::ResolvedMeaning {
            Resolver::resolve(self.0, query)
        }
    }
    let db = Arc::new(QueryDb::default());
    let frontend = build(SOURCE, &db);
    let archive = frontend.body_archive().unwrap();
    let profile = archive.tree().checker_builtin_profile().unwrap();
    let wrapper = Unproven(archive.tree());
    assert_eq!(wrapper.answer_world(), archive.tree().answer_world());
    assert!(CheckerContext::live(&frontend, &wrapper, profile).is_err());
    assert!(CheckerContext::archived(&archive, db.as_ref(), &wrapper, profile).is_err());
}
