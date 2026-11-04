//! Actual completed conditional-range DATA, retained across producer lookahead.
//! Only the same transition kernel's History enters this owner. No incomplete
//! frame is closed, reordered, or promoted into source/model completeness.
use super::{original_conditional::History,OriginalNoticePlace};
use crate::macro_expansion::OriginalMacroRows as Rows;
use dm_syntax::{SettingAdmission,SettingRootLease};use std::io;
#[derive(Clone,Copy,Debug)]pub struct OriginalConditionalRange{pub from:OriginalNoticePlace,pub to:OriginalNoticePlace,pub active:bool}
pub(super) struct OriginalConditionalHistory{rows:Rows<History>,domain:SettingRootLease,failed:bool}
impl OriginalConditionalHistory{
 pub(super) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{rows:Rows::new(a)?,domain:a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?,failed:false})}
 pub(super) fn is_admitted_by(&self,a:&SettingAdmission<'_>)->bool{!self.failed&&a.matches_lease_domain(&self.domain)}
 pub(super) fn record_using(&mut self,actual:History,a:&SettingAdmission<'_>)->io::Result<()>{if !self.is_admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}let result=(||{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if actual.from.byte_column.is_none()||actual.to.byte_column.is_none(){return Err(io::Error::new(io::ErrorKind::InvalidData,"conditional range has no genuine completed source locations"))}self.rows.push(actual,a)})();if result.is_err(){self.failed=true}result}
 pub(super) fn iter(&self)->impl Iterator<Item=OriginalConditionalRange>+'_ {self.rows.as_slice().iter().map(|row|{let place=|origin:crate::macro_expansion::OriginalMacroOrigin|OriginalNoticePlace::Actual{occurrence:origin.occurrence,line:origin.line,column:origin.byte_column.expect("recorded genuine range point"),raw_span:None};OriginalConditionalRange{from:place(row.from),to:place(row.to),active:row.active}})}
 pub(super) fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){self.rows.visit_allocation(|p,n|visit(p,self.rows.len()*std::mem::size_of::<History>(),n));self.domain.visit_counter_storage(|p,n|visit(p,n,n));}
}
