//! Committed rows from the actual Original primary frame machine.
//! Offsets are DATA. The emitted source owner and its source/model receipt
//! remain with the caller that binds the completed primary product.
use super::{Item, ItemKind, Span, original_storage::Storage};
use crate::SettingRootLease;
use std::{io, mem::size_of, ops::Range};

pub(super) const ROOT_ITEM_BLOCK: usize = 256;
const MAX_BLOCK_ROWS: usize = 8192;
const _: () = assert!(MAX_BLOCK_ROWS <= u16::MAX as usize);
const MAX_HEADER_BYTES: usize = 2 * 1024 * 1024;

fn overflow() -> io::Error { io::ErrorKind::OutOfMemory.into() }

#[repr(C)]
#[derive(Clone, Copy)]
struct CompactItem {
    span: [u32; 2],
    header: [u32; 2],
    cursor: u32,
    indent: u32,
    children: [u16; 2],
    kind: ItemKind,
    qualifiers: u8,
    outer: Option<bool>,
    empty_header: bool,
}
const _: () = assert!(size_of::<CompactItem>() == 32);

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

#[repr(C)]
struct NarrowItem {
    span: [u32; 2],
    header_end: u32,
    cursor_delta: u16,
    indent: u16,
    children: [u16; 2],
    kind: ItemKind,
    qualifiers: u8,
    outer: Option<bool>,
    empty_header: bool,
}
const _: () = assert!(size_of::<NarrowItem>() == 24);

impl NarrowItem {
    fn pack(item: CompactItem) -> Option<Self> {
        let start = item.span[0];
        if item.header[0] != start {
            return None;
        }
        let cursor_delta = if item.cursor == u32::MAX {
            u16::MAX
        } else {
            let delta = u16::try_from(item.cursor.checked_sub(start)?).ok()?;
            if delta == u16::MAX { return None; }
            delta
        };
        Some(Self {
            span: item.span,
            header_end: item.header[1],
            cursor_delta,
            indent: u16::try_from(item.indent).ok()?,
            children: item.children,
            kind: item.kind,
            qualifiers: item.qualifiers,
            outer: item.outer,
            empty_header: item.empty_header,
        })
    }

    fn unpack(&self) -> CompactItem {
        CompactItem {
            span: self.span,
            header: [self.span[0], self.header_end],
            cursor: if self.cursor_delta == u16::MAX {
                u32::MAX
            } else {
                self.span[0] + u32::from(self.cursor_delta)
            },
            indent: u32::from(self.indent),
            children: self.children,
            kind: self.kind,
            qualifiers: self.qualifiers,
            outer: self.outer,
            empty_header: self.empty_header,
        }
    }
}

// Exact geometry. A short cell either contains every original datum or
// names one exact 24B row owned by the same block.
#[repr(C)]
struct ShortItem {
    start: u32,
    span_len: u16,
    cursor_delta: u16,
    children: [u16; 2],
    header_len: u8,
    indent: u8,
    flags: u8,
    qualifiers: u8,
}
const _: () = assert!(size_of::<ShortItem>() == 16);

impl ShortItem {
    const ESCAPE: u8 = 1 << 7;
    fn pack(row: &NarrowItem) -> Option<Self> {
        let start = row.span[0];
        let kind = match row.kind {
            ItemKind::Type => 0, ItemKind::Proc => 1, ItemKind::Verb => 2,
            ItemKind::Var => 3, ItemKind::Statement => 4, ItemKind::Unknown => 5,
        };
        let outer = match row.outer { None => 0, Some(false) => 1, Some(true) => 2 };
        Some(Self {
            start,
            span_len: u16::try_from(row.span[1].checked_sub(start)?).ok()?,
            cursor_delta: row.cursor_delta,
            children: row.children,
            header_len: u8::try_from(row.header_end.checked_sub(start)?).ok()?,
            indent: u8::try_from(row.indent).ok()?,
            flags: kind | (outer << 3) | (u8::from(row.empty_header) << 5),
            qualifiers: row.qualifiers,
        })
    }
    fn escape(ordinal: u16) -> Self {
        Self { start: 0, span_len: ordinal, cursor_delta: 0, children: [0; 2],
            header_len: 0, indent: 0, flags: Self::ESCAPE, qualifiers: 0 }
    }
    fn escaped(&self) -> Option<usize> {
        (self.flags == Self::ESCAPE).then_some(usize::from(self.span_len))
    }
    fn unpack(&self) -> CompactItem {
        debug_assert!(self.escaped().is_none());
        let kind = match self.flags & 7 {
            0 => ItemKind::Type, 1 => ItemKind::Proc, 2 => ItemKind::Verb, 3 => ItemKind::Var,
            4 => ItemKind::Statement, 5 => ItemKind::Unknown, _ => unreachable!("issued short item kind"),
        };
        let outer = match (self.flags >> 3) & 3 {
            0 => None, 1 => Some(false), 2 => Some(true), _ => unreachable!("issued short outer marker"),
        };
        NarrowItem {
            span: [self.start, self.start + u32::from(self.span_len)],
            header_end: self.start + u32::from(self.header_len),
            cursor_delta: self.cursor_delta, indent: u16::from(self.indent), children: self.children,
            kind, qualifiers: self.qualifiers, outer, empty_header: self.flags & (1 << 5) != 0,
        }.unpack()
    }
}

