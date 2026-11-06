//! Small real public frontend/report target. No daemon, compiler or alternate parser.
#[path="../../../shared/test_scratch.rs"]mod scratch;
#[path="../../../../analyze/fixtures/report_configuration.rs"]mod report_configuration;
use std::{path::{Path,PathBuf},collections::BTreeMap,io::{self,Write},sync::Arc};
use dmbc::input_snapshot::{RecordingInputs,FileSystemInputs};
use dm_preprocess::{SourceProvider,SourceAcquisitionLease,source_arena_credit::SourceArenaWork};
use dm_tree::frontend::{self,OriginalDiagnosticPoint,FrontendConfig};
// Safe concrete Sync loan of this SAME recorder, not a second store or parser.
struct Inputs(RecordingInputs<FileSystemInputs>);
impl SourceProvider for Inputs{
 fn original_batch_source(&self)->io::Result<Option<&(dyn SourceProvider+Sync)>>{Ok(Some(self))}
 fn initial_environment(&self)->dm_preprocess::InitialEnvironment{self.0.initial_environment()}
 fn read(&self,p:&Path)->Result<String,String>{SourceProvider::read(&self.0,p)}
 fn path_presence_admitted(&self,p:&Path,w:&dyn SourceArenaWork)->io::Result<bool>{self.0.path_presence_admitted(p,w)}
 fn original_raw_source_open_admitted(&self,p:&Path,max:usize,w:&dyn SourceArenaWork,after:&mut dyn FnMut()->io::Result<dm_preprocess::OriginalRawOpenDecision>,before:&mut dyn FnMut(usize)->io::Result<()>,decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->io::Result<()>,acquired:&mut dyn FnMut(&SourceAcquisitionLease)->io::Result<()>)->io::Result<dm_preprocess::OriginalRawReadOutcome>{self.0.original_raw_source_open_admitted(p,max,w,after,before,decode,acquired)}
 fn original_source_bytes<'a>(&'a self,l:&'a SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{self.0.original_source_bytes(l)}
}
fn put(root:&Path,p:&str,text:impl AsRef<[u8]>){let p=root.join(p);std::fs::create_dir_all(p.parent().unwrap()).unwrap();std::fs::write(p,text).unwrap();}
fn fixture(label:&str)->PathBuf{let root=scratch::dir(label);put(&root,"deepquarry.dme","#include \"code/child.dm\"\n#error ROOT_ERROR\n/datum/after\n");put(&root,"code/child.dm","#warn CHILD_WARNING\n/datum/child\n");root}
fn prepare(root:&Path)->frontend::DiagnosticFrontend {
    prepare_using(root, &Arc::new(dmbc::query_db::QueryDb::default()))
}

fn prepare_using(root:&Path, db:&Arc<dmbc::query_db::QueryDb>)->frontend::DiagnosticFrontend {
    let inputs = Inputs(RecordingInputs::new(FileSystemInputs, 0)
        .with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290));
    let settings: Arc<dyn frontend::SettingExpressionQueries> = db.clone();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let seed = dm_tree::checker_builtins::original_analysis_seed().unwrap();
    frontend::build_for_original_analysis_with_state_checked(
        &root.join("deepquarry.dme"), &inputs, &BTreeMap::new(),
        FrontendConfig { workers:1, engine:Some(seed.frontend_seed()), observer:None },
        None, &executor, None, &settings,
    ).unwrap()
}
#[test]fn actual_frontend_raw_notices_preserve_owner_order_byte_points_and_public_report(){
 let root=fixture("original-rich-notice-report");let frontend=prepare(&root);let view=frontend.source_view().unwrap();let notices=view.original_preprocess_notices().expect("actual restricted notice owner");let rows=notices.iter().collect::<Result<Vec<_>,_>>().unwrap();
 assert_eq!(rows.len(),2);assert!(rows[0].message.contains("CHILD_WARNING"));assert!(rows[1].message.contains("ROOT_ERROR"));assert_eq!(rows[0].severity,dm_preprocess::regions::OriginalNoticeSeverity::Warning);assert_eq!(rows[1].severity,dm_preprocess::regions::OriginalNoticeSeverity::Error);
 for (i,row)in rows.iter().enumerate(){let OriginalDiagnosticPoint::Acquired{occurrence,source_path,reported_path,acquisition,line,byte_column,raw_span}=row.point else{panic!("actual physical directive cannot become builtin/default")};assert_eq!(line,if i==0{1}else{2});assert!(byte_column>0);assert!(raw_span.is_none(),"directive without an emitted token must not gain an expanded span");assert!(source_path.ends_with(if i==0{"code/child.dm"}else{"deepquarry.dme"}));assert!(!reported_path.as_os_str().is_empty());assert!(view.mapping().source_acquisition(occurrence).unwrap().same_binding(acquisition));}
 let mut bytes=Vec::new();dmbc::diagnostics::begin(Default::default());dmbc::diagnostics::write_original_preprocess_notices(&mut bytes,&notices).unwrap();let text=String::from_utf8(bytes).unwrap();assert!(text.find("CHILD_WARNING").unwrap()<text.find("ROOT_ERROR").unwrap());assert!(text.contains(":warning"));assert!(text.contains(":error"));assert_eq!(dmbc::diagnostics::tally().errors,1);assert_eq!(dmbc::diagnostics::tally().warnings,1);
 drop(rows);drop(notices);drop(view);assert!(frontend.try_into_compilable().is_err(),"printing actual diagnostics cannot promote the restricted plan");
}
struct FailedWrite;impl Write for FailedWrite{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{panic!("first real write failure must return immediately")}}
#[test]fn real_notice_report_preserves_first_operational_output_error(){let root=fixture("original-rich-notice-output-failure");let frontend=prepare(&root);let view=frontend.source_view().unwrap();let notices=view.original_preprocess_notices().unwrap();assert_eq!(dmbc::diagnostics::write_original_preprocess_notices(&mut FailedWrite,&notices).unwrap_err().raw_os_error(),Some(1450));}
#[test]fn actual_public_prepare_request_presents_original_directive_diagnostics_before_publication(){
 use dmbc::{policy_request::{AnalysisContext,PolicyInputRequest,WorkspacePolicyRequest,WorkspaceAuxiliaryQuestion as Q},request::{Command,BuildOutcome},runner_host::BuildHost};
 let root=fixture("original-rich-notice-public-request");put(&root,"tools/ci/lint_scopes.toml",report_configuration::with_overlay(""));let Command::Build(request)=dmbc::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual public preparation")};let mut request=*request;request.no_cache=true;request.exact_inputs=true;request.progress_enabled=false;request.workers=1;request.timeout_seconds=Some(60);request.engine_template=None;request.bootstrap_catalog=false;request.cache_root=Some(root.join("cache"));request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalAnalyze0290),workspace:Some(WorkspacePolicyRequest{root:root.clone(),recursive_roots:vec![root.join("code")],configuration:root.join("tools/ci/lint_scopes.toml")}),workspace_auxiliary:vec![Q::DerivedReads],..Default::default()});let mut host=BuildHost::default();let result=dmbc::request_runner::run_build_with_host(request,&mut host).unwrap();assert!(matches!(result,BuildOutcome::QueryPrepared{..}),"real source diagnostics keep the old diagnostic model, not a false compiler receipt");let tally=dmbc::diagnostics::tally();assert!(tally.errors>=1,"actual request path must render ROOT_ERROR");assert!(tally.warnings>=1,"actual request path must render CHILD_WARNING");assert!(!root.join("deepquarry.dmb").exists());
}

