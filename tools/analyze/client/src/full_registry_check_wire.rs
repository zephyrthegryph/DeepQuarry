//! Transport DATA for a genuine completed native full-registry CHECK. This
//! schema does not issue source, model, scope or filesystem authority.
use crate::selected_exclusions_wire::{Hex128,Seal,MAX_STREAM};
use crate::full_registry_check_selection_wire::SelectionBinding;
#[derive(Clone,Copy,Debug,Deserialize,Serialize,Eq,PartialEq)]
#[serde(tag="owner",rename_all="snake_case",deny_unknown_fields)]
pub enum CheckFrame{SourceHandlers{query_revision:Hex128,source_revision:Hex128,policy_revision:Hex128,handler_query_revision:Hex128,#[serde(deserialize_with="present_revision")]partial_source_revision:Option<Hex128>,#[serde(deserialize_with="present_revision")]full_source_revision:Option<Hex128>,#[serde(deserialize_with="present_revision")]full_semantic_revision:Option<Hex128>,#[serde(deserialize_with="present_revision")]full_policy_revision:Option<Hex128>},Model{semantic_revision:Hex128,source_revision:Hex128,policy_revision:Hex128},Source{query_revision:Hex128,source_revision:Hex128,policy_revision:Hex128},Handlers{query_revision:Hex128,#[serde(deserialize_with="present_revision")]partial_source_revision:Option<Hex128>,#[serde(deserialize_with="present_revision")]full_source_revision:Option<Hex128>}}
impl From<crate::selected_exclusions_wire::Frame> for CheckFrame{fn from(frame:crate::selected_exclusions_wire::Frame)->Self{Self::Model{semantic_revision:frame.semantic_revision,source_revision:frame.source_revision,policy_revision:frame.policy_revision}}}
use serde::{Deserialize,Serialize};
use std::io;
#[derive(Clone,Copy,Debug,Deserialize,Serialize,Eq,PartialEq,Ord,PartialOrd)]
#[serde(deny_unknown_fields)]
pub struct Options{pub raw:bool,pub ci:bool,pub unused:bool,pub no_cache:bool,pub rehash:bool}
impl Default for Options{fn default()->Self{Self{raw:false,ci:false,unused:true,no_cache:false,rehash:false}}}
#[derive(Clone,Copy,Debug,Deserialize,Serialize,Eq,PartialEq)]
pub enum Schema{#[serde(rename="native-registry-check-v2")]V2,#[serde(rename="native-registry-check-v3")]V3}
#[derive(Clone,Copy,Debug,Deserialize,Serialize,Eq,PartialEq)]
pub enum Scope{#[serde(rename="full_registry")]FullRegistry,#[serde(rename="registry_selection")]RegistrySelection}
#[derive(Clone,Copy,Debug,Deserialize,Serialize,Eq,PartialEq)]
#[serde(from="[u64;2]",into="[u64;2]")]
pub struct Selftests{pub completed:u64,pub failed:u64}
impl From<[u64;2]> for Selftests{fn from([completed,failed]:[u64;2])->Self{Self{completed,failed}}}
impl From<Selftests> for [u64;2]{fn from(actual:Selftests)->Self{[actual.completed,actual.failed]}}
#[derive(Clone,Debug,Deserialize,Serialize)]
#[serde(deny_unknown_fields)]
pub struct Terminal{pub schema:Schema,pub complete:bool,pub full_policy_parity:bool,pub scope:Scope,
 pub options:Options,pub selection:SelectionBinding,pub selected:u64,pub registered:u64,pub frame:CheckFrame,pub clean:bool,#[serde(default,skip_serializing_if="Option::is_none")]pub selftests:Option<Selftests>,#[serde(deserialize_with="present_diagnostics")]pub diagnostics:Option<Seal>,pub report:Seal}
fn present_revision<'de,D:serde::Deserializer<'de>>(deserializer:D)->Result<Option<Hex128>,D::Error>{Option::<Hex128>::deserialize(deserializer)}
fn present_diagnostics<'de,D:serde::Deserializer<'de>>(deserializer:D)->Result<Option<Seal>,D::Error>{Option::<Seal>::deserialize(deserializer)}
impl Terminal{
 pub fn require(&self,expected:Options,selection:SelectionBinding)->io::Result<()>{ self.require_selftests(expected,selection,false) }
 pub fn require_selftests(&self,expected:Options,selection:SelectionBinding,selftests:bool)->io::Result<()>{
  let invalid=||io::Error::new(io::ErrorKind::InvalidData,"full native check terminal differs from the exact requested report-only shape");
  let source_handlers_invalid=match self.frame{
   CheckFrame::SourceHandlers{full_source_revision,full_semantic_revision,full_policy_revision,..}=>self.scope!=Scope::RegistrySelection||full_source_revision.is_some()!=full_semantic_revision.is_some()||full_source_revision.is_some()!=full_policy_revision.is_some(),
   _=>false,
  };
  let selftests_invalid=match(selftests,self.selftests,self.schema){(false,None,Schema::V2)=>false,(true,Some(actual),Schema::V3)=>actual.completed!=self.selected||actual.failed>actual.completed||(actual.failed>0&&self.clean),_=>true};
  if selftests_invalid||source_handlers_invalid||(matches!(self.frame,CheckFrame::Handlers{..})&&(self.scope!=Scope::RegistrySelection||self.selected!=1))
   ||!self.complete||self.full_policy_parity||self.options!=expected||self.selection!=selection||self.selected==0||self.selected>self.registered
   ||(self.scope==Scope::FullRegistry)!=(self.selected==self.registered)||self.report.length==0||self.report.length>MAX_STREAM
   ||self.diagnostics.as_ref().is_some_and(|part|part.length==0||part.length>MAX_STREAM)
   ||self.report.length.checked_add(self.diagnostics.as_ref().map_or(0,|part|part.length)).is_none_or(|n|n>MAX_STREAM){return Err(invalid())}Ok(())
 }
}
#[cfg(test)]mod tests{
 use super::*;use crate::selected_exclusions_wire::Hex128;
 #[test]fn check_terminal_data_refuses_incomplete_wrong_flags_false_parity_and_overflow(){
  let options=Options::default();let mut terminal=Terminal{schema:Schema::V2,scope:Scope::FullRegistry,complete:true,full_policy_parity:false,options,selection:SelectionBinding::for_selectors(&[]).unwrap(),selected:1,registered:1,frame:CheckFrame::Model{semantic_revision:Hex128(1),source_revision:Hex128(2),policy_revision:Hex128(3)},clean:true,selftests:None,diagnostics:None,report:Seal{length:1,hash:Hex128(4)}};
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
  let options=Options::default();let selection=SelectionBinding::for_selectors(&["sem/handlers".into()]).unwrap();let mut terminal=Terminal{schema:Schema::V2,complete:true,full_policy_parity:false,scope:Scope::RegistrySelection,options,selection,selected:1,registered:2,frame:CheckFrame::Handlers{query_revision:Hex128(1),partial_source_revision:Some(Hex128(2)),full_source_revision:None},clean:true,selftests:None,diagnostics:None,report:Seal{length:1,hash:Hex128(3)}};terminal.require(options,selection).unwrap();terminal.selected=2;terminal.scope=Scope::FullRegistry;assert!(terminal.require(options,selection).is_err());terminal.selected=1;assert!(terminal.require(options,selection).is_err());
 }
}

#[cfg(test)]mod source_handler_frame_controls{
 use super::*;
 fn terminal()->Terminal{let options=Options::default();Terminal{schema:Schema::V2,scope:Scope::RegistrySelection,complete:true,full_policy_parity:false,options,selection:SelectionBinding::for_selectors(&["scheduler".into(),"sem/handlers".into()]).unwrap(),selected:2,registered:3,frame:CheckFrame::SourceHandlers{query_revision:Hex128(1),source_revision:Hex128(2),policy_revision:Hex128(3),handler_query_revision:Hex128(4),partial_source_revision:None,full_source_revision:None,full_semantic_revision:None,full_policy_revision:None},clean:false,selftests:None,diagnostics:None,report:Seal{length:1,hash:Hex128(5)}}}
 #[test]fn source_handler_frame_requires_explicit_independent_full_triplet_and_exact_context(){
  let mut actual=terminal();let options=actual.options;let selection=actual.selection;actual.require(options,selection).unwrap();
  for field in["partial_source_revision","full_source_revision","full_semantic_revision","full_policy_revision"]{let mut wire=serde_json::to_value(actual.frame).unwrap();wire.as_object_mut().unwrap().remove(field);assert!(serde_json::from_value::<CheckFrame>(wire).is_err(),"missing {field}");}
  if let CheckFrame::SourceHandlers{full_source_revision,..}=&mut actual.frame{*full_source_revision=Some(Hex128(6));}assert!(actual.require(options,selection).is_err());
  if let CheckFrame::SourceHandlers{full_semantic_revision,full_policy_revision,..}=&mut actual.frame{*full_semantic_revision=Some(Hex128(7));*full_policy_revision=Some(Hex128(8));}actual.require(options,selection).unwrap();actual.scope=Scope::FullRegistry;actual.selected=actual.registered;assert!(actual.require(options,selection).is_err());
 }
 #[test]fn source_handler_frame_does_not_replace_requested_options_binding_or_actual_payload_bounds(){let mut actual=terminal();let options=actual.options;let selection=actual.selection;actual.options.unused=false;assert!(actual.require(options,selection).is_err());actual.options=options;actual.complete=false;assert!(actual.require(options,selection).is_err());actual.complete=true;actual.report.length=MAX_STREAM+1;assert!(actual.require(options,selection).is_err());}
}

#[cfg(test)]mod source_handler_header_bound{
 use super::*;
 #[test]fn maximal_source_handler_terminal_fits_existing_header_without_raising_caps(){
  let options=Options{raw:false,ci:false,unused:false,no_cache:false,rehash:false};let selection=SelectionBinding{selectors:u64::MAX,hash:Hex128(u128::MAX)};
  let frame=CheckFrame::SourceHandlers{query_revision:Hex128(u128::MAX),source_revision:Hex128(u128::MAX),policy_revision:Hex128(u128::MAX),handler_query_revision:Hex128(u128::MAX),partial_source_revision:Some(Hex128(u128::MAX)),full_source_revision:Some(Hex128(u128::MAX)),full_semantic_revision:Some(Hex128(u128::MAX)),full_policy_revision:Some(Hex128(u128::MAX))};
  let actual=Terminal{schema:Schema::V2,scope:Scope::RegistrySelection,complete:true,full_policy_parity:false,options,selection,selected:u64::MAX-1,registered:u64::MAX,frame,clean:false,selftests:None,diagnostics:Some(Seal{length:MAX_STREAM/2,hash:Hex128(u128::MAX)}),report:Seal{length:MAX_STREAM-MAX_STREAM/2,hash:Hex128(u128::MAX)}};
  actual.require(options,selection).unwrap();let bytes=serde_json::to_vec(&actual).unwrap();assert!(bytes.len()+1<=crate::selected_exclusions_wire::MAX_HEADER,"actual serialized header plus newline must fit the unchanged cap: {}",bytes.len()+1);let decoded:Terminal=serde_json::from_slice(&bytes).unwrap();decoded.require(options,selection).unwrap();
 }
}

