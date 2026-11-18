//! Unique original first-use/helper C2 judge over typed borrowed source callbacks.
//! No Tree/model is created here; native source owners must register actual helper
//! name-group reads, including empty groups, before lending candidate metadata.
use std::{cell::RefCell,collections::HashMap,rc::Rc};
use crate::{dm::dx::{Proc,lineage_using,enclosing_call_using},pat::Pat,pat,pat_match,key_policy_control::{self as kc,Control}};
const VALIDATORS:[&str;7]=["ui_number","ui_text","ui_choice","ui_ref","ui_token","ui_member","ui_bool"];
pub(crate) trait Sources<C:Control>{
 fn named(&self,name:&str,c:&mut C)->Result<Rc<Vec<Proc>>,C::Error>;
 /// False stops only this body scan, never a whole-input completion witness.
 fn lines(&self,proc:&Proc,c:&mut C,visit:&mut dyn FnMut(usize,&str,&mut C)->Result<bool,C::Error>)->Result<(),C::Error>;
}
pub(crate) struct FirstUse<'a,S>{pub(crate) source:&'a S,pub(crate) pats:&'a RefCell<HashMap<String,Rc<Pat>>>}
fn copied_proc<C:Control>(p:&Proc,c:&mut C)->Result<Proc,C::Error>{crate::ui_actions_policy::copy_proc_using(c,p)}

