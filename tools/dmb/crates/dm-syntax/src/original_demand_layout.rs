//! Private demand-layout DATA over the SAME native kernels. Neither this
//! retained allocation owner nor a line batch certifies source EOF/model state.
use super::*;
use std::{alloc::{alloc, Layout}, io, mem, ptr::NonNull, sync::Arc};
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

fn fund_buffer<T>(
    rows: &mut Vec<T>, desired: usize, credit: &mut crate::SettingRootLease,
    a: &crate::SettingAdmission<'_>,
) -> io::Result<()> {
    if rows.capacity() >= desired { return Ok(()); }
    let layout = Layout::array::<T>(desired).map_err(|_| io::ErrorKind::OutOfMemory)?;
    let prior = rows.capacity().checked_mul(mem::size_of::<T>()).ok_or(io::ErrorKind::OutOfMemory)?;
    a.grow(credit, layout.size()).map_err(|e| actual_error(a, e))?;
    // SAFETY: nonempty Global layout for the two admitted non-ZST buffer
    // types, reserved before allocation. All existing rows move once.
    let pointer = NonNull::new(unsafe { alloc(layout) }.cast::<T>()).ok_or(io::ErrorKind::OutOfMemory)?;
    let mut next = unsafe { Vec::from_raw_parts(pointer.as_ptr(), 0, desired) };
    next.append(rows);
    drop(mem::replace(rows, next));
    a.shrink(credit, prior).map_err(|e| actual_error(a, e))
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
  fund_buffer(&mut self.masks.visible,visible_bytes,&mut self.mask_credit,self.a)?;
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
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 fn state<'a,'budget>(a:&'a crate::SettingAdmission<'budget>)->OriginalParseState<'a,'static,'budget>{OriginalParseState{storage:original_storage::Storage::new(a).unwrap(),fatal:Default::default(),unavailable:Default::default(),operational:Default::default(),observer:None,observer_stop:Default::default(),first_outer_block:Default::default()}}
 #[test]fn actual_demand_layout_batch_keeps_its_same_resource_root_after_cursor_drop(){
  let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));let source="/datum/a\n    var/value=1\n";let tokens=lex_spans(source).tokens;let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();let batch=cursor.advance(source,&tokens,&original,true).unwrap();assert_eq!(batch.len(),2);let owned=counter.load(Ordering::Acquire);assert!(owned>source.len()*2);drop(cursor);assert_eq!(counter.load(Ordering::Acquire),original.storage.bytes()+batch._credit.bytes());assert!(counter.load(Ordering::Acquire)<owned);assert_eq!(batch[1].header_start,source.find("var/value").unwrap());drop(batch);assert_eq!(counter.load(Ordering::Acquire),original.storage.bytes());drop(original);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_demand_layout_quota_and_operational_fault_refuse_before_mask_growth_and_keep_io_identity(){
  let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,5000,&||Ok(()));let source="/datum/a\n";let tokens=lex_spans(source).tokens;let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();let error=cursor.advance(source,&tokens,&original,true).err().unwrap();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);assert!(cursor.masks.visible.is_empty());drop(cursor);drop(original);assert_eq!(counter.load(Ordering::Acquire),0);
  let fault=||Err(io::Error::from_raw_os_error(1450));let b=crate::SettingAdmission::new(&counter,1<<20,&fault);let error=NativeDemandLayoutCursor::new(&b).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_demand_layout_resumes_same_mask_group_inline_state_with_funded_batches(){
  let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));let source="/datum/a\n    var/list/value=list(\n        1,\n        2)\n/proc/p() return 3\n";let tokens=lex_spans(source).tokens;let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();let mut batches=Vec::new();let mut end=0;
  for raw in source.split_inclusive('\n'){end+=raw.len();let n=tokens.partition_point(|t|t.span.end<=end);batches.push(cursor.advance(&source[..end],&tokens[..n],&original,end==source.len()).unwrap());}
  let old=original_declaration_lines(source,Span::new(0,source.len()),&tokens);let rows:Vec<_>=batches.iter().flat_map(|batch|batch.iter()).collect();assert_eq!(rows.len(),old.len());for(a,b)in rows.into_iter().zip(old){assert_eq!((a.indent,a.header_start,a.header_end,a.same_line_body),(b.indent,b.header_start,b.header_end,b.same_line_body));}drop(cursor);assert!(counter.load(Ordering::Acquire)>0);drop(batches);assert_eq!(counter.load(Ordering::Acquire),original.storage.bytes());drop(original);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_sparse_large_native_demand_layout_pays_real_two_masks_and_growth_peak_without_source_multiplier(){
  let mut source=String::from("/*");source.push_str(&"x".repeat(1_550_000));source.push_str("*/\n");let tokens=lex_spans(&source).tokens;
  let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,6<<20,&||Ok(()));let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();let batch=cursor.advance(&source,&tokens,&original,true).unwrap();assert!(batch.is_empty());assert!(counter.load(Ordering::Acquire)>=source.len()*2);assert!(counter.load(Ordering::Acquire)<6<<20);drop(cursor);assert_eq!(counter.load(Ordering::Acquire),original.storage.bytes()+batch._credit.bytes());drop(batch);assert_eq!(counter.load(Ordering::Acquire),original.storage.bytes());drop(original);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]
 fn cloned_formal_identities_do_not_pin_two_independently_funded_layout_batches() {
    let used=Arc::new(AtomicUsize::new(0));
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
    assert_eq!(used.load(Ordering::Acquire),0);

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
    assert_eq!(used.load(Ordering::Acquire),base+fixed+first._credit.bytes()+second._credit.bytes());
    assert_eq!((first[0].header_start,second[0].header_start),(0,first_end));
    let second_bytes=second._credit.bytes();
    drop(first);
    assert_eq!(used.load(Ordering::Acquire),base+fixed+second_bytes);
    drop((final_identity,identity,another));
    assert_eq!(used.load(Ordering::Acquire),base+second_bytes);
    drop((second,original));
    assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn actual_long_source_keeps_only_live_header_mask_window_and_dropped_batch_rows_do_not_accumulate_debt(){
  let source="/datum/a\n".repeat(2048);let tokens=lex_spans(&source).tokens;let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,64<<10,&||Ok(()));let original=state(&a);let mut cursor=NativeDemandLayoutCursor::new(&a).unwrap();let mut end=0;
  for raw in source.split_inclusive('\n'){end+=raw.len();let n=tokens.partition_point(|token|token.span.end<=end);let batch=cursor.advance(&source[..end],&tokens[..n],&original,end==source.len()).unwrap();assert_eq!(batch.len(),1);assert_eq!(batch[0].header_start,end-raw.len());assert!(cursor.masks.visible.is_empty());assert!(cursor.masks.visible.capacity()<128);assert!(counter.load(Ordering::Acquire)<64<<10);drop(batch);}
  assert_eq!(cursor.source_base,source.len());drop(cursor);drop(original);assert_eq!(counter.load(Ordering::Acquire),0);
 }
}