// The previous short cell's geometry, with a block-relative start and
// child start/count. Explicit byte encoding avoids alignment padding.
struct TinyItem([u8; 14]);
const _: () = assert!(size_of::<TinyItem>() == 14);
impl TinyItem {
    const MAX_DELTA: u32 = 0xff_ffff;
    const CHILD_START_BITS: u32 = 14;
    const MAX_CHILD_COUNT: usize = (1 << (24 - Self::CHILD_START_BITS)) - 1;

    fn pack(row: ShortItem, base: u32) -> Self {
        let delta = row.start.checked_sub(base).expect("preflight item base");
        assert!(delta <= Self::MAX_DELTA);
        let [s0, s1, s2, _] = delta.to_le_bytes();
        let [w0, w1] = row.span_len.to_le_bytes();
        let [c0, c1] = row.cursor_delta.to_le_bytes();
        Self([s0, s1, s2, w0, w1, c0, c1, 0, 0, 0,
              row.header_len, row.indent, row.flags, row.qualifiers])
    }

    fn escape(ordinal: u16) -> Self {
        let [lo, hi] = ordinal.to_le_bytes();
        Self([lo, hi, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ShortItem::ESCAPE, 0])
    }

    fn escaped(&self) -> Option<usize> {
        (self.0[12] == ShortItem::ESCAPE)
            .then(|| usize::from(u16::from_le_bytes([self.0[0], self.0[1]])))
    }

    fn set_children(&mut self, [first, last]: [u16; 2]) {
        let count = usize::from(last.checked_sub(first).expect("ordered children"));
        assert!(u32::from(first) < 1 << Self::CHILD_START_BITS && count <= Self::MAX_CHILD_COUNT);
        let encoded = u32::from(first) | ((count as u32) << Self::CHILD_START_BITS);
        self.0[7..10].copy_from_slice(&encoded.to_le_bytes()[..3]);
    }

    fn unpack(&self, base: u32) -> CompactItem {
        let [s0, s1, s2, w0, w1, c0, c1, k0, k1, k2, header_len, indent, flags, qualifiers] = self.0;
        let children = u32::from_le_bytes([k0, k1, k2, 0]);
        let first = (children & ((1 << Self::CHILD_START_BITS) - 1)) as u16;
        let count = (children >> Self::CHILD_START_BITS) as u16;
        ShortItem {
            start: base + u32::from_le_bytes([s0, s1, s2, 0]),
            span_len: u16::from_le_bytes([w0, w1]),
            cursor_delta: u16::from_le_bytes([c0, c1]),
            children: [first, first + count],
            header_len, indent, flags, qualifiers,
        }.unpack()
    }
}

struct TinyBlockGeometry { base: u32, roots: u16 }

#[cfg(debug_assertions)]
#[derive(Default, Debug)]
pub(super) struct ShortItemCensus {
    narrow_rows: usize,
    tiny_blocks: usize,
    tiny_rows: usize,
    tiny_escape_rows: usize,
    tiny_savings_over_short: usize,
    fits_short: usize,
    span_len_exceeds_u16: usize,
    header_len_exceeds_u8: usize,
    indent_exceeds_u8: usize,
    all_short_blocks: usize,
    mixed_short_blocks: usize,
    mixed_escape_rows: usize,
    original_narrow_bytes: usize,
    whole_block_row_bytes: usize,
    mixed_row_and_side_bytes: usize,
    possible_directory_pointer_bytes: usize,
    whole_block_row_savings: usize,
    mixed_savings_after_directory: usize,
}

#[cfg(debug_assertions)]
impl ShortItemCensus {
    fn visit_narrow(&mut self, rows: &Vec<NarrowItem>) {
        let old = rows.capacity() * size_of::<NarrowItem>();
        self.narrow_rows += rows.len();
        self.original_narrow_bytes += old;
        let mut escapes = 0;
        for row in rows {
            let span_wide = row.span[1].checked_sub(row.span[0]).is_none_or(|len| u16::try_from(len).is_err());
            let header_wide = row.header_end.checked_sub(row.span[0]).is_none_or(|len| u8::try_from(len).is_err());
            let indent_wide = u8::try_from(row.indent).is_err();
            self.span_len_exceeds_u16 += usize::from(span_wide);
            self.header_len_exceeds_u8 += usize::from(header_wide);
            self.indent_exceeds_u8 += usize::from(indent_wide);
            escapes += usize::from(span_wide || header_wide || indent_wide);
        }
        self.fits_short += rows.len() - escapes;
        let short = rows.len() * size_of::<ShortItem>();
        // Each escaped cell can encode its side ordinal in its own u16
        // geometry plus one spare flag bit. No rank or second index.
        let whole = if escapes == 0 {
            self.all_short_blocks += 1;
            short
        } else {
            old
        };
        let mixed = if escapes != 0 {
            let side = escapes * size_of::<NarrowItem>() + size_of::<Vec<NarrowItem>>();
            if short + side < old {
                self.mixed_short_blocks += 1;
                self.mixed_escape_rows += escapes;
                short + side
            } else {
                old
            }
        } else {
            short
        };
        self.whole_block_row_bytes += whole;
        self.mixed_row_and_side_bytes += mixed;
    }

