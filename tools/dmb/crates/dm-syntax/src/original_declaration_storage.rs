//! Funding for actual allocations in the SAME original primary parser.
//! No parser/model/cache is stored here; unique storage leases live with the
//! native primary result and scoped temporary layout/compaction allocations.
use super::*;
use std::{cell::RefCell,io};
pub(super) struct Storage<'a,'b>{pub(super) a:&'a crate::SettingAdmission<'b>,owned:RefCell<crate::SettingRootLease>,failure:RefCell<Option<io::Error>>}
impl<'a,'b> Storage<'a,'b>{
 pub(super) fn new(a:&'a crate::SettingAdmission<'b>)->io::Result<Self>{let owned=match a.reserve(4096){Ok(lease)=>lease,Err(actual)=>return Err(a.take_operational_error().unwrap_or(actual))};Ok(Self{a,owned:RefCell::new(owned),failure:RefCell::new(None)})}
 pub(super) fn poll(&self)->bool{if self.failure.borrow().is_some(){return false}match self.a.checkpoint(){Ok(())=>true,Err(actual)=>self.fail(actual)}}
 pub(super) fn fail(&self,actual:io::Error)->bool{if self.failure.borrow().is_none(){*self.failure.borrow_mut()=Some(self.a.take_operational_error().unwrap_or(actual));}false}
 pub(super) fn take_failure(&self)->Option<io::Error>{self.failure.borrow_mut().take()}
 pub(super) fn bytes(&self)->usize{self.owned.borrow().bytes()}
 #[track_caller]
 fn grow(&self,bytes:usize)->bool{if !self.poll(){return false}match self.a.grow(&mut self.owned.borrow_mut(),bytes){Ok(())=>true,Err(actual)=>self.fail(actual)}}
 fn release(&self,bytes:usize)->bool{match self.a.shrink(&mut self.owned.borrow_mut(),bytes){Ok(())=>true,Err(actual)=>self.fail(actual)}}
 fn overflow(&self)->bool{self.fail(io::ErrorKind::OutOfMemory.into())}
 #[track_caller]
 fn exact_vector<T>(&self,capacity:usize)->Option<Vec<T>>{
  let Ok(layout)=std::alloc::Layout::array::<T>(capacity)else{self.overflow();return None};
  if layout.size()==0{self.overflow();return None}
  if !self.grow(layout.size()){return None}
  match funded_vector(capacity, layout) {
   Some(rows)=>Some(rows),
   None=>{self.overflow();None}
  }
 }

 /// Child has completed all body retention/diagnostic decisions. This is
 /// an optional resource settlement before its actual parent takes it.
 pub(super) fn settle_child_items(&self, mut rows: Vec<Item>) -> Option<Vec<Item>> {
  let len=rows.len();
  let capacity=rows.capacity();
  if len==capacity { return Some(rows); }
  let old_bytes=capacity.checked_mul(std::mem::size_of::<Item>()).expect("actual allocated item capacity");
  if len==0 {
   drop(rows);
   return self.release(old_bytes).then(Vec::new);
  }
  if !self.poll() { return None; }
  let Ok(layout)=std::alloc::Layout::array::<Item>(len) else {self.overflow();return None};
  // New and old buffers overlap. If the budget (or allocator) cannot
  // supply an exact replacement, the already-funded old Vec stays valid.
  let mut credit=match self.a.try_reserve_optimization(layout.size()) {
   Ok(Some(credit))=>credit,
   Ok(None)=>return Some(rows),
   Err(actual)=>{self.fail(actual);return None}
  };
  let Some(mut exact)=funded_vector(len,layout) else {return Some(rows)};
  // Settle the grant before moving any Item. If the actual checkpoint or
  // admission fails, both real buffers drop with both credits still live.
  let transferred=self.a.absorb(&mut self.owned.borrow_mut(),&mut credit);
  if let Err(actual)=transferred {self.fail(actual);return None}
  exact.append(&mut rows);
  drop(rows);
  self.release(old_bytes).then_some(exact)
 }

