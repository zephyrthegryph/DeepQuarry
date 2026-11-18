//! Explicit admitted entry to the existing Fancy parser, compiler and VM.
//! Immutable programs retain no lender; actual search scratch is operation-local.
use crate::{Expr,Result,RegexOptions,parse::native::NativeExprTree};
use alloc::{boxed::Box,string::String,vec::Vec};
use regex_syntax::native_admission::Hook;

/// A sealed compiled program using the same pinned Fancy instruction semantics.
#[derive(Debug)]
pub struct Regex{program:crate::vm::Prog,names:Vec<(String,usize)>,groups:usize}
impl Regex{
 /// Compile with real preallocation admission before parsing or program growth.
 pub fn compile(pattern:&str,hook:&Hook<'_>)->Result<Self>{
  hook.require_active()?;
  let phase=hook.retained_composite_phase()?;
  let compiled=(||{
  let raw=crate::parse::native::parse(pattern,hook)?;
  // Same lazy search prefix and outer capture as Regex::new_options.
  hook.reserve(||core::mem::size_of::<Expr>().checked_add(64))?;
  let any=Box::new(Expr::Any{newline:true});
  hook.reserve(||core::mem::size_of::<Expr>().checked_add(64))?;
  let group=Box::new(raw.expr);
  let mut children=Vec::new();
  hook.push(&mut children,Expr::Repeat{child:any,lo:0,hi:usize::MAX,greedy:false})?;
  hook.push(&mut children,Expr::Group(group))?;
  let tree=NativeExprTree{expr:Expr::Concat(children),backrefs:raw.backrefs,named_groups:raw.named_groups};
  let info=crate::analyze::native::analyze(&tree,hook)?;
  let groups=info.end_group;
  let program=crate::compile::native::compile(&info,hook)?;
  hook.checkpoint()?;Ok::<Self,crate::Error>(Self{program,names:tree.named_groups,groups})
  })()?;
  // Parse tree, analysis rows and delegate-builder scratch are physically
  // gone. Keep actual VM/name/delegate products before a caller's prefilter.
  let retained=compiled.retained_bytes().ok_or_else(||hook.overflow())?;
  phase.settle(hook,retained)?;Ok(compiled)
 }
 /// Numeric capture count, including the actual outer whole-match capture.
 pub fn capture_len(&self)->usize{self.groups}
 /// Borrow a genuinely parsed capture name; no clone or name cache.
 pub fn capture_name(&self,index:usize)->Option<&str>{self.names.iter().find(|(_,i)|*i==index).map(|(name,_)|name.as_str())}
 /// Resolve a genuinely parsed capture name in the same parsed roster.
 pub fn capture_index(&self,name:&str)->Option<usize>{self.names.iter().find(|(n,_)|n==name).map(|(_,i)|*i)}
 /// Retained admission extent from actual live capacities, preserving the
 /// per-allocation metadata already paid by the same hooks. Only refunds admitted
 /// compiler temporaries after those temporaries have dropped.
 pub fn retained_bytes(&self)->Option<usize>{
  let mut bytes=self.program.native_retained_bytes()?;
  if self.names.capacity()!=0{bytes=bytes.checked_add(self.names.capacity().checked_mul(core::mem::size_of::<(String,usize)>())?.checked_add(64)?)?}
  for(name,_)in &self.names{if name.capacity()!=0{bytes=bytes.checked_add(name.capacity().checked_add(64)?)?}}Some(bytes)
 }
 /// Execute with the same Pat backtracking limit and actual admitted scratch.
 /// The returned actual save rows remain under the caller's operation loan.
 pub fn search(&self,text:&str,start:usize,hook:&Hook<'_>)->Result<Option<Vec<usize>>>{
  let options=RegexOptions{backtrack_limit:50_000_000,..RegexOptions::default()};
  crate::vm::run_admitted(&self.program,text,start,0,&options,hook)
 }
}
