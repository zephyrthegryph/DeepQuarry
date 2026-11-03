//! Complete silicon raw + actor DATA, requiring the current admitted Original graph.
//! Only the concrete workspace owner can certify CODE coverage/model/currentness.
use crate::{silicon_entry_policy as judge,silicon_actor_policy as actor,captured_api_pages as fund,captured_generator_budget::Budget,captured_reactive_reads::Failure,captured_raw_file::{Config,RawPolicyViews},reactive_raw_policy_pages::RawPolicyPages,captured_allow_annotations::Operation,key_policy_control::{self as kc,Control}};
use std::{sync::Arc,collections::{HashMap,BTreeSet},path::Path,io};
pub struct Data{sites:Vec<crate::lint::Site>,source_text:Vec<String>,allow_used:Vec<crate::lint::AllowUse>,digests:Vec<(String,[u8;20])>}
impl Data{
 pub fn sites(&self)->&[crate::lint::Site]{&self.sites}pub fn source_text(&self)->&[String]{&self.source_text}pub fn allow_used(&self)->&[crate::lint::AllowUse]{&self.allow_used}pub fn allow_source_digest(&self,path:&str)->Option<&[u8;20]>{self.digests.binary_search_by(|(p,_)|p.as_str().cmp(path)).ok().map(|i|&self.digests[i].1)}
 pub fn retained_charge(&self)->Option<usize>{let mut n=std::mem::size_of::<Self>().checked_add(self.sites.capacity().checked_mul(std::mem::size_of::<crate::lint::Site>())?)?.checked_add(self.source_text.capacity().checked_mul(std::mem::size_of::<String>())?)?.checked_add(self.allow_used.capacity().checked_mul(std::mem::size_of::<crate::lint::AllowUse>())?)?.checked_add(self.digests.capacity().checked_mul(std::mem::size_of::<(String,[u8;20])>())?)?;for s in &self.sites{for value in [&s.rule,&s.rel,&s.msg,&s.key,&s.ident]{n=n.checked_add(value.capacity())?;}}for s in &self.source_text{n=n.checked_add(s.capacity())?;}for a in &self.allow_used{for value in [&a.rel,&a.name,&a.code]{n=n.checked_add(value.capacity())?;}}for(path,_)in &self.digests{n=n.checked_add(path.capacity())?;}Some(n)}
 pub fn serialize_data<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{use serde::ser::SerializeTuple;let mut out=serializer.serialize_tuple(4)?;out.serialize_element(&self.sites)?;out.serialize_element(&self.source_text)?;out.serialize_element(&self.allow_used)?;out.serialize_element(&self.digests)?;out.end()}
}

