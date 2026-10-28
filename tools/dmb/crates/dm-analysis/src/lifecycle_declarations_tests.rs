use super::*;
use dm_tree::frontend::{build, build_with_config, EngineSeed, FrontendConfig};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
// Certify only this fixture's minimal intrinsic hierarchy. Intrinsic member
// metadata remains incomplete; lifecycle classification needs only ancestry.
fn build_fixture<P: dm_preprocess::SourceProvider>(
    project: &Path,
    provider: &P,
) -> dm_tree::frontend::ColdFrontend {
    let parents = [
        ("/", None),
        ("/datum", Some("/")),
        ("/atom", Some("/datum")),
        ("/atom/movable", Some("/atom")),
        ("/obj", Some("/atom/movable")),
        ("/mob", Some("/atom/movable")),
        ("/turf", Some("/atom")),
        ("/area", Some("/atom")),
    ];
    let mut symbols = dm_ir::SymbolTable::default();
    for (path, _) in &parents {
        symbols.intern(path).unwrap();
    }
    let seed = EngineSeed {
        identity: 0x1f3c7,
        symbols,
        hierarchy: dm_tree::EngineHierarchy {
            schema: 0x516,
            parents: parents
                .iter()
                .map(|(path, parent)| (SymbolId::of(path), parent.map(SymbolId::of)))
                .collect(),
        },
        fields: std::sync::Arc::from([]),
        intrinsics: std::sync::Arc::from([]),
    };
    build_with_config(
        project,
        provider,
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap()
}
fn archive(source: &'static str) -> std::sync::Arc<BodyArchive> {
    build_fixture(Path::new("code/lifecycle.dm"), &Source(source))
        .body_archive()
        .unwrap()
}
fn shown<'a>(
    a: &'a BodyArchive,
    rows: &[LifecycleDefinition<'a>],
) -> Vec<(usize, &'a str, &'a str, bool)> {
    rows.iter()
        .map(|row| {
            (
                row.source.line,
                a.tree().symbols().text(row.owner).unwrap(),
                a.tree().symbols().text(row.name).unwrap(),
                row.lifecycle,
            )
        })
        .collect()
}

#[test]
fn decl_roster_retains_manual_initialize_but_marks_only_atom_hooks() {
    let a = archive("/atom\n    proc/Initialize()\n        return\n/datum/manual\n    proc/Initialize()\n        return\n    proc/on_materialize()\n        return\n    proc/on_destroy()\n        return\n");
    let rows = lifecycle_definitions(&a, LifecyclePolicy::Decl, Path::new(".")).unwrap();
    assert_eq!(
        shown(&a, &rows),
        [
            (2, "/atom", "Initialize", true),
            (5, "/datum/manual", "Initialize", false),
            (7, "/datum/manual", "on_materialize", true),
            (9, "/datum/manual", "on_destroy", true)
        ]
    );
}

#[test]
fn init_roster_keeps_legacy_names_and_lexical_turf_materialize_filter() {
    let a = archive("/datum/manual\n    proc/Initialize()\n        return\n    proc/LateInitialize()\n        return\n    proc/on_materialize()\n        return\n    proc/on_destroy()\n        return\n/turf\n    proc/on_materialize()\n        return\n/turf/child\n    on_materialize()\n        return\n/datum/elsewhere\n    parent_type = /turf\n    on_materialize()\n        return\n");
    let rows = lifecycle_definitions(&a, LifecyclePolicy::Init, Path::new(".")).unwrap();
    assert_eq!(
        shown(&a, &rows),
        [
            (2, "/datum/manual", "Initialize", true),
            (4, "/datum/manual", "LateInitialize", true),
            (11, "/turf", "on_materialize", true),
            (14, "/turf/child", "on_materialize", true)
        ]
    );
}

#[test]
fn authored_formals_and_overrides_keep_their_own_sources_without_inherited_copies() {
    let a = archive("/atom\n    proc/Initialize()\n        return\n/atom/first\n    Initialize()\n        return\n/atom/first/leaf\n/atom/second\n    Initialize()\n        return\n");
    let rows = lifecycle_definitions(&a, LifecyclePolicy::Decl, Path::new(".")).unwrap();
    assert_eq!(
        shown(&a, &rows),
        [
            (2, "/atom", "Initialize", true),
            (5, "/atom/first", "Initialize", true),
            (9, "/atom/second", "Initialize", true)
        ]
    );
    assert_eq!(rows.len(), 3);
    assert_eq!(rows[0].definition, DefinitionMode::Declare);
    assert!(a.tree().member(rows[1].member).unwrap().previous.is_some());
    for row in rows {
        assert!(a
            .occurrences()
            .iter()
            .any(|occurrence| occurrence.member == row.member
                && std::ptr::eq(&occurrence.source, row.source)));
    }
}

#[test]
fn decl_initialize_uses_actual_parent_type_ancestry() {
    let a = archive("/atom\n/atom/lexical_detached\n    parent_type = /datum\n    proc/Initialize()\n        return\n/datum/actual_atom\n    parent_type = /atom\n    proc/Initialize()\n        return\n");
    let rows = lifecycle_definitions(&a, LifecyclePolicy::Decl, Path::new(".")).unwrap();
    assert_eq!(
        shown(&a, &rows),
        [
            (4, "/atom/lexical_detached", "Initialize", false),
            (8, "/datum/actual_atom", "Initialize", true)
        ]
    );
}

#[test]
fn absent_origin_is_an_error_not_a_fabricated_header() {
    let a = archive("/datum/manual/proc/Initialize()\n    return\n");
    let mut occurrence = a.occurrences()[0].clone();
    occurrence.source.line = 0;
    assert!(row(a.tree(), &occurrence, LifecyclePolicy::Init)
        .unwrap_err()
        .0
        .contains("source origin"));
}

#[test]
fn report_order_is_file_header_order_not_inheritance_or_include_order() {
    struct Files;
    impl dm_preprocess::SourceProvider for Files {
        fn read(&self, path: &Path) -> Result<String, String> {
            Ok(match path.file_name().and_then(|s| s.to_str()) {
                Some("project.dme") => "#include \"z.dm\"\n#include \"a.dm\"\n",
                Some("z.dm") => "/atom\n    proc/Initialize()\n        return\n",
                Some("a.dm") => "/atom/child\n    Initialize()\n        return\n",
                _ => return Err(format!("unexpected file {}", path.display())),
            }
            .into())
        }
    }
    let a = build_fixture(Path::new("project.dme"), &Files)
        .body_archive()
        .unwrap();
    let rows = lifecycle_definitions(&a, LifecyclePolicy::Decl, Path::new(".")).unwrap();
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0].source.path.file_name().unwrap(), "a.dm");
    assert_eq!(rows[1].source.path.file_name().unwrap(), "z.dm");
    assert_eq!(a.tree().symbols().text(rows[0].owner), Some("/atom/child"));
    assert_eq!(rows[0].source.line, 2);
    assert_eq!(rows[1].source.line, 2);
}

