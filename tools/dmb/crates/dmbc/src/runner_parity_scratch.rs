//! Oracle-only owned physical sources. The real producer keeps authority; this
//! namespace carries copied DATA and fixed output slots, never a source receipt.
use super::{FullRegistryCheckInputs,NativeFixtureSources};
use crate::input_snapshot::{Stamp,SnapshotProvider};
use dm_preprocess::{source_arena_credit::{SourceArenaCredit,SourceArenaWork},regions as funded_path};
use std::{io::{self,Read},path::{Path,PathBuf,Component},mem::size_of};
fn invalid(s:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,s)}
fn oom()->io::Error{io::ErrorKind::OutOfMemory.into()}
fn add(a:usize,b:usize)->io::Result<usize>{a.checked_add(b).ok_or_else(oom)}
fn four(n:usize)->io::Result<usize>{n.checked_mul(4).ok_or_else(oom)}
fn rows<T>(rows:&mut Vec<T>,work:&dyn SourceArenaWork,credit:&mut SourceArenaCredit)->io::Result<()>{
 if rows.len()<rows.capacity(){return Ok(())}let n=add(rows.len(),1)?;let paid=four(n.checked_mul(size_of::<T>()).ok_or_else(oom)?)?;work.grow(credit,paid)?;
 let before=rows.capacity().checked_mul(size_of::<T>()).ok_or_else(oom)?;rows.try_reserve_exact(1).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
 let after=rows.capacity().checked_mul(size_of::<T>()).ok_or_else(oom)?;if after>paid{return Err(oom())}work.shrink(credit,add(paid,before)?.checked_sub(after).ok_or_else(oom)?)
}
fn joined(parent:&Path,relative:&Path,work:&dyn SourceArenaWork,credit:&mut SourceArenaCredit)->io::Result<PathBuf>{
 let need=add(add(parent.as_os_str().len(),relative.as_os_str().len())?,1)?;let paid=four(need)?;work.grow(credit,paid)?;
 let mut path=PathBuf::new();path.try_reserve_exact(need).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;path.push(parent);path.push(relative);
 if path.capacity()>paid{return Err(oom())}work.shrink(credit,paid-path.capacity())?;Ok(path)
}
fn normal(path:&Path)->bool{!path.as_os_str().is_empty()&&path.components().all(|p|matches!(p,Component::Normal(_)))}
#[derive(Clone,Copy)]pub(crate) struct OutputId{root:u128,index:usize}
struct Frozen{path:PathBuf,stamp:Stamp,content:u128}
struct Output{path:PathBuf,state:Option<(Stamp,u128)>,open:bool}
/// Credit drops last, after the SAME physical source owner and all copied paths.
pub(crate) struct Sandbox{
 sources:NativeFixtureSources,frozen:Vec<Frozen>,outputs:Vec<Output>,guard_peak:usize,
 initial_guard:usize,_root_credit:SourceArenaCredit,_credit:SourceArenaCredit,
}
impl Sandbox{
 pub(crate) fn new(cache:&Path,work:&dyn SourceArenaWork)->io::Result<Self>{
  work.checkpoint()?;if !cache.is_absolute()||crate::daemon::control::WorkerContext::capture_for_checkpoints().is_none(){return Err(invalid("parity scratch requires the actual absolute cache and active request"))}
  let mut credit=work.reserve(size_of::<Self>())?;
  let parent=funded_path::copy_path_into_credit(cache,work,&mut credit)?;
  // This is the SAME held ancestor kernel as NativeFixtureSources. Persistent
  // root guard and temporary guard high-water own separate actual backing.
  work.grow(&mut credit,crate::frozen_inputs::generation_publication_guard_charge(cache,cache)?)?;
  let guard=crate::frozen_inputs::generation_ancestor_guard(cache,cache)?;
  fn digits(mut n:u64)->usize{let mut d=1;while n>=10{n/=10;d+=1}d}
  for _ in 0..16{
   work.checkpoint()?;let next=super::native_fixture_next_id();let pid=std::process::id();
   let len=add(add("native-selftest--".len(),digits(u64::from(pid)))?,digits(next))?;let mut name_credit=work.reserve(four(len)?)?;
   let mut name=String::new();name.try_reserve_exact(len).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
   use std::fmt::Write;write!(&mut name,"native-selftest-{pid}-{next}").map_err(|_|oom())?;
   if name.capacity()>four(len)?{return Err(oom())}work.shrink(&mut name_credit,four(len)?-name.capacity())?;
   let mut attempt=work.reserve(0)?;let root=joined(&parent,Path::new(&name),work,&mut attempt)?;
   let guard_peak=crate::frozen_inputs::generation_publication_guard_charge(&root,&parent)?;work.grow(&mut attempt,guard_peak)?;
   match std::fs::create_dir(&root){
    Ok(())=>{let identity=crate::frozen_inputs::generation_directory_identity(&root,&parent)?;
     // Move actual root backing into the one keeper; no clone or hidden budget.
     return Ok(Self{sources:NativeFixtureSources{root,parent,identity,files:Vec::new(),directories:Vec::new(),_parent:guard,_resource:None},frozen:Vec::new(),outputs:Vec::new(),guard_peak,initial_guard:guard_peak,_root_credit:attempt,_credit:credit})},
    Err(actual)if actual.kind()==io::ErrorKind::AlreadyExists=>{drop(root);drop(attempt)},Err(actual)=>return Err(actual),
   }
  }Err(io::Error::new(io::ErrorKind::AlreadyExists,"native parity source namespace exhausted"))
 }
 pub(crate) fn root(&self)->&Path{self.sources.root()}
 fn guard(&mut self,path:&Path,work:&dyn SourceArenaWork)->io::Result<()>{let need=crate::frozen_inputs::generation_publication_guard_charge(path,self.root())?;if need>self.guard_peak{work.grow(&mut self._credit,need-self.guard_peak)?;self.guard_peak=need}Ok(())}
 /// Pay the exact old physical kernel's constructor frontier before it runs.
 /// These four-slot envelopes are the established std Vec/OsString allocator
 /// bounds used by fixture_sources_admitted; they are not input-size budgets.
 fn preflight(&mut self,relative:&str,file:bool,work:&dyn SourceArenaWork)->io::Result<SourceArenaCredit>{
  let path=Path::new(relative);if !normal(path){return Err(invalid("parity scratch path must be an ordinary relative path"))}
  let mut path_credit=work.reserve(0)?;let full=joined(self.root(),path,work,&mut path_credit)?;
  self.guard(&full,work)?;let mut temporary=work.reserve(0)?;let components=path.components().count();
  work.grow(&mut temporary,four(components.max(4).checked_mul(size_of::<Component<'_>>()).ok_or_else(oom)?)?)?;
  work.grow(&mut temporary,four(full.as_os_str().len())?)?;
  work.grow(&mut temporary,four(self.root().as_os_str().len())?)?;
  work.grow(&mut temporary,four(full.as_os_str().len())?)?;
  // Retained parent clones and the owned file path survive the call. Reserve
  // their actual final path widths and row capacity before create_dir/open.
  let mut width=self.root().as_os_str().len();for part in path.parent().unwrap_or_else(||Path::new("")).components(){width=add(add(width,part.as_os_str().len())?,1)?;work.grow(&mut self._credit,four(width)?)?;}
  if file{work.grow(&mut self._credit,four(full.as_os_str().len())?)?;}
  // SAME underlying vectors are reserved here, not independently reconstructed.
  let extra=components.saturating_sub(1);for _ in 0..extra{let n=add(self.sources.directories.len(),extra)?;if n>self.sources.directories.capacity(){let paid=four(n.checked_mul(size_of::<(PathBuf,u128)>()).ok_or_else(oom)?)?;work.grow(&mut self._credit,paid)?;self.sources.directories.try_reserve_exact(extra).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if self.sources.directories.capacity().checked_mul(size_of::<(PathBuf,u128)>()).is_none_or(|n|n>paid){return Err(oom())}}}
  if file{rows(&mut self.sources.files,work,&mut self._credit)?;}Ok(temporary)
 }
 fn settle(&mut self,work:&dyn SourceArenaWork)->io::Result<()>{
  let mut actual=size_of::<Self>();actual=add(actual,self.sources.parent.capacity())?;
  actual=add(actual,crate::frozen_inputs::generation_publication_guard_charge(&self.sources.parent,&self.sources.parent)?)?;
  actual=add(actual,self.guard_peak-self.initial_guard)?;
  for n in [self.sources.files.capacity().checked_mul(size_of::<(PathBuf,Stamp)>()),self.sources.directories.capacity().checked_mul(size_of::<(PathBuf,u128)>()),self.frozen.capacity().checked_mul(size_of::<Frozen>()),self.outputs.capacity().checked_mul(size_of::<Output>())]{actual=add(actual,n.ok_or_else(oom)?)?;}
  for(path,_)in &self.sources.files{actual=add(actual,path.capacity())?;}for(path,_)in &self.sources.directories{actual=add(actual,path.capacity())?;}
  for row in &self.frozen{actual=add(actual,row.path.capacity())?;}for row in &self.outputs{actual=add(actual,row.path.capacity())?;}
  let paid=self._credit.reserved_bytes();if actual>paid{return Err(invalid("owned parity physical storage exceeded its paid constructor frontier"))}work.shrink(&mut self._credit,paid-actual)
 }
 fn remember(&mut self,path:&Path,work:&dyn SourceArenaWork)->io::Result<()>{
  let(stamp,content)=digest(path,work)?;rows(&mut self.frozen,work,&mut self._credit)?;
  let path=funded_path::copy_path_into_credit(path,work,&mut self._credit)?;self.frozen.push(Frozen{path,stamp,content});Ok(())
 }
 fn put(&mut self,relative:&str,bytes:&[u8],work:&dyn SourceArenaWork)->io::Result<()>{
  let mut local=work.reserve(0)?;let path=joined(self.root(),Path::new(relative),work,&mut local)?;
  if let Some(existing)=self.frozen.iter().find(|row|row.path==path){if existing.content==hash_bytes(bytes,work)?&&existing.stamp.size==bytes.len()as u64{return Ok(())}return Err(invalid("parity captured files map to conflicting scratch bytes"))}
  let paid=self.preflight(relative,true,work)?;self.sources.put_unadmitted(relative,bytes)?;drop(paid);self.remember(&path,work)?;self.settle(work)
 }
 pub(crate) fn copy_captured(&mut self,inputs:&FullRegistryCheckInputs,project:&Path,source_root:&Path,selected_configuration:Option<&Path>,work:&dyn SourceArenaWork)->Result<(),Box<dyn std::error::Error>>{
  let mut selected_found=selected_configuration.is_none();inputs.with_report_input_observation(project,|snapshot|{
   snapshot.visit_captured_directories(work,&mut|path,present|{if !present{return Ok(())}let Ok(relative)=path.strip_prefix(source_root)else{return Ok(())};if relative.as_os_str().is_empty(){return Ok(())}if !normal(relative){return Err(invalid("captured parity directory is not ordinary"))}
    // Only the parent kernel runs. This private sentinel is never created.
    let mut path_credit=work.reserve(0)?;let sentinel=joined(relative,Path::new(".native-parity-never-created"),work,&mut path_credit)?;let relative=sentinel.to_str().ok_or_else(||invalid("captured parity directory is not UTF8"))?;
    let paid=self.preflight(relative,false,work)?;let directory=self.sources.ensure_parents_unadmitted(relative)?;drop(directory);drop(paid);self.settle(work)
   })?;
   snapshot.visit_captured_physical_files(work,&mut|path,stamp,content|{
   let Ok(relative)=path.strip_prefix(source_root)else{return Ok(())};if !normal(relative){return Err(invalid("captured parity source path is not ordinary within its genuine root"))}
   let config=Path::new("tools/ci/lint_scopes.toml");let destination=if selected_configuration==Some(path){selected_found=true;config}else{if selected_configuration.is_some()&&relative==config{return Ok(())}relative};
   let physical=crate::native_fix_physical::read(path,stamp,work)?;if hash_bytes(&physical.bytes,work)?!=content{return Err(invalid("parity physical copy differs from actual closed input contents"))}
   let text=destination.to_str().ok_or_else(||invalid("parity scratch relative source is not UTF8"))?;self.put(text,&physical.bytes,work)
  })})?;if !selected_found{return Err(invalid("effective parity configuration was not actually read by its producer").into())}self.current(work)?;Ok(())
 }
 fn output(&mut self,relative:&str,preimage:Option<&[u8]>,work:&dyn SourceArenaWork)->io::Result<OutputId>{
  let mut local=work.reserve(0)?;let path=joined(self.root(),Path::new(relative),work,&mut local)?;
  if self.outputs.iter().any(|row|row.path==path){return Err(invalid("parity declared the same mutable output twice"))}
  if let Some(bytes)=preimage{self.put(relative,bytes,work)?;}else{
   if self.frozen.iter().any(|row|row.path==path){return Err(invalid("captured absent output conflicts with a real positive source fact"))}
   let paid=self.preflight(relative,false,work)?;let _=self.sources.ensure_parents_unadmitted(relative)?;drop(paid);
  }
  rows(&mut self.outputs,work,&mut self._credit)?;let owned=funded_path::copy_path_into_credit(&path,work,&mut self._credit)?;
  let index=self.outputs.len();self.outputs.push(Output{path:owned,state:None,open:true});self.settle(work)?;Ok(OutputId{root:self.sources.identity,index})
 }
 pub(crate) fn ensure_fixture_output(&mut self,target:&crate::runner_host::fixture_scope::CapturedFixtureTarget,source_root:&Path,work:&dyn SourceArenaWork)->io::Result<OutputId>{
  let relative_root=target.root().strip_prefix(source_root).map_err(|_|invalid("actual fixture target escapes source root"))?;if !normal(relative_root){return Err(invalid("actual fixture target root is not an ordinary descendant"))}
  let mut local=work.reserve(0)?;let relative=joined(relative_root,Path::new(target.relative()),work,&mut local)?;self.output(relative.to_str().ok_or_else(||invalid("actual fixture output path is not UTF8"))?,target.original().map(|row|row.bytes()),work)
 }
 pub(crate) fn ensure_baseline_output(&mut self,target:&crate::runner_host::workspace_capture::BaselineTarget,source_root:&Path,work:&dyn SourceArenaWork)->io::Result<OutputId>{
  if target.root()!=source_root{return Err(invalid("baseline target belongs to another captured source root"))}self.output(target.relative(),target.stamp().map(|_|target.preimage()),work)
 }
 /// Call after the oracle even on its failure, before cleanup. Only these exact
 /// typed slots may be adopted; no directory crawl or arbitrary output import.
 pub(crate) fn enroll_outputs(&mut self,work:&dyn SourceArenaWork)->io::Result<()>{
  self.sources.current_unadmitted()?;
  for index in 0..self.outputs.len(){
   work.checkpoint()?;let output=&self.outputs[index];let parent=output.path.parent().ok_or_else(||invalid("owned output has no parent"))?;
   let _guard=crate::frozen_inputs::generation_ancestor_guard(parent,self.root())?;
   match std::fs::symlink_metadata(&output.path){
    Ok(metadata)=>{ordinary_output(&metadata)?;let(stamp,content)=digest(&output.path,work)?;if stamp.file_id.is_none(){return Err(invalid("oracle output lacks stable closed identity"))}
     if let Some((_,owned))=self.sources.files.iter_mut().find(|(path,_)|*path==output.path){*owned=stamp.clone()}else{
      rows(&mut self.sources.files,work,&mut self._credit)?;let path=funded_path::copy_path_into_credit(&output.path,work,&mut self._credit)?;self.sources.files.push((path,stamp.clone()));
     }self.outputs[index].state=Some((stamp,content));
    },
    Err(actual)if actual.kind()==io::ErrorKind::NotFound=>{if let Some(at)=self.sources.files.iter().position(|(path,_)|*path==output.path){self.sources.files.remove(at);}self.outputs[index].state=None},
    Err(actual)=>return Err(actual),
   }self.outputs[index].open=false;
  }self.settle(work)?;self.current(work)
 }
 pub(crate) fn current(&self,work:&dyn SourceArenaWork)->io::Result<()>{
  self.sources.current_unadmitted()?;
  for(path,identity)in &self.sources.directories{work.checkpoint()?;if crate::frozen_inputs::generation_directory_identity(path,self.root())?!=*identity{return Err(invalid("owned parity directory changed identity"))}}
  for row in &self.frozen{if self.outputs.iter().any(|output|output.path==row.path){continue}work.checkpoint()?;if digest(&row.path,work)?!=(row.stamp.clone(),row.content){return Err(invalid("oracle changed a copied input outside its fixed output slots"))}}
  for output in &self.outputs{if output.open{continue}match &output.state{Some(expected)=>if &digest(&output.path,work)?!=expected{return Err(invalid("enrolled oracle output changed after close"))},None=>match std::fs::symlink_metadata(&output.path){Err(actual)if actual.kind()==io::ErrorKind::NotFound=>(),Err(actual)=>return Err(actual),Ok(_)=>return Err(invalid("absent oracle output appeared after close"))}}}Ok(())
 }
 pub(crate) fn with_output_bytes<T>(&self,id:OutputId,work:&dyn SourceArenaWork,visit:&mut dyn FnMut(&[u8])->io::Result<T>)->io::Result<T>{
  if id.root!=self.sources.identity{return Err(invalid("oracle output ID belongs to another scratch owner"))}let row=self.outputs.get(id.index).ok_or_else(||invalid("oracle output ID is outside its actual owner"))?;
  if row.open{return Err(invalid("oracle output must be closed and enrolled before comparison"))}let(stamp,hash)=row.state.as_ref().ok_or_else(||io::Error::from(io::ErrorKind::NotFound))?;
  self.current(work)?;let data=crate::native_fix_physical::read(&row.path,stamp,work)?;if hash_bytes(&data.bytes,work)?!=*hash{return Err(invalid("oracle output differs from enrolled exact contents"))}let result=visit(&data.bytes)?;self.current(work)?;Ok(result)
 }
 pub(crate) fn remove(&mut self)->io::Result<()>{
  // The SAME existing physical cleanup verifies owned identities and never
  // removes an unregistered sibling or unknown replacement. Guards were paid
  // before the original writes; cleanup does not acquire a new resource grant.
  self.sources.remove_unadmitted()
 }
}
fn ordinary_output(metadata:&std::fs::Metadata)->io::Result<()>{
 if !metadata.is_file()||metadata.file_type().is_symlink(){return Err(invalid("oracle fixed output is not an ordinary file"))}
 #[cfg(windows)]{use std::os::windows::fs::MetadataExt;if metadata.file_attributes()&0x400!=0{return Err(invalid("oracle fixed output is a reparse point"))}}
 Ok(())
}
fn hash_bytes(bytes:&[u8],work:&dyn SourceArenaWork)->io::Result<u128>{let _credit=work.reserve(size_of::<xxhash_rust::xxh3::Xxh3>())?;let mut hash=xxhash_rust::xxh3::Xxh3::new();for chunk in bytes.chunks(8192){work.checkpoint()?;hash.update(chunk);}Ok(hash.digest128())}
fn digest(path:&Path,work:&dyn SourceArenaWork)->io::Result<(Stamp,u128)>{
 work.checkpoint()?;let _credit=work.reserve(8192+size_of::<xxhash_rust::xxh3::Xxh3>())?;ordinary_output(&std::fs::symlink_metadata(path)?)?;let mut file=std::fs::File::open(path)?;ordinary_output(&file.metadata()?)?;
 let stamp=crate::input_snapshot::stamp_handle(&file)?;let mut hash=xxhash_rust::xxh3::Xxh3::new();let mut bytes=[0u8;8192];let mut size=0u64;
 loop{work.checkpoint()?;let count=file.read(&mut bytes)?;if count==0{break}size=size.checked_add(count as u64).ok_or_else(oom)?;hash.update(&bytes[..count]);}
 ordinary_output(&std::fs::symlink_metadata(path)?)?;if size!=stamp.size||crate::input_snapshot::stamp_handle(&file)?!=stamp||crate::input_snapshot::FileSystemInputs.stamp(path)?!=stamp{return Err(invalid("oracle scratch file changed during closed digest"))}Ok((stamp,hash.digest128()))
}

#[cfg(test)]mod controls{
 use super::*;
 fn context(run:impl FnOnce()->Result<(),Box<dyn std::error::Error>>){super::super::with_full_registry_check_context(crate::request::BuildCommand::PrepareQuery,Some(120),run).unwrap()}
 #[test]fn copied_sources_are_bytes_exact_and_never_rewrite_the_original(){context(||{
  let cache=crate::test_scratch::dir("parity-owned-bytes");let host=crate::runner_host::BuildHost::default();let work=host.source_arena_work();
  let original=crate::test_scratch::dir("parity-untouched-original");let before=b"/datum/probe\r\n    var/title = \"\xc3\xa9\"\r\n";std::fs::write(original.join("probe.dm"),before)?;
  let mut sandbox=Sandbox::new(&cache,work)?;sandbox.put("code/probe.dm",before,work)?;
  assert_eq!(std::fs::read(sandbox.root().join("code/probe.dm"))?,before);sandbox.current(work)?;sandbox.remove()?;
  assert_eq!(std::fs::read(original.join("probe.dm"))?,before);Ok(())
 })}
 #[test]fn absent_output_owns_only_parents_until_oracle_creates_and_closes_it(){context(||{
  let cache=crate::test_scratch::dir("parity-absent-output");let host=crate::runner_host::BuildHost::default();let work=host.source_arena_work();let mut sandbox=Sandbox::new(&cache,work)?;
  let id=sandbox.output("tools/analyze/fixtures/probe/expected.txt",None,work)?;let path=sandbox.root().join("tools/analyze/fixtures/probe/expected.txt");
  assert!(!path.exists(),"declared absent slot must never gain a placeholder");std::fs::write(&path,b"real oracle output\r\n")?;
  sandbox.enroll_outputs(work)?;sandbox.with_output_bytes(id,work,&mut|bytes|{assert_eq!(bytes,b"real oracle output\r\n");Ok(())})?;sandbox.remove()?;assert!(!path.exists());Ok(())
 })}
 #[test]fn only_fixed_slots_allow_mutation_and_closed_outputs_cannot_change_again(){context(||{
  let cache=crate::test_scratch::dir("parity-fixed-mutations");let host=crate::runner_host::BuildHost::default();let work=host.source_arena_work();let mut sandbox=Sandbox::new(&cache,work)?;
  sandbox.put("code/probe.dm",b"original\n",work)?;let id=sandbox.output("tools/ci/probe_baseline.txt",Some(b"old\n"),work)?;
  std::fs::write(sandbox.root().join("tools/ci/probe_baseline.txt"),b"new\n")?;sandbox.enroll_outputs(work)?;sandbox.with_output_bytes(id,work,&mut|bytes|{assert_eq!(bytes,b"new\n");Ok(())})?;
  std::fs::write(sandbox.root().join("tools/ci/probe_baseline.txt"),b"after-close\n")?;assert!(sandbox.current(work).is_err());
  // Cleanup still owns exact identities; it does not write source bytes back.
  sandbox.remove()?;Ok(())
 })}
 #[test]fn unregistered_source_change_and_foreign_output_id_are_refused(){context(||{
  let cache=crate::test_scratch::dir("parity-source-tamper");let host=crate::runner_host::BuildHost::default();let work=host.source_arena_work();let mut first=Sandbox::new(&cache,work)?;let mut second=Sandbox::new(&cache,work)?;
  first.put("code/probe.dm",b"old",work)?;std::fs::write(first.root().join("code/probe.dm"),b"new")?;assert!(first.current(work).is_err());
  let id=second.output("expected.txt",None,work)?;second.enroll_outputs(work)?;assert!(first.with_output_bytes(id,work,&mut|_|Ok(())).is_err());first.remove()?;second.remove()?;Ok(())
 })}
 #[test]fn failed_oracle_can_enroll_partial_fixed_output_without_false_success_or_restoration(){context(||{
  let cache=crate::test_scratch::dir("parity-partial-oracle");let host=crate::runner_host::BuildHost::default();let work=host.source_arena_work();let mut sandbox=Sandbox::new(&cache,work)?;
  let _=sandbox.output("expected.txt",None,work)?;std::fs::write(sandbox.root().join("expected.txt"),b"partial")?;
  let first=io::Error::from_raw_os_error(1450);let cleanup=sandbox.enroll_outputs(work).and_then(|()|sandbox.remove());assert!(cleanup.is_ok());assert_eq!(first.raw_os_error(),Some(1450));Ok(())
 })}
 #[test]fn unknown_output_is_not_imported_or_deleted(){context(||{
  let cache=crate::test_scratch::dir("parity-unknown-output");let host=crate::runner_host::BuildHost::default();let work=host.source_arena_work();let mut sandbox=Sandbox::new(&cache,work)?;
  sandbox.put("code/probe.dm",b"old",work)?;let unknown=sandbox.root().join("unknown.txt");std::fs::write(&unknown,b"not ours")?;assert!(sandbox.remove().is_err());assert_eq!(std::fs::read(&unknown)?,b"not ours");std::fs::remove_file(unknown)?;sandbox.remove()?;Ok(())
 })}
}