#[cfg(test)]mod actual_callback_receipt_controls{
 use super::*;
 fn terminal()->Terminal{Terminal{schema:Schema::V3,scope:Scope::RegistrySelection,complete:true,full_policy_parity:false,options:Options::default(),selection:SelectionBinding::for_selectors(&["scheduler".into()]).unwrap(),selected:1,registered:2,frame:CheckFrame::Source{query_revision:Hex128(1),source_revision:Hex128(2),policy_revision:Hex128(3)},clean:false,selftests:Some(Selftests{completed:1,failed:1}),diagnostics:None,report:Seal{length:1,hash:Hex128(4)}}}
 #[test]fn actual_selftest_terminal_requires_requested_mode_exact_completion_and_failed_verdict(){let mut t=terminal();t.require_selftests(t.options,t.selection,true).unwrap();assert!(t.require(t.options,t.selection).is_err());t.selftests.as_mut().unwrap().completed=0;assert!(t.require_selftests(t.options,t.selection,true).is_err());t.selftests.as_mut().unwrap().completed=1;t.clean=true;assert!(t.require_selftests(t.options,t.selection,true).is_err());t.clean=false;t.schema=Schema::V2;assert!(t.require_selftests(t.options,t.selection,true).is_err());t.schema=Schema::V3;t.selftests=None;assert!(t.require_selftests(t.options,t.selection,true).is_err());}
 #[test]fn explicit_no_selftest_keeps_v2_shape_without_an_added_null_receipt(){let mut t=terminal();t.schema=Schema::V2;t.selftests=None;t.require(t.options,t.selection).unwrap();let value=serde_json::to_value(&t).unwrap();assert!(value.get("selftests").is_none());let bytes=serde_json::to_vec(&t).unwrap();let decoded:Terminal=serde_json::from_slice(&bytes).unwrap();decoded.require(t.options,t.selection).unwrap();}
 #[test]fn callback_counts_keep_maximal_revision_and_payload_fields_inside_the_actual_bounded_header(){let options=Options{raw:false,ci:false,unused:false,no_cache:false,rehash:false};let mut t=terminal();t.options=options;t.selection=SelectionBinding{selectors:u64::MAX,hash:Hex128(u128::MAX)};t.selected=999;t.registered=u64::MAX;t.selftests=Some(Selftests{completed:999,failed:999});t.frame=CheckFrame::SourceHandlers{query_revision:Hex128(u128::MAX),source_revision:Hex128(u128::MAX),policy_revision:Hex128(u128::MAX),handler_query_revision:Hex128(u128::MAX),partial_source_revision:Some(Hex128(u128::MAX)),full_source_revision:Some(Hex128(u128::MAX)),full_semantic_revision:Some(Hex128(u128::MAX)),full_policy_revision:Some(Hex128(u128::MAX))};t.diagnostics=Some(Seal{length:MAX_STREAM/2,hash:Hex128(u128::MAX)});t.report=Seal{length:MAX_STREAM-MAX_STREAM/2,hash:Hex128(u128::MAX)};t.require_selftests(options,t.selection,true).unwrap();assert!(serde_json::to_vec(&t).unwrap().len()+1<=crate::selected_exclusions_wire::MAX_HEADER,"DATA three-digit callback count width, not a new production cap");}
}
