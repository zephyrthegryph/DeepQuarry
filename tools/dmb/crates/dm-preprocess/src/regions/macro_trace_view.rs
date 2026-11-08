//! One immutable trace projection. Original parent chains are exact prefixes
//! of the same issued frame array, while native traces keep authored chains.
use super::{DefinitionOrigin, MacroExpansion};
use dm_syntax::{SettingAdmission, SettingRootLease, Span};
use std::{cell::UnsafeCell, fmt, io, mem::{self, MaybeUninit}, sync::{Arc, OnceLock, atomic::{AtomicUsize, Ordering}}};

/// Exact name and optional authored definition. An authored epoch and its
/// projected frames share one owner; bootstrap names have no definition.
/// Both allocations stay funded through detached diagnostic/point aliases.
pub(super) struct OriginalMacroAuthor {
    name: Box<str>,
    origin: Option<DefinitionOrigin>,
    credit: SettingRootLease,
}
impl OriginalMacroAuthor {
    const BYTES: usize = mem::size_of::<Self>() + 2 * mem::size_of::<usize>();

    pub(super) fn allocation_bytes(name_bytes: usize) -> Option<usize> { Self::BYTES.checked_add(name_bytes) }

    pub(super) fn new_using(name: &str, origin: Option<DefinitionOrigin>, a: &SettingAdmission<'_>) -> io::Result<Arc<Self>> {
        let name_bytes = name.len();
        let bytes = Self::allocation_bytes(name_bytes).ok_or(io::ErrorKind::OutOfMemory)?;
        let credit = a.reserve(bytes).map_err(|error| a.take_operational_error().unwrap_or(error))?;
        let name = Box::from(name);
        Ok(Arc::new(Self { name, origin, credit }))
    }

    pub(super) fn matches(&self, name: &str, actual: &DefinitionOrigin, a: &SettingAdmission<'_>) -> bool {
        self.name.as_ref() == name && self.matches_origin(actual, a)
    }

    pub(super) fn matches_origin(&self, actual: &DefinitionOrigin, a: &SettingAdmission<'_>) -> bool {
        a.matches_lease_domain(&self.credit)
            && self.origin.as_ref().is_some_and(|origin| {
                Arc::ptr_eq(&origin.path, &actual.path)
                    && origin.source_span == actual.source_span
                    && origin.source_line == actual.source_line
            })
    }

    pub(super) fn name(&self) -> &str { &self.name }
    pub(super) fn is_admitted_by(&self,a:&SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.credit)}
    pub(super) fn origin(&self) -> Option<&DefinitionOrigin> { self.origin.as_ref() }
    pub(super) fn retained_bytes(&self) -> usize { self.credit.bytes() }
    fn buffers(&self) -> [(usize, usize); 2] {
        let (address, bytes) = self.buffer();
        [(address, bytes), (self.name.as_ptr() as usize, self.name.len())]
    }
    pub(super) fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        for (address, bytes) in self.buffers() {
            if bytes != 0 { visit(address, bytes, bytes); }
        }
    }

    pub(super) fn buffer(&self) -> (usize, usize) {
        (std::ptr::from_ref(self) as usize, Self::BYTES)
    }
}
impl PartialEq for OriginalMacroAuthor {
    fn eq(&self, other: &Self) -> bool { self.name == other.name && self.origin == other.origin }
}
impl Eq for OriginalMacroAuthor {}
impl fmt::Debug for OriginalMacroAuthor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { f.debug_struct("OriginalMacroAuthor").field("name", &self.name).field("origin", &self.origin).finish() }
}

#[derive(Debug, Eq, PartialEq)]
pub(super) struct OriginalMacroFrame {
    pub(super) invocation_span: Span,
    pub(super) author: Arc<OriginalMacroAuthor>,
}

#[derive(Debug, Eq, PartialEq)]
pub(super) struct NarrowOriginalMacroFrame {
    invocation_span: [u32; 2],
    author: Arc<OriginalMacroAuthor>,
}

impl NarrowOriginalMacroFrame {
    pub(super) fn checked(frame: OriginalMacroFrame) -> Option<Self> {
        let invocation_span = [u32::try_from(frame.invocation_span.start).ok()?,
                               u32::try_from(frame.invocation_span.end).ok()?];
        Some(Self { invocation_span, author: frame.author })
    }

    fn view(&self) -> OriginalMacroFrameView<'_> {
        let [start, end] = self.invocation_span;
        OriginalMacroFrameView { invocation_span: Span::new(start as usize, end as usize), author: &self.author }
    }
}

#[derive(PartialEq, Eq)]
pub(super) struct OriginalMacroFrameView<'a> {
    pub(super) invocation_span: Span,
    pub(super) author: &'a Arc<OriginalMacroAuthor>,
}

/// Fully issued singleton DATA on the producer stack. Its representation
/// chooses the exact allocation width before the original frame admission.
pub(super) enum PendingOriginalSingleton {
    Narrow(NarrowOriginalMacroFrame),
    Wide(OriginalMacroFrame),
}
impl PendingOriginalSingleton {
    pub(super) fn from_frame(frame: OriginalMacroFrame) -> Self {
        if mem::size_of::<NarrowOriginalMacroFrame>() < mem::size_of::<OriginalMacroFrame>() {
            if let (Ok(start), Ok(end)) = (u32::try_from(frame.invocation_span.start), u32::try_from(frame.invocation_span.end)) {
                return Self::Narrow(NarrowOriginalMacroFrame { invocation_span: [start, end], author: frame.author });
            }
        }
        Self::Wide(frame)
    }
    pub(super) fn bytes(&self) -> usize {
        match self {
            Self::Narrow(_) => mem::size_of::<NarrowOriginalMacroFrame>(),
            Self::Wide(_) => mem::size_of::<OriginalMacroFrame>(),
        }
    }
    pub(super) fn finish(self) -> OriginalMacroTrace {
        match self {
            Self::Narrow(frame) => OriginalMacroTrace::NarrowSingle(Arc::new(frame)),
            Self::Wide(frame) => OriginalMacroTrace::Single(Arc::new(frame)),
        }
    }
}

