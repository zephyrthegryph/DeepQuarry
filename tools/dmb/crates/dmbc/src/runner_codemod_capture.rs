//! Required physical codemod inputs on the SAME prepared Original operation.
//! WORKING source: not a writer, public endpoint, completion grant or cache.
use super::*;
use std::{cell::RefCell,io,path::{Path,PathBuf}};
use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
use crate::input_snapshot::utility_capture::{UtilityBytes,UtilityPhysicalInputs};
use dq_analyze::{codemod::Codemod,captured_codemod_calls::Rows,captured_reactive_reads::Failure};

struct FrameWork<'a>{work:&'a dyn SourceArenaWork,credit:RefCell<SourceArenaCredit>}
impl<'a>FrameWork<'a>{fn new(work:&'a dyn SourceArenaWork)->io::Result<Self>{Ok(Self{work,credit:RefCell::new(work.reserve(0)?)})}}
impl dq_analyze::policy_finish::admitted::Work for FrameWork<'_>{
 fn checkpoint(&self)->io::Result<()>{self.work.checkpoint()}
 // The canonical walker reports the combined OLD+NEW stack capacities at
 // each growth frontier. Bodies are visited sequentially; retain the largest
 // actual frontier instead of charging every earlier (now dead) stack again.
 fn reserve(&self,bytes:usize)->io::Result<()>{
  let mut credit=self.credit.try_borrow_mut().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"codemod frame work already borrowed"))?;
  let extra=bytes.saturating_sub(credit.reserved_bytes());self.work.grow(&mut credit,extra)
 }
 fn overflow(&self)->io::Error{io::ErrorKind::OutOfMemory.into()}
}
/// All byte/row/path payloads die before their matching actual metadata credit.
struct Physical{relative:String,bytes:UtilityBytes}
#[derive(Clone,Copy,Eq,PartialEq)]pub(crate)enum Mode{Check,Apply,WriteResidue,Revert}
pub(crate) struct Captured<'a>{
 root:&'a Path,cm:&'a dyn Codemod,mode:Mode,
 calls:Option<Rows>,physical_roster:Option<utility_capture::Roster>,
 wanted:Vec<usize>,files:Vec<Physical>,absent:Vec<String>,manifest:Option<UtilityBytes>,residue:Option<UtilityBytes>,
 metadata:Option<SourceArenaCredit>,
}
impl<'a>Captured<'a>{
 pub(crate) fn new(root:&'a Path,cm:&'a dyn Codemod,mode:Mode)->Self{Self{root,cm,mode,calls:None,physical_roster:None,wanted:Vec::new(),files:Vec::new(),absent:Vec::new(),manifest:None,residue:None,metadata:None}}
 pub(crate) fn calls(&self)->io::Result<&Rows>{self.calls.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"actual codemod call preparation absent"))}
 /// Actual immutable preimages, not a rewrite authorization. The caller must
 /// retain this capture and final moved Inputs through the physical attempt.
 pub(crate) fn actual_file(&self,relative:&str)->Option<&UtilityBytes>{self.files.binary_search_by(|row|row.relative.as_str().cmp(relative)).ok().map(|i|&self.files[i].bytes)}
 pub(crate) fn manifest(&self)->Option<&[u8]>{self.manifest.as_ref().map(UtilityBytes::bytes)}
 pub(crate) fn committed_residue(&self)->Option<&str>{self.residue.as_ref().and_then(|actual|std::str::from_utf8(actual.bytes()).ok())}
 fn reset(&mut self){self.residue=None;self.absent.clear();self.absent.shrink_to_fit();self.files.clear();self.files.shrink_to_fit();self.manifest=None;self.wanted.clear();self.wanted.shrink_to_fit();self.physical_roster=None;self.calls=None;self.metadata=None;}
 fn prepare_roster(&mut self,actual:&crate::runner_host::workspace_discovery::DiscoveryReceipt,work:&dyn SourceArenaWork)->io::Result<()>{
  if self.physical_roster.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"codemod physical roster repeated"))}
  let calls=self.calls()?;let wanted_upper=calls.rows().len().checked_mul(4).ok_or(io::ErrorKind::OutOfMemory)?;
  let file_upper=actual.files().len().checked_add(calls.rows().len()).and_then(|n|n.checked_mul(4)).ok_or(io::ErrorKind::OutOfMemory)?;
  let mut bytes=wanted_upper.checked_mul(std::mem::size_of::<usize>()).and_then(|n|n.checked_add(file_upper.checked_mul(std::mem::size_of::<Physical>())?)).ok_or(io::ErrorKind::OutOfMemory)?;
  bytes=bytes.checked_add(file_upper.checked_mul(std::mem::size_of::<String>()).ok_or(io::ErrorKind::OutOfMemory)?).ok_or(io::ErrorKind::OutOfMemory)?;
  let mut credit=work.reserve(bytes)?;let roster=utility_capture::Roster::capture(actual,work)?;
  let mut wanted=Vec::new();wanted.try_reserve_exact(calls.rows().len()).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;if wanted.capacity()>wanted_upper{return Err(io::ErrorKind::OutOfMemory.into())}
  wanted.extend(0..calls.rows().len());wanted.sort_unstable_by(|a,b|calls.rows()[*a].rel.cmp(&calls.rows()[*b].rel));wanted.dedup_by(|a,b|calls.rows()[*a].rel==calls.rows()[*b].rel);
  let mut files=Vec::new();files.try_reserve_exact(actual.files().len().checked_add(calls.rows().len()).ok_or(io::ErrorKind::OutOfMemory)?).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;if files.capacity()>file_upper{return Err(io::ErrorKind::OutOfMemory.into())}
  let mut absent=Vec::new();absent.try_reserve_exact(actual.files().len()).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;if absent.capacity()>file_upper{return Err(io::ErrorKind::OutOfMemory.into())}
  let actual_rows=wanted.capacity().checked_mul(std::mem::size_of::<usize>()).and_then(|n|n.checked_add(files.capacity().checked_mul(std::mem::size_of::<Physical>())?)).and_then(|n|n.checked_add(absent.capacity().checked_mul(std::mem::size_of::<String>())?)).ok_or(io::ErrorKind::OutOfMemory)?;
  work.shrink(&mut credit,bytes.checked_sub(actual_rows).ok_or(io::ErrorKind::OutOfMemory)?)?;
  self.metadata=Some(credit);self.physical_roster=Some(roster);self.wanted=wanted;self.files=files;self.absent=absent;Ok(())
 }
}
impl utility_capture::Capture for Captured<'_>{
 fn begin_attempt(&mut self){self.reset()}
 fn workspace_roster(&mut self,_actual:&crate::runner_host::workspace_discovery::DiscoveryReceipt,_work:&dyn SourceArenaWork)->io::Result<()>{Ok(())}
 fn prepare_current(&mut self,_view:&dm_tree::frontend::DiagnosticSourceView<'_>,snapshot:&crate::runner_host::query_snapshot::SourceSnapshot,_outer:&dyn SourceArenaWork)->Result<(),Box<dyn std::error::Error>>{
  if self.mode==Mode::Revert{return Ok(())}let cm=self.cm;let mut calls=None;
  snapshot.with_semantic_only_utility_model(self.root,|inputs,root,budget,work,body|{
   let frames=FrameWork::new(work).map_err(Failure::Operational)?;
   calls=Some(Rows::collect(inputs,root,cm.callees(),cm.ast_alias(),&|relative|cm.excluded(relative),budget,&crate::daemon::control::checkpoint,body,&frames,work)?);Ok(())
  })?;
  self.calls=calls;Ok(())
 }
 fn capture(&mut self,physical:&mut dyn UtilityPhysicalInputs)->io::Result<()>{
  if self.mode==Mode::Revert{return Ok(())}let root=self.root;physical.with_dm_roster(root,&mut|actual,work|self.prepare_roster(actual,work))?;
  let roster=self.physical_roster.as_ref().ok_or_else(||io::Error::other("codemod physical discovery omitted"))?;
  let calls=self.calls.as_ref().ok_or_else(||io::Error::other("codemod actual call rows omitted"))?;
  let limit=crate::runner_host::policy_capture::MAX_POLICY_CAPTURE_CHARGE;
  for path in roster.paths(){
   crate::daemon::control::checkpoint()?;
   let mut relative=None;physical.with_work(&mut|work|{let metadata=self.metadata.as_mut().ok_or_else(||io::Error::other("codemod metadata grant omitted"))?;relative=Some(dm_preprocess::regions::relative_slash_only_into_credit(path,root,work,metadata)?.ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"codemod physical roster escapes actual root"))?);Ok(())})?;
   let relative=relative.ok_or_else(||io::Error::other("codemod relative path work not entered"))?;
   let required=self.wanted.binary_search_by(|index|calls.rows()[*index].rel.as_str().cmp(relative.as_str())).is_ok();
   let read=if required{physical.read(path,limit)}else{physical.read_optional(path,limit)};
   let Some(bytes)=read?else{if required{return Err(io::Error::new(io::ErrorKind::NotFound,"actual codemod call source disappeared before byte capture"))}if self.absent.len()==self.absent.capacity(){return Err(io::ErrorKind::OutOfMemory.into())}self.absent.push(relative);continue};
   // The original lexical ownership/declaration preparation reads ALL Tree
   // files, including declaration destinations with no callee text. Retain
   // their authentic paid bytes; filtering to call mentions here would lose
   // real declaration edits. The shared edit kernel performs its own exact
   // candidate/residue selection later. No hidden untracked byte bank.
   if self.files.len()==self.files.capacity(){return Err(io::ErrorKind::OutOfMemory.into())}
   self.files.push(Physical{relative,bytes});
  }
  // A compiled origin can lie outside CODE/MAPS but still inside the exact
  // actual root. It is demanded by an authentic call row, never a new crawl.
  // Discovery order is authentic roster DATA, not an ordering promise for
  // the retained subset. Sort before the exact candidate lookup.
  self.files.sort_unstable_by(|a,b|a.relative.cmp(&b.relative));
  let roster_files=self.files.len();
  for index in &self.wanted{
   let relative=&calls.rows()[*index].rel;
   if self.files[..roster_files].binary_search_by(|row|row.relative.as_str().cmp(relative.as_str())).is_ok(){continue}
   if Path::new(relative).is_absolute()||Path::new(relative).components().any(|part|matches!(part,std::path::Component::ParentDir|std::path::Component::RootDir|std::path::Component::Prefix(_))){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual codemod call path escapes caller root"))}
   let(mut path,mut owned_relative)=(None,None);physical.with_work(&mut|work|{path=Some(dm_preprocess::regions::joined_path_using(root,relative,work)?);let metadata=self.metadata.as_mut().ok_or_else(||io::Error::other("codemod metadata grant omitted"))?;owned_relative=Some(dm_preprocess::regions::copy_string_into_credit(relative,work,metadata)?);Ok(())})?;
   let path=path.ok_or_else(||io::Error::other("codemod joined path work not entered"))?;let bytes=physical.read(path.path(),limit)?.ok_or_else(||io::Error::new(io::ErrorKind::NotFound,"actual codemod call source disappeared before byte capture"))?;drop(path);
   if self.files.len()==self.files.capacity(){return Err(io::ErrorKind::OutOfMemory.into())}self.files.push(Physical{relative:owned_relative.ok_or_else(||io::Error::other("codemod relative copy work not entered"))?,bytes});
  }
  self.files.sort_unstable_by(|a,b|a.relative.cmp(&b.relative));
  if self.files.windows(2).any(|pair|pair[0].relative==pair[1].relative){return Err(io::Error::new(io::ErrorKind::InvalidData,"codemod physical input repeated"))}
  // The old declaration include-order reader treats OS/read/UTF8 errors as
  // absent DATA. A positive invalid-UTF8 fact remains positive in the ledger.
  if self.cm.declares(){let mut path=None;physical.with_work(&mut|work|{path=Some(dm_preprocess::regions::joined_path_using(root,"deepquarry.dme",work)?);Ok(())})?;let path=path.ok_or_else(||io::Error::other("codemod manifest path work not entered"))?;self.manifest=physical.read_optional(path.path(),limit)?;}
  self.absent.sort_unstable();
  if self.mode==Mode::Check{
   let relative=match self.cm.name(){"own_set"=>"tools/analyze/codemods/own_set/residue.json","own_add"=>"tools/analyze/codemods/own_add/residue.json","om_after"=>"tools/analyze/codemods/om_after/residue.json",_=>return Err(io::Error::new(io::ErrorKind::InvalidInput,"unknown actual codemod residue path"))};
   let mut path=None;physical.with_work(&mut|work|{path=Some(dm_preprocess::regions::joined_path_using(root,relative,work)?);Ok(())})?;let path=path.ok_or_else(||io::Error::other("codemod residue path work not entered"))?;
   self.residue=physical.read_optional(path.path(),limit)?;
  }
  Ok(())
 }
}

