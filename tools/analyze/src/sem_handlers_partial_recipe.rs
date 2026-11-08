//! The unique legacy sem/handlers structural translation-unit recipe.
//! These are policy facts only. No discovery, physical-source, model or full-TU
//! authority can be obtained from this value; the native host binds its own
//! current captured source owners before consuming it.
use crate::key_policy_control::{self as kc,Control};

pub const DEFAULT_TRY_CALLS:&[&str]=&["ACT_ATTEMPT","ACT_TRY","act_try","e0_act_try"];
pub fn candidate(code:&str)->bool{crate::pat!(r"\bACT_TRY\b|\b(?:e0_)?act_try\b|\bdatum/act\b").is_match(code)}
pub fn output_base(relative:&str,code:&str)->bool{relative.starts_with("code/engine/")&&crate::pat!(r"/proc/(?:draw|ui_data|push_to_rust|examine)\s*\(").is_match(code)}
pub fn defines(relative:&str)->bool{crate::scopes::is_defines(relative)}

/// Legacy Sem::build_partial uses a stricter manifest grammar and last
/// duplicate wins. Declared-marker order is a separate policy.
fn define_slots<C:Control>(manifest:&str,c:&mut C)->Result<std::collections::HashMap<String,usize>,C::Error>{
 let mut slots=std::collections::HashMap::new();
 for (ordinal,line) in manifest.lines().enumerate(){
  c.checkpoint()?;
  let Some(path)=line.trim().strip_prefix("#include \"").and_then(|rest|rest.strip_suffix('"'))else{continue};
  // Only actual define paths are consumed. Slash-normalize before deciding
  // membership, and fund that temporary separately from retained keys.
  let normalized=if path.contains('\\'){
   kc::temporary(c,0,||path.len().checked_mul(4)?.checked_add(128))?;
   std::borrow::Cow::Owned(path.replace('\\',"/"))
  }else{std::borrow::Cow::Borrowed(path)};
  if !defines(&normalized){continue}
  if let Some(slot)=slots.get_mut(normalized.as_ref()){*slot=ordinal;}
  else{kc::hash_room(c,&mut slots)?;slots.insert(kc::own(c,normalized.as_ref())?,ordinal);}
 }
 c.checkpoint()?;Ok(slots)
}

