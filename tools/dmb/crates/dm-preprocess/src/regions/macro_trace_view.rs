//! One immutable trace projection. Original parent chains are exact prefixes
//! of the same issued frame array, while native traces keep authored chains.
use super::{DefinitionOrigin, MacroExpansion};
use dm_syntax::{SettingAdmission, SettingRootLease, Span};
use std::{fmt, io, mem, sync::Arc};

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

    pub(super) fn new_using(name: &str, origin: Option<DefinitionOrigin>, a: &SettingAdmission<'_>) -> io::Result<Arc<Self>> {
        let name_bytes = name.len();
        let bytes = Self::BYTES.checked_add(name_bytes).ok_or(io::ErrorKind::OutOfMemory)?;
        let credit = a.reserve(bytes).map_err(|error| a.take_operational_error().unwrap_or(error))?;
        let name = Box::from(name);
        Ok(Arc::new(Self { name, origin, credit }))
    }

    pub(super) fn matches(&self, name: &str, actual: &DefinitionOrigin, a: &SettingAdmission<'_>) -> bool {
        a.matches_lease_domain(&self.credit) && self.name.as_ref() == name
            && self.origin.as_ref().is_some_and(|origin| {
                Arc::ptr_eq(&origin.path, &actual.path)
                    && origin.source_span == actual.source_span
                    && origin.source_line == actual.source_line
            })
    }

    pub(super) fn name(&self) -> &str { &self.name }
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

/// A point owns one exact projected trace allocation. Narrow singletons
/// retain only their own author, with lossless wide and multi-frame fallbacks.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) enum OriginalMacroTrace {
    Single(Arc<OriginalMacroFrame>),
    NarrowSingle(Arc<NarrowOriginalMacroFrame>),
    Shared(Arc<Box<[OriginalMacroFrame]>>),
    NarrowShared(Arc<Box<[NarrowOriginalMacroFrame]>>),
}
impl OriginalMacroTrace {
    pub(super) fn empty() -> Self { Self::Shared(Arc::new(Box::new([]))) }

    pub(super) fn same_owner(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Single(a), Self::Single(b)) => Arc::ptr_eq(a, b),
            (Self::NarrowSingle(a), Self::NarrowSingle(b)) => Arc::ptr_eq(a, b),
            (Self::Shared(a), Self::Shared(b)) => Arc::ptr_eq(a, b),
            (Self::NarrowShared(a), Self::NarrowShared(b)) => Arc::ptr_eq(a, b),
            _ => false,
        }
    }

    fn owner_address(&self) -> usize {
        match self {
            Self::Single(rows) => Arc::as_ptr(rows) as usize,
            Self::NarrowSingle(rows) => Arc::as_ptr(rows) as usize,
            Self::Shared(rows) => Arc::as_ptr(rows) as usize,
            Self::NarrowShared(rows) => Arc::as_ptr(rows) as usize,
        }
    }

    fn buffers(&self) -> [(usize, usize); 2] {
        match self {
            Self::Single(_) => [(self.owner_address(), mem::size_of::<OriginalMacroFrame>()), (0, 0)],
            Self::NarrowSingle(_) => [(self.owner_address(), mem::size_of::<NarrowOriginalMacroFrame>()), (0, 0)],
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
    pub(super) fn original(rows: &'a OriginalMacroTrace) -> Self { Self(Borrowed::Original(rows)) }

    pub fn to_owned(self) -> MacroTrace {
        match self.0 {
            Borrowed::Native(rows) => MacroTrace(Owned::Native(Arc::clone(rows))),
            Borrowed::Original(rows) => MacroTrace(Owned::Original(rows.clone())),
        }
    }
    pub fn native_owner(self) -> Option<&'a Arc<Box<[MacroExpansion]>>> {
        match self.0 { Borrowed::Native(rows) => Some(rows), Borrowed::Original(_) => None }
    }
    pub fn owner_address(self) -> usize {
        match self.0 {
            Borrowed::Native(rows) => Arc::as_ptr(rows) as usize,
            Borrowed::Original(rows) => rows.owner_address(),
        }
    }
    pub fn same_owner(self, other: Self) -> bool {
        match (self.0, other.0) {
            (Borrowed::Native(a), Borrowed::Native(b)) => Arc::ptr_eq(a,b),
            (Borrowed::Original(a), Borrowed::Original(b)) => a.same_owner(b),
            _ => false,
        }
    }
    pub fn len(self) -> usize {
        match self.0 { Borrowed::Native(rows) => rows.len(), Borrowed::Original(rows) => rows.len() }
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
    fn escaped_original_singleton_owns_only_the_same_inline_frame() {
        use std::sync::atomic::{AtomicUsize, Ordering};
        let used = Arc::new(AtomicUsize::new(0));
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
        assert_eq!(used.load(Ordering::Acquire), bytes + name_bytes);
        drop(escaped);
        assert!(first.upgrade().is_none());
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn narrow_singleton_exposes_its_own_stable_allocation_and_exact_wide_fallback() {
        use std::sync::atomic::{AtomicUsize, Ordering};
        let used = Arc::new(AtomicUsize::new(0));
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
        assert_eq!(used.load(Ordering::Acquire), OriginalMacroAuthor::BYTES + "POINT".len());
        drop(escaped);
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn original_prefix_projection_matches_native_content_without_copying_the_owner() {
        let outer: Arc<str> = Arc::from("OUTER");
        let inner: Arc<str> = Arc::from("INNER");
        let used = Arc::new(std::sync::atomic::AtomicUsize::new(0));
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
