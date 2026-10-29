use super::*;
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;

struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}

fn facts(source: &'static str) -> Vec<(String, Rule)> {
    let frontend = build(
        Path::new("project.dme"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let mut result = Vec::new();
    for occurrence in frontend.bodies.iter() {
        arena
            .with_parsed(occurrence, |body| {
                for fact in
                    contributions(&frontend, body, frontend.snapshot.tree.as_ref(), &[]).unwrap()
                {
                    result.push((
                        frontend
                            .snapshot
                            .tree
                            .symbols()
                            .text(fact.name)
                            .unwrap()
                            .into(),
                        fact.rule,
                    ));
                }
            })
            .unwrap();
    }
    result
}

#[test]
fn native_parameters_fields_and_new_contribute_but_locals_and_typed_slots_do_not() {
    let result = facts("/datum/example\n    var/untyped\n    var/datum/typed\n    proc/test(datum/arg)\n        untyped = arg\n        typed = arg\n        var/shadow\n        shadow = new /datum\n");
    assert_eq!(result, [("untyped".into(), Rule::Typed)]);
}

#[test]
fn groups_globals_and_static_local_shadowing_preserve_binding() {
    let result = facts("var/saved\n/datum/example\n    var/shadow\n    proc/test()\n        var/static/shadow\n        shadow = new /datum\n        global.saved = (new /datum)\n");
    assert_eq!(result, [("saved".into(), Rule::Typed)]);
}

#[test]
fn scalar_literals_and_lists_are_not_reference_assignments() {
    assert!(facts("/datum/example\n    var/a\n    proc/test()\n        a = 1\n        a = \"value\"\n        a = list()\n").is_empty());
}

#[test]
fn typed_assignment_dominates_unknown_call_without_losing_first_evidence() {
    let result = facts("/datum/example\n    var/a\n    proc/unknown()\n        return null\n    proc/test(datum/arg)\n        a = unknown()\n        a = arg\n");
    assert_eq!(result, [("a".into(), Rule::Typed)]);
}

#[test]
fn call_named_like_a_scalar_builtin_is_not_a_scalar_proof() {
    let result = facts("/datum/example\n    var/a\n    proc/rand()\n        return new /datum\n    proc/test()\n        a = rand()\n");
    assert_eq!(result, [("a".into(), Rule::Call)]);
}

#[test]
fn loop_bindings_preserve_an_existing_parameter_type_like_the_reference() {
    let result = facts("/datum/example\n    var/saved\n    proc/test(datum/value)\n        for(var/value in list())\n            saved = value\n");
    assert_eq!(result, [("saved".into(), Rule::Typed)]);
}

#[test]
fn inherited_default_overrides_do_not_create_another_field_identity() {
    let frontend = build(Path::new("p.dme"), &Source("/datum/base\n    var/saved\n/datum/base/child\n    saved = null\n    proc/test(datum/value)\n        saved = value\n"), &Default::default(), 1).unwrap();
    let bodies = BodyArena::new_typed(&frontend, |_| true);
    bodies
        .with_parsed(&frontend.bodies[0], |body| {
            let facts =
                contributions(&frontend, body, frontend.snapshot.tree.as_ref(), &[]).unwrap();
            assert_eq!(facts.len(), 1);
            assert_eq!(facts[0].owner, SymbolId::of("/datum/base"));
        })
        .unwrap();
}

#[test]
fn archive_scope_borrows_the_same_semantic_owner_and_binding_facts() {
    let frontend = build(Path::new("project.dme"), &Source("/datum/base\n    var/saved\n/datum/base/child\n    saved = null\n    proc/test(datum/value, list/datum/values)\n        var/static/shadow\n        for(var/value in values)\n            saved = value\n"), &Default::default(), 1).unwrap();
    let archive = frontend.body_archive().unwrap();
    let archived = archive.parse(0).unwrap();
    assert!(std::ptr::eq(
        archived.tree(),
        frontend.snapshot.tree.as_ref()
    ));
    let bodies = BodyArena::new_typed(&frontend, |_| true);
    bodies
        .with_parsed(&frontend.bodies[0], |body| {
            let live = scope(&frontend, body, frontend.snapshot.tree.as_ref(), &[]).unwrap();
            let mut retained = archived_scope(&archived, archived.tree(), &[]).unwrap();
            assert!(std::ptr::eq(live.tree, retained.tree));
            assert_eq!(live.owner, retained.owner);
            assert_eq!(live.locals, retained.locals);
            assert_eq!(retained.locals["value"], "/datum");
            assert_eq!(retained.locals["values"], "/list/datum");
            let live_field = live.field(live.owner, "saved").unwrap().unwrap();
            let retained_field = retained.field(retained.owner, "saved").unwrap().unwrap();
            assert_eq!(live_field.0, SymbolId::of("/datum/base"));
            assert_eq!(live_field.0, retained_field.0);
            assert_eq!(
                live_field.1.canonical_bytes(),
                retained_field.1.canonical_bytes()
            );
            dm_syntax::visit_statements(
                &archived.statement_body().parsed().statements,
                &mut retained,
            );
            assert!(retained.error.is_none());
            assert_eq!(
                retained.found.into_values().collect::<Vec<_>>(),
                contributions(&frontend, body, frontend.snapshot.tree.as_ref(), &[]).unwrap()
            );
        })
        .unwrap();
}

#[test]
fn archive_scope_keeps_issued_metadata_without_a_frontend_or_foreign_tree_input() {
    let archive = {
        let frontend = build(Path::new("project.dme"), &Source("/datum/original\n/datum/holder\n    var/saved\n    proc/test(datum/original/value)\n        saved = value\n"), &Default::default(), 1).unwrap();
        frontend.body_archive().unwrap()
    };
    let foreign = build(Path::new("project.dme"), &Source("/datum/foreign\n/datum/holder\n    var/saved\n    proc/test(datum/foreign/value)\n        saved = value\n"), &Default::default(), 2).unwrap();
    let archived = archive.parse(0).unwrap();
    let scope = archived_scope(&archived, archived.tree(), &[]).unwrap();
    assert!(!std::ptr::eq(scope.tree, foreign.snapshot.tree.as_ref()));
    assert_eq!(scope.locals["value"], "/datum/original");
    let (_, field) = scope.field(scope.owner, "saved").unwrap().unwrap();
    assert!(field.declared_type.is_none());
    // The archive entry point accepts no replacement tree or member. It draws
    // parameter spelling/types from the exact issued archive despite matching
    // owner and proc names in another revision.
    assert_eq!(scope.owner, SymbolId::of("/datum/holder"));
}

#[test]
fn live_scope_rejects_a_body_from_an_independent_equal_source_issuance() {
    let source =
        "/datum/example\n    var/saved\n    proc/test(datum/value)\n        saved = value\n";
    let first = build(
        Path::new("project.dme"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap();
    let second = build(
        Path::new("project.dme"),
        &Source(source),
        &Default::default(),
        2,
    )
    .unwrap();
    let bodies = BodyArena::new_typed(&first, |_| true);
    bodies
        .with_parsed(&first.bodies[0], |body| {
            assert!(scope(&second, body, second.snapshot.tree.as_ref(), &[]).is_err());
        })
        .unwrap();
}

#[test]
fn archive_scope_rejects_unrepresented_or_incomplete_body_syntax() {
    for source in [
        "/proc/test()\n    return (\n",
        "/proc/test()\n    for(var/x in list())\n",
    ] {
        let frontend = build(
            Path::new("project.dme"),
            &Source(source),
            &Default::default(),
            1,
        )
        .unwrap();
        let archive = frontend.body_archive().unwrap();
        let body = archive.parse(0).unwrap();
        assert!(archived_scope(&body, body.tree(), &[]).is_err(), "{source}");
    }
}

#[path = "../examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;

fn native_field_frontend(target: &str, identity: u128) -> dm_tree::frontend::ColdFrontend {
    use dm_ir::{DeclaredTypeKnowledge as K, OpaqueFieldBase};
    let mut seed = reference_hierarchy::seed();
    seed.identity = identity;
    // Synthetic test catalog extends the pinned hierarchy under its own identity.
    seed.hierarchy.schema = identity;
    let owner = seed.symbols.intern("/datum/native").unwrap();
    seed.hierarchy
        .parents
        .push((owner, Some(SymbolId::of("/datum"))));
    let target = seed.symbols.intern(target).unwrap();
    let list = seed.symbols.intern("/list").unwrap();
    let fields = [
        ("typed", K::Known(target)),
        ("loose", K::KnownUntyped),
        ("opaque", K::Unsupported),
        ("items", K::Known(list)),
    ];
    let mut bases = Vec::new();
    let mut members = Vec::new();
    for (name, declared_type) in fields {
        let name = seed.symbols.intern(name).unwrap();
        bases.push(OpaqueFieldBase {
            owner,
            name,
            declared_type,
        });
        members.push(dm_tree::IntrinsicMember {
            owner,
            name,
            kind: dm_tree::MemberKind::Var,
            shared_owner: None,
            instance_storage_proven: true,
        });
    }
    seed.fields = bases.into();
    seed.intrinsics = members.into();
    dm_tree::frontend::build_with_config(Path::new("p.dme"),
        &Source("/datum/target\n/datum/other\n/datum/source\n/datum/native/child\n    var/list/datum/source/authored\n    proc/test(datum/source/typed)\n        return typed\n"),
        &Default::default(), dm_tree::frontend::FrontendConfig { workers: 1, engine: Some(&seed), observer: None }).unwrap()
}

#[test]
fn native_declared_type_facts_do_not_require_full_metadata_or_storage() {
    struct TypeOnly<'a>(&'a dm_tree::SemanticTree);
    impl Resolver for TypeOnly<'_> {
        fn resolve(&self, query: Q) -> M {
            if matches!(query, Q::DeclaredVarType { .. }) {
                Resolver::resolve(self.0, query)
            } else {
                M::Unsupported(query)
            }
        }
    }
    let frontend = native_field_frontend("/datum/target", 101);
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let resolver = TypeOnly(&frontend.snapshot.tree);
            let scope = scope(&frontend, body, &resolver, &[]).unwrap();
            assert_eq!(
                scope.field_type(scope.owner, "typed").unwrap().as_deref(),
                Some("/datum/target")
            );
            assert_eq!(
                scope.field_type(scope.owner, "loose").unwrap().as_deref(),
                Some("")
            );
            assert_eq!(
                scope.field_type(scope.owner, "items").unwrap().as_deref(),
                Some("/list")
            );
            assert!(
                scope.field_type(scope.owner, "opaque").is_err(),
                "unknown never means untyped"
            );
            assert!(
                scope.field(scope.owner, "authored").is_err(),
                "reporting still needs full source/storage facts"
            );
        })
        .unwrap();
}

