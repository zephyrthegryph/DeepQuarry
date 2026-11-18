//! Operation-only base-vars lexical consumer. The enclosing actual capture owns
//! the complete code/*.dm + maps/*.dmm roster, physical read facts and currentness.
//! No filesystem reads, parser, model or persistent cache are performed here.
use crate::{base_vars_dead_policy::{self as policy,BaseVar,Uses,Channel},key_policy_control::{self as kc,Control}};
use std::{collections::{HashMap,HashSet},io};
/// Text is the ordinary physical-byte decode (lossy UTF-8 and CRLF -> LF only),
/// not compiler decoding or the universal-newline AnalyzeRaw view. The actual
/// captured file owner supplies it, including genuine observed skipped reads.
pub trait Files{
 fn visit(&mut self,consume:&mut dyn FnMut(&str,&str,bool)->io::Result<()>)->io::Result<()>;
}
fn invalid(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,message)}
/// All containers are operation-local and prepaid before their allocations.
/// The same shared scanner and report kernel serve the ordinary utility.
pub(crate) fn render<C:Control<Error=io::Error>>(
 vars:&[BaseVar],files:&mut dyn Files,tsv:bool,few:bool,c:&mut C,
 mut emit:impl FnMut(Channel,std::fmt::Arguments<'_>)->io::Result<()>
)->io::Result<()>{
 c.checkpoint()?;
 let slots=vars.len().checked_mul(4).ok_or_else(||c.overflow())?;
 kc::reserve(c,||slots.checked_mul(std::mem::size_of::<&str>()+std::mem::size_of::<(&str,u32)>()+std::mem::size_of::<(String,Uses)>()+3))?;
 let(mut names,mut decl_at,mut uses)=(HashSet::new(),HashSet::new(),HashMap::<String,Uses>::new());
 names.try_reserve(vars.len()).map_err(|_|c.allocation_failed())?;decl_at.try_reserve(vars.len()).map_err(|_|c.allocation_failed())?;uses.try_reserve(vars.len()).map_err(|_|c.allocation_failed())?;
 if names.capacity()>slots||decl_at.capacity()>slots||uses.capacity()>slots{return Err(c.allocation_failed())}
 for var in vars{c.checkpoint()?;names.insert(var.name.as_str());decl_at.insert((var.rel.as_str(),var.line));if !uses.contains_key(var.name.as_str()){let name=kc::own(c,&var.name)?;uses.insert(name,Uses::default());}}
 files.visit(&mut|relative,raw,is_map|{
  c.checkpoint()?;
  // Domain selection is checked again; a supplied row cannot silently widen
  // the utility's lexical namespace. This is DATA filtering, no source grant.
  if is_map{if !relative.starts_with("maps/")||!relative.ends_with(".dmm"){return Err(invalid("base-vars map row is outside its captured namespace"))}}
  else if !relative.starts_with("code/")||!relative.ends_with(".dm"){return Err(invalid("base-vars source row is outside its captured namespace"))}
  let stripped;
  let text=if is_map{raw}else{
   let bytes=raw.len().checked_mul(4).ok_or_else(||c.overflow())?;c.temporary(0,bytes)?;
   stripped=crate::strip::strip_comments_keep_strings(raw);
   if stripped.capacity()>bytes{return Err(c.allocation_failed())}stripped.as_str()
  };
  policy::scan_using(text,&names,c,|name,line,write|{
   if decl_at.contains(&(relative,line)){return Ok(())}
   let count=uses.get_mut(name).ok_or_else(||invalid("base-vars scanner returned an unissued watched name"))?;
   if is_map{if write{count.writes=count.writes.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?}}
   else if write{count.writes=count.writes.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?}
   else{count.reads=count.reads.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?}
   Ok(())
  })?;c.checkpoint()
 })?;
 policy::report(vars,&uses,tsv,few,c,&mut emit)
}

/// Build only actual authored base declarations through the existing compiler
/// factory. Historical engine_line uses the existing captured compiler-text
/// projection; no ambient filesystem/cache adapter is used by native code.
pub(crate) fn declarations<C:Control<Error=io::Error>>(
 inputs:&dm_analysis::policy_inputs::PolicyInputs,root:&std::path::Path,c:&mut C
)->Result<Vec<BaseVar>,Box<dyn std::error::Error>>{
 struct Work<'a,C>(&'a mut C);
 impl<C:Control<Error=io::Error>>dm_analysis::base_var_declarations::DeclarationWork for Work<'_,C>{
  type Error=Box<dyn std::error::Error>;const CHECKED:bool=true;
  fn checkpoint(&mut self)->Result<(),Self::Error>{self.0.checkpoint().map_err(Into::into)}
  fn reserve(&mut self,bytes:usize)->Result<(),Self::Error>{self.0.reserve(bytes).map_err(Into::into)}
  fn overflow(&mut self)->Self::Error{self.0.overflow().into()}
  fn allocation_failed(&mut self)->Self::Error{self.0.allocation_failed().into()}
 }
 c.checkpoint()?;
 let rows=dm_analysis::base_var_declarations::base_type_declarations_using(inputs.archive(),crate::base_var_hot_policy::BASE_TYPES,root,&mut Work(c))?;
 let tree=inputs.archive().tree();let mut out=Vec::new();
 for row in rows{
  c.checkpoint()?;
  let owner=tree.symbols().text(row.owner).ok_or_else(||invalid("base-vars actual owner spelling absent"))?;
  let name=tree.symbols().text(row.name).ok_or_else(||invalid("base-vars actual member spelling absent"))?;
  let cursor=inputs.archive().member_policy_compatibility_cursor(row.declaration)?;
  kc::reserve(c,||cursor.path.as_os_str().len().checked_add(root.as_os_str().len())?.checked_mul(8))?;
  let relative=dm_preprocess::regions::relative_filesystem_path(cursor.path.as_path(),root).ok_or_else(||invalid("base-vars declaration outside actual root"))?;
  let relative=relative.to_string_lossy().replace('\\',"/");
  let current=inputs.file_exact(cursor.path.as_path()).ok_or_else(||invalid("base-vars declaration has no actual captured compiler file"))?;
  if !current.is_compiled(){return Err(invalid("base-vars declaration cursor is not actual compiled source").into())}
  let source_line=u32::try_from(current.analyze_display_line(cursor.line)?).map_err(|_|c.overflow())?;
  let owner=kc::own(c,owner)?;let name=kc::own(c,name)?;kc::row(c,&mut out)?;
  out.push(BaseVar{owner,name,rel:relative,line:source_line});
 }
 c.checkpoint()?;Ok(out)
}

