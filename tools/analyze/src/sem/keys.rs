//! Compatibility projection into the one shared marker-key policy.
pub use crate::keys_policy::{KeyIndex,ID_PREFIXES,id_tokens};
use super::decls::Decls;
impl KeyIndex{
 pub fn build(decls:&Decls)->Self{
  let markers:Vec<_>=decls.markers.iter().map(|m|crate::declare_policy::Marker{
   name:&m.name,rel:&m.rel,line:m.line,body:&m.body,args:&m.args,
   body_offset:m.body_offset,line_starts:&m.line_starts,
  }).collect();
  Self::from_markers(&crate::keys_policy::Input{markers:&markers,entry_ops:&decls.entry_ops})
 }
}
