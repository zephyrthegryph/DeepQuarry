//! Funded use of the EXISTING lexical path/display kernels. No IO, new path
//! policy, source authority, parser, cache or independent budget is introduced.
use std::{io,path::{Path,PathBuf},mem::size_of};
use crate::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
fn oom()->io::Error{io::ErrorKind::OutOfMemory.into()}
fn add(a:usize,b:usize)->io::Result<usize>{a.checked_add(b).ok_or_else(oom)}
fn envelope(n:usize)->io::Result<usize>{n.checked_mul(4).ok_or_else(oom)}
fn settle(work:&dyn SourceArenaWork,credit:&mut SourceArenaCredit,paid:usize,actual:usize)->io::Result<()>{work.shrink(credit,paid.checked_sub(actual).ok_or_else(oom)?)}
fn path_buffer(n:usize,work:&dyn SourceArenaWork,credit:&mut SourceArenaCredit)->io::Result<(PathBuf,usize)>{
 work.checkpoint()?;let paid=envelope(n)?;work.grow(credit,paid)?;
 let mut out=PathBuf::new();out.try_reserve_exact(n).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
 if out.capacity()>paid{return Err(oom())}Ok((out,paid))
}
fn string_buffer(n:usize,work:&dyn SourceArenaWork,credit:&mut SourceArenaCredit)->io::Result<(String,usize)>{
 work.checkpoint()?;let paid=envelope(n)?;work.grow(credit,paid)?;
 let mut out=String::new();out.try_reserve_exact(n).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
 if out.capacity()>paid{return Err(oom())}Ok((out,paid))
}
pub fn copy_path_into_credit(path:&Path,work:&dyn SourceArenaWork,credit:&mut SourceArenaCredit)->io::Result<PathBuf>{
 let(mut out,paid)=path_buffer(path.as_os_str().len(),work,credit)?;out.push(path);
 if out.capacity()>paid{return Err(oom())}settle(work,credit,paid,out.capacity())?;Ok(out)
}
pub fn copy_string_into_credit(text:&str,work:&dyn SourceArenaWork,credit:&mut SourceArenaCredit)->io::Result<String>{
 let(mut out,paid)=string_buffer(text.len(),work,credit)?;out.push_str(text);
 if out.capacity()>paid{return Err(oom())}settle(work,credit,paid,out.capacity())?;Ok(out)
}
/// Payload precedes its one SAME-operation resource credit on destruction.
pub struct FundedPath{path:PathBuf,_credit:SourceArenaCredit}
impl FundedPath{pub fn path(&self)->&Path{&self.path}}
pub fn joined_path_into_credit(root:&Path,child:&str,work:&dyn SourceArenaWork,credit:&mut SourceArenaCredit)->io::Result<PathBuf>{
 let n=add(add(root.as_os_str().len(),child.len())?,1)?;let(mut path,paid)=path_buffer(n,work,credit)?;path.push(root);path.push(child);
 if path.capacity()>paid{return Err(oom())}settle(work,credit,paid,path.capacity())?;Ok(path)
}
pub fn joined_path_using(root:&Path,child:&str,work:&dyn SourceArenaWork)->io::Result<FundedPath>{
 let mut credit=work.reserve(0)?;let path=joined_path_into_credit(root,child,work,&mut credit)?;Ok(FundedPath{path,_credit:credit})
}
pub fn canonical_path_using(path:&Path,work:&dyn SourceArenaWork)->io::Result<FundedPath>{
 let mut credit=work.reserve(0)?;let(mut actual,paid)=path_buffer(path.as_os_str().len(),work,&mut credit)?;
 super::canonical_path_into(path,&mut actual);if actual.capacity()>paid{return Err(oom())}settle(work,&mut credit,paid,actual.capacity())?;
 Ok(FundedPath{path:actual,_credit:credit})
}
fn comparison_path(path:&Path,work:&dyn SourceArenaWork)->io::Result<FundedPath>{
 let FundedPath{path:actual,_credit:credit}=canonical_path_using(path,work)?;
 if super::path_prefix::ordinary_verbatim_drive(&actual).is_none(){return Ok(FundedPath{path:actual,_credit:credit})}
 let mut replacement_credit=work.reserve(0)?;let(mut replacement,paid)=path_buffer(actual.as_os_str().len(),work,&mut replacement_credit)?;
 super::path_prefix::equivalent_prefix_into(&actual,&mut replacement);if replacement.capacity()>paid{return Err(oom())}settle(work,&mut replacement_credit,paid,replacement.capacity())?;
 drop(actual);drop(credit);Ok(FundedPath{path:replacement,_credit:replacement_credit})
}
pub fn relative_slash_into_credit(path:&Path,root:&Path,work:&dyn SourceArenaWork,credit:&mut SourceArenaCredit)->io::Result<Option<String>>{
 let path=comparison_path(path,work)?;let root=comparison_path(root,work)?;
 match path.path.strip_prefix(&root.path){Ok(relative)=>slash_path_into_credit(relative,work,credit).map(Some),Err(_)=>Ok(None)}
}
pub fn relative_slash_only_into_credit(path:&Path,root:&Path,work:&dyn SourceArenaWork,credit:&mut SourceArenaCredit)->io::Result<Option<String>>{
 let path=comparison_path(path,work)?;let root=comparison_path(root,work)?;
 match path.path.strip_prefix(&root.path){Ok(relative)=>slash_path_with_fold(relative,work,credit,false).map(Some),Err(_)=>Ok(None)}
}
pub fn slash_path_into_credit(path:&Path,work:&dyn SourceArenaWork,credit:&mut SourceArenaCredit)->io::Result<String>{slash_path_with_fold(path,work,credit,true)}
fn slash_path_with_fold(path:&Path,work:&dyn SourceArenaWork,credit:&mut SourceArenaCredit,fold:bool)->io::Result<String>{
 work.checkpoint()?;
 // UTF8 replacement expands at most one invalid input byte into three bytes;
 // the standard String allocator's established four-capacity envelope is
 // separate from that encoding bound. Valid UTF8 borrows without a copy.
 let mut lossy_credit=work.reserve(0)?;
 let lossy_bound=if path.to_str().is_some(){0}else{envelope(path.as_os_str().len().checked_mul(3).ok_or_else(oom)?)?};
 work.grow(&mut lossy_credit,lossy_bound)?;let lossy=path.to_string_lossy();
 let actual=match &lossy{std::borrow::Cow::Borrowed(_)=>0,std::borrow::Cow::Owned(s)=>s.capacity()};settle(work,&mut lossy_credit,lossy_bound,actual)?;
 if !fold{
  let(mut out,paid)=string_buffer(lossy.len(),work,credit)?;for ch in lossy.chars(){work.checkpoint()?;out.push(if ch=='\\'{'/'}else{ch});}
  if out.capacity()>paid{return Err(oom())}settle(work,credit,paid,out.capacity())?;drop(lossy);drop(lossy_credit);work.checkpoint()?;return Ok(out)
 }
 let mut slash_credit=work.reserve(0)?;let(mut slash,paid)=string_buffer(lossy.len(),work,&mut slash_credit)?;
 for ch in lossy.chars(){work.checkpoint()?;slash.push(if ch=='\\'{'/'}else{ch});}if slash.capacity()>paid{return Err(oom())}settle(work,&mut slash_credit,paid,slash.capacity())?;
 let count=if slash.contains("/."){slash.bytes().filter(|b|*b==b'/').count().checked_add(1).ok_or_else(oom)?}else{0};
 let mut parts_credit=work.reserve(0)?;let paid=envelope(count.checked_mul(size_of::<&str>()).ok_or_else(oom)?)?;work.grow(&mut parts_credit,paid)?;
 let mut parts=Vec::new();parts.try_reserve_exact(count).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;settle(work,&mut parts_credit,paid,parts.capacity().checked_mul(size_of::<&str>()).ok_or_else(oom)?)?;
 let(mut out,paid)=string_buffer(slash.len(),work,credit)?;
 super::normalize_slash_dots_into(&slash,&mut parts,&mut out);if out.capacity()>paid{return Err(oom())}settle(work,credit,paid,out.capacity())?;
 // Drop actual buffers before retiring their resource credits.
 drop(parts);drop(parts_credit);drop(slash);drop(slash_credit);drop(lossy);drop(lossy_credit);work.checkpoint()?;Ok(out)
}

