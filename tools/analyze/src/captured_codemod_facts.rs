//! Codemod declaration DATA borrowed from the actual native policy archive.
//! No parsed model/index/source receipt or rewrite authority is constructed.
use std::io;
use crate::{codemod_facts::{FactSource,VariableDeclaration},reactive_original_source::ReadSource,reactive_global_source::Source,reactive_reads_native::Failure,policy_finish::admitted::Work};

pub(crate) struct NativeFacts<'source,'loan>{pub(crate) source:&'loan ReadSource<'source>,pub(crate) work:&'loan dyn Work}
impl NativeFacts<'_,'_>{
 fn owned(&self,text:&str)->io::Result<String>{
  self.work.checkpoint()?;self.work.reserve(text.len().checked_add(std::mem::size_of::<String>()).ok_or_else(||self.work.overflow())?)?;
  let mut result=String::new();result.try_reserve_exact(text.len()).map_err(|_|self.work.overflow())?;
  if result.capacity()>text.len(){return Err(self.work.overflow())}result.push_str(text);Ok(result)
 }
 fn operation<T>(&self,run:impl FnOnce()->Result<T,Failure>)->io::Result<T>{
  self.source.checkpoint()?;self.source.require().map_err(|message|io::Error::new(io::ErrorKind::Unsupported,message))?;
  let pending=run();if let Err(Failure::Operational(actual))=pending{return Err(actual)}
  self.source.budget().require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;
  self.source.checkpoint()?;self.source.require().map_err(|message|io::Error::new(io::ErrorKind::Unsupported,message))?;
  pending.map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)})
 }
}
impl FactSource for NativeFacts<'_,'_>{
 fn var_owner(&self,ty:&str,name:&str)->io::Result<Option<String>>{
  self.operation(||self.source.variable_declaring_owner(ty,name).and_then(|owner|owner.map(|owner|self.owned(owner).map_err(Failure::Operational)).transpose()))
 }
 fn var_decl(&self,ty:&str,name:&str)->io::Result<Option<VariableDeclaration>>{
  self.operation(||{
   let Some(actual)=self.source.variable(ty,name)?else{return Ok(None)};
   let archive=self.source.inputs().archive();let tree=archive.tree();let profile=tree.checker_builtin_profile().ok_or("native codemod declaration requires actual original builtin profile")?;
   let fact=dm_analysis::checker_variable_facts::variable_original(tree,profile,dm_ir::SymbolId::of(ty),dm_ir::SymbolId::of(name))?.ok_or("native codemod variable property and declaration issuer differ")?;
   let (file,line)=if let Some(formal)=fact.formal{
    let point=archive.member_policy_line(formal)?;let relative=actual.file.as_deref().ok_or("native codemod actual source variable has no captured file")?;
    (self.owned(relative).map_err(Failure::Operational)?,u32::try_from(point.line).map_err(|_|"native codemod declaration line exceeds original geometry")?)
   }else{(String::new(),0)};
   // Transfer actual owned declaration text into this operation's retained
   // work BEFORE the scoped native fact temporary can be retired.
   let declared=self.owned(&actual.declared).map_err(Failure::Operational)?;
   Ok(Some(VariableDeclaration{declared,file,line}))
  })
 }
}
