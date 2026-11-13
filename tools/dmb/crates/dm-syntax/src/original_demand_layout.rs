//! Private demand-layout DATA over the SAME native kernels. Neither this
//! retained allocation owner nor a line batch certifies source EOF/model state.
use super::*;
use std::{alloc::Layout, io, mem, sync::Arc};
struct LayoutOwner(Option<Arc<LayoutCredit>>);
impl Clone for LayoutOwner{fn clone(&self)->Self{Self(Some(self.0.as_ref().expect("live primary layout owner").clone()))}}
impl Drop for LayoutOwner{fn drop(&mut self){if let Some(owner)=self.0.take(){if let Some(payload)=Arc::into_inner(owner){drop(payload)}}}}
impl std::ops::Deref for LayoutOwner{type Target=LayoutCredit;fn deref(&self)->&LayoutCredit{self.0.as_deref().expect("live primary layout owner")}}
impl LayoutOwner{
 fn new(credit:LayoutCredit)->Self{Self(Some(Arc::new(credit)))}
 fn same(&self,other:&Self)->bool{Arc::ptr_eq(self.0.as_ref().expect("live primary layout owner"),other.0.as_ref().expect("live primary layout owner"))}
}
// Header identity owns only its allocation. Cursor buffers and returned
// batches have separate leases under the same resource counter.
pub(super) struct LayoutCredit {
 lease: crate::SettingRootLease,
 // One funded diagnostic scalar in this existing allocation. Atomic keeps
 // cloned completed identities Send/Sync; only the live cursor claims logs.
 #[cfg(debug_assertions)]
 row_work_trace_next:std::sync::atomic::AtomicUsize,
}

fn actual_error(a: &crate::SettingAdmission<'_>, status: io::Error) -> io::Error {
    a.take_operational_error().unwrap_or(status)
}

// Both buffers use the standard Global allocator and its exact logical
// RawVec capacity. Preserve the existing old+new peak admission, but let
// Global grow/reallocate the owner instead of always copying its full prefix
// into a distinct new allocation on every tiny consumed-token frontier.
fn fund_buffer<T>(
    rows: &mut Vec<T>, desired: usize, credit: &mut crate::SettingRootLease,
    a: &crate::SettingAdmission<'_>,
) -> io::Result<()> {
    if rows.capacity() >= desired { return Ok(()); }
    let layout = Layout::array::<T>(desired).map_err(|_| io::ErrorKind::OutOfMemory)?;
    let prior = rows.capacity().checked_mul(mem::size_of::<T>()).ok_or(io::ErrorKind::OutOfMemory)?;
    a.grow(credit, layout.size()).map_err(|e| actual_error(a, e))?;
    // additional is relative to LEN, not the previous capacity. This asks
    // exactly desired total elements, without geometric speculative storage.
    // On an allocator failure the old Vec is intact and its conservative
    // old+new lease remains live until its unchanged owner drops.
    rows.try_reserve_exact(desired - rows.len()).map_err(|_| io::ErrorKind::OutOfMemory)?;
    a.shrink(credit, prior).map_err(|e| actual_error(a, e))
}

fn fund_visible_string(
    text: &mut String, desired: usize, credit: &mut crate::SettingRootLease,
    a: &crate::SettingAdmission<'_>,
) -> io::Result<()> {
    if text.capacity() >= desired { return Ok(()); }
    let layout=Layout::array::<u8>(desired).map_err(|_| io::ErrorKind::OutOfMemory)?;
    let prior=text.capacity();
    a.grow(credit,layout.size()).map_err(|e|actual_error(a,e))?;
    // String delegates to its existing byte Vec; UTF8 and the payload remain
    // unchanged. No empty replacement Vec, repeated prefix copy, or reparse.
    text.try_reserve_exact(desired-text.len()).map_err(|_|io::ErrorKind::OutOfMemory)?;
    a.shrink(credit,prior).map_err(|e|actual_error(a,e))
}

// Field order keeps each physical Vec alive only while its exact lease lives.
// Neither the kernels nor their callers can extract a mutable unowned Vec.
struct OwnedLayoutLines<'a,'budget> {
 rows:Vec<Line>,
 credit:crate::SettingRootLease,
 a:&'a crate::SettingAdmission<'budget>,
}
impl<'a,'budget> OwnedLayoutLines<'a,'budget> {
 fn new(a:&'a crate::SettingAdmission<'budget>)->io::Result<Self>{
  Ok(Self{rows:Vec::new(),credit:a.reserve(0).map_err(|e|actual_error(a,e))?,a})
 }
 fn as_slice(&self)->&[Line]{&self.rows}
 fn globalize(&mut self,base:usize){for row in &mut self.rows{row.header_start+=base;row.header_end+=base;row.end+=base;}}
 fn into_batch(self,header_start:Option<NativePrimaryHeaderStart>)->NativeLayoutBatch{
  NativeLayoutBatch{lines:self.rows,header_start,_credit:self.credit}
 }
}
impl LayoutLineSink for OwnedLayoutLines<'_,'_> {
 fn push_line(&mut self,line:Line,original:Option<&OriginalParseState<'_,'_,'_>>)->bool{
  let Some(state)=original else{
   self.a.record_operational_error(io::Error::new(io::ErrorKind::InvalidInput,"owned layout rows require their actual primary host"));return false
  };
  if !std::ptr::eq(state.storage.a,self.a){return state.storage.fail(io::Error::new(io::ErrorKind::InvalidInput,"owned layout rows belong to another primary host"))}
  if !state.poll(){return false}
  if self.rows.len()==self.rows.capacity(){
   // Preserve the existing Line Vec policy (first4, then2x); admission is
   // exact old+new physical capacity BEFORE growth, never token geometry.
   let Some(capacity)=self.rows.capacity().max(2).checked_mul(2)else{return state.storage.fail(io::ErrorKind::OutOfMemory.into())};
   if let Err(actual)=fund_buffer(&mut self.rows,capacity,&mut self.credit,self.a){return state.storage.fail(actual)}
  }
  self.rows.push(line);true
 }
 fn len(&self)->usize{self.rows.len()}
 fn get_mut(&mut self,index:usize)->Option<&mut Line>{self.rows.get_mut(index)}
 fn last_mut(&mut self)->Option<&mut Line>{self.rows.last_mut()}
}

// Diagnostic-only borrowed views. No literal payload is materialized or read.
#[cfg(debug_assertions)]
fn layout_trace_clip(text:&str,limit:usize)->&str{
 let mut end=text.len().min(limit);while !text.is_char_boundary(end){end-=1;}&text[..end]
}
#[cfg(debug_assertions)]
fn layout_trace_payload_kind(kind:TokenKind)->bool{
 matches!(kind,TokenKind::String|TokenKind::Resource|TokenKind::Interpolation|TokenKind::Comment|TokenKind::Number|TokenKind::Unknown)
}
#[cfg(debug_assertions)]
fn layout_trace_header_prefix<'s>(source:&'s str,tokens:TokenWindow<'_>,anchor:usize)->Option<&'s str>{
 let tail=source.get(anchor..)?;let prefix=layout_trace_clip(tail,256);
 let end=anchor.checked_add(prefix.len())?;
 let first=tokens.partition_point(|token|token.span.end<=anchor);
 let mut stop=end;
 for token in tokens.range(first,tokens.len())?.iter().take_while(|token|token.span.start<end){
  if layout_trace_payload_kind(token.kind){stop=token.span.start.max(anchor);break}
 }
 source.get(anchor..stop)
}
#[cfg(debug_assertions)]
fn layout_trace_token_spelling(source:&str,token:SpanToken)->&str{
 if layout_trace_payload_kind(token.kind){return "<payload omitted>"}
 source.get(token.span.range()).map(|text|layout_trace_clip(text,24)).unwrap_or("<invalid source span>")
}

