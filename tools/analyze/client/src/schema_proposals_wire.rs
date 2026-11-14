//! Delivered DATA for one actual read-only schema proposal operation.
use crate::selected_exclusions_wire::{Frame,Seal,MAX_STREAM};
use serde::{Deserialize,Serialize};use std::{io,path::Path};
#[derive(Clone,Copy,Debug,Deserialize,Serialize,Eq,PartialEq)]pub enum Schema{#[serde(rename="native-schema-proposals-v1")]V1}
#[derive(Clone,Debug,Deserialize,Serialize)]#[serde(deny_unknown_fields)]
pub struct Terminal{pub schema:Schema,pub complete:bool,pub applied:bool,pub full_policy_parity:bool,pub root:std::path::PathBuf,pub frame:Frame,pub count:u64,#[serde(deserialize_with="diagnostic_presence")]pub diagnostics:Option<Seal>,pub report:Seal}
fn diagnostic_presence<'de,D:serde::Deserializer<'de>>(d:D)->Result<Option<Seal>,D::Error>{Option::<Seal>::deserialize(d)}
impl Terminal{pub fn require(&self,expected_root:&Path)->io::Result<()>{
 if !self.complete||self.applied||self.full_policy_parity||self.root!=expected_root||!self.root.is_absolute()||self.report.length==0||self.report.length>MAX_STREAM||self.diagnostics.as_ref().is_some_and(|seal|seal.length==0||seal.length>MAX_STREAM)||self.report.length.checked_add(self.diagnostics.as_ref().map_or(0,|seal|seal.length)).is_none_or(|n|n>MAX_STREAM){return Err(io::Error::new(io::ErrorKind::InvalidData,"schema proposal terminal differs from exact read-only completed request"))}Ok(())
}}
#[cfg(test)]mod tests{use super::*;use crate::selected_exclusions_wire::Hex128;
 #[test]fn schema_terminal_requires_readonly_completion_exact_root_and_bounded_streams(){
  let root=if cfg!(windows){Path::new("E:/actual-project")}else{Path::new("/actual-project")};let mut t=Terminal{schema:Schema::V1,complete:true,applied:false,full_policy_parity:false,root:root.into(),frame:Frame{semantic_revision:Hex128(1),source_revision:Hex128(2),policy_revision:Hex128(3)},count:0,diagnostics:None,report:Seal{length:1,hash:Hex128(4)}};
  t.require(root).unwrap();t.complete=false;assert!(t.require(root).is_err());t.complete=true;t.applied=true;assert!(t.require(root).is_err());t.applied=false;t.full_policy_parity=true;assert!(t.require(root).is_err());t.full_policy_parity=false;assert!(t.require(&root.join("foreign")).is_err());t.diagnostics=Some(Seal{length:MAX_STREAM,hash:Hex128(5)});assert!(t.require(root).is_err());
  let mut missing=serde_json::to_value(&t).unwrap();missing.as_object_mut().unwrap().remove("diagnostics");assert!(serde_json::from_value::<Terminal>(missing).is_err());
  let mut data=serde_json::to_value(&t).unwrap();data["apply"]=serde_json::json!(true);assert!(serde_json::from_value::<Terminal>(data).is_err());
 }
}
