//! The actual physical source stack lent to the SAME macro cursor. Opening is
//! supplied by the existing bounded RecordingInputs acquisition/adoption path;
//! this module never substitutes PreparedSource, text equality or a private read.
use super::{original_raw_frame::{OriginalRawFrame,OriginalRawNotice},original_raw_points::OriginalRawPointIndex,original_token_factory::{self,Geometry},original_lexical_frame::OriginalLexicalFrameIdentity};
use crate::{SourceProvider,SourceAcquisitionLease,macro_expansion::{OriginalMacroRows as Rows,OriginalMacroToken as Token,OriginalMacroOrigin as Origin,OriginalMacroRawStep as RawStep}};
use dm_syntax::{SettingAdmission,Span,OriginalLexicalNoticePoint,numeric_form::OriginalNumberNotice};
use std::{io,cell::RefCell};
struct OpenFrame{frame:OriginalRawFrame,path:Option<super::original_file_path::OriginalFilePath>,geometry_at:usize,occurrence:usize,expansion_floor:usize}
/// Source notices retain exact same raw acquisition/frame and issued position.
/// The outer DirectivePass records them in its actual report/trace owner before
/// lending the next token. This trait grants no lexical/model/source capability.
pub(super) trait OriginalRawNoticeSink{
 fn condition_identifier_recovery(&mut self,_at:Origin,_value:Option<dm_syntax::OriginalTokenValue<&str>>,_a:&SettingAdmission<'_>)->io::Result<()>{Err(io::Error::new(io::ErrorKind::Unsupported,"actual Original member-name recovery notice sink is unissued"))}

 fn condition_primitive(&mut self,_at:Origin,_kind:dm_syntax::OriginalInputNoticeKind,_value:dm_syntax::OriginalTokenValue<&str>,_a:&SettingAdmission<'_>)->io::Result<()>{Err(io::Error::new(io::ErrorKind::Unsupported,"actual Original condition primitive notice sink is unissued"))}

 fn lexical(&mut self,frame:&OriginalLexicalFrameIdentity,occurrence:usize,location:super::original_raw_points::OriginalRawPoint,notice:OriginalRawNotice,a:&SettingAdmission<'_>)->io::Result<()>;
 fn numeric(&mut self,frame:&OriginalLexicalFrameIdentity,occurrence:usize,location:super::original_raw_points::OriginalRawPoint,point:OriginalLexicalNoticePoint,notice:OriginalNumberNotice<'_>,a:&SettingAdmission<'_>)->io::Result<()>;
}
struct SourceGeometry{occurrence:usize,geometry:super::original_raw_geometry::OriginalRawGeometry,points:OriginalRawPointIndex,actual_eof:bool}
/// Truthful physical-row envelope is distinct from exact raw token extent.
/// Arbitrary-byte raw quote delimiters need not have a decoded token END.
pub(super) struct OriginalPhysicalRow{pub(super) raw:Span,pub(super) decoded:Span,pub(super) point:super::OriginalByteCursor,pub(super) actual_eof:bool}
pub(super) struct OriginalRawInputs{frames:Rows<OpenFrame>,geometries:Rows<SourceGeometry>,failed:bool,stack_changed:bool,last_input:Option<Origin>}
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
impl OriginalRawInputs{
 pub(super) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{frames:Rows::new(a)?,geometries:Rows::new(a)?,failed:false,stack_changed:false,last_input:None})}
 /// The caller has already funded/read/adopted this SAME acquisition through
 /// the host's actual source-family lender. No frame-pop refunds that backing.
 pub(super) fn push_opened(&mut self,provider:&dyn SourceProvider,acquisition:SourceAcquisitionLease,occurrence:usize,expansion_floor:usize,a:&SettingAdmission<'_>)->io::Result<()>{
  if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let result=(||{poll(a)?;if self.geometries.as_slice().last().is_some_and(|prior|prior.occurrence>=occurrence){return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw source occurrences must follow the actual unique open order"))}let bytes=provider.original_source_bytes(&acquisition)?.ok_or(io::ErrorKind::NotConnected)?;let points=OriginalRawPointIndex::new(bytes,a)?;let geometry=super::original_raw_geometry::OriginalRawGeometry::from_acquired_using(provider,&acquisition,a)?;let frame=OriginalRawFrame::from_opened(provider,acquisition,a)?;let geometry_at=self.geometries.len();self.geometries.push(SourceGeometry{occurrence,geometry,points,actual_eof:false},a)?;self.frames.push(OpenFrame{frame,path:None,geometry_at,occurrence,expansion_floor},a)})();if result.is_err(){self.failed=true}result
 }
 /// The actual source owner calls this with the path of its SAME admitted
 /// read/recorded acquisition. No invocation-origin path is substituted.
 pub(super) fn push_opened_at(&mut self,provider:&dyn SourceProvider,acquisition:SourceAcquisitionLease,occurrence:usize,expansion_floor:usize,path:&std::path::Path,a:&SettingAdmission<'_>)->io::Result<()>{
  if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let result=(||{let actual=super::original_file_path::OriginalFilePath::new(path,a)?;self.push_opened(provider,acquisition,occurrence,expansion_floor,a)?;self.frames.last_mut().ok_or(io::ErrorKind::InvalidData)?.path=Some(actual);Ok(())})();if result.is_err(){self.failed=true}result
 }
 pub(super) fn current_physical_path(&self,a:&SettingAdmission<'_>)->io::Result<Option<&std::path::Path>>{
  if self.failed{return Err(io::ErrorKind::InvalidInput.into())}poll(a)?;let Some(frame)=self.frames.as_slice().last()else{return Ok(None)};let path=frame.path.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual opened physical file has no issued path context"))?;if !path.is_admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}Ok(Some(path.path()))
 }
 /// Macro/directive failures use the current underlying raw lexer tracker,
 /// independently of a replacement token's rebound invocation Origin. Loan
 /// validation and byte geometry remain tied to the SAME current acquisition.
 pub(super) fn with_current_read_point<T>(&mut self,provider:&dyn SourceProvider,a:&SettingAdmission<'_>,run:impl FnOnce(&OriginalLexicalFrameIdentity,usize,super::original_raw_points::OriginalRawPoint)->io::Result<T>)->io::Result<Option<T>>{
  if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let result=(||{poll(a)?;let Some(open)=self.frames.last_mut()else{return Ok(None)};let point=open.frame.read_point().ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual current raw reader has not issued a location"))?;let identity=open.frame.identity();let bytes=provider.original_source_bytes(identity.acquisition())?.ok_or(io::ErrorKind::NotConnected)?;let actual=self.geometries.as_mut_slice()[open.geometry_at].points.notice(bytes,point,a)?;run(identity,open.occurrence,actual).map(Some)})();if result.is_err(){self.failed=true}result
 }
 /// Retired file frames never retire their mapping evidence. Binary search
 /// selects the actual opened occurrence, then the private weak binding checks
 /// the independently retained current source lease before translating a point.
 pub(super) fn decoded_point_using(&self,occurrence:usize,lease:&SourceAcquisitionLease,raw_point:usize,a:&SettingAdmission<'_>)->io::Result<usize>{
  if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let at=self.geometries.as_slice().binary_search_by_key(&occurrence,|row|row.occurrence).map_err(|_|io::Error::new(io::ErrorKind::InvalidInput,"raw mapping occurrence was never opened"))?;self.geometries.as_slice()[at].geometry.decoded_point_using(lease,raw_point,a)
 }
 /// Consumed by the SAME final mapping owner; no row copy, raw source payload,
 /// source EOF claim or second geometry dictionary is introduced.
 fn into_source_geometries(self)->Rows<SourceGeometry>{self.geometries}
 /// One actual raw-token point plus physical source-line envelope. The row
 /// end is a real LF/physical byte EOF boundary, never a rounded token end.
 pub(super) fn physical_row_using(&mut self,origin:Origin,lease:&SourceAcquisitionLease,provider:&dyn SourceProvider,a:&SettingAdmission<'_>)->io::Result<OriginalPhysicalRow>{
  if self.failed{return Err(io::ErrorKind::InvalidInput.into())}poll(a)?;
  let at=self.geometries.as_slice().binary_search_by_key(&origin.occurrence,|row|row.occurrence).map_err(|_|io::ErrorKind::InvalidInput)?;
  let geometry=&mut self.geometries.as_mut_slice()[at];let raw=provider.original_source_bytes(lease)?.ok_or(io::ErrorKind::NotConnected)?;
  let offset=origin.physical.start;let eof_token=!origin.invocation&&origin.physical.start==origin.physical.end&&offset==raw.len()&&geometry.actual_eof;
  // A real final-newline token is issued one column after the tracker EOF.
  // Error notices retain their separate EOF tracker point (column before it).
  let point=geometry.points.at(raw,offset,a)?;
  if point.line!=origin.line||Some(point.column)!=origin.byte_column{return Err(io::Error::new(io::ErrorKind::InvalidInput,"source-map origin differs from the actual raw point roster"))}
  let start=geometry.points.line_start(point.line).ok_or(io::ErrorKind::InvalidData)?;
  let mut end=offset;while end<raw.len(){poll(a)?;let byte=raw[end];end+=1;if byte==b'\n'{break}}
  let decoded_start=geometry.geometry.decoded_point_using(lease,start,a)?;let decoded_end=geometry.geometry.decoded_point_using(lease,end,a)?;let decoded_point=geometry.geometry.decoded_point_using(lease,offset,a)?;
  Ok(OriginalPhysicalRow{raw:Span::new(start,end),decoded:Span::new(decoded_start,decoded_end),point:super::OriginalByteCursor{line:point.line,byte_column:point.column,source_offset:decoded_point},actual_eof:eof_token})
 }
 pub(super) fn frame_precedes_expansion(&self,depth:usize)->bool{self.frames.as_slice().last().is_some_and(|open|depth<=open.expansion_floor)}
 pub(super) fn take_stack_change(&mut self)->bool{std::mem::take(&mut self.stack_changed)}
 pub(super) fn depth(&self)->usize{self.frames.len()}
 pub(super) fn last_input(&self)->Option<Origin>{self.last_input}
 pub(super) fn current_occurrence(&self)->Option<usize>{self.frames.as_slice().last().map(|f|f.occurrence)}
 pub(super) fn next_using(&mut self,provider:&dyn SourceProvider,a:&SettingAdmission<'_>,sink:&mut dyn OriginalRawNoticeSink)->io::Result<RawStep<'static>>{
  if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed physical source stack cannot resume or issue EOF"))}let result=self.next_inner(provider,a,sink);if result.is_err(){self.failed=true}result
 }
 fn next_inner(&mut self,provider:&dyn SourceProvider,a:&SettingAdmission<'_>,sink:&mut dyn OriginalRawNoticeSink)->io::Result<RawStep<'static>>{
  loop{poll(a)?;let Some(open)=self.frames.last_mut()else{return Ok(RawStep::End)};
   let OpenFrame{frame,geometry_at,occurrence,..}=open;let points=&mut self.geometries.as_mut_slice()[*geometry_at].points;let occurrence=*occurrence;let identity=frame.identity().clone();
   // Both callbacks execute synchronously and sequentially inside the one
   // actual lexical pull. No RefCell loan survives a callback or another pull.
   let sink=RefCell::new(&mut *sink);let points=RefCell::new(points);
   let token=frame.next_physical_using(provider,a,|notice,bytes|{let location=points.borrow_mut().notice(bytes,notice.point,a)?;sink.borrow_mut().lexical(&identity,occurrence,location,notice,a)},|event,bytes,identity|{
    let span=match &event{super::original_raw_frame::OriginalPhysicalLexeme::FinalNewline{at}=>Span::new(*at,*at),super::original_raw_frame::OriginalPhysicalLexeme::Scalar{token,..}=>token.span,super::original_raw_frame::OriginalPhysicalLexeme::Quote(part)=>part.token_span(),super::original_raw_frame::OriginalPhysicalLexeme::QuoteFailure{recovery,..}=>recovery.token_span()};
    let point=points.borrow_mut().at(bytes,span.start,a)?;let origin=Origin{physical:span,line:point.line,byte_column:Some(point.column),occurrence,invocation:false};
    original_token_factory::project_using(event,bytes,Geometry::Physical{origin,frame:identity},a,&mut|point,notice|{let location=points.borrow_mut().notice(bytes,point,a)?;sink.borrow_mut().numeric(identity,occurrence,location,point,notice,a)})
   })?;
   match token{Some(Some(token))=>{self.last_input=Some(token.origin);return Ok(RawStep::Token(token))},Some(None)=>continue,None=>{
    frame.finish_actual_end(provider,a)?;self.geometries.as_mut_slice()[*geometry_at].actual_eof=true;self.frames.pop();self.stack_changed=true;return Ok(RawStep::NeedInput);
    // Actual file End is the only pop path. A paused/fatal macro demand never
    // calls this method again and therefore never retires an unfinished source.
   }}
  }
 }
}