#[test]
fn macro_defined_header_uses_issued_invocation_origin() {
    let a = archive("#define INIT_HOOK /datum/manual/proc/Initialize()\nINIT_HOOK\n    return\n");
    let rows = lifecycle_definitions(&a, LifecyclePolicy::Decl, Path::new(".")).unwrap();
    assert_eq!(
        shown(&a, &rows),
        [(2, "/datum/manual", "Initialize", false)]
    );
    assert!(!rows[0].source.macro_expansions.is_empty());
}

#[test]
fn source_only_obj_and_mob_ancestry_cannot_be_a_clean_non_lifecycle_answer() {
    for source in [
        "/obj/foo/proc/Initialize()\n    return\n",
        "/mob/foo/proc/Initialize()\n    return\n",
    ] {
        let frontend = build(
            Path::new("code/source_only.dm"),
            &Source(source),
            &Default::default(),
            1,
        )
        .unwrap();
        assert!(!frontend.snapshot.tree.intrinsic_hierarchy_certified());
        let archive = frontend.body_archive().unwrap();
        let error =
            lifecycle_definitions(&archive, LifecyclePolicy::Decl, Path::new(".")).unwrap_err();
        assert!(error.0.contains("certified"), "{error}");
    }
}

#[test]
fn certified_obj_and_mob_are_lifecycle_hooks_but_plain_datums_are_not() {
    let a = archive("/obj/foo/proc/Initialize()\n    return\n/mob/foo/proc/Initialize()\n    return\n/datum/manual/proc/Initialize()\n    return\n");
    assert!(a.tree().intrinsic_hierarchy_certified());
    assert!(
        !a.tree().intrinsic_inventory_complete(),
        "full member metadata is not required for ancestry"
    );
    let rows = lifecycle_definitions(&a, LifecyclePolicy::Decl, Path::new(".")).unwrap();
    assert_eq!(
        shown(&a, &rows),
        [
            (1, "/obj/foo", "Initialize", true),
            (3, "/mob/foo", "Initialize", true),
            (5, "/datum/manual", "Initialize", false)
        ]
    );
}

#[test]
fn init_roster_does_not_require_the_decl_specific_ancestry_query() {
    let frontend = build(
        Path::new("code/source_only.dm"),
        &Source(
            "/obj/foo/proc/Initialize()\n    return\n/mob/foo/proc/LateInitialize()\n    return\n",
        ),
        &Default::default(),
        1,
    )
    .unwrap();
    let archive = frontend.body_archive().unwrap();
    assert!(!archive.tree().intrinsic_hierarchy_certified());
    let rows = lifecycle_definitions(&archive, LifecyclePolicy::Init, Path::new(".")).unwrap();
    assert_eq!(
        shown(&archive, &rows),
        [
            (1, "/obj/foo", "Initialize", true),
            (3, "/mob/foo", "LateInitialize", true)
        ]
    );
}
