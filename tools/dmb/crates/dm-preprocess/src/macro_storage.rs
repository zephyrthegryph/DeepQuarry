//! Allocation-only ownership for the SAME macro kernel. No source/model grant.
//! All payloads precede their lease in field order: physical storage is freed
//! before the matching credit on normal return, early failure, and unwinding.
use dm_syntax::{SettingAdmission, SettingRootLease};
use std::io;
use super::MacroBytePoint;

fn actual(a:&SettingAdmission<'_>,status:io::Error)->io::Error{
    a.take_operational_error().unwrap_or(status)
}
fn failure(a:&SettingAdmission<'_>,kind:io::ErrorKind,message:&'static str)->io::Error{
    a.record_operational_error(io::Error::new(kind,message));
    a.take_operational_error().unwrap_or_else(||kind.into())
}

/// One ordinary Global Vec allocation with its exact admitted Layout. Using
/// alloc directly avoids an infallible reserve/abort and unspecified spare
/// capacity growth. This is not an allocator/cache: ownership immediately moves
/// into the ordinary Vec, whose standard destructor frees the same Layout.
pub(crate) fn empty_exact<T>(capacity:usize,a:&SettingAdmission<'_>)->io::Result<Vec<T>>{
    if capacity==0||std::mem::size_of::<T>()==0{return Ok(Vec::new())}
    let layout=std::alloc::Layout::array::<T>(capacity).map_err(|_|failure(a,io::ErrorKind::OutOfMemory,"macro storage layout overflow"))?;
    // SAFETY: nonzero valid layout. A null Global allocation is returned as the
    // first typed operational failure; no allocation is dereferenced on error.
    let raw=unsafe{std::alloc::alloc(layout)};
    let Some(raw)=std::ptr::NonNull::new(raw.cast::<T>()) else{return Err(failure(a,io::ErrorKind::OutOfMemory,"macro storage allocation denied"))};
    // SAFETY: the pointer came from Global with EXACT Layout::array<T>(capacity),
    // alignment is T's, length zero means no uninitialized T can be read/dropped,
    // and Vec now uniquely owns/deallocates this allocation. No custom allocator.
    Ok(unsafe{Vec::from_raw_parts(raw.as_ptr(),0,capacity)})
}

pub(crate) struct MacroRows<T>{ rows:Vec<T>,root:SettingRootLease }
impl<T> MacroRows<T>{
    pub(crate) fn new(a: &SettingAdmission<'_>) -> io::Result<Self> {
        Self::with_capacity(0, a)
    }

    pub(crate) fn with_capacity(capacity: usize, a: &SettingAdmission<'_>) -> io::Result<Self> {
        let bytes = capacity.checked_mul(std::mem::size_of::<T>())
            .ok_or_else(|| failure(a, io::ErrorKind::OutOfMemory, "macro storage byte count overflow"))?;
        let root = a.reserve(bytes).map_err(|error| actual(a, error))?;
        let rows = empty_exact(capacity, a)?;
        Ok(Self { rows, root })
    }
    pub(crate) fn as_slice(&self)->&[T]{&self.rows}
    pub(crate) fn as_mut_slice(&mut self)->&mut[T]{&mut self.rows}
    pub(crate) fn len(&self)->usize{self.rows.len()}
    pub(crate) fn capacity(&self)->usize{self.rows.capacity()}
    pub(crate) fn visit_allocation(&self,mut visit:impl FnMut(usize,usize)){let bytes=self.rows.capacity()*std::mem::size_of::<T>();if bytes!=0{visit(self.rows.as_ptr()as usize,bytes);}}
    pub(crate) fn pop(&mut self)->Option<T>{self.rows.pop()}
    pub(crate) fn truncate(&mut self,len:usize){self.rows.truncate(len)}
    pub(crate) fn last_mut(&mut self)->Option<&mut T>{self.rows.last_mut()}
    #[track_caller]
    pub(crate) fn ensure(&mut self,additional:usize,a:&SettingAdmission<'_>)->io::Result<()>{
        self.ensure_with_initial_capacity(additional, 4, a)
    }

