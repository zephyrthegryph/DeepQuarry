use super::*;
use dm_tree::frontend::{
    BodySyntax, BodySyntaxInput, BodySyntaxQueries, OriginalInitializerExpression,
    OriginalInitializerExpressionInput, OriginalSignatureAliasCensus, OriginalSignatureAliasGroup,
    SettingExpressionInput, SettingExpressionQueries,
};

#[path = "../../dmb/shared/original_analysis_test_host.rs"]
mod original_host;
#[path = "../fixtures/original_policy_source.rs"]
mod policy_source;

#[derive(Debug)]
struct BodyHost {
    counter: Arc<dm_syntax::SettingChargeCounter>,
    fail_body: std::sync::atomic::AtomicBool,
}
impl Default for BodyHost {
    fn default() -> Self {
        Self {
            counter: dm_syntax::SettingChargeCounter::try_new(16 << 20).unwrap(),
            fail_body: Default::default(),
        }
    }
}
impl BodySyntaxQueries for BodyHost {
    fn syntax(&self,input:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,dm_tree::frontend::Diagnostic>{
        match self.syntax_checked(input){
            Ok(body)=>Ok(body),
            Err(BodySyntaxFailure::Syntax(error))=>Err(error),
            Err(BodySyntaxFailure::Operational(error))=>panic!("fixture compatibility body: {error}"),
        }
    }
    fn syntax_checked(&self,input:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,BodySyntaxFailure>{
        if self.fail_body.load(std::sync::atomic::Ordering::Acquire){
            return Err(BodySyntaxFailure::Operational(io::Error::from_raw_os_error(1450)));
        }
        input.parse_with_setting_admission(&dm_syntax::SettingAdmission::new(&self.counter,16<<20,&||Ok(()))).map(Arc::new)
    }
}

const CODE: &str = concat!(
    "/proc/from_annotation() as /image\n",
    "    return null\n",
    "/proc/from_setting()\n",
    "    set SpacemanDMM_return_type = /image\n",
    "    return null\n",
    "/image/child/proc/check_self()\n",
    "    src.dir = 1 // HIT\n",
    "/datum/image_dir_probe\n",
    "    var/image/field\n",
    "    proc/probe(image/typed, unknown, list/image/images)\n",
    "        typed.dir += 1 // HIT\n",
    "        field.dir = 2 // HIT\n",
    "        var/inferred = image()\n",
    "        inferred.dir *= 2 // HIT\n",
    "        var/also = inferred\n",
    "        also.dir = 2 // HIT\n",
    "        image().dir = 2 // HIT\n",
    "        mutable_appearance().dir = 2 // HIT\n",
    "        from_annotation().dir = 2 // HIT\n",
    "        from_setting().dir = 2 // HIT\n",
    "        unknown.dir = 2\n",
    "        images[1].dir = 2\n",
    "        (unknown ? typed : inferred).dir = 2\n",
    "        typed.appearance.dir = 2\n",
    "        var/reassigned\n",
    "        reassigned = image()\n",
    "        reassigned.dir = 2\n",
);

#[test]
fn image_dir_captured_body_rows_match_independent_legacy_receiver_inference() {
    let root = crate::test_scratch::dir("captured-image-dir-differential");
    std::fs::create_dir_all(root.join("code")).unwrap();
    std::fs::create_dir_all(root.join("tools/ci")).unwrap();
    std::fs::write(root.join("deepquarry.dme"), concat!(
        "#include \"code/a.dm\"\n",
        "#include \"code/exempt.dm\"\n",
        "#include \"code/bodyless.dm\"\n",
        "#include \"code/cross_owner.dm\"\n",
    )).unwrap();
    std::fs::write(root.join("code/bodyless.dm"), concat!(
        "/datum/image_factory\n",
        "    proc/create()\n",
        "        set SpacemanDMM_return_type = /image\n",
        "        return null\n",
        "/datum/image_factory/child/create()\n",
        "/proc/bodyless_probe(datum/image_factory/child/F)\n",
        "    F.create().dir = 2\n",
    )).unwrap();
    std::fs::write(root.join("code/cross_owner.dm"), concat!(
        "/proc/cross_file_probe(image/I)\n",
        "    // This bare CR belongs to the callable owner only.\rStill a comment.\n",
        "    var/unused = 0\n",
        "#include \"cross_statement.dm\"\n",
    )).unwrap();
    std::fs::write(root.join("code/cross_statement.dm"),
        format!("{}    I.dir = 2\n", "\n".repeat(11))).unwrap();
    std::fs::write(root.join("code/a.dm"), CODE).unwrap();
    std::fs::write(root.join("code/exempt.dm"), "/proc/exempt(image/I)\n    I.dir = 2\n").unwrap();
    std::fs::write(root.join("code/uncompiled.dm"), "/proc/uncompiled(image/I)\n    I.dir = 2\n").unwrap();
    let scope = b"[lint.image_dir_after_build.lists]\nexempt_files=['code/exempt.dm']\n";
    std::fs::write(root.join("tools/ci/lint_scopes.toml"), scope).unwrap();
    let engine = crate::run::Engine::new(crate::run::registry(), crate::run::Options {
        root: root.clone(), lints: vec!["image_dir_after_build".into()],
        raw: true, no_cache: true, ..Default::default()
    }).unwrap();
    let old = engine.run_one(engine.reg.find("image_dir_after_build").unwrap());
    let expected_lines = CODE.lines().enumerate().filter(|(_, line)| line.ends_with("// HIT"))
        .map(|(line, _)| line as u32 + 1).collect::<Vec<_>>();
    assert_eq!(old.run.sites.iter().filter(|site| site.rel == "code/a.dm")
        .map(|site| site.line).collect::<Vec<_>>(), expected_lines);
    let cross = old.run.sites.iter().filter(|site| site.rel != "code/a.dm")
        .map(|site| (site.rel.as_str(), site.line)).collect::<Vec<_>>();
    assert_eq!(cross, [("code/cross_owner.dm", 13)],
        "legacy keeps the owner path, child line 12 and one owner CR. The bodyless override has no return hint");
    assert!(old.allow_used.is_empty());

    let provider = policy_source::Provider::new();
    let host = original_host::Host::new() as Arc<dyn SettingExpressionQueries>;
    let seed = dm_tree::checker_builtins::original_analysis_seed().unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let front = dm_tree::frontend::build_for_original_image_dir_checked(
        &root.join("deepquarry.dme"), &provider, &Default::default(),
        dm_tree::frontend::FrontendConfig { workers: 1, engine: Some(seed.frontend_seed()), observer: None },
        &executor, &host,
    ).unwrap().with_body_queries(Arc::new(BodyHost::default())).unwrap();
    let archive = Arc::clone(front.archive());
    let inputs=front;
    let empty = archive.occurrences().iter().enumerate().find(|(_, body)| {
        archive.callables().identity_for_member(body.member).is_some_and(|id| {
            id.owner == dm_ir::SymbolId::of("/datum/image_factory/child")
                && id.name == dm_ir::SymbolId::of("create")
        })
    }).expect("an empty callable retains its issued original body recipe");
    let body = archive.parse_checked(empty.0).unwrap();
    assert!(std::ptr::eq(body.occurrence(), empty.1));
    assert!(body.statement_body().parsed().statements.is_empty());
    let config = Config::capture(crate::captured_raw_policy::Configuration::Captured(scope)).unwrap();
    let data = collect(&inputs, &root, &config, &Budget::new(32 << 20).unwrap(), &|| Ok(())).unwrap();
    assert_eq!(data.sites(), old.run.sites.as_slice());
    assert!(data.allow_used().is_empty());
}

#[test]
fn image_dir_mixed_original_named_report_matches_pinned_five_rows() {
    let root=crate::test_scratch::dir("image-dir-mixed-named-report");
    std::fs::create_dir_all(root.join("code")).unwrap();
    std::fs::create_dir_all(root.join("tools/ci")).unwrap();
    std::fs::write(root.join("deepquarry.dme"),b"#include \"code/probe.dm\"\n").unwrap();
    std::fs::write(root.join("code/probe.dm"),
        include_bytes!("../../dmb/fixtures/unified_checks/image_dir_mixed_callable/probe.dm")).unwrap();
    let scope=b"[lint.image_dir_after_build.lists]\nexempt_files=[]\n";
    std::fs::write(root.join("tools/ci/lint_scopes.toml"),scope).unwrap();
    let engine=crate::run::Engine::new(crate::run::registry(),crate::run::Options{
        root:root.clone(),lints:vec![META.name.into()],raw:true,no_cache:true,..Default::default()
    }).unwrap();
    let old=engine.run_one(engine.reg.find(META.name).unwrap());
    assert_eq!(old.run.sites.iter().map(|site|site.line).collect::<Vec<_>>(),[34,36,37,43,50]);
    assert!(old.allow_used.is_empty());

    let provider=policy_source::Provider::new();
    let host=original_host::Host::new() as Arc<dyn SettingExpressionQueries>;
    let seed=dm_tree::checker_builtins::original_analysis_seed().unwrap();
    let executor=dm_exec::BuildExecutor::new(1).unwrap();
    let body_host=Arc::new(BodyHost::default());
    let frontend=dm_tree::frontend::build_for_original_image_dir_checked(
        &root.join("deepquarry.dme"),&provider,&Default::default(),
        dm_tree::frontend::FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},
        &executor,&host,
    ).unwrap().with_body_queries(body_host.clone()).unwrap();
    let inputs=frontend;
    let config=Config::capture(crate::captured_raw_policy::Configuration::Captured(scope)).unwrap();
    let run=||collect(&inputs,&root,&config,&Budget::new(32<<20).unwrap(),&||Ok(()));
    body_host.fail_body.store(true,std::sync::atomic::Ordering::Release);
    assert!(matches!(run(),Err(Failure::Operational(actual)) if actual.raw_os_error()==Some(1450)));
    body_host.fail_body.store(false,std::sync::atomic::Ordering::Release);
    let actual=run().unwrap();
    assert_eq!(actual.sites(),old.run.sites.as_slice());
    assert_eq!(actual.allow_used(),old.allow_used.as_slice());

    struct Hard;
    impl crate::baseline::SiteText for Hard {
        fn site_text(&self,_:&str,_:usize)->String{panic!("hard ImageDir output has no baseline source dependency")}
    }
    let empty=crate::scopes::LintScope::default();
    let captured_scope=config.borrowed_report_scope(META.name,META.group).unwrap_or(&empty);
    let rendered=crate::policy_finish::finish_report(actual.metadata(),captured_scope,&Hard,
        crate::lint::Run{sites:actual.sites().to_vec(),notes:Vec::new()},
        actual.allow_used().to_vec(),Default::default(),&root,&None,true,
        |_,_,_|panic!("ImageDir has no custom policy"),|_,_|false);
    assert_eq!(rendered.failed,old.failed);
    assert_eq!(rendered.text,old.text);
}