#[test]fn actual_duplicate_include_retains_warning_code_and_previous_include_note_in_order(){
 let root=fixture("original-rich-notice-include-notes");put(&root,"deepquarry.dme","#include \"code/child.dm\"\n#include \"code/child.dm\"\n#error ROOT_ERROR\n/datum/after\n");let frontend=prepare(&root);let view=frontend.source_view().unwrap();let notices=view.original_preprocess_notices().unwrap();let mut rows=notices.iter();assert!(rows.next().unwrap().unwrap().message.contains("CHILD_WARNING"));let duplicate=rows.next().unwrap().unwrap();assert_eq!(duplicate.error_type,Some("duplicate_include"));let OriginalDiagnosticPoint::Acquired{line,..}=duplicate.point else{panic!("duplicate at actual main occurrence")};assert_eq!(line,2);let mut notes=duplicate.notes;let(point,text)=notes.next().unwrap().unwrap();assert_eq!(text,"previously included here");assert!(matches!(point,OriginalDiagnosticPoint::Acquired{line:1,..}));assert!(notes.next().is_none());assert!(rows.next().unwrap().unwrap().message.contains("ROOT_ERROR"));assert!(rows.next().is_none());let mut output=Vec::new();dmbc::diagnostics::write_original_preprocess_notices(&mut output,&notices).unwrap();let output=String::from_utf8(output).unwrap();assert!(output.contains(":warning (duplicate_include):"));assert!(output.contains(":note: previously included here"));assert!(output.find("previously included here").unwrap()<output.find("ROOT_ERROR").unwrap());
}
#[test]fn actual_builtin_redefinition_note_does_not_acquire_a_fake_file_or_expanded_span(){
 let root=scratch::dir("original-rich-notice-builtin-note");put(&root,"deepquarry.dme","#define TRUE 2\n/datum/after\n");let frontend=prepare(&root);let view=frontend.source_view().unwrap();let notices=view.original_preprocess_notices().unwrap();let row=notices.iter().next().unwrap().unwrap();assert_eq!(row.error_type,Some("macro_redefined"));let mut notes=row.notes;let(point,text)=notes.next().unwrap().unwrap();assert!(matches!(point,OriginalDiagnosticPoint::Builtins));assert_eq!(text,"previous definition of TRUE");assert!(notes.next().is_none());let mut output=Vec::new();dmbc::diagnostics::write_original_preprocess_notices(&mut output,&notices).unwrap();assert!(String::from_utf8(output).unwrap().contains("(builtins):1:1:note: previous definition of TRUE"));
}

#[test]fn actual_analyze_primary_prefix_keeps_producer_notice_without_expanded_token_or_full_role(){
 let root=scratch::dir("original-rich-notice-primary-prefix");put(&root,"deepquarry.dme","/proc/p(var/A=)\n#error ACTUAL_LOOKAHEAD_NOTICE\n/datum/never_parsed\n");let frontend=prepare(&root);let view=frontend.source_view().unwrap();assert_eq!(view.preparation_purpose(),frontend::DiagnosticPreparationPurpose::OriginalAnalyzePrefix);assert_eq!(view.original_analysis_completeness(),Some(frontend::OriginalAnalysisCompleteness::PrimaryPrefix));
 let notices=view.original_preprocess_notices().unwrap();let row=notices.iter().find_map(|row|{let row=row.unwrap();row.message.contains("ACTUAL_LOOKAHEAD_NOTICE").then_some(row)}).expect("actual short Analyze batch preprocessing finishes before parser's primary stop");assert_eq!(row.severity,dm_preprocess::regions::OriginalNoticeSeverity::Error);assert!(matches!(row.point,OriginalDiagnosticPoint::Acquired{line:2,raw_span:None,..}));let mut bytes=Vec::new();dmbc::diagnostics::write_original_preprocess_notices(&mut bytes,&notices).unwrap();assert!(String::from_utf8(bytes).unwrap().contains("ACTUAL_LOOKAHEAD_NOTICE"));drop(row);drop(notices);drop(view);assert!(frontend.checker_source_view().is_err());assert!(frontend.try_into_compilable().is_err());
}

