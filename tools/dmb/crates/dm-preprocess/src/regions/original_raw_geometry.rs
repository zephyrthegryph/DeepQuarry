//! Sparse decoded coordinate evidence on the SAME raw input/mapping owner.
//! Authenticated construction borrows actual raw bytes + decoded lease backing;
//! retained evidence keeps only weak acquisition identity, not source payload.
//! No source/current-model/EOF grant follows from this coordinate DATA.
use crate::{SourceProvider,SourceAcquisitionLease,SourceAcquisitionIdentity,source_decode::{DecodedPointException,DecodedPointGeometry,visit_decoded_point_exceptions},macro_expansion::OriginalMacroRows as Rows};
use dm_syntax::{SettingAdmission,SettingRootLease};use std::io;
pub(super) struct OriginalRawGeometry{exceptions:Rows<DecodedPointException>,identity:SourceAcquisitionIdentity,shape:DecodedPointGeometry,domain:SettingRootLease}
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
impl OriginalRawGeometry{
 pub(super) fn from_acquired_using(provider:&dyn SourceProvider,lease:&SourceAcquisitionLease,a:&SettingAdmission<'_>)->io::Result<Self>{
  poll(a)?;let domain=a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?;let mut exceptions=Rows::new(a)?;
  let raw=provider.original_source_bytes(lease)?.ok_or_else(||io::Error::new(io::ErrorKind::NotConnected,"actual raw geometry source loan is unissued"))?;
  let shape=visit_decoded_point_exceptions(raw,lease.source_text().as_str(),&mut||poll(a),&mut|row|exceptions.push(row,a))?;
  Ok(Self{exceptions,identity:lease.identity(),shape,domain})
 }
 /// Raw byte_column stays with the raw point. Only source_offset is translated
 /// into the actual decoded backing; UTF8/BOM interior bytes fail closed.
 pub(super) fn decoded_point_using(&self,lease:&SourceAcquisitionLease,raw_point:usize,a:&SettingAdmission<'_>)->io::Result<usize>{
  poll(a)?;if !a.matches_lease_domain(&self.domain)||!self.identity.matches(lease){return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw point geometry belongs to another actual source binding or admission"))}
  if raw_point>self.shape.original_len()||lease.source_text().len()!=self.shape.decoded_len(){return Err(io::ErrorKind::InvalidInput.into())}
  self.shape.decoded_point(lease.source_text().as_str(),self.exceptions.as_slice(),raw_point).ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual raw point is not representable at a decoded source boundary"))
 }
 pub(super) fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
  self.exceptions.visit_allocation(|p,n|visit(p,n,n));self.domain.visit_counter_storage(|p,n|visit(p,n,n));
  self.identity.visit_storage(|storage|{if let crate::source_acquisition::AcquisitionStorage::Object{address,bytes}=storage{visit(address,bytes,bytes)}});
 }
}

#[cfg(test)]mod tests{
 use super::*;use std::{path::Path,sync::{Arc,atomic::{AtomicUsize,Ordering}}};
 struct File{raw:Vec<u8>,lease:SourceAcquisitionLease}
 impl File{fn new(raw:&[u8])->Self{Self{raw:raw.to_vec(),lease:SourceAcquisitionLease::from_raw_original_bytes(raw.to_vec(),123u64)}}}
 impl SourceProvider for File{fn read(&self,_:&Path)->Result<String,String>{panic!("raw geometry never prepares/reads another source")}fn original_source_bytes<'a>(&'a self,lease:&'a SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{if !lease.same_original_acquisition(&self.lease){return Err(io::ErrorKind::InvalidInput.into())}Ok(Some(&self.raw))}}
 #[test]fn actual_acquired_geometry_preserves_raw_columns_while_decoded_offsets_follow_bom_cp1252_latin1_and_utf8(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let file=File::new(b"\xef\xbb\xbfA\x80\xc3\xa9\xffZ\n");let geometry=OriginalRawGeometry::from_acquired_using(&file,&file.lease,&a).unwrap();
  for(raw,decoded)in [(3,0),(4,1),(5,4),(7,6),(8,8),(9,9),(10,10)]{assert_eq!(geometry.decoded_point_using(&file.lease,raw,&a).unwrap(),decoded)}
  for raw in [1,2,6]{assert_eq!(geometry.decoded_point_using(&file.lease,raw,&a).unwrap_err().kind(),io::ErrorKind::Unsupported)}
  let mut points=super::super::original_raw_points::OriginalRawPointIndex::new(&file.raw,&a).unwrap();let point=points.at(&file.raw,7,&a).unwrap();assert_eq!((point.line,point.column),(1,5));assert_eq!(geometry.decoded_point_using(&file.lease,7,&a).unwrap(),6);drop((points,geometry));assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn actual_geometry_rejects_equal_text_foreign_acquisition_and_resource_domain_without_retaining_source_payload(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let file=File::new(b"plain");let geometry=OriginalRawGeometry::from_acquired_using(&file,&file.lease,&a).unwrap();let foreign=File::new(b"plain");assert_eq!(geometry.decoded_point_using(&foreign.lease,0,&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);let other=Arc::new(AtomicUsize::new(0));let other_a=SettingAdmission::new(&other,1<<20,&||Ok(()));assert_eq!(geometry.decoded_point_using(&file.lease,0,&other_a).unwrap_err().kind(),io::ErrorKind::InvalidInput);drop(geometry);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn actual_geometry_partial_rows_drop_on_first_operational_failure_and_quota_before_publication(){
  let file=File::new(b"\x80\xff");let used=Arc::new(AtomicUsize::new(0));let fault=||Err(io::Error::from_raw_os_error(1450));let a=SettingAdmission::new(&used,1<<20,&fault);assert_eq!(OriginalRawGeometry::from_acquired_using(&file,&file.lease,&a).err().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),0);let small=SettingAdmission::new(&used,1,&||Ok(()));assert_eq!(OriginalRawGeometry::from_acquired_using(&file,&file.lease,&small).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),0);
 }
}