/// Borrow only actual final-attempt captures; the returned Vec copy is paid by
/// the plan's SAME retained work before allocating it. No OS read or path
/// absence is inferred from an unrequested DATA key.
pub(crate) struct PhysicalCopy<'a,'capture>{pub(crate) captured:&'a Captured<'capture>}
impl dq_analyze::codemod::PhysicalFiles for PhysicalCopy<'_,'_>{
 fn read(&self,_relative:&str)->io::Result<Option<Vec<u8>>>{Err(io::Error::new(io::ErrorKind::InvalidInput,"native physical preimage copy needs actual admitted plan work"))}
 fn read_using(&self,relative:&str,work:Option<&dyn dq_analyze::policy_finish::admitted::Work>)->io::Result<Option<Vec<u8>>>{
  let work=work.ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"native physical copy omitted same operation work"))?;work.checkpoint()?;
  let Some(actual)=self.captured.actual_file(relative)else{
   if self.captured.absent.binary_search_by(|path|path.as_str().cmp(relative)).is_ok(){return Ok(None)}
   return Err(io::Error::new(io::ErrorKind::NotFound,"codemod declaration destination was not captured in this actual attempt"))
  };
  work.reserve(actual.bytes().len())?;let mut bytes=Vec::new();bytes.try_reserve_exact(actual.bytes().len()).map_err(|_|work.overflow())?;
  if bytes.capacity()>actual.bytes().len(){return Err(work.overflow())}
  for part in actual.bytes().chunks(8192){work.checkpoint()?;bytes.extend_from_slice(part);}
  work.checkpoint()?;Ok(Some(bytes))
 }
}

