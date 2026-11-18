//! Actual semantic host, source revision and completed Sites delivery controls.
use super::*;use std::io;
#[path="../../../../analyze/fixtures/report_configuration.rs"]mod report_config;
pub(super) fn sys_host()->(crate::runner_host::BuildHost,BuildRequest,PathBuf){
 let(mut host,mut request,root)=fixture("/datum/look\n/datum/sys_probe\n    var/power\n    var/charge\n    var/datum/sys_probe/cell\n/datum/sys_probe/proc/draw(datum/look/look)\n    return cell.power\n/datum/sys_probe/proc/should_run()\n    charge=1\n");
 std::fs::write(root.join("tools/ci/lint_scopes.toml"),report_config::with_overlay("")).unwrap();
 for n in 0..140{std::fs::write(root.join(format!("code/filler_{n:03}.dm")),format!("/datum/sys_filler_{n:03}\n")).unwrap();}
 let intent=request.policy_inputs.as_mut().unwrap();intent.analysis_context=Some(AnalysisContext::OriginalAnalyze0290);intent.workspace_auxiliary=vec![crate::policy_request::WorkspaceAuxiliaryQuestion::SysReactive];run(&mut host,&request);(host,request,root)
}
#[test]fn actual_sys_reactive_same_owner_reuses_then_retracts_auto_and_scope_revisions(){
 let _request=crate::daemon::control::bind_with_deadline(crate::daemon::control::Cancellation::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));
 let(mut host,request,root)=sys_host();let queries=Arc::clone(host.query_db());
 let first=current(&host,|snapshot|snapshot.with_original_sys_reactive_policy_report(|data,_,_|{assert!(data.sites().iter().any(|s|s.rule=="dx_untracked_read"));assert_eq!(data.sites().len(),data.source_text().len());Ok(data.sites().to_vec())}).unwrap());
 let count=queries.db().stats(dm_query::Kind(12)).computed;current(&host,|snapshot|snapshot.with_original_sys_reactive_policy_report(|data,_,_|{assert_eq!(data.sites(),first);Ok(())}).unwrap());assert_eq!(queries.db().stats(dm_query::Kind(12)).computed,count);
 let auto=root.join("code/engine/_generated/auto_tracked.dm");std::fs::create_dir_all(auto.parent().unwrap()).unwrap();std::fs::write(&auto,"// actual AUTO triggers old constant-name exemptions\n").unwrap();
 run(&mut host,&request);current(&host,|snapshot|snapshot.with_original_sys_reactive_policy_report(|data,_,_|{assert!(!data.sites().iter().any(|s|s.rule=="dx_untracked_read"),"available old global constant exemptions apply only with actual AUTO");Ok(())}).unwrap());assert!(queries.db().stats(dm_query::Kind(12)).computed>count);
 std::fs::remove_file(&auto).unwrap();run(&mut host,&request);current(&host,|snapshot|snapshot.with_original_sys_reactive_policy_report(|data,_,_|{assert_eq!(data.sites(),first,"genuine AUTO deletion retracts constant exemptions");Ok(())}).unwrap());
 std::fs::write(root.join("tools/ci/lint_scopes.toml"),report_config::with_overlay("[lint.\"sys/dx_reactive\"]\nexempt_files=[\"code/probe.dm\"]\n")).unwrap();run(&mut host,&request);current(&host,|snapshot|snapshot.with_original_sys_reactive_policy_report(|data,_,_|{assert!(data.sites().is_empty());Ok(())}).unwrap());
}
#[test]fn actual_sys_reactive_foreign_db_wrong_role_and_writer1450_deny_then_recover(){
 let _request=crate::daemon::control::bind_with_deadline(crate::daemon::control::Cancellation::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));
 let(host,_,root)=sys_host();current(&host,|snapshot|{let workspace=snapshot.native_workspace.as_ref().unwrap();let capture=snapshot.workspace_semantic_inputs(crate::policy_request::WorkspaceAuxiliaryQuestion::SysReactive).unwrap();let guard=snapshot.workspace_native_read().unwrap();let foreign=crate::query_db::QueryDb::default();assert!(foreign.with_original_workspace_sys_reactive_guard_report(workspace,&guard,capture,|_,_,_|Ok(())).is_err());assert!(snapshot.with_original_semantic_policy_report(crate::policy_request::WorkspaceAuxiliaryQuestion::SetterPublishes,|_,_,_|Ok(())).is_err());
 struct Failed;impl std::io::Write for Failed{fn write(&mut self,_:&[u8])->io::Result<usize>{Err(io::Error::from_raw_os_error(1450))}fn flush(&mut self)->io::Result<()>{Ok(())}}
 let names=vec!["sys/dx_reactive".into()];let error=snapshot.write_native_workspace_semantic_report_page(&root,&root.join("tools/ci/lint_scopes.toml"),&names,None,128,&snapshot.tree,&mut Failed).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));let mut bytes=Vec::new();snapshot.write_native_workspace_semantic_report_page(&root,&root.join("tools/ci/lint_scopes.toml"),&names,None,128,&snapshot.tree,&mut bytes).unwrap();let text=std::str::from_utf8(&bytes).unwrap();assert!(text.contains("sys/dx_reactive")&&!text.contains("hard_site"),"actual Sites policy retains source text contract");assert!(snapshot.write_native_workspace_semantic_report_page(&root,&root.join("tools/ci/lint_scopes.toml"),&["sys/dx_reactive".into(),"sem/reads".into()],None,128,&snapshot.tree,&mut Vec::new()).is_err());});
}
