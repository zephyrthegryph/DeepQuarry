use super::*;use crate::SourceProvider;use std::{cell::Cell,io};
#[path="../../../../shared/test_scratch.rs"]mod scratch;
struct ActualRaw{path:PathBuf,lease:crate::SourceAcquisitionLease,calls:Cell<usize>}
impl SourceProvider for ActualRaw{
 fn initial_environment(&self)->crate::InitialEnvironment{crate::InitialEnvironment::OriginalChecker0290}
 fn read(&self,_:&Path)->Result<String,String>{panic!("raw adapter must not fallback to decoded Native read")}
 fn original_raw_source_checked(&self,path:&Path,max:usize,before:&mut dyn FnMut(usize,bool,bool)->io::Result<()>)->io::Result<Option<crate::SourceAcquisitionLease>>{assert_eq!(path,self.path);assert!(self.lease.source_text().len()<=max);self.calls.set(self.calls.get()+1);before(0,false,false)?;Ok(Some(self.lease.clone()))}
 fn original_source_bytes<'a>(&'a self,lease:&'a crate::SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{if !lease.same_binding(&self.lease){return Err(io::ErrorKind::InvalidInput.into())}Ok(Some(lease.source_text().as_bytes()))}
}
#[test]fn raw_adapter_uses_actual_input_lease_not_equal_or_different_native_prepared_text(){
 let root=scratch::dir("prepared-original-raw-adapter");std::fs::create_dir_all(&root).unwrap();let path=root.join("source.dm");let bytes=b"/proc/genuine()\n    return 1\n";std::fs::write(&path,bytes).unwrap();let raw=ActualRaw{path:path.clone(),lease:crate::SourceAcquisitionLease::from_raw_original_bytes(std::fs::read(&path).unwrap(),()),calls:Cell::new(0)};let captures=PreparedSources::from_prepared([(path.clone(),Arc::new(PreparedSource::new(Arc::from("/proc/not_the_actual_original()\n"))))]).unwrap();let provider=PreparedSourceProvider::new(&captures,&raw);assert_eq!(provider.initial_environment(),crate::InitialEnvironment::OriginalChecker0290);
 let lease=provider.original_raw_source_checked(&path,4096,&mut |capacity,_,decode|{assert_eq!(capacity,0);assert!(!decode);Ok(())}).unwrap().unwrap();assert!(lease.same_binding(&raw.lease));assert_eq!(provider.original_source_bytes(&lease).unwrap().unwrap(),bytes);assert_eq!(raw.calls.get(),1);let foreign=crate::SourceAcquisitionLease::from_raw_original_bytes(bytes.to_vec(),());assert!(provider.original_source_bytes(&foreign).is_err());let actual=provider.original_raw_source_checked(&path,4096,&mut |_,_,_|Err(io::Error::from_raw_os_error(1450))).unwrap_err();assert_eq!(actual.raw_os_error(),Some(1450));
}
#[test]fn native_prepared_capture_without_raw_issuer_is_not_an_original_source(){
 struct NoRaw;impl SourceProvider for NoRaw{fn read(&self,_:&Path)->Result<String,String>{panic!("no raw issuer must not trigger decoded fallback")}}
 let path=PathBuf::from("no_original_source.dm");let captures=PreparedSources::from_prepared([(path.clone(),Arc::new(PreparedSource::new(Arc::from("/proc/native_only()\n"))))]).unwrap();let provider=PreparedSourceProvider::new(&captures,&NoRaw);let actual=provider.original_raw_source_checked(&path,4096,&mut |_,_,_|panic!("native capture grants no Original admission")).unwrap_err();assert_eq!(actual.kind(),io::ErrorKind::NotConnected);
}
