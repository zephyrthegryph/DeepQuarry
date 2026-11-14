//! Transport DATA for a genuine completed native full-registry CHECK. This
//! schema does not issue source, model, scope or filesystem authority.
use crate::selected_exclusions_wire::{Hex128,Seal,MAX_STREAM};
use crate::full_registry_check_selection_wire::SelectionBinding;
#[derive(Clone,Copy,Debug,Deserialize,Serialize,Eq,PartialEq)]
#[serde(tag="owner",rename_all="snake_case",deny_unknown_fields)]
pub enum CheckFrame{Model{semantic_revision:Hex128,source_revision:Hex128,policy_revision:Hex128},Source{query_revision:Hex128,source_revision:Hex128,policy_revision:Hex128},Handlers{query_revision:Hex128,#[serde(deserialize_with="present_revision")]partial_source_revision:Option<Hex128>,#[serde(deserialize_with="present_revision")]full_source_revision:Option<Hex128>}}
impl From<crate::selected_exclusions_wire::Frame> for CheckFrame{fn from(frame:crate::selected_exclusions_wire::Frame)->Self{Self::Model{semantic_revision:frame.semantic_revision,source_revision:frame.source_revision,policy_revision:frame.policy_revision}}}
use serde::{Deserialize,Serialize};
use std::io;
#[derive(Clone,Copy,Debug,Deserialize,Serialize,Eq,PartialEq,Ord,PartialOrd)]
#[serde(deny_unknown_fields)]
pub struct Options{pub raw:bool,pub ci:bool,pub unused:bool,pub no_cache:bool,pub rehash:bool}
impl Default for Options{fn default()->Self{Self{raw:false,ci:false,unused:true,no_cache:false,rehash:false}}}
#[derive(Clone,Copy,Debug,Deserialize,Serialize,Eq,PartialEq)]
pub enum Schema{#[serde(rename="native-registry-check-v2")]V2}
#[derive(Clone,Copy,Debug,Deserialize,Serialize,Eq,PartialEq)]
pub enum Scope{#[serde(rename="full_registry")]FullRegistry,#[serde(rename="registry_selection")]RegistrySelection}
#[derive(Clone,Debug,Deserialize,Serialize)]
#[serde(deny_unknown_fields)]
pub struct Terminal{pub schema:Schema,pub complete:bool,pub full_policy_parity:bool,pub scope:Scope,
 pub options:Options,pub selection:SelectionBinding,pub selected:u64,pub registered:u64,pub frame:CheckFrame,pub clean:bool,#[serde(deserialize_with="present_diagnostics")]pub diagnostics:Option<Seal>,pub report:Seal}
fn present_revision<'de,D:serde::Deserializer<'de>>(deserializer:D)->Result<Option<Hex128>,D::Error>{Option::<Hex128>::deserialize(deserializer)}
fn present_diagnostics<'de,D:serde::Deserializer<'de>>(deserializer:D)->Result<Option<Seal>,D::Error>{Option::<Seal>::deserialize(deserializer)}
impl Terminal{
 pub fn require(&self,expected:Options,selection:SelectionBinding)->io::Result<()>{
  let invalid=||io::Error::new(io::ErrorKind::InvalidData,"full native check terminal differs from the exact requested report-only shape");
  if (matches!(self.frame,CheckFrame::Handlers{..})&&(self.scope!=Scope::RegistrySelection||self.selected!=1))
   ||!self.complete||self.full_policy_parity||self.options!=expected||self.selection!=selection||self.selected==0||self.selected>self.registered
   ||(self.scope==Scope::FullRegistry)!=(self.selected==self.registered)||self.report.length==0||self.report.length>MAX_STREAM
   ||self.diagnostics.as_ref().is_some_and(|part|part.length==0||part.length>MAX_STREAM)
   ||self.report.length.checked_add(self.diagnostics.as_ref().map_or(0,|part|part.length)).is_none_or(|n|n>MAX_STREAM){return Err(invalid())}Ok(())
 }
}
#[cfg(test)]mod tests{
 use super::*;use crate::selected_exclusions_wire::Hex128;
 #[test]fn check_terminal_data_refuses_incomplete_wrong_flags_false_parity_and_overflow(){
  let options=Options::default();let mut terminal=Terminal{schema:Schema::V2,scope:Scope::FullRegistry,complete:true,full_policy_parity:false,options,selection:SelectionBinding::for_selectors(&[]).unwrap(),selected:1,registered:1,frame:CheckFrame::Model{semantic_revision:Hex128(1),source_revision:Hex128(2),policy_revision:Hex128(3)},clean:true,diagnostics:None,report:Seal{length:1,hash:Hex128(4)}};
  terminal.require(options,SelectionBinding::for_selectors(&[]).unwrap()).unwrap();terminal.complete=false;assert!(terminal.require(options,SelectionBinding::for_selectors(&[]).unwrap()).is_err());terminal.complete=true;terminal.full_policy_parity=true;assert!(terminal.require(options,SelectionBinding::for_selectors(&[]).unwrap()).is_err());terminal.full_policy_parity=false;terminal.options.raw=true;assert!(terminal.require(options,SelectionBinding::for_selectors(&[]).unwrap()).is_err());terminal.options=options;terminal.diagnostics=Some(Seal{length:MAX_STREAM,hash:Hex128(5)});assert!(terminal.require(options,SelectionBinding::for_selectors(&[]).unwrap()).is_err());
  let mut wire=serde_json::to_value(&terminal).unwrap();wire["scope"]=serde_json::json!("three_policy_pilot");assert!(serde_json::from_value::<Terminal>(wire).is_err());
 }
}

#[cfg(test)]mod selected_frame_presence_controls{
 use super::*;
 #[test]fn handler_optional_provenance_fields_are_explicit_data_and_cannot_be_silently_omitted(){
  let frame=CheckFrame::Handlers{query_revision:Hex128(1),partial_source_revision:None,full_source_revision:None};let value=serde_json::to_value(frame).unwrap();assert_eq!(serde_json::from_value::<CheckFrame>(value.clone()).unwrap(),frame);
  for field in ["partial_source_revision","full_source_revision"]{let mut missing=value.clone();missing.as_object_mut().unwrap().remove(field);assert!(serde_json::from_value::<CheckFrame>(missing).is_err(),"{field}");}
  let mut wrong=value;wrong["policy_revision"]=serde_json::json!("00000000000000000000000000000001");assert!(serde_json::from_value::<CheckFrame>(wrong).is_err());
 }
 #[test]fn selected_handler_terminal_cannot_claim_whole_registry_or_more_than_its_actual_one_producer(){
  let options=Options::default();let selection=SelectionBinding::for_selectors(&["sem/handlers".into()]).unwrap();let mut terminal=Terminal{schema:Schema::V2,complete:true,full_policy_parity:false,scope:Scope::RegistrySelection,options,selection,selected:1,registered:2,frame:CheckFrame::Handlers{query_revision:Hex128(1),partial_source_revision:Some(Hex128(2)),full_source_revision:None},clean:true,diagnostics:None,report:Seal{length:1,hash:Hex128(3)}};terminal.require(options,selection).unwrap();terminal.selected=2;terminal.scope=Scope::FullRegistry;assert!(terminal.require(options,selection).is_err());terminal.selected=1;assert!(terminal.require(options,selection).is_err());
 }
}