#[test]fn actual_strict_checker_fatal_retains_raw_prefix_after_provider_and_host_drop(){
 let root=scratch::dir("original-strict-fatal-raw-owner");put(&root,"deepquarry.dme","#warn EARLY_ACTUAL_NOTICE\n/proc/p(var/A=)\n#error MUST_REMAIN_UNPULLED\n");
 let report={let inputs=Inputs(RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290));let db:Arc<dyn frontend::SettingExpressionQueries>=Arc::new(dmbc::query_db::QueryDb::default());let executor=dm_exec::BuildExecutor::new(1).unwrap();let seed=dm_tree::checker_builtins::original_analysis_seed().unwrap();let result=frontend::build_for_checker_diagnostics_with_state_checked(&root.join("deepquarry.dme"),&inputs,&BTreeMap::new(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&db);match result{Err(frontend::FrontendBuildFailure::Diagnostics(report))=>report,Err(frontend::FrontendBuildFailure::Operational(error))=>panic!("strict actual source fatal must keep original report: {error:?}"),Ok(_)=>panic!("malformed formal cannot issue a strict graph")}};
 let formal=frontend::original_fatal_preparation_outcome(&report).expect("same actual native formal fatal");assert_eq!(formal.location().1,2);assert!(!formal.compiler_admissible());assert!(!formal.continues_analysis());assert!(report.is_retained());let notices=report.original_preprocess_notices().expect("same genuine failed preparation's retained raw owner");assert_eq!(notices.len(),1,"lazy Checker must never pull the following#error merely to report it");let row=notices.iter().next().unwrap().unwrap();assert!(row.message.contains("EARLY_ACTUAL_NOTICE"));assert!(matches!(row.point,OriginalDiagnosticPoint::Acquired{line:1,raw_span:None,..}));let mut out=Vec::new();dmbc::diagnostics::write_original_preprocess_notices(&mut out,&notices).unwrap();dmbc::diagnostics::write_diagnostics(&mut out,&report).unwrap();let out=String::from_utf8(out).unwrap();assert!(out.contains("EARLY_ACTUAL_NOTICE"));assert!(!out.contains("MUST_REMAIN_UNPULLED"));assert_eq!(dmbc::diagnostics::write_original_preprocess_notices(&mut FailedWrite,&notices).unwrap_err().raw_os_error(),Some(1450));drop(row);drop(notices);drop(formal);assert!(report.into_legacy().is_err(),"raw owner and funded output cannot be extracted to an uncharged Vec");
}
#[test]fn actual_public_strict_fatal_presents_prior_raw_notice_before_returning_original_failure(){
 use dmbc::{policy_request::{AnalysisContext,PolicyInputRequest},request::Command,runner_host::BuildHost};let root=scratch::dir("original-strict-fatal-public-output");put(&root,"deepquarry.dme","#warn PRIOR_RAW_WARNING\n/proc/p(var/A=)\n#error UNREQUESTED\n");let Command::Build(request)=dmbc::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("actual public checker preparation")};let mut request=*request;request.no_cache=true;request.exact_inputs=true;request.progress_enabled=false;request.workers=1;request.timeout_seconds=Some(60);request.engine_template=None;request.bootstrap_catalog=false;request.cache_root=Some(root.join("cache"));request.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalChecker0290),..Default::default()});let mut host=BuildHost::default();let error=dmbc::request_runner::run_build_with_host(request,&mut host).unwrap_err();assert!(error.to_string().contains("expected"),"real formal error must remain the public failure: {error}");assert_eq!(dmbc::diagnostics::tally().warnings,1,"actual prior raw warning must be presented before strict failure is returned");assert!(!root.join("deepquarry.dmb").exists());
}

