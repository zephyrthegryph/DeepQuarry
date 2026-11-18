//! Source-neutral Hygiene fold. A completed DATA callback is not source authority.
use crate::{captured_generator_budget::Budget,captured_raw_file::{RawPolicyViews,Config},reactive_raw_policy_pages::RawPolicyPages,reactive_reads_native::Failure,lint::{AllowUse,Site,Sink}};
use crate::captured_allow_annotations::PatternOperation;
use std::{io,sync::Arc};
/// Same original descriptor builder, independent of the legacy scan callback.
pub fn metadata()->&'static crate::lint::Meta{static META:std::sync::OnceLock<crate::lint::Meta>=std::sync::OnceLock::new();META.get_or_init(||crate::dm::sys::module_metadata(&crate::dm::sys::SysModule{name:crate::allow_registry_fields::sys_hygiene::SCOPE_MODULE_NAME,rules:crate::sys_hygiene_policy::RULES,..crate::dm::sys::SysModule::DEFAULT},crate::lint::ScanKind::Tree))}
pub fn selected_roots()->&'static[(&'static str,&'static str)]{crate::dm::sys::policy_selection().roots}
pub fn selects_path(relative:&str)->bool{crate::dm::sys::policy_selection().matches_path(relative)}
/// Owned finding/baseline text only; no provider completion or source receipt.
pub struct HygieneData{pub(crate) sites:Vec<Site>,pub(crate) source_text:Vec<String>,pub(crate) allow_used:Vec<AllowUse>,allow_digests:std::collections::BTreeMap<String,[u8;20]>}
impl HygieneData{
 pub fn sites(&self)->&[Site]{&self.sites}
 pub fn source_text(&self)->&[String]{&self.source_text}
 pub fn allow_used(&self)->&[AllowUse]{&self.allow_used}
 pub fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>{self.allow_digests.get(relative)}
}
struct Contribution{relative:String,sites:[Vec<(Site,String)>;3],allowed:[Vec<AllowUse>;3],extra:Vec<AllowUse>,digest:Option<[u8;20]>}
fn oom(message:impl Into<String>)->Failure{Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
fn charge(budget:&Budget,bytes:Option<usize>)->Result<(),Failure>{let bytes=bytes.ok_or_else(||{budget.deny();oom("Hygiene retained capacity overflow")})?;budget.charge(bytes).map_err(oom)}
fn poll(budget:&Budget,checkpoint:&dyn Fn()->io::Result<()>)->Result<(),Failure>{budget.require().map_err(oom)?;checkpoint()?;budget.require().map_err(oom)}
fn row<T>(budget:&Budget,rows:&mut Vec<T>)->Result<(),Failure>{if rows.len()<rows.capacity(){return Ok(())}let cap=rows.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||oom("Hygiene row capacity overflow"))?;charge(budget,cap.checked_mul(4).and_then(|n|n.checked_mul(std::mem::size_of::<T>())).and_then(|n|n.checked_add(64)))?;rows.try_reserve_exact(cap-rows.len()).map_err(|_|oom("Hygiene row allocation refused"))?;if rows.capacity()>cap.saturating_mul(4){budget.deny();return Err(oom("Hygiene exposed row capacity exceeded reservation"))}Ok(())}
fn own(budget:&Budget,text:&str)->Result<String,Failure>{charge(budget,text.len().checked_add(64))?;Ok(text.to_owned())}
fn push_allow(budget:&Budget,out:&mut Vec<AllowUse>,value:AllowUse)->Result<(),Failure>{if !out.contains(&value){row(budget,out)?;out.push(value)}Ok(())}
fn allow_charge(budget:&Budget,value:&AllowUse)->Result<(),Failure>{charge(budget,value.rel.capacity().checked_add(value.name.capacity()).and_then(|n|n.checked_add(value.code.capacity())).and_then(|n|n.checked_add(std::mem::size_of::<AllowUse>()+64)))}
/// SAME one-file judge is called exactly once; all borrowed views die in this loan.
fn contribution(views:RawPolicyViews<'_>,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>,patterns:Option<&dyn crate::native_pattern::Provider>)->Result<Contribution,Failure>{
 poll(budget,checkpoint)?;let file=views.source_file()?;
 // The original judge's private scanner/regex scratch remains the same existing
 // baseline. New owned findings and every escaped row are funded separately.
 struct ExtraCleanup;impl Drop for ExtraCleanup{fn drop(&mut self){let mut discarded=Sink::new();crate::dm::sys::drain_extra(&mut discarded);}}
 let cleanup=ExtraCleanup;let native=patterns.map(|provider|crate::raw_fixture_policy::Fixture::scanned(budget,checkpoint,provider,file)).transpose().map_err(pattern_failure)?;let legacy=crate::raw_fixture_policy::Fixture::legacy();let fixture=native.as_ref().unwrap_or(&legacy);let judged=crate::sys_hygiene_policy::judge_with_fixture(file,fixture);if let Some(actual)=fixture.take_scan_failure(){return Err(pattern_failure(actual))}
 let mut extra=Sink::new();crate::dm::sys::drain_extra(&mut extra);drop(cleanup);
 let mut result=Contribution{relative:own(budget,&file.rel)?,sites:std::array::from_fn(|_|Vec::new()),allowed:std::array::from_fn(|_|Vec::new()),extra:Vec::new(),digest:None};
 for value in extra.allow_used{poll(budget,checkpoint)?;allow_charge(budget,&value)?;row(budget,&mut result.extra)?;result.extra.push(value)}
 for (phase,line) in judged{
  poll(budget,checkpoint)?;let phase=phase as usize;let rule=crate::sys_hygiene_policy::RULES.get(phase).ok_or("Hygiene original rule ordinal unavailable")?.name;
  let allow_name=format!("sys_{rule}");
  if let Some(kept)=crate::allow::kept_using(file,line as usize,&allow_name,&mut PatternOperation{budget:views.allocation_budget(budget),poll:checkpoint,patterns})?{
   let value=AllowUse{rel:own(budget,&file.rel)?,line:kept.line as u32,name:own(budget,&allow_name)?,code:kept.code.unwrap_or_default()};charge(budget,value.code.capacity().checked_add(64))?;push_allow(budget,&mut result.allowed[phase],value)?;continue
  }

  let raw=file.raw();let text=if line>=1 && (line as usize)<=raw.num_lines(){let source=raw.line(line as usize);charge(budget,source.len().checked_add(64))?;crate::util::normalize_ws(source)}else{String::new()};
  let site=Site{rule:own(budget,rule)?,rel:own(budget,&file.rel)?,line,msg:String::new(),key:String::new(),ident:String::new()};row(budget,&mut result.sites[phase])?;result.sites[phase].push((site,text));
 }
 if !result.extra.is_empty()||result.allowed.iter().any(|rows|!rows.is_empty()){result.digest=Some(crate::captured_raw_file::source_allow_digest(file));}
 poll(budget,checkpoint)?;Ok(result)
}
/// Ordered unsealed DATA. Provider EOF is checked, but only the real host's
/// private selected-domain completion may authorize publication.
pub fn collect<P:RawPolicyPages+?Sized>(pages:&P,configuration:&Config,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>)->Result<HygieneData,Failure>{
 let pending=collect_using(pages,configuration,budget,checkpoint,None);if matches!(&pending,Err(Failure::Operational(_))){return pending}poll(budget,checkpoint)?;pending
}
pub fn collect_with_patterns<P:RawPolicyPages+?Sized>(pages:&P,configuration:&Config,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>,patterns:&dyn crate::native_pattern::Provider)->Result<HygieneData,Failure>{let pending=collect_using(pages,configuration,budget,checkpoint,Some(patterns));if matches!(&pending,Err(Failure::Operational(_))){return pending}poll(budget,checkpoint)?;pending}
fn collect_using<P:RawPolicyPages+?Sized>(pages:&P,configuration:&Config,budget:&Arc<Budget>,checkpoint:&dyn Fn()->io::Result<()>,patterns:Option<&dyn crate::native_pattern::Provider>)->Result<HygieneData,Failure>{
 poll(budget,checkpoint)?;let scope=configuration.borrowed_policy_scope("sys/hygiene","sys");let mut files:Vec<Contribution>=Vec::new();
 let exhausted=pages.for_each(&mut|relative,views|{poll(budget,checkpoint)?;if !selects_path(relative)||scope.is_some_and(|scope|scope.exempt(relative)){return Ok(true)}if views.source_file()?.rel!=relative{return Err("Hygiene file label differs from original view".into())}let value=contribution(views,budget,checkpoint,patterns)?;row(budget,&mut files)?;files.push(value);Ok(true)})?;
 if !exhausted{return Err("Hygiene selected source traversal stopped before EOF".into())}poll(budget,checkpoint)?;
 charge(budget,files.len().checked_mul(std::mem::size_of::<Contribution>()).and_then(|n|n.checked_mul(2)).and_then(|n|n.checked_add(128)))?;files.sort_by(|a,b|a.relative.cmp(&b.relative));
 let mut result=HygieneData{sites:Vec::new(),source_text:Vec::new(),allow_used:Vec::new(),allow_digests:std::collections::BTreeMap::new()};
 // Old Sys wrapper first drains the complete judge's auxiliary ALLOW trace.
 for file in &mut files{for value in file.extra.drain(..){push_allow(budget,&mut result.allow_used,value)?;}}
 // Old Hygiene emits rule phases across ALL files, retaining stable ties.
 for phase in 0..3{for file in &mut files{
  poll(budget,checkpoint)?;for value in file.allowed[phase].drain(..){push_allow(budget,&mut result.allow_used,value)?;}
  for(site,text)in file.sites[phase].drain(..){row(budget,&mut result.sites)?;row(budget,&mut result.source_text)?;result.sites.push(site);result.source_text.push(text)}
 }}
 for file in files{if let Some(digest)=file.digest{poll(budget,checkpoint)?;charge(budget,Some(1024+std::mem::size_of::<(String,[u8;20])>()))?;result.allow_digests.insert(file.relative,digest);}}
 poll(budget,checkpoint)?;Ok(result)
}

