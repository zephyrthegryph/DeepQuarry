//! Exact fixed utility-output targets captured by the same operation recorder.
//! Paths are registry constants; no JSON/caller path grants write authority.
use super::*;
use std::{io,path::{Path,PathBuf}};
use crate::{input_snapshot::utility_capture::{UtilityBytes,UtilityPhysicalInputs},request_runner::utility_capture::Capture};
use dm_preprocess::source_arena_credit::SourceArenaWork;
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(crate)enum Mode{Check,Apply,WriteResidue,Revert}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(crate)enum Output{Residue,Keys,RevertRecord}
fn paths(name:&str)->io::Result<[&'static str;3]>{match name{
 "om_after"=>Ok(["tools/analyze/codemods/om_after/residue.json","tools/analyze/codemods/om_after/keys.json","data/codemod/om_after/revert.json"]),
 "own_set"=>Ok(["tools/analyze/codemods/own_set/residue.json","tools/analyze/codemods/own_set/keys.json","data/codemod/own_set/revert.json"]),
 "own_add"=>Ok(["tools/analyze/codemods/own_add/residue.json","tools/analyze/codemods/own_add/keys.json","data/codemod/own_add/revert.json"]),
 _=>Err(io::Error::new(io::ErrorKind::InvalidInput,"unknown actual codemod output registry")),
}}
pub(super)fn paid_path(root:&Path,relative:&str,work:&dyn SourceArenaWork)->io::Result<(PathBuf,dm_preprocess::source_arena_credit::SourceArenaCredit)>{
 work.checkpoint()?;let capacity=root.as_os_str().len().checked_add(1).and_then(|n|n.checked_add(relative.len())).ok_or(io::ErrorKind::OutOfMemory)?;
 let credit=work.reserve(capacity.checked_add(std::mem::size_of::<PathBuf>()).ok_or(io::ErrorKind::OutOfMemory)?)?;
 let mut path=PathBuf::new();path.try_reserve_exact(capacity).map_err(|_|io::ErrorKind::OutOfMemory)?;if path.capacity()>capacity{return Err(io::ErrorKind::OutOfMemory.into())}path.push(root);path.push(relative);Ok((path,credit))
}
pub(crate)struct CapturedCodemodTarget<'a>{root:&'a Path,relative:&'static str,kind:Output,actual:Option<UtilityBytes>,next_directory:Option<crate::input_snapshot::utility_capture::CapturedDirectoryTarget>,ready:bool}
impl CapturedCodemodTarget<'_>{
 pub(crate)fn root(&self)->&Path{self.root}
 pub(crate)fn relative(&self)->&str{self.relative}
 pub(crate)fn kind(&self)->Output{self.kind}
 pub(crate)fn stamp(&self)->io::Result<Option<&crate::input_snapshot::Stamp>>{if !self.ready{return Err(io::Error::new(io::ErrorKind::InvalidInput,"codemod output omitted actual positive/negative capture"))}Ok(self.actual.as_ref().map(UtilityBytes::stamp))}
 pub(crate)fn preimage(&self)->io::Result<&[u8]>{self.stamp()?;Ok(self.actual.as_ref().map_or(&[],UtilityBytes::bytes))}
 pub(crate)fn next_directory(&self)->io::Result<Option<&crate::input_snapshot::utility_capture::CapturedDirectoryTarget>>{self.stamp()?;Ok(self.next_directory.as_ref())}
 fn reset(&mut self){self.ready=false;self.actual=None;self.next_directory=None;}
 fn capture(&mut self,physical:&mut dyn UtilityPhysicalInputs,parents:bool)->io::Result<()>{
  self.reset();let mut path=None;physical.with_work(&mut|work|{path=Some(paid_path(self.root,self.relative,work)?);Ok(())})?;
  let(path,_credit)=path.ok_or_else(||io::Error::other("codemod target path work was not entered"))?;
  self.actual=physical.read(&path,dq_analyze::selected_exclusions_wire::MAX_STREAM as usize)?;self.ready=true;if parents{self.next_directory=physical.capture_codemod_parent(self)?;}Ok(())
 }
}
pub(crate)struct Targets<'a>{rows:[CapturedCodemodTarget<'a>;3],mode:Mode,revert:Option<RevertCaptured>}
impl<'a>Targets<'a>{
 pub(crate)fn new(root:&'a Path,name:&str,mode:Mode)->io::Result<Self>{
  if !root.is_absolute()||dq_analyze::codemod::native_find(name).is_none(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"codemod output needs actual absolute root and native registry member"))}
  let [residue,keys,revert]=paths(name)?;
  Ok(Self{rows:[CapturedCodemodTarget{root,relative:residue,kind:Output::Residue,actual:None,next_directory:None,ready:false},CapturedCodemodTarget{root,relative:keys,kind:Output::Keys,actual:None,next_directory:None,ready:false},CapturedCodemodTarget{root,relative:revert,kind:Output::RevertRecord,actual:None,next_directory:None,ready:false}],mode,revert:None})
 }
 pub(crate)fn target(&self,kind:Output)->&CapturedCodemodTarget<'a>{&self.rows[match kind{Output::Residue=>0,Output::Keys=>1,Output::RevertRecord=>2}]}
}
impl Capture for Targets<'_>{
 fn begin_attempt(&mut self){self.revert=None;for row in &mut self.rows{row.reset()}}
 fn workspace_roster(&mut self,_:&crate::runner_host::workspace_discovery::DiscoveryReceipt,_:&dyn SourceArenaWork)->io::Result<()>{Ok(())}
 fn prepare_current(&mut self,_:&dm_tree::frontend::DiagnosticSourceView<'_>,_:&crate::runner_host::query_snapshot::SourceSnapshot,_:&dyn SourceArenaWork)->Result<(),Box<dyn std::error::Error>>{Ok(())}
 fn capture(&mut self,physical:&mut dyn UtilityPhysicalInputs)->io::Result<()>{for row in &mut self.rows{let needed=match self.mode{Mode::Check=>false,Mode::Apply|Mode::Revert=>row.kind==Output::RevertRecord,Mode::WriteResidue=>row.kind!=Output::RevertRecord};if needed{row.capture(physical,self.mode!=Mode::Revert)?}}if self.mode==Mode::Revert{self.capture_revert(physical)?;}Ok(())}
}
/// Both consumers see the same actual attempt, model and physical lender. This
/// combines obligations; it never creates a second request or swallows IO.
pub(crate)struct Pair<'a>{pub(crate)first:&'a mut dyn Capture,pub(crate)second:&'a mut dyn Capture}
impl Capture for Pair<'_>{
 fn begin_attempt(&mut self){self.first.begin_attempt();self.second.begin_attempt()}
 fn workspace_roster(&mut self,actual:&crate::runner_host::workspace_discovery::DiscoveryReceipt,work:&dyn SourceArenaWork)->io::Result<()>{self.first.workspace_roster(actual,work)?;self.second.workspace_roster(actual,work)}
 fn prepare_current(&mut self,view:&dm_tree::frontend::DiagnosticSourceView<'_>,snapshot:&crate::runner_host::query_snapshot::SourceSnapshot,work:&dyn SourceArenaWork)->Result<(),Box<dyn std::error::Error>>{self.first.prepare_current(view,snapshot,work)?;self.second.prepare_current(view,snapshot,work)}
 fn capture(&mut self,physical:&mut dyn UtilityPhysicalInputs)->io::Result<()>{self.first.capture(physical)?;self.second.capture(physical)}
}
#[cfg(test)]mod tests{use super::*;
 #[test]fn output_registry_is_closed_to_actual_commands_and_exact_artifacts(){for name in ["own_set","own_add","om_after"]{let keys=paths(name).unwrap();assert!(keys[0].ends_with("/residue.json"));assert!(keys[1].ends_with("/keys.json"));assert!(keys[2].starts_with("data/codemod/"));assert!(keys[2].ends_with("/revert.json"));}for name in ["../own_set","own_set/revert.json","tracked",""]{assert!(paths(name).is_err());}}
}

