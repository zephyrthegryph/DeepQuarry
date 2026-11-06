//! Genuine old semantic parser/judges against available-model native DATA.
use crate::{sem::{Sem,ast},lint::Registry,captured_generator_budget::Budget,captured_reactive_reads::Failure,captured_engine_layering_pages::{self as current,PathPages}};
#[path="../fixtures/original_policies/engine_layering_sem_workspace.rs"]mod original_layering;
#[path="../fixtures/original_policies/engine_layering_binding_adapter.rs"]mod original_registration;
#[path="../fixtures/native-engine-layering-workspace/fixture.rs"]mod fixture;
#[path="../../dmb/shared/test_scratch.rs"]mod scratch;
use std::{path::Path,sync::Arc};
use dm_tree::frontend::{SettingExpressionQueries,SettingExpressionInput,OriginalInitializerExpressionInput,OriginalInitializerExpression,BodySyntaxFailure,OriginalSignatureAliasCensus,OriginalSignatureAliasGroup};
#[path="../../dmb/shared/original_analysis_test_host.rs"]mod original_host;
#[path="../fixtures/original_policy_source.rs"]mod policy_source;

fn input(root: &Path) -> dm_analysis::policy_inputs::PolicyInputs {
    let seed = dm_tree::checker_builtins::original_analysis_seed().expect("actual fixed Original declaration seed");
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let host = original_host::Host::new() as Arc<dyn SettingExpressionQueries>;
    let provider = policy_source::Provider::new();
    let front = dm_tree::frontend::build_for_original_analysis_with_state_checked(
        &root.join("deepquarry.dme"), &provider, &Default::default(),
        dm_tree::frontend::FrontendConfig { workers: 1, engine: Some(seed.frontend_seed()), observer: None },
        None, &executor, None, &host,
    ).unwrap();
    let view = front.source_view().unwrap();
    assert!(view.original_analysis_completeness().is_some());
    let raw = view.files().iter().filter(|file| file.captured).map(|file| {
        dm_analysis::policy_inputs::HostCapture::analyze_raw(
            Arc::clone(&file.path), dm_analysis::policy_inputs::PolicyRole::DmSource,
            provider.analyze_raw(&file.path, &file.text),
        )
    }).collect::<Vec<_>>();
    dm_analysis::policy_inputs::PolicyInputs::capture_diagnostic(&view, raw).unwrap()
}
struct Pages<'a>{root:&'a Path,rows:Vec<(String,dm_preprocess::SourceText)>,budget:Arc<Budget>,visits:std::cell::Cell<usize>}
impl PathPages for Pages<'_>{fn for_each_path(&self,emit:&mut dyn FnMut(&str)->Result<(),Failure>)->Result<bool,Failure>{for(rel,_)in &self.rows{emit(rel)?;}Ok(true)}}
impl crate::reactive_raw_policy_pages::RawPolicyPages for Pages<'_>{fn for_each(&self,emit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let phase=self.visits.get();self.visits.set(phase+1);for(rel,text)in &self.rows{let done=if phase==1{crate::captured_raw_file::with_original_policy_file_clean(self.root,&self.root.join(rel),text.clone(),0,&self.budget,emit)}else{crate::captured_raw_file::with_original_policy_file(self.root,&self.root.join(rel),text.clone(),0,&self.budget,emit)}?;if !done{return Ok(false)}}Ok(true)}}
#[test]fn immutable_original_engine_whole_reports_cover_provenance_chronology_root_and_raw_markers(){
 use sha1::Digest as _;assert_eq!(format!("{:x}",sha1::Sha1::digest(include_bytes!("../fixtures/original_policies/engine_layering_sem_workspace.rs"))),"47c43e584692b7bf1a10dda48bfeb5964e28754a");
 assert_eq!(format!("{:x}",sha1::Sha1::digest(include_bytes!("../fixtures/original_policies/engine_layering_workspace.rs"))),"adce44b798bad580357b0390c510214353e64e6f");
 assert_eq!(format!("{:x}",sha1::Sha1::digest(include_bytes!("../fixtures/original_policies/engine_layering_sem_indices_workspace.rs"))),"f2aee8730df056ad7a6cec96e1ad0812cfe89533");
 for case in fixture::CASES{let root=scratch::dir(&format!("engine-original-{case}"));let files=fixture::files(case);for(rel,text)in &files{let path=root.join(rel);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,text).unwrap();}let mut registry=Registry::default();original_registration::register(&mut registry);let engine=crate::run::Engine::new(registry,crate::run::Options{root:root.clone(),lints:vec!["engine_layering".into()],no_cache:true,raw:true,..Default::default()}).unwrap();let sem=crate::sem::sem_for(&engine.tree).unwrap();assert!(sem.errors.is_empty(),"actual old fixture {case} is invalid: {:?}",sem.errors);if *case=="maps"{assert!(sem.ty("/datum/map_type").is_some(),"actual Original model must include the map type before testing provenance");}let expected=engine.run_one(engine.reg.lints[0].as_ref());assert!(expected.internal_error.is_none());if matches!(*case,"builtin"|"inactive"|"maps"|"exempt"){assert!(expected.run.sites.is_empty(),"genuine old clean {case}: {:?}",expected.run.sites);}else{assert!(!expected.run.sites.is_empty(),"genuine old positive {case}");}if *case=="virtual"{assert!(!expected.run.sites.iter().any(|s|s.msg.contains("::hook")));}if *case=="before_first"{assert!(expected.run.sites.iter().any(|s|s.line==2&&s.msg.contains("/proc/helper")),"no future owner can authorize early marker");}assert!(expected.run.notes.is_empty()&&expected.allow_used.is_empty());
 let inputs=input(&root);if *case=="maps"{struct NativeCheck;impl dm_analysis::policy_body_demand::WorkspaceWork for NativeCheck{type Error=dm_analysis::untyped::Unsupported;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),Self::Error>{Ok(())}fn retain(&mut self,_:usize)->Result<(),Self::Error>{Ok(())}fn temporary(&mut self,_:usize)->Result<(),Self::Error>{Ok(())}fn overflow(&mut self)->Self::Error{unreachable!()}fn allocation_failed(&mut self)->Self::Error{unreachable!()}fn body<'a>(&mut self,a:&'a dm_tree::frontend::BodyArchive,n:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,Self::Error>{a.parse(n).map_err(|e|dm_analysis::untyped::Unsupported(e.message))}}assert!(dm_analysis::engine_layering_native::Model::new(&inputs,&root).unwrap().type_exists("/datum/map_type",&mut NativeCheck).unwrap());}let budget=Budget::new(64*1024*1024).unwrap();let rows=files.iter().filter(|(p,_)|crate::captured_raw_file::is_code_dm(p)).map(|(p,t)|{let source=dm_preprocess::AcquiredSource::from_original_bytes(t.as_bytes().to_vec(),());(p.to_string(),source.lease().source_text().clone())}).collect();let pages=Pages{root:&root,rows,budget:budget.clone(),visits:std::cell::Cell::new(0)};let bytes=files.iter().find(|(p,_)|*p=="tools/ci/lint_scopes.toml").map(|(_,s)|s.as_bytes());let config=crate::captured_raw_file::Config::capture(bytes.map_or(crate::captured_raw_policy::Configuration::ProvenMissing,crate::captured_raw_policy::Configuration::Captured)).unwrap();let selected=current::preflight(&pages,&config,&budget,&||Ok(())).unwrap();let actual=current::collect_available(&pages,&inputs,&root,&config,selected,&budget,&||Ok(())).unwrap();assert_eq!(actual.sites(),expected.run.sites.as_slice(),"entire immutable old/native sites {case}");assert_eq!(actual.notes(),expected.run.notes);assert_eq!(actual.allow_used(),expected.allow_used);struct Hard;impl crate::baseline::SiteText for Hard{fn site_text(&self,_:&str,_:usize)->String{panic!("engine Hard finding cannot ask unobserved source text")}}let empty=crate::scopes::LintScope::default();let scope=config.borrowed_report_scope("engine_layering","").unwrap_or(&empty);let rendered=crate::policy_finish::finish_report(actual.metadata(),scope,&Hard,crate::lint::Run{sites:actual.sites().to_vec(),notes:actual.notes().to_vec()},actual.allow_used().to_vec(),Default::default(),&root,&None,true,|_,_,_|panic!("engine is not custom"),|_,_|false);assert_eq!(rendered.failed,expected.failed);assert_eq!(rendered.text,expected.text,"entire original/native Hard report {case}");assert_eq!(rendered.internal_error,expected.internal_error);assert_eq!(pages.visits.get(),if *case=="exempt"{0}else{2});println!("ENGINE_ORIGINAL_NATIVE_FULL={}",serde_json::json!({"case":case,"sites":actual.sites(),"notes":actual.notes(),"allow":actual.allow_used()}));
 }
}
#[test]fn no_selected_engine_path_preflight_never_demands_payload_dme_or_model(){
 struct Metadata;impl PathPages for Metadata{fn for_each_path(&self,f:&mut dyn FnMut(&str)->Result<(),Failure>)->Result<bool,Failure>{f("code/library/unreadable.dm")?;Ok(true)}}let budget=Budget::new(1024*1024).unwrap();let config=crate::captured_raw_file::Config::capture(crate::captured_raw_policy::Configuration::ProvenMissing).unwrap();let selected=current::preflight(&Metadata,&config,&budget,&||Ok(())).unwrap();assert!(selected.is_empty());assert_eq!(selected.first(),None);let clean=current::finish_unselected(selected,&budget,&||Ok(())).unwrap();assert!(clean.sites().is_empty()&&clean.notes().is_empty()&&clean.allow_used().is_empty());
 struct NotEof;impl PathPages for NotEof{fn for_each_path(&self,_:&mut dyn FnMut(&str)->Result<(),Failure>)->Result<bool,Failure>{Ok(false)}}assert!(current::preflight(&NotEof,&config,&budget,&||Ok(())).is_err());
}

