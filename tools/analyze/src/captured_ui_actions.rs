//! The original UI host/C1/C2 producer over authenticated raw source loans.
//! All values here are policy DATA. Only the host owns source/config/EOF grants.
use std::{cell::RefCell,collections::HashMap,io,rc::Rc,sync::Arc};
use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure,captured_raw_file::{Config,RawPolicyViews},captured_raw_tree_pages::Data,key_policy_control::{self as kc,Control},lint::{Site,AllowUse},reactive_raw_policy_pages::RawPolicyPages,tree::SourceFile,ui_actions_policy::{Work,PreparedDispatcher,DispatcherState,DISPATCHER,R_UNSENT,R_UNVALIDATED,R_PROBLEM},ui_actions_hosts::{self as hosts,Hosts,Acts,Call,DmFacts},ui_actions_check::Checks};
pub use crate::dm::dx::Proc as SourceProc;
use crate::dm::dx::Proc;
#[derive(Clone,Debug,serde::Serialize,serde::Deserialize,PartialEq)]
pub struct UiProc{pub proc:Proc,pub hash:u128,pub ordinal:usize}
#[derive(serde::Serialize,serde::Deserialize)]
pub struct SignatureFile{pub relative:String,pub procs:Vec<UiProc>}
impl SignatureFile{
 pub fn retained_charge(&self)->Option<usize>{let mut n=std::mem::size_of::<Self>().checked_add(self.relative.capacity())?.checked_add(self.procs.capacity().checked_mul(std::mem::size_of::<UiProc>())?)?;for p in &self.procs{n=n.checked_add(proc_charge(&p.proc)?)?;}Some(n)}
}
fn proc_charge(p:&Proc)->Option<usize>{let mut n=p.rel.capacity().checked_add(p.path.capacity())?.checked_add(p.name.capacity())?.checked_add(p.params.capacity().checked_mul(std::mem::size_of::<String>())?)?;for v in &p.params{n=n.checked_add(v.capacity())?}Some(n)}
/// Only a named-group DATA description; cached coordinates confer no authority.
/// The host rebinds every value against current raw signatures before use.
impl UiProc{
 pub fn retained_charge(&self)->Option<usize>{std::mem::size_of::<Self>().checked_add(proc_charge(&self.proc)?)}
 pub fn stable_parts(&self)->(&str,&str,&str,&[String],u128,usize){(&self.proc.rel,&self.proc.path,&self.proc.name,&self.proc.params,self.hash,self.ordinal)}
}
/// Dynamic recursive children and root answers join the existing host Db.
/// The original hash excludes coordinates; an answer is a body-relative offset.
pub trait Roots{
 fn sources(&mut self,files:Vec<SignatureFile>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>;
 fn bad_offset(&mut self,root:&UiProc,param:&str,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Option<usize>,Failure>;
}
/// Source reader used by the same unique recursive first-use judge. A missing
/// group is a real dependency. `lines` must authenticate current header geometry.
pub trait C2Sources{
 fn named(&self,name:&str,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Vec<UiProc>,Failure>;
 fn lines(&self,proc:&Proc,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,visit:&mut dyn FnMut(usize,&str)->Result<bool,Failure>)->Result<(),Failure>;
}
struct C2Adapter<'a>{source:&'a dyn C2Sources}
impl<'w> crate::ui_actions_c2::Sources<Work<'w>> for C2Adapter<'_>{
 fn named(&self,name:&str,c:&mut Work<'w>)->Result<Rc<Vec<Proc>>,Failure>{let facts=self.source.named(name,c.budget,c.poll)?;let mut out=Vec::new();for p in facts{kc::row(c,&mut out)?;out.push(p.proc)}c.reserve(std::mem::size_of::<Vec<Proc>>()+2*std::mem::size_of::<usize>())?;Ok(Rc::new(out))}
 fn lines(&self,p:&Proc,c:&mut Work<'w>,visit:&mut dyn FnMut(usize,&str,&mut Work<'w>)->Result<bool,Failure>)->Result<(),Failure>{let b=Arc::clone(c.budget);let poll=c.poll;self.source.lines(p,&b,poll,&mut|n,line|visit(n,line,c))}
}
pub fn first_bad_offset(source:&dyn C2Sources,root:&UiProc,param:&str,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Option<usize>,Failure>{first_bad_offset_using(source,root,param,budget,poll,None)}
pub fn first_bad_offset_with_patterns(source:&dyn C2Sources,root:&UiProc,param:&str,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,patterns:&dyn crate::native_pattern::Provider)->Result<Option<usize>,Failure>{first_bad_offset_using(source,root,param,budget,poll,Some(patterns))}
fn first_bad_offset_using(source:&dyn C2Sources,root:&UiProc,param:&str,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,native_patterns:Option<&dyn crate::native_pattern::Provider>)->Result<Option<usize>,Failure>{let mut c=Work{budget,poll,patterns:native_patterns};c.checkpoint()?;let adapter=C2Adapter{source};let patterns=RefCell::new(HashMap::new());let judge=crate::ui_actions_c2::FirstUse{source:&adapter,pats:&patterns};let value=judge.first_bad_use(&root.proc,param,0,&mut c)?;let offset=value.map(|line|line.checked_sub(root.proc.body_start).ok_or_else(||Failure::Unsupported("UI root result precedes actual body".into()))).transpose()?;c.checkpoint()?;Ok(offset)}
fn signatures(file:&SourceFile,facts:&DmFacts,c:&mut Work<'_>)->Result<SignatureFile,Failure>{let mut procs=Vec::new();let mut ordinal=0usize;crate::dm::dx::visit_proc_headers_using(file,c,|h,c|{let (name_hash,hash)=*facts.names.get(ordinal).ok_or("UI signature/facts header count differs")?;if name_hash!=hosts::name_hash(h.name){return Err("UI signature/facts header order differs".into())}let p=Proc{rel:crate::ui_actions_policy::own_using(c,h.rel)?,line:h.line,path:crate::ui_actions_policy::own_using(c,h.path)?,name:crate::ui_actions_policy::own_using(c,h.name)?,params:crate::dm::dx::param_names_using(h.params,c)?,body_start:h.body_start,body_len:h.body_len};kc::row(c,&mut procs)?;procs.push(UiProc{proc:p,hash,ordinal});ordinal+=1;Ok(())})?;if ordinal!=facts.names.len(){return Err("UI signature/facts EOF differs".into())}Ok(SignatureFile{relative:crate::ui_actions_policy::own_using(c,&file.rel)?,procs})}
struct DmRow{relative:String,facts:DmFacts,digest:[u8;20]}
fn site(data:&mut Data,rule:&str,relative:&str,line:usize,message:&str,c:&mut Work<'_>)->Result<(),Failure>{kc::row(c,&mut data.sites)?;data.sites.push(Site{rule:crate::ui_actions_policy::own_using(c,rule)?,rel:crate::ui_actions_policy::own_using(c,relative)?,line:u32::try_from(line).map_err(|_|c.overflow())?,msg:crate::ui_actions_policy::own_using(c,message)?,ident:String::new(),key:String::new()});Ok(())}
fn kept(data:&mut Data,rows:&[DmRow],relative:&str,line:usize,c:&mut Work<'_>)->Result<bool,Failure>{for row in rows{c.checkpoint()?;if row.relative!=relative{continue}for(asked,at,code)in &row.facts.kept{c.checkpoint()?;if *asked as usize!=line{continue}let u=AllowUse{rel:crate::ui_actions_policy::own_using(c,relative)?,line:*at,name:crate::ui_actions_policy::own_using(c,"ui_actions")?,code:crate::ui_actions_policy::own_using(c,code)?};if !data.allow_used.contains(&u){kc::row(c,&mut data.allow_used)?;data.allow_used.push(u);}if !data.digests.contains_key(relative){c.reserve(256+relative.len())?;data.digests.insert(crate::ui_actions_policy::own_using(c,relative)?,row.digest);}return Ok(true)}return Ok(false)}Ok(false)}
/// Exactly two original productive phases on a valid dispatcher: selected facts,
/// then original source lines. Invalid/missing dispatcher terminates before both.
pub fn collect(pages:&dyn RawPolicyPages,prepared:&PreparedDispatcher,roots:&mut dyn Roots,config:&Config,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Data,Failure>{collect_with_fixture(pages,prepared,roots,config,budget,poll,None)}
pub fn collect_with_fixture(pages:&dyn RawPolicyPages,prepared:&PreparedDispatcher,roots:&mut dyn Roots,config:&Config,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,fixture:Option<&mut FixtureVisitor<'_>>)->Result<Data,Failure>{collect_using(pages,prepared,roots,config,budget,poll,fixture,None)}
pub fn collect_with_fixture_patterns(pages:&dyn RawPolicyPages,prepared:&PreparedDispatcher,roots:&mut dyn Roots,config:&Config,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,fixture:Option<&mut FixtureVisitor<'_>>,patterns:&dyn crate::native_pattern::Provider)->Result<Data,Failure>{collect_using(pages,prepared,roots,config,budget,poll,fixture,Some(patterns))}
fn collect_using(pages:&dyn RawPolicyPages,prepared:&PreparedDispatcher,roots:&mut dyn Roots,config:&Config,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,mut fixture:Option<&mut FixtureVisitor<'_>>,native_patterns:Option<&dyn crate::native_pattern::Provider>)->Result<Data,Failure>{
 let mut c=Work{budget,poll,patterns:native_patterns};c.checkpoint()?;let mut data=crate::captured_raw_tree_pages::empty();match &prepared.state{DispatcherState::Missing=>return Ok(data),DispatcherState::Bad(message)=>{kc::row(&mut c,&mut data.notes)?;data.notes.push(crate::ui_actions_policy::own_using(&mut c,message)?);site(&mut data,R_PROBLEM,DISPATCHER,1,message,&mut c)?;kc::row(&mut c,&mut data.source_text)?;data.source_text.push(crate::ui_actions_policy::own_using(&mut c,prepared.first_source_line())?);return Ok(data)},DispatcherState::Ready(_)=>()};let DispatcherState::Ready(normalizer)=&prepared.state else{unreachable!()};
 let mut rows=Vec::new();let mut calls=Vec::new();let mut signatures_all=Vec::new();let mut last=None::<String>;
 if !pages.for_each(&mut|rel,views:RawPolicyViews<'_>|{c.checkpoint()?;if !crate::ui_actions_policy::metadata().select.matches_path(rel)||config.policy_path_exempt("ui_actions",crate::ui_actions_policy::metadata().group,rel)||rel.ends_with(".d.ts"){return Err("UI source loan is outside productive selection".into())}if last.as_deref().is_some_and(|old|old>=rel){return Err("UI source traversal is not exact slash-string order".into())}last=Some(crate::ui_actions_policy::own_using(&mut c,rel)?);let file=views.source_file()?;if file.rel!=rel{return Err("UI source relative spelling differs".into())}if file.ext()=="dm"{let facts=hosts::dm_facts_using(file,&mut c)?;let names=signatures(file,&facts,&mut c)?;kc::row(&mut c,&mut signatures_all)?;signatures_all.push(names);kc::row(&mut c,&mut rows)?;rows.push(DmRow{relative:crate::ui_actions_policy::own_using(&mut c,rel)?,facts,digest:crate::captured_raw_file::source_allow_digest(file)});}else{let raw=crate::ui_actions_js::tsx_calls_using(file.text(),&mut c)?;let mut file_calls=Vec::new();for call in raw{kc::row(&mut c,&mut file_calls)?;file_calls.push(Call::new_using(rel,&call,normalizer,&mut c)?);}kc::row(&mut c,&mut calls)?;calls.push((crate::ui_actions_policy::own_using(&mut c,rel)?,file_calls));}c.checkpoint()?;Ok(true)})?{return Err("UI productive facts did not reach actual EOF".into())}
 let hosts=Hosts::from_facts_using(rows.iter().map(|r|(r.relative.as_str(),&r.facts)),&mut c)?;let acts=Acts::real(calls);let checks=Checks{hosts:&hosts,norm:normalizer,acts:&acts};roots.sources(signatures_all,budget,poll)?;let procs=checks.ui_procs(&mut c)?;let unsent=checks.unsent_params(&procs,&mut c)?;
 for(n,_param)in &unsent{let p=&hosts.procs[*n];if !kept(&mut data,&rows,&p.rel,p.line,&mut c)?{site(&mut data,R_UNSENT,&p.rel,p.line,"",&mut c)?;}}
 let unsent=if fixture.is_some(){unsent}else{drop(unsent);Vec::new()};
 let unvalidated=checks.unvalidated_params(&procs,&mut c,&mut|n,proc,param,c|{let proc_copy=crate::ui_actions_policy::copy_proc_using(c,proc)?;let signature=UiProc{proc:proc_copy,hash:hosts.hashes[n],ordinal:usize::MAX};let off=roots.bad_offset(&signature,param,budget,poll)?;off.map(|off|proc.body_start.checked_add(off).ok_or_else(||c.overflow())).transpose()})?;
 for(n,_param,line)in &unvalidated{let p=&hosts.procs[*n];if !kept(&mut data,&rows,&p.rel,*line,&mut c)?{site(&mut data,R_UNVALIDATED,&p.rel,*line,"",&mut c)?;}}
 let unvalidated=if fixture.is_some(){unvalidated}else{drop(unvalidated);Vec::new()};
 let problems=checks.check(&mut c)?;if let Some(visit)=fixture.as_mut(){visit(Fixture{patterns:native_patterns,hosts:&hosts,problems:&problems,unsent:&unsent,unvalidated:&unvalidated})?;}drop(unsent);drop(unvalidated);kc::row(&mut c,&mut data.notes)?;data.notes.push(kc::format(&mut c,format_args!("ui_actions_lint: {} problem(s)",problems.len()))?);for(rel,line,message)in problems{site(&mut data,R_PROBLEM,&rel,line,&message,&mut c)?;}
 let mut text=Vec::new();for _ in &data.sites{kc::row(&mut c,&mut text)?;text.push(None::<String>)}last=None;
 if !pages.for_each(&mut|rel,views|{c.checkpoint()?;if last.as_deref().is_some_and(|old|old>=rel){return Err("UI source text traversal order differs".into())}last=Some(crate::ui_actions_policy::own_using(&mut c,rel)?);let file=views.source_file()?;for(i,s)in data.sites.iter().enumerate(){c.checkpoint()?;if s.rel!=rel{continue}if text[i].is_some(){return Err("UI source line repeated".into())}let raw=file.line(s.line as usize);let bytes=raw.len().checked_mul(4).and_then(|n|n.checked_add(128)).ok_or_else(||c.overflow())?;c.reserve(bytes)?;text[i]=Some(crate::util::normalize_ws(raw));}Ok(true)})?{return Err("UI source text did not reach actual EOF".into())}for v in text{kc::row(&mut c,&mut data.source_text)?;data.source_text.push(v.ok_or("UI finding lacks actual source line")?);}c.checkpoint()?;Ok(data)
}

/// Narrow body view: the SourceFile never escapes the authenticated loan.
pub fn with_proc_lines(views:RawPolicyViews<'_>,proc:&UiProc,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,visit:&mut dyn FnMut(usize,&str)->Result<bool,Failure>)->Result<(),Failure>{with_proc_lines_using(views,proc,budget,poll,visit,None)}
pub fn with_proc_lines_patterns(views:RawPolicyViews<'_>,proc:&UiProc,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,visit:&mut dyn FnMut(usize,&str)->Result<bool,Failure>,patterns:&dyn crate::native_pattern::Provider)->Result<(),Failure>{with_proc_lines_using(views,proc,budget,poll,visit,Some(patterns))}
fn with_proc_lines_using(views:RawPolicyViews<'_>,proc:&UiProc,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,visit:&mut dyn FnMut(usize,&str)->Result<bool,Failure>,native_patterns:Option<&dyn crate::native_pattern::Provider>)->Result<(),Failure>{
 let mut c=Work{budget,poll,patterns:native_patterns};c.checkpoint()?;let file=views.source_file()?;if file.rel!=proc.proc.rel{return Err("UI body source relative spelling differs".into())}let mut header=false;crate::dm::dx::visit_proc_headers_using(file,&mut c,|h,c|{if h.line==proc.proc.line&&h.path==proc.proc.path&&h.name==proc.proc.name&&h.body_start==proc.proc.body_start&&h.body_len==proc.proc.body_len&&crate::dm::dx::param_names_using(h.params,c)?==proc.proc.params{header=true}Ok(())})?;if !header{return Err("UI body source has stale/foreign header geometry".into())}let clean=file.clean();for k in 0..proc.proc.body_len{c.checkpoint()?;let n=proc.proc.body_start.checked_add(k).ok_or_else(||c.overflow())?;if !visit(n,clean.line(n))?{break}}c.checkpoint()
}

/// Metadata-only fallible copy used by the host's existing Db family.
pub fn copy_proc(value:&UiProc,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<UiProc,Failure>{let mut c=Work{budget,poll,patterns:None};let proc=crate::ui_actions_policy::copy_proc_using(&mut c,&value.proc)?;c.checkpoint()?;Ok(UiProc{proc,hash:value.hash,ordinal:value.ordinal})}

/// Borrowed within the actual productive phases; never an escaped DATA owner.
pub struct Fixture<'a>{patterns:Option<&'a dyn crate::native_pattern::Provider>,hosts:&'a Hosts,problems:&'a[(String,usize,String)],unsent:&'a[(usize,String)],unvalidated:&'a[(usize,String,usize)]}
pub type FixtureVisitor<'a>=dyn for<'loan> FnMut(Fixture<'loan>)->Result<(),Failure>+'a;
impl Fixture<'_>{pub fn check_original(&self,c:&mut crate::derived_selftest_policy::NativeAssertions<'_>)->Result<(),crate::derived_selftest_policy::Failure>{
 let mut operation=FixtureControl{inner:c,patterns:self.patterns};let actions=self.hosts.actions_of_using("/obj/thing",&mut operation)?;let caps=self.hosts.caps_of_using("/obj/thing",&mut operation)?;
 let breaker=actions.contains_key("breaker")&&caps.len()==1&&caps.contains("/datum/capability/breakers");
 crate::ui_selftest_policy::rows(self.problems.iter().map(|row|row.2.as_str()),breaker,self.unsent.iter().map(|(n,_)|self.hosts.procs[*n].line),self.unvalidated.iter().map(|(_,_,line)|*line),c)
}}

struct FixtureControl<'a,'p,C>{inner:&'a mut C,patterns:Option<&'p dyn crate::native_pattern::Provider>}
impl<C:Control<Error=crate::derived_selftest_policy::Failure>> Control for FixtureControl<'_,'_,C>{type Error=C::Error;const CHECKED:bool=C::CHECKED;
 fn native_patterns(&self)->Option<&dyn crate::native_pattern::Provider>{self.patterns}
 fn native_pattern_failed(&mut self,actual:io::Error)->C::Error{crate::derived_selftest_policy::Failure::Operational(actual)}
 fn checkpoint(&mut self)->Result<(),C::Error>{self.inner.checkpoint()}fn reserve(&mut self,n:usize)->Result<(),C::Error>{self.inner.reserve(n)}
 fn temporary(&mut self,slot:usize,n:usize)->Result<(),C::Error>{self.inner.temporary(slot,n)}fn overflow(&mut self)->C::Error{self.inner.overflow()}fn allocation_failed(&mut self)->C::Error{self.inner.allocation_failed()}
}
