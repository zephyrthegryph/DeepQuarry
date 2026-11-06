//! Committed rows from the actual Original primary frame machine.
//! Offsets are DATA. The emitted source owner and its source/model receipt
//! remain with the caller that binds the completed primary product.
use super::{Item, ItemKind, Span, original_storage::Storage};
use crate::SettingRootLease;
use std::{io, mem::size_of, ops::Range};

pub(super) const ROOT_ITEM_BLOCK: usize = 256;
const MAX_BLOCK_ROWS: usize = 8192;
const MAX_HEADER_BYTES: usize = 2 * 1024 * 1024;

fn overflow() -> io::Error { io::ErrorKind::OutOfMemory.into() }

#[repr(C)]
struct CompactItem {
    span: [u32; 2],
    header: [u32; 2],
    cursor: u32,
    indent: u32,
    children: [u32; 2],
    kind: ItemKind,
    qualifiers: u8,
    outer: Option<bool>,
    empty_header: bool,
}
const _: () = assert!(size_of::<CompactItem>() == 36);

impl CompactItem {
    fn geometry(item: &Item, source: &str) -> Option<Self> {
        let bounds = |span: Span| Some([u32::try_from(span.start).ok()?, u32::try_from(span.end).ok()?]);
        if source.get(item.span.range()).is_none()
            || source.get(item.header_span.range()).is_none_or(|header| !item.header.is_empty() && header != item.header)
        {
            return None;
        }
        let cursor = match item.declaration_cursor {
            None => u32::MAX,
            Some(cursor) => u32::try_from(cursor).ok().filter(|at| *at < u32::MAX)?,
        };
        Some(Self {
            span: bounds(item.span)?,
            header: bounds(item.header_span)?,
            cursor,
            indent: u32::try_from(item.indent).ok()?,
            children: [0, 0],
            kind: item.kind,
            qualifiers: item.checker_qualifiers,
            outer: item.original_outer_terminator,
            empty_header: item.header.is_empty(),
        })
    }

    fn span_of([start, end]: [u32; 2]) -> Span {
        Span::new(start as usize, end as usize)
    }
}

enum Block {
    Compact { rows: Vec<CompactItem>, roots: usize },
    Wide(Vec<Item>),
}

#[derive(Default)]
pub(super) struct PendingCommittedItems {
    blocks: Vec<Block>,
    roots: usize,
}

impl PendingCommittedItems {
    pub(super) fn push(&mut self, items: Vec<Item>, source: &str, storage: &Storage<'_, '_>) -> io::Result<()> {
        if items.is_empty() || items.len() > ROOT_ITEM_BLOCK || self.roots % ROOT_ITEM_BLOCK != 0 {
            return Err(io::ErrorKind::InvalidData.into());
        }
        let roots = self.roots.checked_add(items.len()).ok_or_else(overflow)?;
        let block = compact_block(items, source, storage)?;
        if !storage.push(&mut self.blocks, block) {
            return Err(storage.take_failure().unwrap_or_else(overflow));
        }
        self.roots = roots;
        Ok(())
    }

    pub(super) fn bytes(&self, storage: &Storage<'_, '_>) -> Option<usize> {
        self.blocks.iter().try_fold(self.blocks.capacity().checked_mul(size_of::<Block>())?, |bytes, block| {
            let buffer = match block {
                Block::Compact { rows, .. } => rows.capacity().checked_mul(size_of::<CompactItem>()),
                Block::Wide(items) => storage.item_bytes(items),
            }?;
            bytes.checked_add(buffer)
        })
    }

    pub(super) fn finish(self, source_extent: usize, lease: SettingRootLease) -> OriginalCommittedItems {
        OriginalCommittedItems { data: self, source_extent, _lease: lease }
    }

    #[cfg(debug_assertions)]
    pub(super) fn trace_compact(&self) -> (usize, usize, usize, usize) {
        let mut blocks = 0usize;
        let mut rows = 0usize;
        let mut bytes = 0usize;
        for block in &self.blocks {
            if let Block::Compact { rows: packed, .. } = block {
                blocks += 1;
                rows = rows.saturating_add(packed.len());
                bytes = bytes.saturating_add(packed.capacity().saturating_mul(size_of::<CompactItem>()));
            }
        }
        (blocks, rows, bytes, self.blocks.capacity().saturating_mul(size_of::<Block>()))
    }
}

