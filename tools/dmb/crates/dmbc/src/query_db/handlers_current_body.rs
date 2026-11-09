//! Actual Kind4 child loan for the handlers partial-purpose report.
//! Availability is issued by the SAME native grammar result and exact current
//! archive binding. No diagnostic-string/Unsupported/bodyNone conversion.
use super::*;
use dm_tree::frontend::{BodyArchive,BodySyntaxFailure,CurrentArchivedBody,OriginalBodyDisposition};
/// Both variants retain the real current BODY and diagnostics throughout the
/// consumer callback. Skipped is not a fabricated empty StatementBody.
pub(super) enum HandlerBodyAvailability<'a,'p>{Available(CurrentArchivedBody<'a,'p>),Skipped(CurrentArchivedBody<'a,'p>)}
impl QueryDb{
 /// Called only inside the actual handlers result query. The existing ctx
 /// observes canonical Kind4; archive performs real preparation and current
 /// source/code binding. This does not issue a partial/full source witness.
 pub(super) fn with_handlers_current_body_in<'archive,T>(
  &self,ctx:&mut dm_query::Ctx<'_>,archive:&'archive BodyArchive,ordinal:usize,
  consume:impl for<'p>FnOnce(&mut dm_query::Ctx<'_>,HandlerBodyAvailability<'archive,'p>,&dm_syntax::SettingAdmission<'_>)->Result<T,BodySyntaxFailure>,
 )->Result<T,BodySyntaxFailure>{
  self.with_setting_admission(|admission|archive.with_current_body_checked_in(ordinal,admission,ctx,
   |ctx,input|super::body_syntax::obtain_product(ctx,input).map_err(|error| {
    #[cfg(debug_assertions)]
    if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some() {
     use std::sync::atomic::{AtomicUsize,Ordering};
     static REMAINING:AtomicUsize=AtomicUsize::new(16);
     if let Some(occurrence)=archive.occurrences().get(ordinal) {
      if REMAINING.fetch_update(Ordering::Relaxed,Ordering::Relaxed,|left|left.checked_sub(1)).is_ok() {
       let source=&occurrence.source;
       let _=std::io::Write::write_fmt(&mut std::io::stderr().lock(),format_args!(
        "handlers.body_product_failed ordinal={ordinal} file={} line={} span={:?}\n",
        source.semantic_path,source.line,occurrence.expanded_span,
       ));
      }
     }
    }
    error
   }),
   |ctx,body|{
    let disposition = body.syntax().original_code_disposition().map_err(|error| {
     if cfg!(debug_assertions) && std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some() {
      let source = &body.occurrence().source;
      let _ = std::io::Write::write_fmt(&mut std::io::stderr().lock(), format_args!(
       "handlers.body_failed ordinal={ordinal} file={} line={}\n", source.semantic_path, source.line,
      ));
     }
     error
    })?;
    let available=match disposition{
     OriginalBodyDisposition::Available(grant)=>{if !grant.belongs_to(body.syntax()){return Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"handlers availability belongs to a foreign current BODY")))}true},
     OriginalBodyDisposition::Skipped(grant)=>{if !grant.belongs_to(body.syntax()){return Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"handlers skip belongs to a foreign current BODY")))}false},
    };
    consume(ctx,if available{HandlerBodyAvailability::Available(body)}else{HandlerBodyAvailability::Skipped(body)},admission)
   }))
 }
}