    fn finish(&mut self, directory_capacity: usize) {
        // The mixed model permits one optional side Vec box per new block.
        // Budget a pointer-width directory expansion for every reserved cell.
        self.possible_directory_pointer_bytes = directory_capacity * size_of::<usize>();
        self.whole_block_row_savings = self.original_narrow_bytes - self.whole_block_row_bytes;
        self.mixed_savings_after_directory = self.original_narrow_bytes
            .saturating_sub(self.mixed_row_and_side_bytes + self.possible_directory_pointer_bytes);
    }
}

enum Block {
    Narrow { rows: Vec<NarrowItem>, roots: usize },
    Short { rows: Vec<ShortItem>, escapes: Vec<NarrowItem>, roots: usize },
    Tiny { rows: Vec<TinyItem>, escapes: Vec<NarrowItem>, geometry: TinyBlockGeometry },
    Compact { rows: Vec<CompactItem>, roots: usize },
    Wide(Vec<Item>),
}
// Bound directory overhead independently of the compact row savings.
#[cfg(target_pointer_width = "64")]
const _: () = assert!(size_of::<Block>() <= 64);

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
                Block::Narrow { rows, .. } => rows.capacity().checked_mul(size_of::<NarrowItem>()),
                Block::Short { rows, escapes, .. } => rows.capacity().checked_mul(size_of::<ShortItem>())
                    .and_then(|bytes| bytes.checked_add(escapes.capacity().checked_mul(size_of::<NarrowItem>())?)),
                Block::Tiny { rows, escapes, .. } => rows.capacity().checked_mul(size_of::<TinyItem>())
                    .and_then(|bytes| bytes.checked_add(escapes.capacity().checked_mul(size_of::<NarrowItem>())?)),
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
    pub(super) fn trace_compact(&self) -> ((usize, usize, usize, usize, usize), ShortItemCensus) {
        let mut blocks = 0usize;
        let mut rows = 0usize;
        let mut bytes = 0usize;
        let mut narrow_rows = 0usize;
        let mut short = ShortItemCensus::default();
        for block in &self.blocks {
            let (len, capacity_bytes) = match block {
                Block::Narrow { rows, .. } => {
                    narrow_rows = narrow_rows.saturating_add(rows.len());
                    short.visit_narrow(rows);
                    (rows.len(), rows.capacity().saturating_mul(size_of::<NarrowItem>()))
                }
                Block::Short { rows, escapes, .. } =>
                    (rows.len(), rows.capacity().saturating_mul(size_of::<ShortItem>())
                        + escapes.capacity().saturating_mul(size_of::<NarrowItem>())),
                Block::Tiny { rows, escapes, .. } => {
                    let bytes = rows.capacity() * size_of::<TinyItem>() + escapes.capacity() * size_of::<NarrowItem>();
                    short.tiny_blocks += 1;
                    short.tiny_rows += rows.len();
                    short.tiny_escape_rows += escapes.len();
                    // Count real old-short eligibility inside the exact
                    // escape rows, not all new child-width escapes.
                    let old_escapes = escapes.iter().filter(|row| ShortItem::pack(row).is_none()).count();
                    let old = (rows.len() * size_of::<ShortItem>() + old_escapes * size_of::<NarrowItem>())
                        .min(rows.len() * size_of::<NarrowItem>());
                    short.tiny_savings_over_short += old.saturating_sub(bytes);
                    (rows.len(), bytes)
                }
                Block::Compact { rows, .. } =>
                    (rows.len(), rows.capacity().saturating_mul(size_of::<CompactItem>())),
                Block::Wide(_) => continue,
            };
            blocks += 1;
            rows = rows.saturating_add(len);
            bytes = bytes.saturating_add(capacity_bytes);
        }
        short.finish(self.blocks.capacity());
        ((blocks, rows, bytes, self.blocks.capacity().saturating_mul(size_of::<Block>()), narrow_rows), short)
    }
}