/// One complete operation-local consumer. The caller retains current captured
/// Inputs through delivery and provides its SAME operation Control/physical
/// Files owner; this data renderer never issues a report/currentness seal.
pub fn run<C:Control<Error=io::Error>>(
 inputs:&dm_analysis::policy_inputs::PolicyInputs,root:&std::path::Path,
 files:&mut dyn Files,c:&mut C,
 tsv:bool,few:bool,out:&mut dyn io::Write,err:&mut dyn io::Write
)->Result<(),Box<dyn std::error::Error>>{
 let vars=declarations(inputs,root,c)?;
 render(&vars,files,tsv,few,c,|channel,args|match channel{
  Channel::Stdout=>writeln!(out,"{}",args),Channel::Stderr=>writeln!(err,"{}",args)
 })?;Ok(())
}


pub use policy::{BaseVar as Declaration,Channel as OutputChannel};
pub fn prepare<C:Control<Error=io::Error>>(inputs:&dm_analysis::policy_inputs::PolicyInputs,root:&std::path::Path,c:&mut C)->Result<Vec<Declaration>,Box<dyn std::error::Error>>{declarations(inputs,root,c)}
pub fn render_prepared<C:Control<Error=io::Error>>(vars:&[Declaration],files:&mut dyn Files,tsv:bool,few:bool,c:&mut C,emit:impl FnMut(Channel,std::fmt::Arguments<'_>)->io::Result<()>)->io::Result<()>{render(vars,files,tsv,few,c,emit)}
