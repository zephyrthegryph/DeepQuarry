//! One authenticated authored-file IN-PLACE write, matching legacy open/truncate
//! semantics. No rename, atomic replacement, rollback, OS-CAS or metadata copy.
use crate::input_snapshot::{FileSystemInputs,SnapshotProvider,Stamp};
use dm_preprocess::source_arena_credit::SourceArenaWork;
use std::{error::Error,fmt,fs::{self,File,OpenOptions},io::{self,Read,Seek,SeekFrom,Write},path::{Component,Path}};
fn invalid(s:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,s)}
#[derive(Debug)]pub(crate) struct MutationFailure{pub primary:Box<dyn Error>,pub may_have_changed:bool}
impl fmt::Display for MutationFailure{fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{write!(f,"authored in-place write may_have_changed={}: {}",self.may_have_changed,self.primary)}}
impl Error for MutationFailure{fn source(&self)->Option<&(dyn Error+'static)>{Some(self.primary.as_ref())}}
#[derive(Debug)]pub(crate) struct Committed{pub stamp:Stamp}
fn ordinary(root:&Path,path:&Path)->io::Result<()>{
 let relative=path.strip_prefix(root).map_err(|_|invalid("authored path escapes root"))?;
 if relative.components().any(|p|!matches!(p,Component::Normal(_))){return Err(invalid("authored path is not ordinary"))}
 let mut cursor=root.to_owned();
 for part in std::iter::once(None).chain(relative.components().map(Some)){
  if let Some(part)=part{cursor.push(part.as_os_str())}let m=fs::symlink_metadata(&cursor)?;
  if m.file_type().is_symlink(){return Err(invalid("authored path has linked ancestor"))}
  #[cfg(windows)]{use std::os::windows::fs::MetadataExt;if m.file_attributes()&0x400!=0{return Err(invalid("authored path has reparse ancestor"))}}
  if cursor!=path&&!m.is_dir(){return Err(invalid("authored ancestor is not directory"))}
 }
 if !fs::symlink_metadata(path)?.is_file(){return Err(invalid("authored target is not regular file"))}Ok(())
}
fn isolated(root:&Path,path:&Path,stamp:&Stamp)->io::Result<()>{ordinary(root,path)?;if crate::input_snapshot::isolated_output_stamp(path)?.as_ref()!=Some(stamp){return Err(io::Error::new(io::ErrorKind::Unsupported,"authored write requires captured writable single-link identity"))}Ok(())}
fn verify(file:&mut File,expected:&[u8],work:&dyn SourceArenaWork)->io::Result<()>{
 file.seek(SeekFrom::Start(0))?;let mut scratch=[0u8;8192];for chunk in expected.chunks(8192){work.checkpoint()?;file.read_exact(&mut scratch[..chunk.len()])?;if &scratch[..chunk.len()]!=chunk{return Err(invalid("authored bytes differ from exact physical preimage"))}}
 work.checkpoint()?;let mut extra=[0];if file.read(&mut extra)?!=0{return Err(invalid("authored input has extra bytes"))}Ok(())
}
pub(crate) fn commit(root:&Path,relative:&str,captured:&Stamp,preimage:&[u8],output:&[u8],work:&dyn SourceArenaWork,current:&mut impl FnMut()->Result<(),Box<dyn Error>>)->Result<Committed,MutationFailure>{
 commit_using(root,relative,captured,preimage,output,work,current,&mut |_|Ok(()))
}
#[derive(Clone,Copy)]pub(crate) enum Event{AfterTruncate,BeforeWrite}
pub(crate) fn commit_using(root:&Path,relative:&str,captured:&Stamp,preimage:&[u8],output:&[u8],work:&dyn SourceArenaWork,current:&mut impl FnMut()->Result<(),Box<dyn Error>>,hook:&mut impl FnMut(Event)->io::Result<()>)->Result<Committed,MutationFailure>{
 let mut changed=false;let pending=(||->Result<Committed,Box<dyn Error>>{
  work.checkpoint()?;let rel=Path::new(relative);if !root.is_absolute()||relative.is_empty()||relative.contains(['\\',':'])||rel.components().any(|p|!matches!(p,Component::Normal(_)))||rel.extension()!=Some(std::ffi::OsStr::new("dm")){return Err(invalid("authored write requires absolute root and relative DM path").into())}
  if captured.file_id.is_none()||captured.size!=preimage.len()as u64{return Err(invalid("authored original identity is incomplete").into())}
  let width=root.as_os_str().len().checked_add(relative.len()).ok_or_else(||invalid("authored path width overflow"))?;
  let _path_credit=work.reserve(width.checked_mul(64).and_then(|n|n.checked_add(32768)).ok_or_else(||invalid("authored path funding overflow"))?)?;
  let target=root.join(rel);let parent=target.parent().ok_or_else(||invalid("authored parent absent"))?;
  let _guard_credit=work.reserve(crate::frozen_inputs::generation_publication_guard_charge(parent,root)?)?;
  let _lease=crate::publish::generation_destination_lease()?;
  // In-place mutation creates/removes no directory entry. Keep the existing
  // strict ancestor guard throughout; no staging child/relaxed guard is needed.
  let _guard=crate::frozen_inputs::generation_ancestor_guard(parent,root)?;
  current()?;isolated(root,&target,captured)?;
  let mut file=OpenOptions::new().read(true).write(true).open(&target)?;
  if crate::input_snapshot::stamp_handle(&file)?!=*captured{return Err(invalid("authored identity changed before writable open").into())}
  verify(&mut file,preimage,work)?;current()?;verify(&mut file,preimage,work)?;isolated(root,&target,captured)?;
  if crate::input_snapshot::stamp_handle(&file)?!=*captured{return Err(invalid("authored identity changed before truncate").into())}
  work.checkpoint()?;
  // Conservatively mark BEFORE truncate: an error can follow partial OS work.
  // The caller must retire and reprepare even if this syscall or a write fails.
  changed=true;dm_profile::request_mark("authored.fix.truncate_attempt");file.set_len(0)?;hook(Event::AfterTruncate)?;file.seek(SeekFrom::Start(0))?;
  for chunk in output.chunks(8192){work.checkpoint()?;hook(Event::BeforeWrite)?;file.write_all(chunk)?;}file.flush()?;dm_profile::request_mark("authored.fix.writes_flushed");
  verify(&mut file,output,work)?;let stamp=crate::input_snapshot::stamp_handle(&file)?;
  if stamp.file_id!=captured.file_id||stamp.size!=output.len()as u64||FileSystemInputs.stamp(&target)?!=stamp{return Err(invalid("authored output path changed during in-place write").into())}
  Ok(Committed{stamp})
 })();pending.map_err(|primary|MutationFailure{primary,may_have_changed:changed})
}

#[cfg(test)]mod controls{
 use super::*;
 fn fixture(label:&str)->(std::path::PathBuf,std::path::PathBuf,Stamp,Vec<u8>){let root=crate::test_scratch::dir(label);let path=root.join("source.dm");let bytes=b"/obj/box\r\n    var/list/items\r\n".to_vec();fs::write(&path,&bytes).unwrap();let stamp=FileSystemInputs.stamp(&path).unwrap();(root,path,stamp,bytes)}
 #[test]fn actual_in_place_authored_write_keeps_same_identity_and_crlf_without_replacement(){
  let(root,path,stamp,before)=fixture("native-inplace-identity");let work=crate::query_db::QueryDb::default();let after=b"/obj/box\r\n    var/list/items // changed\r\n";
  let result=commit(&root,"source.dm",&stamp,&before,after,&work,&mut||Ok(())).unwrap();assert_eq!(fs::read(&path).unwrap(),after);assert_eq!(result.stamp.file_id,stamp.file_id);assert_eq!(FileSystemInputs.stamp(&path).unwrap(),result.stamp);assert_eq!(fs::read_dir(&root).unwrap().count(),1,"no staging entry or replacement");
 }
 #[test]fn actual_in_place_first_freshness_io_never_truncates(){
  let(root,path,stamp,before)=fixture("native-inplace-first-io");let work=crate::query_db::QueryDb::default();let error=commit(&root,"source.dm",&stamp,&before,b"after",&work,&mut||Err(Box::new(io::Error::from_raw_os_error(1450)))).err().unwrap();assert!(!error.may_have_changed);assert_eq!(error.primary.downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(1450));assert_eq!(fs::read(&path).unwrap(),before);
 }
 #[test]fn actual_in_place_rechecks_same_stamp_bytes_after_final_freshness_callback(){
  let(root,path,stamp,before)=fixture("native-inplace-same-stamp");let work=crate::query_db::QueryDb::default();let time=fs::metadata(&path).unwrap().modified().unwrap();let mut changed=before.clone();changed[1]=b'x';let mut calls=0;
  let error=commit(&root,"source.dm",&stamp,&before,b"after",&work,&mut||{calls+=1;if calls==2{fs::write(&path,&changed)?;File::options().write(true).open(&path)?.set_times(fs::FileTimes::new().set_modified(time))?;assert_eq!(FileSystemInputs.stamp(&path)?,stamp)}Ok(())}).err().unwrap();assert!(!error.may_have_changed);assert_eq!(error.primary.downcast_ref::<io::Error>().unwrap().kind(),io::ErrorKind::InvalidData);assert_eq!(fs::read(&path).unwrap(),changed,"external same-stamp content is never overwritten");
 }
 #[test]fn actual_in_place_io_after_truncate_reports_possible_mutation_and_never_rolls_back(){
  let(root,path,stamp,before)=fixture("native-inplace-truncate-io");let work=crate::query_db::QueryDb::default();let error=commit_using(&root,"source.dm",&stamp,&before,b"after",&work,&mut||Ok(()),&mut|event|if matches!(event,Event::AfterTruncate){Err(io::Error::from_raw_os_error(1450))}else{Ok(())}).err().unwrap();assert!(error.may_have_changed);assert_eq!(error.primary.downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(1450));assert!(fs::read(&path).unwrap().is_empty());assert_eq!(FileSystemInputs.stamp(&path).unwrap().file_id,stamp.file_id);
 }
 #[test]fn actual_in_place_partial_write_first_io_keeps_actual_prefix_and_no_rollback(){
  let(root,path,stamp,before)=fixture("native-inplace-partial-io");let work=crate::query_db::QueryDb::default();let after=vec![b'a';16385];let mut writes=0;let error=commit_using(&root,"source.dm",&stamp,&before,&after,&work,&mut||Ok(()),&mut|event|{if matches!(event,Event::BeforeWrite){writes+=1;if writes==2{return Err(io::Error::from_raw_os_error(1450))}}Ok(())}).err().unwrap();assert!(error.may_have_changed);assert_eq!(error.primary.downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(1450));assert_eq!(fs::read(&path).unwrap(),after[..8192]);
 }
 #[test]fn actual_in_place_hardlink_and_linked_path_refuse_before_any_write(){
  let(root,path,stamp,before)=fixture("native-inplace-hardlink");let alias=root.join("alias.dm");fs::hard_link(&path,&alias).unwrap();let work=crate::query_db::QueryDb::default();let error=commit(&root,"source.dm",&stamp,&before,b"after",&work,&mut||Ok(())).err().unwrap();assert!(!error.may_have_changed);assert_eq!(error.primary.downcast_ref::<io::Error>().unwrap().kind(),io::ErrorKind::Unsupported);assert_eq!(fs::read(&path).unwrap(),before);assert_eq!(fs::read(&alias).unwrap(),before);assert!(commit(&root,"../source.dm",&stamp,&before,b"after",&work,&mut||panic!("escape cannot reach freshness")).is_err());
 }
 #[cfg(windows)]#[test]fn actual_in_place_write_preserves_existing_ntfs_alternate_stream_by_identity(){
  let(root,path,stamp,before)=fixture("native-inplace-ads");let stream=std::path::PathBuf::from(format!("{}:fix-control",path.display()));fs::write(&stream,b"preserve stream").unwrap();let work=crate::query_db::QueryDb::default();let result=commit(&root,"source.dm",&stamp,&before,b"after",&work,&mut||Ok(())).unwrap();assert_eq!(result.stamp.file_id,stamp.file_id);assert_eq!(fs::read(&stream).unwrap(),b"preserve stream");
 }
}
