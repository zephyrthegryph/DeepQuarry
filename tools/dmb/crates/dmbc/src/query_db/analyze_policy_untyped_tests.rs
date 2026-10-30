use super::*;
use crate::{
    input_snapshot::{FolderListing, RecordingInputs, SnapshotProvider, Stamp},
    policy_request::{PolicyInputFile, PolicyInputRequest, PolicyInputRole},
};
#[path = "../../../dm-analysis/examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
#[derive(Clone)]
struct Source;
impl Source {
    fn bytes(path: &Path) -> io::Result<&'static [u8]> {
        match path.file_name().and_then(|s| s.to_str()) {
            Some("deepquarry.dme") => Ok(b"#include \"code/probe.dm\"\n"),
            Some("probe.dm") => {
                Ok(b"/datum/probe\n    var/link\n    proc/save(datum/probe/P)\n        link = P\n")
            }
            _ => Err(io::ErrorKind::NotFound.into()),
        }
    }
}
impl SnapshotProvider for Source {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        Ok(Stamp {
            size: Self::bytes(path)?.len() as u64,
            modified_ns: 1,
            file_id: Some(1),
        })
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        Ok((self.stamp(path)?, Self::bytes(path)?.to_vec()))
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        Ok(FolderListing::Present(if path.ends_with("code") {
            vec!["probe.dm".into()]
        } else {
            vec!["code".into(), "deepquarry.dme".into()]
        }))
    }
}
fn cohort(db: &Arc<QueryDb>) -> Arc<Cohort> {
    let root = std::env::current_dir().unwrap().join("untyped-host-query");
    let inputs = RecordingInputs::new(Source, 1);
    let seed = reference_hierarchy::seed();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &root.join("deepquarry.dme"),
        &inputs,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
        None,
        &executor,
        None,
        true,
    )
    .unwrap()
    .with_body_queries(db.clone());
    let intent = PolicyInputRequest {
        workspace: None,
        files: vec![PolicyInputFile {
            path: root.join("scopes.toml"),
            role: PolicyInputRole::Configuration,
            required: false,
        }],
        search_folders: vec![],
    }
    .admit()
    .unwrap();
    let capture = Arc::new(
        crate::runner_host::policy_capture::capture(
            &frontend,
            &inputs,
            &intent.capture_files(),
            &[],
        )
        .unwrap()
        .bind_request(&intent)
        .unwrap(),
    );
    db.raw_cohort(capture, &root, &root.join("scopes.toml"))
        .unwrap()
}
#[test]
fn admitted_complete_untyped_reuses_kind5_and_records_real_kind10_dependency() {
    let db = Arc::new(QueryDb::default());
    let cohort = cohort(&db);
    let result = db
        .analyze_fixture_findings(&cohort, &["untyped".into()])
        .unwrap();
    assert_eq!(result.runs.len(), 1);
    assert_eq!(result.runs[0].name, "untyped");
    assert!(result.runs[0].run.sites.iter().any(|s| s.rule == "typed"));
    let input = cohort.capture.untyped_input(&[]).unwrap();
    let proof_key = Key::new(
        super::super::super::value_proofs::VALUE_PROOFS,
        input.key().into(),
    );
    assert!(db
        .db
        .dependants(&[proof_key])
        .iter()
        .any(|k| k.kind == ANALYZE_FINDINGS));
    let inferred = db
        .db
        .stats(super::super::super::value_proofs::VALUE_PROOFS)
        .computed;
    let scans = db.db.stats(ANALYZE_FINDINGS).computed;
    let second = db
        .analyze_fixture_findings(&cohort, &["untyped".into()])
        .unwrap();
    assert_eq!(result.runs[0].run.sites, second.runs[0].run.sites);
    assert_eq!(
        db.db
            .stats(super::super::super::value_proofs::VALUE_PROOFS)
            .computed,
        inferred
    );
    assert_eq!(db.db.stats(ANALYZE_FINDINGS).computed, scans);
    assert!(inferred > 0);
}

