//! Native-only differential against the pinned independent Analyze report.
#[path = "../../../shared/test_scratch.rs"]
mod scratch;

use dm_preprocess::{
    source_arena_credit::SourceArenaWork, InitialEnvironment, OriginalRawAllocationPlan,
    OriginalRawOpenDecision, OriginalRawReadOutcome, SourceAcquisitionLease, SourceProvider,
};
use dm_tree::frontend::{FrontendConfig, SettingExpressionQueries};
use dmbc::{
    input_snapshot::{FileSystemInputs, RecordingInputs},
    query_db::QueryDb,
};
use dq_analyze::{
    captured_generator_budget::Budget, captured_image_dir, captured_raw_file::Config,
    captured_raw_policy::Configuration, captured_reactive_reads::Failure,
};
use std::{io, path::Path, sync::Arc};

/// A Sync loan of the same actual recorder; the fixture owns no fake source,
/// parse, admission, or semantic answer.
struct Batch(RecordingInputs);
impl SourceProvider for Batch {
    fn read(&self,_:&Path)->Result<String,String>{
        panic!("ImageDir must use the actual admitted Original reader")
    }
    fn initial_environment(&self)->InitialEnvironment{
        self.0.initial_environment()
    }
    fn original_batch_source(&self)->io::Result<Option<&(dyn SourceProvider+Sync)>>{
        Ok(Some(self))
    }
    fn path_presence_admitted(&self,path:&Path,work:&dyn SourceArenaWork)->io::Result<bool>{
        self.0.path_presence_admitted(path,work)
    }
    fn original_raw_source_open_admitted(
        &self,path:&Path,max:usize,work:&dyn SourceArenaWork,
        after_open:&mut dyn FnMut()->io::Result<OriginalRawOpenDecision>,
        before_read:&mut dyn FnMut(usize)->io::Result<()>,
        before_decode:&mut dyn FnMut(OriginalRawAllocationPlan<'_>)->io::Result<()>,
        acquired:&mut dyn FnMut(&SourceAcquisitionLease)->io::Result<()>,
    )->io::Result<OriginalRawReadOutcome>{
        self.0.original_raw_source_open_admitted(
            path,max,work,after_open,before_read,before_decode,acquired,
        )
    }
    fn original_source_bytes<'a>(&'a self,lease:&'a SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{
        self.0.original_source_bytes(lease)
    }
}

#[test]
fn native_image_dir_named_report_matches_pinned_mixed_callable_rows(){
    assert_image_dir_report(
        "image-dir-thin-native-pinned",
        include_bytes!("../../../fixtures/unified_checks/image_dir_mixed_callable/probe.dm"),
        &[34,36,37,43,50],
        include_str!("../../../fixtures/unified_checks/image_dir_mixed_callable/expected.report"),
    );
}

#[test]
fn native_image_dir_matches_pinned_builtin_callable_precedence(){
    assert_image_dir_report(
        "image-dir-thin-builtin-pinned",
        include_bytes!("../../../fixtures/unified_checks/image_dir_builtin_callable/probe.dm"),
        &[14,15,18,20],
        include_str!("../../../fixtures/unified_checks/image_dir_builtin_callable/expected.report"),
    );
}

fn assert_image_dir_report(name: &str, source: &[u8], lines: &[u32], expected: &str) {
    let root=scratch::dir(name);
    std::fs::create_dir(root.join("code")).unwrap();
    let project=root.join("deepquarry.dme");
    std::fs::write(&project,b"#include \"code/probe.dm\"\n").unwrap();
    std::fs::write(root.join("code/probe.dm"), source).unwrap();
    let scope=b"[lint.image_dir_after_build.lists]\nexempt_files=[]\n";
    let config=Config::capture(Configuration::Captured(scope)).unwrap();

    let provider=Batch(RecordingInputs::new(FileSystemInputs,0)
        .with_initial_environment(InitialEnvironment::OriginalChecker0290));
    let host=Arc::new(QueryDb::default());
    let declaration:Arc<dyn SettingExpressionQueries>=host.clone();
    let executor=dm_exec::BuildExecutor::new(1).unwrap();
    let seed=dm_tree::checker_builtins::original_analysis_seed().unwrap();
    let frontend=dm_tree::frontend::build_for_original_image_dir_checked(
        &project,&provider,&Default::default(),
        FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},
        &executor,&declaration,
    ).unwrap().with_body_queries(host).unwrap();

    let failed=captured_image_dir::collect(&frontend,&root,&config,&Budget::new(32<<20).unwrap(),
        &||Err(io::Error::from_raw_os_error(1450)));
    assert!(matches!(failed,Err(Failure::Operational(actual)) if actual.raw_os_error()==Some(1450)));
    let actual=captured_image_dir::collect(&frontend,&root,&config,&Budget::new(32<<20).unwrap(),&||Ok(())).unwrap();
    assert_eq!(actual.sites().iter().map(|site|site.line).collect::<Vec<_>>(),lines);
    assert!(actual.sites().iter().all(|site|site.rel=="code/probe.dm"&&site.rule=="dir_after_build"&&site.key.is_empty()&&site.ident.is_empty()));
    assert!(actual.allow_used().is_empty());

    struct Hard;
    impl dq_analyze::baseline::SiteText for Hard {
        fn site_text(&self,_:&str,_:usize)->String{panic!("hard ImageDir report does not read baseline source lines")}
    }
    let empty=dq_analyze::scopes::LintScope::default();
    let scope=config.borrowed_report_scope(actual.metadata().name,actual.metadata().group).unwrap_or(&empty);
    let rendered=dq_analyze::policy_finish::finish_report(actual.metadata(),scope,&Hard,
        dq_analyze::lint::Run{sites:actual.sites().to_vec(),notes:Vec::new()},
        actual.allow_used().to_vec(),Default::default(),&root,&None,true,
        |_,_,_|panic!("ImageDir has no custom report hooks"),|_,_|false);
    assert!(rendered.failed);
    assert_eq!(rendered.text,expected);
    assert!(!project.with_extension("dmb").exists());
}

#[test]
fn named_image_dir_embedding_stages_exact_output_and_keeps_open_io(){
    let root=scratch::dir("image-dir-thin-named-embedding");
    let cache=scratch::dir("image-dir-thin-named-cache");
    std::fs::create_dir_all(root.join("tools/ci")).unwrap();
    std::fs::create_dir(root.join("code")).unwrap();
    std::fs::write(root.join("deepquarry.dme"),b"#include \"code/probe.dm\"\n").unwrap();
    std::fs::write(root.join("code/probe.dm"),
        include_bytes!("../../../fixtures/unified_checks/image_dir_mixed_callable/probe.dm")).unwrap();
    let configuration=root.join("tools/ci/lint_scopes.toml");
    let mut host=dmbc::runner_host::BuildHost::default();
    let mut output=b"untouched prefix".to_vec();
    let actual=host.write_original_image_dir_report(&root,&cache,60,&mut output).unwrap_err();
    assert_eq!(actual.kind(),io::ErrorKind::NotFound);
    assert_eq!(output,b"untouched prefix");
    std::fs::write(configuration,b"[lint.image_dir_after_build.lists]\nexempt_files=[]\n").unwrap();
    let mut output=Vec::new();
    assert!(!host.write_original_image_dir_report(&root,&cache,60,&mut output).unwrap());
    assert_eq!(output,include_bytes!("../../../fixtures/unified_checks/image_dir_mixed_callable/expected.report"));
}
