//! Receiver-owned final source arena and SAME primary token append. Production
//! geometry comes once from OriginalOutputCursor, for lazy and batch delivery.
use super::{original_source_arena::OriginalSourceArena,original_prepared_output::{OriginalOutputCursor,OriginalOutputIdentity,OriginalPreparedOutputToken,OriginalPreparedDeliveryToken,OriginalDeliveredValue,OriginalDeliveryFrontier}};
use crate::{SourceProvider,macro_expansion::OriginalMacroToken as Token};
use dm_syntax::{OriginalPrimaryDemand,SettingAdmission,SettingRootLease};use std::io;
pub(super) struct OriginalFinalOutput<'a>{arena:OriginalSourceArena<'a>,cursor:Option<OriginalOutputCursor>,owner:OriginalOutputIdentity,delivery:OriginalDeliveryFrontier,failed:bool}
pub(super) struct OriginalEmittedToken{pub(super) token:dm_syntax::Token,pub(super) credit:SettingRootLease,pub(super) original:Option<OriginalDeliveredValue>}
impl<'a>OriginalFinalOutput<'a>{
 pub(super) fn new(work:&'a dyn crate::source_arena_credit::SourceArenaWork,a:&SettingAdmission<'_>)->io::Result<Self>{let cursor=OriginalOutputCursor::new(a)?;let owner=cursor.identity();let delivery=cursor.initial_delivery()?;Ok(Self{arena:OriginalSourceArena::new(work)?,cursor:Some(cursor),owner,delivery,failed:false})}
 pub(super) fn receiver(work:&'a dyn crate::source_arena_credit::SourceArenaWork,delivery:OriginalDeliveryFrontier)->io::Result<Self>{if delivery.end()!=0{return Err(io::ErrorKind::InvalidInput.into())}let owner=delivery.owner().clone();Ok(Self{arena:OriginalSourceArena::new(work)?,cursor:None,owner,delivery,failed:false})}
 pub(super) fn source(&self)->&str{self.arena.as_str()}
 pub(super) fn prepare(&mut self,actual:Token<'static>,provider:&dyn SourceProvider,a:&SettingAdmission<'_>)->io::Result<OriginalPreparedOutputToken>{if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let result=self.cursor.as_mut().ok_or(io::ErrorKind::InvalidInput)?.prepare(actual,provider,a);if result.is_err(){self.failed=true;}result}
 pub(super) fn adopt(&mut self,prepared:OriginalPreparedDeliveryToken,primary:&mut OriginalPrimaryDemand<'_,'_,'_>,a:&SettingAdmission<'_>)->io::Result<OriginalEmittedToken>{if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let result=prepared.adopt(&mut self.arena,primary,&self.owner,a);match result{Ok((emitted,delivery))=>{self.delivery=delivery;Ok(emitted)},Err(error)=>{self.failed=true;Err(error)}}}
 pub(super) fn delivery(&self)->io::Result<OriginalDeliveryFrontier>{if self.failed{return Err(io::ErrorKind::InvalidInput.into())}Ok(self.delivery.clone())}
 pub(super) fn finish(self)->io::Result<crate::SourceText>{if self.failed{return Err(io::ErrorKind::InvalidInput.into())}self.arena.finish()}
}