struct RevertCaptured{files:Vec<dq_analyze::codemod::report::RevertFile>,sources:Vec<UtilityBytes>,_credit:dm_preprocess::source_arena_credit::SourceArenaCredit}
struct LoanWork<'a>{work:&'a dyn SourceArenaWork,credit:std::cell::RefCell<dm_preprocess::source_arena_credit::SourceArenaCredit>}
impl dq_analyze::policy_finish::admitted::Work for LoanWork<'_>{fn checkpoint(&self)->io::Result<()>{self.work.checkpoint()}fn reserve(&self,bytes:usize)->io::Result<()>{self.work.checkpoint()?;self.work.grow(&mut *self.credit.try_borrow_mut().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"codemod revert work reentered"))?,bytes)}fn overflow(&self)->io::Error{io::ErrorKind::OutOfMemory.into()}}
impl Targets<'_>{
 fn capture_revert(&mut self,physical:&mut dyn UtilityPhysicalInputs)->io::Result<()>{
  let record=self.target(Output::RevertRecord).preimage()?;if self.target(Output::RevertRecord).stamp()?.is_none(){return Err(io::Error::new(io::ErrorKind::NotFound,"nothing to revert: --apply writes the record"))}
  let text=std::str::from_utf8(record).map_err(|error|io::Error::new(io::ErrorKind::InvalidData,error))?;let mut parsed=None;
  physical.with_work(&mut|work|{let loan=LoanWork{work,credit:std::cell::RefCell::new(work.reserve(0)?)};let files=dq_analyze::codemod::report::parse_revert_using(text,&loan)?;dq_analyze::policy_finish::admitted::Work::reserve(&loan,files.len().checked_mul(std::mem::size_of::<UtilityBytes>()).ok_or(io::ErrorKind::OutOfMemory)?)?;let mut sources=Vec::new();sources.try_reserve_exact(files.len()).map_err(|_|io::ErrorKind::OutOfMemory)?;if sources.capacity()>files.len(){return Err(io::ErrorKind::OutOfMemory.into())}parsed=Some(RevertCaptured{files,sources,_credit:loan.credit.into_inner()});Ok(())})?;
  let mut parsed=parsed.ok_or_else(||io::Error::other("codemod revert parser loan omitted"))?;
  for file in &parsed.files{
   let rel=Path::new(&file.file);if file.file.is_empty()||file.file.contains(['\\',':'])||rel.components().any(|part|!matches!(part,std::path::Component::Normal(_)))||rel.extension()!=Some(std::ffi::OsStr::new("dm")){return Err(io::Error::new(io::ErrorKind::InvalidData,"revert record target is not ordinary authored DM"))}
   let mut path=None;physical.with_work(&mut|work|{path=Some(paid_path(self.target(Output::RevertRecord).root(),&file.file,work)?);Ok(())})?;let(path,_credit)=path.ok_or_else(||io::Error::other("revert source path loan omitted"))?;
   let actual=physical.read(&path,dq_analyze::selected_exclusions_wire::MAX_STREAM as usize)?.ok_or_else(||io::Error::new(io::ErrorKind::NotFound,"revert source was removed"))?;
   if parsed.sources.len()==parsed.sources.capacity(){return Err(io::ErrorKind::OutOfMemory.into())}parsed.sources.push(actual);
  }
  self.revert=Some(parsed);Ok(())
 }
 pub(crate)fn revert_files(&self)->io::Result<&[dq_analyze::codemod::report::RevertFile]>{self.revert.as_ref().map(|actual|actual.files.as_slice()).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"revert files were not actually captured"))}
 pub(crate)fn revert_source(&self,relative:&str)->Option<&UtilityBytes>{let actual=self.revert.as_ref()?;actual.files.iter().position(|file|file.file==relative).and_then(|index|actual.sources.get(index))}
}

impl dq_analyze::captured_codemod_plan::RevertInputs for Targets<'_>{fn file(&self,relative:&str)->Option<&[u8]>{self.revert_source(relative).map(UtilityBytes::bytes)}}
