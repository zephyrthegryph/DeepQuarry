//! One config-free codemod operation over actual native model/body loans and
//! the host's captured physical-byte DATA. No Engine, legacy Sem, parser,
//! filesystem reader, cache or write/completion authority is constructed here.
use std::{io,path::{Path,PathBuf,Component},sync::Arc};
use crate::{codemod::{self,Codemod,RunOpts,RunResult,LexicalFiles,PhysicalFiles},captured_generator_budget::Budget,captured_codemod_work::{Phase,Funded},policy_finish::admitted::Work,reactive_reads_native::Failure};
pub enum FileData<'a>{Bytes(&'a[u8]),NoText}
/// The actual recorder/capture owns every row throughout the operation. No
/// unrequested key may be reported as an observed absence.
pub trait PhysicalInputs{
 fn for_each(&self,visit:&mut dyn FnMut(&str,FileData<'_>)->io::Result<()>)->io::Result<()>;
 fn file(&self,relative:&str)->Option<FileData<'_>>;
}
pub struct Plan{actual:Funded<RunResult>}
impl Plan{pub fn result(&self)->&RunResult{self.actual.borrow()}}
pub type Bodies<'a>=dyn Fn(&Arc<dm_tree::frontend::BodySyntaxInput>)->Result<Arc<dm_tree::frontend::OriginalBodySyntaxProduct>,dm_tree::frontend::BodySyntaxFailure>+'a;
fn actual_failure(value:Failure)->io::Error{match value{Failure::Operational(first)=>first,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)}}
struct Lexical<'a>{root:&'a Path,files:&'a dyn PhysicalInputs,budget:&'a Arc<Budget>,source_work:&'a dyn dm_preprocess::source_arena_credit::SourceArenaWork}
impl Lexical<'_>{
 fn path(&self,relative:&str)->io::Result<(PathBuf,dm_preprocess::source_arena_credit::SourceArenaCredit)>{
  self.budget.require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;self.source_work.checkpoint()?;
  if relative.is_empty()||relative.contains(['\\',':'])||Path::new(relative).components().any(|component|!matches!(component,Component::Normal(_))){return Err(io::Error::new(io::ErrorKind::InvalidData,"native codemod physical key escapes caller namespace"))}
  let capacity=self.root.as_os_str().len().checked_add(1).and_then(|n|n.checked_add(relative.len())).ok_or(io::ErrorKind::OutOfMemory)?;
  let credit=self.source_work.reserve(capacity.checked_add(std::mem::size_of::<PathBuf>()).ok_or(io::ErrorKind::OutOfMemory)?)?;
  let mut path=PathBuf::new();path.try_reserve_exact(capacity).map_err(|_|io::ErrorKind::OutOfMemory)?;if path.capacity()>capacity{return Err(io::ErrorKind::OutOfMemory.into())}path.push(self.root);path.push(relative);Ok((path,credit))
 }
 fn text(&self,bytes:&[u8],normalize:bool)->io::Result<dm_preprocess::SourceText>{
  self.source_work.checkpoint()?;
  // Count the actual standard lossy decoder's output before allocation.
  let mut source=bytes;let mut capacity=0usize;
  loop{self.source_work.checkpoint()?;match std::str::from_utf8(source){Ok(valid)=>{capacity=capacity.checked_add(valid.len()).ok_or(io::ErrorKind::OutOfMemory)?;break},Err(error)=>{capacity=capacity.checked_add(error.valid_up_to()).and_then(|n|n.checked_add(3)).ok_or(io::ErrorKind::OutOfMemory)?;match error.error_len(){Some(width)=>source=&source[error.valid_up_to()+width..],None=>break}}}}
  let payload=self.source_work.reserve(capacity)?;let control=self.source_work.reserve(dm_preprocess::SourceText::source_arena_control_bytes()?)?.into_control();
  let mut out=String::new();out.try_reserve_exact(capacity).map_err(|_|io::ErrorKind::OutOfMemory)?;if out.capacity()>capacity{return Err(io::ErrorKind::OutOfMemory.into())}
  let mut previous_cr=false;
  let mut append=|text:&str|->io::Result<()>{for ch in text.chars(){self.source_work.checkpoint()?;if normalize{if previous_cr&&ch=='\n'{previous_cr=false;continue}previous_cr=ch=='\r';out.push(if ch=='\r'{'\n'}else{ch});}else{out.push(ch);}}Ok(())};
  source=bytes;loop{match std::str::from_utf8(source){Ok(valid)=>{append(valid)?;break},Err(error)=>{append(std::str::from_utf8(&source[..error.valid_up_to()]).map_err(io::Error::other)?)?;append("\u{fffd}")?;match error.error_len(){Some(width)=>source=&source[error.valid_up_to()+width..],None=>break}}}}
  dm_preprocess::SourceText::from_source_arena(out,payload,control)
 }
}
impl LexicalFiles for Lexical<'_>{
 fn for_each(&self,visit:&mut dyn FnMut(&crate::tree::SourceFile)->io::Result<()>)->io::Result<()>{
  self.files.for_each(&mut|relative,data|{
   let FileData::Bytes(bytes)=data else{return Ok(())};
   let(path,_path_credit)=self.path(relative)?;let mut first=None;
   let pending=crate::captured_raw_file::with_original_policy_file_prepared(self.root,&path,0,self.budget,|_|self.text(bytes,true).map_err(Failure::Operational),&mut|actual,views|{
    if actual!=relative{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"physical codemod path projection differs from actual captured key")))}
    let file=views.source_file()?;match visit(file){Ok(())=>Ok(true),Err(error)=>{first=Some(error);Err(Failure::Operational(io::ErrorKind::Other.into()))}}
   });
   if let Some(error)=first{return Err(error)}pending.map(|_|()).map_err(actual_failure)
  })
 }
 fn with_physical_clean(&self,relative:&str,text:&str,visit:&mut dyn FnMut(&str)->io::Result<()>)->io::Result<()>{
  let Some(FileData::Bytes(bytes))=self.files.file(relative)else{return Err(io::Error::new(io::ErrorKind::InvalidData,"physical codemod clean source was not captured"))};
  if bytes!=text.as_bytes(){return Err(io::Error::new(io::ErrorKind::InvalidData,"physical codemod copy differs from actual captured bytes"))}
  let(path,_path_credit)=self.path(relative)?;let mut first=None;
  let pending=crate::captured_raw_file::with_original_policy_file_prepared(self.root,&path,0,self.budget,|_|self.text(bytes,false).map_err(Failure::Operational),&mut|actual,views|{
   if actual!=relative{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"physical clean namespace differs")))}
   let file=views.source_file()?;let clean=file.clean();if let Some(error)=file.captured_budget_error(){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,error)))}
   match visit(&clean.text){Ok(())=>Ok(true),Err(error)=>{first=Some(error);Err(Failure::Operational(io::ErrorKind::Other.into()))}}
  });
  if let Some(error)=first{return Err(error)}pending.map(|_|()).map_err(actual_failure)
 }
}
struct Copies<'a>(&'a dyn PhysicalInputs);
impl PhysicalFiles for Copies<'_>{
 fn read(&self,_:&str)->io::Result<Option<Vec<u8>>>{Err(io::Error::new(io::ErrorKind::InvalidInput,"native copy omitted actual allocation work"))}
 fn read_using(&self,relative:&str,work:Option<&dyn Work>)->io::Result<Option<Vec<u8>>>{
  let work=work.ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"native copy omitted actual allocation work"))?;work.checkpoint()?;
  match self.0.file(relative){Some(FileData::NoText)=>Ok(None),Some(FileData::Bytes(actual))=>{let mut bytes=codemod::work::vec_capacity(Some(work),actual.len())?;for part in actual.chunks(8192){work.checkpoint()?;bytes.extend_from_slice(part);}work.checkpoint()?;Ok(Some(bytes))},None=>Err(io::Error::new(io::ErrorKind::NotFound,"native declaration destination is not an actual captured input"))}
 }
}
pub fn run(inputs:&dm_analysis::policy_inputs::PolicyInputs,root:&Path,budget:&Arc<Budget>,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,patterns:&dyn crate::native_pattern::Provider,body:&Bodies<'_>,poll:&dyn Fn()->io::Result<()>,cm:&dyn Codemod,apply:bool,paths:&[String],candidates:&[codemod::Cand],physical:&dyn PhysicalInputs,manifest:Option<&str>)->io::Result<Plan>{
 use crate::reactive_global_source::Source;
 if !root.is_absolute(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native codemod requires actual absolute caller root"))}
 let mut phase=Phase::new(work,budget,patterns)?;
 let mut owned_paths=codemod::work::vec_capacity(Some(&phase),paths.len())?;for path in paths{Work::checkpoint(&phase)?;owned_paths.push(codemod::work::own(Some(&phase),path)?);}let options=RunOpts{apply,paths:owned_paths};
 let source=crate::reactive_original_source::ReadSource::native(inputs,root,budget).map_err(|message|io::Error::new(io::ErrorKind::Unsupported,message))?.with_checkpoint(poll).with_utility_body_borrower(body);
 source.require().map_err(|message|io::Error::new(io::ErrorKind::Unsupported,message))?;
 let lexical=Lexical{root,files:physical,budget,source_work:work};let copies=Copies(physical);
 let prepared=if cm.declares(){Some(codemod::own_decl::prepare_native(&lexical,manifest,&mut phase,budget,work,patterns)?)}else{None};
 let empty=();let prep:&(dyn std::any::Any+Send+Sync)=match &prepared{Some(actual)=>actual,None=>&empty};
 let facts=crate::captured_codemod_facts::NativeFacts{source:&source,work:&phase};
 let actual=codemod::run_prepared_streamed(root,&lexical,cm,&options,&facts,prep,&copies,candidates,&phase)?;
 source.require().map_err(|message|io::Error::new(io::ErrorKind::Unsupported,message))?;Work::checkpoint(&phase)?;
 drop(facts);drop(source);drop(prepared);drop(options);Ok(Plan{actual:phase.finish(actual)?})
}

#[derive(Clone,Copy,Eq,PartialEq)]pub enum DeliveryMode{Check,Apply,Residue}
pub struct Delivery{pub summary:String,pub sites:String,pub record:Option<String>,pub residue:Option<String>,pub keys:Option<String>,pub recipe:Option<String>,pub errors:String,pub exit:i32}
pub struct Reports{actual:Funded<Delivery>}
impl Reports{pub fn data(&self)->&Delivery{self.actual.borrow()}}
impl Plan{
 pub fn reports(&self,cm:&dyn Codemod,mode:DeliveryMode,list_sites:bool,committed:Option<&str>,took:std::time::Duration,budget:&Arc<Budget>,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,patterns:&dyn crate::native_pattern::Provider)->io::Result<Reports>{
  let phase=Phase::new(work,budget,patterns)?;let actual=self.result();
  let keys=codemod::keys::analyze_using(&actual.keys,&phase)?;
  let summary=codemod::report::summary_using(cm,actual,&keys,took,&phase)?;
  let mut sites=String::new();if list_sites{for site in &actual.residue{let row=codemod::work::format(Some(&phase),format_args!("  {}:{}: [{}] {}
",site.file,site.line,site.reason,site.text))?;codemod::work::push_str(Some(&phase),&mut sites,&row)?;}}
  let record=if mode==DeliveryMode::Apply{Some(codemod::report::revert_json_using(cm.name(),&actual.changes,&phase)?)}else{None};
  let residue=if mode==DeliveryMode::Residue{Some(codemod::report::residue_json_using(cm,actual,&phase)?)}else{None};
  let keys_text=if mode==DeliveryMode::Residue&&!actual.keys.is_empty(){Some(codemod::report::keys_json_using(&keys,&actual.keys,&phase)?)}else{None};
  let recipe=if mode==DeliveryMode::Apply{Some(codemod::report::revert_recipe_using(cm.name(),actual,&phase)?)}else{None};
  let(fail,errors)=if mode==DeliveryMode::Check{codemod::report::gate_using(cm,actual,&keys,committed,&phase)?}else{(false,String::new())};
  drop(keys);Ok(Reports{actual:phase.finish(Delivery{summary,sites,record,residue,keys:keys_text,recipe,errors,exit:if fail{1}else{0}})?})
 }
}

pub trait RevertInputs{fn file(&self,relative:&str)->Option<&[u8]>;}
/// Prevalidate EVERY original hash/inverse before the caller attempts any write.
/// The exact byte transformation reuses the shared checked inverse kernel.
pub fn revert(records:&[codemod::report::RevertFile],physical:&dyn RevertInputs,budget:&Arc<Budget>,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,patterns:&dyn crate::native_pattern::Provider)->io::Result<Plan>{
 let phase=Phase::new(work,budget,patterns)?;let mut actual=RunResult::default();actual.changes=codemod::work::vec_capacity(Some(&phase),records.len())?;
 for record in records{
  Work::checkpoint(&phase)?;let bytes=physical.file(&record.file).ok_or_else(||io::Error::new(io::ErrorKind::NotFound,"revert target not actually captured"))?;
  let before=std::str::from_utf8(bytes).map_err(|first|io::Error::new(io::ErrorKind::InvalidData,first))?;
  let mut hash=blake3::Hasher::new();for chunk in bytes.chunks(8192){Work::checkpoint(&phase)?;hash.update(chunk);}if hash.finalize().to_hex().as_str()!=record.after_hash{return Err(io::Error::new(io::ErrorKind::InvalidData,codemod::work::format(Some(&phase),format_args!("{} changed since the codemod wrote it; revert it with git instead",record.file))?))}
  let after=codemod::revert_edits_using(before,&record.inverse,Some(&phase))?;
  let mut hash=blake3::Hasher::new();for chunk in after.as_bytes().chunks(8192){Work::checkpoint(&phase)?;hash.update(chunk);}if hash.finalize().to_hex().as_str()!=record.before_hash{return Err(io::Error::new(io::ErrorKind::InvalidData,codemod::work::format(Some(&phase),format_args!("{}: the inverse does not reproduce the original (hash mismatch)",record.file))?))}
  actual.changes.push(codemod::FileChange{rel:codemod::work::own(Some(&phase),&record.file)?,before:codemod::work::own(Some(&phase),before)?,after,inverse:Vec::new(),sites:0});
 }
 Ok(Plan{actual:phase.finish(actual)?})
}
