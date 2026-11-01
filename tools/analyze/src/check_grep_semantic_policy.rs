//! Unique policy decisions over borrowed primary-node questions; no AST/model.
pub(crate) enum Mask<'a,E>{Both(&'a E,&'a E),Through(&'a E),Number,Name(&'a str),Other}
pub(crate) trait MaskView<E>{fn mask<'a>(&self,node:&'a E)->Mask<'a,E>;}
pub(crate) fn mask<E,V:MaskView<E>,Error>(view:&V,node:&E,checkpoint:&mut impl FnMut()->Result<(),Error>)->Result<bool,Error>{checkpoint()?;Ok(match view.mask(node){Mask::Both(left,right)=>mask(view,left,checkpoint)?&&mask(view,right,checkpoint)?,Mask::Through(value)=>mask(view,value,checkpoint)?,Mask::Number=>true,Mask::Name(name)=>name!="slot_flags"&&name!="src",Mask::Other=>false})}
/// Preserve the exact pinned raw suffix check and one-based mask column.
pub(crate) fn holder_column(line:&str,start:usize,receiver:&str)->Option<usize>{let tail=line.get(start..)?;let after_name=tail.strip_prefix(receiver)?;let optional=after_name.starts_with('?');if !(after_name.starts_with(".holder")||after_name.starts_with("?.holder")){return None}start.checked_add(receiver.len())?.checked_add(usize::from(optional))?.checked_add(1)}


/// A primary-node projection may refuse a numeric spelling without inventing a value.
pub(crate) trait TryMaskView<E,Error>{fn mask<'a>(&mut self,node:&'a E)->Result<Mask<'a,E>,Error>;}
pub(crate) fn try_mask<E,Error>(view:&mut impl TryMaskView<E,Error>,node:&E,checkpoint:&mut impl FnMut()->Result<(),Error>)->Result<bool,Error>{checkpoint()?;Ok(match view.mask(node)?{Mask::Both(left,right)=>try_mask(view,left,checkpoint)?&&try_mask(view,right,checkpoint)?,Mask::Through(value)=>try_mask(view,value,checkpoint)?,Mask::Number=>true,Mask::Name(name)=>name!="slot_flags"&&name!="src",Mask::Other=>false})}