// Failure diagnostics only. This is the SAME unified()/[] depth convention
// used by structural layout, not a new typed bracket validator or parser.
#[cfg(debug_assertions)]
fn last_unmatched_layout_opener(delimiters:&[u8],start:usize,end:usize)->Option<(usize,u8)>{
 let window=delimiters.get(start..end)?;let mut close_debt=0usize;
 for(index,byte)in window.iter().copied().enumerate().rev(){
  match byte{
   b')'|b']'=>close_debt=close_debt.checked_add(1)?,
   b'('|b'['=>{if close_debt==0{return Some((start+index,byte))}close_debt-=1;},
   _=>(),
  }
 }
 None
}
#[cfg(debug_assertions)]
fn layout_opener_token_metadata(
 global:usize,tokens:TokenWindow<'_>,facts:Option<crate::OriginalLiteralRows<'_>>,
)->(Option<SpanToken>,Option<&'static str>){
 let ordinal=tokens.partition_point(|token|token.span.end<=global);
 let token=tokens.get(ordinal).filter(|token|token.span.start<=global&&global<token.span.end);
 let literal_kind=token.and_then(|token|facts.and_then(|rows|{
  let at=rows.partition_point(|(span,_)|span.end<=global);
  rows.get(at).filter(|(span,_)|*span==token.span).map(|(_,data)|data.kind())
 }));
 (token,literal_kind)
}

/// Lines drop before their exact same-domain buffer credit, independently of
/// other live batches, the cursor's masks and any cloned producer identity.
pub(super) struct NativeLayoutBatch {
    lines: Vec<Line>,
    header_start: Option<NativePrimaryHeaderStart>,
    _credit: crate::SettingRootLease,
}
impl NativeLayoutBatch{pub(super) fn take_header_start(&mut self)->Option<NativePrimaryHeaderStart>{self.header_start.take()}}
impl NativePrimaryLayoutIdentity{
 pub(super) fn same(&self,other:&Self)->bool{self.credit.same(&other.credit)}
 // Only the completed-header wrapper may carry an unbound identity.
 pub(super) fn unbound_completed() -> Self {
  Self { credit: LayoutOwner(None) }
 }
 pub(super) fn take_completed(&mut self) -> Option<Self> {
  self.credit.0.take().map(|owner| Self { credit: LayoutOwner(Some(owner)) })
 }
 pub(super) fn matches_completed(&self, other: &Self) -> bool {
  self.credit.0.as_ref().zip(other.credit.0.as_ref()).is_some_and(|(left, right)| Arc::ptr_eq(left, right))
 }
 pub(super) fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){let owner=self.credit.0.as_ref().expect("live primary layout owner");let fixed=std::mem::size_of::<LayoutCredit>()+2*std::mem::size_of::<usize>();visit(Arc::as_ptr(owner)as usize,fixed,fixed);owner.lease.visit_counter_storage(|p,n|visit(p,n,n));}
}
impl std::ops::Deref for NativeLayoutBatch{type Target=[Line];fn deref(&self)->&[Line]{&self.lines}}

