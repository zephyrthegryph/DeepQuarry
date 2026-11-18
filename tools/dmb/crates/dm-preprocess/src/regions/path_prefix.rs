//! Unify only Windows filesystem spellings with ordinary path semantics.
use std::path::{Path,PathBuf};
#[cfg(not(windows))]
pub(super) fn ordinary_verbatim_drive(_: &Path)->Option<u8>{None}
#[cfg(windows)]
pub(super) fn ordinary_verbatim_drive(path:&Path)->Option<u8>{
 use std::path::{Component,Prefix};let mut components=path.components();
 let drive=match components.next(){Some(Component::Prefix(prefix))=>match prefix.kind(){Prefix::VerbatimDisk(drive)=>drive,_=>return None},_=>return None};
 for component in components{if let Component::Normal(name)=component{
  let name=name.to_str()?;let stem=name.split('.').next().unwrap_or("");
  let device=["CON","PRN","AUX","NUL"].iter().any(|s|stem.eq_ignore_ascii_case(s))
   ||["COM","LPT"].iter().any(|prefix|stem.get(..3).is_some_and(|s|s.eq_ignore_ascii_case(prefix))&&stem.as_bytes().get(3).is_some_and(|n|matches!(n,b'1'..=b'9'))&&stem.len()==4);
  if name.ends_with('.')||name.ends_with(' ')||name.contains(':')||device{return None}
 }}Some(drive)
}
pub(super) fn equivalent_prefix_into(path:&Path,out:&mut PathBuf){
 out.clear();
 if let Some(drive)=ordinary_verbatim_drive(path){let prefix=[drive,b':'];out.push(std::str::from_utf8(&prefix).expect("Windows drive is ASCII"));for component in path.components().skip(1){out.push(component.as_os_str())}}
 else{out.push(path)}
}
pub(super) fn equivalent_prefix(path:PathBuf)->PathBuf{
 if ordinary_verbatim_drive(&path).is_none(){return path}
 let mut out=PathBuf::new();equivalent_prefix_into(&path,&mut out);out
}
