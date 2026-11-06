//! One immutable trace projection. Original parent chains are exact prefixes
//! of the same issued frame array, while native traces keep authored chains.
use super::{DefinitionOrigin, MacroExpansion};
use dm_syntax::{SettingAdmission, SettingRootLease, Span};
use std::{fmt, io, mem, sync::Arc};

/// Actual authored definition metadata, shared by its one binding epoch and
/// projected trace frames. The lease follows detached diagnostic/point aliases.
pub(super) struct OriginalProjectedDefinition {
    origin: DefinitionOrigin,
    credit: SettingRootLease,
}
impl OriginalProjectedDefinition {
    const BYTES: usize = mem::size_of::<Self>() + 2 * mem::size_of::<usize>();

    pub(super) fn new_using(origin: DefinitionOrigin, a: &SettingAdmission<'_>) -> io::Result<Arc<Self>> {
        let credit = a.reserve(Self::BYTES).map_err(|error| a.take_operational_error().unwrap_or(error))?;
        Ok(Arc::new(Self { origin, credit }))
    }

    pub(super) fn matches(&self, actual: &DefinitionOrigin, a: &SettingAdmission<'_>) -> bool {
        a.matches_lease_domain(&self.credit)
            && Arc::ptr_eq(&self.origin.path, &actual.path)
            && self.origin.source_span == actual.source_span
            && self.origin.source_line == actual.source_line
    }

    pub(super) fn origin(&self) -> &DefinitionOrigin { &self.origin }

    pub(super) fn buffer(&self) -> (usize, usize) {
        (std::ptr::from_ref(self) as usize, Self::BYTES)
    }
}
impl std::ops::Deref for OriginalProjectedDefinition {
    type Target = DefinitionOrigin;
    fn deref(&self) -> &DefinitionOrigin { &self.origin }
}
impl PartialEq for OriginalProjectedDefinition {
    fn eq(&self, other: &Self) -> bool { self.origin == other.origin }
}
impl Eq for OriginalProjectedDefinition {}
impl fmt::Debug for OriginalProjectedDefinition {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { fmt::Debug::fmt(&self.origin, f) }
}

#[derive(Debug, Eq, PartialEq)]
pub(super) struct OriginalMacroFrame {
    pub(super) name: Arc<str>,
    pub(super) invocation_span: Span,
    pub(super) definition: Option<Arc<OriginalProjectedDefinition>>,
}

/// A point owns its exact projected trace. A singleton needs only a normal
/// Arc allocation around the actual frame, with no secondary boxed array.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) enum OriginalMacroTrace {
    Single(Arc<OriginalMacroFrame>),
    Shared(Arc<Box<[OriginalMacroFrame]>>),
}
impl OriginalMacroTrace {
    pub(super) fn empty() -> Self { Self::Shared(Arc::new(Box::new([]))) }

    pub(super) fn same_owner(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Single(a), Self::Single(b)) => Arc::ptr_eq(a, b),
            (Self::Shared(a), Self::Shared(b)) => Arc::ptr_eq(a, b),
            _ => false,
        }
    }

    fn owner_address(&self) -> usize {
        match self {
            Self::Single(rows) => Arc::as_ptr(rows) as usize,
            Self::Shared(rows) => Arc::as_ptr(rows) as usize,
        }
    }

    fn buffers(&self) -> [(usize, usize); 2] {
        match self {
            Self::Single(_) => [(self.owner_address(), mem::size_of::<OriginalMacroFrame>()), (0, 0)],
            Self::Shared(rows) => [
                (self.owner_address(), mem::size_of::<Box<[OriginalMacroFrame]>>()),
                (rows.as_ptr() as usize, mem::size_of_val(rows.as_ref().as_ref())),
            ],
        }
    }

    #[cfg(test)]
    pub(super) fn strong_count(&self) -> usize {
        match self {
            Self::Single(rows) => Arc::strong_count(rows),
            Self::Shared(rows) => Arc::strong_count(rows),
        }
    }
}
impl std::ops::Deref for OriginalMacroTrace {
    type Target = [OriginalMacroFrame];
    fn deref(&self) -> &Self::Target {
        match self {
            Self::Single(row) => std::slice::from_ref(row.as_ref()),
            Self::Shared(rows) => rows.as_ref().as_ref(),
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
}

#[derive(Clone, Copy)]
pub struct MacroTraceParents<'a>(Parents<'a>);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct MacroExpansionView<'a> {
    pub name: &'a Arc<str>,
    pub invocation_span: Span,
    pub replacement_chain: MacroTraceParents<'a>,
    pub definition: Option<&'a DefinitionOrigin>,
}

