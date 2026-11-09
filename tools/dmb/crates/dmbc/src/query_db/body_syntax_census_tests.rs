//! Opt-in survey of the existing Original parser, after one actual host capture.
//! The survey never installs its body products or publishes policy reports.
use super::*;
use crate::{
    input_snapshot::{FileSystemInputs, RecordingInputs},
    policy_request::{AnalysisContext, PolicyInputFile, PolicyInputRequest, PolicyInputRole, WorkspacePolicyRequest},
    request::{BuildOutcome, Command},
    runner_host::BuildHost,
};
use dm_tree::frontend::{BodyArchive, CurrentBodySyntax, OriginalBodyDisposition,
    BodySyntaxQueries, FrontendConfig, OriginalAnalysisCompleteness, SettingExpressionQueries};
use dm_syntax::StatementKind;
use std::{io, path::Path};

const MAX_WINDOW: usize = 1024;
const MAX_EXAMPLES: usize = 32;
const ROOT_NAMES: [&str; 18] = [
    "if", "while", "do_while", "spawn", "set", "for", "switch", "try", "throw",
    "label", "goto", "return", "local", "assignment", "call", "expression", "loop_exit",
    "unsupported",
];

fn root_bucket(statement: &StatementKind) -> usize {
    match statement {
        StatementKind::If { .. } => 0,
        StatementKind::While { .. } => 1,
        StatementKind::DoWhile { .. } => 2,
        StatementKind::Spawn { .. } => 3,
        StatementKind::Set { .. } | StatementKind::ProjectedSet { .. } => 4,
        StatementKind::For { .. } => 5,
        StatementKind::Switch { .. } => 6,
        StatementKind::Try { .. } => 7,
        StatementKind::Throw(_) => 8,
        StatementKind::Label { .. } => 9,
        StatementKind::Goto(_) => 10,
        StatementKind::Return(_) => 11,
        StatementKind::Var { .. } => 12,
        StatementKind::Assign { .. } => 13,
        StatementKind::Call(_) => 14,
        StatementKind::Expression(_) => 15,
        StatementKind::Break | StatementKind::BreakLabel(_) | StatementKind::Continue
            | StatementKind::ContinueLabel(_) => 16,
        StatementKind::Unsupported => 17,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Disposition {
    Available,
    Skipped,
    Unissued(u32),
    NativeRejected,
}

fn invalid(message: &str) -> BodySyntaxFailure {
    BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::InvalidData, message))
}

fn prepare(project: &Path) -> BuildHost {
    let root = project.parent().unwrap();
    let args = ["prepare-query".to_owned(), project.to_str().unwrap().to_owned()];
    let Command::Build(mut request) = crate::cli::parse(&args).unwrap() else {
        panic!("expected actual PrepareQuery command");
    };
    request.no_cache = true;
    request.exact_inputs = true;
    request.progress_enabled = false;
    request.workers = 1;
    request.cache_root = Some(crate::test_scratch::dir("original-body-census-cache"));
    request.policy_inputs = Some(PolicyInputRequest {
        analysis_context: Some(AnalysisContext::OriginalChecker0290),
        files: vec![PolicyInputFile {
            path: root.join("SpacemanDMM.toml"),
            role: PolicyInputRole::Configuration,
            required: false,
        }],
        ..Default::default()
    });
    let mut host = BuildHost::default();
    let outcome = crate::request_runner::run_build_with_host(*request, &mut host).unwrap();
    assert!(matches!(outcome, BuildOutcome::QueryPrepared { retained: true, .. }));
    host
}

