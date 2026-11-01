use super::*;
use crate as analyze;
use crate::{captured_raw_file::File,captured_raw_policy::Configuration};
use std::{cell::Cell,path::PathBuf};
#[path="../fixtures/native-keys/fixture.rs"]mod fixture;
#[path="../fixtures/native-keys/report.rs"]mod report;
struct Pages{files:Vec<(String,File)>,mode:Cell<u8>,late:Cell<bool>}
impl RawPolicyPages for Pages{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{for(_,file)in &self.files{if !file.with_policy_views(visit)?{return Ok(false)}match self.mode.get(){1=>{self.late.set(true);return Err(Failure::Operational(io::Error::from_raw_os_error(1450)))},2=>{self.late.set(true);return Ok(false)},_=>{}}}Ok(true)}}
fn pages(case:&str)->(PathBuf,Pages,Config,HashMap<String,usize>){
 let root=std::env::current_dir().unwrap().join("keys-page-data-only");let rows=fixture::files(case).unwrap();let config=Config::capture(rows.iter().find(|(relative,_)|*relative=="tools/ci/lint_scopes.toml").map_or(Configuration::ProvenMissing,|(_,bytes)|Configuration::Captured(bytes))).unwrap();let order_budget=Budget::new(4*1024*1024).unwrap();let order_poll=||Ok(());let mut order_control=Operation{budget:&order_budget,poll:&order_poll};
 let manifest=rows.iter().find(|(relative,_)|*relative=="deepquarry.dme").and_then(|(_,bytes)|std::str::from_utf8(bytes).ok()).unwrap_or("");let order=crate::raw_marker_policy::dme_include_order_controlled(manifest,false,&mut order_control).unwrap();
 let mut files:Vec<_>=rows.into_iter().filter(|(relative,_)|relative.starts_with("code/")&&relative.ends_with(".dm")).map(|(relative,bytes)|(relative.to_owned(),File::capture(&root,&root.join(relative),String::from_utf8_lossy(bytes).replace("\r\n","\n").replace('\r',"\n").into()).unwrap())).collect();files.sort_by(|a,b|a.0.cmp(&b.0));(root,Pages{files,mode:Cell::new(0),late:Cell::new(false)},config,order)
}
#[cfg(all(feature="legacy-sem",feature="unified-oracle"))]
#[test]fn complete_key_pages_match_immutable_whole_original_policy_and_report_for_all_initial_cases(){
 crate::keys_original_reference::verify_original_sources().unwrap();for case in fixture::CASES{
  let root=crate::test_scratch::dir(&format!("keys-original-data-{case}"));for(relative,bytes)in fixture::files(case).unwrap(){let path=root.join(relative);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(path,bytes).unwrap();}
  let(_,pages,config,order)=pages(case);let data=collect(&pages,&config,&order,&Budget::new(64*1024*1024).unwrap(),&||Ok(())).unwrap();let original=crate::keys_original_reference::scan(&root,case).unwrap();let native=report::record(&data,&config,&root,case);assert_eq!(native,original,"complete sites/notes/ALLOW/digests/failed/report differ for {case}");if *case=="basic"{assert_eq!(data.sites().len(),16);assert_eq!(data.allow_used().len(),1);assert_eq!(data.sites().iter().map(|row|row.rule.as_str()).collect::<std::collections::BTreeSet<_>>().len(),6);}
 }
}
#[test]fn key_page_provider_io_precedes_late_cancellation_and_stopped_data_never_becomes_success(){
 let(_,pages,config,order)=pages("basic");for(mode,actual)in[(1,true),(2,false)]{pages.mode.set(mode);pages.late.set(false);let poll=||if pages.late.get(){Err(io::ErrorKind::Interrupted.into())}else{Ok(())};let error=collect(&pages,&config,&order,&Budget::new(64*1024*1024).unwrap(),&poll).err().unwrap();match error{Failure::Operational(error)if actual=>assert_eq!(error.raw_os_error(),Some(1450)),Failure::Operational(error)=>assert_eq!(error.kind(),io::ErrorKind::Interrupted),other=>panic!("final or original operational control was lost: {other:?}")}}
 pages.mode.set(0);pages.late.set(false);let root=Budget::new(256).unwrap();let poll=||if root.denied(){Err(io::ErrorKind::Interrupted.into())}else{Ok(())};assert!(matches!(collect(&pages,&config,&order,&root,&poll),Err(Failure::Operational(error))if error.kind()==io::ErrorKind::OutOfMemory));let data=collect(&pages,&config,&order,&Budget::new(64*1024*1024).unwrap(),&||Ok(())).unwrap();assert_eq!(data.sites().len(),16);
}
#[test]fn key_marker_full_entry_uses_actual_growth_beyond_finite_count_and_preserves_old_limit(){
 let text="SOURCE_DEF(x)\n".repeat(10_001);let counter=Budget::new(64*1024*1024).unwrap();let budget=Budget::scoped_temporaries(&counter).unwrap();let temporary=Budget::scoped_temporaries(&counter).unwrap();let mut rows=Vec::new();let mut count=0;crate::captured_marker_rows::collect_file_funded("code/many.dm",&text,&budget,&temporary,crate::keys_policy::MARKERS,false,false,false,&mut rows,&mut count,&mut||Ok::<_,Failure>(())).unwrap();assert_eq!(count,10_001);assert_eq!(rows.len(),10_001);drop(rows);
 let finite_budget=Budget::new(64*1024*1024).unwrap();let mut finite=Vec::new();let mut finite_count=0;assert!(crate::captured_marker_rows::collect_file_admitted("code/many.dm",&text,&finite_budget,crate::keys_policy::MARKERS,false,false,false,&mut finite,&mut finite_count,&mut||Ok::<_,Failure>(())).is_err());drop(finite);drop(finite_budget);
}
#[test]fn key_file_local_head_regex_line_and_allow_work_retires_before_next_original_file(){
 let root=std::env::current_dir().unwrap().join("keys-original-file-scratch");let path=root.join("code/padding.dm");let source=format!("// {}\n{}// ALLOW(cache): world.Export() is a blocking external call\n","x".repeat(64*1024),"\n".repeat(1000));let budget=Budget::new(64*1024*1024).unwrap();let phase=Budget::scoped_temporaries(&budget).unwrap();let before=budget.used();let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();
 for index in 0..80{let mut projection=Projection::default();crate::captured_raw_file::with_original_policy_file_prepared(&root,&path,0,&budget,|local|{local.charge(source.len().checked_mul(4).and_then(|n|n.checked_add(8192)).unwrap()).map_err(|m|oom(local,m))?;Ok(dm_preprocess::SourceText::from(source.clone()))},&mut|relative,views|{projection.file(relative,views,&phase,&||Ok(()))?;Ok(true)}).unwrap();assert_eq!(projection.count,0);assert!(projection.entry_ops.is_empty()&&projection.defines.is_empty()&&projection.key_refs.is_empty()&&projection.bad_sources.is_empty()&&projection.allows.is_empty());drop(projection);assert_eq!(budget.used(),before+(index+1)*fixed,"only existing fixed FileScratch metadata may survive; no per-file line/head/regex buffers escape");}
}