 #[track_caller]
 pub(super) fn push<T>(&self,rows:&mut Vec<T>,value:T)->bool{
  if !self.poll(){return false}
  if rows.len()==rows.capacity(){
   let Some(capacity)=rows.capacity().max(2).checked_mul(2)else{return self.overflow()};
   let Some(old_bytes)=rows.capacity().checked_mul(std::mem::size_of::<T>())else{return self.overflow()};
   // Keep the old rows funded through the move into the exact new layout.
   let Some(mut next)=self.exact_vector(capacity)else{return false};
   next.append(rows);
   let old=std::mem::replace(rows,next);
   drop(old);
   if !self.release(old_bytes){return false}
  }
  rows.push(value);true
 }
 /// Move the SAME committed root Items into the existing final contiguous
 /// interface. Only the row buffers overlap; nested headers/children move
 /// once. Credit their old storage only after physical deallocation.
 pub(super) fn finish_root_items(&self,blocks:Vec<Vec<Item>>,active:Vec<Item>)->Option<Vec<Item>>{
  if blocks.is_empty(){return Some(active)}
  let Some(count)=blocks.iter().try_fold(active.len(),|count,block|count.checked_add(block.len()))else{self.overflow();return None};
  let Some(directory_bytes)=blocks.capacity().checked_mul(std::mem::size_of::<Vec<Item>>())else{self.overflow();return None};
  let mut result=self.exact_vector(count)?;
  let mut pending=blocks.into_iter();
  for mut block in pending.by_ref().chain(std::iter::once(active)){
   let Some(bytes)=block.capacity().checked_mul(std::mem::size_of::<Item>())else{self.overflow();return None};
   result.append(&mut block);
   drop(block);
   if !self.release(bytes){return None}
  }
  drop(pending);
  if !self.release(directory_bytes){return None}
  Some(result)
 }
 #[track_caller]
 pub(super) fn text(&self,text:&str)->Option<String>{
  if text.is_empty(){return self.poll().then(String::new)}
  let mut bytes=self.exact_vector::<u8>(text.len())?;
  bytes.extend_from_slice(text.as_bytes());
  // The exact layout is funded before allocation. No allocator-sized
  // allowance survives the copy, and the source bytes are already UTF-8.
  self.poll().then(||String::from_utf8(bytes).expect("copied valid UTF-8"))
 }
 pub(super) fn diagnostic_parts(&self,rows:&mut Vec<Diagnostic>,span:Span,kind:DiagnosticKind,message:&str)->bool{let Some(message)=self.text(message)else{return false};self.push(rows,Diagnostic{span,kind,message})}
 /// SAME existing worker stack resource contract, not a grammar nesting limit.
 /// One admitted cleanup frame beyond actual parser/inventory recursion ensures
 /// unwinding can safely drop the unique just-produced child tree as well.
 pub(super) fn frame(&self)->Option<crate::setting_expression::SettingParserFrame<'_,'b>>{
  let frame=match self.a.parser_frame(){Ok(frame)=>frame,Err(actual)=>{self.fail(actual);return None}};
  if let Err(actual)=self.a.admit_drop_depth(1){drop(frame);self.fail(actual);return None}Some(frame)
 }
 pub(super) fn temporary(&self,bytes:usize)->Option<crate::SettingRootLease>{if !self.poll(){return None}match self.a.reserve(bytes){Ok(lease)=>Some(lease),Err(actual)=>{self.fail(actual);None}}}
 pub(super) fn layout(&self,source:&str,tokens:TokenWindow<'_>,line_width:usize)->Option<crate::SettingRootLease>{
  let(mut boundaries,mut multiline)=(8usize,0usize);for token in tokens.iter(){if !self.poll(){return None}if token.kind==TokenKind::Newline||matches!(token.text(source),"{"|"}"|";"|"("){let Some(next)=boundaries.checked_add(2)else{self.overflow();return None};boundaries=next}if token.kind==TokenKind::String&&token.text(source).contains('\n'){multiline+=1;}}
  // Exactly two byte masks plus the simultaneous input/output line vectors,
  // their geometric old/new growth overlap, and actual multiline span roster.
  let bytes=source.len().checked_mul(2).and_then(|n|boundaries.checked_mul(line_width).and_then(|rows|rows.checked_mul(8)).and_then(|rows|n.checked_add(rows))).and_then(|n|multiline.checked_mul(std::mem::size_of::<Span>()).and_then(|rows|rows.checked_mul(4)).and_then(|rows|n.checked_add(rows)));let Some(bytes)=bytes else{self.overflow();return None};
  self.temporary(bytes)
 }
 pub(super) fn compact(&self,count:usize)->Option<crate::SettingRootLease>{let Some(bytes)=count.checked_mul(std::mem::size_of::<Item>()).and_then(|n|n.checked_mul(8))else{self.overflow();return None};self.temporary(bytes)}
 fn item_bytes(&self,items:&Vec<Item>)->Option<usize>{let mut bytes=items.capacity().checked_mul(std::mem::size_of::<Item>())?;if items.is_empty(){return Some(bytes)}let _frame=self.frame()?;for item in items{if !self.poll(){return None}bytes=bytes.checked_add(item.header.capacity())?.checked_add(self.item_bytes(&item.children)?)?;}Some(bytes)}
 fn diagnostic_bytes(&self,rows:&Vec<Diagnostic>)->Option<usize>{let mut bytes=rows.capacity().checked_mul(std::mem::size_of::<Diagnostic>())?;for row in rows{if !self.poll(){return None}bytes=bytes.checked_add(row.message.capacity())?;}Some(bytes)}
 pub(super) fn discard_item(&self,item:Item)->bool{let bytes=self.item_bytes(&item.children).and_then(|n|n.checked_add(item.header.capacity()));drop(item);match bytes{Some(bytes)=>self.release(bytes),None=>self.overflow()}}
 pub(super) fn transfer_compacted_vector(&self,old_capacity:usize,new_capacity:usize)->bool{let Some(release)=old_capacity.checked_sub(new_capacity).and_then(|n|n.checked_mul(std::mem::size_of::<Item>()))else{return self.fail(io::Error::new(io::ErrorKind::InvalidData,"compacted primary vector exceeded funded native input capacity"))};self.release(release)}
 pub(super) fn finish(self,items:&Vec<Item>,token_capacity:usize,diagnostics:&Vec<Diagnostic>)->io::Result<crate::SettingRootLease>{
  if let Some(actual)=self.take_failure(){return Err(actual)}let target=self.item_bytes(items).and_then(|n|token_capacity.checked_mul(std::mem::size_of::<SpanToken>()).and_then(|tokens|n.checked_add(tokens))).and_then(|n|self.diagnostic_bytes(diagnostics).and_then(|diags|n.checked_add(diags))).and_then(|n|n.checked_add(std::mem::size_of::<OriginalDeclarationSkeleton>()));let Some(target)=target else{return Err(self.take_failure().unwrap_or_else(||io::Error::from(io::ErrorKind::OutOfMemory)))};
  let excess=self.bytes().checked_sub(target).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"native primary final storage lacks actual allocation funding"))?;if !self.release(excess){return Err(self.take_failure().unwrap_or_else(||io::Error::from(io::ErrorKind::OutOfMemory)))}Ok(self.owned.into_inner())
 }
}