fn strict_request(root:&Path)->dmbc::request::BuildRequest{use dmbc::{policy_request::{AnalysisContext,PolicyInputRequest},request::Command};let Command::Build(r)=dmbc::cli::parse(&["prepare-query".into(),root.join("deepquarry.dme").to_string_lossy().into_owned()]).unwrap()else{panic!("real strict preparation")};let mut r=*r;r.no_cache=true;r.exact_inputs=true;r.progress_enabled=false;r.workers=1;r.timeout_seconds=Some(60);r.engine_template=None;r.bootstrap_catalog=false;r.cache_root=Some(root.join("cache"));r.policy_inputs=Some(PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalChecker0290),..Default::default()});r}
#[test]fn actual_strict_prepare_to_lends_cold_fatal_diagnostics_to_supplied_writer(){let root=scratch::dir("strict-fatal-output-loan");put(&root,"deepquarry.dme","#warn ACTUAL_COLD_WARNING\n/proc/p(var/A=)\n#error UNPULLED\n");let request=strict_request(&root);let mut bytes=Vec::new();let mut host=dmbc::runner_host::BuildHost::default();let result=dmbc::request_runner::prepare_with_host_to(request,&mut host,&mut bytes).unwrap();let actual=result.preparation.unwrap_err();assert!(actual.to_string().contains("expected"));result.diagnostics.unwrap();let text=String::from_utf8(bytes).unwrap();assert!(text.contains("ACTUAL_COLD_WARNING"));assert!(text.contains("expected"));assert!(!text.contains("UNPULLED"));assert!(text.find("ACTUAL_COLD_WARNING").unwrap()<text.find("expected").unwrap())}
struct CountFailed{calls:usize}impl Write for CountFailed{fn write(&mut self,_:&[u8])->io::Result<usize>{self.calls+=1;Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{self.calls+=1;Err(io::Error::from_raw_os_error(5))}}
#[test]fn actual_strict_prepare_to_preserves_source_failure_separately_from_first_writer_io(){let root=scratch::dir("strict-fatal-first-io");put(&root,"deepquarry.dme","#warn ACTUAL_COLD_WARNING\n/proc/p(var/A=)\n#error UNPULLED\n");let mut output=CountFailed{calls:0};let mut host=dmbc::runner_host::BuildHost::default();let result=dmbc::request_runner::prepare_with_host_to(strict_request(&root),&mut host,&mut output).unwrap();assert!(result.preparation.unwrap_err().to_string().contains("expected"),"actual original fatal cannot be overwritten by later writer IO");assert_eq!(result.diagnostics.unwrap_err().raw_os_error(),Some(1450));assert_eq!(output.calls,1,"no later formal write, flush or BufWriter destructor may retry the failed real sink")}

#[test]
fn actual_formal_physical_end_matches_original_semicolon_and_eof_report() {
    const TERM: &str = "got ';', expected one of: operator, literal, variable, proc call";
    const CLOSE: &str = "got EOF, expected one of: ')', ','";
    const SEMICOLON: &str = "Extraneous ';' in proc parameter";
    const MEMBER: &str = "got ';', expected one of: identifier";
    let cases: &[(&str, &str, usize, usize, &[&str], &str)] = &[
        ("empty-default", "/proc/p(A=", 1, 11, &[], TERM),
        ("missing-close", "/proc/p(A", 1, 10, &[SEMICOLON], CLOSE),
        ("missing-member", "/proc/p(A=world.", 1, 17, &[MEMBER, SEMICOLON], CLOSE),
        ("value-at-end", "/proc/p(A=1", 1, 12, &[SEMICOLON], CLOSE),
        ("missing-annotation", "/proc/p(A as", 1, 13, &[], "got ';', expected one of: '(', identifier"),
        ("newline-empty-default", "/proc/p(A=\n", 2, 1, &[], TERM),
    ];
    for &(label, source, line, column, prior, fatal) in cases {
        let root=scratch::dir(label);
        put(&root,"deepquarry.dme",source);
        let path=root.join("deepquarry.dme");
        let inputs=Inputs(RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290));
        let host:Arc<dyn frontend::SettingExpressionQueries>=Arc::new(dmbc::query_db::QueryDb::default());
        let executor=dm_exec::BuildExecutor::new(1).unwrap();
        let seed=dm_tree::checker_builtins::original_analysis_seed().unwrap();
        let report=match frontend::build_for_checker_diagnostics_with_state_checked(
            &path,&inputs,&BTreeMap::new(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&host,
        ) {
            Err(frontend::FrontendBuildFailure::Diagnostics(report))=>report,
            Err(frontend::FrontendBuildFailure::Operational(error))=>panic!("{label}: actual formal source fatal became operational: {error:?}"),
            Ok(_)=>panic!("{label}: malformed formal issued a complete model"),
        };
        let actual=frontend::original_fatal_preparation_outcome(&report).expect("actual fatal retained");
        assert_eq!(actual.location(),(path.as_path(),line,column),"{label}");
        assert_eq!(actual.message(),fatal,"{label}");
        assert_eq!(actual.prior_notices().count(),prior.len(),"{label}");
        for (row,message) in actual.prior_notices().zip(prior.iter()){ assert_eq!(row.message(),*message,"{label}"); assert_eq!(row.location(),(path.as_path(),line,column),"{label}"); }
        assert!(report.is_retained());
        assert!(!actual.compiler_admissible() && !actual.continues_analysis());
        drop(actual); drop(report);

        let analyzed=prepare(&root);
        assert_eq!(analyzed.preparation_purpose(),frontend::DiagnosticPreparationPurpose::OriginalAnalyzePrefix,"{label}");
        assert!(analyzed.checker_source_view().is_err(),"{label}");
        assert!(analyzed.try_into_compilable().is_err(),"{label}");
    }
}


#[test]
fn actual_original_return_type_path_uses_the_emitted_annotation_tokens() {
    use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver, SymbolId};
    let root = scratch::dir("original-typed-return-adjacency");
    put(&root, "deepquarry.dme",
        "/datum/peer\n/datum/probe/proc/peer() as /datum/peer\n    return null\n");
    let frontend = prepare(&root);
    let view = frontend.source_view().unwrap();
    let archive = view.archive();
    assert!(archive.expanded_source().contains("as/datum/peer"));
    let tree = view.tree();
    let ResolvedMeaning::Members(chain) = Resolver::resolve(tree.as_ref(), ResolveQuery::SourceDeclarationChain {
        owner: SymbolId::of("/datum/probe"), name: SymbolId::of("peer"), verb: false,
    }) else { panic!("actual Original typed return declaration missing") };
    let [ResolvedMeaning::Declaration { data, .. }] = chain.as_ref() else {
        panic!("expected one source declaration");
    };
    let annotation = data.procedure.as_ref().unwrap().signature.return_annotation.as_ref().unwrap();
    let parts = annotation.tokens.iter().map(|token| tree.symbols().text(token.text).unwrap())
        .collect::<Vec<_>>();
    assert_eq!(parts, ["/", "datum", "/", "peer"]);
    let body = archive.parse_checked(0).unwrap();
    assert!(body.statement_body().original_literal_syntax_complete());
    assert!(matches!(
        body.statement_body().parsed().statements.as_slice(),
        [dm_syntax::Statement { kind: dm_syntax::StatementKind::Return(Some(_)), .. }]
    ));
}