#[test]
fn actual_untyped_kind10_kind5_body_operational_failure_is_not_cached_and_recovers() {
    let db = Arc::new(QueryDb::default());
    let cohort = cohort(&db);
    let schedule = db.fail_body_syntax_after_for_test(
        0,
        io::Error::new(io::ErrorKind::OutOfMemory, "actual Kind4 source budget"),
    );
    let error = db
        .analyze_fixture_findings(&cohort, &["untyped".into()])
        .err()
        .expect("scheduled original body failure");
    assert_eq!(error.kind(), io::ErrorKind::OutOfMemory);
    assert_eq!(error.to_string(), "actual Kind4 source budget");
    for kind in [Kind(4), Kind(5), Kind(10)] {
        assert_eq!(
            db.db.stats(kind).computed,
            0,
            "no parser/value/findings error Outcome"
        );
    }
    drop(schedule);
    let result = db
        .analyze_fixture_findings(&cohort, &["untyped".into()])
        .unwrap();
    assert!(result.runs[0]
        .run
        .sites
        .iter()
        .any(|site| site.rule == "typed"));
    assert_eq!(db.db.stats(Kind(5)).computed, 1);
    assert_eq!(db.db.stats(Kind(10)).computed, 1);
}

#[test]
fn native_checked_public_value_query_preserves_io_retries_and_reuses_same_kind5_proof() {
    let db = Arc::new(QueryDb::default());
    let cohort = cohort(&db);
    let input = cohort.capture.untyped_input(&[]).unwrap();
    let schedule = db.fail_body_syntax_after_for_test(
        0,
        io::Error::new(
            io::ErrorKind::Interrupted,
            "actual native value cancellation",
        ),
    );
    match input
        .obtain_checked(db.as_ref())
        .err()
        .expect("scheduled original Kind4 error")
    {
        dm_analysis::value_query::ValueQueryFailure::Operational(error) => {
            assert_eq!(error.kind(), io::ErrorKind::Interrupted);
            assert_eq!(error.to_string(), "actual native value cancellation");
        }
        other => panic!("actual IO became semantic value refusal: {other:?}"),
    }
    assert_eq!(db.db.stats(Kind(5)).computed, 0);
    drop(schedule);
    let first = input.obtain_checked(db.as_ref()).unwrap();
    let second = input.obtain_checked(db.as_ref()).unwrap();
    let legacy = input.obtain(db.as_ref()).unwrap();
    assert!(Arc::ptr_eq(&first, &second));
    assert!(Arc::ptr_eq(&first, &legacy));
    assert_eq!(db.db.stats(Kind(5)).computed, 1);
}

#[test]
fn native_checked_value_syntax_transport_is_cacheable_with_original_anchor() {
    // Explicit failure-transport control, not an authored syntax-parity claim.
    // The location is borrowed from this real frontend's original occurrence.
    let db = Arc::new(QueryDb::default());
    let cohort = cohort(&db);
    let input = cohort.capture.untyped_input(&[]).unwrap();
    let source = input.archive().occurrences()[0].source.clone();
    let diagnostic = dm_tree::frontend::Diagnostic {
        kind: dm_tree::frontend::DiagnosticKind::SourceError,
        stage: dm_tree::frontend::DiagnosticStage::Syntax,
        message: String::from("actual checked syntax boundary"),
        location: Some(source.clone()),
    };
    db.db.define(
        Kind(4),
        "original-syntax-error-transport-control",
        move |_, _| {
            let result: Result<Arc<dm_tree::frontend::BodySyntax>, dm_tree::frontend::Diagnostic> =
                Err(diagnostic.clone());
            Ok(dm_query::Outcome::new(result, 42, 1024))
        },
    );
    for _ in 0..2 {
        match input
            .obtain_checked(db.as_ref())
            .err()
            .expect("scheduled source rejection")
        {
            dm_analysis::value_query::ValueQueryFailure::Syntax(d) => {
                let location = d.location.unwrap();
                assert_eq!(location.span, source.span);
                assert_eq!(location.line, source.line);
                assert!(Arc::ptr_eq(&location.path, &source.path));
            }
            other => panic!("source syntax point lost: {other:?}"),
        }
    }
    assert_eq!(
        db.db.stats(Kind(5)).computed,
        1,
        "genuine syntax status may be cached, operational status may not"
    );
    let mut census = crate::heap_census::HeapCensus::new("value-cached-syntax");
    db.value_rejection_census(&mut census);
    let report = census.finish();
    assert!(report
        .owners
        .iter()
        .any(|owner| owner.owner == "native_value_rejection"
            && owner.unique_known_capacity_bytes > 0));
}