#[cfg(test)]mod controls{
 use super::*;use crate::source_arena_credit::SourceArenaCreditOwner;use std::{any::Any,sync::{Arc,atomic::{AtomicUsize,Ordering}}};
 struct Credit{bytes:AtomicUsize,live:Arc<AtomicUsize>}
 impl Drop for Credit{fn drop(&mut self){self.live.fetch_sub(self.bytes.load(Ordering::Acquire),Ordering::AcqRel);}}
 impl SourceArenaCreditOwner for Credit{fn as_any(&self)->&dyn Any{self}fn reserved_bytes(&self)->usize{self.bytes.load(Ordering::Acquire)}fn visit_storage(&self,_:&mut dyn FnMut(usize,usize)){}}
 struct Work{live:Arc<AtomicUsize>,limit:usize,calls:AtomicUsize,stop:usize}
 impl Work{fn new(limit:usize)->Self{Self{live:Arc::new(AtomicUsize::new(0)),limit,calls:AtomicUsize::new(0),stop:usize::MAX}}fn charge(&self,n:usize)->io::Result<()>{self.live.fetch_update(Ordering::AcqRel,Ordering::Acquire,|v|v.checked_add(n).filter(|n|*n<=self.limit)).map(|_|()).map_err(|_|oom())}}
 impl SourceArenaWork for Work{
  fn checkpoint(&self)->io::Result<()>{if self.calls.fetch_add(1,Ordering::AcqRel)+1==self.stop{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}}
  fn reserve(&self,n:usize)->io::Result<SourceArenaCredit>{self.checkpoint()?;self.charge(n)?;Ok(SourceArenaCredit::from_resource_owner(Arc::new(Credit{bytes:AtomicUsize::new(n),live:Arc::clone(&self.live)})))}
  fn grow(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{self.checkpoint()?;let owner=c.owner().as_any().downcast_ref::<Credit>().ok_or(io::ErrorKind::InvalidInput)?;if !Arc::ptr_eq(&owner.live,&self.live){return Err(io::ErrorKind::InvalidInput.into())}self.charge(n)?;owner.bytes.fetch_add(n,Ordering::AcqRel);Ok(())}
  fn shrink(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{let owner=c.owner().as_any().downcast_ref::<Credit>().ok_or(io::ErrorKind::InvalidInput)?;if !Arc::ptr_eq(&owner.live,&self.live){return Err(io::ErrorKind::InvalidInput.into())}owner.bytes.fetch_update(Ordering::AcqRel,Ordering::Acquire,|v|v.checked_sub(n)).map_err(|_|io::ErrorKind::InvalidInput)?;self.live.fetch_sub(n,Ordering::AcqRel);Ok(())}
 }
 #[test]fn funded_paths_match_same_legacy_component_and_slash_kernels_and_settle_actual_capacity(){
  let work=Work::new(1<<20);
  for(root,path)in [("/root","/root/a/../b.dm"),("/root/./","/root/a//b.dm"),("/root","/elsewhere/a.dm"),("relative/root","relative/root/../other"),("","../../a/./b")]{
   let(root,path)=(Path::new(root),Path::new(path));let expected=super::super::relative_filesystem_path(path,root).map(|p|{let lossy=p.to_string_lossy().replace('\\',"/");super::super::normalize_slash_dots(&lossy)});
   let mut credit=work.reserve(0).unwrap();let actual=relative_slash_into_credit(path,root,&work,&mut credit).unwrap();assert_eq!(actual,expected);assert_eq!(credit.reserved_bytes(),actual.as_ref().map_or(0,String::capacity));assert_eq!(work.live.load(Ordering::Acquire),credit.reserved_bytes(),"all normalized/root/slash scratch physically retired");drop(actual);drop(credit);assert_eq!(work.live.load(Ordering::Acquire),0);
  }
  for path in ["","a","a/../b","../../a/./b","/r/../Ã¼/long-name.dm"]{let path=Path::new(path);let actual=canonical_path_using(path,&work).unwrap();assert_eq!(actual.path(),super::super::canonical_path(path));assert_eq!(actual._credit.reserved_bytes(),actual.path.capacity());drop(actual);assert_eq!(work.live.load(Ordering::Acquire),0);}
 }
 #[test]fn funded_path_preallocation_quota_first_io_late_io_and_foreign_domain_remain_honest(){
  let work=Work::new(4);let mut credit=work.reserve(0).unwrap();assert!(copy_string_into_credit("not funded",&work,&mut credit).is_err());assert_eq!(credit.reserved_bytes(),0);drop(credit);assert_eq!(work.live.load(Ordering::Acquire),0);
  let left=Work::new(1<<20);let right=Work::new(1<<20);let mut foreign=left.reserve(0).unwrap();assert_eq!(copy_path_into_credit(Path::new("a/b"),&right,&mut foreign).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(left.live.load(Ordering::Acquire),0);assert_eq!(right.live.load(Ordering::Acquire),0);
  for stop in 1..=32{let mut work=Work::new(1<<20);let mut credit=work.reserve(0).unwrap();work.calls.store(0,Ordering::Release);work.stop=stop;let result=relative_slash_into_credit(Path::new("/r/a/../b.dm"),Path::new("/r"),&work,&mut credit);if work.calls.load(Ordering::Acquire)>=stop{assert_eq!(result.err().unwrap().raw_os_error(),Some(1450));}else{result.unwrap();}drop(credit);assert_eq!(work.live.load(Ordering::Acquire),0,"failed path work drops real scratch before grant at checkpoint {stop}");}
 }
 #[cfg(windows)]#[test]fn funded_windows_drive_unc_devices_and_unicode_keep_existing_comparison_semantics(){
  let work=Work::new(1<<20);for(root,path)in [(r"C:\root",r"\\?\C:\root\a.dm"),(r"\\?\C:\root",r"C:\root\Ã¼.dm"),(r"C:\root",r"\\?\C:\root\CON"),(r"\\server\share",r"\\server\share\a.dm")]{let(root,path)=(Path::new(root),Path::new(path));let expected=super::super::relative_filesystem_path(path,root).map(|p|p.to_string_lossy().replace('\\',"/"));let mut credit=work.reserve(0).unwrap();let actual=relative_slash_into_credit(path,root,&work,&mut credit).unwrap();assert_eq!(actual,expected);drop(actual);drop(credit);assert_eq!(work.live.load(Ordering::Acquire),0);}
 }
 #[cfg(unix)]#[test]fn funded_lossy_unix_name_uses_encoding_bound_not_generic_path_multiplier(){
  use std::os::unix::ffi::OsStrExt;let raw=std::ffi::OsStr::from_bytes(b"a/\xff/../b");let path=Path::new(raw);let work=Work::new(1<<20);let mut credit=work.reserve(0).unwrap();let actual=slash_path_into_credit(path,&work,&mut credit).unwrap();assert_eq!(actual,super::super::normalize_slash_dots(&path.to_string_lossy().replace('\\',"/")));assert_eq!(credit.reserved_bytes(),actual.capacity());drop(actual);drop(credit);assert_eq!(work.live.load(Ordering::Acquire),0);
 }
}