fn compact_block(items: Vec<Item>, source: &str, storage: &Storage<'_, '_>) -> io::Result<Block> {
    #[derive(Default)]
    struct ExactShape { rows: usize, old_bytes: usize, header_bytes: usize }
    fn inspect(items: &Vec<Item>, source: &str, shape: &mut ExactShape) -> Option<()> {
        shape.rows = shape.rows.checked_add(items.len())?;
        if shape.rows > MAX_BLOCK_ROWS { return None; }
        shape.old_bytes = shape.old_bytes.checked_add(items.capacity().checked_mul(size_of::<Item>())?)?;
        for item in items {
            shape.header_bytes = shape.header_bytes.checked_add(item.header.capacity())?;
            if shape.header_bytes > MAX_HEADER_BYTES { return None; }
            shape.old_bytes = shape.old_bytes.checked_add(item.header.capacity())?;
            CompactItem::geometry(item, source)?;
            // Depth is bounded by the actual admitted primary frame machine.
            inspect(&item.children, source, shape)?;
        }
        Some(())
    }
    fn append(items: &[Item], source: &str, packed: &mut Vec<CompactItem>) -> [u32; 2] {
        let start = packed.len();
        packed.extend(items.iter().map(|item| CompactItem::geometry(item, source).expect("checked original item geometry")));
        let end = packed.len();
        for (i, item) in items.iter().enumerate() {
            let children = append(&item.children, source, packed);
            packed[start + i].children = children;
        }
        [start as u32, end as u32] // Preflight bounds every ordinal.
    }

    let mut shape = ExactShape::default();
    if inspect(&items, source, &mut shape).is_none() {
        return Ok(Block::Wide(items));
    }
    let Some((mut packed, mut credit)) = storage.try_item_block_vector::<CompactItem>(shape.rows)? else {
        return Ok(Block::Wide(items));
    };
    let [_, roots] = append(&items, source, &mut packed);
    debug_assert_eq!(packed.len(), shape.rows);
    storage.adopt_item_block_credit(&mut credit)?;
    drop(items);
    storage.release_item_block_bytes(shape.old_bytes)?;
    Ok(Block::Compact { rows: packed, roots: roots as usize })
}

/// Owned original rows and their exact separate resource lease. No duplicate
/// Item tree, parser/cache, raw-file owner or semantic authority survives here.
pub struct OriginalCommittedItems {
    data: PendingCommittedItems,
    source_extent: usize,
    _lease: SettingRootLease,
}

impl OriginalCommittedItems {
    pub fn view<'a>(&'a self, source: &'a str) -> io::Result<OriginalItems<'a>> {
        if source.len() != self.source_extent
            || self.data.blocks.iter().any(|block| match block {
                Block::Compact { rows, .. } => rows.iter().any(|row| !row.empty_header
                    && source.get(CompactItem::span_of(row.header).range()).is_none()),
                Block::Wide(_) => false,
            })
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "committed rows differ from current source extent or UTF-8 boundaries"));
        }
        self.view_for_same_source(source)
    }

    /// Constant-time DATA view for a holder that already authenticated the
    /// SAME immutable emitted source and kept that owner alive. Extent and
    /// per-item UTF-8 boundaries are still checked; these checks never grant
    /// source authority by text, length, or address equality.
    pub fn view_for_same_source<'a>(&'a self, source: &'a str) -> io::Result<OriginalItems<'a>> {
        if source.len() != self.source_extent { return Err(io::ErrorKind::InvalidInput.into()); }
        Ok(OriginalItems(Siblings::Blocks { blocks: &self.data.blocks, count: self.data.roots, source }))
    }

    pub fn len(&self) -> usize { self.data.roots }
    pub fn is_empty(&self) -> bool { self.len() == 0 }
    pub fn admitted_by(&self, a: &crate::SettingAdmission<'_>) -> bool { a.matches_lease_domain(&self._lease) }

    pub fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        fn buffer<T>(rows: &Vec<T>, visit: &mut impl FnMut(usize, usize, usize)) {
            if rows.capacity() != 0 {
                visit(rows.as_ptr() as usize, rows.len() * size_of::<T>(), rows.capacity() * size_of::<T>());
            }
        }
        fn wide(rows: &Vec<Item>, visit: &mut impl FnMut(usize, usize, usize)) {
            buffer(rows, visit);
            for row in rows {
                if row.header.capacity() != 0 {
                    visit(row.header.as_ptr() as usize, row.header.len(), row.header.capacity());
                }
                wide(&row.children, visit);
            }
        }
        buffer(&self.data.blocks, &mut visit);
        for block in &self.data.blocks {
            match block {
                Block::Compact { rows, .. } => buffer(rows, &mut visit),
                Block::Wide(rows) => wide(rows, &mut visit),
            }
        }
        self._lease.visit_counter_storage(|address, bytes| {
            let bytes = bytes + 2 * size_of::<usize>();
            visit(address, bytes, bytes);
        });
    }
}

