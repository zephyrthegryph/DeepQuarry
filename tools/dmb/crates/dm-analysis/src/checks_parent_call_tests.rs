use super::*;
use dm_ir::SymbolId;
use dm_tree::{
    frontend::{build_with_config, BodyArena, FrontendConfig},
    EngineHierarchy, IntrinsicMember,
};
use std::path::Path;
struct Source(String);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}
fn frontend(source: &str) -> ColdFrontend {
    // Both issued owner and semantic host must carry the same certified
    // hierarchy. Attaching a certificate only to the host is not equivalent
    // to the old unseeded frontend's explicit Unsupported ancestry answer.
    let seed = reference_hierarchy::seed();
    build_with_config(
        Path::new("parents.dme"),
        &Source(source.into()),
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap()
}
fn hierarchy(tree: &SemanticTree) -> EngineHierarchy {
    EngineHierarchy {
        schema: 313,
        parents: tree
            .types()
            .iter()
            .map(|t| (t.path, t.parent.map(|p| tree.type_node(p).unwrap().path)))
            .collect(),
    }
}
// A deliberately synthetic complete engine is appropriate to unit-test negative
// contract admission. It is never used as a real BYOND oracle inventory.
fn synthetic_engine(
    frontend: &ColdFrontend,
    complete: bool,
    entries: Vec<IntrinsicMember>,
) -> SemanticTree {
    let tree = frontend.snapshot.tree.as_ref().clone();
    let hierarchy = hierarchy(&tree);
    if complete {
        tree.with_complete_intrinsics(hierarchy, entries).unwrap()
    } else {
        tree.with_engine_intrinsics(hierarchy, entries).unwrap()
    }
}
fn rows(source: &str, complete: bool) -> Result<Vec<(usize, String)>, String> {
    let frontend = frontend(source);
    let resolver = synthetic_engine(&frontend, complete, Vec::new());
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let mut out = Vec::new();
    for (_, occurrence) in crate::checker_order::bodies(&frontend)? {
        arena
            .with_parsed(occurrence, |body| {
                for row in check(&frontend, body, &resolver, Severity::Error)? {
                    out.push((frontend.location(row.span.start).unwrap().line, row.message));
                }
                Ok::<_, String>(())
            })
            .map_err(|e| e.message)??;
    }
    Ok(out)
}
#[test]
fn current_source_chain_and_occurrence_are_authoritative() {
    let source="/datum/example/proc/probe()\n    return ..()\n/datum/example/probe()\n    return ..()\n/datum/example/child/probe()\n    return ..()\n";
    assert_eq!(
        rows(source, true).unwrap(),
        [(
            2,
            "proc has no parent: /datum/example/proc/probe[0/2]".into()
        )]
    );
}
#[test]
fn source_parent_positive_does_not_need_complete_engine_inventory() {
    let source="/datum/example/proc/probe()\n    return 1\n/datum/example/child/probe()\n    return ..()\n";
    assert!(rows(source, false).unwrap().is_empty());
}
#[test]
fn negative_requires_complete_intrinsic_inventory() {
    let source = "/datum/example/proc/probe()\n    return ..()\n";
    assert!(rows(source, false)
        .unwrap_err()
        .contains("complete intrinsic inventory"));
    assert_eq!(rows(source, true).unwrap().len(), 1);
}
#[test]
fn authored_shadow_does_not_hide_engine_parent() {
    let frontend = frontend("/datum/example/proc/probe()\n    return ..()\n");
    let resolver = synthetic_engine(
        &frontend,
        false,
        vec![IntrinsicMember {
            owner: SymbolId::of("/datum/example"),
            name: SymbolId::of("probe"),
            kind: MemberKind::Proc,
            shared_owner: None,
            instance_storage_proven: false,
        }],
    );
    let fact = parent_fact(
        &frontend.snapshot.tree,
        frontend.bodies[0].member,
        &resolver,
    )
    .unwrap();
    assert!(fact.has_parent);
}
#[test]
fn missing_parent_does_not_visit_its_own_arguments() {
    assert_eq!(
        rows("/datum/example/proc/probe()\n    return ..(..())\n", true)
            .unwrap()
            .len(),
        1
    );
}
#[test]
fn linear_return_and_settings_preserve_exact_visitation() {
    let source="/datum/example/proc/probe()\n    set desc = \"description\"\n    var/a = list(..(), (..()))\n    return ..()\n    ..()\n";
    let rows = rows(source, true).unwrap();
    assert_eq!(rows.iter().map(|r| r.0).collect::<Vec<_>>(), [3, 3, 4]);
}
#[test]
fn unknown_control_and_call_argument_visitation_fail_closed() {
    for body in [
        "    if(1)\n        return ..()\n",
        "    return unresolved(..())\n",
        "    return !..()\n",
    ] {
        assert!(rows(&format!("/datum/example/proc/probe()\n{body}"), true).is_err());
    }
}
#[test]
fn disabled_policy_needs_no_parent_absence_proof() {
    let frontend = frontend("/datum/example/proc/probe()\n    return unresolved(..())\n");
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            assert!(check(
                &frontend,
                body,
                frontend.snapshot.tree.as_ref(),
                Severity::Disabled
            )
            .unwrap()
            .is_empty());
        })
        .unwrap();
}

