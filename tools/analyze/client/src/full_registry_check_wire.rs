//! Transport DATA for a genuine completed native full-registry CHECK. This
//! schema does not issue source, model, scope or filesystem authority.
use crate::selected_exclusions_wire::{Frame,Seal,MAX_STREAM};
use serde::{Deserialize,Serialize};
use std::io;
#[derive(Clone,Copy,Debug,Deserialize,Serialize,Eq,PartialEq,Ord,PartialOrd)]
#[serde(deny_unknown_fields)]
pub struct Options{pub raw:bool,pub ci:bool,pub unused:bool}
impl Default for Options{fn default()->Self{Self{raw:false,ci:false,unused:true}}}
#[derive(Clone,Copy,Debug,Deserialize,Serialize,Eq,PartialEq)]
pub enum Schema{#[serde(rename="native-full-registry-check-v1")]V1}
#[derive(Clone,Copy,Debug,Deserialize,Serialize,Eq,PartialEq)]
pub enum Scope{#[serde(rename="full_registry")]FullRegistry}
#[derive(Clone,Debug,Deserialize,Serialize)]
#[serde(deny_unknown_fields)]
pub struct Terminal{pub schema:Schema,pub complete:bool,pub full_policy_parity:bool,pub scope:Scope,
 pub options:Options,pub frame:Frame,pub clean:bool,pub diagnostics:Option<Seal>,pub report:Seal}
impl Terminal{
 pub fn require(&self,expected:Options)->io::Result<()>{
  let invalid=||io::Error::new(io::ErrorKind::InvalidData,"full native check terminal differs from the exact requested report-only shape");
  if !self.complete||self.full_policy_parity||self.options!=expected||self.report.length==0||self.report.length>MAX_STREAM
   ||self.diagnostics.as_ref().is_some_and(|part|part.length==0||part.length>MAX_STREAM)
   ||self.report.length.checked_add(self.diagnostics.as_ref().map_or(0,|part|part.length)).is_none_or(|n|n>MAX_STREAM){return Err(invalid())}Ok(())
 }
}
#[cfg(test)]mod tests{
 use super::*;use crate::selected_exclusions_wire::Hex128;
 #[test]fn check_terminal_data_refuses_incomplete_wrong_flags_false_parity_and_overflow(){
  let options=Options::default();let mut terminal=Terminal{schema:Schema::V1,scope:Scope::FullRegistry,complete:true,full_policy_parity:false,options,frame:Frame{semantic_revision:Hex128(1),source_revision:Hex128(2),policy_revision:Hex128(3)},clean:true,diagnostics:None,report:Seal{length:1,hash:Hex128(4)}};
  terminal.require(options).unwrap();terminal.complete=false;assert!(terminal.require(options).is_err());terminal.complete=true;terminal.full_policy_parity=true;assert!(terminal.require(options).is_err());terminal.full_policy_parity=false;terminal.options.raw=true;assert!(terminal.require(options).is_err());terminal.options=options;terminal.diagnostics=Some(Seal{length:MAX_STREAM,hash:Hex128(5)});assert!(terminal.require(options).is_err());
  let mut wire=serde_json::to_value(&terminal).unwrap();wire["scope"]=serde_json::json!("three_policy_pilot");assert!(serde_json::from_value::<Terminal>(wire).is_err());
 }
}
