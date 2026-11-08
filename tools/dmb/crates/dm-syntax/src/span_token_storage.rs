//! Immutable token DATA ownership, no parser/cache/source/completeness grant.
use crate::{SpanToken,SettingAdmission,SettingRootLease};
use std::{io,fmt,sync::Arc};
#[path="loaned_token_pages.rs"] mod loaned_token_pages;
pub use loaned_token_pages::{OriginalTokenPageData, OriginalTokenPageLoan, ORIGINAL_TOKEN_PAGE_ROWS};
pub(crate) use loaned_token_pages::LoanedTokenPages;
#[path="packed_token_blocks.rs"] mod packed_token_blocks;
pub(crate) use packed_token_blocks::PackedTokenBlocks;
enum SharedTokenData {
    Dense(Vec<SpanToken>),
    Packed(PackedTokenBlocks),
    Loaned(LoanedTokenPages),
}
struct SharedPayload{tokens:SharedTokenData,credit:SettingRootLease}

#[derive(Clone, Copy)]
enum TokenBacking<'a> {
    Borrowed(&'a [SpanToken]),
    Owned(&'a Vec<SpanToken>),
    Shared(&'a SharedPayload),
    Packed(&'a PackedTokenBlocks),
    Loaned(&'a LoanedTokenPages),
}

impl<'a> TokenBacking<'a> {
    fn as_dense(self) -> Option<&'a [SpanToken]> {
        match self {
            Self::Borrowed(tokens) => Some(tokens),
            Self::Owned(tokens) => Some(tokens),
            Self::Shared(owner) => match &owner.tokens { SharedTokenData::Dense(tokens) => Some(tokens), SharedTokenData::Packed(_) | SharedTokenData::Loaned(_) => None },
            Self::Packed(_) | Self::Loaned(_) => None,
        }
    }

    fn packed(self) -> Option<&'a PackedTokenBlocks> {
        match self {
            Self::Packed(blocks) => Some(blocks),
            Self::Shared(owner) => match &owner.tokens { SharedTokenData::Packed(blocks) => Some(blocks), SharedTokenData::Dense(_) | SharedTokenData::Loaned(_) => None },
            _ => None,
        }
    }
    fn loaned(self) -> Option<&'a LoanedTokenPages> {
        match self {
            Self::Loaned(pages) => Some(pages),
            Self::Shared(owner) => match &owner.tokens { SharedTokenData::Loaned(pages) => Some(pages), _ => None },
            _ => None,
        }
    }

    fn len(self) -> usize {
        if let Some(pages) = self.loaned() { return pages.len(); }
        match self.packed() {
            Some(blocks) => blocks.len(),
            _ => self.as_dense().expect("dense token backing").len(),
        }
    }

    fn get(self, ordinal: usize) -> Option<SpanToken> {
        if let Some(pages) = self.loaned() { return pages.get(ordinal); }
        match self.packed() {
            Some(blocks) => blocks.get(ordinal),
            _ => self.as_dense()?.get(ordinal).copied(),
        }
    }

    fn same(self, other: Self) -> bool {
        match (self, other) {
            // An unowned empty slice has no allocation identity.
            (Self::Borrowed(left), Self::Borrowed(right)) => !left.is_empty() && std::ptr::eq(left, right),
            (Self::Owned(left), Self::Owned(right)) => std::ptr::eq(left, right),
            (Self::Shared(left), Self::Shared(right)) => std::ptr::eq(left, right),
            (Self::Packed(left), Self::Packed(right)) => std::ptr::eq(left, right),
            (Self::Loaned(left), Self::Loaned(right)) => std::ptr::eq(left, right),
            _ => false,
        }
    }
}

/// Borrowed ordinal interval over one existing token backing. Token spans
/// stay in the original source coordinates. This proves no source identity.
#[derive(Clone, Copy)]
pub struct TokenWindow<'a> {
    backing: TokenBacking<'a>,
    first: usize,
    end: usize,
}

impl<'a> TokenWindow<'a> {
    fn full(backing: TokenBacking<'a>) -> Self {
        Self { backing, first: 0, end: backing.len() }
    }

    pub fn from_slice(tokens: &'a [SpanToken]) -> Self {
        Self::full(TokenBacking::Borrowed(tokens))
    }

    pub(crate) fn from_vec(tokens: &'a Vec<SpanToken>) -> Self {
        Self::full(TokenBacking::Owned(tokens))
    }