#[derive(Clone)]pub(super) struct NativePrimaryLayoutIdentity{credit:LayoutOwner}
pub(super) struct NativeDemandLayoutCursor<'a,'budget>{
 masks:NativeLayoutMaskCursor,structural:NativeStructuralCursor,inline:NativeInlineBlockCursor,
 source_base:usize,counted_tokens:usize,boundaries:usize,finished:bool,
 credit:LayoutOwner,
 // Masks and multiline geometry physically release before this lease.
 mask_credit:crate::SettingRootLease,a:&'a crate::SettingAdmission<'budget>,
}
impl<'a,'budget> NativeDemandLayoutCursor<'a,'budget>{
 pub(super) fn new(a:&'a crate::SettingAdmission<'budget>)->io::Result<Self>{
  let bytes=std::mem::size_of::<LayoutCredit>().checked_add(2*std::mem::size_of::<usize>()).ok_or(io::ErrorKind::OutOfMemory)?;
  let lease=a.reserve(bytes).map_err(|e|a.take_operational_error().unwrap_or(e))?;
  #[cfg(debug_assertions)]
  let row_work_trace_next=std::sync::atomic::AtomicUsize::new(
   if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){1<<20}else{usize::MAX});
  let mask_credit=a.reserve(0).map_err(|e|actual_error(a,e))?;
  Ok(Self{masks:Default::default(),structural:Default::default(),inline:Default::default(),source_base:0,counted_tokens:0,boundaries:8,finished:false,credit:LayoutOwner::new(LayoutCredit{lease,
   #[cfg(debug_assertions)]
   row_work_trace_next,
  }),mask_credit,a})
 }
 // Once compaction has consumed the entire genuine mask window, batches
 // retain only global scalar spans and their own line buffers. No issued
 // header identity or batch borrows this scratch allocation.
 fn release_consumed_mask_storage(&mut self)->io::Result<()> {
  if !self.masks.visible.is_empty()||!self.masks.delimiters.is_empty()
      ||!self.masks.multiline_literals.is_empty(){return Ok(())}
  let dead=self.masks.visible.capacity().checked_add(self.masks.delimiters.capacity())
   .and_then(|n|self.masks.multiline_literals.capacity().checked_mul(mem::size_of::<Span>()).and_then(|spans|n.checked_add(spans)))
   .ok_or(io::ErrorKind::OutOfMemory)?;
  if dead==0{return Ok(())}
  // Free the exact same unique buffers BEFORE refunding. A first release
  // checkpoint fault keeps the conservative lease until the cursor drops;
  // no stale scratch pointer, credit transfer or successful batch escapes.
  drop((mem::take(&mut self.masks.visible),mem::take(&mut self.masks.delimiters),
      mem::take(&mut self.masks.multiline_literals)));
  self.a.shrink(&mut self.mask_credit,dead).map_err(|actual|actual_error(self.a,actual))
 }
 pub(super) fn identity(&self)->NativePrimaryLayoutIdentity{NativePrimaryLayoutIdentity{credit:self.credit.clone()}}
 pub(super) fn matches_identity(&self,identity:&NativePrimaryLayoutIdentity)->bool{self.credit.same(&identity.credit)}
 /// Free actual scratch FIRST, then retain only this SAME existing Arc's
 /// fixed metadata as final producer identity. No query/admission borrow or
 /// source/AST/mask buffer is pinned by a completed header handle.
 pub(super) fn finish_identity(self)->io::Result<NativePrimaryLayoutIdentity>{
  let Self{masks,structural,inline,credit,mask_credit,a,..}=self;
  drop(masks);drop(structural);drop(inline);drop(mask_credit);
  a.checkpoint().map_err(|e|actual_error(a,e))?;
  Ok(NativePrimaryLayoutIdentity{credit})
 }
 #[cfg(debug_assertions)]
 fn claim_row_work_trace_sample(&self,bytes:usize)->bool{
  use std::sync::atomic::Ordering;
  let next=self.credit.row_work_trace_next.load(Ordering::Relaxed);
  if next==usize::MAX||bytes<next{return false}
  self.credit.row_work_trace_next.store(bytes.saturating_mul(2),Ordering::Relaxed);
  true
 }
 #[cfg(debug_assertions)]
 fn trace_row_work_highwater(&self,source_len:usize,row_work:usize,boundaries:usize,token_frontier:usize){
  if self.claim_row_work_trace_sample(row_work){
   self.trace_layout_geometry("ROW_WORK_HIGHWATER","row_work_live",source_len,row_work,boundaries,token_frontier);
  }
 }
 #[cfg(debug_assertions)]
 fn trace_pending_opener(&self,source:&str,tokens:TokenWindow<'_>,facts:Option<crate::OriginalLiteralRows<'_>>){
  if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_none(){return}
  let Some(pending)=self.structural.pending.as_ref()else{
   eprintln!("ORIGINAL_LAYOUT_UNMATCHED_OPENER status=no_pending structural_depth={}",self.structural.depth);return
  };
  let start=pending.header_start;let end=self.structural.offset;
  if let Some(header)=self.source_base.checked_add(start){
   let prefix=layout_trace_header_prefix(source,tokens,header);
   eprintln!("ORIGINAL_LAYOUT_PENDING_HEADER global_start={header} prefix={prefix:?}");
   let first=tokens.partition_point(|token|token.span.end<=header);
   if let Some(rows)=tokens.range(first,tokens.len()){
    for (ordinal,token) in rows.iter().take(16).enumerate(){
     eprintln!("ORIGINAL_LAYOUT_PENDING_TOKEN ordinal={ordinal} kind={:?} span={:?} spelling={:?}",token.kind,token.span,layout_trace_token_spelling(source,token));
    }
   }
  }
  // Do not inspect unprocessed bytes after structural.offset. This one
  // reverse sweep borrows the existing mask only, with constant stack state.
  let Some((local,byte))=last_unmatched_layout_opener(&self.masks.delimiters,start,end)else{
   eprintln!("ORIGINAL_LAYOUT_UNMATCHED_OPENER status=none_or_invalid_window start={start} processed_end={end} mask_len={} structural_depth={}",self.masks.delimiters.len(),self.structural.depth);return
  };
  let Some(global)=self.source_base.checked_add(local)else{return};
  let Some(global_end)=global.checked_add(1)else{return};
  let (token,literal_kind)=layout_opener_token_metadata(global,tokens,facts);
  eprintln!("ORIGINAL_LAYOUT_UNMATCHED_OPENER status=found start={start} processed_end={end} local={local} global_span={:?} marker={} token={token:?} literal_kind={literal_kind:?}",
   Span::new(global,global_end),if byte==b'(' {"LeftParen"}else{"LeftBracket"});
 }
 #[cfg(debug_assertions)]
 fn trace_funding_geometry(&self,stage:&str,source_len:usize,row_work:usize,boundaries:usize,token_frontier:usize){
  if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_none(){return}
  self.trace_layout_geometry("FUNDING_FAILURE",stage,source_len,row_work,boundaries,token_frontier);
 }
 #[cfg(debug_assertions)]
 fn trace_layout_geometry(&self,event:&str,stage:&str,source_len:usize,row_work:usize,boundaries:usize,token_frontier:usize){
  eprintln!("ORIGINAL_LAYOUT_{event} root_retained_sample={} stage={stage} source_len={source_len} source_base={} window={} visible_len={} visible_capacity={} delimiter_len={} delimiter_capacity={} literal_len={} literal_capacity={} mask_credit={} row_work={row_work} boundaries={boundaries} token_frontier={token_frontier} prior_boundaries={} counted_tokens={} structural_offset={} structural_depth={} initializer_depth={} block_depth={} pending={:?} literal_cursor={}",
   self.a.retained_bytes_for_trace(),self.source_base,source_len.saturating_sub(self.source_base),self.masks.visible.len(),self.masks.visible.capacity(),self.masks.delimiters.len(),self.masks.delimiters.capacity(),self.masks.multiline_literals.len(),self.masks.multiline_literals.capacity(),self.mask_credit.bytes(),self.boundaries,self.counted_tokens,self.structural.offset,self.structural.depth,self.structural.initializer_depth,self.structural.block_depth,self.structural.pending,self.structural.literal_cursor);
 }
 pub(super) fn advance(&mut self,source:&str,tokens:&[SpanToken],original:&OriginalParseState<'_,'_,'_>,final_input:bool)->io::Result<NativeLayoutBatch>{self.advance_with_literal_facts(source,TokenWindow::from_slice(tokens),original,final_input,None)}
 pub(super) fn advance_with_literal_facts(&mut self,source:&str,tokens:TokenWindow<'_>,original:&OriginalParseState<'_,'_,'_>,final_input:bool,facts:Option<crate::OriginalLiteralRows<'_>>)->io::Result<NativeLayoutBatch>{
  self.a.checkpoint().map_err(|e|self.a.take_operational_error().unwrap_or(e))?;
  if !std::ptr::eq(original.storage.a,self.a){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native demanded layout belongs to a foreign primary resource host"))}
  if self.finished||self.counted_tokens>tokens.len()||self.source_base>source.len()||self.masks.visible.len()>source.len().saturating_sub(self.source_base){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native demanded layout has no new complete physical source frontier"))}
  let(mut boundaries,mut new_multiline)=(self.boundaries,0usize);
  for token in tokens.range(self.counted_tokens,tokens.len()).expect("checked layout token frontier").iter(){self.a.checkpoint().map_err(|e|self.a.take_operational_error().unwrap_or(e))?;let Some(text)=source.get(token.span.range())else{return Err(io::Error::new(io::ErrorKind::InvalidInput,"native demanded layout token escapes actual source"))};if token.kind==TokenKind::Newline||matches!(text,"{"|"}"|";"|"("){boundaries=boundaries.checked_add(2).ok_or(io::ErrorKind::OutOfMemory)?;}if matches!(token.kind,TokenKind::String|TokenKind::Interpolation)&&text.contains('\n'){new_multiline=new_multiline.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;}}
  // Actual physical and inline Line Vecs below own independent leases.
  // Retained token boundaries remain diagnostic DATA, not phantom row storage.
  let visible_bytes=source.len()-self.source_base;
  fund_visible_string(&mut self.masks.visible,visible_bytes,&mut self.mask_credit,self.a).map_err(|actual|{
    #[cfg(debug_assertions)]
    self.trace_funding_geometry("visible",source.len(),0,boundaries,tokens.len());
    #[cfg(debug_assertions)]
    self.trace_pending_opener(source,tokens,facts);
    actual
   })?;

  fund_buffer(&mut self.masks.delimiters,visible_bytes,&mut self.mask_credit,self.a).map_err(|actual|{
    #[cfg(debug_assertions)]
    self.trace_funding_geometry("delimiters",source.len(),0,boundaries,tokens.len());
    #[cfg(debug_assertions)]
    self.trace_pending_opener(source,tokens,facts);
    actual
   })?;

  let spans=self.masks.multiline_literals.len().checked_add(new_multiline).ok_or(io::ErrorKind::OutOfMemory)?;
  if spans>self.masks.multiline_literals.capacity(){
   // Actual next consumed tokens were counted above, so the native mask
   // pass appends inside this exact already funded allocation.
   let capacity=spans.max(4).checked_next_power_of_two().ok_or(io::ErrorKind::OutOfMemory)?;
   fund_buffer(&mut self.masks.multiline_literals,capacity,&mut self.mask_credit,self.a).map_err(|actual|{
    #[cfg(debug_assertions)]
    self.trace_funding_geometry("multiline",source.len(),0,boundaries,tokens.len());
    #[cfg(debug_assertions)]
    self.trace_pending_opener(source,tokens,facts);
    actual
   })?;

  }
  if !self.masks.advance_with_literal_facts(source,Span::new(self.source_base,source.len()),tokens,Some(original),facts.map(|rows|(rows,0))){return Err(original.storage.take_failure().unwrap_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"native mask continuation has no actual complete-token provenance")))}
  self.counted_tokens=tokens.len();self.boundaries=boundaries;
  let visible=self.masks.visible();let complete=if final_input{visible.len()}else{visible.rfind('\n').map_or(0,|at|at+1)};let mut physical=OwnedLayoutLines::new(self.a)?;self.structural.advance_into(&visible[..complete],&self.masks.delimiters[..complete],&self.masks.multiline_literals,Some(original),source,tokens,self.source_base,final_input,&mut physical)?;
  if let Some(actual)=original.storage.take_failure(){return Err(actual)}
  let header_start=if !final_input&&complete<visible.len(){match self.structural.partial_header_start(visible,self.source_base){Some(start)=>self.inline.live_header_start(start)?,None=>None}}else{None};
  let mut lines=OwnedLayoutLines::new(self.a)?;
  self.inline.advance_into(&source[self.source_base..],physical.as_slice(),&self.masks.delimiters,Some(original),source,tokens,self.source_base,&mut lines);
  #[cfg(debug_assertions)]
  self.trace_row_work_highwater(source.len(),physical.credit.bytes().checked_add(lines.credit.bytes()).ok_or(io::ErrorKind::OutOfMemory)?,boundaries,tokens.len());
  drop(physical);lines.globalize(self.source_base);
  if let Some(actual)=original.storage.take_failure(){return Err(actual)}self.finished=final_input;
  // Consumed masks are scratch, never another retained source store. Keep only
  // the genuine unfinished logical header/literal window; committed Line spans
  // above are already in the SAME global native arena coordinates.
  let mut cut=self.structural.pending.as_ref().map_or(self.structural.offset,|line|line.header_start);
  if let Some(literal)=self.masks.multiline_literals.iter().find(|span|span.end>self.structural.offset){cut=cut.min(literal.start);}
  if cut>0{
   if !self.masks.visible.is_char_boundary(cut){return Err(io::Error::new(io::ErrorKind::InvalidData,"native mask compaction cuts a UTF8 code point"))}
   self.masks.visible.drain(..cut);self.masks.delimiters.drain(..cut);self.source_base+=cut;self.structural.offset-=cut;self.structural.early_physical=self.structural.early_physical.map(|at|at.saturating_sub(cut));
   if let Some(line)=&mut self.structural.pending{line.header_start-=cut;line.header_end-=cut;line.end-=cut;}
   let removed=self.masks.multiline_literals.partition_point(|span|span.end<=cut);self.masks.multiline_literals.drain(..removed);self.structural.literal_cursor=self.structural.literal_cursor.saturating_sub(removed);for span in &mut self.masks.multiline_literals{span.start=span.start.saturating_sub(cut);span.end-=cut;}
   self.boundaries=8;let start=tokens.partition_point(|token|token.span.end<=self.source_base);for token in tokens.range(start,tokens.len()).expect("retained layout token window").iter(){if token.kind==TokenKind::Newline||matches!(token.text(source),"{"|"}"|";"|"("){self.boundaries=self.boundaries.checked_add(2).ok_or(io::ErrorKind::OutOfMemory)?;}}
  }
  self.release_consumed_mask_storage()?;
  Ok(lines.into_batch(header_start))
 }
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::atomic::{Ordering};
 fn state<'a,'budget>(a:&'a crate::SettingAdmission<'budget>)->OriginalParseState<'a,'static,'budget>{OriginalParseState{storage:original_storage::Storage::new(a).unwrap(),fatal:Default::default(),unavailable:Default::default(),operational:Default::default(),observer:None,observer_stop:Default::default(),first_outer_block:Default::default()}}
 #[test]fn actual_demand_layout_batch_keeps_its_same_resource_root_after_cursor_drop(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));let source="/datum/a\n    var/value=1\n";let tokens=lex_spans(source).tokens;let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();let batch=cursor.advance(source,&tokens,&original,true).unwrap();assert_eq!(batch.len(),2);let owned=counter.load(Ordering::Acquire);assert!(owned>source.len()*2);drop(cursor);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (original.storage.bytes()+batch._credit.bytes()));assert!(counter.load(Ordering::Acquire)<owned);assert_eq!(batch[1].header_start,source.find("var/value").unwrap());drop(batch);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (original.storage.bytes()));drop(original);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_demand_layout_quota_and_operational_fault_refuse_before_mask_growth_and_keep_io_identity(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,5000,&||Ok(()));let source="/datum/a\n";let tokens=lex_spans(source).tokens;let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();
  // A distinct actual byte allocation holds the remaining resource capacity.
  // This storage-only fixture creates no source/model authority. Leave one
  // byte free so the genuine visible-mask allocation must refuse before grow.
  let free=5000usize.checked_sub(counter.load(Ordering::Acquire)).unwrap();assert!(free>1);
  let mut other_credit=a.reserve(0).unwrap();let mut other=Vec::<u8>::new();
  fund_buffer(&mut other,free-1,&mut other_credit,&a).unwrap();other.resize(free-1,0);
  let before=counter.load(Ordering::Acquire);assert_eq!(before,4999);
  let error=cursor.advance(source,&tokens,&original,true).err().unwrap();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);
  assert!(cursor.masks.visible.is_empty());assert_eq!(cursor.masks.visible.capacity(),0);assert_eq!(cursor.masks.delimiters.capacity(),0);assert_eq!(cursor.mask_credit.bytes(),0);
  assert_eq!(counter.load(Ordering::Acquire),before);assert_eq!(other.capacity(),free-1);assert_eq!(other_credit.bytes(),free-1);assert!(other.iter().all(|byte|*byte==0));
  drop(cursor);drop(original);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes()+other_credit.bytes());
  drop(other);drop(other_credit);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let fault=||Err(io::Error::from_raw_os_error(1450));let b=crate::SettingAdmission::new(&counter,1<<20,&fault);let error=NativeDemandLayoutCursor::new(&b).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_demand_layout_resumes_same_mask_group_inline_state_with_funded_batches(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));let source="/datum/a\n    var/list/value=list(\n        1,\n        2)\n/proc/p() return 3\n";let tokens=lex_spans(source).tokens;let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();let mut batches=Vec::new();let mut end=0;
  for raw in source.split_inclusive('\n'){end+=raw.len();let n=tokens.partition_point(|t|t.span.end<=end);batches.push(cursor.advance(&source[..end],&tokens[..n],&original,end==source.len()).unwrap());}
  let old=original_declaration_lines(source,Span::new(0,source.len()),&tokens);let rows:Vec<_>=batches.iter().flat_map(|batch|batch.iter()).collect();assert_eq!(rows.len(),old.len());for(a,b)in rows.into_iter().zip(old){assert_eq!((a.indent,a.header_start,a.header_end,a.same_line_body),(b.indent,b.header_start,b.header_end,b.same_line_body));}drop(cursor);assert!(counter.load(Ordering::Acquire)>crate::SettingChargeCounter::root_allocation_bytes());drop(batches);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (original.storage.bytes()));drop(original);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_sparse_large_native_demand_layout_pays_real_two_masks_and_growth_peak_without_source_multiplier(){
  let mut source=String::from("/*");source.push_str(&"x".repeat(1_550_000));source.push_str("*/\n");let tokens=lex_spans(&source).tokens;
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let peak=std::cell::Cell::new(0);let poll=||{peak.set(peak.get().max(counter.load(Ordering::Acquire)));Ok(())};let a=crate::SettingAdmission::new(&counter,6<<20,&poll);let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();let batch=cursor.advance(&source,&tokens,&original,true).unwrap();assert!(batch.is_empty());assert!(peak.get()>=crate::SettingChargeCounter::root_allocation_bytes() + (source.len()*2));assert_eq!(cursor.mask_credit.bytes(),0);assert_eq!((cursor.masks.visible.capacity(),cursor.masks.delimiters.capacity(),cursor.masks.multiline_literals.capacity()),(0,0,0));assert!(counter.load(Ordering::Acquire)<6<<20);drop(cursor);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (original.storage.bytes()+batch._credit.bytes()));drop(batch);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (original.storage.bytes()));drop(original);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn cloned_formal_identities_do_not_pin_two_independently_funded_layout_batches() {
    let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let fail=std::cell::Cell::new(false);
    let poll=||if fail.get(){Err(io::Error::from_raw_os_error(1450))}else{Ok(())};
    let a=crate::SettingAdmission::new(&used,1<<20,&poll);
    let source="/proc/first()\n/proc/second()\n";
    let first_end=source.find("/proc/second").unwrap();
    let tokens=lex_spans(source).tokens;
    let cut=tokens.partition_point(|t|t.span.end<=first_end);
    let original=state(&a);
    let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();
    let identity=cursor.identity();
    let another=identity.clone();
    let first=cursor.advance(&source[..first_end],&tokens[..cut],&original,false).unwrap();
    assert_eq!(first.len(),1);
    assert_eq!(first._credit.bytes(),first.lines.capacity()*mem::size_of::<Line>());
    let before=used.load(Ordering::Acquire);
    fail.set(true);
    assert_eq!(cursor.advance(source,&tokens,&original,true).err().unwrap().raw_os_error(),Some(1450));
    assert_eq!(used.load(Ordering::Acquire),before);
    // A new admission starts a new operation; this one has a latched I/O
    // failure. Rebuild only this tiny fixture to test both live batches.
    drop((first,cursor,identity,another,original));
    assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());

    let a=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));
    let original=state(&a);
    let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();
    let identity=cursor.identity();
    let another=identity.clone();
    let first=cursor.advance(&source[..first_end],&tokens[..cut],&original,false).unwrap();
    let second=cursor.advance(source,&tokens,&original,true).unwrap();
    let final_identity=cursor.finish_identity().unwrap();
    assert!(final_identity.same(&identity));
    assert!(final_identity.same(&another));
    let fixed=final_identity.credit.lease.bytes();
    let base=original.storage.bytes();
    assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (base+fixed+first._credit.bytes()+second._credit.bytes()));
    assert_eq!((first[0].header_start,second[0].header_start),(0,first_end));
    let second_bytes=second._credit.bytes();
    drop(first);
    assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (base+fixed+second_bytes));
    drop((final_identity,identity,another));
    assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (base+second_bytes));
    drop((second,original));
    assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn exact_visible_string_buffer_replacement_keeps_peak_funding_and_refunds_old_storage() {
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=crate::SettingAdmission::new(&counter,4096,&||Ok(()));let mut credit=a.reserve(0).unwrap();let mut visible=String::new();
  fund_visible_string(&mut visible,8,&mut credit,&a).unwrap();assert_eq!(visible.capacity(),8);assert_eq!(credit.bytes(),8);
  visible.push_str("\u{3b1}\u{3b2}");fund_visible_string(&mut visible,23,&mut credit,&a).unwrap();
  assert_eq!(visible,"\u{3b1}\u{3b2}");assert_eq!(visible.capacity(),23);assert_eq!(credit.bytes(),23);
  assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes()+23);
  drop(visible);drop(credit);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let limit=crate::SettingChargeCounter::root_allocation_bytes()+7;let b=crate::SettingAdmission::new(&counter,limit,&||Ok(()));let mut credit=b.reserve(0).unwrap();let mut denied=String::new();
  assert_eq!(fund_visible_string(&mut denied,8,&mut credit,&b).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert_eq!(denied.capacity(),0);drop(denied);drop(credit);
  assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn incremental_visible_string_first_io_keeps_partial_storage_valid_and_no_batch_escapes() {
  let source=format!("/datum/\u{3b1}\n    /* \u{3b2}{} */ var/value=1\n","x".repeat(2050));let tokens=lex_spans(&source).tokens;let mut saw_partial=false;
  // Bounded fault positions, not a timing benchmark. At least one must stop
  // midway through the byte-preserving comment mask, not only before work.
  for stop in 1..=64 {
   let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let calls=std::cell::Cell::new(0usize);let armed=std::cell::Cell::new(false);
   let poll=||{if armed.get(){let n=calls.get()+1;calls.set(n);if n==stop{return Err(io::Error::from_raw_os_error(1450))}}Ok(())};
   let a=crate::SettingAdmission::new(&counter,1<<20,&poll);let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();armed.set(true);
   match cursor.advance(&source,&tokens,&original,true) {
    Err(actual)=>{assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(calls.get(),stop);saw_partial|=!cursor.masks.visible().is_empty()&&cursor.masks.visible().len()<source.len();},
    Ok(batch)=>{assert!(calls.get()<stop);drop(batch);},
   }
   assert!(std::str::from_utf8(cursor.masks.visible().as_bytes()).is_ok());
   drop(cursor);drop(original);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
  assert!(saw_partial,"an actual mid-mask first IO was exercised; no invalid String or layout batch escaped it");
 }
 #[test]fn actual_long_source_keeps_only_live_header_mask_window_and_dropped_batch_rows_do_not_accumulate_debt(){
  let source="/datum/a\n".repeat(2048);let tokens=lex_spans(&source).tokens;let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,64<<10,&||Ok(()));let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();let mut end=0;
  for raw in source.split_inclusive('\n'){end+=raw.len();let n=tokens.partition_point(|token|token.span.end<=end);let batch=cursor.advance(&source[..end],&tokens[..n],&original,end==source.len()).unwrap();assert_eq!(batch.len(),1);assert_eq!(batch[0].header_start,end-raw.len());assert!(cursor.masks.visible.is_empty());assert!(cursor.masks.visible.capacity()<128);assert!(counter.load(Ordering::Acquire)<64<<10);drop(batch);}
  assert_eq!(cursor.source_base,source.len());drop(cursor);drop(original);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn exact_layout_growth_keeps_real_global_capacity_and_preserves_bounded_frontiers() {
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));
  let mut strings=a.reserve(0).unwrap();let mut bytes=a.reserve(0).unwrap();let mut spans=a.reserve(0).unwrap();
  let mut text=String::new();let mut data=Vec::<u8>::new();let mut rows=Vec::<Span>::new();
  fund_visible_string(&mut text,4,&mut strings,&a).unwrap();text.push_str("\u{3b1}\u{3b2}");
  fund_buffer(&mut data,4,&mut bytes,&a).unwrap();data.extend_from_slice(&[1,2,3,4]);
  fund_buffer(&mut rows,4,&mut spans,&a).unwrap();rows.push(Span::new(10,20));
  // Deterministic bounded work, not a timing benchmark or an assertion that
  // Global realloc must stay in-place. Every frontier requests only its exact
  // logical capacity; no application-level prefix copy is required.
  for desired in 5..=132 {
   fund_visible_string(&mut text,desired,&mut strings,&a).unwrap();
   fund_buffer(&mut data,desired,&mut bytes,&a).unwrap();
   fund_buffer(&mut rows,desired,&mut spans,&a).unwrap();
   assert_eq!((text.capacity(),data.capacity(),rows.capacity()),(desired,desired,desired));
   assert_eq!((strings.bytes(),bytes.bytes(),spans.bytes()),(desired,desired,desired*mem::size_of::<Span>()));
   assert_eq!(&text[..4],"\u{3b1}\u{3b2}");assert!(text[4..].bytes().all(|v|v==b'x'));
   assert_eq!(&data[..4],&[1,2,3,4]);assert!(data[4..].iter().all(|v|*v==5));
   assert_eq!(rows.as_slice(),&[Span::new(10,20)]);
   text.push('x');data.push(5);
  }
  let pointers=(text.as_ptr(),data.as_ptr(),rows.as_ptr());let held=counter.load(Ordering::Acquire);
  // A capacity-sufficient query does not allocate or change the lease.
  fund_visible_string(&mut text,132,&mut strings,&a).unwrap();fund_buffer(&mut data,132,&mut bytes,&a).unwrap();fund_buffer(&mut rows,132,&mut spans,&a).unwrap();
  assert_eq!((text.as_ptr(),data.as_ptr(),rows.as_ptr()),pointers);assert_eq!(counter.load(Ordering::Acquire),held);
  drop((text,data,rows));drop((strings,bytes,spans));
  assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn exact_layout_realloc_cannot_spend_delta_only_when_old_plus_new_peak_is_denied() {
  for string in [false,true] {
   let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
   let limit=crate::SettingChargeCounter::root_allocation_bytes()+4+9-1;
   let a=crate::SettingAdmission::new(&counter,limit,&||Ok(()));let mut credit=a.reserve(0).unwrap();
   let mut rows=Vec::new();let mut text=String::new();
   if string {fund_visible_string(&mut text,4,&mut credit,&a).unwrap();text.push_str("\u{3b1}");}
   else {fund_buffer(&mut rows,4,&mut credit,&a).unwrap();rows.extend_from_slice(&[1u8,2]);}
   let actual=if string {fund_visible_string(&mut text,9,&mut credit,&a)}else{fund_buffer(&mut rows,9,&mut credit,&a)};
   assert_eq!(actual.unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert_eq!(credit.bytes(),4);
   if string {assert_eq!(text,"\u{3b1}");assert_eq!(text.capacity(),4);}else{assert_eq!(rows,&[1,2]);assert_eq!(rows.capacity(),4);}
   assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes()+4);
   drop((text,rows));drop(credit);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 }
 #[test]
 fn exact_layout_realloc_first_io_preserves_actual_error_and_conservative_credit_until_drop() {
  for string in [false,true] {for stop in 1..=3 {
   let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
   let calls=std::cell::Cell::new(0);let armed=std::cell::Cell::new(false);let observed_peak=std::cell::Cell::new(0);
   let poll=||{if armed.get(){observed_peak.set(observed_peak.get().max(counter.load(Ordering::Acquire)));let n=calls.get()+1;calls.set(n);if n==stop{return Err(io::Error::from_raw_os_error(1450));}}Ok(())};
   let a=crate::SettingAdmission::new(&counter,4096,&poll);let mut credit=a.reserve(0).unwrap();let mut rows=Vec::new();let mut text=String::new();
   if string {fund_visible_string(&mut text,4,&mut credit,&a).unwrap();text.push_str("\u{3b1}");}
   else {fund_buffer(&mut rows,4,&mut credit,&a).unwrap();rows.extend_from_slice(&[1u8,2]);}
   armed.set(true);
   let actual=if string{fund_visible_string(&mut text,9,&mut credit,&a)}else{fund_buffer(&mut rows,9,&mut credit,&a)};
   assert_eq!(actual.unwrap_err().raw_os_error(),Some(1450));assert_eq!(calls.get(),stop);
   let expected=if stop<3 {4}else{9};let held=if stop<3 {4}else{4+9};
   assert_eq!(credit.bytes(),held);
   if string{assert_eq!(text,"\u{3b1}");assert_eq!(text.capacity(),expected);}else{assert_eq!(rows,&[1,2]);assert_eq!(rows.capacity(),expected);}
   if stop==3 {assert_eq!(observed_peak.get(),crate::SettingChargeCounter::root_allocation_bytes()+4+9);}
   drop((text,rows));drop(credit);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }}
 }

 #[test]
 fn actual_burst_masks_release_highwater_without_reclaiming_live_batches_or_unfinished_window() {
  let burst=format!("/*{}*/\n","x".repeat(65_536));
  let source=format!("{burst}/datum/a\n    var/\u{3b1}=list(\n        1,\n        2)\n");let tokens=lex_spans(&source).tokens;
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();let identity=cursor.identity();let cloned=identity.clone();
  let end=burst.len();let n=tokens.partition_point(|token|token.span.end<=end);
  let first=cursor.advance(&source[..end],&tokens[..n],&original,false).unwrap();assert!(first.is_empty());
  assert_eq!(cursor.source_base,end);assert_eq!(cursor.mask_credit.bytes(),0);
  assert_eq!((cursor.masks.visible.capacity(),cursor.masks.delimiters.capacity(),cursor.masks.multiline_literals.capacity()),(0,0,0));
  let header_end=end+"/datum/a\n".len();let n=tokens.partition_point(|token|token.span.end<=header_end);
  let header=cursor.advance(&source[..header_end],&tokens[..n],&original,false).unwrap();assert_eq!(header.len(),1);
  let owned_header=(header[0].header_start,header[0].header_end,header[0].end);assert_eq!(owned_header,(end,end+"/datum/a".len(),header_end-1));
  // The SAME inline layout kernel trims segment whitespace and publishes
  // end==header_end, excluding the consumed physical trailing newline.
  assert_eq!(source.as_bytes()[header[0].end],b'\n');
  let partial_end=source.find("        2)").unwrap();let n=tokens.partition_point(|token|token.span.end<=partial_end);
  let partial=cursor.advance(&source[..partial_end],&tokens[..n],&original,false).unwrap();assert!(partial.is_empty());
  assert!(cursor.structural.pending.is_some());assert!(!cursor.masks.visible.is_empty());assert!(cursor.mask_credit.bytes()>0);
  assert_eq!(cursor.source_base,header_end+4); // only leading indentation is no longer needed
  assert_eq!(cursor.masks.visible(),&source[cursor.source_base..partial_end]);assert!(cursor.masks.visible().contains("\u{3b1}"));assert!(cursor.matches_identity(&identity));
  let finish=cursor.advance(&source,&tokens,&original,true).unwrap();assert_eq!(finish.len(),1);
  assert_eq!(finish[0].header_start,header_end+4);assert_eq!(finish[0].end,source.len()-1);
  assert_eq!(source.as_bytes()[finish[0].end],b'\n');
  assert_eq!((header[0].header_start,header[0].header_end,header[0].end),owned_header);
  assert_eq!(cursor.source_base,source.len());assert_eq!(cursor.mask_credit.bytes(),0);
  assert_eq!((cursor.masks.visible.capacity(),cursor.masks.delimiters.capacity(),cursor.masks.multiline_literals.capacity()),(0,0,0));
  let finished_identity=cursor.finish_identity().unwrap();assert!(finished_identity.same(&identity));assert!(identity.same(&cloned));let fixed=identity.credit.lease.bytes();assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes()+fixed+original.storage.bytes()+first._credit.bytes()+header._credit.bytes()+partial._credit.bytes()+finish._credit.bytes());
  drop((first,header,partial,finish,original,identity,cloned,finished_identity));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn consumed_mask_release_first_io_physically_frees_buffers_before_refund_and_preserves_error() {
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let calls=std::cell::Cell::new(0);let armed=std::cell::Cell::new(false);
  let poll=||{if armed.get(){calls.set(calls.get()+1);return Err(io::Error::from_raw_os_error(1450));}Ok(())};
  let a=crate::SettingAdmission::new(&counter,4096,&poll);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();
  // Storage-only failure fixture: empty buffers hold no source/body authority.
  fund_visible_string(&mut cursor.masks.visible,8,&mut cursor.mask_credit,&a).unwrap();
  fund_buffer(&mut cursor.masks.delimiters,8,&mut cursor.mask_credit,&a).unwrap();
  fund_buffer(&mut cursor.masks.multiline_literals,4,&mut cursor.mask_credit,&a).unwrap();
  let held=cursor.mask_credit.bytes();assert_eq!(held,16+4*mem::size_of::<Span>());
  let before=counter.load(Ordering::Acquire);armed.set(true);
  let actual=cursor.release_consumed_mask_storage().unwrap_err();assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(calls.get(),1);
  assert_eq!((cursor.masks.visible.capacity(),cursor.masks.delimiters.capacity(),cursor.masks.multiline_literals.capacity()),(0,0,0));
  assert_eq!(cursor.mask_credit.bytes(),held);assert_eq!(counter.load(Ordering::Acquire),before);
  drop(cursor);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[cfg(debug_assertions)]
 #[test]
 fn layout_highwater_trace_metadata_is_in_exact_existing_owner_funding_and_visit() {
  assert_eq!(mem::size_of::<std::sync::atomic::AtomicUsize>(),mem::size_of::<usize>());
  assert!(mem::size_of::<LayoutCredit>()>=mem::size_of::<crate::SettingRootLease>()+mem::size_of::<usize>());
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,4096,&||Ok(()));
  let cursor=NativeDemandLayoutCursor::new(&a).unwrap();let identity=cursor.identity();
  let fixed=mem::size_of::<LayoutCredit>()+2*mem::size_of::<usize>();
  assert_eq!(cursor.credit.lease.bytes(),fixed);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes()+fixed);
  let mut first=None;identity.visit_storage(|address,capacity,used|{if first.is_none(){first=Some((address,capacity,used));}});
  let (_,capacity,used)=first.unwrap();assert_eq!((capacity,used),(fixed,fixed));
  drop(cursor);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes()+fixed);
  drop(identity);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[cfg(debug_assertions)]
 #[test]
 fn layout_row_work_trace_is_geometrically_bounded_and_cannot_admit_work() {
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,4096,&||Ok(()));let cursor=NativeDemandLayoutCursor::new(&a).unwrap();
  cursor.credit.row_work_trace_next.store(1<<20,Ordering::Relaxed);let before=counter.load(Ordering::Acquire);let mut samples=0;
  // Metadata-only scheduling control. These sizes do NOT reserve or grant
  // row work, source/header authority, or any extra quota to this4KiB host.
  for bytes in [0,(1<<20)-1,1<<20,(1<<20)+1,2<<20,(2<<20)+1,4<<20,8<<20,16<<20,32<<20,64<<20,(128<<20)-1] {
   if cursor.claim_row_work_trace_sample(bytes){samples+=1;assert!(!cursor.claim_row_work_trace_sample(bytes));}
   assert_eq!(counter.load(Ordering::Acquire),before);
  }
  assert_eq!(samples,7);
  cursor.credit.row_work_trace_next.store(1<<20,Ordering::Relaxed);
  assert!(cursor.claim_row_work_trace_sample(3<<20));
  assert_eq!(cursor.credit.row_work_trace_next.load(Ordering::Relaxed),6<<20);
  assert!(!cursor.claim_row_work_trace_sample((6<<20)-1));assert!(cursor.claim_row_work_trace_sample(6<<20));
  cursor.credit.row_work_trace_next.store(usize::MAX,Ordering::Relaxed);assert!(!cursor.claim_row_work_trace_sample(usize::MAX));
  assert_eq!(counter.load(Ordering::Acquire),before);drop(cursor);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

 fn line_owner_shape(rows:&[Line])->Vec<(usize,usize,usize,usize,bool,bool)>{
  rows.iter().map(|r|(r.indent,r.header_start,r.header_end,r.end,r.explicit_block_opener,r.same_line_body)).collect()
 }
 fn line_owner_probe(at:usize)->Line{Line{indent:0,header_start:at,header_end:at+1,end:at+1,explicit_block_opener:false,same_line_body:false}}
 #[test]
 fn owned_layout_rows_keep_same_kernels_shapes_and_both_live_allocations(){
  for source in [
   "/datum/a {\n var/value=1;\n var/other=2;\n}\n/proc/p()\n return 3\n",
   "/proc/p() {\n if(1) do {\n return 1;\n } while(0);\n}\n/datum/b\n",
   "/datum/a\n var/value=new /datum/other {x=1; y=2}\n/proc/p() return 2\n",
  ]{
   let tokens=lex_spans(source).tokens;
   let expected_physical=NativeStructuralCursor::default().advance(source,source.as_bytes(),&[],None,source,TokenWindow::from_slice(&tokens),0,true).unwrap();
   let expected=NativeInlineBlockCursor::default().advance(source,&expected_physical,source.as_bytes(),None,source,TokenWindow::from_slice(&tokens),0);
   let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
   let peak=std::cell::Cell::new(0);let poll=||{peak.set(peak.get().max(counter.load(Ordering::Acquire)));Ok(())};
   let a=crate::SettingAdmission::new(&counter,1<<20,&poll);let original=state(&a);
   let base=counter.load(Ordering::Acquire);
   let mut physical=OwnedLayoutLines::new(&a).unwrap();
   NativeStructuralCursor::default().advance_into(source,source.as_bytes(),&[],Some(&original),source,TokenWindow::from_slice(&tokens),0,true,&mut physical).unwrap();
   assert!(original.storage.take_failure().is_none());
   assert_eq!(line_owner_shape(physical.as_slice()),line_owner_shape(&expected_physical));
   assert_eq!(physical.credit.bytes(),physical.rows.capacity()*mem::size_of::<Line>());
   let physical_bytes=physical.credit.bytes();assert!(physical_bytes>0);
   let mut lines=OwnedLayoutLines::new(&a).unwrap();
   NativeInlineBlockCursor::default().advance_into(source,physical.as_slice(),source.as_bytes(),Some(&original),source,TokenWindow::from_slice(&tokens),0,&mut lines);
   assert!(original.storage.take_failure().is_none());
   assert_eq!(line_owner_shape(lines.as_slice()),line_owner_shape(&expected));
   let final_bytes=lines.credit.bytes();assert!(final_bytes>0);
   assert_eq!(final_bytes,lines.rows.capacity()*mem::size_of::<Line>());
   assert_eq!(counter.load(Ordering::Acquire),base+physical_bytes+final_bytes);
   assert!(peak.get()>=base+physical_bytes+final_bytes);
   drop(physical);assert_eq!(counter.load(Ordering::Acquire),base+final_bytes);
   let batch=lines.into_batch(None);drop(original);
   assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes()+final_bytes);
   assert_eq!(line_owner_shape(&batch),line_owner_shape(&expected));drop(batch);
   assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 }
 #[test]
 fn owned_layout_rows_pending_initializer_does_not_pay_phantom_delimiter_rows(){
  let mut source=String::from("/datum/a\n    var/value = list(\n");source.push_str(&"        list(1),\n".repeat(300));
  let cut=source.len();source.push_str("    )\n/datum/b\n");
  let tokens=lex_spans(&source).tokens;let n=tokens.partition_point(|token|token.span.end<=cut);
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=crate::SettingAdmission::new(&counter,64<<10,&||Ok(()));let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();
  let first=cursor.advance(&source[..cut],&tokens[..n],&original,false).unwrap();
  assert_eq!(first.len(),1);assert!(cursor.structural.pending.is_some());assert!(cursor.structural.depth>0);
  assert_eq!(first._credit.bytes(),first.lines.capacity()*mem::size_of::<Line>());
  assert!(first._credit.bytes()<=4*mem::size_of::<Line>());
  let second=cursor.advance(&source,&tokens,&original,true).unwrap();
  let expected=original_declaration_lines(&source,Span::new(0,source.len()),&tokens);
  let actual:Vec<Line>=first.iter().chain(second.iter()).cloned().collect();
  assert_eq!(line_owner_shape(&actual),line_owner_shape(&expected));
  drop(actual);drop(cursor);drop(original);
  assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes()+first._credit.bytes()+second._credit.bytes());
  drop((first,second));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn owned_layout_rows_deny_actual_old_plus_new_peak_before_growth(){
  let root=crate::SettingChargeCounter::root_allocation_bytes();let size=mem::size_of::<Line>();
  let counter=crate::SettingChargeCounter::try_new(root).unwrap();
  let a=crate::SettingAdmission::new(&counter,root+4096+4*size+8*size-1,&||Ok(()));let original=state(&a);let mut rows=OwnedLayoutLines::new(&a).unwrap();
  for at in 0..4{assert!(rows.push_line(line_owner_probe(at),Some(&original)));}
  let before=line_owner_shape(rows.as_slice());let ptr=rows.rows.as_ptr();
  assert!(!rows.push_line(line_owner_probe(4),Some(&original)));
  assert_eq!(original.storage.take_failure().unwrap().kind(),io::ErrorKind::OutOfMemory);
  assert_eq!(line_owner_shape(rows.as_slice()),before);assert_eq!(rows.rows.as_ptr(),ptr);
  assert_eq!(rows.rows.capacity(),4);assert_eq!(rows.credit.bytes(),4*size);
  drop(rows);drop(original);assert_eq!(counter.load(Ordering::Acquire),root);
 }
 #[test]
 fn owned_layout_rows_keep_first_io_and_conservative_credit_on_growth_failure(){
  // One existing state poll, then grow/reserve/refund checkpoints. The final
  // failure is after real Vec growth but before prior-capacity credit retires.
  for stop in 1..=4{
   let root=crate::SettingChargeCounter::root_allocation_bytes();let size=mem::size_of::<Line>();
   let counter=crate::SettingChargeCounter::try_new(root).unwrap();let calls=std::cell::Cell::new(0);let armed=std::cell::Cell::new(false);
   let poll=||{if armed.get(){let n=calls.get()+1;calls.set(n);if n==stop{return Err(io::Error::from_raw_os_error(1450));}}Ok(())};
   let a=crate::SettingAdmission::new(&counter,1<<20,&poll);let original=state(&a);let mut rows=OwnedLayoutLines::new(&a).unwrap();
   for at in 0..4{assert!(rows.push_line(line_owner_probe(at),Some(&original)));}
   let before=line_owner_shape(rows.as_slice());armed.set(true);
   assert!(!rows.push_line(line_owner_probe(4),Some(&original)));
   assert_eq!(original.storage.take_failure().unwrap().raw_os_error(),Some(1450));assert_eq!(calls.get(),stop);
   assert_eq!(line_owner_shape(rows.as_slice()),before);
   assert_eq!(rows.rows.capacity(),if stop<4{4}else{8});
   assert_eq!(rows.credit.bytes(),if stop<4{4*size}else{(4+8)*size});
   drop(rows);drop(original);assert_eq!(counter.load(Ordering::Acquire),root);
  }
 }
 #[test]
 fn owned_layout_rows_foreign_primary_refuses_without_a_grant_or_mutation(){
  // Even equal resource-counter identity cannot substitute for the exact
  // admission host borrowed by this actual output owner.
  for same_counter in [false,true]{for prior_io in [false,true]{
   let root=crate::SettingChargeCounter::root_allocation_bytes();
   let counter=crate::SettingChargeCounter::try_new(root).unwrap();
   let other=if same_counter{Arc::clone(&counter)}else{crate::SettingChargeCounter::try_new(root).unwrap()};
   let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));let original=state(&a);
   let mut rows=OwnedLayoutLines::new(&a).unwrap();assert!(rows.push_line(line_owner_probe(0),Some(&original)));
   let armed=std::cell::Cell::new(false);let polls=std::cell::Cell::new(0);
   let poll=||{polls.set(polls.get()+1);if armed.get(){Err(io::Error::from_raw_os_error(1450))}else{Ok(())}};
   let foreign=crate::SettingAdmission::new(&other,1<<20,&poll);let foreign_original=state(&foreign);
   assert!(!std::ptr::eq(&a,&foreign));
   let before=line_owner_shape(rows.as_slice());let ptr=rows.rows.as_ptr();let capacity=rows.rows.capacity();let credit=rows.credit.bytes();
   let own_used=counter.load(Ordering::Acquire);let other_used=other.load(Ordering::Acquire);
   if prior_io{armed.set(true);assert!(foreign.checkpoint().is_err());}
   let prior_polls=polls.get();
   assert!(!rows.push_line(line_owner_probe(1),Some(&foreign_original)));
   let actual=foreign_original.storage.take_failure().unwrap();
   if prior_io{assert_eq!(actual.raw_os_error(),Some(1450));}else{assert_eq!(actual.kind(),io::ErrorKind::InvalidInput);assert!(actual.to_string().contains("another primary host"));}
   assert_eq!(polls.get(),prior_polls,"wrong-host refusal must not allocate or poll the foreign host");
   assert_eq!(line_owner_shape(rows.as_slice()),before);assert_eq!(rows.rows.as_ptr(),ptr);
   assert_eq!(rows.rows.capacity(),capacity);assert_eq!(rows.credit.bytes(),credit);
   assert_eq!(counter.load(Ordering::Acquire),own_used);assert_eq!(other.load(Ordering::Acquire),other_used);
   assert!(original.storage.take_failure().is_none());
   drop(foreign_original);drop(rows);drop(original);
   assert_eq!(counter.load(Ordering::Acquire),root);assert_eq!(other.load(Ordering::Acquire),root);
  }}
 }
 #[test]
 fn owned_layout_rows_absent_primary_refuses_and_keeps_first_observed_io(){
  for prior_io in [false,true]{
   let root=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(root).unwrap();
   let armed=std::cell::Cell::new(false);let polls=std::cell::Cell::new(0);
   let poll=||{polls.set(polls.get()+1);if armed.get(){Err(io::Error::from_raw_os_error(1450))}else{Ok(())}};
   let a=crate::SettingAdmission::new(&counter,1<<20,&poll);let original=state(&a);
   let mut rows=OwnedLayoutLines::new(&a).unwrap();assert!(rows.push_line(line_owner_probe(0),Some(&original)));
   let before=line_owner_shape(rows.as_slice());let ptr=rows.rows.as_ptr();let capacity=rows.rows.capacity();let credit=rows.credit.bytes();let used=counter.load(Ordering::Acquire);
   if prior_io{armed.set(true);assert!(a.checkpoint().is_err());}
   let prior_polls=polls.get();
   assert!(!rows.push_line(line_owner_probe(1),None));
   let actual=a.take_operational_error().unwrap();
   if prior_io{assert_eq!(actual.raw_os_error(),Some(1450));}else{assert_eq!(actual.kind(),io::ErrorKind::InvalidInput);assert!(actual.to_string().contains("actual primary host"));}
   assert_eq!(polls.get(),prior_polls,"missing primary must refuse before another poll or allocation");
   assert_eq!(line_owner_shape(rows.as_slice()),before);assert_eq!(rows.rows.as_ptr(),ptr);
   assert_eq!(rows.rows.capacity(),capacity);assert_eq!(rows.credit.bytes(),credit);assert_eq!(counter.load(Ordering::Acquire),used);
   drop(rows);drop(original);assert_eq!(counter.load(Ordering::Acquire),root);
  }
 }

 #[cfg(debug_assertions)]
 #[test]
 fn pending_opener_reverse_sweep_uses_only_processed_window_and_same_unified_depth(){
  for (bytes,start,end,expected)in[
   (&b"call(x) ("[..],0,7,None), // later unprocessed '(' is deliberately excluded
   (&b"call(x) ("[..],0,9,Some((8,b'('))),
   (&b"old( new()"[..],4,10,None), // opener outside pending header is excluded
   (&b"old( new()"[..],0,10,Some((3,b'('))),
   (&b"((x)"[..],0,4,Some((0,b'('))),
   (&b"((x"[..],0,3,Some((1,b'('))),
   (&b"([)]"[..],0,4,None), // same unified depth, NOT a new typed nesting grammar
   (&b"x[y]"[..],0,4,None),
   (&b"x[y"[..],0,3,Some((1,b'['))),
   (&b"("[..],1,0,None),(&b"("[..],0,2,None),
  ]{
   assert_eq!(last_unmatched_layout_opener(bytes,start,end),expected,"{bytes:?} {start}..{end}");
  }
 }
 #[cfg(debug_assertions)]
 #[test]
 fn pending_opener_metadata_distinguishes_actual_punctuation_from_typed_interpolation_without_payload_read(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));
  // Same final-token/literal-row fixture contract as the existing literal
  // layout controls. It supplies no procedure/source/body availability grant.
  let source="call(\"a([x]b)\")";
  let quote=source.find('"').unwrap();let open=source.find('[').unwrap();let close=source.find(']').unwrap();let last_quote=source.rfind('"').unwrap();
  let begin=Span::new(quote,open+1);let end=Span::new(close,last_quote+1);
  let rows=[SpanToken{kind:TokenKind::Ident,span:Span::new(0,4)},SpanToken{kind:TokenKind::Punctuation,span:Span::new(4,5)},
   SpanToken{kind:TokenKind::Interpolation,span:begin},SpanToken{kind:TokenKind::Ident,span:Span::new(open+1,close)},
   SpanToken{kind:TokenKind::Interpolation,span:end},SpanToken{kind:TokenKind::Punctuation,span:Span::new(last_quote+1,source.len())}];
  let mut facts=crate::OriginalPrimaryLiteralFacts::new(&a).unwrap();
  for(span,value)in[(begin,crate::OriginalTokenValue::InterpBegin("a(")),(end,crate::OriginalTokenValue::InterpEnd("b)"))]{
   let data=crate::OriginalLiteralData::from_value_with_mode_using(source[span.range()].into(),value,crate::OriginalStringMode::Normal,&a).unwrap();facts.append_actual(span,data,&a).unwrap();
  }
  let tokens=TokenWindow::from_slice(&rows);let mut mask=NativeLayoutMaskCursor::default();
  assert!(mask.advance_with_literal_facts(source,Span::new(0,source.len()),tokens,None,Some((facts.rows(),0))));
  assert_eq!(last_unmatched_layout_opener(&mask.delimiters,0,source.len()),None);
  assert_eq!(mask.delimiters[quote+2],b' ');assert_eq!(mask.delimiters[last_quote-1],b' '); // payload parens are not structural
  let before_outer_close=last_quote+1;assert_eq!(last_unmatched_layout_opener(&mask.delimiters,0,before_outer_close),Some((4,b'(')));
  let before_interpolation_close=close;assert_eq!(last_unmatched_layout_opener(&mask.delimiters,0,before_interpolation_close),Some((open,b'[')));
  let (token,kind)=layout_opener_token_metadata(open,tokens,Some(facts.rows()));assert_eq!(token.unwrap().span,begin);assert_eq!(kind,Some("InterpBegin"));
  let (token,kind)=layout_opener_token_metadata(4,tokens,Some(facts.rows()));assert_eq!(token.unwrap().kind,TokenKind::Punctuation);assert!(kind.is_none());
  let held=used.load(Ordering::Acquire);a.record_operational_error(io::Error::from_raw_os_error(1450));
  assert_eq!(layout_opener_token_metadata(open,tokens,Some(facts.rows())).1,Some("InterpBegin"));
  assert_eq!(a.take_operational_error().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),held);
  drop(mask);drop(facts);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[cfg(debug_assertions)]
 #[test]
 fn pending_layout_header_diagnostic_borrows_utf8_and_redacts_payloads(){
  let utf8="\u{3b1}".repeat(140);let clipped=layout_trace_clip(&utf8,255);
  assert_eq!(clipped.len(),254);assert_eq!(clipped.as_ptr(),utf8.as_ptr());assert!(clipped.is_char_boundary(clipped.len()));
  let source="/proc/probe(arg=\"sensitive(payload)\")\n";let rows=lex_spans(source).tokens;let tokens=TokenWindow::from_slice(&rows);
  let prefix=layout_trace_header_prefix(source,tokens,0).unwrap();assert_eq!(prefix,"/proc/probe(arg=");assert_eq!(prefix.as_ptr(),source.as_ptr());
  for kind in [TokenKind::String,TokenKind::Resource,TokenKind::Interpolation,TokenKind::Comment,TokenKind::Number,TokenKind::Unknown]{
   // No payload read even if the supplied diagnostic-only span is invalid.
   assert_eq!(layout_trace_token_spelling(source,SpanToken{kind,span:Span::new(usize::MAX-1,usize::MAX)}),"<payload omitted>");
  }
  let name=rows.iter().find(|token|token.kind==TokenKind::Ident&&token.text(source)=="probe").unwrap();
  assert_eq!(layout_trace_token_spelling(source,*name),"probe");
  let mut large=String::from("/proc/");large.push_str(&"x".repeat(300));large.push_str("()\n");let rows=lex_spans(&large).tokens;
  assert_eq!(layout_trace_header_prefix(&large,TokenWindow::from_slice(&rows),0).unwrap().len(),256);
  let name=rows.iter().find(|token|token.kind==TokenKind::Ident).unwrap();assert_eq!(layout_trace_token_spelling(&large,*name).len(),4); // proc
  let long=rows.iter().find(|token|token.span.end-token.span.start==300).unwrap();assert_eq!(layout_trace_token_spelling(&large,*long).len(),24);
 }

}