enum UseProgram{Legacy(Rc<Pat>),#[cfg(feature="native-policy")]Native(String)}
impl UseProgram{fn find<'h,C:Control>(&self,text:&'h str,start:usize,c:&mut C)->Result<Option<crate::pat::M<'h>>,C::Error>{match self{Self::Legacy(program)=>Ok(program.find_at(text,start)),#[cfg(feature="native-policy")]Self::Native(source)=>Ok(kc::captures_recipe(c,source,text,start)?.map(|row|{let(start,end)=row.groups[0].expect("actual compiled pattern has group0");crate::pat::M{hay:text,start,end}}))}}}
impl<S> FirstUse<'_,S>{
 fn pattern<C:Control>(&self,param:&str,c:&mut C)->Result<Rc<Pat>,C::Error>{c.checkpoint()?;if let Some(value)=self.pats.borrow().get(param){return Ok(Rc::clone(value))}kc::reserve(c,||param.len().checked_mul(2)?.checked_add(128))?;let escaped=regex::escape(param);let pattern=kc::format(c,format_args!(r"(?<![\w./:]){}\b",escaped))?;kc::reserve(c,||std::mem::size_of::<Pat>().checked_add(pattern.len().checked_mul(8)?)?.checked_add(512))?;let compiled=Rc::new(Pat::new(&pattern));crate::ui_actions_policy::map_room_using(&mut *self.pats.borrow_mut(),c)?;let key=crate::ui_actions_policy::own_using(c,param)?;self.pats.borrow_mut().insert(key,Rc::clone(&compiled));Ok(compiled)}
 pub(crate) fn find_proc<C:Control>(&self,path:&str,name:&str,c:&mut C)->Result<Option<Proc>,C::Error>where S:Sources<C>{
  let chain=lineage_using(path,c)?;let mut best:Option<(i64,usize)>=None;let named=self.source.named(name,c)?;
  for(i,proc)in named.iter().enumerate(){c.checkpoint()?;let mut contained=false;if !proc.is_global(){for owner in &chain{c.checkpoint()?;if *owner==proc.path{contained=true;break}}}if proc.is_global()||contained{let rank=if proc.is_global(){-1}else{let mut position=None;for(i,owner)in chain.iter().enumerate(){c.checkpoint()?;if *owner==proc.path{position=Some(i);break}}chain.len()as i64-position.unwrap()as i64};if best.map(|b|rank>b.0).unwrap_or(true){best=Some((rank,i));}}}match best{Some((_,i))=>Ok(Some(copied_proc(&named[i],c)?)),None=>Ok(None)}
 }
 pub(crate) fn first_bad_use<C:Control>(&self,proc:&Proc,param:&str,depth:usize,c:&mut C)->Result<Option<usize>,C::Error>where S:Sources<C>{
  let native={#[cfg(feature="native-policy")]{c.native_patterns().is_some()}#[cfg(not(feature="native-policy"))]{false}};
  let use_pat=if native{#[cfg(feature="native-policy")]{let escaped=kc::escape_native(c,param)?;UseProgram::Native(kc::format(c,format_args!(r"(?<![\w./:]){}\b",escaped))?)}#[cfg(not(feature="native-policy"))]{unreachable!()}}else{UseProgram::Legacy(self.pattern(param,c)?)};
  #[cfg(feature="native-policy")]if let UseProgram::Native(source)=&use_pat{let pending=c.native_patterns().expect("native recipe was selected from this actual provider").capture_len(crate::native_pattern::Spec{pattern:source,mode:crate::native_pattern::Mode::Search});pending.map_err(|actual|c.native_pattern_failed(actual))?;}
  let mut decided:Option<Option<usize>>=None;
  self.source.lines(proc,c,&mut|number,text,c|{c.checkpoint()?;let mut pos=0;while pos<=text.len(){c.checkpoint()?;let Some(m)=use_pat.find(text,pos,c)?else{break};pos=if m.end==m.start{m.end+text[m.end..].chars().next().map(|ch|ch.len_utf8()).unwrap_or(1)}else{m.end};let col=m.start;let(before,after)=(&text[..col],&text[col+param.len()..]);
   if kc::is_match_match_static(c,r"\s*=(?!=)",after,||pat_match!(r"\s*=(?!=)"))?{continue}
   if kc::is_match_static(c,r"(?<!!)!\s*$",before,||pat!(r"(?<!!)!\s*$"))?&&!kc::is_match_match_static(c,r"\s*(?:==|!=|in\b)",after,||pat_match!(r"\s*(?:==|!=|in\b)"))?{continue}
   if kc::is_match_static(c,r"\bisnull\(\s*$",before,||pat!(r"\bisnull\(\s*$"))?{continue}
   if kc::is_match_static(c,r"!!\s*$",before,||pat!(r"!!\s*$"))?{decided=Some(None);return Ok(false)}
   if kc::is_match_static(c,r"\b(?:switch|islist)\s*\(\s*$",before,||pat!(r"\b(?:switch|islist)\s*\(\s*$"))?&&kc::is_match_match_static(c,r"\s*\)",after,||pat_match!(r"\s*\)"))?{decided=Some(None);return Ok(false)}
   if kc::is_match_match_static(c,r#"\s*(?:==|!=)\s*(?:"[^"\n]*"|-?\d+(?:\.\d+)?|TRUE|FALSE|null|[A-Z][A-Z0-9_]+)\b"#,after,||pat_match!(r#"\s*(?:==|!=)\s*(?:"[^"\n]*"|-?\d+(?:\.\d+)?|TRUE|FALSE|null|[A-Z][A-Z0-9_]+)\b"#))?||kc::is_match_static(c,r#"(?:"[^"\n]*"|-?\d+(?:\.\d+)?|TRUE|FALSE|null|[A-Z][A-Z0-9_]+)\b\s*(?:==|!=)\s*$"#,before,||pat!(r#"(?:"[^"\n]*"|-?\d+(?:\.\d+)?|TRUE|FALSE|null|[A-Z][A-Z0-9_]+)\b\s*(?:==|!=)\s*$"#))?{decided=Some(None);return Ok(false)}
   if let Some(call)=enclosing_call_using(text,col,c)?{if kc::is_match_match_static(c,r"\s*[,)]",after,||pat_match!(r"\s*[,)]"))?{
    if VALIDATORS.contains(&call.name.as_str())&&call.index==0&&call.key.is_none()&&!call.member{decided=Some(None);return Ok(false)}
    let helper=if call.member{None}else{self.find_proc(&proc.path,&call.name,c)?};if let Some(helper)=helper{if depth<3{let target=match &call.key{Some(key)=>Some(key),None=>helper.params.get(call.index)};if let Some(target)=target{let mut has=false;for param in &helper.params{c.checkpoint()?;if param==target{has=true;break}}if has&&self.first_bad_use(&helper,target,depth+1,c)?.is_none(){decided=Some(None);return Ok(false)}}}
   }}}decided=Some(Some(number));return Ok(false)
  }Ok(true)})?;c.checkpoint()?;Ok(decided.flatten())
 }
}

#[cfg(all(test,feature="legacy-sem"))]#[path="ui_actions_c2_tests.rs"]mod tests;
