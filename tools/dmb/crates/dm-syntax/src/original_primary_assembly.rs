//! Retained assembly over the SAME primary layout, frame and commit kernels.
//! This internal DATA owner cannot issue acquisition, EOF or frontend roles.
use super::*;
use std::io;
use super::{demand_frames::NativeOriginalPrimaryFrames,demand_layout::NativeDemandLayoutCursor};

/// Owned SAME live primary-header locator. It shares the existing actual
/// layout resource owner (no new nonce/cache), never an arena/token borrow.
/// It is parser DATA only; frontend source/model grants remain separate.
#[derive(Clone)]pub struct OriginalPrimaryLiveHeader{
 owner:super::demand_layout::NativePrimaryLayoutIdentity,
 header:Span,open:Span,open_ordinal:usize,indent:usize,kind:ItemKind,prior_outer:Option<usize>,
}
impl OriginalPrimaryLiveHeader{
 pub fn start(&self)->usize{self.header.start}
 pub(super) fn matches_owner(&self,owner:&super::demand_layout::NativePrimaryLayoutIdentity)->bool{self.owner.same(owner)}
 pub fn header_prefix_span(&self)->Span{self.header}pub fn argument_start(&self)->usize{self.open.end}pub fn open_span(&self)->Span{self.open}pub fn kind(&self)->ItemKind{self.kind}pub fn prior_outer_block(&self)->Option<usize>{self.prior_outer}
}
pub struct OriginalPrimaryDemand<'a,'observer,'budget>{
 frames:Option<NativeOriginalPrimaryFrames<'a,'budget>>,
 layout:Option<NativeDemandLayoutCursor<'a,'budget>>,
 tokens:Vec<SpanToken>,diagnostics:Vec<Diagnostic>,lexical:Vec<Diagnostic>,literal_facts:OriginalPrimaryLiteralFacts,literal_facts_issued:bool,
 frontier:usize,ended:bool,failed:bool,
 // Physical rows above are destroyed before the actual root below.
 original:OriginalParseState<'a,'observer,'budget>,
}
impl<'a,'observer,'budget> OriginalPrimaryDemand<'a,'observer,'budget>{
 pub fn new(a:&'a crate::SettingAdmission<'budget>,observer:Option<&'observer mut dyn OriginalDeclarationHeaderObserver>)->io::Result<Self>{
  let original=OriginalParseState{storage:original_storage::Storage::new(a)?,fatal:Default::default(),unavailable:Default::default(),operational:Default::default(),observer:observer.map(std::cell::RefCell::new),observer_stop:Default::default(),first_outer_block:Default::default()};
  Ok(Self{frames:Some(NativeOriginalPrimaryFrames::new(a)?),layout:Some(NativeDemandLayoutCursor::new(a)?),tokens:Vec::new(),diagnostics:Vec::new(),lexical:Vec::new(),literal_facts:OriginalPrimaryLiteralFacts::new(a)?,literal_facts_issued:true,frontier:0,ended:false,failed:false,original})
 }
 /// Issue only after actual structural HeaderStart has established the
 /// current frame, and the SAME native token stream reaches callable '('.
 /// No following formal/default/body token is demanded by this operation.
 pub fn live_callable_header(&self,source:&str)->io::Result<Option<OriginalPrimaryLiveHeader>>{
  if self.failed||self.ended||self.original.stopped(){return Err(io::ErrorKind::InvalidInput.into())}
  let Some((start,indent,in_body,prior_outer))=self.frames.as_ref().ok_or(io::ErrorKind::InvalidInput)?.live_header_scope(&self.original)?else{return Ok(None)};if in_body{return Ok(None)}
  if source.len()!=self.frontier{return Err(io::ErrorKind::InvalidInput.into())}let first=self.tokens.partition_point(|token|token.span.end<=start);
  let Some((ordinal,open))=self.tokens.iter().enumerate().skip(first).find(|(_,token)|matches!(token.kind,TokenKind::Punctuation|TokenKind::Operator)&&token.text(source)=="(")else{return Ok(None)};
  let header=Span::new(start,open.span.end);let kind=classify_primary_header(source,&self.tokens,header,false);if !matches!(kind,ItemKind::Proc|ItemKind::Verb){return Ok(None)}
  Ok(Some(OriginalPrimaryLiveHeader{owner:self.layout.as_ref().ok_or(io::ErrorKind::InvalidInput)?.identity(),header,open:open.span,open_ordinal:ordinal,indent,kind,prior_outer}))
 }
 /// Neutral live DATA loan only. The demand-source session first validates
 /// its actual raw-pull ordinal→primary output-span association; this lookup
 /// cannot authenticate an external source/model or manufacture a missing row.
 pub fn original_literal_for_span(&self,span:Span)->io::Result<Option<&crate::OriginalLiteralData>>{
  if self.failed||self.ended{return Err(io::ErrorKind::InvalidInput.into())}let rows=self.literal_facts.as_slice();let at=rows.partition_point(|(actual,_)|actual.start<span.start);Ok(rows.get(at).filter(|(actual,_)|*actual==span).map(|(_,data)|data))
 }
 pub fn validate_live_header(&self,header:&OriginalPrimaryLiveHeader)->io::Result<()>{
  if self.failed||self.ended||self.original.stopped()||!self.layout.as_ref().ok_or(io::ErrorKind::InvalidInput)?.matches_identity(&header.owner){return Err(io::Error::new(io::ErrorKind::InvalidInput,"foreign or completed actual primary header owner"))}
  let Some((start,indent,in_body,_))=self.frames.as_ref().ok_or(io::ErrorKind::InvalidInput)?.live_header_scope(&self.original)?else{return Err(io::ErrorKind::InvalidInput.into())};if in_body||start!=header.header.start||indent!=header.indent||self.tokens.get(header.open_ordinal).is_none_or(|token|token.span!=header.open){return Err(io::ErrorKind::InvalidInput.into())}Ok(())
 }
 pub fn span_tokens(&self)->&[SpanToken]{&self.tokens}
 pub fn consumed_frontier(&self)->usize{self.frontier}
 /// Observer control only, never an authored syntax fatal or EOF/model grant.
 /// Actual frontend prefix issuance additionally requires the SAME genuine
 /// signature failure retained by its Tree consumer, as on the whole route.
 pub fn observer_stop_live_header(&mut self,header:&OriginalPrimaryLiveHeader)->io::Result<()>{
  self.validate_live_header(header)?;self.original.observer_stop.set(Some(Span::new(header.start(),self.frontier)));Ok(())
 }
 /// A live formal consumer owns the mutable observer loan while it pulls.
 /// Those actual tokens are inserted once but layout/complete-header callbacks
 /// cannot reenter it. On genuine Stop, seal THAT consumed formal frontier
 /// without running layout, requesting another token or pretending EOF.
 /// This remains control DATA; Tree requires the real private fatal receipt.
 pub fn observer_stop_live_header_at(&mut self,header:&OriginalPrimaryLiveHeader,actual_source:&str)->io::Result<()>{
  let result=(||{self.validate_live_header(header)?;if actual_source.len()<self.frontier||self.tokens.last().is_some_and(|token|token.span.end>actual_source.len()){return Err(io::ErrorKind::InvalidInput.into())}self.frontier=actual_source.len();self.original.observer_stop.set(Some(Span::new(header.start(),self.frontier)));Ok(())})();if result.is_err(){self.failed=true}result
 }
 fn failure(&self)->io::Error{self.original.operational.borrow_mut().take().or_else(||self.original.storage.take_failure()).unwrap_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual primary demand has no issued continuation"))}
 // Token issuance is the native cursor owner's responsibility. This private
 // insertion cannot turn arbitrary DATA into a source/current-model grant.
 pub fn token(&mut self,token:SpanToken)->io::Result<()>{if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed primary owner cannot resume"))}if matches!(token.kind,TokenKind::Number|TokenKind::String|TokenKind::Resource){self.literal_facts_issued=false;}let status=self.token_inner(token);if status.is_err(){self.failed=true}status}
 // Called only by the actual final-token owner after constructing its genuine
 // scalar/static DATA. This is the SAME produced token occurrence, not a name
 // or spelling lookup, and no borrowed source/token survives another pull.
 pub fn token_with_original_literal(&mut self,token:SpanToken,data:crate::OriginalLiteralData)->io::Result<()>{
  if self.failed{return Err(io::ErrorKind::InvalidInput.into())}let result=(||{if token.span.start>=token.span.end||!matches!((token.kind,data.kind()),(TokenKind::Number,"Int"|"Float")|(TokenKind::String,"String")|(TokenKind::Resource,"Resource")){return Err(io::ErrorKind::InvalidInput.into())}let span=token.span;self.token_inner(token)?;self.literal_facts.append_actual(span,data,self.original.storage.a)})();if result.is_err(){self.failed=true}result
 }
 fn token_inner(&mut self,token:SpanToken)->io::Result<()>{
  if self.ended||self.original.stopped(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual primary token demanded after stop"))}
  if self.tokens.last().is_some_and(|prior|prior.span.end>token.span.start){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual primary tokens are not a forward cursor"))}
  if !self.original.storage.push(&mut self.tokens,token){return Err(self.failure())}Ok(())
 }
 pub fn lexical(&mut self,span:Span,kind:DiagnosticKind,message:&str)->io::Result<()>{if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed primary owner cannot resume"))}let status=self.lexical_inner(span,kind,message);if status.is_err(){self.failed=true}status}
 fn lexical_inner(&mut self,span:Span,kind:DiagnosticKind,message:&str)->io::Result<()>{
  if self.ended||self.original.stopped(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"lexical producer advanced after primary stop"))}
  if !self.original.storage.diagnostic_parts(&mut self.lexical,span,kind,message){return Err(self.failure())}Ok(())
 }
 /// Accept a genuinely complete physical layout frontier. A pause is not EOF;
 /// a whole-source parser is never called to rediscover prior declarations.
 pub fn advance(&mut self,source:&str,actual_eof:bool)->io::Result<bool>{if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed primary owner cannot resume"))}let status=self.advance_inner(source,actual_eof,None);if status.is_err(){self.failed=true}status}
 /// Streaming construction uses observer=None; this callback loan ends before
 /// the caller enters its SAME live formal parser. Retained state stays in place.
 pub fn advance_with_observer(&mut self,source:&str,actual_eof:bool,observer:&mut dyn OriginalDeclarationHeaderObserver)->io::Result<bool>{
  if self.failed||self.original.observer.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"scoped primary observer conflicts with retained observer or failed state"))}
  let status=self.advance_inner(source,actual_eof,Some(observer));if status.is_err(){self.failed=true}status
 }
 fn advance_inner(&mut self,source:&str,actual_eof:bool,mut observer:Option<&mut dyn OriginalDeclarationHeaderObserver>)->io::Result<bool>{
  if self.ended||source.len()<self.frontier{return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual primary frontier regressed or was sealed"))}
  if self.original.stopped(){return Ok(false)}
  if self.tokens.last().is_some_and(|token|token.span.end>source.len()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual native token exceeds current arena frontier"))}
  let mut batch=self.layout.as_mut().ok_or(io::ErrorKind::InvalidInput)?.advance(source,&self.tokens,&self.original,actual_eof)?;
  for line in batch.iter(){
   // Line is scalar geometry; no header/source String is copied or reparsed.
   let line=Line{indent:line.indent,header_start:line.header_start,header_end:line.header_end,end:line.end,explicit_block_opener:line.explicit_block_opener,same_line_body:line.same_line_body};
   let continuing=match observer.as_mut(){Some(actual)=>self.frames.as_mut().ok_or(io::ErrorKind::InvalidInput)?.line_scoped(source,&self.tokens,line,&self.original,&mut self.diagnostics,Some(&mut **actual))?,None=>self.frames.as_mut().ok_or(io::ErrorKind::InvalidInput)?.line(source,&self.tokens,line,&self.original,&mut self.diagnostics)?};
   if !continuing{break}
  }
  if !self.original.stopped(){if let Some(start)=batch.take_header_start(){if !self.frames.as_mut().ok_or(io::ErrorKind::InvalidInput)?.begin_early_header(source,&self.tokens,start,&self.original,&mut self.diagnostics)?{drop(batch);self.frontier=source.len();return Ok(false)}}}
  drop(batch);self.frontier=source.len();self.ended=actual_eof;
  if self.original.operational.borrow().is_some(){return Err(self.failure())}if let Some(actual)=self.original.storage.take_failure(){return Err(actual)}
  Ok(!self.original.stopped())
 }
 pub fn finish(mut self,source:&str,actual_eof:bool)->io::Result<OriginalDeclarationSkeleton>{
  if self.failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"failed primary owner cannot seal"))}
  if source.len()!=self.frontier||actual_eof!=self.ended{return Err(io::Error::new(io::ErrorKind::InvalidInput,"primary sealing lacks the exact actual consumed frontier"))}
  if !actual_eof&&!self.original.stopped(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"temporary input pause is not a primary EOF or authored stop"))}
  let items=self.frames.take().ok_or(io::ErrorKind::InvalidInput)?.finish(source,&self.tokens,&self.original,&mut self.diagnostics,actual_eof)?;
  let primary_owner=Some(self.layout.take().ok_or(io::ErrorKind::InvalidInput)?.finish_identity()?);
  if self.literal_facts_issued{self.literal_facts.seal_actual_frontier(source.len(),self.original.storage.a)?;}
  let diagnostics=std::mem::take(&mut self.diagnostics);for diagnostic in diagnostics{if !self.original.storage.push(&mut self.lexical,diagnostic){return Err(self.failure())}}
  drop(self.diagnostics);
  let OriginalParseState{storage,fatal,unavailable,operational,observer:_,observer_stop,first_outer_block:_}=self.original;
  if let Some(actual)=operational.into_inner(){return Err(actual)}if let Some(actual)=storage.take_failure(){return Err(actual)}
  let lease=storage.finish(&items,&self.tokens,&self.lexical)?;
  Ok(OriginalDeclarationSkeleton{syntax:OriginalDeclarationSyntax{items,tokens:self.tokens.into(),diagnostics:self.lexical},literal_facts:if self.literal_facts_issued{Some(self.literal_facts)}else{None},primary_owner,fatal:fatal.into_inner(),unavailable:unavailable.into_inner(),observer_stop:observer_stop.get(),_lease:lease})
 }
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 #[test]fn actual_primary_assembly_retains_one_traversal_across_physical_pauses_and_not_fake_eof(){
  let source="/datum/a\n    var/value=1\n    proc/p()\n        return 2\n/datum/b\n";let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,4<<20,&||Ok(()));let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();let mut cursor=crate::NativeTokenCursor::default();let mut end=0;
  for line in source.split_inclusive('\n'){end+=line.len();loop{match cursor.next_available_using(&source[..end],end==source.len(),&a,|_,_,_|true).unwrap(){crate::NativeTokenStep::Token(token)=>primary.token(token).unwrap(),crate::NativeTokenStep::NeedInput|crate::NativeTokenStep::End=>break,crate::NativeTokenStep::Stopped=>panic!("no diagnostic stop")}}assert!(primary.advance(&source[..end],end==source.len()).unwrap());}
  let actual=primary.finish(source,true).unwrap();let expected=parse_original_declaration_skeleton_using(source,&a).unwrap();assert_eq!(actual.syntax(),expected.syntax());drop(actual);drop(expected);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_primary_assembly_refuses_pause_sealing_foreign_frontier_and_keeps_first_io(){
  let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,4<<20,&||Ok(()));let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();assert!(primary.advance("",false).unwrap());assert_eq!(primary.finish("",false).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(counter.load(Ordering::Acquire),0);
  let fault=||Err(io::Error::from_raw_os_error(1450));let a=crate::SettingAdmission::new(&counter,4<<20,&fault);assert_eq!(OriginalPrimaryDemand::new(&a,None).err().unwrap().raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_primary_one_shot_observer_failure_poison_survives_error_drain_and_only_fresh_owner_recovers(){
  struct Once(bool);impl OriginalDeclarationHeaderObserver for Once{fn header(&mut self,_:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{if !self.0{self.0=true;Err(io::Error::from_raw_os_error(1450))}else{Ok(OriginalHeaderFlow::Continue)}}}
  let source="/proc/p()\n";let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,4<<20,&||Ok(()));let mut observer=Once(false);let mut primary=OriginalPrimaryDemand::new(&a,Some(&mut observer)).unwrap();for token in lex_spans(source).tokens{primary.token(token).unwrap();}
  assert_eq!(primary.advance(source,true).err().unwrap().raw_os_error(),Some(1450));assert_eq!(primary.advance(source,true).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(primary.token(SpanToken{kind:TokenKind::Newline,span:Span::new(source.len(),source.len())}).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(primary.finish(source,true).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(counter.load(Ordering::Acquire),0);
  let mut fresh=OriginalPrimaryDemand::new(&a,Some(&mut observer)).unwrap();for token in lex_spans(source).tokens{fresh.token(token).unwrap()}assert!(fresh.advance(source,true).unwrap());let actual=fresh.finish(source,true).unwrap();assert_eq!(actual.syntax().items.len(),1);drop(actual);assert_eq!(counter.load(Ordering::Acquire),0);
 }

}

#[cfg(test)]mod early_and_literal_tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 #[test]fn actual_first_productive_token_establishes_same_primary_scope_before_newline_and_full_header_joins_once(){
  let source="/datum/a\n    proc/p(value=1)\n";let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,4<<20,&||Ok(()));let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();let mut saw_early=false;
  for token in lex_spans(source).tokens{let end=token.span.end;primary.token(token).unwrap();assert!(primary.advance(&source[..end],false).unwrap());if end>source.find("proc/p").unwrap()&&end<source.len(){let scope=primary.frames.as_ref().unwrap().live_header_scope(&primary.original).unwrap();if let Some((start,indent,in_body,prior))=scope{assert_eq!(start,source.find("proc/p").unwrap());assert_eq!(indent,4);assert!(!in_body);assert!(prior.is_none());saw_early=true;}}}
  assert!(saw_early);assert!(primary.advance(source,true).unwrap());let actual=primary.finish(source,true).unwrap();let expected=parse_original_declaration_skeleton_using(source,&a).unwrap();assert_eq!(actual.syntax(),expected.syntax());assert!(actual.original_literal_facts().is_none(),"untyped number insertion cannot issue a completed zero-literal roster");drop((actual,expected));assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn genuine_typed_primary_occurrence_retains_same_neutral_roster_and_untyped_literals_keep_none(){
  let source="/datum/a\n    var/value=1\n";let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,4<<20,&||Ok(()));let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();let mut span=None;
  for token in lex_spans(source).tokens{if token.kind==TokenKind::Number{span=Some(token.span);let data=crate::OriginalLiteralData::from_value_using("1".to_owned(),crate::OriginalTokenValue::Int(1),&a).unwrap();primary.token_with_original_literal(token,data).unwrap();}else{primary.token(token).unwrap();}}
  primary.advance(source,true).unwrap();let product=primary.finish(source,true).unwrap();let rows=product.original_literal_facts().unwrap();assert_eq!(rows.len(),1);assert_eq!(rows[0].0,span.unwrap());assert!(matches!(rows[0].1.value(),crate::OriginalTokenValue::Int(1)));let(_,_,_,lease,facts)=product.into_parts_with_literal_facts();let facts=facts.unwrap();assert!(facts.is_admitted_by(&a));drop(lease);assert_eq!(facts.as_slice().len(),1);assert!(used.load(Ordering::Acquire)>0);drop(facts);assert_eq!(used.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod producer_identity_tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 #[test]fn live_header_binds_actual_final_same_layout_owner_and_rejects_equal_source_foreign_primary(){
  let source="/proc/p(value=1)\n";let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();let mut live=None;
  for token in lex_spans(source).tokens{let end=token.span.end;primary.token(token).unwrap();primary.advance(&source[..end],false).unwrap();if &source[token.span.range()]=="("{let header=primary.live_callable_header(&source[..end]).unwrap().unwrap();primary.validate_live_header(&header).unwrap();assert_eq!(header.start(),0);assert_eq!(header.argument_start(),"/proc/p(".len());live=Some(header.clone());}}
  let live=live.unwrap();assert!(primary.validate_live_header(&live).is_err(),"completed live header cannot resume formal input");primary.advance(source,true).unwrap();let actual=primary.finish(source,true).unwrap();assert!(actual.same_primary_header(&live));
  let mut foreign=OriginalPrimaryDemand::new(&a,None).unwrap();for token in lex_spans(source).tokens{foreign.token(token).unwrap()}foreign.advance(source,true).unwrap();let foreign=foreign.finish(source,true).unwrap();assert!(!foreign.same_primary_header(&live));drop((actual,foreign));assert!(used.load(Ordering::Acquire)>0,"live handle retains only its actual fixed producer metadata");drop(live);assert_eq!(used.load(Ordering::Acquire),0);
 }

 #[test]fn actual_scoped_primary_observer_loan_ends_before_same_consumer_is_reused(){
  struct Observer(usize);impl OriginalDeclarationHeaderObserver for Observer{fn header(&mut self,_:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{self.0+=1;Ok(OriginalHeaderFlow::Continue)}}
  let source="/proc/p()\n";let count=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&count,4<<20,&||Ok(()));
  let mut observer=Observer(0);let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();for token in lex_spans(source).tokens{primary.token(token).unwrap()}
  assert!(primary.advance_with_observer(source,true,&mut observer).unwrap());assert_eq!(observer.0,1);observer.0+=1;
  let product=primary.finish(source,true).unwrap();assert_eq!(observer.0,2);assert_eq!(product.syntax().items.len(),1);drop(product);assert_eq!(count.load(Ordering::Acquire),0);
 }
 #[test]fn actual_scoped_primary_observer_first_io_poison_refuses_retry_and_finish(){
  struct Observer(bool);impl OriginalDeclarationHeaderObserver for Observer{fn header(&mut self,_:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{if !self.0{self.0=true;Err(io::Error::from_raw_os_error(1450))}else{Ok(OriginalHeaderFlow::Continue)}}}
  let source="/proc/p()\n";let count=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&count,4<<20,&||Ok(()));let mut observer=Observer(false);let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();for token in lex_spans(source).tokens{primary.token(token).unwrap()}
  assert_eq!(primary.advance_with_observer(source,true,&mut observer).unwrap_err().raw_os_error(),Some(1450));assert!(observer.0);assert!(primary.advance_with_observer(source,true,&mut observer).is_err());assert!(primary.finish(source,true).is_err());assert_eq!(count.load(Ordering::Acquire),0);
 }

 #[test]fn actual_scoped_header_keeps_its_registered_outer_probe_through_pending_child_resolution(){
  struct Observer(Vec<Option<usize>>);impl OriginalDeclarationHeaderObserver for Observer{fn header(&mut self,event:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{self.0.push(event.prior_outer_block);Ok(OriginalHeaderFlow::Continue)}}
  let source="/proc/first()\n    return 1\n/proc/second()\n";let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,4<<20,&||Ok(()));let mut observer=Observer(Vec::new());let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();
  for token in lex_spans(source).tokens{primary.token(token).unwrap();assert!(primary.advance_with_observer(&source[..token.span.end],false,&mut observer).unwrap());}
  assert!(primary.advance_with_observer(source,true,&mut observer).unwrap());let product=primary.finish(source,true).unwrap();assert_eq!(observer.0,vec![None,Some(source.find('\n').unwrap())]);assert_eq!(product.syntax().items.len(),2);drop(product);assert_eq!(used.load(Ordering::Acquire),0);
 }

 #[test]fn actual_inline_type_brace_scope_is_already_bound_before_nested_callable_formals(){
  struct Observer;impl OriginalDeclarationHeaderObserver for Observer{fn header(&mut self,_:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{Ok(OriginalHeaderFlow::Continue)}}
  let source="/datum/parent{\nproc/child(){\n}\n}\n";let open=source.find("child(").unwrap()+"child(".len();let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,4<<20,&||Ok(()));let mut observer=Observer;let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();let tokens=lex_spans(source).tokens;for token in tokens.iter().filter(|token|token.span.end<=open){primary.token(*token).unwrap();assert!(primary.advance_with_observer(&source[..token.span.end],false,&mut observer).unwrap());}
  let live=primary.live_callable_header(&source[..open]).unwrap().expect("genuine nested callable at current open");assert_eq!(live.start(),source.find("proc/child").unwrap());assert_eq!(live.indent,4);primary.validate_live_header(&live).unwrap();
  for token in tokens.iter().filter(|token|token.span.end>open){primary.token(*token).unwrap();assert!(primary.advance_with_observer(&source[..token.span.end],false,&mut observer).unwrap());}assert!(primary.advance_with_observer(source,true,&mut observer).unwrap());let product=primary.finish(source,true).unwrap();assert!(product.same_primary_header(&live));assert_eq!(product.syntax().items.len(),1);assert_eq!(product.syntax().items[0].children.len(),1);assert_eq!(product.syntax().items[0].children[0].kind,ItemKind::Proc);drop((product,live));assert_eq!(used.load(Ordering::Acquire),0);
 }

 #[test]fn actual_live_formal_stop_seals_only_inserted_consumed_frontier_without_reentrant_observer_or_eof(){
  struct Observer;impl OriginalDeclarationHeaderObserver for Observer{fn header(&mut self,_:OriginalPrimaryHeader<'_>)->io::Result<OriginalHeaderFlow>{panic!("unfinished fatal header must not reenter complete observer")}}
  let source="/proc/bad(value=, BAD())\n";let open=source.find('(').unwrap()+1;let stop=source.find(',').unwrap()+1;let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,4<<20,&||Ok(()));let mut observer=Observer;let mut primary=OriginalPrimaryDemand::new(&a,None).unwrap();let tokens=lex_spans(source).tokens;
  for token in tokens.iter().filter(|token|token.span.end<=open){primary.token(*token).unwrap();primary.advance_with_observer(&source[..token.span.end],false,&mut observer).unwrap();}let live=primary.live_callable_header(&source[..open]).unwrap().unwrap();
  for token in tokens.iter().filter(|token|token.span.start>=open&&token.span.end<=stop){primary.token(*token).unwrap();}assert_eq!(primary.consumed_frontier(),open);primary.observer_stop_live_header_at(&live,&source[..stop]).unwrap();assert_eq!(primary.consumed_frontier(),stop);let actual=primary.finish(&source[..stop],false).unwrap();assert!(actual.syntax().items.is_empty());assert_eq!(actual.observer_stop(),Some(Span::new(0,stop)));assert!(actual.fatal().is_none(),"observer control is not a fabricated authored fatal");drop((actual,live));assert_eq!(used.load(Ordering::Acquire),0);
 }
}
