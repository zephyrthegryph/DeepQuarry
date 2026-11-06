//! Exact body-free original derived-read schema, shared by both adapters.
//! These are lexical policy identifier rows, not declarations or semantic authority.
use crate::{key_policy_control::{self as kc,Control},reactive_reaction_policy::{self as reaction,Procedure},pat_match};
use std::collections::{BTreeMap,BTreeSet};
pub(crate) type Table=BTreeMap<String,BTreeSet<String>>;
#[derive(Default)]pub(crate) struct Schema{pub vars:Table,pub typed:Table,pub tracked:Table,pub relations:Table,pub published:Vec<(String,String,String)>}
fn insert<C:Control>(table:&mut Table,owner:&str,name:&str,c:&mut C)->Result<(),C::Error>{if !table.contains_key(owner){kc::reserve(c,||Some(2048))?;table.insert(kc::own(c,owner)?,BTreeSet::new());}let set=table.get_mut(owner).unwrap();if !set.contains(name){kc::reserve(c,||Some(512))?;set.insert(kc::own(c,name)?);}Ok(())}
fn admit<C:Control>(c:&mut C,pattern:&crate::pat::Pat)->Result<(),C::Error>{kc::reserve(c,||pattern.capture_group_count().checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+64))}
macro_rules! first{($c:expr,$line:expr,$pat:literal)=>{{let p=pat_match!($pat);admit($c,p)?;p.captures($line)}}}
pub(crate) fn file<C:Control>(code:&crate::tree::View,c:&mut C)->Result<Schema,C::Error>{
 let mut out=Schema::default();reaction::visit_variable_names(code,c,|c,row|{let owner=kc::format(c,format_args!("/{}",row.owner_without_leading_slash))?;insert(&mut out.vars,&owner,row.name,c)?;let mut segs=row.qualified.split('/').filter(|s|!s.is_empty()&&!["tmp","static","global","const","final"].contains(s));let first=segs.next();if segs.next().is_some()&&first.is_some_and(|s|["datum","obj","mob","atom","turf","area","client","image","list"].contains(&s)){insert(&mut out.typed,&owner,row.name,c)?}Ok(true)})?;
 let mut caps_owner:Option<String>=None;
 for(_,line)in code.numbered(){c.checkpoint()?;if line.starts_with('#'){continue}
  if let Some(m)=first!(c,line,r"^CAPABILITIES(?:_PART)?\(\s*(/[\w/]+)"){caps_owner=Some(kc::own(c,m.s(1))?)}else if !line.starts_with('\t')&&!line.starts_with(' ')&&!line.is_empty(){caps_owner=None}else if let Some(owner)=&caps_owner{if let Some(m)=first!(c,line,r"^\s+(?:ref|rel|owns?)_(?:one|many)\(\s*nameof\(\s*(\w+)\s*\)"){insert(&mut out.relations,owner,m.s(1),c)?}}
  if let Some(m)=first!(c,line,r"^\s+links?\(\s*(/[\w/]+)::(\w+)\s*,\s*(/[\w/]+)::(\w+)"){insert(&mut out.relations,m.s(1),m.s(2),c)?;insert(&mut out.relations,m.s(3),m.s(4),c)?}
  if let Some(m)=first!(c,line,r"^STAT\(\s*(/[\w/]+)\s*,\s*(\w+)"){insert(&mut out.tracked,m.s(1),m.s(2),c)?}
  if let Some(m)=first!(c,line,r"(?:TRACKED|TRACKED_DATA|TRACKED_STATE|SETTER)\(\s*(/[\w/]+)\s*,\s*(\w+)"){insert(&mut out.tracked,m.s(1),m.s(2),c)?}
  if let Some(m)=first!(c,line,r"(?:OWN|OWN_POLICY|OWN_IF|REL|REL_LIST|REL_PAIR|REL_PAIR_LIST|REL_SET|REL_KEYED|REL_KEYED_LIST)\(\s*(/[\w/]+)\s*,\s*(\w+)"){insert(&mut out.relations,m.s(1),m.s(2),c)?}
  let om=first!(c,line,r"(?:OM_FIELD|OM_FLAG_FIELD_BITS|OM_FLAG_FIELD|OM_FIELD_SETTER)\(\s*(/[\w/]+)\s*,\s*(\w+)");
  if let Some(m)=om{insert(&mut out.tracked,m.s(1),m.s(2),c)?}else if let Some(m)=first!(c,line,r"OM_FIELD_TYPED\(\s*(/[\w/]+)\s*,\s*[\w/]+\s*,\s*(\w+)"){insert(&mut out.tracked,m.s(1),m.s(2),c)?}
  if let Some(m)=first!(c,line,r"PUBLISHED_BY\(\s*(/[\w/]+)\s*,\s*(\w+)\s*,\s*(\w+)\s*\)"){kc::row(c,&mut out.published)?;out.published.push((kc::own(c,m.s(1))?,kc::own(c,m.s(2))?,kc::own(c,m.s(3))?));}
 }Ok(out)
}
pub(crate) fn relations<C:Control>(schema:&mut Schema,proc:Procedure<'_>,c:&mut C)->Result<(),C::Error>{if proc.name!="relations"||proc.owner=="/"{return Ok(())}for(_,line)in proc.lines.iter(){crate::reactive_dependency_policy::captures(crate::pat!(r"\b(?:rel|ref|owns?)_(?:one|many)\(\s*nameof\(\s*(\w+)\s*\)"),line,c,|c,m|insert(&mut schema.relations,proc.owner,m.s(1),c))?}Ok(())}
/// Prefix iteration borrows every real segment and adds only the historical DM
/// implicit parents. Triple/internal slashes and empty owner preserve old chain().
pub(crate) fn chain(path:&str,mut visit:impl FnMut(&str,&str)){
 let path=path.trim_matches('/');let first=path.split('/').next().unwrap_or("");match first{"obj"|"mob"=>{visit("/","datum");visit("/","atom");visit("/","atom/movable")},"turf"|"area"=>{visit("/","datum");visit("/","atom")},"atom"=>visit("/","datum"),_=>()}
 for(at,ch)in path.char_indices(){if ch=='/'{visit("/",&path[..at])}}visit("/",path)
}