fn inspect(
    db: &QueryDb,
    archive: &BodyArchive,
    ordinal: usize,
    describe: bool,
) -> Result<Disposition, BodySyntaxFailure> {
    let occurrence = archive.occurrences().get(ordinal).ok_or_else(|| invalid("missing archive body ordinal"))?;
    let input = archive.syntax_inputs()
        .and_then(|inputs| inputs.get(ordinal))
        .ok_or_else(|| invalid("missing archive-issued BODY input"))?;
    if !archive.uses_body_queries(db) {
        return Err(invalid("census BODY owner differs"));
    }
    let show = |reason: &str, detail: &str| {
        if describe {
            eprintln!("original.census ordinal={ordinal} file={} line={} result={reason} detail={detail:?}",
                occurrence.source.semantic_path, occurrence.source.line);
        }
    };
    db.with_setting_admission(|admission| {
        // Same producer and budget as Kind4; keep only one body product alive
        // and do not prepare or populate any graph rows for the census.
        let product = input.parse_original_product_with_setting_admission(admission)?;
        if let Some(diagnostic) = product.bind_error(input)? {
            show("native_rejected", &diagnostic.message);
            return Ok(Disposition::NativeRejected);
        }
        let syntax = product.parsed().ok_or_else(|| invalid("BODY producer supplied no parse or rejection"))?;
        let bound = input.bind_original_product_checked(syntax, admission)?;
        if bound.body_span() != occurrence.expanded_span {
            return Err(invalid("census current BODY occurrence differs"));
        }
        match bound.original_code_disposition() {
            Ok(OriginalBodyDisposition::Available(_)) => Ok(Disposition::Available),
            Ok(OriginalBodyDisposition::Skipped(_)) => Ok(Disposition::Skipped),
            Err(BodySyntaxFailure::Operational(error))
                if CurrentBodySyntax::is_unissued_original_grammar(&error) =>
            {
                // A sample of real root headers is context, not a claim to
                // identify which nested production failed to issue a witness.
                let parsed = bound.canonical_statement_storage().parsed();
                let detail = parsed.statements.first().map_or("", |first| first.raw_header.as_str());
                let end = detail.char_indices().nth(120).map_or(detail.len(), |(end, _)| end);
                show("unissued", &detail[..end]);
                let mut roots = 0u32;
                for statement in &parsed.statements {
                    admission.checkpoint().map_err(BodySyntaxFailure::Operational)?;
                    roots |= 1 << root_bucket(&statement.kind);
                }
                Ok(Disposition::Unissued(roots))
            }
            Err(other) => Err(other),
        }
    })
}

fn survey(host: &BuildHost, start: usize, count: usize) -> [usize; 4] {
    let db = host.query_db();
    let state = host.query_state();
    let guard = state.lock().unwrap();
    let snapshot = guard.snapshot.as_ref().expect("actual Original snapshot");
    let archive = snapshot.original_body_census_archive().unwrap();
    survey_archive(db, archive, start, count)
}

fn survey_archive(db: &Arc<QueryDb>, archive: &BodyArchive, start: usize, count: usize) -> [usize; 4] {
    assert!((1..=MAX_WINDOW).contains(&count), "invalid survey window size");
    assert_eq!(archive.source_mapping().initial_environment(), dm_preprocess::InitialEnvironment::OriginalChecker0290);
    assert!(archive.uses_body_queries(db.as_ref()));
    let total = archive.occurrences().len();
    let end = start.checked_add(count).unwrap().min(total);
    assert!(start < end, "window starts beyond actual callable roster");
    let before = db.db.stats(BODY_SYNTAX).computed;
    let mut counts = [0; 4];
    let mut unissued_roots = [0usize; ROOT_NAMES.len()];
    for ordinal in start..end {
        let disposition = inspect(db.as_ref(), archive, ordinal, counts[2] + counts[3] < MAX_EXAMPLES)
            .unwrap_or_else(|error| panic!("Original census stopped at ordinal {ordinal}; prior counts {counts:?}: {error:?}"));
        match disposition {
            Disposition::Available => counts[0] += 1,
            Disposition::Skipped => counts[1] += 1,
            Disposition::Unissued(roots) => {
                counts[2] += 1;
                for (index, count) in unissued_roots.iter_mut().enumerate() {
                    *count += usize::from(roots & (1 << index) != 0);
                }
            }
            Disposition::NativeRejected => counts[3] += 1,
        }
    }
    assert_eq!(db.db.stats(BODY_SYNTAX).computed, before, "survey must not install Kind4 products");
    eprintln!("original.census range={start}..{end} total={total} available={} skipped={} unissued={} native_rejected={}",
        counts[0], counts[1], counts[2], counts[3]);
    for (root, count) in ROOT_NAMES.into_iter().zip(unissued_roots).filter(|(_, count)| *count != 0) {
        eprintln!("original.census unissued_bodies_containing_root={root} count={count}");
    }
    counts
}

