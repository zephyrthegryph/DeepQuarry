//! Shared lexical declaration-block adapter.
use crate::lint::{Cx,Lint,Meta,Registry,Sink};
use crate::tree::SourceFile;
use crate::raw_tree_declaration_block_policy as policy;
struct DeclarationBlock;
impl Lint for DeclarationBlock{fn meta(&self)->&Meta{&policy::META}fn scan_file(&self,_cx:&Cx,f:&SourceFile,out:&mut Sink){policy::scan_file(f,out)}fn scan_tree(&self,cx:&Cx,out:&mut Sink){let mut rows=Vec::new();for f in cx.all_files(){policy::blocks(f,|ty,line|rows.push((ty.to_string(),f.rel.clone(),line)))}policy::assemble(rows.iter().map(|(ty,rel,line)|(ty.as_str(),rel.as_str(),*line)),out)}}
pub fn register(reg:&mut Registry){reg.add(DeclarationBlock)}
