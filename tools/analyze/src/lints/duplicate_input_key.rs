//! Shared input-key adapter.
use crate::lint::{Cx,Lint,Meta,Registry,Sink};
use crate::raw_tree_duplicate_input_key_policy as policy;
struct DuplicateInputKey{p:policy::Patterns}
impl Lint for DuplicateInputKey{fn meta(&self)->&Meta{&policy::META}fn scan_tree(&self,cx:&Cx,out:&mut Sink){let mut rows=Vec::new();for f in cx.files(){policy::declared(f,&self.p,|ty,key,line|rows.push((ty.to_string(),key.to_string(),f.rel.clone(),line)))}policy::assemble(rows.iter().map(|(ty,key,rel,line)|(ty.as_str(),key.as_str(),rel.as_str(),*line)),out)}}
pub fn register(reg:&mut Registry){reg.add(DuplicateInputKey{p:policy::Patterns::new()})}