    #[track_caller]
    fn ensure_with_initial_capacity(&mut self, additional: usize, initial: usize, a: &SettingAdmission<'_>) -> io::Result<()> {
        a.checkpoint().map_err(|e|actual(a,e))?;
        if !a.matches_lease_domain(&self.root){return Err(failure(a,io::ErrorKind::InvalidInput,"macro storage resumed under a foreign resource domain"))}
        let needed=self.rows.len().checked_add(additional).ok_or_else(||failure(a,io::ErrorKind::OutOfMemory,"macro storage element count overflow"))?;
        if needed<=self.rows.capacity(){return Ok(())}
        let capacity=self.rows.capacity().checked_mul(2).unwrap_or(needed).max(needed).max(initial);
        let bytes=capacity.checked_mul(std::mem::size_of::<T>()).ok_or_else(||failure(a,io::ErrorKind::OutOfMemory,"macro storage byte count overflow"))?;
        // Both old and new buffers are admitted for their REAL overlap. The
        // new allocation stays local until no operation below can fail.
        let root=a.reserve(bytes).map_err(|e|actual(a,e))?;
        let mut rows=empty_exact(capacity,a)?;
        a.checkpoint().map_err(|e|actual(a,e))?;
        rows.append(&mut self.rows); // capacity already covers every moved T
        let old_rows=std::mem::replace(&mut self.rows,rows);
        let old_root=std::mem::replace(&mut self.root,root);
        drop(old_rows);drop(old_root); // NEVER release before physical deallocation
        Ok(())
    }
    /// Capacity is fully admitted before the infallible slice copy; the copy
    /// cannot grow this ordinary Vec and retains the SAME root until drop.
    #[track_caller]
    pub(crate) fn extend_from_slice(&mut self,values:&[T],a:&SettingAdmission<'_>)->io::Result<()>where T:Copy{self.ensure(values.len(),a)?;self.rows.extend_from_slice(values);Ok(())}
    #[track_caller]
    pub(crate) fn push(&mut self,value:T,a:&SettingAdmission<'_>)->io::Result<()>{self.ensure(1,a)?;self.rows.push(value);Ok(())}
    /// Retained definition arrays are often a single parameter or token.
    /// Fund the first real row alone and keep the same geometric growth.
    #[track_caller]
    pub(crate) fn push_definition_row(&mut self, value: T, a: &SettingAdmission<'_>) -> io::Result<()> {
        self.ensure_with_initial_capacity(1, 1, a)?;
        self.rows.push(value);
        Ok(())
    }

    pub(crate) fn insert(&mut self,index:usize,value:T,a:&SettingAdmission<'_>)->io::Result<()>{
        if index>self.rows.len(){return Err(io::ErrorKind::InvalidInput.into())}
        self.ensure(1,a)?;
        self.rows.insert(index,value);
        Ok(())
    }
    pub(crate) fn is_admitted_by(&self,a:&SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.root)}
    pub(crate) fn into_parts(self)->(Vec<T>,SettingRootLease){(self.rows,self.root)}
}

/// Standard IntoIter keeps its actual Vec allocation until final iterator drop.
/// The payload iterator is always destroyed BEFORE its matching lease.
pub(crate) struct MacroRowsCursor<T>{iter:std::vec::IntoIter<T>,root:SettingRootLease}
impl<T>MacroRowsCursor<T>{pub(crate) fn next(&mut self)->Option<T>{self.iter.next()}pub(crate) fn remaining(&self)->usize{self.iter.len()}}
impl<T>MacroRows<T>{pub(crate) fn into_cursor(self)->MacroRowsCursor<T>{MacroRowsCursor{iter:self.rows.into_iter(),root:self.root}}}

// Raw function arguments and substituted output can exceed a contiguous
// buffer's overlap allowance even when all their live rows fit. Leave small
// macros in an ordinary first buffer and fund further pages independently.
const TOKEN_PAGE_ROWS: usize = 128;
pub(crate) struct MacroTokenRows<T> {
    first: MacroRows<T>,
    later: MacroRows<MacroRows<T>>,
}
impl<T> MacroTokenRows<T> {
    pub(crate) fn new(a: &SettingAdmission<'_>) -> io::Result<Self> {
        Ok(Self { first: MacroRows::new(a)?, later: MacroRows::new(a)? })
    }
    pub(crate) fn push(&mut self, value: T, a: &SettingAdmission<'_>) -> io::Result<()> {
        let last = self.later.last_mut().unwrap_or(&mut self.first);
        if last.len() < TOKEN_PAGE_ROWS {
            return last.push(value, a);
        }
        self.later.ensure(1, a)?;
        let mut page = MacroRows::new(a)?;
        page.ensure_with_initial_capacity(1, TOKEN_PAGE_ROWS, a)?;
        page.push(value, a)?;
        self.later.push(page, a)
    }
    pub(crate) fn pop(&mut self) -> Option<T> {
        if let Some(page) = self.later.last_mut() {
            let value = page.pop();
            if page.len() == 0 {
                drop(self.later.pop());
            }
            value
        } else {
            self.first.pop()
        }
    }
    pub(crate) fn iter(&self) -> impl Iterator<Item = &T> {
        self.first.as_slice().iter().chain(
            self.later.as_slice().iter().flat_map(|page| page.as_slice()),
        )
    }
    #[cfg(debug_assertions)]
    pub(crate) fn trace_allocation_bytes(&self) -> usize {
        let mut bytes = 0usize;
        self.first.visit_allocation(|_, size| bytes += size);
        self.later.visit_allocation(|_, size| bytes += size);
        for page in self.later.as_slice() {
            page.visit_allocation(|_, size| bytes += size);
        }
        bytes
    }

