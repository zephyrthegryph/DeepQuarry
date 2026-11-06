//! Original raw-token records owned by the EXISTING expanded-origin arena.
//! Physical source-row envelope, raw token extent and actual token point are
//! separate facts. No rounded UTF8 token end or PreparedLine is fabricated.
use super::{ExpandedOriginView,OriginView,MacroExpansion,OriginalByteCursor,original_driver::RawSourceDriver};
use crate::{SourceProvider,SourceAcquisitionLease,SourceAcquisitionIdentity,macro_expansion::{OriginalMacroRows as Rows,OriginalMacroToken as Token}};
use dm_syntax::{Span,SettingAdmission,SettingRootLease};use std::{io,sync::Arc,path::PathBuf};
// Adjacent tokens share only already-authenticated physical row metadata. The
// compact token records remain distinct; grouping never proves a source point.
struct Group{occurrence:usize,binding:SourceAcquisitionIdentity,path:Arc<PathBuf>,trace:Arc<Vec<MacroExpansion>>,decoded:Span,line:usize,output_line:usize,region:usize}
struct Row {
    group: usize,
    output: Span,
    token_end: usize,
    source_offset: usize,
    byte_column: usize,
    raw_extent: Span,
    actual_eof: bool,
}
impl Row {
    fn token_span(&self) -> Span {
        Span::new(self.output.start, self.token_end)
    }

