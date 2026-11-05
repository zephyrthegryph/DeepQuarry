//! Unique ACT_TRY pairing CFG over borrowed statement/expression projections.
//! No syntax/parser/model is copied or manufactured. No source/EOF grant.
use crate::key_policy_control::{self as kc,Control};
#[derive(Debug,PartialEq,Eq)]pub struct Found{pub line:u32,pub msg:String}
#[derive(Default)]pub struct Pending(Vec<(String,u32)>);
impl Pending{pub fn close(&mut self,name:&str){if let Ok(at)=self.0.binary_search_by(|(key,_)|key.as_str().cmp(name)){self.0.remove(at);}}}
pub struct Var<'a,E>{pub name:&'a str,pub value:Option<&'a E>}
pub enum Step<'a,S,E>{Return(Option<&'a E>),Terminate,Conditional{arms:Vec<(&'a E,&'a[S])>,otherwise:Option<&'a[S]>},Simple(&'a E),Assign{lhs:&'a E,rhs:&'a E,plain:bool},Variables{values:Vec<Var<'a,E>>,grouped:bool},Other{expressions:Vec<&'a E>,blocks:Vec<&'a[S]>,exhaustive:bool}}
pub trait Syntax<C:Control>{
 type Statement;type Expression;
 fn seen_try(&self,block:&[Self::Statement],c:&mut C)->Result<bool,C::Error>;
 fn line(&self,statement:&Self::Statement,c:&mut C)->Result<u32,C::Error>;
 fn step<'a>(&'a self,statement:&'a Self::Statement,c:&mut C)->Result<Step<'a,Self::Statement,Self::Expression>,C::Error>;
 fn is_try(&self,e:&Self::Expression,c:&mut C)->Result<bool,C::Error>;
 fn bare_name<'a>(&self,e:&'a Self::Expression)->Option<&'a str>;
 fn closes(&self,e:&Self::Expression,pending:&mut Pending,c:&mut C)->Result<(),C::Error>;
 fn null_tested(&self,e:&Self::Expression,c:&mut C)->Result<Vec<String>,C::Error>;
 fn non_null_tested(&self,e:&Self::Expression,c:&mut C)->Result<Vec<String>,C::Error>;
}
fn put<C:Control>(pending:&mut Pending,name:&str,line:u32,replace:bool,c:&mut C)->Result<(),C::Error>{c.checkpoint()?;match pending.0.binary_search_by(|(key,_)|key.as_str().cmp(name)){Ok(at)=>{if replace{pending.0[at].1=line;}},Err(at)=>{kc::row(c,&mut pending.0)?;pending.0.insert(at,(kc::own(c,name)?,line));}}Ok(())}
fn duplicate<C:Control>(pending:&Pending,c:&mut C)->Result<Pending,C::Error>{let mut out=Pending::default();for(name,line)in &pending.0{c.checkpoint()?;kc::row(c,&mut out.0)?;out.0.push((kc::own(c,name)?,*line));}Ok(out)}
fn merge<C:Control>(outs:Vec<Pending>,c:&mut C)->Result<Option<Pending>,C::Error>{if outs.is_empty(){return Ok(None)}let mut merged=Pending::default();for out in outs{for(name,line)in out.0{c.checkpoint()?;if let Err(at)=merged.0.binary_search_by(|(key,_)|key.as_str().cmp(&name)){kc::row(c,&mut merged.0)?;merged.0.insert(at,(name,line));}}}Ok(Some(merged))}
fn found<C:Control>(rows:&mut Vec<Found>,line:u32,msg:String,c:&mut C)->Result<(),C::Error>{kc::row(c,rows)?;rows.push(Found{line,msg});Ok(())}
struct Pair<'a,S,C>{source:&'a S,control:&'a mut C,found:Vec<Found>}
impl<S,C> Pair<'_,S,C>where C:Control,S:Syntax<C>{
 fn block(&mut self,block:&[S::Statement],mut pending:Pending,depth:usize)->Result<Option<Pending>,C::Error>{
  // Operation-local stack exposure. Compatibility does not evaluate native
  // bounds; Native grammar still owns body shape/depth validity.
  kc::temporary(self.control,904,||depth.checked_add(1)?.checked_mul(4096))?;
  for statement in block{self.control.checkpoint()?;let line=self.source.line(statement,self.control)?;match self.source.step(statement,self.control)?{
   Step::Return(expression)=>{let mut out=duplicate(&pending,self.control)?;if let Some(e)=expression{self.source.closes(e,&mut out,self.control)?;}for(name,at)in out.0{let msg=kc::format(self.control,format_args!("ACT_ATTEMPT into `{name}` is returned past at line {line} without act_done or act_cancel"))?;found(&mut self.found,at,msg,self.control)?;}return Ok(None)},
   Step::Terminate=>return Ok(None),
   Step::Conditional{arms,otherwise}=>{let mut outs=Vec::new();let mut on_false=duplicate(&pending,self.control)?;for(condition,body)in arms{self.source.closes(condition,&mut on_false,self.control)?;let mut inner=duplicate(&on_false,self.control)?;for name in self.source.null_tested(condition,self.control)?{inner.close(&name);}if let Some(out)=self.block(body,inner,depth+1)?{kc::row(self.control,&mut outs)?;outs.push(out);}for name in self.source.non_null_tested(condition,self.control)?{on_false.close(&name);}}if let Some(body)=otherwise{if let Some(out)=self.block(body,on_false,depth+1)?{kc::row(self.control,&mut outs)?;outs.push(out);}}else{kc::row(self.control,&mut outs)?;outs.push(on_false);}let Some(out)=merge(outs,self.control)?else{return Ok(None)};pending=out;},
   Step::Assign{lhs,rhs,plain}=>{if plain&&self.source.is_try(rhs,self.control)?{if let Some(name)=self.source.bare_name(lhs){put(&mut pending,name,line,true,self.control)?;}else{let msg=kc::own(self.control,"ACT_ATTEMPT result is stored where act_done cannot name it; assign it to a local")?;found(&mut self.found,line,msg,self.control)?;}}else{self.source.closes(lhs,&mut pending,self.control)?;self.source.closes(rhs,&mut pending,self.control)?;}},
   Step::Simple(e)=>{if self.source.is_try(e,self.control)?{let msg=kc::own(self.control,"ACT_ATTEMPT result is dropped: nothing can act_done or act_cancel it")?;found(&mut self.found,line,msg,self.control)?;}else{self.source.closes(e,&mut pending,self.control)?;}},
   Step::Variables{values,grouped}=>for var in values{if let Some(e)=var.value{if self.source.is_try(e,self.control)?{put(&mut pending,var.name,line,true,self.control)?;}else if !grouped{self.source.closes(e,&mut pending,self.control)?;}}},
   Step::Other{expressions,blocks,exhaustive}=>{for e in expressions{self.source.closes(e,&mut pending,self.control)?;}if blocks.is_empty(){continue}let mut outs=Vec::new();if !exhaustive{kc::row(self.control,&mut outs)?;outs.push(duplicate(&pending,self.control)?);}for body in blocks{let inner=duplicate(&pending,self.control)?;if let Some(out)=self.block(body,inner,depth+1)?{kc::row(self.control,&mut outs)?;outs.push(out);}}let Some(out)=merge(outs,self.control)?else{return Ok(None)};pending=out;},
  }}Ok(Some(pending))
 }
}
pub fn collect_using<C:Control,S:Syntax<C>>(source:&S,block:&[S::Statement],c:&mut C)->Result<Vec<Found>,C::Error>{c.checkpoint()?;if !source.seen_try(block,c)?{return Ok(Vec::new())}let mut pair=Pair{source,control:c,found:Vec::new()};if let Some(pending)=pair.block(block,Pending::default(),0)?{for(name,line)in pending.0{let msg=kc::format(pair.control,format_args!("ACT_ATTEMPT into `{name}` reaches the end of the proc without act_done or act_cancel"))?;found(&mut pair.found,line,msg,pair.control)?;}}kc::sort_data(&mut pair.found,&mut|a,b|->Result<std::cmp::Ordering,C::Error>{pair.control.checkpoint()?;Ok((a.line,&a.msg).cmp(&(b.line,&b.msg)))})?;pair.found.dedup();pair.control.checkpoint()?;Ok(pair.found)}

