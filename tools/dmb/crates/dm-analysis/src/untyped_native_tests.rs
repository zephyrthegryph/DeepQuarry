use super::*;
#[path = "../examples/support/reference_hierarchy.rs"]
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
fn scan(source: &'static str) -> Result<Vec<Finding>, Unsupported> {
    let frontend = build(
        Path::new("code/probe.dm"),
        &Source(source),
        &Default::default(),
        1,
    )
    .map_err(|e| Unsupported(format!("{e:?}")))?;
    let bodies = BodyArena::new_typed(&frontend, |_| true);
    let mut schemas = Schemas::default();
    schemas.read_source(source).map_err(Unsupported)?;
    let values = Values::build(&frontend, &bodies, frontend.snapshot.tree.as_ref(), &[])?;
    findings(
        &frontend,
        &bodies,
        &values,
        &schemas,
        Path::new("."),
        &[],
        |_| false,
    )
}
#[test]
fn native_policy_keeps_scalar_proofs_and_all_assigning_evidence() {
    let result = scan("/datum/test\n    var/saved\n    var/scalar\n    proc/entity()\n        return new /datum\n    proc/number()\n        return 7\n    proc/use(datum/arg)\n        saved = entity()\n        scalar = number()\n        saved = arg\n").unwrap();
    assert_eq!(result.len(), 1);
    let row = &result[0];
    assert_eq!(row.rule, Rule::Typed);
    assert_eq!(row.line, 2);
    assert_eq!(row.identity, "/datum/test::saved");
    assert_eq!(row.message,"/datum/test/var/saved has no type and is assigned an atom or datum at code/probe.dm:9, code/probe.dm:11");
}
#[test]
fn native_policy_distinguishes_unknown_call_aliases_from_scalar_aliases() {
    let result = scan("/datum/test\n    var/saved\n    var/scalar\n    proc/entity()\n        return new /datum\n    proc/number()\n        return 7\n    proc/use()\n        var/temp = entity()\n        var/copy = temp\n        saved = copy\n        var/value = number()\n        scalar = value\n").unwrap();
    assert_eq!(result.len(), 1);
    assert_eq!(result[0].rule, Rule::Call);
    assert_eq!(result[0].identity, "/datum/test::saved");
}
#[test]
fn raw_schema_policy_checks_inherited_path_literals() {
    let result = scan("#define SCHEMA(T,V,K)\n/datum/msg\n/datum/msg/ok\n/datum/test\n    var/reason\nSCHEMA(/datum/test, reason, schema_msg())\n/datum/test/sub/proc/use()\n    reason = /datum/test\n").unwrap();
    assert_eq!(result.len(), 1);
    assert_eq!(result[0].rule, Rule::Schema);
    assert_eq!(result[0].identity, "/datum/test::reason");
    assert!(result[0]
        .message
        .ends_with("code/probe.dm:8 (/datum/test is not a /datum/msg path)"));
}
#[test]
fn unsupported_string_children_never_produce_a_clean_policy_result() {
    let error = scan("/datum/test/proc/use()\n    return \"[broken(]\"\n").unwrap_err();
    assert!(
        error.0.contains("unsupported") || error.0.contains("incomplete"),
        "{error}"
    );
}

#[test]
fn world_value_reads_resolve_without_inventing_a_source_field() {
    let rows = scan("/datum/test\n    var/saved\n    proc/clock()\n        return world.time\n    proc/use()\n        saved = clock()\n").unwrap();
    assert!(rows.is_empty());
}

#[test]
fn retained_archive_preserves_policy_rows_after_frontend_release() {
    let source = "/datum/test\n    var/saved\n    var/scalar\n    proc/entity()\n        return new /datum\n    proc/number()\n        return 7\n    proc/use(datum/arg)\n        saved = entity()\n        scalar = number()\n        saved = arg\n";
    let (archive, expected) = {
        let frontend = build(
            Path::new("code/probe.dm"),
            &Source(source),
            &Default::default(),
            1,
        )
        .unwrap();
        let bodies = BodyArena::new_typed(&frontend, |_| true);
        let schemas = Schemas::default();
        let values =
            Values::build(&frontend, &bodies, frontend.snapshot.tree.as_ref(), &[]).unwrap();
        let expected = findings(
            &frontend,
            &bodies,
            &values,
            &schemas,
            Path::new("."),
            &[],
            |_| false,
        )
        .unwrap();
        (frontend.body_archive().unwrap(), expected)
    };
    let values = Values::build_archive(&archive, archive.tree(), &[]).unwrap();
    let actual = archived_findings(
        &archive,
        &values,
        &Schemas::default(),
        Path::new("."),
        &[],
        |_| false,
    )
    .unwrap();
    assert_eq!(actual, expected);
    assert_eq!(actual.len(), 1);
    assert!(actual[0]
        .message
        .ends_with("code/probe.dm:9, code/probe.dm:11"));
}

