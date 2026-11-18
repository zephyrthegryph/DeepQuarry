//! Callback-only receipt; no policy frame/model/source-completion fields.
use serde::{Serialize,Deserialize};use std::io;
use crate::{selected_exclusions_wire::Seal,full_registry_check_selection_wire::SelectionBinding};
#[derive(Debug,Clone,Copy,Serialize,Deserialize,PartialEq,Eq)]pub enum Schema{#[serde(rename="native-standalone-selftests-v1")]V1}
#[derive(Debug,Serialize,Deserialize)]#[serde(deny_unknown_fields)]pub struct Terminal{pub schema:Schema,pub complete:bool,pub selection:SelectionBinding,pub selected:u64,pub completed:u64,pub failed:u64,pub report:Seal}
impl Terminal{pub fn require(&self,selection:SelectionBinding)->io::Result<()>{if !self.complete||self.selection!=selection||self.selected==0||self.selected>999||self.completed!=self.selected||self.failed>self.completed||self.report.length==0||self.report.length>crate::selected_exclusions_wire::MAX_STREAM{return Err(io::Error::new(io::ErrorKind::InvalidData,"standalone selftest terminal differs from requested completed callbacks"))}Ok(())}}