impl std::fmt::Debug for OriginalCommittedItems {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("OriginalCommittedItems")
            .field("roots", &self.data.roots)
            .field("blocks", &self.data.blocks.len())
            .field("source_extent", &self.source_extent)
            .field("retained_buffer_bytes", &self._lease.bytes())
            .finish()
    }
}

#[derive(Clone, Copy)]
enum Siblings<'a> {
    Wide(&'a [Item]),
    Compact { rows: &'a [CompactItem], interval: [u32; 2], source: &'a str },
    Blocks { blocks: &'a [Block], count: usize, source: &'a str },
}

/// Borrowed sibling order over the existing same-source production data.
/// Constructing a view does not authorize a source/acquisition/model join.
#[derive(Clone, Copy)]
pub struct OriginalItems<'a>(Siblings<'a>);

impl<'a> OriginalItems<'a> {
    pub fn from_items(items: &'a [Item]) -> Self { Self(Siblings::Wide(items)) }
    pub fn len(self) -> usize {
        match self.0 {
            Siblings::Wide(items) => items.len(),
            Siblings::Compact { interval: [first, last], .. } => (last - first) as usize,
            Siblings::Blocks { count, .. } => count,
        }
    }
    pub fn is_empty(self) -> bool { self.len() == 0 }

    pub fn same_interval(self, other: Self) -> bool {
        match (self.0, other.0) {
            (Siblings::Wide(a), Siblings::Wide(b)) => std::ptr::eq(a, b),
            (Siblings::Compact { rows: a, interval: x, source: s },
             Siblings::Compact { rows: b, interval: y, source: t }) => x == y && std::ptr::eq(a, b) && std::ptr::eq(s, t),
            (Siblings::Blocks { blocks: a, count: x, source: s },
             Siblings::Blocks { blocks: b, count: y, source: t }) => x == y && std::ptr::eq(a, b) && std::ptr::eq(s, t),
            _ => false,
        }
    }

    pub fn get(self, index: usize) -> Option<OriginalItem<'a>> {
        if index >= self.len() { return None; }
        match self.0 {
            Siblings::Wide(items) => Some(OriginalItem(ItemView::Wide(items.get(index)?))),
            Siblings::Compact { rows, interval, source } => {
                let row = rows.get(interval[0] as usize + index)?;
                let header = if row.empty_header { "" } else { source.get(CompactItem::span_of(row.header).range())? };
                Some(OriginalItem(ItemView::Compact { row, rows, source, header }))
            }
            Siblings::Blocks { blocks, source, .. } => {
                let block = blocks.get(index / ROOT_ITEM_BLOCK)?;
                let local = index % ROOT_ITEM_BLOCK;
                match block {
                    Block::Wide(items) => Self::from_items(items).get(local),
                    Block::Compact { rows, roots } => {
                        Self(Siblings::Compact { rows, interval: [0, *roots as u32], source }).get(local)
                    }
                }
            }
        }
    }

    pub fn iter(self) -> impl ExactSizeIterator<Item=OriginalItem<'a>> + DoubleEndedIterator {
        (0..self.len()).map(move |index| self.get(index).expect("issued sibling ordinal"))
    }
}

#[derive(Clone, Copy)]
enum ItemView<'a> {
    Wide(&'a Item),
    Compact { row: &'a CompactItem, rows: &'a [CompactItem], source: &'a str, header: &'a str },
}

#[derive(Clone, Copy)]
pub struct OriginalItem<'a>(ItemView<'a>);