#[test]
fn archive_policy_rejects_equal_syntax_from_another_issuance() {
    let source = "/datum/test\n    var/saved\n    proc/use(datum/arg)\n        saved = arg\n";
    let first = build(
        Path::new("code/probe.dm"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap()
    .body_archive()
    .unwrap();
    let second = build(
        Path::new("code/probe.dm"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap()
    .body_archive()
    .unwrap();
    let values = Values::build_archive(&first, first.tree(), &[]).unwrap();
    let body = second.parse(0).unwrap();
    assert!(
        archived_body_evidence(&first, &body, &values, &Schemas::default(), &[])
            .unwrap_err()
            .0
            .contains("another archive")
    );
    assert!(archived_findings(
        &second,
        &values,
        &Schemas::default(),
        Path::new("."),
        &[],
        |_| false
    )
    .is_err());
}

#[test]
fn foreign_value_summaries_are_rejected_even_when_no_assignment_is_observed() {
    for source in ["/datum/empty\n", "/proc/test()\n    return 1\n"] {
        let first = build(
            Path::new("code/probe.dm"),
            &Source(source),
            &Default::default(),
            1,
        )
        .unwrap();
        let second = build(
            Path::new("code/probe.dm"),
            &Source(source),
            &Default::default(),
            2,
        )
        .unwrap();
        let first_bodies = BodyArena::new_typed(&first, |_| true);
        let second_bodies = BodyArena::new_typed(&second, |_| true);
        let foreign_live =
            Values::build(&second, &second_bodies, second.snapshot.tree.as_ref(), &[]).unwrap();
        // Even exemptions covering every file may not convert an unauthorized
        // origin into a clean report.
        assert!(findings(
            &first,
            &first_bodies,
            &foreign_live,
            &Schemas::default(),
            Path::new("."),
            &[],
            |_| true
        )
        .is_err());
        if let Some(occurrence) = first.bodies.first() {
            first_bodies
                .with_parsed(occurrence, |body| {
                    assert!(
                        body_evidence(&first, body, &foreign_live, &Schemas::default(), &[])
                            .is_err()
                    );
                })
                .unwrap();
        }
        let archive = first.body_archive().unwrap();
        let foreign_archive = second.body_archive().unwrap();
        let foreign_values =
            Values::build_archive(&foreign_archive, foreign_archive.tree(), &[]).unwrap();
        assert!(archived_findings(
            &archive,
            &foreign_values,
            &Schemas::default(),
            Path::new("."),
            &[],
            |_| true
        )
        .is_err());
        if !archive.is_empty() {
            let body = archive.parse(0).unwrap();
            assert!(archived_body_evidence(
                &archive,
                &body,
                &foreign_values,
                &Schemas::default(),
                &[]
            )
            .is_err());
        }
    }
}

#[test]
fn policy_field_reads_use_the_same_observed_resolver_as_value_inference() {
    use std::sync::atomic::{AtomicUsize, Ordering};
    struct Observed<'a> {
        tree: &'a SemanticTree,
        field_reads: AtomicUsize,
    }
    impl Resolver for Observed<'_> {
        fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            if matches!(query, dm_ir::ResolveQuery::Var { name, .. } if name == SymbolId::of("saved"))
            {
                self.field_reads.fetch_add(1, Ordering::Relaxed);
            }
            Resolver::resolve(self.tree, query)
        }
    }
    let frontend = build(
        Path::new("code/probe.dm"),
        &Source("/datum/test\n    var/saved\n    proc/use(datum/value)\n        saved = value\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let bodies = BodyArena::new_typed(&frontend, |_| true);
    let resolver = Observed {
        tree: frontend.snapshot.tree.as_ref(),
        field_reads: AtomicUsize::new(0),
    };
    let values = Values::build(&frontend, &bodies, &resolver, &[]).unwrap();
    let before = resolver.field_reads.load(Ordering::Relaxed);
    bodies
        .with_parsed(&frontend.bodies[0], |body| {
            let evidence =
                body_evidence(&frontend, body, &values, &Schemas::default(), &[]).unwrap();
            assert_eq!(evidence.len(), 1);
            assert_eq!(evidence[0].rule, Rule::Typed);
        })
        .unwrap();
    assert!(resolver.field_reads.load(Ordering::Relaxed) > before);
}

#[test]
fn inference_exemptions_are_bound_before_empty_reports_or_file_exemptions() {
    let frontend = build(
        Path::new("code/probe.dm"),
        &Source("/proc/test()\n    return 1\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let bodies = BodyArena::new_typed(&frontend, |_| true);
    let exemptions = vec!["/datum/alpha".to_owned(), "/datum/beta".to_owned()];
    let same = vec![
        "/datum/beta".to_owned(),
        "/datum/alpha".to_owned(),
        "/datum/alpha".to_owned(),
    ];
    let values = Values::build(
        &frontend,
        &bodies,
        frontend.snapshot.tree.as_ref(),
        &exemptions,
    )
    .unwrap();
    assert!(values.validate_exempt_types(&same).is_ok());
    assert!(findings(
        &frontend,
        &bodies,
        &values,
        &Schemas::default(),
        Path::new("."),
        &same,
        |_| true
    )
    .unwrap()
    .is_empty());
    assert!(findings(
        &frontend,
        &bodies,
        &values,
        &Schemas::default(),
        Path::new("."),
        &[],
        |_| true
    )
    .is_err());
    bodies
        .with_parsed(&frontend.bodies[0], |body| {
            assert!(body_evidence(&frontend, body, &values, &Schemas::default(), &[]).is_err());
        })
        .unwrap();
    let archive = frontend.body_archive().unwrap();
    let values = Values::build_archive(&archive, archive.tree(), &exemptions).unwrap();
    assert!(archived_findings(
        &archive,
        &values,
        &Schemas::default(),
        Path::new("."),
        &same,
        |_| true
    )
    .unwrap()
    .is_empty());
    assert!(archived_findings(
        &archive,
        &values,
        &Schemas::default(),
        Path::new("."),
        &[],
        |_| true
    )
    .is_err());
    let body = archive.parse(0).unwrap();
    assert!(archived_body_evidence(&archive, &body, &values, &Schemas::default(), &[]).is_err());
}

#[cfg(windows)]
#[test]
fn dos_root_reports_real_verbatim_archive_finding_without_rewriting_origin() {
    let source = "/datum/test\n    var/saved\n    proc/use(datum/arg)\n        saved = arg\n";
    let authored = Path::new(r"\\?\E:\native-policy-fixture\code\probe.dm");
    let frontend = build(authored, &Source(source), &Default::default(), 1).unwrap();
    let archive = frontend.body_archive().unwrap();
    let values = Values::build_archive(&archive, archive.tree(), &[]).unwrap();
    let rows = archived_findings(&archive, &values, &Schemas::default(),
        Path::new(r"E:\native-policy-fixture"), &[], |_| false).unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].file, "code/probe.dm");
    assert!(rows[0].message.ends_with("code/probe.dm:4"));
    // The reporting comparison never changes the compiler's issued location.
    assert_eq!(archive.occurrences()[0].source.path.as_path(), authored);
}
#[cfg(windows)]
#[test]
fn report_projection_unifies_only_safe_drive_verbatim_spelling() {
    let root = Path::new(r"E:\native-policy-fixture");
    assert_eq!(relative(root, Path::new(r"\\?\E:\native-policy-fixture\code\x.dm")), "code/x.dm");
    assert_ne!(relative(root, Path::new(r"\\.\E:\native-policy-fixture\code\x.dm")), "code/x.dm");
    assert_ne!(relative(root, Path::new(r"\\?\UNC\server\share\native-policy-fixture\code\x.dm")), "code/x.dm");
    assert_ne!(relative(root, Path::new(r"E:\native-policy-fixture-other\code\x.dm")), "code/x.dm");
}