impl<'a> MacroTraceParents<'a> {
    pub fn len(self) -> usize {
        match self.0 { Parents::Native(rows) => rows.len(), Parents::Original(rows) => rows.len() }
    }

    pub fn is_empty(self) -> bool { self.len() == 0 }

    pub fn get(self, ordinal: usize) -> Option<&'a Arc<str>> {
        match self.0 {
            Parents::Native(rows) => rows.get(ordinal),
            Parents::Original(rows) => rows.get(ordinal).map(|row| &row.name),
        }
    }

    pub fn iter(self) -> impl ExactSizeIterator<Item = &'a Arc<str>> + DoubleEndedIterator {
        (0..self.len()).map(move |i| self.get(i).expect("issued trace parent"))
    }

    /// Physical independent slice only. Original prefixes borrow the
    /// already-accounted trace frame storage, and do not own any array.
    pub fn native_owner(self) -> Option<&'a Arc<[Arc<str>]>> {
        match self.0 { Parents::Native(rows) => Some(rows), Parents::Original(_) => None }
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
                let row = rows.get(at)?;
                MacroExpansionView {
                    name: &row.name, invocation_span: row.invocation_span,
                    definition: row.definition.as_deref().map(OriginalProjectedDefinition::origin),
                    replacement_chain: MacroTraceParents(Parents::Original(&rows[..at])),
                }
            }
        })
    }
    pub fn iter(self) -> impl ExactSizeIterator<Item = MacroExpansionView<'a>> + DoubleEndedIterator {
        (0..self.len()).map(move |i| self.get(i).expect("issued trace frame"))
    }
    /// Actual separate definition allocation, including its Arc control.
    /// Native frames still keep definition data inline. Repeated Original
    /// aliases have the same address for retained-heap deduplication.
    pub fn definition_buffer(self, at: usize) -> Option<(usize, usize)> {
        match self.0 {
            Borrowed::Native(_) => None,
            Borrowed::Original(rows) => Some(rows.get(at)?.definition.as_ref()?.buffer()),
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
            name: Arc::from("POINT"), invocation_span: Span::new(2, 7),
            definition: Some(OriginalProjectedDefinition::new_using(DefinitionOrigin {
                path: Arc::new("test.dm".into()), source_span: Span::new(3, 8), source_line: 9,
            }, &a).unwrap()),
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
        let (_, bytes) = escaped.view().definition_buffer(0).unwrap();
        assert_eq!(used.load(Ordering::Acquire), bytes);
        drop(escaped);
        assert!(first.upgrade().is_none());
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn original_prefix_projection_matches_native_content_without_copying_the_owner() {
        let outer: Arc<str> = Arc::from("OUTER");
        let inner: Arc<str> = Arc::from("INNER");
        let original = OriginalMacroTrace::Shared(Arc::new(Box::new([
            OriginalMacroFrame { name: outer.clone(), invocation_span: Span::new(0, 5), definition: None },
            OriginalMacroFrame { name: inner.clone(), invocation_span: Span::new(3, 7), definition: None },
        ])));
        let native: Arc<Box<[MacroExpansion]>> = Arc::new(Box::new([
            MacroExpansion { name: outer, invocation_span: Span::new(0, 5), definition: None, replacement_chain: Arc::from([]) },
            MacroExpansion { name: inner, invocation_span: Span::new(3, 7), definition: None, replacement_chain: Arc::from([original[0].name.clone()]) },
        ]));
        let view = MacroTraceView::original(&original);
        assert_eq!(view, MacroTraceView::from(&native));
        assert!(!view.same_owner((&native).into()));
        let child = view.get(1).unwrap();
        assert!(child.replacement_chain.native_owner().is_none());
        assert!(Arc::ptr_eq(child.replacement_chain.get(0).unwrap(), view.get(0).unwrap().name));
        let retained = view.to_owned();
        assert!(retained.view().same_owner(view));
        let [_, (_, row_bytes)] = retained.view().buffers();
        assert_eq!(row_bytes, original.len() * mem::size_of::<OriginalMacroFrame>());
        assert_eq!(mem::size_of::<MacroExpansion>() - mem::size_of::<OriginalMacroFrame>(),
            mem::size_of::<Arc<[Arc<str>]>>() + mem::size_of::<Option<DefinitionOrigin>>()
                - mem::size_of::<Option<Arc<OriginalProjectedDefinition>>>());
        drop(original);
        assert_eq!(retained.view(), MacroTraceView::from(&native));
    }
}