    fn point(&self, line: usize) -> OriginalByteCursor {
        OriginalByteCursor { line, byte_column: self.byte_column, source_offset: self.source_offset }
    }
}
pub(super) struct OriginalRawOrigins{rows:Rows<Row>,groups:Rows<Group>,nonphysical:Rows<Span>,output:Option<super::original_prepared_output::OriginalOutputIdentity>,delivery_sealed:bool,domain:SettingRootLease}
impl std::fmt::Debug for OriginalRawOrigins{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("OriginalRawOrigins").field("rows",&self.rows.len()).finish()}}
impl OriginalRawOrigins{
 pub(super) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{rows:Rows::new(a)?,groups:Rows::new(a)?,nonphysical:Rows::new(a)?,output:None,delivery_sealed:false,domain:a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?})}
 /// The actual controller records once beside its final arena append. The
 /// private actual raw stack authenticates current occurrence/binding/point;
 /// the supplied source path and region come from that SAME DirectivePlan.
 pub(super) fn append_actual_using(&mut self,actual:&Token<'_>,token:Span,output_cover:Span,output_line:usize,region:usize,path:Arc<PathBuf>,trace:Arc<Vec<MacroExpansion>>,lease:&SourceAcquisitionLease,provider:&dyn SourceProvider,inputs:&mut RawSourceDriver,a:&SettingAdmission<'_>)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
  if self.delivery_sealed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"delivered origin rows are already finalized"))}
  if token.start>=token.end||output_cover.start!=token.start||output_cover.end<token.end||self.rows.as_slice().last().is_some_and(|row|row.output.end>output_cover.start){return Err(io::ErrorKind::InvalidInput.into())}
  let source=inputs.physical_row_using(actual.origin,lease,provider,a)?;
  match (&actual.lexical_frame,actual.lexical_span){(Some(frame),Some(_)) if frame.admitted_by(a)=>(),(None,None)=>(),_=>return Err(io::ErrorKind::InvalidData.into())};
  // Share only the immediately preceding metadata group. This is linear in
  // actual output size, with no path/trace dictionary or historical scan. The
  // SAME raw owner has already authenticated every token above.
  let shared=self.groups.as_slice().last().is_some_and(|g|g.occurrence==actual.origin.occurrence&&g.binding.matches(lease)&&g.decoded==source.decoded&&g.line==source.point.line&&g.output_line==output_line&&g.region==region&&Arc::ptr_eq(&g.path,&path)&&Arc::ptr_eq(&g.trace,&trace));
  let group=if shared{self.groups.len()-1}else{let index=self.groups.len();self.groups.push(Group{occurrence:actual.origin.occurrence,binding:lease.identity(),path,trace,decoded:source.decoded,line:source.point.line,output_line,region},a)?;index};
  // Group sharing already requires the same source line, and validation
  // above requires the token and output cover to start at the same byte.
  let row=Row{
   group, output:output_cover, token_end:token.end, source_offset:source.point.source_offset,
   byte_column:source.point.byte_column, raw_extent:actual.origin.physical, actual_eof:source.actual_eof,
  };
  self.rows.push(row,a)
 }

 /// The actual runner binds even an empty stream from its SAME cursor's zero
 /// receipt before lending that producer. No numeric offset issues this owner.
 pub(super) fn bind_output_using(&mut self,initial:&super::original_prepared_output::OriginalDeliveryFrontier,a:&SettingAdmission<'_>)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if self.delivery_sealed||(self.rows.len()!=0||self.nonphysical.len()!=0)||initial.end()!=0||!self.is_admitted_by(a)||!initial.owner().admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}
  match &self.output{Some(owner)if !initial.belongs_to(owner)=>Err(io::ErrorKind::InvalidInput.into()),Some(_)=>Ok(()),None=>{self.output=Some(initial.owner().clone());Ok(())}}
 }
 /// Actual token/interval/line belong to ONE prepared-output record. Pointer
 /// comparison authenticates those two private callback arguments only; source
 /// geometry is independently checked by the SAME raw frame/lease below.
 pub(super) fn append_produced_using(&mut self,actual:&Token<'static>,produced:super::original_prepared_output::OriginalProducedSpan<'_>,region:usize,path:Arc<PathBuf>,trace:Arc<Vec<MacroExpansion>>,lease:&SourceAcquisitionLease,provider:&dyn SourceProvider,inputs:&mut RawSourceDriver,a:&SettingAdmission<'_>)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
  let owner=self.output.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"origin owner lacks its actual output cursor"))?;
  if !owner.same(produced.owner())||!produced.owner().admitted_by(a)||!std::ptr::eq(actual,produced.actual()?){return Err(io::Error::new(io::ErrorKind::InvalidInput,"origin arguments differ from the SAME prepared token"))}
  self.append_actual_using(actual,produced.token().span,produced.cover(),produced.output_line(),region,path,trace,lease,provider,inputs,a)
 }
 /// Only the receiver's actual complete-append receipt can discard producer
 /// lookahead mappings. Acquisitions/notices/history remain genuine lookahead
 /// DATA; trimming mappings cannot grant primary/model/physical EOF.
 /// Authentic receiver coverage for a SAME issued default delimiter. It has
 /// no physical source row/line/column/token extent and is never returned by
 /// geometry/get/point as an origin or CODE grant.
 pub(super) fn append_default_semicolon_using(&mut self,produced:super::original_prepared_output::OriginalProducedSpan<'_>,a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;let owner=self.output.as_ref().ok_or(io::ErrorKind::InvalidInput)?;if self.delivery_sealed||!self.is_admitted_by(a)||!owner.same(produced.owner())||!produced.owner().admitted_by(a)||!produced.is_default_semicolon()||self.rows.len()!=0||self.nonphysical.len()!=0||produced.cover().start!=0{return Err(io::ErrorKind::InvalidInput.into())}self.nonphysical.push(produced.cover(),a)}
 pub(super) fn retain_delivered_using(&mut self,delivered:&super::original_prepared_output::OriginalDeliveryFrontier,a:&SettingAdmission<'_>)->io::Result<usize>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;let owner=self.output.as_ref().ok_or(io::ErrorKind::InvalidInput)?;
  if self.delivery_sealed||!self.is_admitted_by(a)||!delivered.belongs_to(owner)||!delivered.owner().admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}
  let keep=self.rows.as_slice().partition_point(|row|row.output.end<=delivered.end());
  if delivered.end()!=0&&(keep==0||self.rows.as_slice()[keep-1].output.end!=delivered.end())&&!self.nonphysical.as_slice().iter().any(|cover|cover.end==delivered.end()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"delivery receipt is not an actual recorded complete cover"))}
  let groups=if keep==0{0}else{self.rows.as_slice()[keep-1].group.checked_add(1).ok_or(io::ErrorKind::InvalidData)?};self.rows.truncate(keep);self.groups.truncate(groups);let nonphysical=self.nonphysical.as_slice().partition_point(|cover|cover.end<=delivered.end());self.nonphysical.truncate(nonphysical);self.delivery_sealed=true;Ok(keep)
 }
 pub(super) fn has_delivered_binding(&self)->bool{self.output.is_some()&&self.delivery_sealed}
 pub(super) fn is_admitted_by(&self,a:&SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.domain)}
 pub(super) fn geometry(&self,index:usize)->Option<(usize,OriginalByteCursor,Span,Span,bool)>{
  let row=self.rows.as_slice().get(index)?;
  let group=self.groups.as_slice().get(row.group)?;
  Some((group.occurrence,row.point(group.line),row.token_span(),row.raw_extent,row.actual_eof))
 }
 pub(super) fn equivalent(&self,other:&Self)->bool{self.len()==other.len()&&self.nonphysical.as_slice()==other.nonphysical.as_slice()&&(0..self.len()).all(|index|self.geometry(index)==other.geometry(index))}
 pub(super) fn len(&self)->usize{self.rows.len()}
 pub(super) fn get(&self,index:usize)->Option<ExpandedOriginView<'_>>{let row=self.rows.as_slice().get(index)?;let group=self.groups.as_slice().get(row.group)?;Some(ExpandedOriginView{origin:OriginView{output_line:group.output_line,path:&group.path,source_line:group.line},output_span:row.output,source_span:group.decoded,region:group.region,macro_expansions:&group.trace})}
 /// Exact point projection only. Expanded grammar offsets inside a transformed
 /// token must never be mistaken for original source-byte deltas. Genuine raw
 /// EOF additionally lends its actual terminal point at the output boundary.
 pub(super) fn point(&self,index:usize,occurrence:usize,lease:&SourceAcquisitionLease,offset:usize)->Result<OriginalByteCursor,&'static str>{
  let row=self.rows.as_slice().get(index).ok_or("actual raw origin row absent")?;let group=self.groups.as_slice().get(row.group).ok_or("actual raw origin metadata absent")?;if group.occurrence!=occurrence||!group.binding.matches(lease){return Err("actual raw origin belongs to another source acquisition or occurrence")}
  if offset!=row.output.start&&!(row.actual_eof&&(offset==row.token_end||offset==row.output.end)){return Err("expanded byte has no exact issued raw token point")}
  Ok(row.point(group.line))
 }
 pub(super) fn source_end_at(&self,index:usize,offset:usize)->bool{self.rows.as_slice().get(index).is_some_and(|row|row.actual_eof&&(offset==row.output.start||offset==row.token_end||offset==row.output.end))}
 pub(super) fn policy_line(&self,index:usize,occurrence:usize,lease:&SourceAcquisitionLease,offset:usize)->Result<usize,&'static str>{let row=self.rows.as_slice().get(index).ok_or("actual raw origin row absent")?;let group=self.groups.as_slice().get(row.group).ok_or("actual raw origin metadata absent")?;if group.occurrence!=occurrence||!group.binding.matches(lease)||offset<row.output.start||offset>=row.output.end{return Err("actual raw policy point belongs to another input or interval")}Ok(group.line)}
 pub(super) fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
  self.nonphysical.visit_allocation(|p,n|visit(p,self.nonphysical.len()*std::mem::size_of::<Span>(),n));
  if let Some(output)=&self.output{output.visit_storage(&mut visit);}
  self.rows.visit_allocation(|p,n|visit(p,self.rows.len(),n));self.groups.visit_allocation(|p,n|visit(p,self.groups.len(),n));self.domain.visit_counter_storage(|p,n|visit(p,n,n));for group in self.groups.as_slice(){group.binding.visit_storage(|storage|if let crate::source_acquisition::AcquisitionStorage::Object{address,bytes}=storage{visit(address,1,bytes)});}
 }
}

