//! Opt-in survey of the existing Original parser, after one actual host capture.
//! The survey never installs its body products or publishes policy reports.
use super::*;
use super::super::purity::REPORT;
use crate::{
    input_snapshot::{FileSystemInputs, RecordingInputs},
    policy_request::{AnalysisContext, PolicyInputRequest, WorkspacePolicyRequest},


};
#[cfg(test)]
use crate::{policy_request::{PolicyInputFile, PolicyInputRole}, request::{BuildOutcome, Command}, runner_host::BuildHost};
use dm_tree::frontend::{BodyArchive, CurrentBodySyntax, OriginalBodyDisposition,
    BodySyntaxQueries, FrontendConfig, OriginalAnalysisCompleteness, SettingExpressionQueries};
use dm_syntax::StatementKind;
use std::{io, path::Path};

const MAX_WINDOW: usize = 1024;
const MAX_EXAMPLES: usize = 32;

#[derive(Clone,Copy,Eq,PartialEq)]enum CensusContract{Original0290,NativeIntrinsic}
impl CensusContract{fn label(self)->&'static str{match self{Self::Original0290=>"original",Self::NativeIntrinsic=>"native_intrinsic"}}}
#[derive(Clone, Copy)]
enum Order {
    #[cfg(test)]
    Archive,
    Checker,
}

impl Order {
    fn label(self) -> &'static str {
        match self {
            #[cfg(test)]
            Self::Archive => "archive_ordinal",
            Self::Checker => "checker_rank",
        }
    }
}

#[derive(Default)]
struct Examples {
    total: usize,
    roots: [usize; ROOT_NAMES.len()],
    native_rejected: usize,
}

impl Examples {
    fn include(&mut self, roots: Option<u32>) -> bool {
        if self.total == MAX_EXAMPLES { return false; }
        if let Some(roots) = roots {
            let Some((_, count)) = self.roots.iter_mut().enumerate()
                .filter(|(index, count)| roots & (1u32 << *index) != 0 && **count < 2)
                .min_by_key(|(_, count)| **count)
            else { return false; };
            *count += 1;
        } else {
            if self.native_rejected == 4 { return false; }
            self.native_rejected += 1;
        }
        self.total += 1;
        true
    }
}
const ROOT_NAMES: [&str; 19] = [
    "if", "while", "do_while", "spawn", "set", "for", "switch", "try", "throw",
    "label", "goto", "return", "local", "assignment", "call", "expression", "loop_exit",
    "unsupported", "delete",
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
        StatementKind::Delete(_) => 18,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Disposition {
    Available,
    Skipped,
    Unissued(u32),
    NativeRejected,
    NativeComplete,NativeRecovered,NativeDeferred,NativeNotCovered,
}

fn invalid(message: &str) -> BodySyntaxFailure {
    BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::InvalidData, message))
}

#[cfg(test)]
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
    rank: Option<usize>,
    examples: &mut Examples,
) -> Result<Disposition, BodySyntaxFailure> {
    inspect_contract(db,archive,ordinal,rank,examples,CensusContract::Original0290)
}
fn inspect_contract(db:&QueryDb,archive:&BodyArchive,ordinal:usize,rank:Option<usize>,examples:&mut Examples,contract:CensusContract)->Result<Disposition,BodySyntaxFailure>{
    let occurrence = archive.occurrences().get(ordinal).ok_or_else(|| invalid("missing archive body ordinal"))?;
    let input = archive.syntax_inputs()
        .and_then(|inputs| inputs.get(ordinal))
        .ok_or_else(|| invalid("missing archive-issued BODY input"))?;
    if !archive.uses_body_queries(db) {
        return Err(invalid("census BODY owner differs"));
    }
    let show = |reason: &str, detail: &str| {
        eprintln!("original.census rank={rank:?} ordinal={ordinal} file={} line={} result={reason} detail={detail:?}",
            occurrence.source.semantic_path, occurrence.source.line);
    };
    db.with_setting_admission(|admission| {
        // Same producer and budget as Kind4; keep only one body product alive
        // and do not prepare or populate any graph rows for the census.
        let product = input.parse_original_product_with_setting_admission(admission)?;
        if let Some(diagnostic) = product.bind_error(input)? {
            if examples.include(None) { show("native_rejected", &diagnostic.message); }
            return Ok(Disposition::NativeRejected);
        }
        let syntax = product.parsed().ok_or_else(|| invalid("BODY producer supplied no parse or rejection"))?;
        let bound = input.bind_original_product_checked(syntax, admission)?;
        if bound.body_span() != occurrence.expanded_span {
            return Err(invalid("census current BODY occurrence differs"));
        }
        if contract==CensusContract::NativeIntrinsic{
            use dm_tree::frontend::NativeBodyDisposition as Native;
            let result=match bound.native_code_disposition_using(admission)?{
                Native::Complete(grant)=>{if !grant.belongs_to(&bound){return Err(invalid("native census current grant owner differs"))}Disposition::NativeComplete},
                Native::Recovered=>Disposition::NativeRecovered,Native::Deferred=>Disposition::NativeDeferred,Native::NotCovered=>Disposition::NativeNotCovered,
            };
            if result!=Disposition::NativeComplete&&examples.include(None){
                eprintln!("native_intrinsic.census rank={rank:?} ordinal={ordinal} file={} line={} result={result:?}",
                    occurrence.source.semantic_path,occurrence.source.line);
            }
            return Ok(result)
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
                let mut roots = 0u32;
                for statement in &parsed.statements {
                    admission.checkpoint().map_err(BodySyntaxFailure::Operational)?;
                    roots |= 1 << root_bucket(&statement.kind);
                }
                if examples.include(Some(roots)) {
                    for statement in parsed.statements.iter().take(3) {
                        let detail = &statement.raw_header;
                        let end = detail.char_indices().nth(120).map_or(detail.len(), |(end, _)| end);
                        show("unissued", &detail[..end]);
                    }
                }
                Ok(Disposition::Unissued(roots))
            }
            Err(other) => Err(other),
        }
    })
}