impl dq_analyze::captured_codemod_plan::PhysicalInputs for Captured<'_>{
 fn for_each(&self,visit:&mut dyn FnMut(&str,dq_analyze::captured_codemod_plan::FileData<'_>)->io::Result<()>)->io::Result<()>{
  use dq_analyze::captured_codemod_plan::FileData;
  let(mut present,mut missing)=(0,0);
  while present<self.files.len()||missing<self.absent.len(){
   crate::daemon::control::checkpoint()?;
   match(self.files.get(present),self.absent.get(missing)){
    (Some(file),Some(absent))=>match file.relative.cmp(absent){std::cmp::Ordering::Less=>{visit(&file.relative,FileData::Bytes(file.bytes.bytes()))?;present+=1},std::cmp::Ordering::Greater=>{visit(absent,FileData::NoText)?;missing+=1},std::cmp::Ordering::Equal=>return Err(io::Error::new(io::ErrorKind::InvalidData,"codemod input has both positive and absent capture"))},
    (Some(file),None)=>{visit(&file.relative,FileData::Bytes(file.bytes.bytes()))?;present+=1},
    (None,Some(absent))=>{visit(absent,FileData::NoText)?;missing+=1},(None,None)=>break,
   }
  }
  Ok(())
 }
 fn file(&self,relative:&str)->Option<dq_analyze::captured_codemod_plan::FileData<'_>>{
  use dq_analyze::captured_codemod_plan::FileData;
  match self.actual_file(relative){Some(actual)=>Some(FileData::Bytes(actual.bytes())),None=>self.absent.binary_search_by(|path|path.as_str().cmp(relative)).ok().map(|_|FileData::NoText)}
 }
}
