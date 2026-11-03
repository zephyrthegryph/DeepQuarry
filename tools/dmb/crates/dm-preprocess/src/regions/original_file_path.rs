//! Bounded spelling of an actual opened physical file, not source authority.
//! Paths remain independent of token invocation/replacement provenance.
use dm_syntax::{SettingAdmission,SettingRootLease};use std::{io,path::{Path,PathBuf},mem};
pub(super) struct OriginalFilePath{path:PathBuf,credit:SettingRootLease}
impl OriginalFilePath{
 pub(super) fn new(path:&Path,a:&SettingAdmission<'_>)->io::Result<Self>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
  let bound=path.as_os_str().len().checked_mul(4).and_then(|n|n.checked_add(mem::size_of::<PathBuf>()+32)).ok_or(io::ErrorKind::OutOfMemory)?;
  let credit=a.reserve(bound).map_err(|e|a.take_operational_error().unwrap_or(e))?;let mut actual=PathBuf::new();actual.try_reserve_exact(path.as_os_str().len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;actual.push(path);if actual.capacity()>bound{return Err(io::ErrorKind::OutOfMemory.into())}Ok(Self{path:actual,credit})
 }
 pub(super) fn path(&self)->&Path{&self.path}
 pub(super) fn is_admitted_by(&self,a:&SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.credit)}
}