#[test]
fn actual_original_return_accepts_joined_issued_prefix_and_literal_tokens() {
    use dm_syntax::{Expr, ExprKind, OriginalTokenValue, Statement, StatementKind};

    let root = scratch::dir("original-joined-return-tokens");
    put(&root, "deepquarry.dme", concat!(
        "/proc/negated(a, b)\n    return !a in (!a & b)\n",
        "/proc/string_value()\n    return \"text\"\n",
        "/proc/resource_value()\n    return 'example.dmi'\n",
        "/proc/interpolated(a)\n    return \"[a]\"\n",
        "/proc/return_identifier(returnValue)\n    returnValue = 2\n    return returnValue\n",
    ));
    let db = Arc::new(dmbc::query_db::QueryDb::default());
    let frontend = prepare_using(&root, &db).with_body_queries(db.clone()).unwrap();
    let view = frontend.source_view().unwrap();
    let archive = view.archive();
    assert_eq!(archive.len(), 5);
    for (ordinal, joined_prefix) in ["return!", "return\"", "return'", "return\"", "returnValue"]
        .into_iter().enumerate()
    {
        let body = archive.parse_checked(ordinal).unwrap();
        let parsed = body.statement_body().parsed();
        assert!(body.statement_body().original_literal_syntax_complete(),
            "{joined_prefix}: diagnostics={:?}, pending={:?}", parsed.diagnostics, parsed.pending_bodies);
        assert!(parsed.statements[0].raw_header.starts_with(joined_prefix), "{:?}", parsed.statements);
        if ordinal == 4 {
            assert!(matches!(parsed.statements.as_slice(), [
                Statement { kind: StatementKind::Assign { .. }, .. },
                Statement { kind: StatementKind::Return(Some(Expr { kind: ExprKind::Ident(name), .. })), .. },
            ] if name == "returnValue"));
            continue;
        }
        let [Statement { kind: StatementKind::Return(Some(value)), .. }] = parsed.statements.as_slice()
            else { panic!("expected one issued return for {joined_prefix}") };
        match (ordinal, &value.kind) {
            (0, ExprKind::Binary { op, lhs, .. }) => {
                assert_eq!(op, "in");
                assert!(matches!(&lhs.kind, ExprKind::Unary { op, .. } if op == "!"));
            }
            (1, ExprKind::Literal(literal)) => {
                assert!(matches!(literal.original_value(), Some(OriginalTokenValue::String("text"))));
            }
            (2, ExprKind::Literal(literal)) => {
                assert!(matches!(literal.original_value(), Some(OriginalTokenValue::Resource("example.dmi"))));
            }
            (3, ExprKind::Literal(literal)) => {
                assert!(matches!(literal.prepared_syntax_parts(), Some(Ok(Some(parts)))
                    if parts.expressions.len() == 1));
            }
            _ => panic!("unexpected return for {joined_prefix}: {value:?}"),
        }
    }
}

#[test]
fn actual_original_inline_procedure_body_precedes_its_synthetic_semicolon() {
    let root = scratch::dir("original-inline-proc-semicolon");
    put(&root, "deepquarry.dme", concat!(
        "/proc/rustg_get_version() return call_ext((__rust_g || __detect_rust_g()), \"get_version\")()\n",
        "/proc/next()\n    return 1\n",
    ));
    let db = Arc::new(dmbc::query_db::QueryDb::default());
    let frontend = prepare_using(&root, &db).with_body_queries(db.clone()).unwrap();
    let view = frontend.source_view().unwrap();
    let archive = view.archive();
    assert_eq!(archive.len(), 2);
    for (ordinal, name) in ["rustg_get_version", "next"].into_iter().enumerate() {
        let identity = archive.callables().identity(ordinal).unwrap();
        assert_eq!(view.tree().symbols().text(identity.name), Some(name));
        let body = archive.parse_checked(ordinal).unwrap();
        assert!(body.statement_body().has_native_literal_syntax());
        let parsed = body.statement_body().parsed();
        assert!(body.statement_body().original_literal_syntax_complete(),
            "{name}: diagnostics={:?}, pending={:?}", parsed.diagnostics, parsed.pending_bodies);
        let [dm_syntax::Statement { kind: dm_syntax::StatementKind::Return(Some(value)), .. }]
            = parsed.statements.as_slice() else { panic!("{name}: expected one return") };
        if ordinal == 0 {
            let dm_syntax::ExprKind::Call { callee, .. } = &value.kind
                else { panic!("expected the chained external call") };
            let dm_syntax::ExprKind::Call { args, .. } = &callee.kind
                else { panic!("expected the external call arguments") };
            assert!(matches!(&args[1].kind, dm_syntax::ExprKind::Literal(literal)
                if matches!(literal.original_value(), Some(dm_syntax::OriginalTokenValue::String("get_version")))));
        }
    }
}


