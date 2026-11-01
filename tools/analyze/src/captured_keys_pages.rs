//! Unique key policy over actual callback-local original source pages.
//! DATA only: the host must authenticate selected Keys/current CODE EOF separately.
use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure,captured_raw_file::{Config,RawPolicyViews},captured_marker_rows::OwnedMarker,key_policy_control::{self as kc,Control},reactive_raw_policy_pages::RawPolicyPages};
use std::{collections::{BTreeMap,HashMap,HashSet},io,sync::Arc};
use crate::captured_allow_annotations::Operation;
fn oom(budget:&Budget,message:impl Into<String>)->Failure{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
fn checked(budget:&Budget,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{budget.require().map_err(|m|oom(budget,m))?;poll()?;budget.require().map_err(|m|oom(budget,m))}
fn finish<T>(pending:Result<T,Failure>,budget:&Budget,poll:&dyn Fn()->io::Result<()>)->Result<T,Failure>{if matches!(&pending,Err(Failure::Operational(_))){return pending}checked(budget,poll)?;pending}
struct Scratch{budget:Arc<Budget>,complete:bool}impl Scratch{fn new(root:&Arc<Budget>)->Result<Self,Failure>{Ok(Self{budget:Budget::scoped_temporaries(root).map_err(|m|oom(root,m))?,complete:false})}}impl Drop for Scratch{fn drop(&mut self){if !self.complete{self.budget.keep_failed_scratch()}}}
struct Annotation{code:String,comment_only:bool}
struct AllowFile{rows:BTreeMap<u32,Annotation>,digest:[u8;20]}
#[derive(Default)]struct Projection{markers:Vec<OwnedMarker>,count:usize,entry_ops:Vec<(String,String)>,defines:HashSet<String>,key_refs:Vec<crate::raw_key_calls_policy::KeyRef>,bad_sources:Vec<(String,u32,String)>,allows:BTreeMap<String,AllowFile>}
fn own(budget:&Budget,poll:&dyn Fn()->io::Result<()>,text:&str)->Result<String,Failure>{kc::own(&mut Operation{budget,poll},text)}
fn row<T>(budget:&Budget,poll:&dyn Fn()->io::Result<()>,rows:&mut Vec<T>)->Result<(),Failure>{kc::row(&mut Operation{budget,poll},rows)}
fn node(budget:&Budget)->Result<(),Failure>{budget.charge(2048).map_err(|m|oom(budget,m))}
fn define(budget:&Budget,poll:&dyn Fn()->io::Result<()>,set:&mut HashSet<String>,name:&str)->Result<(),Failure>{
 checked(budget,poll)?;if set.contains(name){return Ok(())}
 if set.len()==set.capacity(){let target=set.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||oom(budget,"key define capacity overflow"))?;let bound=target.checked_mul(4).ok_or_else(||oom(budget,"key define capacity envelope overflow"))?;budget.charge(bound.checked_mul(std::mem::size_of::<String>()+std::mem::size_of::<usize>()).and_then(|n|n.checked_add(256)).ok_or_else(||oom(budget,"key define storage overflow"))?).map_err(|m|oom(budget,m))?;set.try_reserve(1).map_err(|_|oom(budget,"key define allocation refused"))?;if set.capacity()>bound{return Err(oom(budget,"key define actual capacity exceeds admission"))}}
 set.insert(own(budget,poll,name)?);Ok(())
}
impl Projection{
 fn file(&mut self,relative:&str,views:RawPolicyViews<'_>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{
  let local=views.allocation_budget(budget);let pending=(||{
   checked(budget,poll)?;let marker=views.marker()?;
   crate::captured_marker_rows::collect_file_funded(relative,marker,budget,local,crate::keys_policy::MARKERS,true,false,false,&mut self.markers,&mut self.count,&mut||checked(budget,poll))?;
   let lines=marker.bytes().filter(|byte|*byte==b'\n').count().checked_add(1).ok_or_else(||oom(local,"key call line count overflow"))?;let bound=lines.checked_mul(4).ok_or_else(||oom(local,"key line backing overflow"))?;local.charge(bound.checked_mul(std::mem::size_of::<u32>()).and_then(|n|n.checked_add(128)).ok_or_else(||oom(local,"key line storage overflow"))?).map_err(|m|oom(local,m))?;
   let mut starts=Vec::new();starts.try_reserve_exact(lines).map_err(|_|oom(local,"key line allocation refused"))?;if starts.capacity()>bound{return Err(oom(local,"key line actual capacity exceeds admission"))}starts.push(0);for(offset,byte)in marker.bytes().enumerate(){if byte==b'\n'{starts.push(u32::try_from(offset.checked_add(1).ok_or_else(||oom(local,"key line offset overflow"))?).map_err(|_|oom(local,"key line offset exceeds original range"))?);}}
   let(entries,defines)=(&mut self.entry_ops,&mut self.defines);
   crate::raw_key_calls_policy::visit_headers_try_admitted(marker,|owner,name|{row(budget,poll,entries)?;entries.push((own(budget,poll,owner)?,own(budget,poll,name)?));Ok(())},|name|define(budget,poll,defines,name),|bytes|{checked(local,poll)?;local.charge(bytes).map_err(|m|oom(local,m))},||oom(local,"key header projection overflow"))?;
   let(keys,bad)=(&mut self.key_refs,&mut self.bad_sources);
   crate::raw_key_calls_policy::visit_calls_try_admitted(relative,marker,&starts,|value|{row(budget,poll,keys)?;let bytes=value.key.capacity().checked_add(value.call.capacity()).and_then(|n|n.checked_add(value.rel.capacity())).ok_or_else(||oom(budget,"key retained call overflow"))?;budget.charge(bytes).map_err(|m|oom(budget,m))?;keys.push(value);Ok(())},|value|{row(budget,poll,bad)?;budget.charge(value.0.capacity().checked_add(value.2.capacity()).ok_or_else(||oom(budget,"key retained source overflow"))?).map_err(|m|oom(budget,m))?;bad.push(value);Ok(())},|bytes|{checked(local,poll)?;local.charge(bytes).map_err(|m|oom(local,m))},||oom(local,"key call projection overflow"))?;
   let raw=views.raw()?;for(index,line)in raw.split('\n').enumerate(){let mut control=Operation{budget:local,poll};let Some(code)=crate::allow::keeps_with(line,"keys",&mut control)?else{continue};if !self.allows.contains_key(relative){node(budget)?;self.allows.insert(own(budget,poll,relative)?,AllowFile{rows:BTreeMap::new(),digest:crate::captured_raw_file::source_allow_digest_text(raw)});}let number=u32::try_from(index.checked_add(1).ok_or_else(||oom(budget,"key annotation line overflow"))?).map_err(|_|oom(budget,"key annotation line exceeds range"))?;node(budget)?;let code=code.unwrap_or_default();budget.charge(code.capacity()).map_err(|m|oom(budget,m))?;self.allows.get_mut(relative).ok_or("key allowance file disappeared")?.rows.insert(number,Annotation{code,comment_only:crate::util::py_lstrip(line).starts_with("//")});}
   checked(budget,poll)?;Ok(())
  })();if matches!(&pending,Err(Failure::Operational(_))){return pending}if local.denied()||budget.denied(){return Err(oom(budget,"key original callback admission denied"))}pending
 }
}

struct System{known:bool,requested:BTreeMap<String,bool>,types:Vec<String>}
type Systems=BTreeMap<String,System>;
fn requested_systems(projection:&Projection,budget:&Budget,poll:&dyn Fn()->io::Result<()>)->Result<Systems,Failure>{
 let mut systems=BTreeMap::new();for marker in projection.markers.iter().filter(|marker|marker.name=="SYSTEM_ACCESSOR"){
  checked(budget,poll)?;let(Some(system),Some(key))=(marker.args.first(),marker.args.get(2))else{continue};let Some(var)=key.trim().strip_prefix("nameof(").and_then(|value|value.strip_suffix(')')).map(str::trim)else{continue};
  if !systems.contains_key(system.as_str()){
   node(budget)?;let bytes=system.len().checked_mul(8).and_then(|n|n.checked_add(4096)).ok_or_else(||oom(budget,"key system type strings overflow"))?;budget.charge(bytes).map_err(|m|oom(budget,m))?;
   let types=crate::system_accessors_policy::system_types(system);if types.capacity()>8{return Err(oom(budget,"key system type vector exceeds original two-type envelope"))}let capacity=types.iter().try_fold(0usize,|sum,value|sum.checked_add(value.capacity())).ok_or_else(||oom(budget,"key system actual path capacity overflow"))?;if capacity>bytes{return Err(oom(budget,"key system actual path capacity exceeds admission"))}
   systems.insert(own(budget,poll,system)?,System{known:false,requested:BTreeMap::new(),types});
  }
  let row=systems.get_mut(system.as_str()).ok_or("key requested system disappeared")?;if !row.requested.contains_key(var){node(budget)?;row.requested.insert(own(budget,poll,var)?,false);}
 }Ok(systems)
}
fn system_file(relative:&str,views:RawPolicyViews<'_>,systems:&mut Systems,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{
 let local=views.allocation_budget(budget);let pending=(||{
  checked(budget,poll)?;if systems.is_empty(){return Ok(())}let code=views.code()?;let mut clean=None;
  for(name,system)in systems.iter_mut(){checked(local,poll)?;if !crate::system_accessors_policy::file_mentions_system_with_types(&code.text,name,&system.types){continue}
   if code.text.lines().any(|line|system.types.iter().any(|ty|line.trim_end()==ty)){system.known=true;}
   let text=match clean{Some(text)=>text,None=>{let text=views.clean(local)?;clean=Some(text);text}};
   crate::raw_type_vars_policy::visit_with(text,&mut Operation{budget:local,poll},&mut|owner,var|{if system.types.iter().any(|ty|ty==owner){system.known=true;if let Some(found)=system.requested.get_mut(var){*found=true;}}Ok(())})?;
  }let _=relative;Ok(())
 })();if matches!(&pending,Err(Failure::Operational(_))){return pending}if local.denied()||budget.denied(){return Err(oom(budget,"key system original callback admission denied"))}pending
}
/// Owned policy DATA. Complete source/current-request authority remains private
/// to the real reader that invoked this producer and consumed both EOFs.
pub struct KeyData{sites:Vec<crate::lint::Site>,allow_used:Vec<crate::lint::AllowUse>,allow_digests:BTreeMap<String,[u8;20]>}
impl KeyData{pub fn sites(&self)->&[crate::lint::Site]{&self.sites}pub fn allow_used(&self)->&[crate::lint::AllowUse]{&self.allow_used}pub fn allow_source_digest(&self,relative:&str)->Option<&[u8;20]>{self.allow_digests.get(relative)}}
struct Output<'a>{configuration:&'a Config,allows:&'a BTreeMap<String,AllowFile>,budget:&'a Budget,poll:&'a dyn Fn()->io::Result<()>,data:KeyData}
impl<C:Control<Error=Failure>> crate::keys_policy::ScanSource<C> for Output<'_>{
 fn exempt(&self,relative:&str)->bool{self.configuration.policy_path_exempt("sem/keys","sem",relative)}
 fn allowed(&mut self,relative:&str,line:u32,control:&mut C)->Result<bool,Failure>{
  control.checkpoint()?;let Some(file)=self.allows.get(relative)else{return Ok(false)};
  let kept=file.rows.get(&line).map(|row|(line,row)).or_else(||line.checked_sub(1).filter(|_|line>=2).and_then(|above|file.rows.get(&above).filter(|row|row.comment_only).map(|row|(above,row))));let Some((at,annotation))=kept else{return Ok(false)};
  if !self.data.allow_used.iter().any(|row|row.rel==relative&&row.line==at&&row.name=="keys"&&row.code==annotation.code){row(self.budget,self.poll,&mut self.data.allow_used)?;self.data.allow_used.push(crate::lint::AllowUse{rel:own(self.budget,self.poll,relative)?,line:at,name:own(self.budget,self.poll,"keys")?,code:own(self.budget,self.poll,&annotation.code)?});}
  if !self.data.allow_digests.contains_key(relative){node(self.budget)?;self.data.allow_digests.insert(own(self.budget,self.poll,relative)?,file.digest);}Ok(true)
 }
 fn site(&mut self,rule:&'static str,relative:&str,line:usize,message:String)->Result<(),Failure>{
  checked(self.budget,self.poll)?;row(self.budget,self.poll,&mut self.data.sites)?;self.data.sites.push(crate::lint::Site{rule:own(self.budget,self.poll,rule)?,rel:own(self.budget,self.poll,relative)?,line:u32::try_from(line).map_err(|_|oom(self.budget,"key site line exceeds original range"))?,msg:message,key:String::new(),ident:String::new()});Ok(())
 }
}
fn retained(data:&KeyData)->Option<usize>{
 let mut bytes=std::mem::size_of::<KeyData>().checked_add(data.sites.capacity().checked_mul(std::mem::size_of::<crate::lint::Site>())?)?.checked_add(data.allow_used.capacity().checked_mul(std::mem::size_of::<crate::lint::AllowUse>())?)?;
 for row in &data.sites{bytes=bytes.checked_add(row.rule.capacity())?.checked_add(row.rel.capacity())?.checked_add(row.msg.capacity())?.checked_add(row.key.capacity())?.checked_add(row.ident.capacity())?;}
 for row in &data.allow_used{bytes=bytes.checked_add(row.rel.capacity())?.checked_add(row.name.capacity())?.checked_add(row.code.capacity())?;}
 for label in data.allow_digests.keys(){bytes=bytes.checked_add(2048)?.checked_add(label.capacity())?;}Some(bytes)
}
/// Produce over one actual source provider, without granting it a source role.
/// The concrete host requires its selected Keys manifest and two actual CODE EOFs.
pub fn collect(pages:&dyn RawPolicyPages,configuration:&Config,order:&HashMap<String,usize>,root:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<KeyData,Failure>{
 checked(root,poll)?;let mut scratch=Scratch::new(root)?;let pending=(||{
  let mut projection=Projection::default();let first=pages.for_each(&mut|relative,views|{projection.file(relative,views,&scratch.budget,poll)?;Ok(true)})?;if !first{return Err("key original source projection stopped before EOF".into())}
  let mut systems=requested_systems(&projection,&scratch.budget,poll)?;let second=pages.for_each(&mut|relative,views|{system_file(relative,views,&mut systems,&scratch.budget,poll)?;Ok(true)})?;if !second{return Err("key system source projection stopped before EOF".into())}
  scratch.budget.charge(projection.markers.len().checked_mul(2*std::mem::size_of::<OwnedMarker>()).and_then(|n|n.checked_add(128)).ok_or_else(||oom(&scratch.budget,"key marker sort storage overflow"))?).map_err(|m|oom(&scratch.budget,m))?;
  projection.markers.sort_by(|a,b|(order.get(&a.rel).copied().unwrap_or(usize::MAX),a.rel.as_str(),a.line).cmp(&(order.get(&b.rel).copied().unwrap_or(usize::MAX),b.rel.as_str(),b.line)));
  let mut markers=Vec::new();for row in &projection.markers{crate::key_policy_control::row(&mut Operation{budget:&scratch.budget,poll},&mut markers)?;markers.push(crate::declare_policy::Marker{name:&row.name,rel:&row.rel,line:row.line,body:&row.body,args:&row.args,body_offset:row.body_offset,line_starts:&row.line_starts});}
  let input=crate::keys_policy::ScanInput{keys:crate::keys_policy::Input{markers:&markers,entry_ops:&projection.entry_ops},defines:&projection.defines,key_refs:&projection.key_refs,bad_sources:&projection.bad_sources};
  let mut output=Output{configuration,allows:&projection.allows,budget:&scratch.budget,poll,data:KeyData{sites:Vec::new(),allow_used:Vec::new(),allow_digests:BTreeMap::new()}};let mut control=Operation{budget:&scratch.budget,poll};
  crate::keys_policy::scan_keys_using(&mut output,&input,&mut control,|system,var,control|{control.checkpoint()?;Ok(systems.get(system).map_or((false,false),|row|(row.known,row.requested.get(var).copied().unwrap_or(false))))},|system,control|{let mut types=Vec::new();if let Some(row)=systems.get(system){for ty in &row.types{kc::row(control,&mut types)?;types.push(kc::own(control,ty)?);}}else{return Err("key system type request has no original requested owner".into())}Ok(types)})?;
  checked(&scratch.budget,poll)?;Ok(output.data)
 })();let pending=finish(pending,&scratch.budget,poll);let funded=match pending{Ok(data)=>{let bytes=retained(&data).ok_or_else(||oom(root,"key output retained capacity overflow"));match bytes.and_then(|bytes|root.charge(bytes).map_err(|m|oom(root,m))){Ok(())=>Ok(data),Err(error)=>{drop(data);Err(error)}}},Err(error)=>Err(error)};scratch.complete=funded.is_ok();drop(scratch);finish(funded,root,poll)
}

#[cfg(test)]
#[path="captured_keys_pages_tests.rs"]mod tests;
