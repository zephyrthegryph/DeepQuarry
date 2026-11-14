//! A single actual compiled-file ALLOW loan. Not full-CODE coverage or a model.
//! The private current Handler snapshot validates its partial/full owner first.
use std::{io,path::Path,sync::Arc};
use dq_analyze::{captured_generator_budget::Budget,captured_reactive_reads::Failure};
fn quota(b:&Budget,message:impl Into<String>)->Failure{b.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
pub(super) fn with_actual_file(subject:&crate::input_snapshot::HandlerStructuralSubject,mapping:&dm_tree::frontend::SourceExportMapping,relative:&str,budget:&Arc<Budget>,visit:&mut dyn FnMut(Option<dq_analyze::captured_raw_file::RawPolicyViews<'_>>)->Result<(),Failure>)->Result<(),Failure>{
 crate::daemon::control::checkpoint()?;budget.require().map_err(|m|quota(budget,m))?;
 if !subject.old_tree_contains(relative)?{return visit(None)}
 // This is the original reported relative spelling, not a canonicalized alias.
 budget.charge(subject.root_path().as_os_str().len().checked_add(subject.canonical_root_path().as_os_str().len()).and_then(|n|n.checked_add(relative.len().checked_mul(2)?)).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)).ok_or_else(||quota(budget,"handler original path overflow"))?).map_err(|m|quota(budget,m))?;
 // The report uses the logical root and unchanged relative spelling. The
 // already authenticated mapping can issue this path under either root.
 let path=subject.root_path().join(Path::new(relative));
 let canonical=subject.canonical_root_path().join(Path::new(relative));
 // The private Handler recipe renders its already captured canonical root
 // through this exact existing drive-prefix key before issuing includes.
 // Match that producer spelling, never an arbitrary canonicalized candidate.
 let rendered=dm_preprocess::regions::filesystem_comparison_key(subject.canonical_root_path()).join(Path::new(relative));
 let acquired=mapping.source_acquisitions().find(|(actual,_)|*actual==path.as_path())
  .or_else(||mapping.source_acquisitions().find(|(actual,_)|*actual==canonical.as_path()))
  .or_else(||mapping.source_acquisitions().find(|(actual,_)|*actual==rendered.as_path()))
  .ok_or("handler finding file has no actual partial/full acquisition")?.1.ok_or("handler finding file's acquisition is unissued")?;
 let original=crate::input_snapshot::recorded_source_original(acquired)?;let raw=match &original{crate::input_snapshot::RecordedSourceOriginal::Utf8(text)=>text.as_bytes(),crate::input_snapshot::RecordedSourceOriginal::Bytes(bytes)=>bytes.as_slice()};
 let all=dq_analyze::captured_raw_file::with_original_policy_file_prepared(subject.root_path(),&path,0,budget,|scratch|{
  let transform=if matches!(&original,crate::input_snapshot::RecordedSourceOriginal::Utf8(text)if !text.as_bytes().contains(&b'\r')){0}else{dq_analyze::captured_raw_file::analyze_raw_len(raw)?.checked_mul(4).and_then(|n|n.checked_add(8192)).ok_or_else(||quota(scratch,"handler raw projection overflow"))?};scratch.charge(transform).map_err(|m|quota(scratch,m))?;Ok(crate::input_snapshot::normalize_recorded_policy_original(&original))
 },&mut|actual,views|{if actual!=relative{return Err("handler actual ALLOW projection relative path differs".into())}visit(Some(views))?;Ok(true)})?;
 if !all{return Err("handler actual ALLOW projection callback stopped".into())}crate::daemon::control::checkpoint()?;Ok(())
}