#[test]fn all_engine_paths_exempt_finish_before_poison_payloads_and_cancellation_keeps_actual_io(){
 struct Paths;impl PathPages for Paths{fn for_each_path(&self,f:&mut dyn FnMut(&str)->Result<(),Failure>)->Result<bool,Failure>{f("code/engine/probe.dm")?;Ok(true)}}let budget=Budget::new(1024*1024).unwrap();let config=crate::captured_raw_file::Config::capture(crate::captured_raw_policy::Configuration::Captured(b"[lint.engine_layering]\nexempt_files=[\"code/engine/probe.dm\"]\n")).unwrap();let selection=current::preflight(&Paths,&config,&budget,&||Ok(())).unwrap();assert!(selection.is_empty());assert!(current::finish_unselected(selection,&budget,&||Ok(())).unwrap().sites().is_empty());
 let error=current::preflight(&Paths,&config,&budget,&||Err(std::io::Error::from_raw_os_error(1450))).err().unwrap();assert!(matches!(error,Failure::Operational(e)if e.raw_os_error()==Some(1450)));let selection=current::preflight(&Paths,&config,&budget,&||Ok(())).unwrap();assert!(current::finish_unselected(selection,&budget,&||Ok(())).is_ok());
}

#[test]
fn merged_host_and_library_boundaries_preserve_selected_sources_and_fingerprints() {
    use crate::engine_layering_policy::Layer;
    let root = scratch::dir("merged-native-layering");
    let sources = [
        ("code/engine/uses_host.dm", "/proc/engine_entry(datum/host_type/value)\n    return value\n"),
        ("code/host/probe.dm", concat!(
            "/datum/host_type\n",
            "/proc/host_entry()\n",
            "    library_helper() // host may not call library\n",
            "#define CAPABILITIES_PART(T, feature) /datum/marker\n",
            "#define ERASE_CALLBACK(X) 1\n",
            "CAPABILITIES_PART(/datum/host_type, fixture)\n",
            "    var/marker_row = ERASE_CALLBACK(PROC_REF(library_only))\n",
        )),
        ("code/library/probe.dm", concat!(
            "/datum/host_type\n",
            "/datum/host_type/proc/library_only()\n",
            "    return\n",
            "/proc/library_helper()\n",
            "    return\n",
            "/proc/library_entry(datum/world_type/value)\n",
            "\tcontent_helper()  // retain this raw comment in the fingerprint\n",
            "    return value\n",
        )),
        ("code/domains/world_model/base.dm", "/datum/world_type\n"),
        ("code/content/content.dm", "/datum/world_type\n/proc/content_helper()\n    return\n"),
    ];
    let mut dme = String::new();
    for (relative, text) in sources {
        let path = root.join(relative);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
        dme.push_str(&format!("#include \"{relative}\"\n"));
    }
    std::fs::write(root.join("deepquarry.dme"), dme).unwrap();
    let inputs = input(&root);
    for layer in [Layer::Engine, Layer::Library] {
        let mut registry = Registry::default();
        match layer {
            Layer::Engine => crate::lints::engine_layering::register(&mut registry),
            Layer::Library => crate::lints::library_layering::register(&mut registry),
        }
        let legacy = crate::run::Engine::new(registry, crate::run::Options {
            root: root.clone(), lints: vec![layer.name().into()], no_cache: true, raw: true,
            ..Default::default()
        }).unwrap();
        assert!(crate::sem::sem_for(&legacy.tree).unwrap().errors.is_empty(), "genuine merged-layout fixture must parse");
        let expected = legacy.run_one(legacy.reg.lints[0].as_ref());
        assert!(expected.internal_error.is_none());
        let budget = Budget::new(64 * 1024 * 1024).unwrap();
        let rows = sources.iter().map(|(p, text)| {
            let source = dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(), ());
            (p.to_string(), source.lease().source_text().clone())
        }).collect();
        let pages = Pages { root: &root, rows, budget: budget.clone(), visits: std::cell::Cell::new(0) };
        let config = crate::captured_raw_file::Config::capture(crate::captured_raw_policy::Configuration::ProvenMissing).unwrap();
        let selection = current::preflight_for(layer, &pages, &config, &budget, &|| Ok(())).unwrap();
        let actual = current::collect_available(&pages, &inputs, &root, &config, selection, &budget, &|| Ok(())).unwrap();
        assert_eq!(actual.metadata().name, layer.name());
        assert_eq!(actual.sites(), expected.run.sites.as_slice(), "genuine current-master sites for {layer:?}");
        assert_eq!(pages.visits.get(), 2);
        match layer {
            Layer::Engine => {
                assert!(actual.source_text().is_none());
                assert!(actual.sites().iter().all(|site| site.rel == "code/host/probe.dm"));
                assert!(actual.sites().iter().any(|site| site.line == 3 && site.msg.contains("/proc/library_helper")));
                assert!(actual.sites().iter().any(|site| site.line == 7 && site.msg.contains("/datum/host_type::library_only")));
            }
            Layer::Library => {
                let text = actual.source_text().unwrap();
                assert_eq!(text.len(), actual.sites().len());
                for (site, actual_text) in actual.sites().iter().zip(text) {
                    assert_eq!(*actual_text, legacy.tree.site_text(&site.rel, site.line as usize));
                }
                assert!(actual.sites().iter().all(|site| site.rel == "code/library/probe.dm"));
                assert!(text.iter().any(|text| text == "content_helper() // retain this raw comment in the fingerprint"));
                assert!(!actual.sites().iter().any(|site| site.msg.contains("/datum/world_type")), "world_model authorizes the shared type despite the content reopening");
            }
        }
    }
}
