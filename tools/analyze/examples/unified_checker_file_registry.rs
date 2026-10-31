//! Independent old FileList registration versus admitted native coordinates.
//! No old checker answers or current semantic output are substituted.
#[cfg(all(feature="legacy-sem",feature="native-policy"))]
#[path="../../dmb/crates/dm-analysis/examples/support/acquired_files.rs"]mod acquired_files;
#[cfg(all(feature="legacy-sem",feature="native-policy"))]
fn main()->Result<(),Box<dyn std::error::Error>>{
 use std::{path::PathBuf,sync::{Arc,atomic::{AtomicUsize,Ordering}}};
 let project=PathBuf::from(std::env::args().nth(1).ok_or("expected original DME path")?);
 let context=dreammaker::Context::default();
 let preprocessor=dreammaker::preprocessor::Preprocessor::new(&context,project.clone())?;
 for _ in preprocessor{}
 if context.errors().iter().any(|error|error.severity()==dreammaker::Severity::Error){return Err(format!("independent preprocessor errors: {:?}",context.errors()).into())}
 let provider=acquired_files::AcquiredFiles::default();let frontend=dm_tree::frontend::build(&project,&provider,&Default::default(),1).map_err(|errors|format!("native source preparation: {errors:?}"))?;
 let map=frontend.source_export_mapping().ok_or("native mapping unavailable")?;
 let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let admission=dm_syntax::SettingAdmission::new(&counter,4*1024*1024,&poll);let registry=map.original_checker_source_registry(&admission)?;
 let mut expected=Vec::new();context.file_list().for_each(|path|expected.push(path.to_owned()));
 let mut seen=std::collections::BTreeSet::new();for(_,key,id)in registry.registrations(){let original=context.file_list().get_id(key).ok_or_else(||format!("original FileList has no native key {key:?}"))?;if format!("{original:?}")!=format!("FileId({id})"){return Err(format!("FileId differs for {key:?}: original {original:?}, native {id}").into())}seen.insert(key);}
 if seen.len()!=expected.len(){return Err(format!("complete original registered-file count differs: {} vs {}",expected.len(),seen.len()).into())}
 drop(seen);drop(registry);assert_eq!(counter.load(Ordering::Acquire),0);println!("original file registry exact: {} files",expected.len());Ok(())
}
#[cfg(not(all(feature="legacy-sem",feature="native-policy")))]fn main(){panic!("independent registry oracle requires legacy-sem,native-policy")}