#[test]
fn actual_original_block_doc_keeps_the_next_declaration_at_the_same_scope() {
    let root = scratch::dir("original-block-doc-scope");
    put(&root, "deepquarry.dme", concat!(
        "/proc/before()\n    return 1\n\n",
        "/**\n * The next proc has a format default.\n */\n",
        "/proc/after(format = \"%F\")\n    return format\n",
    ));
    let db = Arc::new(dmbc::query_db::QueryDb::default());
    let frontend = prepare_using(&root, &db).with_body_queries(db.clone()).unwrap();
    let view = frontend.source_view().unwrap();
    let archive = view.archive();
    assert_eq!(archive.len(), 2);
    for (ordinal, name) in ["before", "after"].into_iter().enumerate() {
        let identity = archive.callables().identity(ordinal).unwrap();
        assert_eq!(identity.owner, dm_ir::SymbolId::of("/"));
        assert_eq!(view.tree().symbols().text(identity.name), Some(name));
        let body = archive.parse_checked(ordinal).unwrap();
        assert!(body.statement_body().original_literal_syntax_complete());
    }
}

#[test]
fn original_projected_super_return_keeps_its_issued_member_grammar() {
    let root = scratch::dir("original-projected-super-return");
    put(&root, "deepquarry.dme", "#include \"code/probe.dm\"\n");
    put(&root, "code/probe.dm", concat!(
        "/datum/base/proc/probe()\n    return null\n",
        "/datum/base/child/probe()\n    return ..().field\n",
    ));
    let inputs = Inputs(RecordingInputs::new(FileSystemInputs, 0)
        .with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290));
    let db = Arc::new(dmbc::query_db::QueryDb::default());
    let settings: Arc<dyn frontend::SettingExpressionQueries> = db.clone();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let seed = dm_tree::checker_builtins::original_analysis_seed().unwrap();
    let front = frontend::build_for_checker_diagnostics_with_state_checked(
        &root.join("deepquarry.dme"), &inputs, &BTreeMap::new(),
        FrontendConfig { workers: 1, engine: Some(seed.frontend_seed()), observer: None },
        None, &executor, None, &settings,
    ).unwrap().with_body_queries(db).unwrap();
    let view = front.checker_source_view().unwrap();
    let archive = view.archive();
    let child = dm_ir::SymbolId::of("/datum/base/child");
    let ordinal = (0..archive.len())
        .find(|&ordinal| archive.callables().identity(ordinal).is_some_and(|row| row.owner == child))
        .expect("actual child override");
    let body = archive.parse_checked(ordinal).unwrap();
    let tokens = body.original_body_tokens().unwrap();
    let significant: Vec<_> = tokens
        .tokens(archive.occurrences()[ordinal].expanded_span).unwrap()
        .filter(|(kind, _, _)| !matches!(kind, dm_syntax::TokenKind::Whitespace | dm_syntax::TokenKind::Newline | dm_syntax::TokenKind::Comment))
        .collect();
    let expression = significant.windows(6)
        .find(|rows| rows.iter().map(|(_, _, spelling)| *spelling).eq(["return", "..", "(", ")", ".", "field"]))
        .expect("actual return and single Super token sequence");
    assert_eq!(expression[0].1.end, expression[1].1.start, "projected return and Super are joined");
    assert!(expression[1].1.end < expression[2].1.start, "projected Super and parenthesis are separated");
    let parsed = body.statement_body().parsed();
    assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
    assert!(matches!(&parsed.statements[..], [row] if matches!(&row.kind, dm_syntax::StatementKind::Return(Some(_)))));
    let outcome = parsed.original_grammar.expect("same token body issued Original grammar");
    assert_eq!(outcome.kind(), dm_syntax::OriginalBodyGrammarKind::Available);
    assert_eq!(outcome.statement_span(), Some(parsed.statements[0].header_span));
}

#[test]
fn actual_initialized_class_comma_preserves_original_fatal_and_unregistered_variable() {
    const MESSAGE: &str = "got ',', expected one of: operator, field access, 'as', 'in', ';'";
    let root = scratch::dir("original-initialized-class-comma");
    put(&root, "deepquarry.dme", concat!(
        "/datum/holder\n",
        "    var/kept = 7\n",
        "    var/first = 1, second = 2\n",
        "/proc/later()\n",
        "    return\n",
    ));
    let path = root.join("deepquarry.dme");
    let inputs = Inputs(RecordingInputs::new(FileSystemInputs, 0)
        .with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290));
    let host: Arc<dyn frontend::SettingExpressionQueries> = Arc::new(dmbc::query_db::QueryDb::default());
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let seed = dm_tree::checker_builtins::original_analysis_seed().unwrap();
    let report = match frontend::build_for_checker_diagnostics_with_state_checked(
        &path, &inputs, &BTreeMap::new(),
        FrontendConfig { workers: 1, engine: Some(seed.frontend_seed()), observer: None },
        None, &executor, None, &host,
    ) {
        Err(frontend::FrontendBuildFailure::Diagnostics(report)) => report,
        Err(frontend::FrontendBuildFailure::Operational(error)) => panic!("issued comma became operational: {error:?}"),
        Ok(_) => panic!("initialized comma issued a complete checker model"),
    };
    let fatal = frontend::original_fatal_preparation_outcome(&report).expect("actual initialized comma source fatal");
    assert_eq!((fatal.location().1, fatal.location().2), (3, 18));
    assert_eq!(fatal.message(), MESSAGE);
    assert!(!fatal.compiler_admissible() && !fatal.continues_analysis());
    assert_eq!(fatal.severity(), "error");
    assert_eq!(fatal.notes(), [
        "fatal error: the parser cannot continue", "constant evaluation will be skipped",
    ]);

    let analyzed = prepare(&root);
    assert_eq!(analyzed.preparation_purpose(), frontend::DiagnosticPreparationPurpose::OriginalAnalyzePrefix);
    assert!(analyzed.checker_source_view().is_err());
    let view = analyzed.source_view().unwrap();
    let tree = view.tree();
    let has_member = |owner, name| tree.members().iter().any(|member| {
        tree.type_node(member.owner).is_some_and(|node| node.path == dm_ir::SymbolId::of(owner))
            && member.name == dm_ir::SymbolId::of(name)
    });
    assert!(has_member("/datum/holder", "kept"));
    assert!(!has_member("/datum/holder", "first"));
    assert!(!has_member("/datum/holder", "second"));
    assert!(!has_member("/", "later"));
}

