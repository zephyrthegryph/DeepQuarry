//! Shared input-key adapter.
use crate::lint::{Cx,Lint,Meta,Registry,Sink};
use crate::raw_tree_duplicate_input_key_policy as policy;
struct DuplicateInputKey{p:policy::Patterns}
impl Lint for DuplicateInputKey{fn meta(&self)->&Meta{&policy::META}fn scan_tree(&self,cx:&Cx,out:&mut Sink){let mut rows=Vec::new();for f in cx.files(){policy::declared(f,&self.p,|ty,key,line|rows.push((ty.to_string(),key.to_string(),f.rel.clone(),line)))}policy::assemble(rows.iter().map(|(ty,key,rel,line)|(ty.as_str(),key.as_str(),rel.as_str(),*line)),out)}}
pub fn register(reg:&mut Registry){reg.add(DuplicateInputKey{p:policy::Patterns::new()})}

#[cfg(feature="native-policy")]
struct NativeDuplicateInputKey{legacy:std::sync::OnceLock<DuplicateInputKey>}
#[cfg(feature="native-policy")]
impl Lint for NativeDuplicateInputKey{
 fn meta(&self)->&Meta{&policy::META}
 fn scan_tree(&self,cx:&Cx,out:&mut Sink){
  let Some(fixture)=cx.fixture else{return self.legacy.get_or_init(||DuplicateInputKey{p:policy::Patterns::new()}).scan_tree(cx,out)};
  let patterns=policy::native_patterns(fixture);let mut rows=Vec::new();
  for file in cx.files(){
   let mut first=None;
   let parsed=fixture.declared_input_keys(file,&patterns,|ty,key,line|{if first.is_none(){let row=(||{let row=(fixture.own(ty)?,fixture.own(key)?,fixture.own(&file.rel)?,line);fixture.push(&mut rows,row)})();if let Err(error)=row{first=Some(error)}}});
   if let Some(error)=first{fixture.note_scan(Err(error));return}if let Err(error)=parsed{fixture.note_scan(Err(error));return}
  }
  policy::assemble(rows.iter().map(|(ty,key,rel,line)|(ty.as_str(),key.as_str(),rel.as_str(),*line)),out)
 }
}
#[cfg(feature="native-policy")]
pub fn register_native(reg:&mut Registry){reg.add(NativeDuplicateInputKey{legacy:std::sync::OnceLock::new()})}