#[test]
fn seeded_linear_fixture_preserves_exact_pinned_term_columns() {
    let frontend = frontend(include_str!(
        "../../../fixtures/unified_checks/parent_call_linear/probe.dm"
    ));
    let resolver = synthetic_engine(&frontend, true, Vec::new());
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let mut positions = Vec::new();
    for (_, occurrence) in crate::checker_order::bodies(&frontend).unwrap() {
        arena
            .with_parsed(occurrence, |body| {
                for row in check(&frontend, body, &resolver, Severity::Error).unwrap() {
                    let line = frontend.location(row.span.start).unwrap().line;
                    let column = frontend.expanded.text[..row.span.start]
                        .rsplit('\n')
                        .next()
                        .unwrap()
                        .chars()
                        .count()
                        + 1;
                    positions.push((line, column));
                }
            })
            .unwrap();
    }
    assert_eq!(positions, [(2, 18), (2, 25), (3, 12)]);
}

#[path = "../examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
#[test]
fn real_pinned_checker_catalog_proves_absence_without_runtime_inventory_claim() {
    let seed = reference_hierarchy::seed();
    let source = include_str!("../../../fixtures/unified_checks/parent_call_linear/probe.dm");
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("parents.dme"),
        &Source(source.into()),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let resolver = frontend.snapshot.tree.as_ref();
    assert!(!resolver.intrinsic_inventory_complete());
    let profile = resolver.checker_builtin_profile().unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let mut diagnostics = Vec::new();
    for (_, occurrence) in crate::checker_order::bodies(&frontend).unwrap() {
        arena
            .with_parsed(occurrence, |body| {
                diagnostics.extend(
                    check_in_profile(&frontend, body, resolver, Some(profile), Severity::Error)
                        .unwrap(),
                );
            })
            .unwrap();
    }
    assert_eq!(diagnostics.len(), 3);
    assert!(diagnostics
        .iter()
        .all(|d| d.message == "proc has no parent: /datum/example/proc/probe[0/2]"));
    let member = frontend.bodies[0].member;
    assert!(parent_fact_in_profile(
        &frontend.snapshot.tree,
        member,
        resolver,
        Some(PackedU128::new(profile.get() ^ 1))
    )
    .is_err());
    assert!(
        parent_fact(&frontend.snapshot.tree, member, resolver).is_err(),
        "runtime partial inventory must still decline absence"
    );
}

#[test]
fn checker_profile_does_not_authorize_foreign_body_rebinding() {
    let a = frontend("/datum/example/proc/probe()\n    return ..()\n");
    let b = frontend("/datum/example/proc/probe()\n    return 1\n");
    let arena = BodyArena::new_typed(&a, |_| true);
    arena
        .with_parsed(&a.bodies[0], |body| {
            assert!(check_in_profile(
                &b,
                body,
                b.snapshot.tree.as_ref(),
                Some(PackedU128::new(1)),
                Severity::Error
            )
            .is_err());
        })
        .unwrap();
    // No attachment/rebind API is added to BodyArchive; archived bodies remain
    // authenticated against their original tree and syntax owners.
}

#[test]
fn pinned_parent_search_includes_global_source_and_builtin_procs() {
    let seed = reference_hierarchy::seed();
    let source = include_str!("../../../fixtures/unified_checks/parent_call_global/probe.dm");
    let frontend = build_with_config(
        Path::new("global_parent.dme"),
        &Source(source.into()),
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let resolver = frontend.snapshot.tree.as_ref();
    let profile = resolver.checker_builtin_profile().unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let mut rows = Vec::new();
    for (_, occurrence) in crate::checker_order::bodies(&frontend).unwrap() {
        arena
            .with_parsed(occurrence, |body| {
                for diagnostic in
                    check_in_profile(&frontend, body, resolver, Some(profile), Severity::Error)
                        .unwrap()
                {
                    rows.push((
                        frontend.location(diagnostic.span.start).unwrap().line,
                        diagnostic.message,
                    ));
                }
            })
            .unwrap();
    }
    assert_eq!(
        rows,
        [(
            8,
            "proc has no parent: /datum/example/proc/genuine_missing".into()
        )]
    );
}