#[cfg(all(test,feature="legacy-sem"))]#[path="../fixtures/native-sem-handlers/oracle.rs"]mod immutable;
#[cfg(all(test,feature="legacy-sem"))]mod old_cfg_controls{
 #[test]fn borrowed_cfg_projection_matches_frozen_old_pairing_including_zero_run_merge_and_grouped_var_traps(){
  for written in ["ACT_TRY()", "src.saved = ACT_TRY()", "(src.saved = ACT_TRY())", "var/A = ACT_TRY()", "var/A = ACT_TRY()\nreturn", "var/A = ACT_TRY()\nreturn act_done(A)", "var/A = ACT_TRY()\nthrow A", "var/A = ACT_TRY()\nCRASH()", "var/A = ACT_TRY()\nhandler.act_done(A)", "var/A = ACT_TRY()\nif(!A)\n    return\nact_done(A)", "var/A = ACT_TRY()\nif(A)\n    act_done(A)", "var/A = ACT_TRY()\nif(isnull(A) || A == -1)\n    return\nact_done(A)", "var/A = ACT_TRY()\nwhile(mode)\n    act_done(A)", "var/A = ACT_TRY()\nvar/x = act_done(A)", "var/A = ACT_TRY()\nvar/x = act_done(A), y = 1", "var/A = ACT_TRY()\nswitch(mode)\n    if(1)\n        act_done(A)\n    else\n        act_cancel(A)", "var/A = ACT_TRY()\nswitch(mode)\n    if(1)\n        act_done(A)", "var/A = ACT_TRY()\nif(mode)\n    A = ACT_TRY()\nelse\n    A = ACT_TRY()"]{
   let text=format!("/datum/probe\n    var/saved\n    var/mode\n    proc/p()\n        {}\n",written.replace("\n","\n        "));let tree=crate::tree::Tree::from_files(vec![crate::tree::SourceFile::from_text("code/pair-control.dm",&text)]);let sem=crate::sem::sem_for(&tree).expect("actual old source model");let proc=sem.proc_ref("/datum/probe","p").unwrap();let body=sem.proc_body(proc);let code=body.code.expect("real old statement body");let mut old=Vec::new();let mut current=Vec::new();super::immutable::checks::act_try_pairing(code,crate::sem_handlers_partial_recipe::DEFAULT_TRY_CALLS,&mut old);crate::sem::checks::act_try_pairing(code,crate::sem_handlers_partial_recipe::DEFAULT_TRY_CALLS,&mut current);assert_eq!(old.iter().map(|f|(f.rule,f.line,f.msg.as_str())).collect::<Vec<_>>(),current.iter().map(|f|(f.rule,f.line,f.msg.as_str())).collect::<Vec<_>>(),"unchanged frozen CFG contract for {written}");
  }
 }
}