// Only the ignored checkout probe needs the compact compound frontend.
// Borrow the same genuine recorder and authenticated body roster as the
// production compact builder, then stop before report or Strict publication.
fn compact_checkout_survey(project: &Path, start: usize, count: usize) -> [usize; 4] {
    let root = project.parent().unwrap();
    let intent = PolicyInputRequest {
        analysis_context: Some(AnalysisContext::OriginalAnalyze0290),
        workspace: Some(WorkspacePolicyRequest {
            root: root.to_path_buf(),
            recursive_roots: vec![root.join("code")],
            configuration: root.join("tools/ci/lint_scopes.toml"),
        }),
        ..Default::default()
    }.admit().unwrap();
    let mut recorder = RecordingInputs::new(FileSystemInputs, 0)
        .with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
    let subject = recorder.issue_original_analysis_subject(&intent).unwrap();
    assert!(subject.matches_request_project(project) && !subject.synthetic());
    let queries = Arc::new(QueryDb::default());
    let settings = Arc::clone(&queries) as Arc<dyn SettingExpressionQueries>;
    let provider = recorder.original_batch_view(None);
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let seed = dm_tree::checker_builtins::original_analysis_seed().unwrap();
    let frontend = dm_tree::frontend::build_for_original_compound_with_callable_anchors_checked(
        subject.project(), &provider, &Default::default(),
        FrontendConfig { workers: executor.workers(), engine: Some(seed.frontend_seed()), observer: None },
        None, &executor, None, &settings, None,
    ).unwrap().with_body_queries(Arc::clone(&queries) as Arc<dyn BodySyntaxQueries>).unwrap();
    let view = frontend.source_view().unwrap();
    assert_eq!(view.original_analysis_completeness(), Some(OriginalAnalysisCompleteness::Complete));
    subject.bind_frontend(&view).unwrap();
    recorder.diagnostic_source_evidence(&view).unwrap().check(view.mapping()).unwrap();
    assert!(view.archive().matches_tree(view.tree()));
    assert!(Arc::ptr_eq(view.archive().source_mapping(), view.mapping()));
    survey_archive(&queries, view.archive(), start, count)
}

#[test]
fn actual_original_census_classifies_issued_skipped_and_unissued_without_kind4() {
    let root = crate::test_scratch::dir("original-body-census-control");
    let project = root.join("deepquarry.dme");
    std::fs::create_dir(root.join("code")).unwrap();
    std::fs::write(&project, "#include \"code/probe.dm\"\n").unwrap();
    std::fs::write(root.join("code/probe.dm"), concat!(
        "/proc/available()\n    return 1\n",
        "/proc/skipped(argument)\n    return argument +\n",
        "/proc/unissued(argument)\n    return (1 +)\n",
    )).unwrap();
    let host = prepare(&project);
    assert_eq!(survey(&host, 0, 3), [1, 1, 1, 0]);
    assert_eq!(compact_checkout_survey(&project, 0, 3), [1, 1, 1, 0]);
    let state = host.query_state();
    let guard = state.lock().unwrap();
    let archive = guard.snapshot.as_ref().unwrap().original_body_census_archive().unwrap();
    let copied_message = io::Error::new(io::ErrorKind::Unsupported,
        "genuine original per-body grammar outcome is not issued for this syntax");
    assert!(!CurrentBodySyntax::is_unissued_original_grammar(&copied_message));
    let foreign = QueryDb::default();
    assert!(matches!(inspect(&foreign, archive, 0, false),
        Err(BodySyntaxFailure::Operational(error)) if error.kind() == io::ErrorKind::InvalidData));
    assert_eq!(foreign.db.stats(BODY_SYNTAX).computed, 0);
}

#[test]
#[ignore = "explicit whole-project preparation for a bounded Original grammar census"]
fn authenticated_original_checkout_body_syntax_census() {
    let project = std::path::PathBuf::from(std::env::var_os("DMB_ORIGINAL_CENSUS_PROJECT").expect("absolute DME path"));
    assert!(project.is_absolute());
    let start = std::env::var("DMB_ORIGINAL_CENSUS_START").map_or(0, |value| value.parse().unwrap());
    let count = std::env::var("DMB_ORIGINAL_CENSUS_COUNT").map_or(128, |value| value.parse().unwrap());
    assert!((1..=MAX_WINDOW).contains(&count), "invalid survey window size");
    std::thread::Builder::new().stack_size(dm_exec::COMPILER_STACK_BYTES)
        .spawn(move || {
            use crate::daemon::control::{bind_with_deadline, Cancellation};
            use std::time::{Duration, Instant};
            let _deadline = bind_with_deadline(Cancellation::default(), Instant::now() + Duration::from_secs(300));
            compact_checkout_survey(&project, start, count);
        }).unwrap().join().unwrap();
}
