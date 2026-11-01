//! Feature-only whole original policy oracle. Never used by native runtime.
use crate::lint::{Cx,Lint,Meta,Registry,Sink};
use std::{collections::BTreeMap,path::Path};
use sha1::{Digest,Sha1};
struct OriginalKeys;
impl Lint for OriginalKeys{
 fn meta(&self)->&Meta{crate::keys_old_policy::metadata()}
 fn scan_tree(&self,cx:&Cx,out:&mut Sink){
  let decls=crate::keys_old_decls::Decls::get(cx.tree);
  let markers:Vec<_>=decls.markers.iter().map(|row|crate::declare_policy::Marker{name:&row.name,rel:&row.rel,line:row.line,body:&row.body,args:&row.args,body_offset:row.body_offset,line_starts:&row.line_starts}).collect();
  let input=crate::keys_old_policy::ScanInput{keys:crate::keys_old_policy::Input{markers:&markers,entry_ops:&decls.entry_ops},defines:&decls.defines,key_refs:&decls.key_refs,bad_sources:&decls.bad_sources};
  crate::keys_old_policy::scan_keys(cx,&input,out,|system|crate::keys_old_system::system_vars(cx.tree,system),crate::keys_old_system::system_types);
 }
}
fn hex(bytes:&[u8])->String{let mut text=String::with_capacity(bytes.len()*2);use std::fmt::Write;for byte in bytes{write!(&mut text,"{byte:02x}").unwrap();}text}
fn verify(bytes:&[u8],expected:&str)->Result<(),String>{if hex(&Sha1::digest(bytes))!=expected{return Err("immutable original key policy source hash changed".into())}Ok(())}
pub fn verify_original_sources()->Result<(),String>{
    verify(include_bytes!("../fixtures/original_policies/keys_policy.rs"),"74aecd22ddaf588b9844bc3d2e46178b0b72335a")?;
    verify(include_bytes!("../fixtures/original_policies/keys_decls.rs"),"d4b165a0880d462565c1dc9f25567929e972beff")?;
    verify(include_bytes!("../fixtures/original_policies/keys_raw_marker.rs"),"95e4004676f46179648ca244cc3c521f845b195a")?;
    verify(include_bytes!("../fixtures/original_policies/keys_raw_calls.rs"),"41f6187e73698e37c4a9eef70669c702f4923282")?;
    verify(include_bytes!("../fixtures/original_policies/keys_raw_entries.rs"),"c796b1f79193805338e7474f53ce8f25e8015c83")?;
    verify(include_bytes!("../fixtures/original_policies/keys_system_lookup.rs"),"8224f688bd56a1ee01fd7033c655d025534d1802")?;
    if include_str!("../fixtures/original_policies/keys_policy.rs").to_owned().replace("crate::raw_marker_policy","crate::keys_old_marker").replace("crate::raw_key_calls_policy","crate::keys_old_calls").replace("crate::raw_entry_proc_policy","crate::keys_old_entries")!=include_str!("../examples/support/keys_original/policy.rs"){return Err("nominal original key projection differs: tools/analyze/examples/support/keys_original/policy.rs".into())}
    if include_str!("../fixtures/original_policies/keys_decls.rs").to_owned().replace("crate::raw_marker_policy","crate::keys_old_marker").replace("crate::raw_key_calls_policy","crate::keys_old_calls").replace("crate::raw_entry_proc_policy","crate::keys_old_entries")!=include_str!("../examples/support/keys_original/decls.rs"){return Err("nominal original key projection differs: tools/analyze/examples/support/keys_original/decls.rs".into())}
    if include_str!("../fixtures/original_policies/keys_raw_marker.rs").to_owned()!=include_str!("../examples/support/keys_original/marker.rs"){return Err("nominal original key projection differs: tools/analyze/examples/support/keys_original/marker.rs".into())}
    if include_str!("../fixtures/original_policies/keys_raw_calls.rs").to_owned().replace("crate::raw_marker_policy","crate::keys_old_marker")!=include_str!("../examples/support/keys_original/calls.rs"){return Err("nominal original key projection differs: tools/analyze/examples/support/keys_original/calls.rs".into())}
    if include_str!("../fixtures/original_policies/keys_raw_entries.rs").to_owned().replace("crate::raw_marker_policy","crate::keys_old_marker")!=include_str!("../examples/support/keys_original/entries.rs"){return Err("nominal original key projection differs: tools/analyze/examples/support/keys_original/entries.rs".into())}
 Ok(())
}
/// Actual old Tree/scopes/registry scan; this owner is never supplied native rows.
pub fn scan(root:&Path,case:&str)->Result<serde_json::Value,String>{
 verify_original_sources()?;let mut registry=Registry::default();registry.add(OriginalKeys);
 let engine=crate::run::Engine::new(registry,crate::run::Options{root:root.to_path_buf(),lints:vec!["sem/keys".into()],no_cache:true,raw:true,..Default::default()})?;
 let outcome=engine.run_one(engine.reg.lints[0].as_ref());let mut digests=BTreeMap::new();for used in &outcome.allow_used{if digests.contains_key(&used.rel){continue}let file=engine.tree.get(&used.rel).ok_or("original key ALLOW source missing from actual old tree")?;digests.insert(used.rel.clone(),hex(&Sha1::digest(file.text().trim_end_matches('\n').as_bytes())));}
 Ok(serde_json::json!({"case":case,"sites":outcome.run.sites,"notes":outcome.run.notes,"allow_used":outcome.allow_used,"allow_digests":digests,"failed":outcome.failed,"text":outcome.text}))
}