    /// Packed pages keep their actual ordinal. Only the tail may be short.
    pub(crate) fn len(&self) -> usize {
        self.later.as_slice().last().map_or(self.first.len(), |last|
            self.first.len() + (self.later.len() - 1) * TOKEN_PAGE_ROWS + last.len())
    }

    pub(crate) fn last(&self) -> Option<&T> {
        self.later.as_slice().last().unwrap_or(&self.first).as_slice().last()
    }

    pub(crate) fn get(&self, index: usize) -> Option<&T> {
        if index < TOKEN_PAGE_ROWS { return self.first.as_slice().get(index); }
        let index = index - TOKEN_PAGE_ROWS;
        self.later.as_slice().get(index / TOKEN_PAGE_ROWS)?.as_slice().get(index % TOKEN_PAGE_ROWS)
    }

    pub(crate) fn get_mut(&mut self, index: usize) -> Option<&mut T> {
        if index < TOKEN_PAGE_ROWS { return self.first.as_mut_slice().get_mut(index); }
        let index = index - TOKEN_PAGE_ROWS;
        self.later.as_mut_slice().get_mut(index / TOKEN_PAGE_ROWS)?.as_mut_slice().get_mut(index % TOKEN_PAGE_ROWS)
    }

    pub(crate) fn into_cursor(self) -> MacroTokenCursor<T> {
        MacroTokenCursor {
            current: Some(self.first.into_cursor()),
            later: Some(self.later.into_cursor()),
        }
    }
}

/// Consuming output/repacked-argument cursor. Drop each physical buffer and
/// its matching credit as soon as its last row moves out, not when the entire
/// macro expansion ends. Object definitions can keep their existing one Vec.
pub(crate) struct MacroTokenCursor<T> {
    current: Option<MacroRowsCursor<T>>,
    later: Option<MacroRowsCursor<MacroRows<T>>>,
}
impl<T> From<MacroRowsCursor<T>> for MacroTokenCursor<T> {
    fn from(current: MacroRowsCursor<T>) -> Self {
        Self { current: Some(current), later: None }
    }
}
impl<T> MacroTokenCursor<T> {
    pub(crate) fn next(&mut self) -> Option<T> {
        loop {
            if let Some(current) = &mut self.current {
                let value = current.next();
                if current.remaining() == 0 {
                    self.current = None;
                }
                if value.is_some() {
                    return value;
                }
            }
            let later = self.later.as_mut()?;
            let page = later.next();
            if later.remaining() == 0 {
                self.later = None;
            }
            self.current = Some(page?.into_cursor());
        }
    }
}

pub(crate) struct MacroText{ bytes:MacroRows<u8> }
impl MacroText{
    pub(crate) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{bytes:MacroRows::new(a)?})}
    pub(crate) fn as_str(&self)->&str{
        // SAFETY: the ONLY insertion operations below append valid UTF-8 str or
        // chars; truncation validates a scalar boundary before changing length.
        unsafe{std::str::from_utf8_unchecked(self.bytes.as_slice())}
    }
    pub(crate) fn len(&self)->usize{self.bytes.len()}
    pub(crate) fn is_admitted_by(&self,a:&SettingAdmission<'_>)->bool{self.bytes.is_admitted_by(a)}
    pub(crate) fn visit_allocation(&self,visit:impl FnMut(usize,usize)){self.bytes.visit_allocation(visit)}
    #[track_caller]
    pub(crate) fn push_str(&mut self,text:&str,a:&SettingAdmission<'_>)->io::Result<()>{self.bytes.ensure(text.len(),a)?;self.bytes.rows.extend_from_slice(text.as_bytes());Ok(())}
    pub(crate) fn push(&mut self,ch:char,a:&SettingAdmission<'_>)->io::Result<()>{let mut b=[0;4];self.push_str(ch.encode_utf8(&mut b),a)}
    pub(crate) fn truncate(&mut self,len:usize)->io::Result<()>{if !self.as_str().is_char_boundary(len){return Err(io::ErrorKind::InvalidInput.into())}self.bytes.truncate(len);Ok(())}
    pub(crate) fn pop(&mut self)->Option<char>{let ch=self.as_str().chars().next_back()?;let len=self.len()-ch.len_utf8();self.bytes.truncate(len);Some(ch)}
    pub(crate) fn into_parts(self)->(String,SettingRootLease){let(bytes,root)=self.bytes.into_parts();
        // SAFETY: same invariant as as_str; this adopts, NEVER clones, the Vec.
        (unsafe{String::from_utf8_unchecked(bytes)},root)
    }
}

/// Final output owner, not source/provenance authority. Moving it into the ONE
/// region arena keeps the SAME lease alive through append/copy/adoption.
/// Text and points are both dropped before the one merged resource root.
pub(crate) struct FundedMacroOutput{ text:String,points:Option<Vec<MacroBytePoint>>,root:SettingRootLease }
impl FundedMacroOutput{
    pub(crate) fn from_buffers(text:MacroText,points:Option<MacroRows<MacroBytePoint>>,a:&SettingAdmission<'_>)->io::Result<Self>{
        let(text,mut root)=text.into_parts();
        let points=if let Some(points)=points{let(points,mut credit)=points.into_parts();if let Err(error)=a.absorb(&mut root,&mut credit){drop(points);drop(credit);drop(text);drop(root);return Err(error)}Some(points)}else{None};
        Ok(Self{text,points,root})
    }
    pub(crate) fn text(&self)->&str{&self.text}
    pub(crate) fn points(&self)->Option<&[MacroBytePoint]>{self.points.as_deref()}
    pub(crate) fn into_parts(self)->(String,Option<Vec<MacroBytePoint>>,SettingRootLease){(self.text,self.points,self.root)}
}

#[cfg(test)]mod tests{
    use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
    #[test]fn real_text_points_move_keeps_exact_allocations_funded_until_final_payload_drop(){
        let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
        let mut text=MacroText::new(&a).unwrap();text.push_str("α漢\r\n",&a).unwrap();let mut points=MacroRows::new(&a).unwrap();points.push(MacroBytePoint{output:dm_syntax::Span::new(0,text.len()),source_start:7,invocation:true},&a).unwrap();
        let expected=text.bytes.capacity()+points.capacity()*std::mem::size_of::<MacroBytePoint>();assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes() + (expected));
        let output=FundedMacroOutput::from_buffers(text,Some(points),&a).unwrap();assert_eq!(output.text(),"α漢\r\n");drop(a);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes() + (expected));
        let(text,points,root)=output.into_parts();assert_eq!(root.bytes(),text.capacity()+points.as_ref().unwrap().capacity()*std::mem::size_of::<MacroBytePoint>());drop(text);drop(points);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes() + (expected),"credit cannot disappear before its actual final owner");drop(root);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }
    #[test]
    fn paged_macro_rows_cross_boundary_without_a_second_full_buffer() {
        use std::mem::size_of;
        let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let directory = 4 * size_of::<MacroRows<u64>>();
        let page = TOKEN_PAGE_ROWS * size_of::<u64>();
        let full = SettingAdmission::new(&used, dm_syntax::SettingChargeCounter::root_allocation_bytes() + (3 * page), &|| Ok(()));
        let mut rows = MacroTokenRows::new(&full).unwrap();
        for index in 0..TOKEN_PAGE_ROWS {
            rows.push(index as u64, &full).unwrap();
        }
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes() + (page));

        // The directory can be retained but no unfunded data page may publish.
        let tight = SettingAdmission::new(&used, dm_syntax::SettingChargeCounter::root_allocation_bytes() + (2 * page + directory - 1), &|| Ok(()));
        assert_eq!(rows.push(TOKEN_PAGE_ROWS as u64, &tight).unwrap_err().kind(), io::ErrorKind::OutOfMemory);
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes() + (page + directory));
        assert!(rows.iter().copied().eq(0..TOKEN_PAGE_ROWS as u64));

        let exact = SettingAdmission::new(&used, dm_syntax::SettingChargeCounter::root_allocation_bytes() + (2 * page + directory), &|| Ok(()));
        rows.push(TOKEN_PAGE_ROWS as u64, &exact).unwrap();
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes() + (2 * page + directory));
        assert!(rows.iter().copied().eq(0..=TOKEN_PAGE_ROWS as u64));
        drop(rows);
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }
    #[test]fn denied_growth_keeps_existing_data_and_credit_and_same_root_recovers_after_drop(){
        let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,dm_syntax::SettingChargeCounter::root_allocation_bytes() + (12),&||Ok(()));let mut text=MacroText::new(&a).unwrap();text.push_str("abcd",&a).unwrap();let before=used.load(Ordering::Acquire);let err=text.push_str("012345678901",&a).unwrap_err();assert_eq!(err.kind(),io::ErrorKind::OutOfMemory);assert_eq!(text.as_str(),"abcd");assert_eq!(used.load(Ordering::Acquire),before);drop(text);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());let retry=SettingAdmission::new(&used,dm_syntax::SettingChargeCounter::root_allocation_bytes() + (12),&||Ok(()));let mut text=MacroText::new(&retry).unwrap();text.push_str("again",&retry).unwrap();drop(text);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }
    #[test]fn first_actual_1450_during_overlap_drops_new_credit_without_mutating_existing_payload(){
        use std::cell::Cell;let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let calls=Cell::new(0);let deny=Cell::new(usize::MAX);let checkpoint=||{let n=calls.get()+1;calls.set(n);if n==deny.get(){Err(io::Error::from_raw_os_error(1450))}else{Ok(())}};let a=SettingAdmission::new(&used,4096,&checkpoint);let mut text=MacroText::new(&a).unwrap();text.push_str("abcd",&a).unwrap();let before=used.load(Ordering::Acquire);deny.set(calls.get()+3);let error=text.push_str("e",&a).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(text.as_str(),"abcd");assert_eq!(used.load(Ordering::Acquire),before);drop(text);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }
    #[test]fn foreign_operation_cannot_reuse_or_steal_actual_macro_allocation_credit(){let x=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let y=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&x,4096,&||Ok(()));let b=SettingAdmission::new(&y,4096,&||Ok(()));let mut text=MacroText::new(&a).unwrap();text.push_str("held",&a).unwrap();assert_eq!(text.push_str("!",&b).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(text.as_str(),"held");assert_eq!(y.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());drop(text);assert_eq!(x.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
    #[test]fn actual_element_drop_and_panic_unwind_keep_credit_until_payload_destructors_finish(){
        use std::cell::Cell;use std::panic::{catch_unwind,AssertUnwindSafe};
        struct Probe{used:Arc<dm_syntax::SettingChargeCounter>,expected:Arc<AtomicUsize>,seen:Arc<AtomicUsize>}
        impl Drop for Probe{fn drop(&mut self){assert!(self.used.load(Ordering::Acquire)>=self.expected.load(Ordering::Acquire),"actual element destructor lost its allocation credit");self.seen.fetch_add(1,Ordering::AcqRel);}}
        let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let expected=Arc::new(AtomicUsize::new(0));let seen=Arc::new(AtomicUsize::new(0));let entered=Cell::new(false);
        let result=catch_unwind(AssertUnwindSafe(||{let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut rows=MacroRows::new(&a).unwrap();for _ in 0..3{rows.push(Probe{used:used.clone(),expected:expected.clone(),seen:seen.clone()},&a).unwrap();}expected.store(rows.capacity()*std::mem::size_of::<Probe>(),Ordering::Release);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes() + (expected.load(Ordering::Acquire)));entered.set(true);panic!("deliberate actual macro-owner unwind");}));
        assert!(result.is_err());assert!(entered.get());assert_eq!(seen.load(Ordering::Acquire),3);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes(),"all credit released only after complete real unwind");
    }
    #[test]fn actual_layout_overflow_precedes_global_allocation_and_same_domain_retry_recovers(){
        let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,4096,&||Ok(()));
        let error=empty_exact::<u64>(usize::MAX,&a).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);assert!(error.to_string().contains("layout overflow"));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
        let retry=SettingAdmission::new(&used,4096,&||Ok(()));let mut rows=MacroRows::new(&retry).unwrap();rows.push(7u64,&retry).unwrap();assert_eq!(rows.as_slice(),[7]);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes() + (rows.capacity()*std::mem::size_of::<u64>()));drop(rows);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }

}

