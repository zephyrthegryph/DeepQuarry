//! SAME original TSX action scanner, extracted for both source owners.
//! No semantic model, filesystem access, result cache, or source authority.
use crate::{key_policy_control::{self as kc,Control},util::{is_py_space,py_strip},pat,pat_match};
use serde::{Deserialize,Serialize};
#[derive(Clone,Debug,PartialEq,Serialize,Deserialize)]
pub struct RawCall{pub line:usize,pub action:String,pub keys:Option<Vec<String>>}
fn starts_at<C:Control>(t:&[char],s:&str,j:usize,c:&mut C)->Result<bool,C::Error>{let mut k=j;for ch in s.chars(){c.checkpoint()?;if t.get(k)!=Some(&ch){return Ok(false)}k+=1;}Ok(true)}
fn find_str<C:Control>(t:&[char],s:&str,from:usize,c:&mut C)->Result<Option<usize>,C::Error>{let n=s.chars().count();if t.len()<n{return Ok(None)}for k in from..=t.len()-n{c.checkpoint()?;if starts_at(t,s,k,c)?{return Ok(Some(k))}}Ok(None)}
fn slice<C:Control>(t:&[char],a:usize,b:usize,c:&mut C)->Result<String,C::Error>{let n=t.len();let(a,b)=(a.min(n),b.min(n));if b<=a{return Ok(String::new())}kc::reserve(c,||b.checked_sub(a)?.checked_mul(4)?.checked_add(64))?;let mut out=String::new();out.try_reserve_exact((b-a)*4).map_err(|_|c.allocation_failed())?;for ch in &t[a..b]{c.checkpoint()?;out.push(*ch)}Ok(out)}
fn skip_string<C:Control>(t:&[char],i:usize,c:&mut C)->Result<usize,C::Error>{let quote=t[i];let mut j=i+1;while j<t.len(){c.checkpoint()?;let ch=t[j];if ch=='\\'{j+=2;continue}if ch==quote{return Ok(j+1)}if quote=='`'&&starts_at(t,"${",j,c)?{let end=match_brace(t,j+1,c)?;j=if end>0{end as usize+1}else{t.len()};continue}j+=1;}Ok(j)}
fn match_brace<C:Control>(t:&[char],i:usize,c:&mut C)->Result<isize,C::Error>{let mut stack=Vec::new();let mut j=i;while j<t.len(){c.checkpoint()?;let ch=t[j];if matches!(ch,'\''|'"'|'`'){j=skip_string(t,j,c)?;continue}if starts_at(t,"//",j,c)?{j=find_str(t,"\n",j,c)?.unwrap_or(t.len());continue}if starts_at(t,"/*",j,c)?{j=match find_str(t,"*/",j+2,c)?{Some(k)=>k+2,None=>t.len()};continue}match ch{'{'|'['|'('=>{kc::row(c,&mut stack)?;stack.push(match ch{'{'=>'}','['=>']',_=>')'});},')'|']'|'}'=>{if stack.pop()!=Some(ch){return Ok(-1)}if stack.is_empty(){return Ok(j as isize)}},_=>{}}j+=1;}Ok(-1)}
fn split_top<C:Control>(t:&[char],c:&mut C)->Result<Vec<String>,C::Error>{let mut parts=Vec::new();let(mut depth,mut start,mut j)=(0i32,0usize,0usize);while j<t.len(){c.checkpoint()?;let ch=t[j];if matches!(ch,'\''|'"'|'`'){j=skip_string(t,j,c)?;continue}if matches!(ch,'{'|'['|'('){depth+=1}else if matches!(ch,'}'|']'|')'){depth-=1}else if ch==','&&depth==0{let text=slice(t,start,j,c)?;kc::row(c,&mut parts)?;parts.push(text);start=j+1;}j+=1;}let text=slice(t,start,t.len(),c)?;kc::row(c,&mut parts)?;parts.push(text);Ok(parts)}
fn object_keys<C:Control>(body:&[char],c:&mut C)->Result<Option<Vec<String>>,C::Error>{let mut keys=Vec::new();for part in split_top(body,c)?{c.checkpoint()?;let part=py_strip(&part);if part.is_empty(){continue}if part.starts_with("...")||part.starts_with('['){return Ok(None)}let mut key=None;kc::try_for_each_capture_match_static(r#"(?s)^\s*(?:(['"])(.*?)\1|([A-Za-z_$][\w$]*))\s*(:|\(|$)"#,||pat_match!(r#"(?s)^\s*(?:(['"])(.*?)\1|([A-Za-z_$][\w$]*))\s*(:|\(|$)"#),part,c,|c,n|kc::reserve(c,||n.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(128)),|c,m|{key=Some(kc::own(c,if m.matched(1){m.s(2)}else{m.s(3)})?);Ok(())})?;let Some(key)=key else{return Ok(None)};kc::row(c,&mut keys)?;keys.push(key);}Ok(Some(keys))}
/// Original lexical order, including Python whitespace, comments, nested
/// templates, open object keys and malformed bracket/string fallthrough.
pub fn tsx_calls_using<C:Control>(text:&str,c:&mut C)->Result<Vec<RawCall>,C::Error>{
 c.checkpoint()?;let mut t=Vec::new();for ch in text.chars(){c.checkpoint()?;kc::row(c,&mut t)?;t.push(ch);}let mut out=Vec::new();
 kc::try_for_each_capture_static(r"(?<![\w$])act\(\s*",||pat!(r"(?<![\w$])act\(\s*"),text,c,|c,n|kc::reserve(c,||n.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(128)),|c,m|{
  c.checkpoint()?;let mut i=0usize;for _ in text[..m.end(0)].chars(){c.checkpoint()?;i+=1;}if i>=t.len()||!matches!(t[i],'\''|'"'|'`'){return Ok(())}let end=skip_string(&t,i,c)?;let action=slice(&t,i+1,end.saturating_sub(1),c)?;if t[i]=='`'&&action.contains("${"){return Ok(())}let mut j=end;while j<t.len()&&is_py_space(t[j]){c.checkpoint()?;j+=1;}let mut keys=Some(Vec::new());if j<t.len()&&t[j]==','{j+=1;while j<t.len()&&is_py_space(t[j]){c.checkpoint()?;j+=1;}if j<t.len()&&t[j]=='{'{let close=match_brace(&t,j,c)?;keys=if close>0{object_keys(&t[j+1..close as usize],c)?}else{None};}else if j<t.len()&&t[j]!=')'{keys=None;}}
  kc::row(c,&mut out)?;let mut line=1usize;for ch in text[..m.start(0)].chars(){c.checkpoint()?;if ch=='\n'{line+=1;}}out.push(RawCall{line,action,keys});Ok(())
 })?;c.checkpoint()?;Ok(out)
}
pub fn tsx_calls(text:&str)->Vec<RawCall>{match tsx_calls_using(text,&mut kc::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}

#[cfg(all(test,feature="legacy-sem",feature="unified-oracle"))]
#[path="ui_actions_js_tests.rs"]mod tests;
