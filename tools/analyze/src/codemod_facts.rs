//! Read-only semantic DATA used by the existing codemod edit kernel.
//! This port cannot issue source/currentness or physical rewrite authority.
use std::io;
#[derive(Clone,Debug,PartialEq,Eq)]
pub struct VariableDeclaration{pub declared:String,pub file:String,pub line:u32}
pub trait FactSource{
 fn var_owner(&self,ty:&str,name:&str)->io::Result<Option<String>>;
 fn var_decl(&self,ty:&str,name:&str)->io::Result<Option<VariableDeclaration>>;
}
#[cfg(feature="legacy-sem")]
impl FactSource for crate::sem::Sem{
 fn var_owner(&self,ty:&str,name:&str)->io::Result<Option<String>>{Ok(crate::sem::Sem::var_owner(self,ty,name))}
 fn var_decl(&self,ty:&str,name:&str)->io::Result<Option<VariableDeclaration>>{Ok(crate::sem::Sem::var_decl(self,ty,name).map(|actual|VariableDeclaration{declared:actual.declared,file:actual.file,line:actual.line}))}
}
