//! One operation-local checked vector, not source authority or a cache.
//! Physical buffer release precedes its SAME-counter reservation's release.
use crate::{SettingAdmission,SettingRootLease};
use std::{io,mem::size_of};
pub(crate) struct Worklist<'a,'op,T>{values:Vec<T>,admission:&'a SettingAdmission<'op>,lease:SettingRootLease}
fn failure(a:&SettingAdmission<'_>,actual:io::Error)->io::Error{let kind=actual.kind();a.record_operational_error(actual);kind.into()}
impl<'a,'op,T> Worklist<'a,'op,T>{
 pub(crate) fn new(a:&'a SettingAdmission<'op>)->io::Result<Self>{
  let lease=a.reserve(size_of::<Self>())?;Ok(Self{values:Vec::new(),admission:a,lease})
 }
 fn reserve_one(&mut self)->io::Result<()>{
  self.admission.checkpoint()?;
  if self.values.len()<self.values.capacity(){return Ok(());}
  let requested=self.values.capacity().checked_mul(2).map(|n|n.max(8)).ok_or_else(||failure(self.admission,io::Error::new(io::ErrorKind::OutOfMemory,"syntax worklist capacity overflow")))?;
  let bytes=requested.checked_mul(size_of::<T>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(size_of::<Self>())).ok_or_else(||failure(self.admission,io::Error::new(io::ErrorKind::OutOfMemory,"syntax worklist storage overflow")))?;
  // SAME established native Vec coordination envelope: retain the old lease
  // over replacement, and admit FOUR requested capacities before allocation.
  let next=self.admission.reserve(bytes)?;
  self.values.try_reserve_exact(requested-self.values.len()).map_err(|actual|failure(self.admission,io::Error::new(io::ErrorKind::OutOfMemory,actual)))?;
  self.lease=next; // old backing has physically gone before its credit drops
  if self.values.capacity()>requested.saturating_mul(2){return Err(failure(self.admission,io::Error::new(io::ErrorKind::OutOfMemory,"syntax worklist allocator capacity exceeded admitted envelope")));}
  Ok(())
 }
 pub(crate) fn push(&mut self,value:T)->io::Result<()>{self.reserve_one()?;self.values.push(value);Ok(())}
 pub(crate) fn extend(&mut self,values:impl IntoIterator<Item=T>)->io::Result<()>{for value in values{self.push(value)?;}Ok(())}
 pub(crate) fn pop(&mut self)->Option<T>{self.values.pop()}
 pub(crate) fn as_slice(&self)->&[T]{&self.values}
}