const SINGLETON_PAGE_ROWS: usize = 64;
const SINGLETON_PAGE_AUTHORS: usize = 15;
const SINGLETON_OVERFLOW_AUTHORS: usize = SINGLETON_PAGE_ROWS - SINGLETON_PAGE_AUTHORS;
type AuthorCell = UnsafeCell<MaybeUninit<Arc<OriginalMacroAuthor>>>;

struct SingletonAuthorOverflow {
    rows: [AuthorCell; SINGLETON_OVERFLOW_AUTHORS],
    _credit: SettingRootLease,
}
// SAFETY: the only containing page publishes each cell once via its
// author-prefix Release. No overflow handle is exposed to readers.
unsafe impl Sync for SingletonAuthorOverflow {}
impl SingletonAuthorOverflow {
    const BYTES: usize = mem::size_of::<Self>() + 2 * mem::size_of::<usize>();
}


/// One exact allocation and independently escaping credit. The sole producer
/// appends through its noncloneable pool; readers only see a published prefix.
pub(super) struct SingletonTracePage {
    spans: [UnsafeCell<MaybeUninit<[u32; 2]>>; SINGLETON_PAGE_ROWS],
    slots: [UnsafeCell<MaybeUninit<u8>>; SINGLETON_PAGE_ROWS],
    authors: [AuthorCell; SINGLETON_PAGE_AUTHORS],
    overflow: OnceLock<Arc<SingletonAuthorOverflow>>,
    authors_issued: AtomicUsize,
    issued: AtomicUsize,
    // Author aliases drop before this page returns its storage credit.
    _credit: SettingRootLease,
}

// SAFETY: all stored frames are Send + Sync. Only SingletonTracePool writes,
// sequentially, into the first unpublished slot. The Release store publishes
// initialization permanently; no published slot is ever written or moved.
// Shared readers use Acquire before lending exactly one initialized cell.
unsafe impl Sync for SingletonTracePage {}

impl SingletonTracePage {
    const BYTES: usize = mem::size_of::<Self>() + 2 * mem::size_of::<usize>();

    fn issued(&self) -> usize { self.issued.load(Ordering::Acquire) }

    fn author_slot(&self, author: &Arc<OriginalMacroAuthor>) -> Option<usize> {
        let len = self.authors_issued.load(Ordering::Acquire);
        (0..len).find(|&at| Arc::ptr_eq(self.author(at), author))
            .or_else(|| (len < SINGLETON_PAGE_ROWS).then_some(len))
    }

    fn author(&self, at: usize) -> &Arc<OriginalMacroAuthor> {
        assert!(at < self.authors_issued.load(Ordering::Acquire));
        // SAFETY: the exact author prefix is published once and never moved.
        unsafe { (&*self.author_cell(at).get()).assume_init_ref() }
    }

    fn author_cell(&self, at: usize) -> &AuthorCell {
        if at < SINGLETON_PAGE_AUTHORS {
            &self.authors[at]
        } else {
            &self.overflow.get().expect("funded singleton author overflow").rows[at - SINGLETON_PAGE_AUTHORS]
        }
    }

    fn prepare_author_overflow(&self, a: &SettingAdmission<'_>) -> io::Result<bool> {
        let Some(credit) = a.try_reserve_optimization(SingletonAuthorOverflow::BYTES)
            .map_err(|error| a.take_operational_error().unwrap_or(error))? else { return Ok(false); };
        let owner = Arc::new(SingletonAuthorOverflow {
            rows: std::array::from_fn(|_| UnsafeCell::new(MaybeUninit::uninit())),
            _credit: credit,
        });
        assert!(self.overflow.set(owner).is_ok(), "one exclusive singleton producer");
        Ok(true)
    }

    fn overflow_backing(&self) -> Option<(usize, usize)> {
        self.overflow.get().map(|owner| (Arc::as_ptr(owner) as usize, SingletonAuthorOverflow::BYTES))
    }

    fn row(&self, at: usize) -> OriginalMacroFrameView<'_> {
        assert!(at < self.issued());
        // SAFETY: the issued row Release follows both geometry/slot writes
        // and publication of its immutable author.
        let ([start, end], slot) = unsafe {
            (*(&*self.spans[at].get()).assume_init_ref(),
             *(&*self.slots[at].get()).assume_init_ref())
        };
        OriginalMacroFrameView {
            invocation_span: Span::new(start as usize, end as usize),
            author: self.author(usize::from(slot)),
        }
    }

    fn row_address(&self, at: usize) -> usize {
        assert!(at < self.issued());
        self.spans[at].get() as usize
    }

    fn row_buffers(&self, at: usize) -> [(usize, usize); 2] {
        [(self.row_address(at), mem::size_of::<[u32; 2]>()),
         (self.slots[at].get() as usize, mem::size_of::<u8>())]
    }
}
impl fmt::Debug for SingletonTracePage {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SingletonTracePage").field("issued", &self.issued()).finish()
    }
}
impl Drop for SingletonTracePage {
    fn drop(&mut self) {
        let issued = *self.authors_issued.get_mut();
        for at in 0..issued {
            // SAFETY: the last page owns the entire initialized author prefix,
            // including the unaliased optional overflow allocation.
            unsafe { (&mut *self.author_cell(at).get()).assume_init_drop(); }
        }
        if let Some(owner) = self.overflow.take() {
            drop(Arc::into_inner(owner));
        }
    }
}

