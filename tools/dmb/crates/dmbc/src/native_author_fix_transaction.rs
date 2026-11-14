//! One authenticated authored-file IN-PLACE write, matching legacy open/truncate
//! semantics. No rename, atomic replacement, rollback, OS-CAS or metadata copy.
use crate::input_snapshot::{FileSystemInputs,SnapshotProvider,Stamp};
use dm_preprocess::source_arena_credit::SourceArenaWork;
use std::{error::Error,fmt,fs::{self,File,OpenOptions},io::{self,Read,Seek,SeekFrom,Write},path::{Component,Path}};
fn invalid(s:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,s)}
#[derive(Debug)]pub(crate) struct MutationFailure{pub primary:Box<dyn Error>,pub may_have_changed:bool}
impl fmt::Display for MutationFailure{fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{write!(f,"authored in-place write may_have_changed={}: {}",self.may_have_changed,self.primary)}}
impl Error for MutationFailure{fn source(&self)->Option<&(dyn Error+'static)>{Some(self.primary.as_ref())}}
#[derive(Debug)]pub(crate) struct Committed{pub stamp:Stamp,transition:Transition}
/// Minted ONLY after the existing in-place writer verified exact preimage,
/// wrote/flushed/read-verified output and checked the final same-file identity.
/// This is an operation-local authored transition, never generated-output policy.
pub(crate) struct Transition{path:std::path::PathBuf,before:Stamp,before_hash:u128,after:Stamp,after_hash:u128,_credit:dm_preprocess::source_arena_credit::SourceArenaCredit}
impl std::fmt::Debug for Transition{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("AuthoredTransition").field("path",&self.path).field("before",&self.before).field("after",&self.after).finish_non_exhaustive()}}
impl Committed{pub(crate) fn into_parts(self)->(Stamp,Transition){(self.stamp,self.transition)}}
impl Transition{
 pub(crate) fn path(&self)->&Path{&self.path}
 pub(crate) fn before(&self,stamp:&Stamp,hash:u128)->bool{*stamp==self.before&&hash==self.before_hash}
 pub(crate) fn after(&self,stamp:&Stamp,hash:u128)->bool{*stamp==self.after&&hash==self.after_hash}
}
fn digest(bytes:&[u8],work:&dyn SourceArenaWork)->io::Result<u128>{let mut hash=xxhash_rust::xxh3::Xxh3::new();for chunk in bytes.chunks(8192){work.checkpoint()?;hash.update(chunk);}Ok(hash.digest128())}

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
#[derive(Clone,Copy)]pub(crate) enum Event{AfterTruncate,BeforeWrite,BeforeClosedVerification}
pub(crate) fn commit_using(root:&Path,relative:&str,captured:&Stamp,preimage:&[u8],output:&[u8],work:&dyn SourceArenaWork,current:&mut impl FnMut()->Result<(),Box<dyn Error>>,hook:&mut impl FnMut(Event)->io::Result<()>)->Result<Committed,MutationFailure>{
 let mut changed=false;let pending=(||->Result<Committed,Box<dyn Error>>{
  work.checkpoint()?;let rel=Path::new(relative);if !root.is_absolute()||relative.is_empty()||relative.contains(['\\',':'])||rel.components().any(|p|!matches!(p,Component::Normal(_)))||rel.extension()!=Some(std::ffi::OsStr::new("dm")){return Err(invalid("authored write requires absolute root and relative DM path").into())}
  if captured.file_id.is_none()||captured.size!=preimage.len()as u64{return Err(invalid("authored original identity is incomplete").into())}
  let width=root.as_os_str().len().checked_add(relative.len()).ok_or_else(||invalid("authored path width overflow"))?;
  let path_credit=work.reserve(width.checked_mul(64).and_then(|n|n.checked_add(32768)).ok_or_else(||invalid("authored path funding overflow"))?)?;
  let before_hash=digest(preimage,work)?;let after_hash=digest(output,work)?;
  let target=root.join(rel);let receipt_path=dm_preprocess::regions::canonical_path(&target);let parent=target.parent().ok_or_else(||invalid("authored parent absent"))?;
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
  // Windows finalizes the writing handle's last-write timestamp at close.
  // Keep the SAME destination lease/ancestor guard, close the writer, then
  // authenticate the final same-file bytes and stamp through a read handle.
  drop(file);hook(Event::BeforeClosedVerification)?;work.checkpoint()?;
  let mut final_read=File::open(&target)?;let stamp=crate::input_snapshot::stamp_handle(&final_read)?;verify(&mut final_read,output,work)?;
  if crate::input_snapshot::stamp_handle(&final_read)?!=stamp||stamp.file_id!=captured.file_id||stamp.size!=output.len()as u64||FileSystemInputs.stamp(&target)?!=stamp{return Err(invalid("authored closed-writer output identity or stamp changed").into())}isolated(root,&target,&stamp)?;
  Ok(Committed{stamp:stamp.clone(),transition:Transition{path:receipt_path,before:captured.clone(),before_hash,after:stamp,after_hash,_credit:path_credit}})
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

#[cfg(test)]mod transition_controls{
 use super::*;use crate::input_snapshot::InputSnapshot;
 fn capture(path:&Path,root:&Path)->InputSnapshot{let provider=FileSystemInputs;let(stamp,bytes)=provider.read(path).unwrap();let mut snapshot=InputSnapshot::new(0);snapshot.record_file(path,stamp,&bytes).unwrap();snapshot.record_folder(root,provider.list(root).unwrap()).unwrap();snapshot}
 #[test]fn actual_in_place_transition_links_only_its_exact_before_and_after_recorded_source(){
  let root=fs::canonicalize(crate::test_scratch::dir("authored-transition-records")).unwrap();let path=root.join("source.dm");let before=b"/obj/box\r\n    var/value = 1\r\n";let after=b"/obj/box\r\n    var/value = 2\r\n";fs::write(&path,before).unwrap();let initial=capture(&path,&root);let work=crate::query_db::QueryDb::default();let stamp=FileSystemInputs.stamp(&path).unwrap();let committed=commit(&root,"source.dm",&stamp,before,after,&work,&mut||Ok(())).unwrap();let(_,transition)=committed.into_parts();let final_source=capture(&path,&root);assert!(!initial.same_authored_step(&final_source,None,&work).unwrap());assert!(initial.same_authored_step(&final_source,Some(&transition),&work).unwrap());assert!(!final_source.same_authored_step(&initial,Some(&transition),&work).unwrap());assert!(!initial.same_authored_step(&initial,Some(&transition),&work).unwrap());
  fs::write(&path,b"/obj/box\r\n    var/value = 3\r\n").unwrap();let external=capture(&path,&root);assert!(!initial.same_authored_step(&external,Some(&transition),&work).unwrap());
 }
 #[test]fn actual_in_place_transition_cannot_advance_another_file_configuration_or_namespace(){
  let root=fs::canonicalize(crate::test_scratch::dir("authored-transition-foreign")).unwrap();let path=root.join("source.dm");let other=root.join("configuration.toml");fs::write(&path,b"old").unwrap();fs::write(&other,b"configuration = 1").unwrap();let provider=FileSystemInputs;let mut initial=capture(&path,&root);let(stamp,bytes)=provider.read(&other).unwrap();initial.record_file(&other,stamp,&bytes).unwrap();let work=crate::query_db::QueryDb::default();let stamp=provider.stamp(&path).unwrap();let(_,transition)=commit(&root,"source.dm",&stamp,b"old",b"new",&work,&mut||Ok(())).unwrap().into_parts();fs::write(&other,b"configuration = 2").unwrap();let mut changed=capture(&path,&root);let(stamp,bytes)=provider.read(&other).unwrap();changed.record_file(&other,stamp,&bytes).unwrap();assert!(!initial.same_authored_step(&changed,Some(&transition),&work).unwrap());fs::write(&other,b"configuration = 1").unwrap();fs::write(root.join("new.dm"),b"/obj/new").unwrap();let mut namespace=capture(&path,&root);let(stamp,bytes)=provider.read(&other).unwrap();namespace.record_file(&other,stamp,&bytes).unwrap();assert!(!initial.same_authored_step(&namespace,Some(&transition),&work).unwrap());
 }
}

#[cfg(test)]mod closed_writer_controls{use super::*;
 #[test]fn actual_committed_transition_uses_post_close_same_file_stamp_and_exact_output(){let root=fs::canonicalize(crate::test_scratch::dir("native-inplace-closed-stamp")).unwrap();let path=root.join("source.dm");let before=b"before\r\n";let after=b"after!\r\n";fs::write(&path,before).unwrap();let captured=FileSystemInputs.stamp(&path).unwrap();let work=crate::query_db::QueryDb::default();let actual=commit(&root,"source.dm",&captured,before,after,&work,&mut||Ok(())).unwrap();assert_eq!(actual.stamp,FileSystemInputs.stamp(&path).unwrap());let(stamp,transition)=actual.into_parts();assert!(transition.before(&captured,xxhash_rust::xxh3::xxh3_128(before)));assert!(transition.after(&stamp,xxhash_rust::xxh3::xxh3_128(after)));assert_eq!(stamp.file_id,captured.file_id);assert_eq!(fs::read(path).unwrap(),after);}
 #[test]fn actual_closed_verification_io_refuses_transition_and_keeps_first_error_after_real_mutation(){let root=fs::canonicalize(crate::test_scratch::dir("native-inplace-closed-first-io")).unwrap();let path=root.join("source.dm");fs::write(&path,b"before").unwrap();let captured=FileSystemInputs.stamp(&path).unwrap();let work=crate::query_db::QueryDb::default();let mut seen=0;let error=commit_using(&root,"source.dm",&captured,b"before",b"after!",&work,&mut||Ok(()),&mut|event|{if matches!(event,Event::BeforeClosedVerification){seen+=1;return Err(io::Error::from_raw_os_error(1450))}Ok(())}).err().unwrap();assert!(error.may_have_changed);assert_eq!(seen,1);assert_eq!(error.primary.downcast_ref::<io::Error>().unwrap().raw_os_error(),Some(1450));assert_eq!(fs::read(path).unwrap(),b"after!");}
}