impl AsRef<str> for MacroText{fn as_ref(&self)->&str{self.as_str()}}

#[cfg(test)]mod cursor_owner_tests{use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};#[test]fn drained_and_partial_standard_iterator_retain_real_allocation_credit_until_iterator_drop(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,4096,&||Ok(()));let mut rows=MacroRows::new(&a).unwrap();for n in 0..3{rows.push(n,&a).unwrap();}let held=used.load(Ordering::Acquire);let mut cursor=rows.into_cursor();assert_eq!(cursor.next(),Some(0));assert_eq!(cursor.remaining(),2);assert_eq!(used.load(Ordering::Acquire),held);assert_eq!(cursor.next(),Some(1));assert_eq!(cursor.next(),Some(2));assert_eq!(cursor.next(),None);assert_eq!(used.load(Ordering::Acquire),held,"empty IntoIter still owns actual capacity");drop(cursor);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}}

// Shared typed formatter sink used by token Display and source-number notices.
pub(crate) struct Writer<'a,'op>{out:&'a mut MacroText,a:&'a SettingAdmission<'op>,first:Option<io::Error>}
impl std::fmt::Write for Writer<'_,'_>{fn write_str(&mut self,text:&str)->std::fmt::Result{if self.first.is_some(){return Err(std::fmt::Error)}if let Err(actual)=self.out.push_str(text,self.a){self.first=Some(actual);return Err(std::fmt::Error)}Ok(())}}
pub(crate) fn formatted(out:&mut MacroText,a:&SettingAdmission<'_>,write:impl FnOnce(&mut Writer<'_,'_>)->std::fmt::Result)->io::Result<()>{let mut writer=Writer{out,a,first:None};let result=write(&mut writer);match writer.first{Some(first)=>Err(first),None=>result.map_err(|_|io::Error::new(io::ErrorKind::InvalidData,"original macro token formatter failed without its actual output error"))}}