#[test]
fn untyped_checked_report_body_redemand_failure_after_warm_proof_is_not_cached() {
    use dm_analysis::value_query::ArchiveValueQueries;
    let db = Arc::new(QueryDb::default());
    let cohort = cohort(&db);
    let input = cohort.capture.untyped_input(&[]).unwrap();
    let proof = db.value_proof_checked(&input).unwrap();
    assert_eq!(db.db.stats(Kind(5)).computed, 1);
    assert!(
        db.db.evict_values(&[Kind(4)]) > 0,
        "force a real later original body demand, retaining only its value summary"
    );
    let schedule = db.fail_body_syntax_after_for_test(
        0,
        io::Error::new(
            io::ErrorKind::OutOfMemory,
            "actual report-phase body admission",
        ),
    );
    let error = db
        .analyze_fixture_findings(&cohort, &["untyped".into()])
        .err()
        .expect("checked report demand must fail");
    assert_eq!(error.kind(), io::ErrorKind::OutOfMemory);
    assert_eq!(error.to_string(), "actual report-phase body admission");
    assert_eq!(
        db.db.stats(Kind(5)).computed,
        1,
        "cached same-owner value proof is not recomputed"
    );
    assert_eq!(
        db.db.stats(Kind(10)).computed,
        0,
        "report IO cannot become a cached String refusal"
    );
    drop(schedule);
    let recovered = db
        .analyze_fixture_findings(&cohort, &["untyped".into()])
        .unwrap();
    assert!(recovered.runs[0]
        .run
        .sites
        .iter()
        .any(|site| site.rule == "typed"));
    assert!(Arc::ptr_eq(
        &proof,
        &db.value_proof_checked(&input).unwrap()
    ));
    assert_eq!(db.db.stats(Kind(10)).computed, 1);
}

#[test]
fn actual_player_link_kind10_body_operation_is_not_semantic_outcome_and_same_input_recovers() {
    let db=Arc::new(QueryDb::default());
    let cohort=cohort(&db);
    let names=["player_link".into()];
    let schedule=db.fail_body_syntax_after_for_test(0,
        io::Error::new(io::ErrorKind::OutOfMemory,"actual player-link Kind4 source budget"));
    let error=db.analyze_fixture_findings(&cohort,&names).err().expect("original current body operation");
    assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);
    assert_eq!(error.to_string(),"actual player-link Kind4 source budget");
    for kind in [Kind(4),Kind(10)]{assert_eq!(db.db.stats(kind).computed,0,"no operational Outcome");}
    drop(schedule);
    let actual=db.analyze_fixture_findings(&cohort,&names).unwrap();
    assert_eq!(actual.runs.len(),1);
    assert_eq!(actual.runs[0].name,"player_link");
    assert!(actual.runs[0].run.sites.is_empty(),"same original datum receiver is not a mob");
    let warm=db.analyze_fixture_findings(&cohort,&names).unwrap();
    assert_eq!(actual.runs[0].run.sites,warm.runs[0].run.sites);
    for kind in [Kind(4),Kind(10)]{assert_eq!(db.db.stats(kind).computed,1,"same-input successful retry/warm reuse");}
}
