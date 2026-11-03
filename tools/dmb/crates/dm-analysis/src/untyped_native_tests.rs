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
    let rows = archived_findings(
        &archive,
        &values,
        &Schemas::default(),
        Path::new(r"E:\native-policy-fixture"),
        &[],
        |_| false,
    )
    .unwrap();
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
    assert_eq!(
        relative(root, Path::new(r"\\?\E:\native-policy-fixture\code\x.dm")),
        "code/x.dm"
    );
    assert_ne!(
        relative(root, Path::new(r"\\.\E:\native-policy-fixture\code\x.dm")),
        "code/x.dm"
    );
    assert_ne!(
        relative(
            root,
            Path::new(r"\\?\UNC\server\share\native-policy-fixture\code\x.dm")
        ),
        "code/x.dm"
    );
    assert_ne!(
        relative(root, Path::new(r"E:\native-policy-fixture-other\code\x.dm")),
        "code/x.dm"
    );
}

#[test]
fn qualified_assignment_fields_without_primary_view_refuse() {
    // The ordinary field path still lacks its original primary property view.
    assert!(scan("/datum/holder\n    var/SpacemanDMM_private/saved\n    proc/check()\n        saved = new /datum\n").is_err());
}
#[test]
fn original_qualified_locals_and_parameters_match_independent_old_empty_policy() {
    // Exact former negatives. Actual old Engine comparisons are retained in
    // array-qualifier-policy-oracles; these local hints have no finding.
    for source in [
        "/datum/holder\n    var/saved\n    proc/check()\n        var/SpacemanDMM_private/local = new /datum\n        saved = local\n",
        "/datum/holder\n    var/saved\n    proc/check(SpacemanDMM_protected/local)\n        saved = local\n",
    ] {
        assert!(scan(source).unwrap().is_empty(),"{source}");
    }
}

#[test]
fn qualified_fields_use_original_archive_hints_in_value_equations_and_policy_targets() {
    let source="/datum/holder\n    var/SpacemanDMM_private/saved\n    var/SpacemanDMM_private/call_value\n    var/SpacemanDMM_private/scalar\n    var/SpacemanDMM_private/missing_type/typed\n    proc/entity()\n        return new /datum\n    proc/number()\n        return 7\n    proc/use(datum/arg)\n        saved = arg\n        call_value = entity()\n        scalar = number()\n        typed = arg\n";
    struct Acquired(&'static str);
    impl dm_preprocess::SourceProvider for Acquired {
        fn read(&self, _: &Path) -> Result<String, String> {
            Err("must use actual acquired original bytes".into())
        }
        fn acquired_source(
            &self,
            _: &Path,
        ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
            Ok(Some(dm_preprocess::AcquiredSource::from_original_bytes(
                self.0.as_bytes().to_vec(),
                (),
            )))
        }
    }
    let seed = reference_hierarchy::seed();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let make = |primary| {
        dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
            Path::new("code/owned_fields.dm"),
            &Acquired(source),
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
            None,
            &executor,
            None,
            primary,
        )
        .unwrap()
        .body_archive()
        .unwrap()
    };
    let ordinary = make(false);
    assert!(
        Values::build_archive(&ordinary, ordinary.tree(), &[]).is_err(),
        "unissued raw qualifier spelling is not an untyped proof"
    );
    let archive = make(true);
    let body = archive.parse(0).unwrap();
    assert!(std::ptr::eq(body.archive_owner(), archive.as_ref()));
    let values = Values::build_archive(&archive, archive.tree(), &[]).unwrap();
    let rows = archived_findings(
        &archive,
        &values,
        &Schemas::default(),
        Path::new("."),
        &[],
        |_| false,
    )
    .unwrap();
    assert_eq!(
        rows.iter()
            .map(|r| (r.identity.as_str(), r.rule))
            .collect::<Vec<_>>(),
        [
            ("/datum/holder::saved", Rule::Typed),
            ("/datum/holder::call_value", Rule::Call)
        ]
    );
    assert!(rows
        .iter()
        .all(|r| !r.identity.ends_with("::typed") && !r.identity.ends_with("::scalar")));
}