/// All page aliases use this last-owner path. Arc control is destroyed
/// before the moved-out payload returns its page lease.
#[derive(Clone, Debug)]
pub(super) struct SingletonPageOwner(Option<Arc<SingletonTracePage>>);
impl SingletonPageOwner {
    fn shared(&self) -> &Arc<SingletonTracePage> { self.0.as_ref().expect("live singleton trace page") }
    pub(super) fn same_page(&self, other:&Self)->bool{Arc::ptr_eq(self.shared(),other.shared())}
}
impl std::ops::Deref for SingletonPageOwner {
    type Target = SingletonTracePage;
    fn deref(&self) -> &Self::Target { self.shared() }
}
impl Drop for SingletonPageOwner {
    fn drop(&mut self) {
        if let Some(page) = self.0.take() { drop(Arc::into_inner(page)); }
    }
}

#[derive(Default)]
pub(super) struct SingletonTracePool {
    current: Option<SingletonPageOwner>,
    #[cfg(debug_assertions)]
    pages_granted: usize,
    #[cfg(debug_assertions)]
    overflows_granted: usize,
}
impl SingletonTracePool {
    /// Called after actual definition validation. Pressure declines this
    /// optional page without replacing the established exact singleton route.
    pub(super) fn prepare_using(&mut self, frame: &NarrowOriginalMacroFrame, a: &SettingAdmission<'_>) -> io::Result<Option<usize>> {
        if let Some(page) = &self.current {
            if !a.matches_lease_domain(&page._credit) { return Err(io::ErrorKind::InvalidInput.into()); }
            if page.issued() < SINGLETON_PAGE_ROWS {
                let slot = page.author_slot(&frame.author).expect("at most one author per issued row");
                if slot >= SINGLETON_PAGE_AUTHORS && page.overflow.get().is_none() {
                    if !page.prepare_author_overflow(a)? { return Ok(None); }
                    #[cfg(debug_assertions)]
                    { self.overflows_granted += 1; }
                }
                return Ok(Some(slot));
            }
        }
        let Some(credit) = a.try_reserve_optimization(SingletonTracePage::BYTES)
            .map_err(|error| a.take_operational_error().unwrap_or(error))? else { return Ok(None); };
        self.current = Some(SingletonPageOwner(Some(Arc::new(SingletonTracePage {
            spans: std::array::from_fn(|_| UnsafeCell::new(MaybeUninit::uninit())),
            slots: std::array::from_fn(|_| UnsafeCell::new(MaybeUninit::uninit())),
            authors: std::array::from_fn(|_| UnsafeCell::new(MaybeUninit::uninit())),
            authors_issued: AtomicUsize::new(0),
            overflow: OnceLock::new(),
            issued: AtomicUsize::new(0),
            _credit: credit,
        }))));
        #[cfg(debug_assertions)]
        { self.pages_granted += 1; }
        Ok(Some(0))
    }

    #[cfg(debug_assertions)]
    pub(super) fn bytes_granted(&self) -> usize {
        self.pages_granted.saturating_mul(SingletonTracePage::BYTES)
            .saturating_add(self.overflows_granted.saturating_mul(SingletonAuthorOverflow::BYTES))
    }

    pub(super) fn append(&mut self, frame: NarrowOriginalMacroFrame, slot: usize) -> OriginalMacroTrace {
        let page = self.current.as_ref().expect("prepared singleton page");
        let at = page.issued();
        assert!(at < SINGLETON_PAGE_ROWS);
        let len = page.authors_issued.load(Ordering::Relaxed);
        assert!(slot <= len && slot < SINGLETON_PAGE_ROWS);
        if slot == len {
            // SAFETY: sole producer writes the next unpublished author once.
            unsafe { (*page.author_cell(slot).get()).write(frame.author); }
            page.authors_issued.store(len + 1, Ordering::Release);
        } else {
            assert!(Arc::ptr_eq(page.author(slot), &frame.author));
        }
        // SAFETY: only the sole producer can write the next unpublished row.
        unsafe {
            (*page.spans[at].get()).write(frame.invocation_span);
            (*page.slots[at].get()).write(slot as u8);
        }
        page.issued.store(at + 1, Ordering::Release);
        OriginalMacroTrace::PooledSingleton { ordinal: at as u16, page: page.clone() }
    }
}

/// A point owns one exact projected trace allocation. Narrow singletons
/// retain only their own author, with lossless wide and multi-frame fallbacks.
#[derive(Clone, Debug)]
pub(super) enum OriginalMacroTrace {
    Single(Arc<OriginalMacroFrame>),
    NarrowSingle(Arc<NarrowOriginalMacroFrame>),
    PooledSingleton { ordinal: u16, page: SingletonPageOwner },
    Shared(Arc<Box<[OriginalMacroFrame]>>),
    NarrowShared(Arc<Box<[NarrowOriginalMacroFrame]>>),
}
#[cfg(target_pointer_width = "64")]
const _: () = assert!(mem::size_of::<OriginalMacroTrace>() == 16);

impl PartialEq for OriginalMacroTrace {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Single(a), Self::Single(b)) => a == b,
            (Self::Shared(a), Self::Shared(b)) => a == b,
            (Self::NarrowShared(a), Self::NarrowShared(b)) => a == b,
            (Self::NarrowSingle(a), Self::NarrowSingle(b)) => a == b,
            (Self::PooledSingleton { ordinal, page }, Self::NarrowSingle(row))
            | (Self::NarrowSingle(row), Self::PooledSingleton { ordinal, page }) =>
                page.row(usize::from(*ordinal)) == row.view(),
            (Self::PooledSingleton { ordinal: left, page: a }, Self::PooledSingleton { ordinal: right, page: b }) =>
                a.row(usize::from(*left)) == b.row(usize::from(*right)),
            _ => false,
        }
    }
}
impl Eq for OriginalMacroTrace {}