    fn from_packed(tokens: &'a PackedTokenBlocks) -> Self {
        Self::full(TokenBacking::Packed(tokens))
    }

    pub(crate) fn from_loaned(tokens: &'a LoanedTokenPages) -> Self {
        Self::full(TokenBacking::Loaned(tokens))
    }

    pub fn len(self) -> usize {
        self.end - self.first
    }

    pub fn is_empty(self) -> bool {
        self.first == self.end
    }

    pub fn range(self, first: usize, end: usize) -> Option<Self> {
        if first > end || end > self.len() {
            return None;
        }
        Some(Self { backing: self.backing, first: self.first + first, end: self.first + end })
    }

    pub fn get(self, ordinal: usize) -> Option<SpanToken> {
        if ordinal < self.len() { self.backing.get(self.first + ordinal) } else { None }
    }

    pub fn last(self) -> Option<SpanToken> {
        self.get(self.len().checked_sub(1)?)
    }

    pub fn iter(self) -> impl ExactSizeIterator<Item = SpanToken> + DoubleEndedIterator + 'a {
        if let Some(pages) = self.backing.loaned() {
            return TokenIter::Loaned { pages, ordinals: self.first..self.end };
        }
        match self.backing.packed() {
            Some(blocks) => TokenIter::Packed { blocks, ordinals: self.first..self.end },
            _ => TokenIter::Dense(self.as_dense_slice().expect("dense backing").iter().copied()),
        }
    }

    pub fn partition_point(self, mut before: impl FnMut(SpanToken) -> bool) -> usize {
        if let Some(dense) = self.as_dense_slice() {
            return dense.partition_point(|token| before(*token));
        }
        let (mut low, mut high) = (0, self.len());
        while low < high {
            let mid = low + (high - low) / 2;
            if before(self.get(mid).expect("issued packed token ordinal")) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        low
    }

    pub fn same_interval(self, other: TokenWindow<'_>) -> bool {
        self.first == other.first && self.end == other.end && self.backing.same(other.backing)
    }

    pub fn as_dense_slice(self) -> Option<&'a [SpanToken]> {
        Some(&self.backing.as_dense()?[self.first..self.end])
    }

    /// Borrow dense storage directly, or materialize this exact local window
    /// under the SAME admission for one callback. No decoded buffer escapes.
    pub fn with_dense_using<T>(
        self, a: &SettingAdmission<'_>,
        use_tokens: impl FnOnce(&[SpanToken]) -> io::Result<T>,
    ) -> io::Result<T> {
        if let Some(dense) = self.as_dense_slice() {
            return use_tokens(dense);
        }
        let admitted = self.backing.packed().map(|blocks| blocks.admitted_by(a))
            .or_else(|| self.backing.loaned().map(|pages| pages.admitted_by(a))).unwrap_or(false);
        if !admitted {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        let mut credit = a.reserve(0).map_err(|status| a.take_operational_error().unwrap_or(status))?;
        let mut rows = packed_token_blocks::exact_vec(self.len(), &mut credit, a)?;
        for (index, token) in self.iter().enumerate() {
            if index % 64 == 0 {
                packed_token_blocks::poll(a)?;
            }
            rows.push(token);
        }
        use_tokens(&rows)
    }
}

enum TokenIter<'a> {
    Dense(std::iter::Copied<std::slice::Iter<'a, SpanToken>>),
    Packed { blocks: &'a PackedTokenBlocks, ordinals: std::ops::Range<usize> },
    Loaned { pages: &'a LoanedTokenPages, ordinals: std::ops::Range<usize> },
}

impl Iterator for TokenIter<'_> {
    type Item = SpanToken;
    fn next(&mut self) -> Option<Self::Item> { self.nth(0) }
    fn nth(&mut self, n: usize) -> Option<Self::Item> {
        match self {
            Self::Dense(rows) => rows.nth(n),
            Self::Packed { blocks, ordinals } => ordinals.nth(n).map(|at| blocks.get(at).expect("issued packed token ordinal")),
            Self::Loaned { pages, ordinals } => ordinals.nth(n).map(|at| pages.get(at).expect("issued loaned token ordinal")),
        }
    }
    fn size_hint(&self) -> (usize, Option<usize>) { let len = self.len(); (len, Some(len)) }
}

impl DoubleEndedIterator for TokenIter<'_> {
    fn next_back(&mut self) -> Option<Self::Item> { self.nth_back(0) }
    fn nth_back(&mut self, n: usize) -> Option<Self::Item> {
        match self {
            Self::Dense(rows) => rows.nth_back(n),
            Self::Packed { blocks, ordinals } => ordinals.nth_back(n).map(|at| blocks.get(at).expect("issued packed token ordinal")),
            Self::Loaned { pages, ordinals } => ordinals.nth_back(n).map(|at| pages.get(at).expect("issued loaned token ordinal")),
        }
    }
}