/// Private allocation helper. Both callers have already admitted this exact,
/// nonzero Layout before invoking Global. The returned empty Vec has the
/// same allocation and its normal destructor uses that identical Layout.
fn funded_vector<T>(capacity:usize,layout:std::alloc::Layout)->Option<Vec<T>>{
 debug_assert_eq!(std::alloc::Layout::array::<T>(capacity).ok(),Some(layout));
 debug_assert_ne!(layout.size(),0);
 let raw=std::ptr::NonNull::new(unsafe{std::alloc::alloc(layout)})?;
 // SAFETY: Global allocated the exact array layout above; length is zero.
 Some(unsafe{Vec::from_raw_parts(raw.as_ptr().cast::<T>(),0,capacity)})
}

#[cfg(test)]
mod exact_vector_funding_tests {
    use super::*;
    use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};

    fn token(at:usize)->SpanToken {
        SpanToken{kind:TokenKind::Ident,span:Span::new(at,at+1)}
    }

    #[test]
    fn primary_text_reserves_only_its_actual_utf8_capacity() {
        let text = "long header with a multibyte spelling: α";
        let used = Arc::new(AtomicUsize::new(0));
        let limit = 4096 + text.len();
        let a = crate::SettingAdmission::new(&used, limit, &|| Ok(()));
        let storage = Storage::new(&a).unwrap();
        let retained = storage.text(text).unwrap();
        assert_eq!(retained, text);
        assert_eq!(retained.capacity(), text.len());
        assert_eq!(used.load(Ordering::Acquire), limit);
        drop(retained);
        drop(storage);
        assert_eq!(used.load(Ordering::Acquire), 0);

        let a = crate::SettingAdmission::new(&used, limit - 1, &|| Ok(()));
        let storage = Storage::new(&a).unwrap();
        assert!(storage.text(text).is_none());
        assert_eq!(storage.take_failure().unwrap().kind(), io::ErrorKind::OutOfMemory);
        drop(storage);
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn settled_child_items_keep_exact_moved_header_under_tight_overlap() {
        let width=std::mem::size_of::<Item>();
        let text="var/value";
        let retained=4096+text.len()+4*width;
        for allow_overlap in [false,true] {
            let used=Arc::new(AtomicUsize::new(0));
            let limit=retained+width-usize::from(!allow_overlap);
            let a=crate::SettingAdmission::new(&used,limit,&||Ok(()));
            let storage=Storage::new(&a).unwrap();
            let header=storage.text(text).unwrap();
            let original=header.as_ptr();
            let span=Span::new(1,1+text.len());
            let mut children=Vec::new();
            assert!(storage.push(&mut children,Item{
                kind:ItemKind::Var,header,span,header_span:span,
                declaration_cursor:None,checker_qualifiers:crate::UNKNOWN_HEADER_QUALIFIERS,
                original_outer_terminator:Some(false),indent:4,children:Vec::new(),
            }));
            let rows=storage.settle_child_items(children).unwrap();
            assert_eq!(rows.len(),1);
            assert_eq!(rows[0].header.as_ptr(),original);
            assert_eq!(rows[0].header,text);
            assert_eq!(rows[0].header_span,span);
            let expected=if allow_overlap{1}else{4};
            assert_eq!(rows.capacity(),expected);
            assert_eq!(used.load(Ordering::Acquire),4096+text.len()+expected*width);
            assert!(storage.take_failure().is_none());
            assert!(!a.is_stopped());
            drop((rows,storage));
            assert_eq!(used.load(Ordering::Acquire),0);
        }
    }

    #[test]
    fn settled_child_items_keeps_first_typed_checkpoint_and_refunds_candidate() {
        let used=Arc::new(AtomicUsize::new(0));
        let calls=std::cell::Cell::new(None::<usize>);
        let poll=||{
            let Some(previous)=calls.get() else {return Ok(())};
            calls.set(Some(previous+1));
            if previous==2 {Err(io::Error::from_raw_os_error(1450))} else {Ok(())}
        };
        let a=crate::SettingAdmission::new(&used,1<<20,&poll);
        let storage=Storage::new(&a).unwrap();
        let header=storage.text("var/value").unwrap();
        let span=Span::new(0,header.len());
        let mut children=Vec::new();
        assert!(storage.push(&mut children,Item{
            kind:ItemKind::Var,header,span,header_span:span,
            declaration_cursor:None,checker_qualifiers:crate::UNKNOWN_HEADER_QUALIFIERS,
            original_outer_terminator:Some(false),indent:4,children:Vec::new(),
        }));
        let held=used.load(Ordering::Acquire);
        calls.set(Some(0));
        assert!(storage.settle_child_items(children).is_none());
        assert_eq!(storage.take_failure().unwrap().raw_os_error(),Some(1450));
        assert_eq!(used.load(Ordering::Acquire),held,"candidate released separately from the failed primary root");
        drop(storage);
        assert_eq!(used.load(Ordering::Acquire),0);
    }

    #[test]
    fn original_primary_vector_grows_at_actual_overlap_and_refuses_one_byte_less() {
        let width=std::mem::size_of::<SpanToken>();
        let overlap=4096+12*width; // Initial four plus replacement eight.
        let used=Arc::new(AtomicUsize::new(0));
        let peak=AtomicUsize::new(0);
        let observe=||{
            peak.fetch_max(used.load(Ordering::Acquire),Ordering::AcqRel);
            Ok(())
        };
        let a=crate::SettingAdmission::new(&used,overlap,&observe);
        let storage=Storage::new(&a).unwrap();
        let mut tokens=Vec::new();
        for at in 0..8 {
            assert!(storage.push(&mut tokens,token(at)));
        }
        assert_eq!(peak.load(Ordering::Acquire),overlap);
        assert_eq!(used.load(Ordering::Acquire),4096+8*width);
        assert_eq!(tokens,(0..8).map(token).collect::<Vec<_>>());
        drop((tokens,storage));
        assert_eq!(used.load(Ordering::Acquire),0);

        let a=crate::SettingAdmission::new(&used,overlap-1,&||Ok(()));
        let storage=Storage::new(&a).unwrap();
        let mut tokens=Vec::new();
        for at in 0..4 {
            assert!(storage.push(&mut tokens,token(at)));
        }
        let first=tokens.as_ptr();
        assert!(!storage.push(&mut tokens,token(4)));
        assert_eq!(storage.take_failure().unwrap().kind(),io::ErrorKind::OutOfMemory);
        assert_eq!(tokens.as_ptr(),first);
        assert_eq!(tokens,(0..4).map(token).collect::<Vec<_>>());
        drop((tokens,storage));
        assert_eq!(used.load(Ordering::Acquire),0);
    }

    #[test]
    fn root_item_settlement_funds_real_overlap_and_refunds_only_dead_buffers() {
        fn item(at:usize)->Item {
            let span=Span::new(at,at+1);
            Item{kind:ItemKind::Type,header:String::new(),span,header_span:span,declaration_cursor:None,checker_qualifiers:crate::UNKNOWN_HEADER_QUALIFIERS,original_outer_terminator:Some(false),indent:0,children:Vec::new()}
        }
        let width=std::mem::size_of::<Item>();
        let directory=4*std::mem::size_of::<Vec<Item>>();
        let overlap=4096+16*width+directory;
        let used=Arc::new(AtomicUsize::new(0));
        let peak=AtomicUsize::new(0);
        let stop=std::cell::Cell::new(false);
        let observe=||{
            let live=used.load(Ordering::Acquire);
            peak.fetch_max(live,Ordering::AcqRel);
            if stop.get()&&live==overlap{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}
        };
        let a=crate::SettingAdmission::new(&used,overlap,&observe);
        for fail in [false,true] {
            let storage=Storage::new(&a).unwrap();
            let(mut blocks,mut first,mut active)=(Vec::new(),Vec::new(),Vec::new());
            for at in 0..4{assert!(storage.push(&mut first,item(at)));}
            for at in 4..8{assert!(storage.push(&mut active,item(at)));}
            assert!(storage.push(&mut blocks,first));
            stop.set(fail);
            let result=storage.finish_root_items(blocks,active);
            if fail {
                assert!(result.is_none());
                assert_eq!(storage.take_failure().unwrap().raw_os_error(),Some(1450));
                assert_eq!(used.load(Ordering::Acquire),overlap,"failed checkpoint did not release credit early");
            }else{
                let result=result.unwrap();
                assert_eq!(result.iter().map(|row|row.span.start).collect::<Vec<_>>(),(0..8).collect::<Vec<_>>());
                assert_eq!(used.load(Ordering::Acquire),4096+8*width);
                assert_eq!(peak.load(Ordering::Acquire),overlap);
                drop(result);
            }
            drop(storage);
            assert_eq!(used.load(Ordering::Acquire),0);
            stop.set(false);
        }
    }

    #[test]
    fn original_primary_vector_refund_checkpoint_preserves_first_typed_error() {
        let width=std::mem::size_of::<SpanToken>();
        let overlap=4096+12*width;
        let used=Arc::new(AtomicUsize::new(0));
        let fail_at_overlap=||if used.load(Ordering::Acquire)==overlap{
            Err(io::Error::from_raw_os_error(1450))
        }else{
            Ok(())
        };
        let a=crate::SettingAdmission::new(&used,overlap,&fail_at_overlap);
        let storage=Storage::new(&a).unwrap();
        let mut tokens=Vec::new();
        for at in 0..4 {
            assert!(storage.push(&mut tokens,token(at)));
        }
        assert!(!storage.push(&mut tokens,token(4)));
        assert_eq!(storage.take_failure().unwrap().raw_os_error(),Some(1450));
        assert_eq!(tokens,(0..4).map(token).collect::<Vec<_>>());
        assert_eq!(used.load(Ordering::Acquire),overlap);
        drop((tokens,storage));
        assert_eq!(used.load(Ordering::Acquire),0);
    }
}