impl OriginalMacroTrace {
    pub(super) fn empty() -> Self { Self::Shared(Arc::new(Box::new([]))) }

    pub(super) fn same_owner(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Single(a), Self::Single(b)) => Arc::ptr_eq(a, b),
            (Self::NarrowSingle(a), Self::NarrowSingle(b)) => Arc::ptr_eq(a, b),
            (Self::PooledSingleton { ordinal: left, page: a }, Self::PooledSingleton { ordinal: right, page: b }) =>
                left == right && Arc::ptr_eq(a.shared(), b.shared()),
            (Self::Shared(a), Self::Shared(b)) => Arc::ptr_eq(a, b),
            (Self::NarrowShared(a), Self::NarrowShared(b)) => Arc::ptr_eq(a, b),
            _ => false,
        }
    }

    fn owner_address(&self) -> usize {
        match self {
            Self::Single(rows) => Arc::as_ptr(rows) as usize,
            Self::NarrowSingle(rows) => Arc::as_ptr(rows) as usize,
            Self::PooledSingleton { ordinal, page } => page.row_address(usize::from(*ordinal)),
            Self::Shared(rows) => Arc::as_ptr(rows) as usize,
            Self::NarrowShared(rows) => Arc::as_ptr(rows) as usize,
        }
    }

    fn buffers(&self) -> [(usize, usize); 2] {
        match self {
            Self::Single(_) => [(self.owner_address(), mem::size_of::<OriginalMacroFrame>()), (0, 0)],
            Self::NarrowSingle(_) => [(self.owner_address(), mem::size_of::<NarrowOriginalMacroFrame>()), (0, 0)],
            Self::PooledSingleton { ordinal, page } => page.row_buffers(usize::from(*ordinal)),
            Self::Shared(rows) => [
                (self.owner_address(), mem::size_of::<Box<[OriginalMacroFrame]>>()),
                (rows.as_ptr() as usize, mem::size_of_val(rows.as_ref().as_ref())),
            ],
            Self::NarrowShared(rows) => [
                (self.owner_address(), mem::size_of::<Box<[NarrowOriginalMacroFrame]>>()),
                (rows.as_ptr() as usize, mem::size_of_val(rows.as_ref().as_ref())),
            ],
        }
    }

    #[cfg(test)]
    pub(super) fn strong_count(&self) -> usize {
        match self {
            Self::Single(rows) => Arc::strong_count(rows),
            Self::NarrowSingle(rows) => Arc::strong_count(rows),
            Self::PooledSingleton { page, .. } => Arc::strong_count(page.shared()),
            Self::Shared(rows) => Arc::strong_count(rows),
            Self::NarrowShared(rows) => Arc::strong_count(rows),
        }
    }
    pub(super) fn len(&self) -> usize {
        match self {
            Self::Shared(rows) => rows.len(),
            Self::NarrowShared(rows) => rows.len(),
            _ => 1,
        }
    }

    pub(super) fn frame(&self, at: usize) -> Option<OriginalMacroFrameView<'_>> {
        let row: &OriginalMacroFrame = match self {
            Self::Single(row) if at == 0 => row,
            Self::NarrowSingle(row) if at == 0 => return Some(row.view()),
            Self::PooledSingleton { ordinal, page } if at == 0 => return Some(page.row(usize::from(*ordinal))),
            Self::NarrowShared(rows) => return rows.get(at).map(NarrowOriginalMacroFrame::view),
            Self::Shared(rows) => rows.get(at)?,
            _ => return None,
        };
        Some(OriginalMacroFrameView { invocation_span: row.invocation_span, author: &row.author })
    }

    #[cfg(debug_assertions)]
    pub(super) fn frame_storage_bytes(&self) -> usize {
        match self {
            Self::Single(_) => mem::size_of::<OriginalMacroFrame>(),
            Self::NarrowSingle(_) => mem::size_of::<NarrowOriginalMacroFrame>(),
            Self::PooledSingleton { .. } => mem::size_of::<[u32; 2]>() + mem::size_of::<u8>(),
            Self::Shared(rows) => mem::size_of_val(rows.as_ref().as_ref()),
            Self::NarrowShared(rows) => mem::size_of_val(rows.as_ref().as_ref()),
        }
    }

    fn parents(&self, at: usize) -> Parents<'_> {
        match self {
            Self::Shared(rows) => Parents::Original(&rows[..at]),
            Self::NarrowShared(rows) => Parents::NarrowOriginal(&rows[..at]),
            _ => Parents::Original(&[]),
        }
    }
}

#[derive(Clone)]
enum Owned {
    Native(Arc<Box<[MacroExpansion]>>),
    Original(OriginalMacroTrace),
}

/// Cloneable exact trace owner. An Original source location clones only the
/// compact allocation, never a materialized native chain or another parser.
#[derive(Clone)]
pub struct MacroTrace(Owned);

