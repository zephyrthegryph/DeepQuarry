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
pub(super) struct LayoutCredit { lease: crate::SettingRootLease }

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
  let mask_credit=a.reserve(0).map_err(|e|actual_error(a,e))?;
  Ok(Self{masks:Default::default(),structural:Default::default(),inline:Default::default(),source_base:0,counted_tokens:0,boundaries:8,finished:false,credit:LayoutOwner::new(LayoutCredit{lease}),mask_credit,a})
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
 pub(super) fn advance(&mut self,source:&str,tokens:&[SpanToken],original:&OriginalParseState<'_,'_,'_>,final_input:bool)->io::Result<NativeLayoutBatch>{self.advance_with_literal_facts(source,TokenWindow::from_slice(tokens),original,final_input,None)}
 pub(super) fn advance_with_literal_facts(&mut self,source:&str,tokens:TokenWindow<'_>,original:&OriginalParseState<'_,'_,'_>,final_input:bool,facts:Option<crate::OriginalLiteralRows<'_>>)->io::Result<NativeLayoutBatch>{
  self.a.checkpoint().map_err(|e|self.a.take_operational_error().unwrap_or(e))?;
  if !std::ptr::eq(original.storage.a,self.a){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native demanded layout belongs to a foreign primary resource host"))}
  if self.finished||self.counted_tokens>tokens.len()||self.source_base>source.len()||self.masks.visible.len()>source.len().saturating_sub(self.source_base){return Err(io::Error::new(io::ErrorKind::InvalidInput,"native demanded layout has no new complete physical source frontier"))}
  let(mut boundaries,mut new_multiline)=(self.boundaries,0usize);
  for token in tokens.range(self.counted_tokens,tokens.len()).expect("checked layout token frontier").iter(){self.a.checkpoint().map_err(|e|self.a.take_operational_error().unwrap_or(e))?;let Some(text)=source.get(token.span.range())else{return Err(io::Error::new(io::ErrorKind::InvalidInput,"native demanded layout token escapes actual source"))};if token.kind==TokenKind::Newline||matches!(text,"{"|"}"|";"|"("){boundaries=boundaries.checked_add(2).ok_or(io::ErrorKind::OutOfMemory)?;}if matches!(token.kind,TokenKind::String|TokenKind::Interpolation)&&text.contains('\n'){new_multiline=new_multiline.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;}}
  // Preserve the existing structural/inline row peak bound for this advance.
  // Earlier returned batches pay their own exact buffers. Reserve before any
  // mask or layout work, then release only after the physical rows are dead.
  let rows=boundaries.checked_mul(mem::size_of::<Line>()).and_then(|n|n.checked_mul(8)).ok_or(io::ErrorKind::OutOfMemory)?;
  let mut row_work=self.a.reserve(rows).map_err(|e|actual_error(self.a,e))?;
  let visible_bytes=source.len()-self.source_base;
  fund_visible_string(&mut self.masks.visible,visible_bytes,&mut self.mask_credit,self.a)?;
  fund_buffer(&mut self.masks.delimiters,visible_bytes,&mut self.mask_credit,self.a)?;
  let spans=self.masks.multiline_literals.len().checked_add(new_multiline).ok_or(io::ErrorKind::OutOfMemory)?;
  if spans>self.masks.multiline_literals.capacity(){
   // Actual next consumed tokens were counted above, so the native mask
   // pass appends inside this exact already funded allocation.
   let capacity=spans.max(4).checked_next_power_of_two().ok_or(io::ErrorKind::OutOfMemory)?;
   fund_buffer(&mut self.masks.multiline_literals,capacity,&mut self.mask_credit,self.a)?;
  }
  if !self.masks.advance_with_literal_facts(source,Span::new(self.source_base,source.len()),tokens,Some(original),facts.map(|rows|(rows,0))){return Err(original.storage.take_failure().unwrap_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"native mask continuation has no actual complete-token provenance")))}
  self.counted_tokens=tokens.len();self.boundaries=boundaries;
  let visible=self.masks.visible();let complete=if final_input{visible.len()}else{visible.rfind('\n').map_or(0,|at|at+1)};let physical=self.structural.advance(&visible[..complete],&self.masks.delimiters[..complete],&self.masks.multiline_literals,Some(original),source,tokens,self.source_base,final_input)?;
  let header_start=if !final_input&&complete<visible.len(){match self.structural.partial_header_start(visible,self.source_base){Some(start)=>self.inline.live_header_start(start)?,None=>None}}else{None};
  let mut lines=self.inline.advance(&source[self.source_base..],&physical,&self.masks.delimiters,Some(original),source,tokens,self.source_base);drop(physical);for line in &mut lines{line.header_start+=self.source_base;line.header_end+=self.source_base;line.end+=self.source_base;}
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
  let retained=lines.capacity().checked_mul(mem::size_of::<Line>()).ok_or(io::ErrorKind::OutOfMemory)?;
  let dead=row_work.bytes().checked_sub(retained).ok_or(io::ErrorKind::InvalidData)?;
  if dead!=0{self.a.shrink(&mut row_work,dead).map_err(|e|actual_error(self.a,e))?;}
  Ok(NativeLayoutBatch{lines,header_start,_credit:row_work})
 }
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::atomic::{Ordering};
 fn state<'a,'budget>(a:&'a crate::SettingAdmission<'budget>)->OriginalParseState<'a,'static,'budget>{OriginalParseState{storage:original_storage::Storage::new(a).unwrap(),fatal:Default::default(),unavailable:Default::default(),operational:Default::default(),observer:None,observer_stop:Default::default(),first_outer_block:Default::default()}}
 #[test]fn actual_demand_layout_batch_keeps_its_same_resource_root_after_cursor_drop(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));let source="/datum/a\n    var/value=1\n";let tokens=lex_spans(source).tokens;let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();let batch=cursor.advance(source,&tokens,&original,true).unwrap();assert_eq!(batch.len(),2);let owned=counter.load(Ordering::Acquire);assert!(owned>source.len()*2);drop(cursor);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (original.storage.bytes()+batch._credit.bytes()));assert!(counter.load(Ordering::Acquire)<owned);assert_eq!(batch[1].header_start,source.find("var/value").unwrap());drop(batch);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (original.storage.bytes()));drop(original);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_demand_layout_quota_and_operational_fault_refuse_before_mask_growth_and_keep_io_identity(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,5000,&||Ok(()));let source="/datum/a\n";let tokens=lex_spans(source).tokens;let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();let error=cursor.advance(source,&tokens,&original,true).err().unwrap();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);assert!(cursor.masks.visible.is_empty());drop(cursor);drop(original);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let fault=||Err(io::Error::from_raw_os_error(1450));let b=crate::SettingAdmission::new(&counter,1<<20,&fault);let error=NativeDemandLayoutCursor::new(&b).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_demand_layout_resumes_same_mask_group_inline_state_with_funded_batches(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));let source="/datum/a\n    var/list/value=list(\n        1,\n        2)\n/proc/p() return 3\n";let tokens=lex_spans(source).tokens;let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();let mut batches=Vec::new();let mut end=0;
  for raw in source.split_inclusive('\n'){end+=raw.len();let n=tokens.partition_point(|t|t.span.end<=end);batches.push(cursor.advance(&source[..end],&tokens[..n],&original,end==source.len()).unwrap());}
  let old=original_declaration_lines(source,Span::new(0,source.len()),&tokens);let rows:Vec<_>=batches.iter().flat_map(|batch|batch.iter()).collect();assert_eq!(rows.len(),old.len());for(a,b)in rows.into_iter().zip(old){assert_eq!((a.indent,a.header_start,a.header_end,a.same_line_body),(b.indent,b.header_start,b.header_end,b.same_line_body));}drop(cursor);assert!(counter.load(Ordering::Acquire)>crate::SettingChargeCounter::root_allocation_bytes());drop(batches);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (original.storage.bytes()));drop(original);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_sparse_large_native_demand_layout_pays_real_two_masks_and_growth_peak_without_source_multiplier(){
  let mut source=String::from("/*");source.push_str(&"x".repeat(1_550_000));source.push_str("*/\n");let tokens=lex_spans(&source).tokens;
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,6<<20,&||Ok(()));let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();let batch=cursor.advance(&source,&tokens,&original,true).unwrap();assert!(batch.is_empty());assert!(counter.load(Ordering::Acquire)>=crate::SettingChargeCounter::root_allocation_bytes() + (source.len()*2));assert!(counter.load(Ordering::Acquire)<6<<20);drop(cursor);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (original.storage.bytes()+batch._credit.bytes()));drop(batch);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (original.storage.bytes()));drop(original);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
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

}