#[test]
fn actual_original_contentless_reference_delimiter_keeps_dme_eof_and_authored_source_distinct() {
    const HEADER: &str = "/datum/queues_other\n    var/datum/prior\n";
    for (case, declaration, next, expected_file, expected_line, terminal_eof) in [
        ("scalar-eof", "var/datum/terminal", false, "deepquarry.dme", 2, true),
        ("private-eof", "var/SpacemanDMM_private/datum/terminal", false, "deepquarry.dme", 2, true),
        ("list-eof", "var/list/datum/terminal", false, "deepquarry.dme", 2, true),
        ("scalar-initialized", "var/datum/terminal = null", false, "code/probe.dm", 3, false),
        ("list-initialized", "var/list/datum/terminal = list()", false, "code/probe.dm", 3, false),
        ("list-followed", "var/list/datum/terminal", true, "code/probe.dm", 3, false),
        ("list-explicit", "var/list/datum/terminal;", false, "code/probe.dm", 3, false),
    ] {
        let root = scratch::dir(case);
        put(&root, "deepquarry.dme", if next {
            "#include \"code/probe.dm\"\n#include \"code/after.dm\"\n"
        } else {
            "#include \"code/probe.dm\"\n"
        });
        put(&root, "code/probe.dm", format!("{HEADER}    {declaration}\n"));
        if next {
            put(&root, "code/after.dm", "/datum/after_queues\n");
        }
        let front = prepare(&root);
        let view = front.source_view().unwrap();
        assert_eq!(view.original_analysis_completeness(), Some(frontend::OriginalAnalysisCompleteness::Complete), "{case}");
        let archive = view.archive();
        let tree = view.tree();
        let owner = tree.lookup_type(dm_ir::SymbolId::of("/datum/queues_other")).unwrap();
        let member = tree.resolve(owner, dm_ir::SymbolId::of("terminal"), dm_tree::MemberKind::Var).unwrap();
        let authored = archive.member_location(member).expect("actual authored member occurrence");
        assert!(authored.path.ends_with("code/probe.dm"), "{case}: {authored:?}");
        assert_eq!(authored.line, 3, "{case}");

        let text = view.expanded_text();
        let storage = view.storage_view();
        let name_start = text.find("terminal").expect("unique actual expanded declaration name");
        let header = text[..name_start].rfind("var").expect("actual expanded declaration header");
        let cursor = storage.syntax.declaration_cursor_at_for_policy(header)
            .unwrap_or_else(|| panic!("{case}: actual primary cursor missing in {text:?}"));
        let origins = &storage.expanded.origins;
        let index = origins.partition_point(|origin| origin.output_span.end <= cursor);
        let (include, point, token, raw, eof) = origins.original_raw_point_geometry(index)
            .unwrap_or_else(|| panic!("{case}: actual primary cursor has no received origin in {text:?}"));
        assert_eq!(cursor, token.start, "{case}: actual primary cursor must land on the issued token");
        let location = view.mapping().original_note_origin(cursor).unwrap();
        assert!(location.path.ends_with(expected_file), "{case}: {location:?}; {text:?}");
        assert_eq!((location.line, point.line), (expected_line, expected_line), "{case}");
        if terminal_eof {
            assert_eq!(include, 0, "{case}: actual final delimiter has the root acquisition");
            assert_eq!(location.byte_column, 1, "{case}: final Original lexer newline column");
            assert_eq!(text.get(token.range()), Some(";"), "{case}: actual issued EOF semicolon");
            assert!(eof, "{case}: producer must have issued physical EOF, not merely punctuation");
            let acquired = view.mapping().source_acquisition(include).unwrap();
            assert_eq!(raw.start, acquired.source_text().len(), "{case}");
            assert_eq!(raw.start, raw.end, "{case}: synthetic delimiter has no physical width");
            assert_ne!(authored.include_occurrence, include, "{case}");
        } else {
            assert_eq!(authored.include_occurrence, include, "{case}");
            assert!(!eof, "{case}: ordinary cursor must not gain terminal authority");
        }

        let profile = tree.checker_builtin_profile().unwrap();
        let flags = if case == "private-eof" { dm_syntax::CHECKER_VAR_PRIVATE } else { 0 };
        assert_eq!(archive.checker_variable_qualifiers(member, profile).unwrap(), flags, "{case}");
        let note = archive.member_source_note_point(member).unwrap();
        assert_eq!(note, location, "{case}: declaration diagnostic must use the issued token");
        let diagnostic = archive.member_declaration_diagnostic_line(member).unwrap();
        assert_eq!((diagnostic.path, diagnostic.line), (location.path, location.line), "{case}");
        assert_eq!(archive.member_policy_line(member).is_err(), terminal_eof, "{case}");
        assert_eq!(archive.member_primary_policy_span(member).is_err(), terminal_eof, "{case}");

        // The stored-reference policy uses the diagnostic's reported file.
        // Its Analyze sink already applies the legacy code/ eligibility filter.
        let inputs = dm_analysis::policy_inputs::PolicyInputs::capture_diagnostic(&view, []).unwrap();
        let policy = dm_analysis::untyped::StoredPolicy {
            exempt_types: &[],
            registry: &[],
            transient_types: &[],
            work_queues: &[],
            relations: &Default::default(),
            init_only: &[],
            has_schema: &|_, _| false,
        };
        let rows = dm_analysis::untyped::stored_findings(
            &inputs, &root, &policy, |_| false, &mut (64 * 1024 * 1024), || Ok(()),
        ).unwrap();
        let row = rows.iter().find(|row| row.ident == "/datum/queues_other::terminal").unwrap();
        assert_eq!((row.rel.as_str(), row.line), (expected_file, expected_line), "{case}");
    }
}