#[derive(Clone, Copy)]
enum Borrowed<'a> {
    Native(&'a Arc<Box<[MacroExpansion]>>),
    Original(&'a OriginalMacroTrace),
    Pooled(&'a SingletonPageOwner,u16),
}

#[derive(Clone, Copy)]
pub struct MacroTraceView<'a>(Borrowed<'a>);

#[derive(Clone, Copy)]
enum Parents<'a> {
    Native(&'a Arc<[Arc<str>]>),
    Original(&'a [OriginalMacroFrame]),
    NarrowOriginal(&'a [NarrowOriginalMacroFrame]),
}

#[derive(Clone, Copy)]
pub struct MacroTraceParents<'a>(Parents<'a>);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct MacroExpansionView<'a> {
    pub name: &'a str,
    pub invocation_span: Span,
    pub replacement_chain: MacroTraceParents<'a>,
    pub definition: Option<&'a DefinitionOrigin>,
}

impl<'a> MacroTraceParents<'a> {
    pub fn len(self) -> usize {
        match self.0 {
            Parents::Native(rows) => rows.len(),
            Parents::Original(rows) => rows.len(),
            Parents::NarrowOriginal(rows) => rows.len(),
        }
    }

    pub fn is_empty(self) -> bool { self.len() == 0 }

    pub fn get(self, ordinal: usize) -> Option<&'a str> {
        match self.0 {
            Parents::Native(rows) => rows.get(ordinal).map(Arc::as_ref),
            Parents::Original(rows) => rows.get(ordinal).map(|row| row.author.name()),
            Parents::NarrowOriginal(rows) => rows.get(ordinal).map(|row| row.author.name()),
        }
    }

    pub fn iter(self) -> impl ExactSizeIterator<Item = &'a str> + DoubleEndedIterator {
        (0..self.len()).map(move |i| self.get(i).expect("issued trace parent"))
    }

    /// Physical independent slice only. Original prefixes borrow the
    /// already-accounted trace frame storage, and do not own any array.
    pub fn native_owner(self) -> Option<&'a Arc<[Arc<str>]>> {
        match self.0 { Parents::Native(rows) => Some(rows), Parents::Original(_) | Parents::NarrowOriginal(_) => None }
    }
}

impl PartialEq for MacroTraceParents<'_> {
    fn eq(&self, other: &Self) -> bool { self.iter().eq(other.iter()) }
}
impl Eq for MacroTraceParents<'_> {}
impl fmt::Debug for MacroTraceParents<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { f.debug_list().entries(self.iter()).finish() }
}

impl From<Arc<Box<[MacroExpansion]>>> for MacroTrace {
    fn from(rows: Arc<Box<[MacroExpansion]>>) -> Self { Self(Owned::Native(rows)) }
}
impl Default for MacroTrace {
    fn default() -> Self { Arc::<Box<[MacroExpansion]>>::default().into() }
}
impl MacroTrace {
    pub fn view(&self) -> MacroTraceView<'_> {
        match &self.0 {
            Owned::Native(rows) => rows.into(),
            Owned::Original(rows) => MacroTraceView::original(rows),
        }
    }
    pub fn len(&self) -> usize { self.view().len() }
    pub fn is_empty(&self) -> bool { self.view().is_empty() }
    pub fn iter(&self) -> impl ExactSizeIterator<Item = MacroExpansionView<'_>> + DoubleEndedIterator {
        self.view().iter()
    }
}
impl PartialEq for MacroTrace {
    fn eq(&self, other: &Self) -> bool { self.view() == other.view() }
}
impl Eq for MacroTrace {}
impl fmt::Debug for MacroTrace {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { fmt::Debug::fmt(&self.view(), f) }
}
impl<'a> From<&'a Arc<Box<[MacroExpansion]>>> for MacroTraceView<'a> {
    fn from(rows: &'a Arc<Box<[MacroExpansion]>>) -> Self { Self(Borrowed::Native(rows)) }
}
impl<'a> MacroTraceView<'a> {
    pub(super) fn original(rows: &'a OriginalMacroTrace) -> Self {
        match rows {
            OriginalMacroTrace::PooledSingleton{ordinal,page}=>Self::pooled(page,*ordinal),
            _=>Self(Borrowed::Original(rows)),
        }
    }

    pub(super) fn pooled(page:&'a SingletonPageOwner,ordinal:u16)->Self{
        Self(Borrowed::Pooled(page,ordinal))
    }

    pub(super) fn clone_original(self)->Option<OriginalMacroTrace>{
        match self.0 {
            Borrowed::Native(_)=>None,
            Borrowed::Original(rows)=>Some(rows.clone()),
            Borrowed::Pooled(page,ordinal)=>Some(OriginalMacroTrace::PooledSingleton{page:page.clone(),ordinal}),
        }
    }