#[cfg(test)]mod tests{
 use super::*;use super::super::{original_driver::{DriverEvent,LogicalToken},original_raw_inputs::OriginalRawNoticeSink,original_macro_source::OriginalMacroHost,original_output_queue::OriginalOutputQueue,original_ordinary_output::OriginalOrdinaryOutput};
 use crate::{InitialEnvironment,macro_expansion::{OriginalMacroOrigin as Origin,OriginalMacroValue as Value,OriginalMacroNotice as MacroNotice}};
 use std::{path::Path,sync::{atomic::{AtomicUsize,Ordering},Arc}};
 struct File{raw:Vec<u8>,lease:SourceAcquisitionLease}
 impl File{fn new(raw:&[u8])->Self{Self{raw:raw.to_vec(),lease:SourceAcquisitionLease::from_raw_original_bytes(raw.to_vec(),17u64)}}}
 impl SourceProvider for File{
  fn initial_environment(&self)->InitialEnvironment{InitialEnvironment::OriginalChecker0290}
  fn read(&self,_:&Path)->Result<String,String>{panic!("raw mapping must not read/prepare another source")}
  fn original_source_bytes<'a>(&'a self,lease:&'a SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{if !lease.same_original_acquisition(&self.lease){return Err(io::ErrorKind::InvalidInput.into())}Ok(Some(&self.raw))}
 }
 struct Notices;
 impl OriginalRawNoticeSink for Notices{
  fn lexical(&mut self,_:&super::super::OriginalLexicalFrameIdentity,_:usize,_:super::super::original_raw_points::OriginalRawPoint,_:super::super::original_raw_frame::OriginalRawNotice,_:&SettingAdmission<'_>)->io::Result<()>{panic!("valid fixture has no lexical notice")}
  fn numeric(&mut self,_:&super::super::OriginalLexicalFrameIdentity,_:usize,_:super::super::original_raw_points::OriginalRawPoint,_:dm_syntax::OriginalLexicalNoticePoint,_:dm_syntax::numeric_form::OriginalNumberNotice<'_>,_:&SettingAdmission<'_>)->io::Result<()>{panic!("valid fixture has no numeric notice")}
 }
 struct Host{ordinary:OriginalOrdinaryOutput}
 impl OriginalMacroHost for Host{
  fn before_identifier(&mut self,name:&str,origin:Origin,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<()>{self.ordinary.before_identifier(name,origin,queue,a)}
  fn ordinary_token(&mut self,token:Token<'static>,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<()>{self.ordinary.ordinary_token(token,queue,a)}
  fn direct_noncall_output(&mut self,token:&Token<'static>,a:&SettingAdmission<'_>)->io::Result<()>{self.ordinary.direct_noncall_output(token,a)}
  fn dynamic(&mut self,_:bool,_:Origin,_:Option<usize>,_:Option<Origin>,_:&SettingAdmission<'_>)->io::Result<Token<'static>>{panic!("fixture has no dynamic macro")}
  fn invocation(&mut self,_:&str,_:Origin,_:&SettingAdmission<'_>)->io::Result<()>{Ok(())}
 }
 fn driver(a:&SettingAdmission<'_>)->RawSourceDriver{RawSourceDriver::new(InitialEnvironment::OriginalChecker0290,&std::collections::BTreeMap::new(),a,&mut|definition,a|super::super::original_token_factory::initial_definition_using(definition,a,&mut|_|panic!("fixed definitions have no lexical notice"),&mut|_,_|panic!("fixed definitions have no numeric notice"))).unwrap()}
 fn next(source:&mut RawSourceDriver,file:&File,host:&mut Host,a:&SettingAdmission<'_>)->Option<Token<'static>>{
  loop{match source.next_logical_using(file,&mut Notices,host,a).unwrap(){DriverEvent::Token(LogicalToken::Actual(token))=>return Some(token),DriverEvent::Token(LogicalToken::Delimiter{spelling,location})=>return Some(Token{value:Value::Punct(spelling),origin:location.expect("actual fixture delimiter point"),string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None}),DriverEvent::ActualEnd=>return None,DriverEvent::NeedInput=>continue,_=>panic!("fixture has no directives or notices")}}
 }
 #[test]fn actual_raw_arena_retains_exact_point_eof_and_credit_until_last_alias(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let file=File::new(b"\xef\xbb\xbfvar/value=7\r\n");let mut source=driver(&a);source.push_opened(&file,file.lease.clone(),0,&a).unwrap();let mut host=Host{ordinary:OriginalOrdinaryOutput::new(&a).unwrap()};let mut rows=OriginalRawOrigins::new(&a).unwrap();
  // One bounded fixture metadata grant, before path/trace/anchor allocations.
  let metadata_credit=a.reserve(1024).unwrap();let path=Arc::new(PathBuf::from("actual-mapping.dm"));let trace=Arc::new(Vec::new());let mut offset=0;
  while let Some(actual)=next(&mut source,&file,&mut host,&a){rows.append_actual_using(&actual,Span::new(offset,offset+1),Span::new(offset,offset+1),1,0,path.clone(),trace.clone(),&file.lease,&file,&mut source,&a).unwrap();offset+=1;}
  assert!(rows.len()>3);let mut saw_end=false;for index in 0..rows.len(){let(occurrence,point,span,_,eof)=rows.geometry(index).unwrap();assert_eq!(occurrence,0);assert_eq!(rows.point(index,0,&file.lease,span.start).unwrap(),point);if eof{saw_end=true;assert_eq!(rows.point(index,0,&file.lease,span.end).unwrap(),point)}else{assert!(rows.point(index,0,&file.lease,span.end).is_err())}}
  assert!(saw_end,"only the actual finished raw input can mark terminal rows");let metadata=dm_syntax::SharedSettingRetention::new(metadata_credit);let arena=super::super::ExpandedOriginArena::from_actual_raw_rows_using(rows,metadata,&a).unwrap();let alias=arena.clone();assert!(arena.same_owner(&alias));assert_eq!(arena.len(),offset);drop((source,host,path,trace,arena));assert!(used.load(Ordering::Acquire)>0,"last mapping alias must still pay for retained rows and metadata");drop(alias);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn actual_raw_arena_rejects_equal_bytes_foreign_acquisition_and_nonexact_offsets(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let file=File::new(b"var/value=7\n");let foreign=File::new(b"var/value=7\n");let mut source=driver(&a);source.push_opened(&file,file.lease.clone(),0,&a).unwrap();let mut host=Host{ordinary:OriginalOrdinaryOutput::new(&a).unwrap()};let actual=next(&mut source,&file,&mut host,&a).unwrap();let mut rows=OriginalRawOrigins::new(&a).unwrap();let credit=a.reserve(1024).unwrap();let path=Arc::new(PathBuf::from("same.dm"));let trace=Arc::new(Vec::new());rows.append_actual_using(&actual,Span::new(0,4),Span::new(0,5),1,0,path,trace,&file.lease,&file,&mut source,&a).unwrap();assert!(rows.point(0,0,&foreign.lease,0).is_err());assert!(rows.point(0,1,&file.lease,0).is_err());assert!(rows.point(0,0,&file.lease,1).is_err());assert_eq!(rows.policy_line(0,0,&file.lease,3).unwrap(),1);assert!(rows.policy_line(0,0,&foreign.lease,3).is_err());drop((rows,source,host,credit));assert!(used.load(Ordering::Acquire)>0,"the still-owned emitted token must retain its own text credit");drop(actual);assert_eq!(used.load(Ordering::Acquire),0);
 }
 struct OutputCredit{bytes:std::sync::atomic::AtomicUsize,live:Arc<std::sync::atomic::AtomicUsize>}
 impl Drop for OutputCredit{fn drop(&mut self){self.live.fetch_sub(self.bytes.load(std::sync::atomic::Ordering::Acquire),std::sync::atomic::Ordering::AcqRel);}}
 impl crate::source_arena_credit::SourceArenaCreditOwner for OutputCredit{fn as_any(&self)->&dyn std::any::Any{self}fn reserved_bytes(&self)->usize{self.bytes.load(std::sync::atomic::Ordering::Acquire)}fn visit_storage(&self,_:&mut dyn FnMut(usize,usize)){}}
 struct OutputWork(Arc<std::sync::atomic::AtomicUsize>);
 impl crate::source_arena_credit::SourceArenaWork for OutputWork{
  fn checkpoint(&self)->io::Result<()>{Ok(())}fn reserve(&self,n:usize)->io::Result<crate::source_arena_credit::SourceArenaCredit>{self.0.fetch_add(n,std::sync::atomic::Ordering::AcqRel);Ok(crate::source_arena_credit::SourceArenaCredit::from_resource_owner(Arc::new(OutputCredit{bytes:std::sync::atomic::AtomicUsize::new(n),live:self.0.clone()})))}
  fn grow(&self,c:&mut crate::source_arena_credit::SourceArenaCredit,n:usize)->io::Result<()>{let own=c.owner().as_any().downcast_ref::<OutputCredit>().ok_or(io::ErrorKind::InvalidInput)?;if !Arc::ptr_eq(&own.live,&self.0){return Err(io::ErrorKind::InvalidInput.into())}own.bytes.fetch_add(n,std::sync::atomic::Ordering::AcqRel);self.0.fetch_add(n,std::sync::atomic::Ordering::AcqRel);Ok(())}
  fn shrink(&self,c:&mut crate::source_arena_credit::SourceArenaCredit,n:usize)->io::Result<()>{let own=c.owner().as_any().downcast_ref::<OutputCredit>().ok_or(io::ErrorKind::InvalidInput)?;if !Arc::ptr_eq(&own.live,&self.0){return Err(io::ErrorKind::InvalidInput.into())}own.bytes.fetch_update(std::sync::atomic::Ordering::AcqRel,std::sync::atomic::Ordering::Acquire,|v|v.checked_sub(n)).map_err(|_|io::ErrorKind::InvalidInput)?;self.0.fetch_sub(n,std::sync::atomic::Ordering::AcqRel);Ok(())}
 }
 #[test]fn actual_receiver_receipt_trims_raw_eof_lookahead_without_claiming_consumed_eof_and_rejects_foreign_same_end(){
  use super::super::{original_prepared_output::OriginalOutputCursor,original_source_arena::OriginalSourceArena};
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let file=File::new(b"/datum/x\n");let mut source=driver(&a);source.push_opened(&file,file.lease.clone(),0,&a).unwrap();let mut host=Host{ordinary:OriginalOrdinaryOutput::new(&a).unwrap()};let metadata=a.reserve(1024).unwrap();let path=Arc::new(PathBuf::from("delivery.dm"));let trace=Arc::new(Vec::new());let mut cursor=OriginalOutputCursor::new(&a).unwrap();let initial=cursor.initial_delivery().unwrap();let mut rows=OriginalRawOrigins::new(&a).unwrap();rows.bind_output_using(&initial,&a).unwrap();let mut prepared=Vec::new();
  while let Some(actual)=next(&mut source,&file,&mut host,&a){let item=cursor.prepare(actual,&file,&a).unwrap();rows.append_produced_using(item.actual().unwrap(),item.produced(),0,path.clone(),trace.clone(),&file.lease,&file,&mut source,&a).unwrap();prepared.push(item);}
  assert!(rows.len()>1);assert!((0..rows.len()).any(|at|rows.geometry(at).unwrap().4),"producer genuinely reached raw EOF before receiver starts");
  // A different actual cursor/receiver produces the SAME first span. Matching
  // numbers do not authorize trimming this producer's retained mappings.
  let mut foreign=OriginalOutputCursor::new(&a).unwrap();let foreign_item=foreign.prepare(prepared[0].actual().unwrap().duplicate(&a).unwrap(),&file,&a).unwrap();let work=OutputWork(Arc::new(AtomicUsize::new(0)));let mut foreign_arena=OriginalSourceArena::new(&work).unwrap();let mut foreign_primary=dm_syntax::OriginalPrimaryDemand::new(&a,None).unwrap();let(foreign_token,foreign_receipt)=foreign_item.into_delivery().adopt(&mut foreign_arena,&mut foreign_primary,&foreign.identity(),&a).unwrap();assert!(rows.retain_delivered_using(&foreign_receipt,&a).is_err());
  let mut arena=OriginalSourceArena::new(&work).unwrap();let mut primary=dm_syntax::OriginalPrimaryDemand::new(&a,None).unwrap();let(first,receipt)=prepared.remove(0).into_delivery().adopt(&mut arena,&mut primary,&cursor.identity(),&a).unwrap();assert_eq!(receipt.end(),foreign_receipt.end());let keep=rows.retain_delivered_using(&receipt,&a).unwrap();assert_eq!(keep,1);assert_eq!(rows.len(),1);assert!(!rows.geometry(0).unwrap().4,"unreceived producer EOF cannot become received output EOF");assert!(rows.has_delivered_binding());assert!(rows.retain_delivered_using(&receipt,&a).is_err());let item=&prepared[0];assert!(rows.append_produced_using(item.actual().unwrap(),item.produced(),0,path.clone(),trace.clone(),&file.lease,&file,&mut source,&a).is_err());drop((source,host,rows,cursor,initial,prepared,first,receipt,foreign_token,foreign_receipt,foreign,foreign_primary,primary,arena,foreign_arena,path,trace,metadata));assert_eq!(used.load(Ordering::Acquire),0);assert_eq!(work.0.load(Ordering::Acquire),0);
 }
 #[test]fn same_actual_empty_delivery_discards_all_unreceived_rows_but_foreign_zero_cannot_bind(){
  use super::super::original_prepared_output::OriginalOutputCursor;let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let cursor=OriginalOutputCursor::new(&a).unwrap();let actual=cursor.initial_delivery().unwrap();let foreign=OriginalOutputCursor::new(&a).unwrap();let mut rows=OriginalRawOrigins::new(&a).unwrap();rows.bind_output_using(&actual,&a).unwrap();assert!(rows.bind_output_using(&foreign.initial_delivery().unwrap(),&a).is_err());assert_eq!(rows.retain_delivered_using(&actual,&a).unwrap(),0);assert!(rows.has_delivered_binding());drop((rows,actual,cursor,foreign));assert_eq!(used.load(Ordering::Acquire),0);
 }

}
