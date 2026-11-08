//! SAME dispatcher normalization for both legacy and captured source owners.
//! Data only: no filesystem/model/cache/source or whole-report completion authority.
use std::collections::{HashMap,HashSet};
use crate::{pat::{Pat,Caps},pat,key_policy_control::{self as kc,Control,Compatibility}};
// Keep the legacy diagnostic text stable after moving the source file.
const DISPATCHER: &str = "code/datums/capabilities/ui_actions.dm";
pub(crate) struct Normaliser{raw:Pat,camel:Pat,replacement:String,max_length:usize,pub(crate) reserved:HashSet<String>}
fn push<C:Control>(out:&mut String,text:&str,c:&mut C)->Result<(),C::Error>{
 if C::CHECKED{let need=out.len().checked_add(text.len()).ok_or_else(||c.overflow())?;if need>out.capacity(){let cap=need.max(out.capacity().saturating_mul(2)).max(64);kc::reserve(c,||cap.checked_add(64))?;out.try_reserve_exact(cap-out.len()).map_err(|_|c.allocation_failed())?;}}out.push_str(text);Ok(())
}
fn capture<'a,C:Control>(p:&Pat,text:&'a str,c:&mut C)->Result<Option<Caps<'a>>,C::Error>{kc::reserve(c,||p.capture_group_count().checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(128))?;c.checkpoint()?;let got=p.captures(text);c.checkpoint()?;Ok(got)}
/// Original Python-$ rewrite, including escaped dollars and classes.
pub(crate) fn py_dollar_using<C:Control>(pattern:&str,c:&mut C)->Result<String,C::Error>{let mut out=String::new();let mut in_class=false;let mut chars=pattern.chars().peekable();while let Some(ch)=chars.next(){c.checkpoint()?;match ch{'\\'=>{push(&mut out,"\\",c)?;if let Some(next)=chars.next(){let mut b=[0;4];push(&mut out,next.encode_utf8(&mut b),c)?}},'[' if !in_class=>{in_class=true;push(&mut out,"[",c)?},']' if in_class=>{in_class=false;push(&mut out,"]",c)?},'$' if !in_class=>push(&mut out,r"(?=\n?\z)",c)?,_=>{let mut b=[0;4];push(&mut out,ch.encode_utf8(&mut b),c)?}}}Ok(out)}
fn expand_template_using<C:Control>(template:&str,m:&Caps<'_>,c:&mut C)->Result<String,C::Error>{let mut out=String::new();let mut it=template.chars().peekable();while let Some(ch)=it.next(){c.checkpoint()?;if ch=='\\'{if let Some(d)=it.peek().copied().filter(|d|d.is_ascii_digit()){it.next();push(&mut out,m.s(d.to_digit(10).unwrap()as usize),c)?;continue}}let mut b=[0;4];push(&mut out,ch.encode_utf8(&mut b),c)?;}Ok(out)}
fn replace_using<C:Control>(pattern:&Pat,text:&str,template:&str,c:&mut C)->Result<String,C::Error>{let mut out=String::new();let mut last=0;pattern.try_for_each_capture(text,c,|c,n|kc::reserve(c,||n.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(128)),|c,m|{push(&mut out,&text[last..m.start(0)],c)?;let replacement=expand_template_using(template,&m,c)?;push(&mut out,&replacement,c)?;last=m.end(0);Ok(())})?;push(&mut out,&text[last..],c)?;Ok(out)}
impl Normaliser{
 pub(crate) fn key_using<C:Control>(&self,raw:&str,c:&mut C)->Result<Option<String>,C::Error>{c.checkpoint()?;if raw.is_empty(){return Ok(None)}let mut count=0usize;for _ in raw.chars(){c.checkpoint()?;count+=1;}if count>self.max_length||capture(&self.raw,raw,c)?.is_none(){return Ok(None)}let s=replace_using(&self.camel,raw,&self.replacement,c)?;kc::reserve(c,||s.len().checked_mul(16)?.checked_add(256))?;c.checkpoint()?;let lower=s.to_lowercase().replace('-',"_");c.checkpoint()?;Ok(Some(lower))}
 pub(crate) fn key(&self,raw:&str)->Option<String>{match self.key_using(raw,&mut Compatibility){Ok(value)=>value,Err(never)=>match never{}}}
}
pub(crate) fn normaliser_from_using<C:DispatcherControl>(text:&str,c:&mut C)->Result<Result<Normaliser,String>,C::Error>{
 let patterns:[(&str,&Pat);7]=[("raw",pat!(r#"GLOBAL_DATUM_INIT\(\s*ui_action_raw_regex\s*,\s*/regex\s*,\s*regex\(\s*@?"([^"]+)""#)),("camel",pat!(r#"GLOBAL_DATUM_INIT\(\s*ui_action_camel_regex\s*,\s*/regex\s*,\s*regex\(\s*@?"([^"]+)""#)),("replacement",pat!(r#"ui_action_camel_regex\.Replace\(\s*\w+\s*,\s*"([^"]+)"\s*\)"#)),("max_length",pat!(r"length\(raw\)\s*>\s*(\d+)")),("reserved",pat!(r"GLOBAL_LIST_INIT\(\s*ui_reserved_arg_names\s*,\s*list\(([^)]*)\)")),("lower",pat!(r"lowertext\(")),("hyphen",pat!(r#"replacetext\([^,]+,\s*"-"\s*,\s*"_"\s*\)"#))];
 kc::reserve(c,||Some(7*(std::mem::size_of::<(&str,String)>()+256)))?;let mut found:HashMap<&str,String>=HashMap::new();for(name,pattern)in patterns{c.checkpoint()?;let Some(m)=capture(pattern,text,c)?else{let message=kc::format(c,format_args!("ui_actions_lint: can't find the dispatcher's {} in {}; update PARITY (and the lint) to match ui_action_key()",name,DISPATCHER))?;return Ok(Err(message))};crate::ui_actions_policy::map_room_using(&mut found,c)?;found.insert(name,crate::ui_actions_policy::own_using(c,m.get(1).unwrap_or(""))?);}
 let mut reserved=HashSet::new();pat!(r#""(\w+)""#).try_for_each_capture(&found["reserved"],c,|c,n|kc::reserve(c,||n.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(128)),|c,m|{c.checkpoint()?;kc::reserve(c,||std::mem::size_of::<String>().checked_add(m.s(1).len())?.checked_add(256))?;crate::ui_actions_policy::set_room_using(&mut reserved,c)?;reserved.insert(crate::ui_actions_policy::own_using(c,m.s(1))?);Ok(())})?;
 // Exactly the old re.sub(r"\$(\d)",r"\\\1",replacement).
 let replacement=replace_using(pat!(r"\$(\d)"),&found["replacement"],r"\\1",c)?;
 let raw=py_dollar_using(&found["raw"],c)?;let camel=py_dollar_using(&found["camel"],c)?;kc::reserve(c,||raw.len().checked_add(camel.len())?.checked_mul(8)?.checked_add(2048))?;c.checkpoint()?;let raw=Pat::try_new(&raw).map_err(|message|c.invalid_pattern(&raw,message))?;let camel=Pat::try_new(&camel).map_err(|message|c.invalid_pattern(&camel,message))?;let max_length=found["max_length"].parse().unwrap_or(usize::MAX);c.checkpoint()?;Ok(Ok(Normaliser{raw,camel,replacement,max_length,reserved}))
}
pub(crate) fn normaliser_from(text:&str)->Result<Normaliser,String>{match normaliser_from_using(text,&mut Compatibility){Ok(value)=>value,Err(never)=>match never{}}}

#[cfg(all(test,feature="legacy-sem"))]#[path="ui_actions_normalizer_tests.rs"]mod tests;

pub(crate) trait DispatcherControl:Control{fn invalid_pattern(&mut self,pattern:&str,message:String)->Self::Error;}
impl DispatcherControl for Compatibility{fn invalid_pattern(&mut self,pattern:&str,message:String)->Self::Error{panic!("bad pattern {:?}: {}",pattern,message)}}

impl Normaliser{pub(crate) fn visit_exposed_storage(&self,visit:&mut dyn FnMut(usize,usize,usize)){visit(self.replacement.as_ptr()as usize,self.replacement.len(),self.replacement.capacity());for key in &self.reserved{visit(key.as_ptr()as usize,key.len(),key.capacity());}}}
