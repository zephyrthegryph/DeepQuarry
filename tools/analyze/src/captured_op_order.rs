//! Complete op_order DATA fold over authentic whole CODE loans and fixed raw manifest.
//! Neither this DATA nor provider booleans issue source/EOF/model authority.
use crate::{op_order_policy as judge,captured_api_pages as fund,captured_generator_budget::Budget,captured_raw_file::Config,captured_reactive_reads::Failure,captured_allow_annotations::PatternOperation,reactive_raw_policy_pages::RawPolicyPages,lint::{Site,AllowUse}};
use std::{collections::{BTreeMap,HashMap},sync::Arc,io};
pub struct Data{pub(crate)sites:Vec<Site>,pub(crate)source_text:Vec<String>,pub(crate)allow_used:Vec<AllowUse>,pub(crate)digests:BTreeMap<String,[u8;20]>}
fn empty()->Data{Data{sites:Vec::new(),source_text:Vec::new(),allow_used:Vec::new(),digests:BTreeMap::new()}}
struct Phase{budget:Arc<Budget>,complete:bool}impl Drop for Phase{fn drop(&mut self){if !self.complete{self.budget.keep_failed_scratch()}}}
fn oom(b:&Budget)->Failure{b.deny();Failure::Operational(io::ErrorKind::OutOfMemory.into())}
fn charge(b:&Budget,n:Option<usize>)->Result<(),Failure>{b.charge(n.ok_or_else(||oom(b))?).map_err(|_|oom(b))}
fn selected(c:&Config,path:&str)->bool{!c.policy_path_exempt("op_order","",path)&&!path.starts_with("code/engine/_generated/")}
fn allowed(data:&mut Data,file:&crate::tree::SourceFile,line:usize,b:&Budget,local:&Budget,poll:&dyn Fn()->io::Result<()>,patterns:Option<&dyn crate::native_pattern::Provider>)->Result<bool,Failure>{
 fund::checked(b,poll)?;let raw=file.raw();let mut operation=PatternOperation{patterns,budget:local,poll};let mut kept=None;
 if line>=1&&line<=raw.num_lines(){if let Some(code)=crate::allow::keeps_with(raw.line(line),"op_order",&mut operation)?{kept=Some((line,code));}}
 if kept.is_none()&&line>=2{let above=raw.line(line-1);if crate::util::py_lstrip(above).starts_with("//"){if let Some(code)=crate::allow::keeps_with(above,"op_order",&mut operation)?{kept=Some((line-1,code));}}}
 let Some((at,code))=kept else{return Ok(false)};let code=code.unwrap_or_default();let line=u32::try_from(at).map_err(|_|oom(b))?;
 if !data.allow_used.iter().any(|u|u.rel==file.rel&&u.line==line&&u.name=="op_order"&&u.code==code){fund::row(b,poll,&mut data.allow_used)?;data.allow_used.push(AllowUse{rel:fund::own(b,poll,&file.rel)?,line,name:fund::own(b,poll,"op_order")?,code:fund::own(b,poll,&code)?});}
 if !data.digests.contains_key(file.rel.as_str()){fund::node(b)?;data.digests.insert(fund::own(b,poll,&file.rel)?,crate::captured_raw_file::source_allow_digest(file));}Ok(true)
}
fn finding(data:&mut Data,file:&crate::tree::SourceFile,rule:&str,line:usize,msg:&str,key:&str,b:&Budget,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{
 fund::checked(b,poll)?;fund::row(b,poll,&mut data.sites)?;fund::row(b,poll,&mut data.source_text)?;
 let raw=file.line(line);charge(b,raw.len().checked_mul(4).and_then(|n|n.checked_add(256)))?;data.source_text.push(crate::util::normalize_ws(raw));
 data.sites.push(Site{rule:fund::own(b,poll,rule)?,rel:fund::own(b,poll,&file.rel)?,line:u32::try_from(line).map_err(|_|oom(b))?,msg:fund::own(b,poll,msg)?,key:fund::own(b,poll,key)?,ident:String::new()});Ok(())
}
fn append(to:&mut Data,mut from:Data,b:&Budget,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{
 fund::reserve_append(b,poll,&mut to.sites,from.sites.len())?;fund::reserve_append(b,poll,&mut to.source_text,from.source_text.len())?;fund::reserve_append(b,poll,&mut to.allow_used,from.allow_used.len())?;
 to.sites.append(&mut from.sites);to.source_text.append(&mut from.source_text);to.allow_used.append(&mut from.allow_used);for(path,digest)in from.digests{fund::node(b)?;to.digests.insert(path,digest);}Ok(())
}
pub fn collect(pages:&dyn RawPolicyPages,order:&HashMap<String,usize>,config:&Config,root:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Data,Failure>{collect_using(pages,order,config,root,poll,None)}
#[cfg(feature="native-policy")]
pub fn collect_with_patterns(pages:&dyn RawPolicyPages,order:&HashMap<String,usize>,config:&Config,root:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,patterns:&dyn crate::native_pattern::Provider)->Result<Data,Failure>{collect_using(pages,order,config,root,poll,Some(patterns))}
fn collect_using(pages:&dyn RawPolicyPages,order:&HashMap<String,usize>,config:&Config,root:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,patterns:Option<&dyn crate::native_pattern::Provider>)->Result<Data,Failure>{
 fund::checked(root,poll)?;let mut phase=Phase{budget:Budget::scoped_temporaries(root).map_err(|_|oom(root))?,complete:false};let b=&phase.budget;
 let pending=(||{
 let mut files=Vec::new();let mut markers=Vec::new();let mut marker_count=0;
 if !pages.for_each(&mut|relative,views|{
  fund::checked(b,poll)?;let file=views.source_file()?;if relative!=file.rel{return Err("op_order original index relative path differs".into())}let local=views.allocation_budget(root);
  let gate=judge::Controlled::new(PatternOperation{patterns,budget:local,poll});let facts=judge::file_facts_using(file,&gate);let facts=gate.finish(facts)?;
  charge(b,facts.storage_bytes())?;fund::row(b,poll,&mut files)?;files.push((fund::own(b,poll,relative)?,facts));
  crate::captured_marker_rows::collect_file_funded(relative,views.marker()?,b,local,&["CAPABILITIES","CAPABILITY_TYPE","CAPABILITY_DEF"],true,true,false,&mut markers,&mut marker_count,&mut||{fund::checked(b,poll)})?;
  fund::checked(local,poll)?;Ok(true)
 })?{return Err("op_order actual constructor/marker phase stopped before EOF".into())}
 crate::key_policy_control::sort_data(&mut files,&mut|a,c|->Result<std::cmp::Ordering,Failure>{fund::checked(b,poll)?;Ok(a.0.cmp(&c.0))})?;
 crate::key_policy_control::sort_data(&mut markers,&mut|a,c|->Result<std::cmp::Ordering,Failure>{fund::checked(b,poll)?;Ok((order.get(&a.rel).copied().unwrap_or(usize::MAX),a.rel.as_str(),a.line).cmp(&(order.get(&c.rel).copied().unwrap_or(usize::MAX),c.rel.as_str(),c.line)))})?;
 let mut marker_views=Vec::new();fund::reserve_append(b,poll,&mut marker_views,markers.len())?;for m in &markers{fund::checked(b,poll)?;marker_views.push(judge::Marker{name:&m.name,relative:&m.rel,line:m.line,args:&m.args});}
 let gate=judge::Controlled::new(PatternOperation{patterns,budget:b,poll});let model=judge::Model::from_facts_using(files.into_iter().map(|(_,f)|f),&marker_views,&gate);let model=gate.finish(model)?;
 let mut file_batches=Vec::new();let mut clash_batches=Vec::new();
 if !pages.for_each(&mut|relative,views|{
  fund::checked(b,poll)?;if !selected(config,relative){return Ok(true)}let file=views.source_file()?;if relative!=file.rel{return Err("op_order actual judge relative path differs".into())}let local=views.allocation_budget(root);
  let mut relative_data=empty();let mut actual=None;let gate=judge::Controlled::new(PatternOperation{patterns,budget:local,poll});
  judge::relative_priority_using(file,|line|{if actual.is_some(){return false}let result=(||{if !allowed(&mut relative_data,file,line,root,local,poll,patterns)?{finding(&mut relative_data,file,"relative_priority",line,file.line(line).trim(),"relative_priority",root,poll)?;}Ok::<_,Failure>(())})();if let Err(error)=result{actual=Some(error)}actual.is_none()},&gate);
  if let Some(error)=actual{return Err(error)}gate.finish(())?;fund::row(b,poll,&mut file_batches)?;file_batches.push((fund::own(b,poll,relative)?,relative_data));
  for(index,m)in marker_views.iter().enumerate(){
   fund::checked(b,poll)?;if m.name!="CAPABILITIES"||m.relative!=relative{continue}let gate=judge::Controlled::new(PatternOperation{patterns,budget:local,poll});let found=model.judge_using(m.args,&gate);let found=gate.finish(found)?;let mut data=empty();
   for clash in found{fund::checked(b,poll)?;if !allowed(&mut data,file,m.line as usize,root,local,poll,patterns)?{finding(&mut data,file,"unordered_clash",m.line as usize,&clash.message,&clash.key,root,poll)?;}}
   fund::row(b,poll,&mut clash_batches)?;clash_batches.push((index,data));
  }
  fund::checked(local,poll)?;Ok(true)
 })?{return Err("op_order actual selected relative/clash phase stopped before EOF".into())}
 crate::key_policy_control::sort_data(&mut file_batches,&mut|a,c|->Result<std::cmp::Ordering,Failure>{fund::checked(b,poll)?;Ok(a.0.cmp(&c.0))})?;
 crate::key_policy_control::sort_data(&mut clash_batches,&mut|a,c|->Result<std::cmp::Ordering,Failure>{fund::checked(b,poll)?;Ok(a.0.cmp(&c.0))})?;
 let mut data=empty();for(_,batch)in file_batches{fund::checked(b,poll)?;append(&mut data,batch,root,poll)?;}for(_,batch)in clash_batches{fund::checked(b,poll)?;append(&mut data,batch,root,poll)?;}
 drop(model);drop(marker_views);drop(markers);fund::checked(b,poll)?;Ok(data)
 })();if matches!(&pending,Err(Failure::Operational(_))){return pending}fund::checked(root,poll)?;phase.complete=pending.is_ok();drop(phase);pending
}

impl Data{pub fn sites(&self)->&[Site]{&self.sites}pub fn source_text(&self)->&[String]{&self.source_text}pub fn allow_used(&self)->&[AllowUse]{&self.allow_used}}