struct UntypedWork{calls:usize,stop:usize,denial:bool}
impl crate::policy_body_demand::WorkspaceWork for UntypedWork{type Error=crate::policy_body_demand::PolicyFailure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{self.calls+=1;if self.calls==self.stop{return Err(Self::Error::Operational(std::io::Error::from_raw_os_error(1450)))}Ok(())}fn retain(&mut self,_:usize)->Result<(),Self::Error>{self.checkpoint()?;if self.denial{Err(Self::Error::Operational(std::io::ErrorKind::OutOfMemory.into()))}else{Ok(())}}fn temporary(&mut self,n:usize)->Result<(),Self::Error>{self.retain(n)}fn overflow(&mut self)->Self::Error{Self::Error::Operational(std::io::ErrorKind::OutOfMemory.into())}fn allocation_failed(&mut self)->Self::Error{Self::Error::Operational(std::io::ErrorKind::OutOfMemory.into())}fn body<'a>(&mut self,a:&'a BodyArchive,n:usize)->Result<ArchivedBody<'a>,Self::Error>{self.checkpoint()?;a.parse_checked(n).map_err(|e|match e{dm_tree::frontend::BodySyntaxFailure::Operational(e)=>Self::Error::Operational(e),dm_tree::frontend::BodySyntaxFailure::Syntax(e)=>Unsupported(e.message).into()})}}
#[test]fn complete_untyped_same_walk_checks_mid_scope_alias_and_dispatch_io_quota_and_recovery(){let source="/datum/test\n    var/saved\n    proc/entity()\n        return new /datum\n    proc/use()\n        var/a = entity()\n        var/b = a\n        saved = b\n";let front=build(Path::new("code/probe.dm"),&Source(source),&Default::default(),1).unwrap();let archive=front.body_archive().unwrap();let input=crate::value_query::ArchiveValueInput::new(archive.clone(),&[]);let proof=input.compute_checked().unwrap();let mut good=UntypedWork{calls:0,stop:usize::MAX,denial:false};let values=Values::from_archive_input_using(&input,proof.clone(),&mut good).unwrap();let expected=archived_findings_workspace_using(&archive,&values,&Schemas::default(),Path::new("."),&[],|_|false,|_,s|Ok(s),&mut good).unwrap();assert_eq!(expected.len(),1);assert_eq!(expected[0].rule,Rule::Call);assert!(good.calls>40);for stop in[1,17,39,good.calls/2]{let mut work=UntypedWork{calls:0,stop,denial:false};let error=(||{let values=Values::from_archive_input_using(&input,proof.clone(),&mut work)?;archived_findings_workspace_using(&archive,&values,&Schemas::default(),Path::new("."),&[],|_|false,|_,s|Ok(s),&mut work)})().unwrap_err();assert!(matches!(error,crate::policy_body_demand::PolicyFailure::Operational(e)if e.raw_os_error()==Some(1450)));assert_eq!(work.calls,stop,"no later checkpoint replaces actual mid-walk IO");}let mut denied=UntypedWork{calls:0,stop:usize::MAX,denial:true};assert!(matches!(Values::from_archive_input_using(&input,proof.clone(),&mut denied),Err(crate::policy_body_demand::PolicyFailure::Operational(e))if e.kind()==std::io::ErrorKind::OutOfMemory));let mut recovered=UntypedWork{calls:0,stop:usize::MAX,denial:false};let values=Values::from_archive_input_using(&input,proof,&mut recovered).unwrap();assert_eq!(archived_findings_workspace_using(&archive,&values,&Schemas::default(),Path::new("."),&[],|_|false,|_,s|Ok(s),&mut recovered).unwrap(),expected);}