struct Phase{budget:Arc<Budget>,complete:bool}impl Drop for Phase{fn drop(&mut self){if !self.complete{self.budget.keep_failed_scratch()}}}
fn oom(b:&Budget)->Failure{b.deny();Failure::Operational(io::ErrorKind::OutOfMemory.into())}
fn selected(c:&Config,p:&str)->bool{!p.starts_with("code/engine/_generated/")&&!c.policy_path_exempt("silicon_entry","",p)}
fn finish_sink(mut sink:crate::lint::Sink,file:&crate::tree::SourceFile,b:&Budget,poll:&dyn Fn()->io::Result<()>)->Result<fund::ApiData,Failure>{
 fund::checked(b,poll)?;if let Some(message)=sink.admission_error(){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))}let mut out=fund::empty();out.sites=std::mem::take(&mut sink.sites);out.allow_used=std::mem::take(&mut sink.allow_used);
 for row in &out.sites{fund::checked(b,poll)?;if row.rel!=file.rel{return Err("silicon captured output escaped its actual source file".into())}fund::row(b,poll,&mut out.source_text)?;let raw=file.line(row.line as usize);b.charge(raw.len().checked_mul(4).and_then(|n|n.checked_add(128)).ok_or_else(||oom(b))?).map_err(|_|oom(b))?;out.source_text.push(crate::util::normalize_ws(raw));}
 if !out.allow_used.is_empty(){fund::node(b)?;out.digests.insert(fund::own(b,poll,&file.rel)?,crate::captured_raw_file::source_allow_digest(file));}Ok(out)
}
fn append(out:&mut Data,mut row:fund::ApiData,b:&Budget,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{fund::reserve_append(b,poll,&mut out.sites,row.sites.len())?;fund::reserve_append(b,poll,&mut out.source_text,row.source_text.len())?;out.sites.append(&mut row.sites);out.source_text.append(&mut row.source_text);for used in row.allow_used{fund::checked(b,poll)?;if !out.allow_used.contains(&used){fund::row(b,poll,&mut out.allow_used)?;out.allow_used.push(used)}}for(path,digest)in row.digests{fund::checked(b,poll)?;if !out.digests.iter().any(|(p,_)|p==&path){fund::row(b,poll,&mut out.digests)?;out.digests.push((path,digest));}}Ok(())}
pub fn collect_available(inputs:&dm_analysis::policy_inputs::PolicyInputs,root:&Path,pages:&dyn RawPolicyPages,order:&HashMap<String,usize>,config:&Config,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,borrower:&dyn Fn(&Arc<dm_tree::frontend::BodySyntaxInput>)->Result<Arc<dm_tree::frontend::BodySyntax>,dm_tree::frontend::BodySyntaxFailure>)->Result<Data,Failure>{
 fund::checked(budget,poll)?;let mut phase=Phase{budget:Budget::scoped_temporaries(budget).map_err(|_|oom(budget))?,complete:false};let scratch=&phase.budget;
 let pending=(||{let mut batches=Vec::new();let mut macros=BTreeSet::new();
  if !pages.for_each(&mut|relative,views|{fund::checked(scratch,poll)?;let file=views.source_file()?;if file.rel!=relative{return Err("silicon current raw source path differs".into())}if !crate::tree::CODE_DM.matches(file){return Ok(true)}let local=views.allocation_budget(scratch);
   // Old actor discovery observes all handlers before any output exemption.
   for(number,line)in file.code().numbered(){fund::checked(local,poll)?;if judge::macro_line(line){scratch.charge(relative.len().checked_mul(4).and_then(|n|n.checked_add(1024)).ok_or_else(||oom(scratch))?).map_err(|_|oom(scratch))?;macros.insert((fund::own(scratch,poll,relative)?,u32::try_from(number).map_err(|_|Failure::from("silicon macro line overflow"))?));}}
   if selected(config,relative){let mut sink=crate::lint::Sink::bounded_budget(budget).map_err(|_|oom(budget))?;budget.charge(relative.len().checked_mul(4).and_then(|n|n.checked_add(128)).ok_or_else(||oom(budget))?).map_err(|_|oom(budget))?;sink.begin_captured_phase(relative);let gate=kc::Controlled::new(Operation{budget:local,poll});judge::scan_file_using(file,&mut sink,&gate);gate.finish(())?;let output=finish_sink(sink,file,budget,poll)?;fund::row(scratch,poll,&mut batches)?;batches.push((fund::own(scratch,poll,relative)?,output));}
   fund::checked(local,poll)?;Ok(true)
  })?{return Err("silicon original raw phase stopped before genuine CODE EOF".into())}
  kc::sort_data(&mut batches,&mut|a,b|->Result<std::cmp::Ordering,Failure>{fund::checked(scratch,poll)?;Ok(a.0.cmp(&b.0))})?;
  let mut out=Data{sites:Vec::new(),source_text:Vec::new(),allow_used:Vec::new(),digests:Vec::new()};for(_,batch)in batches{append(&mut out,batch,budget,poll)?;}
  let source=crate::reactive_original_source::ReadSource::native(inputs,root,scratch)?.with_checkpoint(poll).with_body_borrower(borrower).with_raw_policy_pages(pages,order);
  let rows=crate::silicon_actor_native::actor_tests(&source,&macros)?;drop(source);drop(macros);
  // Preserve old sorted actor row order. A requested raw-file search is DATA,
  // not another source acquisition or a fresh CODE-completeness assertion.
  let mut used=Vec::new();
  for row in rows{fund::checked(scratch,poll)?;if row.rel.is_empty()||!selected(config,&row.rel){continue}let mut matched=false;pages.for_each(&mut|relative,views:RawPolicyViews<'_>|{fund::checked(scratch,poll)?;if relative!=row.rel{return Ok(true)}if matched{return Err("silicon original file lookup returned duplicate source".into())}matched=true;let file=views.source_file()?;if !crate::tree::CODE_DM.matches(file){return Ok(false)}let local=views.allocation_budget(scratch);let mut sink=crate::lint::Sink::bounded_budget(budget).map_err(|_|oom(budget))?;
    if !sink.allowed(file,row.line as usize,"silicon_entry"){let mut work=Operation{budget,poll};let message=actor::describe_using(&row,&mut work)?;sink.site_in_msg(row.rule,&row.rel,row.line as usize,message);}
    let mut result=finish_sink(sink,file,budget,poll)?;result.allow_used.retain(|u|!used.contains(u));for u in &result.allow_used{fund::row(scratch,poll,&mut used)?;scratch.charge(u.rel.len().checked_add(u.name.len()).and_then(|n|n.checked_add(u.code.len())).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(128)).ok_or_else(||oom(scratch))?).map_err(|_|oom(scratch))?;used.push(u.clone());}append(&mut out,result,budget,poll)?;fund::checked(local,poll)?;Ok(false)
   })?;
  }
  kc::sort_data(&mut out.digests,&mut|a,b|->Result<std::cmp::Ordering,Failure>{fund::checked(budget,poll)?;Ok(a.0.cmp(&b.0))})?;fund::checked(scratch,poll)?;Ok(out)
 })();if matches!(&pending,Err(Failure::Operational(_))){return pending}fund::checked(budget,poll)?;phase.complete=pending.is_ok();drop(phase);pending
}
