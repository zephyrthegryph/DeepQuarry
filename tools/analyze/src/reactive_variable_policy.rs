//! SAME original reactive-variable judgement over original producer callbacks.
//! A boolean/classification is policy data, never a source/query authority.
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum VarClass{Reactive,Constant,Unknown}
pub trait Source{
 type Error;
 fn checkpoint(&mut self)->Result<(),Self::Error>;
 fn tracked(&mut self,owner:&str,name:&str)->Result<bool,Self::Error>;
 fn relation(&mut self,owner:&str,name:&str)->Result<bool,Self::Error>;
 fn stat(&mut self,owner:&str,name:&str)->Result<bool,Self::Error>;
 fn derived(&mut self,owner:&str,name:&str)->Result<bool,Self::Error>;
 fn published_builtin(&mut self,owner:&str,name:&str)->Result<bool,Self::Error>;
 fn flyweight(&mut self,owner:&str)->Result<bool,Self::Error>;
 fn written(&mut self,owner:&str,name:&str)->Result<bool,Self::Error>;
 fn constant(&mut self,owner:&str,name:&str)->Result<bool,Self::Error>;
}
/// Preserve the old short circuit and source-query order exactly. Compatibility
/// supplies a no-op checkpoint; native callers use their SAME stack control.
pub fn classify<S:Source>(source:&mut S,owner:&str,name:&str)->Result<VarClass,S::Error>{
 source.checkpoint()?;
 let result=if source.tracked(owner,name)?||source.relation(owner,name)?{VarClass::Reactive}
 else if source.stat(owner,name)?||source.derived(owner,name)?||source.published_builtin(owner,name)?{VarClass::Reactive}
 else if matches!(name,"type"|"parent_type"|"gc_destroyed"){VarClass::Constant}
 else if source.flyweight(owner)?{VarClass::Constant}
 else if !source.written(owner,name)?||source.constant(owner,name)?{VarClass::Constant}
 else{VarClass::Unknown};
 source.checkpoint()?;Ok(result)
}
