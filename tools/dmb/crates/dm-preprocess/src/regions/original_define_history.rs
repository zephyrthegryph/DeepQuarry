//! Actual old define-history DATA, not a second expansion environment. Entries
//! alias the SAME typed immutable products removed/finalized from Binding.
use super::environment::{OriginalDefinitionProduct,MacroEnvironment};
use crate::macro_expansion::{OriginalMacroRows as Rows,OriginalMacroText as Text,OriginalMacroOrigin as Origin};
use dm_syntax::{SettingAdmission,SettingRootLease};use std::{io,sync::Arc};
#[derive(Clone,Copy,Debug)]pub(super) enum OriginalDefineHistoryEnd{Undef(Origin),Final{ordinal:usize}}
struct Entry{name:Text,product:Arc<OriginalDefinitionProduct>,end:OriginalDefineHistoryEnd}
pub(super) struct OriginalDefineHistory{rows:Rows<Entry>,finalized:bool,failed:bool,domain:SettingRootLease}
pub(super) struct OriginalDefineHistoryEntry<'a>{pub(super) name:&'a str,pub(super) defined_at:Option<Origin>,pub(super) end:OriginalDefineHistoryEnd,pub(super) product:&'a OriginalDefinitionProduct}
impl OriginalDefineHistory{
 pub(super) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{rows:Rows::new(a)?,finalized:false,failed:false,domain:a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?})}
 fn check(&mut self,a:&SettingAdmission<'_>)->io::Result<()>{if self.failed||self.finalized{return Err(io::ErrorKind::InvalidInput.into())}let result=if !a.matches_lease_domain(&self.domain){Err(io::ErrorKind::InvalidInput.into())}else{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))};if result.is_err(){self.failed=true}result}
 fn push(&mut self,name:&str,product:Arc<OriginalDefinitionProduct>,end:OriginalDefineHistoryEnd,a:&SettingAdmission<'_>)->io::Result<()>{let mut text=Text::new(a)?;text.push_str(name,a)?;self.rows.push(Entry{name:text,product,end},a)}
 pub(super) fn record_undef_using(&mut self,name:&str,removed:Arc<OriginalDefinitionProduct>,completed:Origin,a:&SettingAdmission<'_>)->io::Result<()>{self.check(a)?;let result=self.push(name,removed,OriginalDefineHistoryEnd::Undef(completed),a);if result.is_err(){self.failed=true}result}
 /// Like old finalize: each STILL CURRENT stack epoch gets a distinct terminal
 /// sentinel ordinal. That sentinel is not a physical source location or EOF.
 /// Root callers separately retain the genuine primary delivery/completion role.
 pub(super) fn capture_current_using(&mut self,environment:&MacroEnvironment,a:&SettingAdmission<'_>)->io::Result<()>{self.check(a)?;let mut ordinal=0usize;let result=environment.visit_original_stack_owners_using(a,|name,product|{ordinal=ordinal.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;self.push(name,Arc::clone(product),OriginalDefineHistoryEnd::Final{ordinal},a)});if result.is_err(){self.failed=true}else{self.finalized=true}result}
 pub(super) fn is_finalized_by(&self,a:&SettingAdmission<'_>)->bool{!self.failed&&self.finalized&&a.matches_lease_domain(&self.domain)}
 pub(super) fn entries(&self)->impl Iterator<Item=OriginalDefineHistoryEntry<'_>>{self.rows.as_slice().iter().map(|row|OriginalDefineHistoryEntry{name:row.name.as_str(),defined_at:row.product.definition_name().map(|token|token.origin),end:row.end,product:&row.product})}
}