#[cfg(test)]
fn survey(host: &BuildHost, start: usize, count: usize) -> [usize; 4] {
    let db = host.query_db();
    let state = host.query_state();
    let guard = state.lock().unwrap();
    let snapshot = guard.snapshot.as_ref().expect("actual Original snapshot");
    let archive = snapshot.original_body_census_archive().unwrap();
    survey_archive(db, archive, start, count, Order::Archive, false)
}

fn survey_archive(
    db: &Arc<QueryDb>, archive: &BodyArchive, start: usize, count: usize, order: Order,
    continue_after_oom: bool,
) -> [usize; 4] {
    let all=survey_archive_contract(db,archive,start,count,order,continue_after_oom,CensusContract::Original0290);
    [all[0],all[1],all[2],all[3]]
}
fn survey_archive_contract(db:&Arc<QueryDb>,archive:&BodyArchive,start:usize,count:usize,order:Order,continue_after_oom:bool,contract:CensusContract)->[usize;5]{
    assert!((1..=MAX_WINDOW).contains(&count), "invalid survey window size");
    assert_eq!(archive.source_mapping().initial_environment(), dm_preprocess::InitialEnvironment::OriginalChecker0290);
    assert!(archive.uses_body_queries(db.as_ref()));
    let total = archive.occurrences().len();
    let end = start.checked_add(count).unwrap().min(total);
    assert!(start < end, "window starts beyond actual callable roster");
    let before = db.db.stats(BODY_SYNTAX).computed;
    let report_before = db.db.stats(REPORT).computed;
    let mut ordinals = [0; MAX_WINDOW];
    let ordinals = &mut ordinals[..end - start];
    match order {
        #[cfg(test)]
        Order::Archive => ordinals.iter_mut().zip(start..end).for_each(|(slot, ordinal)| *slot = ordinal),
        Order::Checker => db.checker_order_window_for_census(archive, start, ordinals).unwrap(),
    }
    let mut counts = [0; 5];
    let mut unissued_roots = [0usize; ROOT_NAMES.len()];
    let mut examples = Examples::default();
    let mut unmeasured_oom = 0;
    let syntax = db.policy_syntax_counter();
    use std::sync::atomic::Ordering;
    for (index, &ordinal) in ordinals.iter().enumerate() {
        let rank = match order {
            #[cfg(test)]
            Order::Archive => None,
            Order::Checker => Some(start + index),
        };
        let retained_before = syntax.load(Ordering::Acquire);
        let disposition = match inspect_contract(db.as_ref(), archive, ordinal, rank, &mut examples,contract) {
            Ok(disposition) => disposition,
            Err(BodySyntaxFailure::Operational(error))
                if continue_after_oom && error.kind() == io::ErrorKind::OutOfMemory =>
            {
                let retained_after = syntax.load(Ordering::Acquire);
                assert!(retained_after <= retained_before, "failed census body retained syntax storage");
                crate::daemon::control::checkpoint().unwrap();
                let occurrence = &archive.occurrences()[ordinal];
                let span = occurrence.expanded_span;
                eprintln!("original.census rank={rank:?} ordinal={ordinal} file={} line={} result=unmeasured_oom body_bytes={} retained_before={retained_before} retained_after={retained_after} error={error}",
                    occurrence.source.semantic_path, occurrence.source.line, span.end - span.start);
                unmeasured_oom += 1;
                continue;
            }
            Err(error) => {
                if contract==CensusContract::NativeIntrinsic{panic!("Native intrinsic census stopped at rank {rank:?}, ordinal {ordinal}; prior counts {counts:?}: {error:?}")}
                panic!("Original census stopped at rank {rank:?}, ordinal {ordinal}; prior counts {counts:?}: {error:?}")
            },
        };
        match disposition {
            Disposition::Available => counts[0] += 1,
            Disposition::Skipped => counts[1] += 1,
            Disposition::Unissued(roots) => {
                counts[2] += 1;
                for (index, count) in unissued_roots.iter_mut().enumerate() {
                    *count += usize::from(roots & (1 << index) != 0);
                }
            }
            Disposition::NativeRejected => counts[if contract==CensusContract::NativeIntrinsic{4}else{3}] += 1,
            Disposition::NativeComplete=>counts[0]+=1,Disposition::NativeRecovered=>counts[1]+=1,
            Disposition::NativeDeferred=>counts[2]+=1,Disposition::NativeNotCovered=>counts[3]+=1,
        }
    }
    assert_eq!(db.db.stats(BODY_SYNTAX).computed, before, "survey must not install Kind4 products");
    assert_eq!(db.db.stats(REPORT).computed, report_before, "survey must not compute reports");
    assert_eq!(counts.iter().sum::<usize>() + unmeasured_oom, ordinals.len());
    if contract==CensusContract::NativeIntrinsic{
        eprintln!("native_intrinsic.census coordinate={} range={start}..{end} total={total} complete={} recovered={} deferred={} unsupported_or_not_issued={} native_rejected={} unmeasured_oom={unmeasured_oom} actual_initial_environment=OriginalChecker0290 pinned_parity=false",
            order.label(),counts[0],counts[1],counts[2],counts[3],counts[4]);
    }else{
    eprintln!("original.census coordinate={} range={start}..{end} total={total} available={} skipped={} unissued={} native_rejected={} unmeasured_oom={unmeasured_oom}",
        order.label(), counts[0], counts[1], counts[2], counts[3]);
    for (root, count) in ROOT_NAMES.into_iter().zip(unissued_roots).filter(|(_, count)| *count != 0) {
        eprintln!("original.census unissued_bodies_containing_root={root} count={count}");
    }
    }
    counts
}