fn compact_block(items: Vec<Item>, source: &str, storage: &Storage<'_, '_>) -> io::Result<Block> {
    #[derive(Default)]
    struct ExactShape {
        rows: usize, old_bytes: usize, header_bytes: usize, needs_full_compact: bool,
        short_escapes: usize, tiny_escapes: usize, min_start: Option<u32>, max_start: u32,
    }
    fn inspect(items: &Vec<Item>, source: &str, shape: &mut ExactShape) -> Option<()> {
        shape.rows = shape.rows.checked_add(items.len())?;
        if shape.rows > MAX_BLOCK_ROWS { return None; }
        shape.old_bytes = shape.old_bytes.checked_add(items.capacity().checked_mul(size_of::<Item>())?)?;
        for item in items {
            shape.header_bytes = shape.header_bytes.checked_add(item.header.capacity())?;
            if shape.header_bytes > MAX_HEADER_BYTES { return None; }
            shape.old_bytes = shape.old_bytes.checked_add(item.header.capacity())?;
            let geometry = CompactItem::geometry(item, source)?;
            match NarrowItem::pack(geometry) {
                Some(narrow) => {
                    let start = narrow.span[0];
                    shape.min_start = Some(shape.min_start.map_or(start, |old| old.min(start)));
                    shape.max_start = shape.max_start.max(start);
                    let short_escape = ShortItem::pack(&narrow).is_none();
                    shape.short_escapes += usize::from(short_escape);
                    shape.tiny_escapes += usize::from(short_escape || item.children.len() > TinyItem::MAX_CHILD_COUNT);
                }
                None => shape.needs_full_compact = true,
            }
            // Depth is bounded by the actual admitted primary frame machine.
            inspect(&item.children, source, shape)?;
        }
        Some(())
    }
    fn append<T>(
        items: &[Item],
        source: &str,
        packed: &mut Vec<T>,
        pack: fn(CompactItem) -> T,
        set_children: fn(&mut T, [u16; 2]),
    ) -> [u16; 2] {
        let start = packed.len();
        packed.extend(items.iter().map(|item| pack(CompactItem::geometry(item, source).expect("checked original item geometry"))));
        let end = packed.len();
        for (i, item) in items.iter().enumerate() {
            let children = append(&item.children, source, packed, pack, set_children);
            set_children(&mut packed[start + i], children);
        }
        [start, end].map(|ordinal| u16::try_from(ordinal).expect("preflight bounds block ordinals"))
    }

    fn append_tiny(items: &[Item], source: &str, base: u32, rows: &mut Vec<TinyItem>,
                   escapes: &mut Vec<NarrowItem>) -> [u16; 2] {
        let start = rows.len();
        for item in items {
            let geometry = CompactItem::geometry(item, source).expect("checked original item geometry");
            let narrow = NarrowItem::pack(geometry).expect("checked narrow geometry");
            let short = (item.children.len() <= TinyItem::MAX_CHILD_COUNT)
                .then(|| ShortItem::pack(&narrow)).flatten();
            rows.push(if let Some(short) = short {
                TinyItem::pack(short, base)
            } else {
                let ordinal = u16::try_from(escapes.len()).expect("preflight bounds exact escapes");
                escapes.push(narrow);
                TinyItem::escape(ordinal)
            });
        }
        let end = rows.len();
        for (i, item) in items.iter().enumerate() {
            let children = append_tiny(&item.children, source, base, rows, escapes);
            let row = &mut rows[start + i];
            if let Some(at) = row.escaped() { escapes[at].children = children; }
            else { row.set_children(children); }
        }
        [start, end].map(|ordinal| u16::try_from(ordinal).expect("preflight bounds block ordinals"))
    }

    fn append_short(items: &[Item], source: &str, rows: &mut Vec<ShortItem>, escapes: &mut Vec<NarrowItem>) -> [u16; 2] {
        let start = rows.len();
        for item in items {
            let geometry = CompactItem::geometry(item, source).expect("checked original item geometry");
            let narrow = NarrowItem::pack(geometry).expect("checked narrow geometry");
            let row = ShortItem::pack(&narrow).unwrap_or_else(|| {
                let ordinal = u16::try_from(escapes.len()).expect("preflight bounds exact escapes");
                escapes.push(narrow);
                ShortItem::escape(ordinal)
            });
            rows.push(row);
        }
        let end = rows.len();
        for (i, item) in items.iter().enumerate() {
            let children = append_short(&item.children, source, rows, escapes);
            let row = &mut rows[start + i];
            if let Some(at) = row.escaped() { escapes[at].children = children; }
            else { row.children = children; }
        }
        [start, end].map(|ordinal| u16::try_from(ordinal).expect("preflight bounds block ordinals"))
    }

    fn tiny_block(items: &[Item], source: &str, base: u32, shape: &ExactShape, storage: &Storage<'_, '_>)
        -> io::Result<Option<(Block, SettingRootLease, Option<SettingRootLease>)>>
    {
        let Some((mut rows, credit)) = storage.try_item_block_vector::<TinyItem>(shape.rows)? else { return Ok(None); };
        let (mut escapes, escape_credit) = match stage_escapes(shape.tiny_escapes, storage) {
            Ok(Some(result)) => result,
            result => {
                drop(rows);
                drop(credit);
                return result.map(|_| None);
            }
        };
        let [_, roots] = append_tiny(items, source, base, &mut rows, &mut escapes);
        debug_assert_eq!((rows.len(), escapes.len()), (shape.rows, shape.tiny_escapes));
        Ok(Some((Block::Tiny { rows, escapes, geometry: TinyBlockGeometry { base, roots } }, credit, escape_credit)))
    }

    fn stage_escapes(count: usize, storage: &Storage<'_, '_>)
        -> io::Result<Option<(Vec<NarrowItem>, Option<SettingRootLease>)>>
    {
        if count == 0 { return Ok(Some((Vec::new(), None))); }
        Ok(storage.try_item_block_vector::<NarrowItem>(count)?
            .map(|(rows, credit)| (rows, Some(credit))))
    }

    fn short_block(items: &[Item], source: &str, shape: &ExactShape, storage: &Storage<'_, '_>)
        -> io::Result<Option<(Block, SettingRootLease, Option<SettingRootLease>)>>
    {
        let Some((mut rows, credit)) = storage.try_item_block_vector::<ShortItem>(shape.rows)? else { return Ok(None); };
        let (mut escapes, escape_credit) = match stage_escapes(shape.short_escapes, storage) {
            Ok(Some(result)) => result,
            result => {
                // Candidate rows physically die before their grant.
                drop(rows);
                drop(credit);
                return result.map(|_| None);
            }
        };
        let [_, roots] = append_short(items, source, &mut rows, &mut escapes);
        debug_assert_eq!((rows.len(), escapes.len()), (shape.rows, shape.short_escapes));
        Ok(Some((Block::Short { rows, escapes, roots: usize::from(roots) }, credit, escape_credit)))
    }

    let mut shape = ExactShape::default();
    if inspect(&items, source, &mut shape).is_none() {
        return Ok(Block::Wide(items));
    }
    let short_bytes = shape.rows * size_of::<ShortItem>() + shape.short_escapes * size_of::<NarrowItem>();
    let tiny_bytes = shape.rows * size_of::<TinyItem>() + shape.tiny_escapes * size_of::<NarrowItem>();
    let tiny = if !shape.needs_full_compact && tiny_bytes < short_bytes.min(shape.rows * size_of::<NarrowItem>()) {
        let base = shape.min_start.expect("nonempty narrow block");
        if shape.max_start - base <= TinyItem::MAX_DELTA {
            tiny_block(&items, source, base, &shape, storage)?
        } else { None }
    } else { None };
    let short = if tiny.is_none() && !shape.needs_full_compact
        && shape.rows * size_of::<ShortItem>() + shape.short_escapes * size_of::<NarrowItem>()
            < shape.rows * size_of::<NarrowItem>()
    {
        short_block(&items, source, &shape, storage)?
    } else { None };
    let (block, mut credit, mut escape_credit) = if let Some(short) = tiny.or(short) {
        short
    } else if shape.needs_full_compact {
        let Some((mut packed, credit)) = storage.try_item_block_vector::<CompactItem>(shape.rows)? else {
            return Ok(Block::Wide(items));
        };
        let [_, roots] = append(&items, source, &mut packed, |item| item, |item, children| item.children = children);
        debug_assert_eq!(packed.len(), shape.rows);
        (Block::Compact { rows: packed, roots: usize::from(roots) }, credit, None)
    } else {
        let Some((mut packed, credit)) = storage.try_item_block_vector::<NarrowItem>(shape.rows)? else {
            return Ok(Block::Wide(items));
        };
        let [_, roots] = append(&items, source, &mut packed, |item| NarrowItem::pack(item).expect("checked narrow geometry"), |item, children| item.children = children);
        debug_assert_eq!(packed.len(), shape.rows);
        (Block::Narrow { rows: packed, roots: usize::from(roots) }, credit, None)
    };
    let adopted = storage.adopt_item_block_credit(&mut credit).and_then(|()| {
        escape_credit.as_mut().map_or(Ok(()), |credit| storage.adopt_item_block_credit(credit))
    });
    if let Err(error) = adopted {
        drop(block);
        return Err(error);
    }
    drop(items);
    storage.release_item_block_bytes(shape.old_bytes)?;
    Ok(block)
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
                Block::Narrow { rows, .. } => rows.iter().any(|row| !row.empty_header
                    && source.get(CompactItem::span_of([row.span[0], row.header_end]).range()).is_none()),
                Block::Short { rows, escapes, .. } => rows.iter().any(|row| {
                    let geometry = row.escaped().map_or_else(|| row.unpack(), |at| escapes[at].unpack());
                    !geometry.empty_header && source.get(CompactItem::span_of(geometry.header).range()).is_none()
                }),
                Block::Tiny { rows, escapes, geometry } => rows.iter().any(|row| {
                    let row = row.escaped().map_or_else(|| row.unpack(geometry.base), |at| escapes[at].unpack());
                    !row.empty_header && source.get(CompactItem::span_of(row.header).range()).is_none()
                }),
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
                Block::Narrow { rows, .. } => buffer(rows, &mut visit),
                Block::Short { rows, escapes, .. } => { buffer(rows, &mut visit); buffer(escapes, &mut visit); }
                Block::Tiny { rows, escapes, .. } => { buffer(rows, &mut visit); buffer(escapes, &mut visit); }
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
enum CompactSlice<'a> {
    Narrow(&'a [NarrowItem]),
    Short(&'a [ShortItem], &'a [NarrowItem]),
    Tiny(&'a [TinyItem], &'a [NarrowItem], u32),
    Full(&'a [CompactItem]),
}

impl<'a> CompactSlice<'a> {
    fn get(self, index: usize) -> Option<CompactRow<'a>> {
        match self {
            Self::Narrow(rows) => rows.get(index).map(CompactRow::Narrow),
            Self::Short(rows, escapes) => {
                let row = rows.get(index)?;
                match row.escaped() {
                    Some(at) => escapes.get(at).map(CompactRow::Narrow),
                    None => Some(CompactRow::Short(row)),
                }
            }
            Self::Tiny(rows, escapes, base) => {
                let row = rows.get(index)?;
                match row.escaped() {
                    Some(at) => escapes.get(at).map(CompactRow::Narrow),
                    None => Some(CompactRow::Tiny(row, base)),
                }
            }
            Self::Full(rows) => rows.get(index).map(CompactRow::Full),
        }
    }

    fn same(self, other: Self) -> bool {
        match (self, other) {
            (Self::Narrow(a), Self::Narrow(b)) => std::ptr::eq(a, b),
            (Self::Short(a, aw), Self::Short(b, bw)) => std::ptr::eq(a, b) && std::ptr::eq(aw, bw),
            (Self::Tiny(a, aw, ab), Self::Tiny(b, bw, bb)) =>
                ab == bb && std::ptr::eq(a, b) && std::ptr::eq(aw, bw),
            (Self::Full(a), Self::Full(b)) => std::ptr::eq(a, b),
            _ => false,
        }
    }
}

#[derive(Clone, Copy)]
enum CompactRow<'a> {
    Narrow(&'a NarrowItem),
    Short(&'a ShortItem),
    Tiny(&'a TinyItem, u32),
    Full(&'a CompactItem),
}

impl CompactRow<'_> {
    fn geometry(self) -> CompactItem {
        match self {
            Self::Narrow(row) => row.unpack(),
            Self::Short(row) => row.unpack(),
            Self::Tiny(row, base) => row.unpack(base),
            Self::Full(row) => *row,
        }
    }

    fn same(self, other: Self) -> bool {
        match (self, other) {
            (Self::Narrow(a), Self::Narrow(b)) => std::ptr::eq(a, b),
            (Self::Short(a), Self::Short(b)) => std::ptr::eq(a, b),
            (Self::Tiny(a, ab), Self::Tiny(b, bb)) => ab == bb && std::ptr::eq(a, b),
            (Self::Full(a), Self::Full(b)) => std::ptr::eq(a, b),
            _ => false,
        }
    }
}

#[derive(Clone, Copy)]
enum Siblings<'a> {
    Wide(&'a [Item]),
    Compact { rows: CompactSlice<'a>, interval: [u32; 2], source: &'a str },
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
             Siblings::Compact { rows: b, interval: y, source: t }) => x == y && a.same(b) && std::ptr::eq(s, t),
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
                let geometry = row.geometry();
                let header = if geometry.empty_header { "" } else { source.get(CompactItem::span_of(geometry.header).range())? };
                Some(OriginalItem(ItemView::Compact { row, rows, source, header }))
            }
            Siblings::Blocks { blocks, source, .. } => {
                let block = blocks.get(index / ROOT_ITEM_BLOCK)?;
                let local = index % ROOT_ITEM_BLOCK;
                match block {
                    Block::Wide(items) => Self::from_items(items).get(local),
                    Block::Narrow { rows, roots } => {
                        Self(Siblings::Compact { rows: CompactSlice::Narrow(rows), interval: [0, *roots as u32], source }).get(local)
                    }
                    Block::Short { rows, escapes, roots } => {
                        Self(Siblings::Compact { rows: CompactSlice::Short(rows, escapes),
                            interval: [0, *roots as u32], source }).get(local)
                    }
                    Block::Tiny { rows, escapes, geometry } => {
                        Self(Siblings::Compact { rows: CompactSlice::Tiny(rows, escapes, geometry.base),
                            interval: [0, u32::from(geometry.roots)], source }).get(local)
                    }
                    Block::Compact { rows, roots } => {
                        Self(Siblings::Compact { rows: CompactSlice::Full(rows), interval: [0, *roots as u32], source }).get(local)
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
    Compact { row: CompactRow<'a>, rows: CompactSlice<'a>, source: &'a str, header: &'a str },
}

#[derive(Clone, Copy)]
pub struct OriginalItem<'a>(ItemView<'a>);

impl std::fmt::Debug for OriginalItem<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("OriginalItem")
            .field("kind", &self.kind())
            .field("header", &self.header())
            .field("span", &self.span())
            .finish_non_exhaustive()
    }
}

impl<'a> OriginalItem<'a> {
    pub fn kind(self) -> ItemKind { match self.0 { ItemView::Wide(i) => i.kind, ItemView::Compact { row, .. } => row.geometry().kind } }
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
                a.same(b) && std::ptr::eq(s, t),
            _ => false,
        }
    }
    pub fn span(self) -> Span { match self.0 { ItemView::Wide(i) => i.span, ItemView::Compact { row, .. } => CompactItem::span_of(row.geometry().span) } }
    pub fn header_span(self) -> Span { match self.0 { ItemView::Wide(i) => i.header_span, ItemView::Compact { row, .. } => CompactItem::span_of(row.geometry().header) } }
    pub fn declaration_cursor(self) -> Option<usize> {
        match self.0 {
            ItemView::Wide(i) => i.declaration_cursor,
            ItemView::Compact { row, .. } => {
                let cursor = row.geometry().cursor;
                (cursor != u32::MAX).then_some(cursor as usize)
            }
        }
    }
    pub fn checker_qualifiers(self) -> u8 { match self.0 { ItemView::Wide(i) => i.checker_qualifiers, ItemView::Compact { row, .. } => row.geometry().qualifiers } }
    pub fn original_outer_terminator(self) -> Option<bool> { match self.0 { ItemView::Wide(i) => i.original_outer_terminator, ItemView::Compact { row, .. } => row.geometry().outer } }
    pub fn indent(self) -> usize { match self.0 { ItemView::Wide(i) => i.indent, ItemView::Compact { row, .. } => row.geometry().indent as usize } }
    pub fn children(self) -> OriginalItems<'a> {
        match self.0 {
            ItemView::Wide(i) => OriginalItems::from_items(&i.children),
            ItemView::Compact { row, rows, source, .. } => OriginalItems(Siblings::Compact { rows, interval: row.geometry().children.map(u32::from), source }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{NativeTokenCursor, NativeTokenStep, OriginalPrimaryDemand, SettingAdmission};
    use std::{fmt::Write, sync::{atomic::{Ordering}}};

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
            let dense_used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
            let compact_used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
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
            assert!(forest.data.blocks.iter().all(|block| matches!(block, Block::Tiny { .. })));
            assert!(forest.data.blocks.len() >= 3);
            assert!(compact_used.load(Ordering::Acquire) + 20_000 < dense_used.load(Ordering::Acquire));
            drop((tokens, diagnostics, diagnostic_lease));
            assert_eq!(compact_used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (forest._lease.bytes()));
            drop((forest, dense));
            assert_eq!(compact_used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
            assert_eq!(dense_used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
        }
    }

    #[test]
    fn committed_item_child_endpoints_include_the_exact_block_bound() {
        let source = "/datum/p";
        let span = Span::new(0, source.len());
        for count in [MAX_BLOCK_ROWS, MAX_BLOCK_ROWS + 1] {
            let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
            let admission = SettingAdmission::new(&used, 8<<20, &|| Ok(()));
            let storage = Storage::new(&admission).unwrap();
            let make = |children| Item {
                kind: ItemKind::Type, header: storage.text(source).unwrap(), span, header_span: span,
                declaration_cursor: None, checker_qualifiers: crate::UNKNOWN_HEADER_QUALIFIERS,
                original_outer_terminator: Some(false), indent: u32::MAX as usize, children,
            };
            let mut children = Vec::new();
            for _ in 1..count {
                assert!(storage.push(&mut children, make(Vec::new())));
            }
            let mut items = Vec::new();
            assert!(storage.push(&mut items, make(children)));
            let block = compact_block(items, source, &storage).unwrap();
            match &block {
                Block::Compact { rows, roots } if count == MAX_BLOCK_ROWS => {
                    assert_eq!(*roots, 1);
                    assert_eq!(rows[0].children, [1, MAX_BLOCK_ROWS as u16]);
                    assert_eq!(rows.last().unwrap().children, [MAX_BLOCK_ROWS as u16; 2]);
                    let root = OriginalItems(Siblings::Compact { rows: CompactSlice::Full(rows), interval: [0, 1], source }).get(0).unwrap();
                    assert_eq!(root.indent(), u32::MAX as usize);
                    let children = root.children();
                    assert_eq!(children.len(), count - 1);
                    assert_eq!(children.iter().next_back().unwrap().header().as_ptr(), source.as_ptr());
                    assert!(children.get(count - 1).is_none());
                }
                Block::Wide(items) if count == MAX_BLOCK_ROWS + 1 => {
                    assert_eq!(items[0].children.len(), count - 1);
                    assert_eq!(items[0].indent, u32::MAX as usize);
                }
                _ => panic!("block bound must select its original exact representation"),
            }
            drop((block, storage));
            assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
        }
    }

    #[test]
    fn short_committed_block_preserves_exact_escape_children_and_owner() {
        let text = "é".repeat(160);
        let span = Span::new(0, text.len());
        let fixed = crate::SettingChargeCounter::root_allocation_bytes();
        let used = crate::SettingChargeCounter::try_new(fixed).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let storage = Storage::new(&a).unwrap();
        let make = |len, indent, children| Item {
            kind: ItemKind::Var, header: storage.text(&text[..len]).unwrap(),
            span: Span::new(0, len), header_span: Span::new(0, len),
            declaration_cursor: Some(len), checker_qualifiers: 0xff,
            original_outer_terminator: Some(false), indent, children,
        };
        let mut children = Vec::new();
        for _ in 0..5 {
            assert!(storage.push(&mut children, make(2, 255, Vec::new())));
        }
        let mut items = Vec::new();
        assert!(storage.push(&mut items, make(text.len(), 256, children)));
        let block = compact_block(items, &text, &storage).unwrap();
        let Block::Tiny { rows, escapes, geometry } = &block else { panic!("profitable exact mixed block"); };
        assert_eq!((geometry.roots, rows.len(), escapes.len()), (1, 6, 1));
        let view = OriginalItems(Siblings::Compact {
            rows: CompactSlice::Tiny(rows, escapes, geometry.base), interval: [0, 1], source: &text,
        });
        let root = view.get(0).unwrap();
        assert!(root.same_item(view.get(0).unwrap()));
        assert_eq!(root.span(), span);
        assert_eq!(root.header().as_ptr(), text.as_ptr());
        assert_eq!((root.indent(), root.declaration_cursor()), (256, Some(text.len())));
        let children = root.children();
        assert_eq!(children.len(), 5);
        for child in children.iter() {
            assert_eq!((child.indent(), child.declaration_cursor()), (255, Some(2)));
            assert_eq!(child.header(), "é");
            assert_eq!(child.checker_qualifiers(), 0xff);
            assert_eq!(child.original_outer_terminator(), Some(false));
        }
        drop((block, storage));
        assert_eq!(used.load(Ordering::Acquire), fixed);
    }

    #[test]
    fn tiny_cell_preserves_maximum_relative_start_and_both_child_bounds() {
        let base = 19;
        let start = base + TinyItem::MAX_DELTA;
        let mut row = TinyItem::pack(ShortItem {
            start, span_len: 255, cursor_delta: 65_534, children: [0, 0],
            header_len: 255, indent: 255, flags: 2 | (2 << 3), qualifiers: u8::MAX,
        }, base);
        row.set_children([8192, 8192]);
        let geometry = row.unpack(base);
        assert_eq!((geometry.span, geometry.header), ([start, start + 255], [start, start + 255]));
        assert_eq!(geometry.cursor, start + 65_534);
        assert_eq!(geometry.children, [8192, 8192]);
        assert_eq!(geometry.outer, Some(true));
        assert_eq!(geometry.qualifiers, u8::MAX);
        row.set_children([7169, 8192]);
        assert_eq!(row.unpack(base).children, [7169, 8192]);
    }

    #[test]
    fn tiny_mixed_child_escape_keeps_distinct_empty_intervals_and_exact_credit() {
        let source = "/datum/p";
        let span = Span::new(0, source.len());
        let fixed = crate::SettingChargeCounter::root_allocation_bytes();
        let used = crate::SettingChargeCounter::try_new(fixed).unwrap();
        let a = SettingAdmission::new(&used, 8 << 20, &|| Ok(()));
        let storage = Storage::new(&a).unwrap();
        let make = |children| Item {
            kind: ItemKind::Type, header: storage.text(source).unwrap(), span, header_span: span,
            declaration_cursor: Some(1), checker_qualifiers: 0xff,
            original_outer_terminator: Some(false), indent: 0, children,
        };
        let children = |count| {
            let mut rows = Vec::new();
            for _ in 0..count {
                assert!(storage.push(&mut rows, make(Vec::new())));
            }
            rows
        };
        let mut roots = Vec::new();
        assert!(storage.push(&mut roots, make(children(1024))));
        assert!(storage.push(&mut roots, make(children(1))));
        let mut pending = PendingCommittedItems::default();
        pending.push(roots, source, &storage).unwrap();
        let Block::Tiny { rows, escapes, .. } = &pending.blocks[0] else { panic!("profitable mixed block"); };
        assert_eq!((rows.len(), escapes.len()), (1027, 1));
        assert_eq!(rows[0].escaped(), Some(0));
        let bytes = pending.bytes(&storage).unwrap();
        let (credit, parser) = storage.finish_committed(bytes, &Vec::new()).unwrap();
        let forest = pending.finish(source.len(), credit);
        let view = forest.view(source).unwrap();
        let left = view.get(0).unwrap().children();
        let right = view.get(1).unwrap().children();
        assert_eq!((left.len(), right.len()), (1024, 1));
        let left_empty = left.get(1023).unwrap().children();
        let right_empty = right.get(0).unwrap().children();
        assert!(left_empty.is_empty() && right_empty.is_empty());
        assert!(!left_empty.same_interval(right_empty));
        assert!(left_empty.same_interval(left.get(1023).unwrap().children()));
        drop(parser);
        assert_eq!(used.load(Ordering::Acquire), fixed + bytes);
        drop(forest);
        assert_eq!(used.load(Ordering::Acquire), fixed);
    }

    #[test]
    fn committed_narrow_geometry_preserves_exact_edge_and_full_compact_fallback() {
        let source = "abc".repeat(22_000);
        let span = Span::new(0, source.len());
        for (cursor, indent, header_start, narrow) in [
            (None, 0, 0, true),
            (Some(65_534), 65_535, 0, true),
            (Some(65_535), 0, 0, false),
            (Some(1), 65_536, 0, false),
            (Some(1), 1, 1, false),
        ] {
            let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
            let admission = SettingAdmission::new(&used, 1<<20, &|| Ok(()));
            let storage = Storage::new(&admission).unwrap();
            let header_span = Span::new(header_start, 3);
            let mut items = Vec::new();
            assert!(storage.push(&mut items, Item {
                kind: ItemKind::Var,
                header: storage.text(&source[header_span.range()]).unwrap(),
                span,
                header_span,
                declaration_cursor: cursor,
                checker_qualifiers: crate::UNKNOWN_HEADER_QUALIFIERS,
                original_outer_terminator: Some(false),
                indent,
                children: Vec::new(),
            }));
            let block = compact_block(items, &source, &storage).unwrap();
            let rows = match &block {
                Block::Narrow { rows, roots: 1 } if narrow => CompactSlice::Narrow(rows),
                Block::Compact { rows, roots: 1 } if !narrow => CompactSlice::Full(rows),
                _ => panic!("unexpected compact geometry"),
            };
            let siblings = OriginalItems(Siblings::Compact { rows, interval: [0, 1], source: &source });
            let row = siblings.get(0).unwrap();
            assert!(row.same_item(siblings.get(0).unwrap()));
            assert_eq!(row.span(), span);
            assert_eq!(row.header_span(), header_span);
            assert_eq!(row.header().as_ptr(), source[header_span.range()].as_ptr());
            assert_eq!(row.declaration_cursor(), cursor);
            assert_eq!(row.indent(), indent);
            assert!(row.children().is_empty());
            drop((block, storage));
            assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
        }
    }

    #[test]
    fn committed_block_falls_back_for_distinct_spelling_and_unavailable_overlap() {
        for altered in [false, true] {
            let source = "/datum/p";
            let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
            let retained = 4096 + 4*size_of::<Item>() + source.len();
            let limit = if altered { 1<<20 } else { retained + size_of::<ShortItem>() - 1 };
            let admission = SettingAdmission::new(&used, crate::SettingChargeCounter::root_allocation_bytes() + (limit), &|| Ok(()));
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
            assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (retained));
            assert!(!admission.is_stopped());
            drop((rows, storage));
            assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
        }
    }
}