#[derive(Clone,Debug,PartialEq,Eq)]
pub struct Input{pub relative:String,pub fingerprint:u128}
/// Exact ordered root includes, candidate membership and call-name vocabulary.
/// `includes` starts with *all* selected legacy define files, then candidates
/// not already present. Ordinary noncandidate macros do not enter this TU.
#[derive(Debug,PartialEq,Eq)]
pub struct Recipe{pub candidates:Vec<Input>,pub includes:Vec<Input>,pub try_calls:Vec<String>,pub has_output_base:bool}
#[derive(Default)]
pub struct Selection{candidates:Vec<Input>,defines:Vec<Input>,has_output_base:bool}
fn append<C:Control>(rows:&mut Vec<Input>,relative:&str,fingerprint:u128,c:&mut C)->Result<(),C::Error>{
 kc::row(c,rows)?;let relative=kc::own(c,relative)?;rows.push(Input{relative,fingerprint});Ok(())
}
impl Selection{
 /// Feed the actual selected CODE_DM roster in Tree's slash-string order,
 /// including every negative candidate. The host must retain that traversal's
 /// discovery/source dependencies; omission is not certified by this builder.
 pub fn push<C:Control>(&mut self,relative:&str,fingerprint:u128,code:&str,c:&mut C)->Result<(),C::Error>{
  self.push_selected(relative,fingerprint,Some(code),c)
 }
 /// An exempt CODE page can still define a macro for the partial TU, but
 /// cannot seed structural candidates or the standard-output phase.
 pub(crate) fn push_selected<C:Control>(&mut self,relative:&str,fingerprint:u128,selected_code:Option<&str>,c:&mut C)->Result<(),C::Error>{
  c.checkpoint()?;
  if let Some(code)=selected_code{
   if candidate(code){append(&mut self.candidates,relative,fingerprint,c)?}
   self.has_output_base|=output_base(relative,code);
  }
  if defines(relative){append(&mut self.defines,relative,fingerprint,c)?}
  c.checkpoint()
 }
 pub fn finish<C:Control>(self,extra:&[String],generated:impl IntoIterator<Item=String>,c:&mut C)->Result<Recipe,C::Error>{
  self.finish_with_manifest(extra,generated,None,c)
 }
 pub(crate) fn finish_with_manifest<C:Control>(self,extra:&[String],generated:impl IntoIterator<Item=String>,manifest:Option<&str>,c:&mut C)->Result<Recipe,C::Error>{
  let Self{candidates,defines:mut includes,has_output_base}=self;
  if let Some(manifest)=manifest{
   let slots=define_slots(manifest,c)?;
   // Native input is already in unique slash-string order. The tie-break
   // reproduces the old stable sort's order for absent manifest paths.
   kc::sort_data(&mut includes,&mut|a,b|{
    c.checkpoint()?;
    Ok::<_,C::Error>(slots.get(&a.relative).unwrap_or(&usize::MAX).cmp(slots.get(&b.relative).unwrap_or(&usize::MAX)).then_with(||a.relative.cmp(&b.relative)))
   })?;
  }
  for input in &candidates{c.checkpoint()?;if !includes.iter().any(|row|row.relative==input.relative){append(&mut includes,&input.relative,input.fingerprint,c)?}}
  let mut try_calls=Vec::new();for name in DEFAULT_TRY_CALLS{kc::row(c,&mut try_calls)?;try_calls.push(kc::own(c,name)?)}
  for name in extra{c.checkpoint()?;kc::row(c,&mut try_calls)?;try_calls.push(kc::own(c,name)?)}
  // `generated` is the producer's actual non-FIXED ACTION marker vocabulary,
  // in old declaration order. It must have been funded by that producer.
  for name in generated{c.checkpoint()?;kc::row(c,&mut try_calls)?;try_calls.push(name)}
  Ok(Recipe{candidates,includes,try_calls,has_output_base})
 }
}
impl Recipe{
 /// Heap payload moved out of the temporary recipe producer. Inline fields
 /// are covered by the receiving subject's own allocation grant.
 pub(crate) fn retained_backing(&self)->Option<usize>{
  let mut bytes=self.try_calls.capacity().checked_mul(std::mem::size_of::<String>())?;
  for rows in [&self.candidates,&self.includes]{
   bytes=bytes.checked_add(rows.capacity().checked_mul(std::mem::size_of::<Input>())?)?;
   for row in rows{bytes=bytes.checked_add(row.relative.capacity())?;}
  }
  for name in &self.try_calls{bytes=bytes.checked_add(name.capacity())?;}
  Some(bytes)
 }
 /// Render exactly the old synthetic include text. This does not touch the
 /// filesystem or manufacture a physical synth.dme source/EOF observation.
 pub fn render<C:Control>(&self,root:&std::path::Path,c:&mut C)->Result<String,C::Error>{
  let mut text=String::new();for input in &self.includes{
   c.checkpoint()?;
   kc::reserve(c,||root.as_os_str().len().checked_add(input.relative.len())?.checked_mul(4)?.checked_add(256))?;
   let absolute=root.join(&input.relative);let path=absolute.display().to_string().replace('\\',"/");
   let line=kc::format(c,format_args!("#include \"{}\"\n",path))?;
   let need=text.len().checked_add(line.len()).ok_or_else(||c.overflow())?;
   if need>text.capacity(){let cap=need.max(text.capacity().saturating_mul(2)).max(64);kc::reserve(c,||cap.checked_add(64))?;text.try_reserve_exact(cap-text.len()).map_err(|_|c.allocation_failed())?;}
   text.push_str(&line);
  }c.checkpoint()?;Ok(text)
 }
}
#[cfg(test)]mod tests{
 use super::*;use crate::key_policy_control::Compatibility;
 fn select(rows:&[(&str,u128,&str)])->Recipe{let mut s=Selection::default();for(path,key,text)in rows{s.push(path,*key,text,&mut Compatibility).unwrap();}s.finish(&[],std::iter::empty(),&mut Compatibility).unwrap()}
 #[test]fn legacy_candidate_boundaries_and_output_gate(){
  for yes in["ACT_TRY(x)","e0_act_try(x)","act_try(x)","datum/act/input/A"]{assert!(candidate(yes),"{yes}")}
  for no in["ACT_ATTEMPT(x)","ACT_TRYX(x)","other_act_try(x)","/datum/action/A"]{assert!(!candidate(no),"{no}")}
  assert!(output_base("code/engine/a.dm","/proc/ui_data ("));assert!(!output_base("code/library/a.dm","/proc/ui_data("));assert!(!output_base("code/engine/a.dm","/ui_data("));
 }
 #[test]fn defines_first_candidates_once_ordinary_macros_absent(){
  let r=select(&[("code/__defines/z.dm",1,"datum/act"),("code/a.dm",2,"act_try(A)"),("code/ordinary_macros.dm",3,"#define X ACT_ATTEMPT"),("code/z.dm",4,"datum/act/A")]);
  assert_eq!(r.includes.iter().map(|i|i.relative.as_str()).collect::<Vec<_>>(),["code/__defines/z.dm","code/a.dm","code/z.dm"]);
  assert_eq!(r.candidates.len(),3);assert_eq!(r.try_calls,DEFAULT_TRY_CALLS);
  let root=std::path::Path::new("/workspace");assert_eq!(r.render(root,&mut Compatibility).unwrap(),"#include \"/workspace/code/__defines/z.dm\"\n#include \"/workspace/code/a.dm\"\n#include \"/workspace/code/z.dm\"\n");
 }
 #[test]fn candidate_and_define_changes_are_distinct_from_negative_scan_changes(){
  let a=select(&[("code/__defines/a.dm",1,"#define X 1"),("code/a.dm",2,"datum/act/A"),("code/ordinary.dm",3,"/datum/ordinary")]);
  let b=select(&[("code/__defines/a.dm",1,"#define X 1"),("code/a.dm",2,"datum/act/A"),("code/ordinary.dm",4,"/datum/ordinary // changed")]);assert_eq!(a,b,"child recipe can remain green after parent reselects a changed negative");
  let c=select(&[("code/__defines/a.dm",1,"#define X 1"),("code/a.dm",2,"datum/act/A"),("code/ordinary.dm",5,"/proc/x(datum/act/A)")]);assert_ne!(a,c,"negative becoming candidate changes child recipe");
  let d=select(&[("code/__defines/a.dm",6,"#define X 2"),("code/a.dm",2,"datum/act/A")]);assert_ne!(a,d,"define bytes belong to the actual partial child");
 }

 #[test]
 fn actual_handler_defines_use_all_migrated_roots_and_strict_last_manifest_slot(){
  let manifest=concat!(
   "#include \"code/defines/library/z.dm\"\n",
   "#include \"code/__defines/a.dm\"\n",
   "#include \"code\\defines\\library\\z.dm\"\n",
   "#include \"code/defines/base/b.dm\" // this is not a strict include row\n",
   "#include\t\"code/defines/content/c.dm\"\n",
  );
  let paths=[
   "code/__defines/a.dm","code/candidate.dm","code/defines/base/b.dm",
   "code/defines/content/c.dm","code/defines/engine/d.dm","code/defines/host/e.dm",
   "code/defines/library/z.dm","code/defines/not_a_define.dm",
  ];
  let mut selection=Selection::default();
  for (index,relative) in paths.iter().enumerate(){
   let code=(*relative=="code/candidate.dm").then_some("act_try(A)");
   selection.push_selected(relative,index as u128,code,&mut Compatibility).unwrap();
  }
  let recipe=selection.finish_with_manifest(&[],std::iter::empty(),Some(manifest),&mut Compatibility).unwrap();
  let actual=recipe.includes.iter().map(|row|row.relative.as_str()).collect::<Vec<_>>();
  let mut expected=paths.iter().copied().filter(|path|crate::scopes::is_defines(path)).collect::<Vec<_>>();
  // Independent original Sem::build_partial exact path and precedence fold.
  let original_slots=manifest.lines().filter_map(|line|line.trim().strip_prefix("#include \"")
   .and_then(|rest|rest.strip_suffix('"')).map(|path|path.replace('\\',"/")))
   .enumerate().map(|(index,path)|(path,index)).collect::<std::collections::HashMap<_,_>>();
  expected.sort_by_key(|path|original_slots.get(*path).copied().unwrap_or(usize::MAX));
  expected.push("code/candidate.dm");
  assert_eq!(actual,expected);
  assert_eq!(actual,["code/__defines/a.dm","code/defines/library/z.dm","code/defines/base/b.dm",
   "code/defines/content/c.dm","code/defines/engine/d.dm","code/defines/host/e.dm","code/candidate.dm"]);
  let markers=crate::raw_marker_policy::dme_include_order(manifest);
  assert!(markers["code/defines/library/z.dm"]<markers["code/__defines/a.dm"],"declared marker order must retain FIRST duplicate");
 }

 #[test]fn first_operational_failure_precedes_allocations(){
  struct Stop;impl Control for Stop{type Error=std::io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{Err(std::io::Error::from_raw_os_error(1450))}fn reserve(&mut self,_:usize)->Result<(),Self::Error>{panic!("must not allocate after cancellation")}fn overflow(&mut self)->Self::Error{panic!()}fn allocation_failed(&mut self)->Self::Error{panic!()}}
  let err=Selection::default().push("code/a.dm",1,"datum/act/A",&mut Stop).unwrap_err();assert_eq!(err.raw_os_error(),Some(1450));
 }
}

pub const DECLARATION_MARKERS: &[&str] = &[
    "CAPABILITIES",
    "CAPABILITY_DEF",
    "CAPABILITY_TYPE",
    "cap_keys",
    "ACTION",
    "STAT",
    "SCHEMA",
    "TRACKED_SCHEMA",
    "SYSTEM_ACCESSOR",
    "sparse",
    "STAGE_DEF",
    "STATE_GRAPH",
    "RESOURCE_DEF",
    "SOURCE_DEF",
    "READS_AS",
    "READ_LOOKUP",
    "READS_FROM",
    "STATIC_ENTRY",
    "PROC_SUMMARY",
];