// Only explicit diagnostic surveys use this compact compound frontend.
// Borrow the same genuine recorder and authenticated body roster as the
// production compact builder, then stop before report or Strict publication.
fn compact_checkout_survey(
    project: &Path, start: usize, count: usize, order: Order, continue_after_oom: bool,
) -> [usize; 4] {
    let all=compact_checkout_survey_contract(project,start,count,order,continue_after_oom,CensusContract::Original0290);
    [all[0],all[1],all[2],all[3]]
}
fn compact_checkout_survey_contract(project:&Path,start:usize,count:usize,order:Order,continue_after_oom:bool,contract:CensusContract)->[usize;5]{
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
    survey_archive_contract(&queries, view.archive(), start, count, order, continue_after_oom,contract)
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
    assert_eq!(compact_checkout_survey(&project, 0, 3, Order::Checker, false), [1, 1, 1, 0]);
    let state = host.query_state();
    let guard = state.lock().unwrap();
    let archive = guard.snapshot.as_ref().unwrap().original_body_census_archive().unwrap();
    let copied_message = io::Error::new(io::ErrorKind::Unsupported,
        "genuine original per-body grammar outcome is not issued for this syntax");
    assert!(!CurrentBodySyntax::is_unissued_original_grammar(&copied_message));
    let foreign = QueryDb::default();
    assert!(matches!(inspect(&foreign, archive, 0, None, &mut Examples::default()),
        Err(BodySyntaxFailure::Operational(error)) if error.kind() == io::ErrorKind::InvalidData));
    assert_eq!(foreign.db.stats(BODY_SYNTAX).computed, 0);
}

#[test]
fn compact_census_checker_rank_can_differ_from_archive_ordinal() {
    let root = crate::test_scratch::dir("original-body-census-checker-rank");
    std::fs::create_dir(root.join("code")).unwrap();
    let project = root.join("deepquarry.dme");
    std::fs::write(&project, "#include \"code/probe.dm\"\n").unwrap();
    std::fs::write(root.join("code/probe.dm"), concat!(
        "/datum/z/proc/available()\n    return 1\n",
        "/datum/a/proc/unissued()\n    return (1 +)\n",
    )).unwrap();
    assert_eq!(compact_checkout_survey(&project, 0, 1, Order::Archive, false), [1, 0, 0, 0]);
    assert_eq!(compact_checkout_survey(&project, 0, 1, Order::Checker, false), [0, 0, 1, 0]);
}