    pub fn to_owned(self) -> MacroTrace {
        match self.0 {
            Borrowed::Native(rows) => MacroTrace(Owned::Native(Arc::clone(rows))),
            _ => MacroTrace(Owned::Original(self.clone_original().expect("actual Original trace"))),
        }
    }
    pub fn native_owner(self) -> Option<&'a Arc<Box<[MacroExpansion]>>> {
        match self.0 { Borrowed::Native(rows) => Some(rows), Borrowed::Original(_) | Borrowed::Pooled(..) => None }
    }
    pub fn owner_address(self) -> usize {
        match self.0 {
            Borrowed::Native(rows) => Arc::as_ptr(rows) as usize,
            Borrowed::Original(rows) => rows.owner_address(),
            Borrowed::Pooled(page,ordinal)=>page.row_address(usize::from(ordinal)),
        }
    }
    pub fn same_owner(self, other: Self) -> bool {
        match (self.0, other.0) {
            (Borrowed::Native(a), Borrowed::Native(b)) => Arc::ptr_eq(a,b),
            (Borrowed::Original(a), Borrowed::Original(b)) => a.same_owner(b),
            (Borrowed::Pooled(a,x),Borrowed::Pooled(b,y))=>x==y&&a.same_page(b),
            _ => false,
        }
    }
    pub fn len(self) -> usize {
        match self.0 { Borrowed::Native(rows) => rows.len(), Borrowed::Original(rows) => rows.len(), Borrowed::Pooled(..)=>1 }
    }
    pub fn is_empty(self) -> bool { self.len() == 0 }
    pub fn get(self, at: usize) -> Option<MacroExpansionView<'a>> {
        Some(match self.0 {
            Borrowed::Native(rows) => {
                let row = rows.get(at)?;
                MacroExpansionView {
                    name: &row.name, invocation_span: row.invocation_span,
                    definition: row.definition.as_ref(),
                    replacement_chain: MacroTraceParents(Parents::Native(&row.replacement_chain)),
                }
            }
            Borrowed::Pooled(page,ordinal)=>{
                if at!=0{return None;}
                let row=page.row(usize::from(ordinal));
                MacroExpansionView{
                    name:row.author.name(), invocation_span:row.invocation_span,
                    definition:row.author.origin(),replacement_chain:MacroTraceParents(Parents::Original(&[])),
                }
            }
            Borrowed::Original(rows) => {
                let row = rows.frame(at)?;
                MacroExpansionView {
                    name: row.author.name(), invocation_span: row.invocation_span,
                    definition: row.author.origin(),
                    replacement_chain: MacroTraceParents(rows.parents(at)),
                }
            }
        })
    }
    pub fn iter(self) -> impl ExactSizeIterator<Item = MacroExpansionView<'a>> + DoubleEndedIterator {
        (0..self.len()).map(move |i| self.get(i).expect("issued trace frame"))
    }
    /// Actual author and name allocations for an Original frame. Repeated
    /// aliases share both addresses for retained-heap deduplication.
    pub fn author_buffers(self, at: usize) -> Option<[(usize, usize); 2]> {
        match self.0 {
            Borrowed::Native(_) => None,
            Borrowed::Original(rows) => Some(rows.frame(at)?.author.buffers()),
            Borrowed::Pooled(page,ordinal) if at==0=>Some(page.row(usize::from(ordinal)).author.buffers()),
            Borrowed::Pooled(..)=>None,
        }
    }
    /// Physical pooled backing. A detached trace keeps the whole small
    /// page, while its logical address remains the selected frame address.
    pub fn pooled_backing(self) -> Option<(usize, usize)> {
        let Borrowed::Pooled(page,_) = self.0 else { return None; };
        Some((Arc::as_ptr(page.shared()) as usize, SingletonTracePage::BYTES))
    }

    /// Separately paid author-slot allocation if this page crossed the
    /// inline author count. The containing page remains its sole owner.
    pub fn pooled_overflow_backing(self) -> Option<(usize, usize)> {
        let Borrowed::Pooled(page,_) = self.0 else { return None; };
        page.overflow_backing()
    }

    /// Exact unique author allocations on the published page, including
    /// sibling authors retained only by a detached trace.
    pub fn visit_pooled_authors(self, mut visit: impl FnMut([(usize, usize); 2], Option<&'a DefinitionOrigin>)) {
        let Borrowed::Pooled(page,_) = self.0 else { return; };
        for at in 0..page.authors_issued.load(Ordering::Acquire) {
            let author = page.author(at);
            visit(author.buffers(), author.origin());
        }
    }

    /// Exact row array and Box payload, exclusive of Arc control and children.
    pub fn buffers(self) -> [(usize, usize); 2] {
        match self.0 {
            Borrowed::Native(rows) => [
                (self.owner_address(), mem::size_of::<Box<[MacroExpansion]>>()),
                (rows.as_ptr() as usize, mem::size_of_val(rows.as_ref().as_ref())),
            ],
            Borrowed::Original(rows) => rows.buffers(),
            Borrowed::Pooled(page,ordinal)=>page.row_buffers(usize::from(ordinal)),
        }
    }
}
impl PartialEq for MacroTraceView<'_> {
    fn eq(&self, other: &Self) -> bool { self.same_owner(*other) || self.iter().eq(other.iter()) }
}
impl Eq for MacroTraceView<'_> {}
impl fmt::Debug for MacroTraceView<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { f.debug_list().entries(self.iter()).finish() }
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pooled_singletons_keep_row_identity_and_last_detached_page_credit() {
        let fixed = dm_syntax::SettingChargeCounter::root_allocation_bytes();
        let used = dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let author = OriginalMacroAuthor::new_using("REAL", None, &a).unwrap();
        let mut pool = SingletonTracePool::default();
        let make = |at| NarrowOriginalMacroFrame {
            invocation_span: [at, at + 1], author: Arc::clone(&author),
        };
        let before = used.load(Ordering::Acquire);
        let denied = SettingAdmission::new(&used, before + SingletonTracePage::BYTES - 1, &|| Ok(()));
        assert_eq!(pool.prepare_using(&make(0), &denied).unwrap(), None);
        let fault = || Err(io::Error::from_raw_os_error(1450));
        let stopped = SettingAdmission::new(&used, 1 << 20, &fault);
        assert_eq!(pool.prepare_using(&make(0), &stopped).unwrap_err().raw_os_error(), Some(1450));
        assert_eq!(used.load(Ordering::Acquire), before);
        let frame = make(0);
        let slot = pool.prepare_using(&frame, &a).unwrap().unwrap();
        let first = pool.append(frame, slot);
        let escaped = MacroTraceView::original(&first).to_owned();
        let address = escaped.view().owner_address();
        let page = escaped.view().pooled_backing().unwrap();
        for at in 1..SINGLETON_PAGE_ROWS {
            let frame = make(at as u32);
            let slot = pool.prepare_using(&frame, &a).unwrap().unwrap();
            let next = pool.append(frame, slot);
            let next = MacroTraceView::original(&next);
            assert_eq!(next.pooled_backing(), Some(page));
            assert_ne!(next.owner_address(), address);
            assert!(!next.same_owner(escaped.view()));
        }
        let frame = make(SINGLETON_PAGE_ROWS as u32);
        let slot = pool.prepare_using(&frame, &a).unwrap().unwrap();
        let next = pool.append(frame, slot);
        assert_ne!(MacroTraceView::original(&next).pooled_backing(), Some(page));
        assert_eq!(escaped.view().owner_address(), address);
        assert_eq!(escaped.view().get(0).unwrap().invocation_span, Span::new(0, 1));
        let mut authors = 0;
        escaped.view().visit_pooled_authors(|_, _| authors += 1);
        assert_eq!(authors, 1);
        drop((pool, first, next));
        assert_eq!(used.load(Ordering::Acquire), before + SingletonTracePage::BYTES);
        drop((escaped, author));
        assert_eq!(used.load(Ordering::Acquire), fixed);
    }

    #[test]
    fn pooled_authors_match_identity_and_saturate_with_exact_dedicated_fallback() {
        let fixed = dm_syntax::SettingChargeCounter::root_allocation_bytes();
        let used = dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut pool = SingletonTracePool::default();
        let mut first = None;
        let mut first_author = None;
        for at in 0..SINGLETON_PAGE_AUTHORS {
            // Equal names still have distinct issued Arc identities.
            let author = OriginalMacroAuthor::new_using("SAME", None, &a).unwrap();
            let frame = NarrowOriginalMacroFrame { invocation_span: [2, 7], author };
            let slot = pool.prepare_using(&frame, &a).unwrap().unwrap();
            assert_eq!(slot, at);
            if at == 0 { first_author = Some(Arc::clone(&frame.author)); }
            let trace = pool.append(frame, slot);
            if at == 0 { first = Some(trace); }
        }
        let wide = NarrowOriginalMacroFrame {
            invocation_span: [2, 7],
            author: OriginalMacroAuthor::new_using("SAME", None, &a).unwrap(),
        };
        let before = used.load(Ordering::Acquire);
        let denied = SettingAdmission::new(&used, before + SingletonAuthorOverflow::BYTES - 1, &|| Ok(()));
        assert_eq!(pool.prepare_using(&wide, &denied).unwrap(), None);
        assert_eq!(used.load(Ordering::Acquire), before);
        let slot = pool.prepare_using(&wide, &a).unwrap().unwrap();
        assert_eq!(slot, SINGLETON_PAGE_AUTHORS);
        assert_eq!(used.load(Ordering::Acquire), before + SingletonAuthorOverflow::BYTES);
        let overflow_row = pool.append(NarrowOriginalMacroFrame {
            invocation_span: wide.invocation_span,
            author: Arc::clone(&wide.author),
        }, slot);
        let trace = MacroTraceView::original(&overflow_row);
        assert_eq!(trace.pooled_overflow_backing().unwrap().1, SingletonAuthorOverflow::BYTES);
        let mut authors = 0;
        trace.visit_pooled_authors(|_, _| authors += 1);
        assert_eq!(authors, SINGLETON_PAGE_AUTHORS + 1);
        let fallback_credit = a.reserve(mem::size_of::<NarrowOriginalMacroFrame>() + 2 * mem::size_of::<usize>()).unwrap();
        let dedicated = PendingOriginalSingleton::Narrow(wide).finish();
        let first = first.unwrap();
        assert_eq!(first, dedicated, "published semantics match exact fallback");
        assert!(!first.same_owner(&dedicated));
        assert!(!Arc::ptr_eq(first.frame(0).unwrap().author, dedicated.frame(0).unwrap().author));
        let reused = NarrowOriginalMacroFrame { invocation_span: [9, 13], author: first_author.take().unwrap() };
        let slot = pool.prepare_using(&reused, &a).unwrap().unwrap();
        assert_eq!(slot, 0, "full author table still accepts its existing epoch");
        let reused = pool.append(reused, slot);
        assert!(Arc::ptr_eq(first.frame(0).unwrap().author, reused.frame(0).unwrap().author));
        assert_eq!(reused.frame(0).unwrap().invocation_span, Span::new(9, 13));
        assert!(!first.same_owner(&reused));
        assert_ne!(first.owner_address(), reused.owner_address());
        #[cfg(target_pointer_width = "64")]
        assert_eq!(SingletonTracePage::BYTES, 760, "304B less than a prior 1064B page");
        // A long distinct-author tail continues to fill and then roll over
        // the page. No further optional allocation is needed until rollover.
        for at in SINGLETON_PAGE_AUTHORS + 2..SINGLETON_PAGE_ROWS {
            let frame = NarrowOriginalMacroFrame {
                invocation_span: [at as u32, at as u32 + 1],
                author: OriginalMacroAuthor::new_using("SAME", None, &a).unwrap(),
            };
            let slot = pool.prepare_using(&frame, &a).unwrap().unwrap();
            assert_eq!(slot, at - 1);
            let row = pool.append(frame, slot);
            assert_eq!(MacroTraceView::original(&row).pooled_backing(), trace.pooled_backing());
        }
        let frame = NarrowOriginalMacroFrame {
            invocation_span: [64, 65],
            author: OriginalMacroAuthor::new_using("SAME", None, &a).unwrap(),
        };
        let slot = pool.prepare_using(&frame, &a).unwrap().unwrap();
        let next = pool.append(frame, slot);
        assert_ne!(MacroTraceView::original(&next).pooled_backing(), trace.pooled_backing());
        drop((pool, first, dedicated, reused, overflow_row, next, fallback_credit));
        assert_eq!(used.load(Ordering::Acquire), fixed);
    }

    #[test]
    fn escaped_original_singleton_owns_only_the_same_inline_frame() {
        use std::sync::atomic::{Ordering};
        let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let make = || Arc::new(OriginalMacroFrame {
            invocation_span: Span::new(2, 7),
            author: OriginalMacroAuthor::new_using("POINT", Some(DefinitionOrigin {
                path: Arc::new("test.dm".into()), source_span: Span::new(3, 8), source_line: 9,
            }), &a).unwrap(),
        });
        let frame = make();
        let first = Arc::downgrade(&frame);
        let other_frame = make();
        let other = Arc::downgrade(&other_frame);
        let actual = OriginalMacroTrace::Single(frame);
        let unrelated = OriginalMacroTrace::Single(other_frame);
        let escaped = MacroTraceView::original(&actual).to_owned();
        assert_eq!(escaped.view(), MacroTraceView::original(&unrelated));
        assert!(!escaped.view().same_owner(MacroTraceView::original(&unrelated)));
        assert_eq!(escaped.view().buffers(), [
            (first.as_ptr() as usize, mem::size_of::<OriginalMacroFrame>()), (0, 0),
        ]);
        drop((actual, unrelated));
        assert!(first.upgrade().is_some());
        assert!(other.upgrade().is_none());
        assert_eq!(escaped.iter().next().unwrap().definition.unwrap().source_line, 9);
        let [(_, bytes), (_, name_bytes)] = escaped.view().author_buffers(0).unwrap();
        assert_eq!(name_bytes, "POINT".len());
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes() + (bytes + name_bytes));
        drop(escaped);
        assert!(first.upgrade().is_none());
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn narrow_singleton_exposes_its_own_stable_allocation_and_exact_wide_fallback() {
        use std::sync::atomic::{Ordering};
        let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let author = OriginalMacroAuthor::new_using("POINT", Some(DefinitionOrigin {
            path: Arc::new("narrow-actual.dm".into()), source_span: Span::new(8, 10), source_line: 9,
        }), &a).unwrap();
        let expected_path = Arc::clone(&author.origin().unwrap().path);
        let make = |span| PendingOriginalSingleton::from_frame(OriginalMacroFrame {
            invocation_span: span, author: Arc::clone(&author),
        });
        let last = u32::MAX as usize;
        let span = Span::new(last - 1, last);
        let pending = make(span);
        #[cfg(target_pointer_width = "64")]
        {
            assert!(matches!(&pending, PendingOriginalSingleton::Narrow(_)));
            assert_eq!(pending.bytes(), 16);
            assert_eq!(mem::size_of::<OriginalMacroTrace>(), 16);
        }
        let size = pending.bytes();
        let trace = pending.finish();
        let view = MacroTraceView::original(&trace);
        let duplicate = make(span).finish();
        assert_eq!(view, MacroTraceView::original(&duplicate));
        assert_ne!(view.owner_address(), MacroTraceView::original(&duplicate).owner_address());
        assert!(!view.same_owner(MacroTraceView::original(&duplicate)));
        assert_eq!(view.buffers(), [(view.owner_address(), size), (0, 0)]);
        assert_eq!(view.get(0).unwrap().invocation_span, span);
        assert!(view.get(0).unwrap().replacement_chain.is_empty());
        assert!(view.get(1).is_none());
        assert!(Arc::ptr_eq(&view.get(0).unwrap().definition.unwrap().path, &expected_path));
        let escaped = view.to_owned();
        let pointer = view.owner_address();
        assert!(escaped.view().same_owner(view));

        #[cfg(target_pointer_width = "64")]
        {
            let wide_span = Span::new(last + 1, usize::MAX);
            let pending = make(wide_span);
            assert!(matches!(&pending, PendingOriginalSingleton::Wide(_)));
            assert_eq!(pending.bytes(), 24);
            let wide = pending.finish();
            assert_eq!(MacroTraceView::original(&wide).get(0).unwrap().invocation_span, wide_span);
            assert!(!escaped.view().same_owner(MacroTraceView::original(&wide)));
        }
        drop((trace, duplicate, author));
        assert_eq!(escaped.view().owner_address(), pointer);
        assert_eq!(escaped.view().get(0).unwrap().invocation_span, span);
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes() + (OriginalMacroAuthor::BYTES + "POINT".len()));
        drop(escaped);
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn original_prefix_projection_matches_native_content_without_copying_the_owner() {
        let outer: Arc<str> = Arc::from("OUTER");
        let inner: Arc<str> = Arc::from("INNER");
        let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let original = OriginalMacroTrace::Shared(Arc::new(Box::new([
            OriginalMacroFrame { invocation_span: Span::new(0, 5), author: OriginalMacroAuthor::new_using(&outer, None, &a).unwrap() },
            OriginalMacroFrame { invocation_span: Span::new(3, 7), author: OriginalMacroAuthor::new_using(&inner, None, &a).unwrap() },
        ])));
        let native: Arc<Box<[MacroExpansion]>> = Arc::new(Box::new([
            MacroExpansion { name: outer.clone(), invocation_span: Span::new(0, 5), definition: None, replacement_chain: Arc::from([]) },
            MacroExpansion { name: inner, invocation_span: Span::new(3, 7), definition: None, replacement_chain: Arc::from([outer]) },
        ]));
        let view = MacroTraceView::original(&original);
        assert_eq!(view, MacroTraceView::from(&native));
        assert!(!view.same_owner((&native).into()));
        let child = view.get(1).unwrap();
        assert!(child.replacement_chain.native_owner().is_none());
        assert!(std::ptr::eq(child.replacement_chain.get(0).unwrap(), view.get(0).unwrap().name));
        let retained = view.to_owned();
        assert!(retained.view().same_owner(view));
        let [_, (_, row_bytes)] = retained.view().buffers();
        assert_eq!(row_bytes, original.len() * mem::size_of::<OriginalMacroFrame>());
        assert_eq!(mem::size_of::<OriginalMacroFrame>(), mem::size_of::<Span>() + mem::size_of::<Arc<OriginalMacroAuthor>>());
        assert!(mem::size_of::<OriginalMacroFrame>() < mem::size_of::<(Span, Arc<str>, Option<Arc<OriginalMacroAuthor>>)>());
        assert!(retained.view().get(0).unwrap().definition.is_none());
        assert!(retained.view().author_buffers(0).is_some());
        drop(original);
        assert_eq!(retained.view(), MacroTraceView::from(&native));
    }
}
