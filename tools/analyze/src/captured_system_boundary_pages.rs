//! Full original boundary policy over two source-page passes; no source authority.
use crate::{captured_generator_budget::Budget,captured_raw_file::{Config,RawPolicyViews},reactive_raw_policy_pages::RawPolicyPages,reactive_reads_native::Failure,lint::{Site,AllowUse,Sink},system_boundary_policy as policy};
use std::{io,sync::Arc};
pub struct BoundaryData{sites:Vec<Site>,source_text:Vec<String>,allow_used:Vec<AllowUse>}
impl BoundaryData{pub fn sites(&self)->&[Site]{&self.sites}pub fn source_text(&self)->&[String]{&self.source_text}pub fn allow_used(&self)->&[AllowUse]{&self.allow_used}}
fn oom(message:impl Into<String>)->Failure{Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
fn charge(b:&Budget,n:Option<usize>)->Result<(),Failure>{let n=n.ok_or_else(||{b.deny();oom("Boundary retained capacity overflow")})?;b.charge(n).map_err(oom)}
fn poll(b:&Budget,p:&dyn Fn()->io::Result<()>)->Result<(),Failure>{b.require().map_err(oom)?;p()?;b.require().map_err(oom)}
fn row<T>(b:&Budget,v:&mut Vec<T>)->Result<(),Failure>{if v.len()<v.capacity(){return Ok(())}let n=v.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||oom("Boundary vector overflow"))?;charge(b,n.checked_mul(4).and_then(|n|n.checked_mul(std::mem::size_of::<T>())).and_then(|n|n.checked_add(64)))?;v.try_reserve_exact(n-v.len()).map_err(|_|oom("Boundary allocation refused"))?;if v.capacity()>n.saturating_mul(4){b.deny();return Err(oom("Boundary exposed capacity exceeds reservation"))}Ok(())}
fn own(b:&Budget,s:&str)->Result<String,Failure>{charge(b,s.len().checked_add(64))?;Ok(s.to_owned())}
struct FileFacts{relative:String,facts:policy::Facts}
struct FileResult{relative:String,result:policy::FileOut,lines:Vec<(u32,String)>}
/// Ordinary scanner scratch remains the preexisting policy allocation baseline.
/// Every new escaped metadata row/capacity is separately funded before retention.
pub fn collect<P:RawPolicyPages+?Sized>(pages:&P,config:&Config,b:&Arc<Budget>,p:&dyn Fn()->io::Result<()>)->Result<BoundaryData,Failure>{let pending=collect_using(pages,config,b,p);if matches!(&pending,Err(Failure::Operational(_))){return pending}poll(b,p)?;pending}
fn collect_using<P:RawPolicyPages+?Sized>(pages:&P,config:&Config,b:&Arc<Budget>,p:&dyn Fn()->io::Result<()>)->Result<BoundaryData,Failure>{
 poll(b,p)?;let scope=config.borrowed_policy_scope("system_boundary","");let selected=|rel:&str|crate::dm::sys::policy_selection().matches_path(rel)&&!scope.is_some_and(|s|s.exempt(rel));
 let mut files=Vec::<FileFacts>::new();
 if !pages.for_each(&mut|rel,views|{poll(b,p)?;if !selected(rel){return Ok(true)}let file=views.source_file()?;if file.rel!=rel{return Err("Boundary original file label differs".into())}let facts=policy::facts_of(file);charge(b,policy::facts_bytes(&facts).and_then(|n|n.checked_add(64)))?;let relative=own(b,rel)?;row(b,&mut files)?;files.push(FileFacts{relative,facts});Ok(true)})?{return Err("Boundary fact source pass stopped before EOF".into())}poll(b,p)?;
 charge(b,files.len().checked_mul(2*std::mem::size_of::<FileFacts>()).and_then(|n|n.checked_add(128)))?;files.sort_by(|a,b|a.relative.cmp(&b.relative));if files.windows(2).any(|w|w[0].relative==w[1].relative){return Err("Boundary source provider repeated a file".into())}
 charge(b,files.len().checked_mul(4*std::mem::size_of::<(&str,&policy::Facts)>()).and_then(|n|n.checked_add(64)))?;let mut borrowed=Vec::new();borrowed.try_reserve_exact(files.len()).map_err(|_|oom("Boundary borrowed fact projection allocation refused"))?;if borrowed.capacity()>files.len().saturating_mul(4){b.deny();return Err(oom("Boundary fact projection capacity exceeds reservation"))}for file in &files{borrowed.push((file.relative.as_str(),&file.facts));}charge(b,policy::prepared_headroom(&borrowed))?;let prepared=policy::prepare(&borrowed);drop(borrowed);
 let mut results=Vec::<FileResult>::new();let mut allows=Vec::<AllowUse>::new();
 if !pages.for_each(&mut|rel,views:RawPolicyViews<'_>|{poll(b,p)?;if !selected(rel){return Ok(true)}let index=files.binary_search_by(|f|f.relative.as_str().cmp(rel)).map_err(|_|Failure::Unsupported("Boundary second pass added a file".into()))?;let file=views.source_file()?;if file.rel!=rel{return Err("Boundary original judgement label differs".into())}
  let mut recorded=Sink::new();let result=crate::dm::pylines::recorded_into(&mut recorded,||policy::judge_file(file,&prepared));charge(b,policy::result_bytes(&result).and_then(|n|n.checked_add(64)))?;
  for value in recorded.allow_used{poll(b,p)?;charge(b,value.rel.capacity().checked_add(value.name.capacity()).and_then(|n|n.checked_add(value.code.capacity())).and_then(|n|n.checked_add(64)))?;if !allows.contains(&value){row(b,&mut allows)?;allows.push(value)}}
  let mut lines=Vec::new();let raw=file.raw();for number in result.hits.iter().map(|(_,line,_,_)|*line).chain(result.b6.iter().map(|(_,line,_)|*line)){if !lines.iter().any(|(old,_)|*old==number){let text=if number>0&&(number as usize)<=raw.num_lines(){raw.line(number as usize)}else{""};charge(b,text.len().checked_add(64))?;row(b,&mut lines)?;lines.push((number,crate::util::normalize_ws(text)))}}
  let relative=own(b,&files[index].relative)?;row(b,&mut results)?;results.push(FileResult{relative,result,lines});Ok(true)
 })?{return Err("Boundary judgement source pass stopped before EOF".into())}poll(b,p)?;
 charge(b,results.len().checked_mul(2*std::mem::size_of::<FileResult>()).and_then(|n|n.checked_add(128)))?;results.sort_by(|a,b|a.relative.cmp(&b.relative));if results.len()!=files.len()||results.iter().zip(&files).any(|(r,f)|r.relative!=f.relative){return Err("Boundary two source passes differ".into())}
 // Final unique policy assembly has the same phase ordering as the original.
 // Move results rather than duplicating retained findings.
 charge(b,results.len().checked_mul(4*std::mem::size_of::<(String,policy::FileOut)>()).and_then(|n|n.checked_add(128)))?;
 let mut lines=Vec::new();let mut ordered=Vec::new();for result in results{row(b,&mut lines)?;lines.push((own(b,&result.relative)?,result.lines));row(b,&mut ordered)?;ordered.push((result.relative,result.result));}
 let final_headroom=ordered.iter().try_fold(8192usize,|n,(_,r)|policy::result_bytes(r).and_then(|bytes|bytes.checked_mul(8)).and_then(|bytes|n.checked_add(bytes))) ;charge(b,final_headroom)?;
 let mut sink=Sink::new();policy::finish(&prepared,&ordered,&mut sink);let mut text=Vec::new();for site in &sink.sites{poll(b,p)?;let source=if site.line==0{None}else{lines.binary_search_by(|(rel,_)|rel.as_str().cmp(&site.rel)).ok().and_then(|i|lines[i].1.iter().find(|(line,_)|*line==site.line)).map(|(_,text)|text.as_str())};row(b,&mut text)?;text.push(own(b,source.unwrap_or(""))?);}
 poll(b,p)?;Ok(BoundaryData{sites:sink.sites,source_text:text,allow_used:allows})
}
#[cfg(all(test,feature="legacy-sem"))]#[path="system_boundary_report_frozen_original.rs"]mod original;
#[cfg(all(test,feature="legacy-sem"))]mod tests{
 use super::*;use crate::{captured_raw_file::{File,Config},captured_raw_policy::Configuration,lint::{Registry,Cx},tree::{Tree,SourceFile}};use std::cell::Cell;
 struct Pages{files:Vec<(String,String)>,calls:Cell<usize>,stop:Option<usize>,fail:Option<usize>}
 impl RawPolicyPages for Pages{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let pass=self.calls.get();self.calls.set(pass+1);if self.fail==Some(pass){return Err(Failure::Operational(io::Error::from_raw_os_error(1450)))}let root=std::env::current_dir().unwrap();for(rel,text)in &self.files{let file=File::capture(&root,&root.join(rel),text.clone().into())?;if !file.with_policy_views(visit)?{return Ok(false)}}Ok(self.stop!=Some(pass))}}
 fn pages()->Pages{Pages{files:vec![
  ("code/alpha/model.dm".into(),"SYSTEM_DEF(alpha)\nGLOBAL_DATUM_INIT(alpha_service, /datum/world_service/alpha)\n/datum/system/alpha\n    needs = list(/datum/system/beta, /datum/system/missing)\n    uses = list()\n    emits = list(/datum/om/event/good)\n    OM_EMIT(/datum/om/event/bad)\n".into()),
  ("code/alpha/api.dm".into(),"/datum/system/alpha/proc/allowed()\n    return 1\n".into()),
  ("code/beta/model.dm".into(),"/datum/system/beta\n    needs = list(/datum/system/alpha)\n    uses = list()\n    system(/datum/system/alpha).allowed()\n".into()),
  ("code/gamma/model.dm".into(),"/datum/system/gamma\n".into()),
  ("code/gamma/api.dm".into(),"/datum/system/gamma/proc/unused()\n    return 0\n".into()),
  ("maps/client.dm".into(),"/datum/world/client()\n    SSalpha.hidden\n    GLOB.alpha_service.hidden\n    system(/datum/system/alpha).secret()\n    system(/datum/system/beta).secret()\n    SSalpha.held // ALLOW(system_boundary): this frozen fixture checks exact annotation replay\n/datum/system/alpha/proc/outside()\n    return 1\n".into())],calls:Cell::new(0),stop:None,fail:None}}
 #[test]fn boundary_two_pass_complete_sites_order_text_and_allows_match_whole_original(){
  for bytes in [None,Some(br#"[lint.system_boundary]
exempt_files=['maps/client.dm']
"#.as_slice())]{let p=pages();let tree=Tree::from_files(p.files.iter().map(|(rel,text)|SourceFile::from_text(rel,text)).collect());let mut registry=Registry::default();original::register(&mut registry);let lint=registry.find("system_boundary").unwrap();let scopes=bytes.map(|bytes|crate::scopes::Scopes::parse(std::str::from_utf8(bytes).unwrap()).unwrap()).unwrap_or_default();let scope=scopes.for_lint("system_boundary","");let mut expected=Sink::new();lint.scan_tree(&Cx{tree:&tree,meta:lint.meta(),scope:&scope},&mut expected);let config=Config::capture(bytes.map_or(Configuration::ProvenMissing,Configuration::Captured)).unwrap();let actual=collect(&p,&config,&Budget::new(32*1024*1024).unwrap(),&||Ok(())).unwrap();assert_eq!(p.calls.get(),2);assert_eq!(actual.sites(),expected.sites);assert_eq!(actual.allow_used(),expected.allow_used);for(site,text)in actual.sites().iter().zip(actual.source_text()){assert_eq!(*text,tree.site_text(&site.rel,site.line as usize));}if bytes.is_none(){for rule in ["B1","B2","B3","B4","B5","B6","B7"]{assert!(actual.sites().iter().any(|site|site.rule==rule),"missing real fixture rule {rule}")}assert!(!actual.allow_used().is_empty());}}
 }
 #[test]fn boundary_two_pass_quota_io_stopped_and_late_cancel_refuse_without_partial_output(){
  let config=Config::capture(Configuration::ProvenMissing).unwrap();for stop in [0,1]{let mut p=pages();p.stop=Some(stop);assert!(collect(&p,&config,&Budget::new(32*1024*1024).unwrap(),&||Ok(())).is_err());}let mut p=pages();p.fail=Some(1);let error=collect(&p,&config,&Budget::new(32*1024*1024).unwrap(),&||Ok(())).err().unwrap();assert!(matches!(error,Failure::Operational(ref e)if e.raw_os_error()==Some(1450)));let p=pages();let error=collect(&p,&config,&Budget::new(std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>()).unwrap(),&||Ok(())).err().unwrap();assert!(matches!(error,Failure::Operational(ref e)if e.kind()==io::ErrorKind::OutOfMemory));let p=pages();let error=collect(&p,&config,&Budget::new(32*1024*1024).unwrap(),&||if p.calls.get()==2{Err(io::Error::new(io::ErrorKind::Interrupted,"actual final cancellation"))}else{Ok(())}).err().unwrap();assert!(matches!(error,Failure::Operational(ref e)if e.kind()==io::ErrorKind::Interrupted));let p=pages();assert!(collect(&p,&config,&Budget::new(32*1024*1024).unwrap(),&||Ok(())).is_ok());
 }
}