impl<'a> OriginalItem<'a> {
    pub fn kind(self) -> ItemKind { match self.0 { ItemView::Wide(i) => i.kind, ItemView::Compact { row, .. } => row.kind } }
    pub fn header(self) -> &'a str {
        match self.0 {
            ItemView::Wide(item) => &item.header,
            ItemView::Compact { header, .. } => header,
        }
    }
    pub fn same_item(self, other: Self) -> bool {
        match (self.0, other.0) {
            (ItemView::Wide(a), ItemView::Wide(b)) => std::ptr::eq(a, b),
            (ItemView::Compact { row: a, source: s, .. }, ItemView::Compact { row: b, source: t, .. }) =>
                std::ptr::eq(a, b) && std::ptr::eq(s, t),
            _ => false,
        }
    }
    pub fn span(self) -> Span { match self.0 { ItemView::Wide(i) => i.span, ItemView::Compact { row, .. } => CompactItem::span_of(row.span) } }
    pub fn header_span(self) -> Span { match self.0 { ItemView::Wide(i) => i.header_span, ItemView::Compact { row, .. } => CompactItem::span_of(row.header) } }
    pub fn declaration_cursor(self) -> Option<usize> {
        match self.0 {
            ItemView::Wide(i) => i.declaration_cursor,
            ItemView::Compact { row, .. } => (row.cursor != u32::MAX).then_some(row.cursor as usize),
        }
    }
    pub fn checker_qualifiers(self) -> u8 { match self.0 { ItemView::Wide(i) => i.checker_qualifiers, ItemView::Compact { row, .. } => row.qualifiers } }
    pub fn original_outer_terminator(self) -> Option<bool> { match self.0 { ItemView::Wide(i) => i.original_outer_terminator, ItemView::Compact { row, .. } => row.outer } }
    pub fn indent(self) -> usize { match self.0 { ItemView::Wide(i) => i.indent, ItemView::Compact { row, .. } => row.indent as usize } }
    pub fn children(self) -> OriginalItems<'a> {
        match self.0 {
            ItemView::Wide(i) => OriginalItems::from_items(&i.children),
            ItemView::Compact { row, rows, source, .. } => OriginalItems(Siblings::Compact { rows, interval: row.children, source }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{NativeTokenCursor, NativeTokenStep, OriginalPrimaryDemand, SettingAdmission};
    use std::{fmt::Write, sync::{Arc, atomic::{AtomicUsize, Ordering}}};

    fn feed<'s>(primary: &mut OriginalPrimaryDemand<'_, '_, '_>, source: &'s str,
                admission: &SettingAdmission<'_>) -> (&'s str, bool) {
        let mut cursor = NativeTokenCursor::default();
        let mut end = 0usize;
        for line in source.split_inclusive('\n') {
            end += line.len();
            let actual = &source[..end];
            let eof = end == source.len();
            loop {
                match cursor.next_available_using(actual, eof, admission, |_, _, _| true).unwrap() {
                    NativeTokenStep::Token(token) => primary.token(token).unwrap(),
                    NativeTokenStep::NeedInput | NativeTokenStep::End => break,
                    NativeTokenStep::Stopped => panic!("no lexer stop in this source"),
                }
            }
            if !primary.advance(actual, eof).unwrap() {
                return (actual, eof);
            }
        }
        (source, true)
    }

    fn compare(actual: OriginalItems<'_>, expected: &[Item], source: &str) {
        assert_eq!(actual.len(), expected.len());
        for (view, row) in actual.iter().zip(expected) {
            assert_eq!(view.kind(), row.kind);
            assert_eq!(view.span(), row.span);
            assert_eq!(view.header_span(), row.header_span);
            assert_eq!(view.declaration_cursor(), row.declaration_cursor);
            assert_eq!(view.checker_qualifiers(), row.checker_qualifiers);
            assert_eq!(view.original_outer_terminator(), row.original_outer_terminator);
            assert_eq!(view.indent(), row.indent);
            assert_eq!(view.header(), row.header);
            if !view.header().is_empty() {
                assert_eq!(view.header().as_ptr(), source[view.header_span().range()].as_ptr());
            }
            compare(view.children(), &row.children, source);
        }
    }

    #[test]
    fn actual_committed_primary_keeps_sealed_blocks_and_exact_fatal_prefix_without_dense_rebuild() {
        for fatal in [false, true] {
            let mut source = String::new();
            for index in 0..ROOT_ITEM_BLOCK*2+3 {
                writeln!(&mut source, "/datum/root_{index}\n    var/name = \"é{index}\"").unwrap();
            }
            if fatal {
                source.push_str("/datum/stop\n    var/first,second\n/proc/future()\n    return 2\n");
            }
            let dense_used = Arc::new(AtomicUsize::new(0));
            let compact_used = Arc::new(AtomicUsize::new(0));
            let old = SettingAdmission::new(&dense_used, 8<<20, &|| Ok(()));
            let new = SettingAdmission::new(&compact_used, 8<<20, &|| Ok(()));
            let mut dense = OriginalPrimaryDemand::new(&old, None).unwrap();
            let mut compact = OriginalPrimaryDemand::new_committed(&new, None).unwrap();
            let (old_source, old_eof) = feed(&mut dense, &source, &old);
            let (actual, actual_eof) = feed(&mut compact, &source, &new);
            assert_eq!((actual, actual_eof), (old_source, old_eof));
            assert_eq!(actual_eof, !fatal);
            let dense = dense.finish(old_source, old_eof).unwrap();
            let compact = compact.finish_committed(actual, actual_eof).unwrap();
            assert_eq!(compact.fatal().map(|f| f.token_span()), dense.fatal().map(|f| f.token_span()));
            assert_eq!(compact.diagnostics(), dense.syntax().diagnostics.as_slice());
            assert!(compact.tokens().window().iter().eq(dense.syntax().tokens.window().iter()));
            let items = compact.items(actual).unwrap();
            assert!(items.same_interval(compact.items(actual).unwrap()));
            let foreign = actual.to_owned();
            // A matching string is DATA only; it is not the same view.
            assert!(!items.same_interval(compact.items(&foreign).unwrap()));
            assert!(items.get(ROOT_ITEM_BLOCK).unwrap().same_item(compact.items(actual).unwrap().get(ROOT_ITEM_BLOCK).unwrap()));
            assert!(!items.get(ROOT_ITEM_BLOCK).unwrap().same_item(items.get(ROOT_ITEM_BLOCK+1).unwrap()));
            compare(items, &dense.syntax().items, actual);
            let (forest, tokens, diagnostics, _, _, diagnostic_lease) = compact.into_parts();
            assert!(forest.data.blocks.iter().all(|block| matches!(block, Block::Compact { .. })));
            assert!(forest.data.blocks.len() >= 3);
            assert!(compact_used.load(Ordering::Acquire) + 20_000 < dense_used.load(Ordering::Acquire));
            drop((tokens, diagnostics, diagnostic_lease));
            assert_eq!(compact_used.load(Ordering::Acquire), forest._lease.bytes());
            drop((forest, dense));
            assert_eq!(compact_used.load(Ordering::Acquire), 0);
            assert_eq!(dense_used.load(Ordering::Acquire), 0);
        }
    }

    #[test]
    fn committed_block_falls_back_for_distinct_spelling_and_unavailable_overlap() {
        for altered in [false, true] {
            let source = "/datum/p";
            let used = Arc::new(AtomicUsize::new(0));
            let retained = 4096 + 4*size_of::<Item>() + source.len();
            let limit = if altered { 1<<20 } else { retained + size_of::<CompactItem>() - 1 };
            let admission = SettingAdmission::new(&used, limit, &|| Ok(()));
            let storage = Storage::new(&admission).unwrap();
            let mut rows = Vec::new();
            let header = storage.text(if altered { "/datum/q" } else { source }).unwrap();
            let backing = header.as_ptr();
            let span = Span::new(0, source.len());
            assert!(storage.push(&mut rows, Item {
                kind: ItemKind::Type, header, span, header_span: span,
                declaration_cursor: None, checker_qualifiers: crate::UNKNOWN_HEADER_QUALIFIERS,
                original_outer_terminator: Some(false), indent: 0, children: Vec::new(),
            }));
            let block = compact_block(rows, source, &storage).unwrap();
            let Block::Wide(rows) = block else { panic!("must keep exact wide representation") };
            assert_eq!(rows[0].header.as_ptr(), backing);
            assert_eq!(used.load(Ordering::Acquire), retained);
            assert!(!admission.is_stopped());
            drop((rows, storage));
            assert_eq!(used.load(Ordering::Acquire), 0);
        }
    }
}