impl ExactSizeIterator for TokenIter<'_> {
    fn len(&self) -> usize {
        match self {
            Self::Dense(rows) => rows.len(),
            Self::Packed { ordinals, .. } | Self::Loaned { ordinals, .. } => ordinals.len(),
        }
    }
}
/// The actual token Vec moves once; aliases retain its resource root. No Arc or
/// Weak escape exists, and control allocation dies before payload/credit.
pub struct SharedSpanTokens(Option<Arc<SharedPayload>>);
impl Clone for SharedSpanTokens{fn clone(&self)->Self{Self(Some(self.0.as_ref().expect("live shared tokens").clone()))}}
impl Drop for SharedSpanTokens{fn drop(&mut self){if let Some(owner)=self.0.take(){if let Some(payload)=Arc::into_inner(owner){drop(payload)}}}}
impl fmt::Debug for SharedSpanTokens{fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{f.debug_struct("SharedSpanTokens").field("len",&self.window().len()).finish_non_exhaustive()}}
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
impl SharedSpanTokens{
 /// Resource-only move, not token/source authorization. The actual producer
 /// remains responsible for real grammar/ordering/current acquisition proof.
 pub fn from_admitted_using(tokens:Vec<SpanToken>,credit:SettingRootLease,a:&SettingAdmission<'_>)->io::Result<Self>{
  let bytes=tokens.capacity().checked_mul(std::mem::size_of::<SpanToken>()).ok_or(io::ErrorKind::OutOfMemory)?;
  let mut pending=SharedPayload{tokens:SharedTokenData::Dense(tokens),credit};poll(a)?;
  if !a.matches_lease_domain(&pending.credit)||pending.credit.bytes()<bytes{return Err(io::Error::new(io::ErrorKind::InvalidInput,"shared tokens lack actual same-domain buffer admission"))}
  let fixed=std::mem::size_of::<SharedPayload>().checked_add(2*std::mem::size_of::<usize>()).ok_or(io::ErrorKind::OutOfMemory)?;
  a.grow(&mut pending.credit,fixed).map_err(|e|a.take_operational_error().unwrap_or(e))?;poll(a)?;
  Ok(Self(Some(Arc::new(pending))))
 }
 pub(crate) fn from_packed_using(blocks: PackedTokenBlocks, a: &SettingAdmission<'_>) -> io::Result<Self> {
    poll(a)?;
    if blocks.failed() || !blocks.admitted_by(a) { return Err(io::ErrorKind::InvalidInput.into()); }
    let fixed = std::mem::size_of::<SharedPayload>() + 2 * std::mem::size_of::<usize>();
    let credit = a.reserve(fixed).map_err(|status| a.take_operational_error().unwrap_or(status))?;
    Ok(Self(Some(Arc::new(SharedPayload { tokens: SharedTokenData::Packed(blocks), credit }))))
 }
 pub(crate) fn from_loaned_using(mut pages: LoanedTokenPages, a: &SettingAdmission<'_>) -> io::Result<Self> {
    poll(a)?;
    pages.retain_adopted_prefix(a)?;
    let fixed = std::mem::size_of::<SharedPayload>() + 2 * std::mem::size_of::<usize>();
    let credit = a.reserve(fixed).map_err(|status| a.take_operational_error().unwrap_or(status))?;
    Ok(Self(Some(Arc::new(SharedPayload { tokens: SharedTokenData::Loaned(pages), credit }))))
 }
 pub fn window(&self) -> TokenWindow<'_> {
    TokenWindow::full(TokenBacking::Shared(self.0.as_deref().expect("live shared tokens")))
 }
 pub fn same_owner(&self,other:&Self)->bool{Arc::ptr_eq(self.0.as_ref().unwrap(),other.0.as_ref().unwrap())}
 pub fn admitted_by(&self,a:&SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.0.as_ref().unwrap().credit)}
 /// Allocation identity only, not semantic/source authority. Actual collector
 /// deduplicates across expanded/primary/header aliases at the same addresses.
 pub fn visit_storage(&self,visit:impl FnMut(usize,usize,usize)){
  self.visit_storage_with_backing_filter(visit, &mut |_| false);
 }
 /// Resource-only owners of the actual immutable token page loans.
 #[doc(hidden)]
 pub fn try_visit_backing_owners(&self, visit: &mut dyn FnMut(&dyn std::any::Any) -> io::Result<()>) -> io::Result<()> {
  match &self.0.as_ref().expect("live shared token owner").tokens {
   SharedTokenData::Loaned(pages) => pages.try_visit_backing_owners(visit),
   _ => Ok(()),
  }
 }
 fn visit_storage_with_backing_filter(&self,mut visit:impl FnMut(usize,usize,usize), skip:&mut dyn FnMut(&dyn std::any::Any)->bool){
  let owner=self.0.as_ref().unwrap();let fixed=std::mem::size_of::<SharedPayload>()+2*std::mem::size_of::<usize>();visit(Arc::as_ptr(owner)as usize,fixed,fixed);
  match &owner.tokens {
    SharedTokenData::Dense(tokens) if tokens.capacity()!=0 => visit(tokens.as_ptr() as usize,tokens.len()*std::mem::size_of::<SpanToken>(),tokens.capacity()*std::mem::size_of::<SpanToken>()),
    SharedTokenData::Dense(_) => {},
    SharedTokenData::Packed(blocks) => blocks.visit_storage(&mut visit),
    SharedTokenData::Loaned(pages) => pages.visit_storage(&mut visit, skip),
  }
  owner.credit.visit_counter_storage(|p,n|{let n=n+2*std::mem::size_of::<usize>();visit(p,n,n)});
 }
}
/// Ordinary Native keeps its original owned Vec algorithms/clone behavior;
/// genuine final Original handoff shares one immutable actual allocation.
#[derive(Clone,Debug)]pub enum SpanTokenStorage{Owned(Vec<SpanToken>),Shared(SharedSpanTokens)}
impl Default for SpanTokenStorage{fn default()->Self{Self::Owned(Vec::new())}}
impl From<Vec<SpanToken>> for SpanTokenStorage{fn from(tokens:Vec<SpanToken>)->Self{Self::Owned(tokens)}}
impl From<SharedSpanTokens> for SpanTokenStorage{fn from(tokens:SharedSpanTokens)->Self{Self::Shared(tokens)}}
impl PartialEq for SpanTokenStorage {
    fn eq(&self, other: &Self) -> bool {
        let left = self.window();
        let right = other.window();
        left.same_interval(right) || match (left.as_dense_slice(), right.as_dense_slice()) {
            (Some(left), Some(right)) => left == right,
            _ => left.iter().eq(right.iter()),
        }
    }
}
impl Eq for SpanTokenStorage {}
impl SpanTokenStorage {
 pub fn window(&self) -> TokenWindow<'_> {
    match self {
        Self::Owned(tokens) => TokenWindow::from_vec(tokens),
        Self::Shared(tokens) => tokens.window(),
    }
 }
 pub fn shared(&self)->Option<&SharedSpanTokens>{match self{Self::Shared(tokens)=>Some(tokens),_=>None}}
 pub fn visit_storage(&self,visit:impl FnMut(usize,usize,usize)){
  self.visit_storage_with_backing_filter(visit, &mut |_| false);
 }
 /// The caller must prove external funding for each omitted concrete owner.
 /// Owned buffers, loan wrappers, directories and tails always reach visit.
 #[doc(hidden)]
 pub fn visit_storage_with_backing_filter(&self,mut visit:impl FnMut(usize,usize,usize), skip:&mut dyn FnMut(&dyn std::any::Any)->bool){match self{Self::Shared(tokens)=>tokens.visit_storage_with_backing_filter(visit,skip),Self::Owned(tokens)=>{if tokens.capacity()!=0{visit(tokens.as_ptr()as usize,tokens.len()*std::mem::size_of::<SpanToken>(),tokens.capacity()*std::mem::size_of::<SpanToken>())}}}}
}
#[cfg(test)]mod tests{
 use super::*;use std::sync::atomic::{Ordering};
 #[test]fn actual_vec_moves_once_and_last_alias_keeps_same_buffer_credit_without_source_or_ast_owner(){let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let tokens=crate::lex_spans("a+2").tokens;let ptr=tokens.as_ptr();let credit=a.reserve(tokens.capacity()*std::mem::size_of::<SpanToken>()).unwrap();let shared=SharedSpanTokens::from_admitted_using(tokens,credit,&a).unwrap();let primary:SpanTokenStorage=shared.clone().into();let expanded:SpanTokenStorage=shared.clone().into();let header:SpanTokenStorage=shared.clone().into();assert_eq!(primary.window().as_dense_slice().unwrap().as_ptr(),ptr);assert_eq!(expanded.window().as_dense_slice().unwrap().as_ptr(),ptr);assert_eq!(header.window().as_dense_slice().unwrap().as_ptr(),ptr);assert!(primary.shared().unwrap().same_owner(header.shared().unwrap()));let charge=used.load(Ordering::Acquire);drop((shared,primary,expanded));assert_eq!(used.load(Ordering::Acquire),charge);drop(header);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn foreign_short_and_first_io_refuse_without_losing_actual_storage_credit_and_fresh_handoff_recovers(){let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let other=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let b=SettingAdmission::new(&other,1<<20,&||Ok(()));let tokens=crate::lex_spans("x").tokens;let n=tokens.capacity()*std::mem::size_of::<SpanToken>();assert_eq!(SharedSpanTokens::from_admitted_using(tokens,b.reserve(n).unwrap(),&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(other.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());let tokens=crate::lex_spans("x").tokens;assert_eq!(SharedSpanTokens::from_admitted_using(tokens,a.reserve(0).unwrap(),&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);let fault=||Err(io::Error::from_raw_os_error(1450));let fail=SettingAdmission::new(&used,1<<20,&fault);let tokens=crate::lex_spans("x").tokens;let n=tokens.capacity()*std::mem::size_of::<SpanToken>();assert_eq!(SharedSpanTokens::from_admitted_using(tokens,a.reserve(n).unwrap(),&fail).unwrap_err().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());let tokens=crate::lex_spans("x").tokens;let n=tokens.capacity()*std::mem::size_of::<SpanToken>();drop(SharedSpanTokens::from_admitted_using(tokens,a.reserve(n).unwrap(),&a).unwrap());assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}

 #[test]
 fn exact_windows_keep_their_backing_and_ordinal_through_subranges_and_shared_aliases() {
    let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
    let tokens = crate::lex_spans("a+b+c").tokens;
    let foreign: SpanTokenStorage = tokens.clone().into();
    let credit = a.reserve(tokens.capacity() * std::mem::size_of::<SpanToken>()).unwrap();
    let shared = SharedSpanTokens::from_admitted_using(tokens, credit, &a).unwrap();
    let alias: SpanTokenStorage = shared.clone().into();

    let window = shared.window();
    let middle = window.range(1, 4).unwrap();
    let nested = middle.range(1, 2).unwrap();
    assert!(nested.same_interval(alias.window().range(2, 3).unwrap()));
    assert!(nested.as_dense_slice().unwrap().as_ptr() == shared.window().as_dense_slice().unwrap()[2..3].as_ptr());
    assert_eq!(middle.get(1), window.get(2));
    assert_eq!(middle.iter().rev().collect::<Vec<_>>(), shared.window().as_dense_slice().unwrap()[1..4].iter().rev().copied().collect::<Vec<_>>());
    assert_eq!(middle.partition_point(|token| token.span.start < 3), 2);
    assert!(!nested.same_interval(alias.window().range(1, 2).unwrap()));
    assert_eq!(nested.as_dense_slice().unwrap(), foreign.window().range(2, 3).unwrap().as_dense_slice().unwrap());
    assert!(!nested.same_interval(foreign.window().range(2, 3).unwrap()));
    assert!(window.range(2, 1).is_none());
    assert!(window.range(0, window.len() + 1).is_none());
    assert!(middle.range(1, 1).unwrap().same_interval(window.range(2, 2).unwrap()));
    assert!(!window.range(1, 1).unwrap().same_interval(window.range(2, 2).unwrap()));

    let empty = SpanTokenStorage::default();
    let foreign_empty = SpanTokenStorage::default();
    assert!(empty.window().same_interval(empty.window()));
    assert!(!empty.window().same_interval(foreign_empty.window()));
    drop((shared, alias));
    assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
 }

}