#[test]
#[ignore = "explicit whole-project preparation for a bounded Original grammar census"]
fn authenticated_original_checkout_body_syntax_census() {
    let project = std::path::PathBuf::from(std::env::var_os("DMB_ORIGINAL_CENSUS_PROJECT").expect("absolute DME path"));
    assert!(project.is_absolute());
    let start = std::env::var("DMB_ORIGINAL_CENSUS_START").map_or(0, |value| value.parse().unwrap());
    let count = std::env::var("DMB_ORIGINAL_CENSUS_COUNT").map_or(128, |value| value.parse().unwrap());
    let order = match std::env::var("DMB_ORIGINAL_CENSUS_ORDER").as_deref() {
        Ok("archive") => Order::Archive,
        Ok("checker") | Err(std::env::VarError::NotPresent) => Order::Checker,
        _ => panic!("DMB_ORIGINAL_CENSUS_ORDER must be checker or archive"),
    };
    assert!((1..=MAX_WINDOW).contains(&count), "invalid survey window size");
    let continue_after_oom = std::env::var_os("DMB_ORIGINAL_CENSUS_CONTINUE_AFTER_OOM").is_some();
    std::thread::Builder::new().stack_size(dm_exec::COMPILER_STACK_BYTES)
        .spawn(move || {
            use crate::daemon::control::{bind_with_deadline, Cancellation};
            use std::time::{Duration, Instant};
            let _deadline = bind_with_deadline(Cancellation::default(), Instant::now() + Duration::from_secs(300));
            compact_checkout_survey(&project, start, count, order, continue_after_oom);
        }).unwrap().join().unwrap();
}

/// Hidden diagnostic only. Uses the exact same source-authenticated survey as
/// the existing ignored test, never a report, graph or publication operation.
pub(crate) fn run_current_cli(project: std::path::PathBuf, start: usize, count: usize) -> Result<(), String> {
    run_contract_cli(project,start,count,CensusContract::Original0290)
}
pub(crate) fn run_native_cli(project:std::path::PathBuf,start:usize,count:usize)->Result<(),String>{
    run_contract_cli(project,start,count,CensusContract::NativeIntrinsic)
}
fn run_contract_cli(project:std::path::PathBuf,start:usize,count:usize,contract:CensusContract)->Result<(),String>{
    if !project.is_absolute() || !(1..=MAX_WINDOW).contains(&count) || start.checked_add(count).is_none() {
        return Err("invalid bounded Original grammar census request".into());
    }
    let worker = std::thread::Builder::new().name(format!("{}-grammar-census",contract.label()))
        .stack_size(dm_exec::COMPILER_STACK_BYTES).spawn(move || {
            use crate::daemon::control::{bind_with_deadline, Cancellation};
            use std::time::{Duration, Instant};
            let _deadline = bind_with_deadline(Cancellation::default(), Instant::now() + Duration::from_secs(300));
            // No CLI or environment opt-out for operational errors. This shared
            // implementation classifies only the nominal missing-witness cause.
            compact_checkout_survey_contract(&project, start, count, Order::Checker, false,contract);
        }).map_err(|error| error.to_string())?;
    worker.join().map_err(|cause| {
        if let Some(message) = cause.downcast_ref::<String>() { message.clone() }
        else if let Some(message) = cause.downcast_ref::<&str>() { (*message).to_owned() }
        else { "Original grammar census failed; no report or publication produced".into() }
    })
}

#[test]
fn actual_native_census_separates_same_parser_completion_recovery_and_deferred_children(){
    let root=crate::test_scratch::dir("native-intrinsic-census-control");
    std::fs::create_dir(root.join("code")).unwrap();let project=root.join("deepquarry.dme");
    std::fs::write(&project,"#include \"code/probe.dm\"\n").unwrap();
    std::fs::write(root.join("code/probe.dm"),concat!(
      "/proc/a()\n    return 1\n",
      "/proc/b(value)\n    return value +\n",
      "/proc/c(size)\n    var/list/items[size]\n    return 0\n",
    )).unwrap();
    let actual=compact_checkout_survey_contract(&project,0,3,Order::Checker,false,CensusContract::NativeIntrinsic);
    assert_eq!(actual,[1,1,1,0,0],"actual same parser; native recovery is not Original skipped, local dimension DATA is deferred");
}