#[test]
fn actual_large_original_macro_arguments_keep_order_and_wrong_arity_origin() {
    const COUNT: usize = 2100;
    let root = scratch::dir("actual-large-original-macro-arguments");
    put(&root, "deepquarry.dme", "#include \"code/probe.dm\"\n");
    let values = (0..COUNT).map(|index| index.to_string()).collect::<Vec<_>>();
    let joined = values.join(",");
    let wrong_arity = format!("NEED_TWO(list({joined}))");
    put(&root, "code/probe.dm", format!(
        "#define FORWARD(x) x\n#define NEED_TWO(a,b) a\n\
         /datum/large_arguments\n    var/list/forwarded = FORWARD(list({joined}))\n\
         {wrong_arity}\n/datum/after_large_arguments\n"
    ));
    let front = prepare(&root);
    let view = front.source_view().unwrap();
    let expanded = view.expanded_text();
    let numbers = dm_syntax::lex_spans(expanded).tokens.into_iter()
        .filter(|token| token.kind == dm_syntax::TokenKind::Number)
        .map(|token| token.text(expanded)).collect::<Vec<_>>();
    assert!(numbers.iter().copied().eq(values.iter().map(String::as_str)),
        "only the forwarded invocation can contribute numeric output in source order");
    assert!(view.tree().lookup_type(dm_ir::SymbolId::of("/datum/after_large_arguments")).is_some());
    let notices = view.original_preprocess_notices().unwrap();
    let errors = notices.iter().collect::<Result<Vec<_>, _>>().unwrap();
    let [error] = errors.as_slice() else { panic!("one real wrong-arity notice") };
    assert_eq!(error.message, "wrong number of arguments to macro call");
    assert_eq!(error.severity, dm_preprocess::regions::OriginalNoticeSeverity::Error);
    let OriginalDiagnosticPoint::Acquired{source_path,line,byte_column,..} = error.point else {
        panic!("real wrong arity must keep the current raw source");
    };
    assert!(source_path.ends_with("code/probe.dm"));
    assert_eq!((line,byte_column),(5,wrong_arity.len()));
}

#[test]
fn original_nested_mapping_requires_its_current_recorder_and_occurrence() {
    use dm_preprocess::{OriginalRawOpenDecision, OriginalRawReadOutcome};
    use dm_preprocess::source_arena_credit::read_original_source_open_using;
    let root=scratch::dir("checker-nested-current-raw-receipt");
    put(&root,"deepquarry.dme","#include \"bridge.dm\"\n");
    put(&root,"bridge.dm","#include \"leaf.dm\"\n");
    put(&root,"leaf.dm",b"// raw \xff\r\n/datum/leaf\r\n");
    let project=std::fs::canonicalize(root.join("deepquarry.dme")).unwrap();
    let inputs=RecordingInputs::new(FileSystemInputs,0)
        .with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
    let host=dmbc::runner_host::BuildHost::default();
    let db=Arc::new(dmbc::query_db::QueryDb::default());
    let settings:Arc<dyn frontend::SettingExpressionQueries>=db.clone();
    let executor=dm_exec::BuildExecutor::new(1).unwrap();
    let seed=dm_tree::checker_builtins::original_analysis_seed().unwrap();
    let prepared=frontend::build_for_checker_diagnostics_with_state_checked(
        &project,&inputs,&BTreeMap::new(),
        FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},
        None,&executor,None,&settings,
    ).unwrap();
    let source=prepared.checker_source_view().unwrap();
    let (index,path)=source.semantic_includes().find(|(_,path)|path.ends_with("leaf.dm")).unwrap();
    assert!(!inputs.snapshot().unwrap().files().any(|fact|fact.path.as_path()==path.as_path()));
    inputs.check_recorded_mapping_observation(source.mapping(),index,path).unwrap();
    assert!(inputs.check_recorded_mapping_observation(source.mapping(),0,path).is_err());

    let foreign=RecordingInputs::new(FileSystemInputs,0)
        .with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290);
    let OriginalRawReadOutcome::Acquired(lease)=read_original_source_open_using(
        &foreign,path,1<<20,host.source_arena_work(),&mut||Ok(OriginalRawOpenDecision::Read),
    ).unwrap() else { panic!("actual foreign read") };
    assert_eq!(foreign.original_source_bytes(&lease).unwrap().unwrap(),b"// raw \xff\r\n/datum/leaf\r\n");
    assert!(foreign.check_recorded_mapping_observation(source.mapping(),index,path).is_err());
}
