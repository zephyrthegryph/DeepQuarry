//! The actual physical source stack lent to the SAME macro cursor. Opening is
//! supplied by the existing bounded RecordingInputs acquisition/adoption path;
//! this module never substitutes PreparedSource, text equality or a private read.
use super::{original_raw_frame::{OriginalRawFrame,OriginalRawNotice},original_raw_points::OriginalRawPointIndex,original_token_factory::{self,Geometry},original_lexical_frame::OriginalLexicalFrameIdentity};
use crate::{SourceProvider,SourceAcquisitionLease,macro_expansion::{OriginalMacroRows as Rows,OriginalPagedMacroRows as PagedRows,OriginalMacroToken as Token,OriginalMacroOrigin as Origin,OriginalMacroRawStep as RawStep}};
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
#[derive(Clone,Copy)]
pub(super) struct OriginalPhysicalRow{pub(super) raw:Span,pub(super) decoded:Span,pub(super) point:super::OriginalByteCursor,pub(super) actual_eof:bool}
/// Short-lived actual lender observation. No retained source owner or
/// authorization to skip a later current-source loan.
pub(super) struct OriginalPhysicalRowObservation<'source>{
 origin:Origin,
 geometry_at:usize,
 lease:&'source SourceAcquisitionLease,
 bytes:&'source [u8],
 row:OriginalPhysicalRow,
}
impl OriginalPhysicalRowObservation<'_>{
 pub(super) fn row(&self)->&OriginalPhysicalRow{&self.row}
 pub(super) fn into_row(self)->OriginalPhysicalRow{self.row}
}
/// One actual producer-local boundary pair, never a byte/source grant.
#[derive(Clone,Copy)]
struct DecodedRowBoundary{geometry_at:usize,raw:Span,decoded:Span}
pub(super) struct OriginalRawInputs{frames:Rows<OpenFrame>,geometries:PagedRows<SourceGeometry>,failed:bool,stack_changed:bool,last_input:Option<Origin>,last_decoded_row:Option<DecodedRowBoundary>}
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
impl OriginalRawInputs{
 pub(super) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{frames:Rows::new(a)?,geometries:PagedRows::new(a)?,failed:false,stack_changed:false,last_input:None,last_decoded_row:None})}
 #[cfg(debug_assertions)]
 pub(super) fn trace_line_starts(&self) -> super::original_raw_points::PhysicalLineStartCensus {
  let mut census = super::original_raw_points::PhysicalLineStartCensus::default();
  for geometry in self.geometries.iter() {
   geometry.points.record_line_starts(&mut census);
  }
  census
 }
 /// The caller has already funded/read/adopted this SAME acquisition through
 /// the host's actual source-family lender. No frame-pop refunds that backing.
 pub(super) fn push_opened(&mut self,provider:&dyn SourceProvider,acquisition:SourceAcquisitionLease,occurrence:usize,expansion_floor:usize,a:&SettingAdmission<'_>)->io::Result<()>{
  if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let result=(||{poll(a)?;if self.geometries.last().is_some_and(|prior|prior.occurrence>=occurrence){return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw source occurrences must follow the actual unique open order"))}let bytes=provider.original_source_bytes(&acquisition)?.ok_or(io::ErrorKind::NotConnected)?;let points=OriginalRawPointIndex::new(bytes,a)?;let geometry=super::original_raw_geometry::OriginalRawGeometry::from_acquired_using(provider,&acquisition,a)?;let frame=OriginalRawFrame::from_opened(provider,acquisition,a)?;let geometry_at=self.geometries.len();self.geometries.push(SourceGeometry{occurrence,geometry,points,actual_eof:false},a)?;self.frames.push(OpenFrame{frame,path:None,geometry_at,occurrence,expansion_floor},a)})();if result.is_err(){self.failed=true}result
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
  if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let result=(||{poll(a)?;let Some(open)=self.frames.last_mut()else{return Ok(None)};let point=open.frame.read_point().ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual current raw reader has not issued a location"))?;let identity=open.frame.identity();let bytes=provider.original_source_bytes(identity.acquisition())?.ok_or(io::ErrorKind::NotConnected)?;let actual=self.geometries.get_mut(open.geometry_at).expect("opened source geometry").points.notice(bytes,point,a)?;run(identity,open.occurrence,actual).map(Some)})();if result.is_err(){self.failed=true}result
 }
 /// Decode the END of the same short-lived observation. The observation
 /// already selected its actual occurrence, so no second roster search is
 /// needed. The original admission, exact lease and coordinate checks remain.
 pub(super) fn decoded_observed_end_using(&self,observed:&OriginalPhysicalRowObservation<'_>,a:&SettingAdmission<'_>)->io::Result<usize>{
  if self.failed{return Err(io::ErrorKind::InvalidInput.into())}
  let row=self.geometries.get(observed.geometry_at)
   .filter(|row|row.occurrence==observed.origin.occurrence)
   .ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"raw mapping occurrence was never opened"))?;
  row.geometry.decoded_point_using(observed.lease,observed.origin.physical.end,a)
 }
 /// One actual raw-token point plus physical source-line envelope. The row
 /// end is a real LF/physical byte EOF boundary, never a rounded token end.
 #[cfg(test)]
 pub(super) fn physical_row_using(&mut self,origin:Origin,lease:&SourceAcquisitionLease,provider:&dyn SourceProvider,a:&SettingAdmission<'_>)->io::Result<OriginalPhysicalRow>{
  self.observe_physical_row_using(origin,lease,provider,None,a).map(OriginalPhysicalRowObservation::into_row)
 }
 pub(super) fn observe_physical_row_using<'source>(&mut self,origin:Origin,lease:&'source SourceAcquisitionLease,provider:&'source dyn SourceProvider,prior:Option<&OriginalPhysicalRowObservation<'_>>,a:&SettingAdmission<'_>)->io::Result<OriginalPhysicalRowObservation<'source>>{
  #[cfg(feature="original-fill-sample")]
  let _sample=super::original_fill_sample::scope(super::original_fill_sample::Bucket::Coordinate);
  if self.failed{return Err(io::ErrorKind::InvalidInput.into())}poll(a)?;
  let geometries = &self.geometries;
  let active = self.frames.as_slice().last().filter(|open| {
   open.occurrence == origin.occurrence
    && geometries.get(open.geometry_at).is_some_and(|row| row.occurrence == origin.occurrence)
  });
  // Ordinary tokens are in the current raw frame. Macro definitions and
  // earlier includes can still address any exact, previously opened frame.
  let at = match active {
   Some(open) => open.geometry_at,
   None => {
    let mut first = 0;
    let mut end = geometries.len();
    while first < end {
     let mid = first + (end - first) / 2;
     if geometries.get(mid).expect("issued source geometry ordinal").occurrence < origin.occurrence {
      first = mid + 1;
     } else {
      end = mid;
     }
    }
    if geometries.get(first).is_none_or(|row| row.occurrence != origin.occurrence) {
     return Err(io::ErrorKind::InvalidInput.into());
    }
    first
   }
  };
  let geometry=&mut self.geometries.get_mut(at).expect("located source geometry");let raw=original_fill_bucket!(Provider,provider.original_source_bytes(lease))?.ok_or(io::ErrorKind::NotConnected)?;
  let offset=origin.physical.start;let eof_token=!origin.invocation&&origin.physical.start==origin.physical.end&&offset==raw.len()&&geometry.actual_eof;
  if let Some(prior)=prior.filter(|prior|prior.origin==origin&&prior.lease.same_binding(lease)
   &&std::ptr::eq(prior.bytes,raw)&&prior.row.actual_eof==eof_token
   &&geometry.geometry.matches_context(lease,a)
   &&geometry.points.contains_issued_row(raw.len(),offset,origin.line,prior.row.raw)){
   // The second lender call succeeded at its original boundary. Keep the
   // line-end checkpoint and all three decoded-point checkpoints. A provider
   // refusal or cancellation at any of those boundaries must still win.
   poll(a)?;
   poll(a)?;
   poll(a)?;
   poll(a)?;
   return Ok(OriginalPhysicalRowObservation{origin,geometry_at:at,lease,bytes:raw,row:prior.row})
  }
  // A real final-newline token is issued one column after the tracker EOF.
  // Error notices retain their separate EOF tracker point (column before it).
  let point=geometry.points.at(raw,offset,a)?;
  if point.line!=origin.line||Some(point.column)!=origin.byte_column{return Err(io::Error::new(io::ErrorKind::InvalidInput,"source-map origin differs from the actual raw point roster"))}
  let start=geometry.points.line_start(point.line).ok_or(io::ErrorKind::InvalidData)?;
  let end=geometry.points.line_end_using(raw,point.line,a)?;
  let raw_span=Span::new(start,end);
  let decoded=if let Some(prior)=self.last_decoded_row.filter(|prior|prior.geometry_at==at&&prior.raw==raw_span){
   // The append-only geometry roster owns the same immutable decoder at
   // this ordinal. The actual provider and both old checkpoints/identity
   // checks still run before either cached endpoint is used.
   geometry.geometry.check_point_using(lease,start,a)?;
   geometry.geometry.check_point_using(lease,end,a)?;
   prior.decoded
  }else{
   let decoded_start=geometry.geometry.decoded_point_using(lease,start,a)?;
   let decoded_end=geometry.geometry.decoded_point_using(lease,end,a)?;
   Span::new(decoded_start,decoded_end)
  };
  let decoded_point=geometry.geometry.decoded_point_using(lease,offset,a)?;
  self.last_decoded_row=Some(DecodedRowBoundary{geometry_at:at,raw:raw_span,decoded});
  let row=OriginalPhysicalRow{raw:raw_span,decoded,point:super::OriginalByteCursor{line:point.line,byte_column:point.column,source_offset:decoded_point},actual_eof:eof_token};
  Ok(OriginalPhysicalRowObservation{origin,geometry_at:at,lease,bytes:raw,row})
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
   let OpenFrame{frame,geometry_at,occurrence,..}=open;let points=&mut self.geometries.get_mut(*geometry_at).expect("opened source geometry").points;let occurrence=*occurrence;
   // Both callbacks execute synchronously and sequentially inside the one
   // actual lexical pull. No RefCell loan survives a callback or another pull.
   let sink=RefCell::new(&mut *sink);let points=RefCell::new(points);
   let token=frame.next_physical_using(provider,a,|notice,bytes,identity|{let location=points.borrow_mut().notice(bytes,notice.point,a)?;sink.borrow_mut().lexical(identity,occurrence,location,notice,a)},|event,bytes,identity|{
    let span=match &event{super::original_raw_frame::OriginalPhysicalLexeme::FinalNewline{at}=>Span::new(*at,*at),super::original_raw_frame::OriginalPhysicalLexeme::Scalar{token,..}=>token.span,super::original_raw_frame::OriginalPhysicalLexeme::Quote(part)=>part.token_span(),super::original_raw_frame::OriginalPhysicalLexeme::QuoteFailure{recovery,..}=>recovery.token_span()};
    let point=original_fill_bucket!(Coordinate,points.borrow_mut().at(bytes,span.start,a))?;let origin=Origin{physical:span,line:point.line,byte_column:Some(point.column),occurrence,invocation:false};
    original_token_factory::project_using(event,bytes,Geometry::Physical{origin,frame:identity},a,&mut|point,notice|{let location=points.borrow_mut().notice(bytes,point,a)?;sink.borrow_mut().numeric(identity,occurrence,location,point,notice,a)})
   })?;
   match token{Some(Some(token))=>{self.last_input=Some(token.origin);return Ok(RawStep::Token(token))},Some(None)=>continue,None=>{
    frame.finish_actual_end(provider,a)?;self.geometries.get_mut(*geometry_at).expect("opened source geometry").actual_eof=true;self.frames.pop();self.stack_changed=true;return Ok(RawStep::NeedInput);
    // Actual file End is the only pop path. A paused/fatal macro demand never
    // calls this method again and therefore never retires an unfinished source.
   }}
  }
 }
}

#[cfg(test)]
mod row_tests {
    use super::*;
    use std::{cell::Cell, path::Path, sync::{atomic::{Ordering}}};

    struct File {
        bytes: Vec<u8>,
        lease: SourceAcquisitionLease,
        failure: Cell<Option<i32>>,
    }
    impl SourceProvider for File {
        fn read(&self, _: &Path) -> Result<String, String> {
            panic!("actual row may only borrow its opened acquisition")
        }

        fn original_source_bytes<'a>(&'a self, lease: &'a SourceAcquisitionLease) -> io::Result<Option<&'a [u8]>> {
            if let Some(code)=self.failure.get() {
                return Err(io::Error::from_raw_os_error(code));
            }
            if !self.lease.same_binding(lease) {
                return Err(io::ErrorKind::InvalidInput.into());
            }
            Ok(Some(&self.bytes))
        }
    }

    #[test]
    fn observed_definition_end_reuses_only_its_exact_slot_and_preserves_first_error() {
        let bytes="café\n".as_bytes();
        let make=||File{bytes:bytes.to_vec(),lease:SourceAcquisitionLease::from_raw_original_bytes(bytes.to_vec(),()),failure:Cell::new(None)};
        let file=make();
        let foreign=make();
        let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let polls=Cell::new(0);
        let checkpoint=||{polls.set(polls.get()+1);Ok(())};
        let a=SettingAdmission::new(&used,1<<20,&checkpoint);
        let mut inputs=OriginalRawInputs::new(&a).unwrap();
        let mut other=OriginalRawInputs::new(&a).unwrap();
        inputs.push_opened(&file,file.lease.clone(),7,0,&a).unwrap();
        other.push_opened(&foreign,foreign.lease.clone(),7,0,&a).unwrap();
        let origin=Origin{physical:Span::new(0,5),line:1,byte_column:Some(1),occurrence:7,invocation:false};
        let row=inputs.observe_physical_row_using(origin,&file.lease,&file,None,&a).unwrap();
        let interior=inputs.observe_physical_row_using(Origin{physical:Span::new(0,4),..origin},&file.lease,&file,None,&a).unwrap();
        let before=polls.get();
        // A definition end never makes a second provider loan.
        file.failure.set(Some(1450));
        assert_eq!(inputs.decoded_observed_end_using(&row,&a).unwrap(),5);
        assert_eq!(polls.get()-before,1);
        assert_eq!(inputs.decoded_observed_end_using(&interior,&a).unwrap_err().kind(),io::ErrorKind::Unsupported);
        assert_eq!(other.decoded_observed_end_using(&row,&a).unwrap_err().kind(),io::ErrorKind::InvalidInput,
            "same slot and bytes from a foreign acquisition cannot authorize a decoded point");
        let actual=||Err(io::Error::from_raw_os_error(1451));
        let failed=SettingAdmission::new(&used,1<<20,&actual);
        assert_eq!(inputs.decoded_observed_end_using(&row,&failed).unwrap_err().raw_os_error(),Some(1451));
        assert_eq!(inputs.observe_physical_row_using(origin,&file.lease,&file,None,&a).err().unwrap().raw_os_error(),Some(1450),
            "the next actual row observation still requires the real provider");
        drop((inputs,other));
        assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn warm_row_reuse_preserves_checkpoint_order_and_rejects_a_changed_loan_view() {
        let bytes=b"var/example\r\nnext";
        let file=File{bytes:bytes.to_vec(),lease:SourceAcquisitionLease::from_raw_original_bytes(bytes.to_vec(),()),failure:Cell::new(None)};
        let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let polls=Cell::new(0);
        let fail_at=Cell::new(None);
        let checkpoint=||{
            polls.set(polls.get()+1);
            if fail_at.get()==Some(polls.get()){Err(io::Error::from_raw_os_error(1451))}else{Ok(())}
        };let a=SettingAdmission::new(&used,1<<20,&checkpoint);
        let mut inputs=OriginalRawInputs::new(&a).unwrap();
        inputs.push_opened(&file,file.lease.clone(),0,0,&a).unwrap();
        let RawStep::Token(actual)=inputs.next_using(&file,&a,&mut NoNotices).unwrap()else{panic!("actual source token")};
        let first=inputs.observe_physical_row_using(actual.origin,&file.lease,&file,None,&a).unwrap();
        for prior in [None,Some(&first)]{
            polls.set(0);
            let observed=inputs.observe_physical_row_using(actual.origin,&file.lease,&file,prior,&a).unwrap();
            assert_eq!(observed.row.raw,first.row.raw);
            assert_eq!(observed.row.decoded,first.row.decoded);
            assert_eq!(observed.row.point,first.row.point);
            assert_eq!(polls.get(),5,"one before the provider loan, four after it");
        }

        struct ChangedView<'a>{bytes:&'a[u8],calls:Cell<usize>}
        impl SourceProvider for ChangedView<'_>{
            fn read(&self,_:&Path)->Result<String,String>{panic!("no filesystem re-open")}
            fn original_source_bytes<'a>(&'a self,_:&'a SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{
                self.calls.set(self.calls.get()+1);
                Ok(Some(self.bytes))
            }
        }
        let shorter=ChangedView{bytes:&file.bytes[..1],calls:Cell::new(0)};
        let failed=inputs.observe_physical_row_using(actual.origin,&file.lease,&shorter,Some(&first),&a).err().unwrap();
        assert_eq!(failed.kind(),io::ErrorKind::InvalidInput);
        assert_eq!(shorter.calls.get(),1,"fallback validates the second loan itself");

        polls.set(0);
        fail_at.set(Some(5));
        let failed=inputs.observe_physical_row_using(actual.origin,&file.lease,&file,Some(&first),&a).err().unwrap();
        assert_eq!(failed.raw_os_error(),Some(1451));
        assert_eq!(polls.get(),5,"the last decoded-point checkpoint still fails");
        drop((actual,inputs));
        assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }

    struct NoNotices;
    impl OriginalRawNoticeSink for NoNotices {
        fn lexical(&mut self, _: &OriginalLexicalFrameIdentity, _: usize, _: super::super::original_raw_points::OriginalRawPoint, _: OriginalRawNotice, _: &SettingAdmission<'_>) -> io::Result<()> {
            panic!("valid fixture has no lexical notice")
        }

        fn numeric(&mut self, _: &OriginalLexicalFrameIdentity, _: usize, _: super::super::original_raw_points::OriginalRawPoint, _: OriginalLexicalNoticePoint, _: OriginalNumberNotice<'_>, _: &SettingAdmission<'_>) -> io::Result<()> {
            panic!("valid fixture has no numeric notice")
        }
    }

    #[test]
    fn active_and_older_physical_rows_keep_their_actual_opened_geometry() {
        let open = |bytes: &[u8]| File {
            bytes: bytes.to_vec(),
            lease: SourceAcquisitionLease::from_raw_original_bytes(bytes.to_vec(), ()),
            failure: Cell::new(None),
        };
        let parent = open(b"var/parent\nnext");
        let child = open(b"var/included_child\r\nnext");
        let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut inputs = OriginalRawInputs::new(&a).unwrap();
        inputs.push_opened(&parent, parent.lease.clone(), 2, 0, &a).unwrap();
        let RawStep::Token(outer) = inputs.next_using(&parent, &a, &mut NoNotices).unwrap()
            else { panic!("parent token") };
        inputs.push_opened(&child, child.lease.clone(), 9, 0, &a).unwrap();
        let RawStep::Token(inner) = inputs.next_using(&child, &a, &mut NoNotices).unwrap()
            else { panic!("included token") };
        assert_eq!(inputs.current_occurrence(), Some(9));
        assert_eq!(inputs.physical_row_using(inner.origin, &child.lease, &child, &a).unwrap().raw, Span::new(0, 20));
        assert_eq!(inputs.physical_row_using(outer.origin, &parent.lease, &parent, &a).unwrap().raw, Span::new(0, 11));
        let Err(wrong) = inputs.physical_row_using(outer.origin, &child.lease, &child, &a)
            else { panic!("an active lease cannot authenticate an older row") };
        assert_eq!(wrong.kind(), io::ErrorKind::InvalidInput);
        drop((inputs, inner, outer));
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn paged_geometries_keep_older_issued_points_and_page_boundary_order() {
        let open = |bytes: &[u8]| File {
            bytes: bytes.to_vec(),
            lease: SourceAcquisitionLease::from_raw_original_bytes(bytes.to_vec(), ()),
            failure: Cell::new(None),
        };
        let first = open(b"var/old\r\n");
        let later = open(b"var/new\n");
        let fixed = dm_syntax::SettingChargeCounter::root_allocation_bytes();
        let used = dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut inputs = OriginalRawInputs::new(&a).unwrap();
        let mut sampled = Vec::new();
        for i in 0..258 {
            let file = if i == 0 { &first } else { &later };
            inputs.push_opened(file,file.lease.clone(),i*2,0,&a).unwrap();
            let RawStep::Token(token) = inputs.next_using(file,&a,&mut NoNotices).unwrap()
                else { panic!("actual first token"); };
            if matches!(i,0|127|128|255|256|257) { sampled.push((i,token.origin)); }
            while inputs.current_occurrence().is_some() {
                inputs.next_using(file,&a,&mut NoNotices).unwrap();
            }
        }
        assert_eq!(inputs.geometries.len(),258);
        for (i, origin) in sampled {
            let file = if i==0 { &first } else { &later };
            let row = inputs.physical_row_using(origin,&file.lease,file,&a).unwrap();
            assert_eq!(row.raw,Span::new(0,file.bytes.len()));
            let missing = Origin { occurrence: i*2+1, ..origin };
            assert_eq!(inputs.physical_row_using(missing,&file.lease,file,&a).err().unwrap().kind(),io::ErrorKind::InvalidInput);
        }
        drop(inputs);
        assert_eq!(used.load(Ordering::Acquire),fixed);
    }

    #[test]
    fn cached_row_boundaries_keep_exact_same_file_and_first_io() {
        let bytes=b"var/example\r\nnext";
        let file=File{bytes:bytes.to_vec(),lease:SourceAcquisitionLease::from_raw_original_bytes(bytes.to_vec(),()),failure:Cell::new(None)};
        let fixed=dm_syntax::SettingChargeCounter::root_allocation_bytes();
        let used=dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();
        let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
        let mut inputs=OriginalRawInputs::new(&a).unwrap();
        inputs.push_opened(&file,file.lease.clone(),0,0,&a).unwrap();
        let RawStep::Token(actual)=inputs.next_using(&file,&a,&mut NoNotices).unwrap()
            else{panic!("actual opened source token")};
        let cold=inputs.physical_row_using(actual.origin,&file.lease,&file,&a).unwrap();
        let second=Origin{physical:Span::new(1,2),byte_column:Some(2),..actual.origin};
        let warm=inputs.physical_row_using(second,&file.lease,&file,&a).unwrap();
        assert_eq!((warm.raw,warm.decoded),(cold.raw,cold.decoded));
        assert_eq!(warm.point.source_offset,1);
        let visits=Cell::new(0);
        let failing=||{
            visits.set(visits.get()+1);
            if visits.get()==4{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}
        };
        let fault=SettingAdmission::new(&used,1<<20,&failing);
        assert_eq!(inputs.physical_row_using(second,&file.lease,&file,&fault).err().unwrap().raw_os_error(),Some(1450));
        assert_eq!(visits.get(),4,"same second endpoint checkpoint still wins");
        file.failure.set(Some(32));
        assert_eq!(inputs.physical_row_using(second,&file.lease,&file,&a).err().unwrap().raw_os_error(),Some(32));
        drop((actual, inputs));
        assert_eq!(used.load(Ordering::Acquire),fixed);
    }

    #[test]
    fn warm_physical_row_still_demands_the_actual_source_loan() {
        let bytes=b"var/example\r\nnext";
        let file=File{
            bytes:bytes.to_vec(),
            lease:SourceAcquisitionLease::from_raw_original_bytes(bytes.to_vec(),()),
            failure:Cell::new(None),
        };
        let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
        let mut inputs=OriginalRawInputs::new(&a).unwrap();
        inputs.push_opened(&file,file.lease.clone(),0,0,&a).unwrap();
        let RawStep::Token(actual)=inputs.next_using(&file,&a,&mut NoNotices).unwrap()
            else { panic!("actual opened source token") };
        let observed=inputs.observe_physical_row_using(actual.origin,&file.lease,&file,None,&a).unwrap();
        let row=observed.row();
        assert_eq!(row.raw,Span::new(0,13));
        assert_eq!(row.decoded,Span::new(0,13));
        assert!(!row.actual_eof);
        file.failure.set(Some(1450));
        let Err(error)=inputs.observe_physical_row_using(actual.origin,&file.lease,&file,Some(&observed),&a)
            else { panic!("cached row geometry must not hide the real provider failure") };
        assert_eq!(error.raw_os_error(),Some(1450));
        drop((actual,inputs));
        assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }
}