#[test]
fn source_list_precision_and_local_shadowing_survive_native_type_queries() {
    let frontend = native_field_frontend("/datum/target", 102);
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let scope = scope(&frontend, body, frontend.snapshot.tree.as_ref(), &[]).unwrap();
            assert_eq!(
                scope
                    .field_type(scope.owner, "authored")
                    .unwrap()
                    .as_deref(),
                Some("/list/datum/source")
            );
            let parsed = dm_syntax::parse_expression("typed");
            assert!(parsed.diagnostics.is_empty());
            let expression = parsed.expr.unwrap();
            assert_eq!(
                scope.type_of(&expression).unwrap().as_deref(),
                Some("/datum/source")
            );
            let query = Q::Var {
                owner: scope.owner,
                name: SymbolId::of("typed"),
            };
            assert!(
                matches!(Resolver::resolve(scope.resolver, query), M::Unsupported(_)),
                "no fabricated source metadata"
            );
        })
        .unwrap();
}

#[test]
fn native_declared_type_changes_are_bound_to_engine_qualified_semantic_owner() {
    let first = native_field_frontend("/datum/target", 103);
    let second = native_field_frontend("/datum/other", 104);
    assert_ne!(
        first.snapshot.tree.identity(),
        second.snapshot.tree.identity()
    );
    for (frontend, expected) in [(&first, "/datum/target"), (&second, "/datum/other")] {
        let archive = frontend.body_archive().unwrap();
        let body = archive.parse(0).unwrap();
        let scope = archived_scope(&body, archive.tree(), &[]).unwrap();
        assert_eq!(
            scope.field_type(scope.owner, "typed").unwrap().as_deref(),
            Some(expected)
        );
    }
}