#[cfg(all(test,feature="legacy-sem"))]
#[path="sys_hygiene_frozen_original.rs"]mod original;
#[cfg(all(test,feature="legacy-sem"))]mod tests{
 use super::*;use crate::{lint::{Cx,Registry,Sink},tree::{Tree,SourceFile},captured_raw_file::{File,Config},captured_raw_policy::Configuration};use std::{path::PathBuf,cell::Cell};
 const BODY:&str="/obj/probe
	var/cached_charge
/obj/probe/process()
	if(world.time > next_move) // ALLOW(sys_deadline_poll): this deadline is intentionally tested as raw policy data
		return
	cached_charge = 4
	// ALLOW(scheduler): baseline when ci was wired
";
 struct Pages{root:PathBuf,files:Vec<(String,String)>,stop:bool,fail:Option<usize>}
 impl RawPolicyPages for Pages{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{for(index,(rel,text))in self.files.iter().enumerate(){if self.fail==Some(index){return Err(Failure::Operational(io::Error::from_raw_os_error(1450)))}let file=File::capture(&self.root,&self.root.join(rel),text.clone().into())?;if !file.with_policy_views(visit)?{return Ok(false)}}Ok(!self.stop)}}
 fn pages()->Pages{Pages{root:std::env::current_dir().unwrap(),files:vec![("maps/z.dm".into(),BODY.into()),("code/a.dm".into(),BODY.into()),("code/.hidden.dm".into(),BODY.into()),("code/modules/tgs/exempt.dm".into(),BODY.into())],stop:false,fail:None}}

 #[test]fn hygiene_whole_original_findings_exceed_finite_fixture_cardinality(){let mut p=pages();let seed=p.files[0].1.lines().filter(|line|!line.contains("ALLOW(")).collect::<Vec<_>>().join("\n")+"\n";p.files.retain(|(rel,_)|rel.starts_with("maps/"));for index in 0..101{p.files.push((format!("code/large{index:04}.dm"),seed.repeat(101)));}let tree=Tree::from_files(p.files.iter().map(|(rel,text)|SourceFile::from_text(rel,text)).collect());let mut registry=Registry::default();super::original::register(&mut registry);let lint=registry.find("sys/hygiene").unwrap();let scopes=crate::scopes::Scopes::default();let scope=scopes.for_lint("sys/hygiene","sys");let mut expected=Sink::new();lint.scan_tree(&Cx{ fixture:None,tree:&tree,meta:lint.meta(),scope:&scope},&mut expected);assert_eq!(expected.sites.iter().filter(|row|row.rule=="cached_var").count(),101*101*102+2,"each original same-name declaration scans all same-name writes, including the map control");assert_eq!(expected.sites.len(),101*101*102+3);let config=Config::capture(Configuration::ProvenMissing).unwrap();let budget=Budget::new(256*1024*1024).unwrap();let error=collect(&p,&config,&budget,&||Ok(())).err().expect("the unchanged million-row original cross product exceeds this retained admission and cannot publish partial rows");assert!(matches!(error,Failure::Operational(ref actual)if actual.kind()==io::ErrorKind::OutOfMemory));assert!(budget.denied());}
 #[test]fn hygiene_unique_variable_large_fold_matches_whole_original_without_cross_product(){let mut p=pages();p.files.retain(|(rel,_)|rel.starts_with("maps/"));for file in 0..101{let mut text=format!("/obj/large{file}\n");for index in 0..101{text.push_str(&format!("\tvar/cached_v{index}\n"));}text.push_str(&format!("/obj/large{file}/process()\n"));for index in 0..101{text.push_str(&format!("\tcached_v{index} = 4\n"));}p.files.push((format!("code/large{file:04}.dm"),text));}let tree=Tree::from_files(p.files.iter().map(|(rel,text)|SourceFile::from_text(rel,text)).collect());let mut registry=Registry::default();super::original::register(&mut registry);let lint=registry.find("sys/hygiene").unwrap();let scopes=crate::scopes::Scopes::default();let scope=scopes.for_lint("sys/hygiene","sys");let mut expected=Sink::new();lint.scan_tree(&Cx{ fixture:None,tree:&tree,meta:lint.meta(),scope:&scope},&mut expected);assert_eq!(expected.sites.iter().filter(|row|row.rule=="cached_var").count(),2*101*101+2);assert_eq!(expected.sites.len(),2*101*101+3);let config=Config::capture(Configuration::ProvenMissing).unwrap();let actual=collect(&p,&config,&Budget::new(256*1024*1024).unwrap(),&||Ok(())).unwrap();assert_eq!(actual.sites(),expected.sites);assert_eq!(actual.allow_used(),expected.allow_used);for(site,text)in actual.sites().iter().zip(actual.source_text()){assert_eq!(*text,tree.site_text(&site.rel,site.line as usize));}}
 #[test]fn hygiene_completed_report_descriptor_and_allow_fingerprints_match_full_frozen_original(){
  let mut reg=Registry::default();super::original::register(&mut reg);let meta=metadata();assert_eq!((meta.name,meta.group,meta.label,meta.legacy),("sys/hygiene","sys","sys/hygiene","tools/ci/sys_lint.py"));assert_eq!(meta.scan,crate::lint::ScanKind::Tree);assert_eq!(meta.allow,&["sys_annotation_boilerplate","sys_cached_var","sys_deadline_poll"]);assert!(meta.lists.is_empty());assert_eq!(format!("{:?}",meta.rules),format!("{:?}",reg.find("sys/hygiene").unwrap().meta().rules));match meta.policy{crate::lint::Policy::Sites{baseline,header,banned}=>{assert_eq!(baseline,"tools/ci/sys_baseline/hygiene.txt");assert_eq!(header,&["sys_lint baseline for tools/ci/sys_rules/hygiene.py (doc/rewrite/systems.md); shrink-only, target 0"]);assert!(banned.is_empty());},_=>panic!("original Sites report policy")};assert!(meta.select.matches_path("code/probe.dm")&&meta.select.matches_path("maps/probe.dm"));assert!(!meta.select.matches_path("code/.hidden/probe.dm"));let p=pages();let config=Config::capture(Configuration::ProvenMissing).unwrap();let data=collect(&p,&config,&Budget::new(8*1024*1024).unwrap(),&||Ok(())).unwrap();for used in data.allow_used(){let(_,text)=p.files.iter().find(|(relative,_)|relative==&used.rel).unwrap();let file=SourceFile::from_text(&used.rel,text);let expected=crate::captured_raw_file::source_allow_digest(&file);assert_eq!(data.allow_source_digest(&used.rel),Some(&expected));}}
 #[test]fn full_hygiene_fold_matches_immutable_original_phase_file_allow_and_as_of_text(){
  let p=pages();let tree=Tree::from_files(p.files.iter().map(|(rel,text)|SourceFile::from_text(rel,text)).collect());let mut registry=Registry::default();super::original::register(&mut registry);let lint=registry.find("sys/hygiene").unwrap();
  for configuration in [None,Some(br#"[lint."sys/hygiene"]
exempt_files=['maps/z.dm']
"#.as_slice())]{let config=Config::capture(configuration.map_or(Configuration::ProvenMissing,Configuration::Captured)).unwrap();let scopes=match configuration{None=>crate::scopes::Scopes::default(),Some(bytes)=>crate::scopes::Scopes::parse(std::str::from_utf8(bytes).unwrap()).unwrap()};let scope=scopes.for_lint("sys/hygiene","sys");let cx=Cx{ fixture:None,tree:&tree,meta:lint.meta(),scope:&scope};let mut expected=Sink::new();lint.scan_tree(&cx,&mut expected);let budget=Budget::new(8*1024*1024).unwrap();let actual=collect(&p,&config,&budget,&||Ok(())).unwrap();assert_eq!(actual.sites(),expected.sites);assert_eq!(actual.allow_used(),expected.allow_used);assert!(actual.sites().iter().any(|s|s.rule=="cached_var"));assert!(actual.sites().iter().any(|s|s.rule=="annotation_boilerplate"));assert!(actual.allow_used().iter().any(|u|u.name=="sys_deadline_poll"));for(site,text)in actual.sites().iter().zip(actual.source_text()){assert_eq!(*text,tree.site_text(&site.rel,site.line as usize));}}
 }
 #[test]fn hygiene_unsealed_data_refuses_stopped_provider_actual_io_quota_and_recovers(){let p=pages();let config=Config::capture(Configuration::ProvenMissing).unwrap();let budget=Budget::new(8*1024*1024).unwrap();let mut stopped=pages();stopped.stop=true;assert!(collect(&stopped,&config,&budget,&||Ok(())).is_err());let mut failure=pages();failure.fail=Some(1);let error=collect(&failure,&config,&Budget::new(8*1024*1024).unwrap(),&||Ok(())).err().unwrap();assert!(matches!(error,Failure::Operational(ref e)if e.raw_os_error()==Some(1450)));let budget=Budget::new(std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>()).unwrap();let error=collect(&p,&config,&budget,&||Ok(())).err().unwrap();assert!(matches!(error,Failure::Operational(ref e)if e.kind()==io::ErrorKind::OutOfMemory));assert!(collect(&p,&config,&Budget::new(8*1024*1024).unwrap(),&||Ok(())).is_ok());let polls=Cell::new(0);let error=collect(&p,&config,&Budget::new(8*1024*1024).unwrap(),&||{polls.set(polls.get()+1);if polls.get()==3{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}}).err().unwrap();assert!(matches!(error,Failure::Operational(ref e)if e.raw_os_error()==Some(1450)));}
}

#[cfg(all(test,feature="legacy-sem"))]mod final_control_tests{
 use super::*;use std::cell::Cell;
 struct Stopped<'a>(&'a Cell<bool>);impl RawPolicyPages for Stopped<'_>{fn for_each(&self,_:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{self.0.set(true);Ok(false)}}
 #[test]fn hygiene_stopped_provider_late_cancellation_preserves_final_typed_control(){let stopped=Cell::new(false);let config=Config::capture(crate::captured_raw_policy::Configuration::ProvenMissing).unwrap();let budget=Budget::new(8192).unwrap();let error=collect(&Stopped(&stopped),&config,&budget,&||if stopped.get(){Err(io::Error::new(io::ErrorKind::Interrupted,"actual final control"))}else{Ok(())}).err().unwrap();assert!(matches!(error,Failure::Operational(ref error)if error.kind()==io::ErrorKind::Interrupted));}
}

fn pattern_failure(actual:crate::derived_selftest_policy::Failure)->Failure{match actual{crate::derived_selftest_policy::Failure::Operational(actual)=>Failure::Operational(actual),crate::derived_selftest_policy::Failure::Assertion(message)=>Failure::Unsupported(message)}}
