//! Original raw-token records owned by the EXISTING expanded-origin arena.
//! Physical source-row envelope, raw token extent and actual token point are
//! separate facts. No rounded UTF8 token end or PreparedLine is fabricated.
use super::{ExpandedOriginView,OriginView,MacroTraceView,OriginalByteCursor,original_driver::RawSourceDriver,macro_trace_view::OriginalMacroTrace};
use crate::{SourceProvider,SourceAcquisitionLease,SourceAcquisitionIdentity,macro_expansion::{OriginalMacroRows as Rows,OriginalMacroToken as Token}};
use dm_syntax::{Span,SettingAdmission,SettingRootLease};use std::{io,sync::Arc,path::PathBuf};
// Adjacent tokens share only already-authenticated physical row metadata. The
// compact token records remain distinct; grouping never proves a source point.
// A physical encounter can contain many distinct row groups, including
// expansions with different macro traces. Keep its exact acquisition and
// path owner once, independent of those row and trace transitions.
struct Encounter {
    occurrence: usize,
    binding: SourceAcquisitionIdentity,
    path: Arc<PathBuf>,
    region: usize,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct GroupGeometry {
    encounter: usize,
    decoded: Span,
    line: usize,
    output_line: usize,
    output_base: usize,
    raw_base: usize,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Row {
    group: usize,
    output: Span,
    token_end: usize,
    source_offset: usize,
    byte_column: usize,
    raw_extent: Span,
    actual_eof: bool,
}
impl Row {
    fn token_span(&self) -> Span {
        Span::new(self.output.start, self.token_end)
    }

    fn point(&self, line: usize) -> OriginalByteCursor {
        OriginalByteCursor { line, byte_column: self.byte_column, source_offset: self.source_offset }
    }
}
impl Row {
    fn offsets(self, group: GroupGeometry) -> Option<[usize; 6]> {
        let raw_start = self.raw_extent.start.checked_sub(group.raw_base)?;
        if raw_start.checked_add(1)? != self.byte_column {
            return None;
        }
        Some([
            self.output.start.checked_sub(group.output_base)?,
            self.output.end.checked_sub(self.output.start)?,
            self.token_end.checked_sub(self.output.start)?,
            self.source_offset.checked_sub(group.decoded.start)?,
            raw_start,
            self.raw_extent.end.checked_sub(self.raw_extent.start)?,
        ])
    }

    fn from_offsets(group_index: usize, group: GroupGeometry, fields: [usize; 6], actual_eof: bool) -> Option<Self> {
        let [output, cover, token, decoded, raw, raw_width] = fields;
        let output_start = group.output_base.checked_add(output)?;
        let raw_start = group.raw_base.checked_add(raw)?;
        Some(Self {
            group: group_index,
            output: Span::new(output_start, output_start.checked_add(cover)?),
            token_end: output_start.checked_add(token)?,
            source_offset: group.decoded.start.checked_add(decoded)?,
            byte_column: raw.checked_add(1)?,
            raw_extent: Span::new(raw_start, raw_start.checked_add(raw_width)?),
            actual_eof,
        })
    }
}

// Cover differs from token width only by the actual output producer's
// trailing LF on the ordinary path. An arbitrary geometry that does not
// round-trip uses the same medium/full side rows. Raw and decoded offsets
// share an inline byte only after exact equality relative to their own line
// bases. Group ordinals are indexed by the page's exact transition rank.
#[repr(C)]
struct NarrowRow {
    tag: u8,
    fields: [u8; 4],
}
impl NarrowRow {
    const EOF: u8 = 1;
    const TRAILING: u8 = 2;
    const MEDIUM: u8 = 4;
    const FULL: u8 = 8;
    const CLASS: u8 = Self::EOF | Self::MEDIUM | Self::FULL;

    fn pack(row: Row, [output, cover, token, decoded, raw, raw_width]: [usize; 6]) -> Option<Self> {
        let trailing = cover.checked_sub(token)?;
        if trailing > 1 || decoded != raw { return None; }
        let mut fields = [0; 4];
        for (out, value) in fields.iter_mut().zip([output, token, raw, raw_width]) {
            *out = u8::try_from(value).ok()?;
        }
        let tag = (if row.actual_eof { Self::EOF } else { 0 })
            | (if trailing != 0 { Self::TRAILING } else { 0 });
        Some(Self { tag, fields })
    }

    fn escape(class: u8, index: usize) -> Self {
        // Each page contributes at most one side record per cell. Only the
        // page-local index is encoded in the payload.
        assert!(index < ROW_PAGE_LEN);
        let [low, high] = (index as u16).to_le_bytes();
        Self { tag: class, fields: [low, high, 0, 0] }
    }

    fn class(&self) -> u8 { self.tag & Self::CLASS }
    fn escape_index(&self) -> usize {
        usize::from(u16::from_le_bytes([self.fields[0], self.fields[1]]))
    }
    fn offsets(&self) -> [usize; 6] {
        let [output, token, raw, width] = self.fields.map(usize::from);
        [output, token + usize::from(self.tag & Self::TRAILING != 0), token, raw, raw, width]
    }
}

#[repr(C)]
struct MediumRow {
    tag: u32,
    fields: [u16; 6],
}
impl MediumRow {
    const EOF: u32 = 1 << 31;

    fn pack(row: Row, fields: [usize; 6]) -> Option<Self> {
        let group_index = u32::try_from(row.group).ok()?;
        if group_index >= Self::EOF || fields.iter().any(|&value| value > usize::from(u16::MAX)) {
            return None;
        }
        Some(Self {
            tag: group_index | if row.actual_eof { Self::EOF } else { 0 },
            fields: fields.map(|value| value as u16),
        })
    }

    fn unpack(&self, group_at: impl FnOnce(usize) -> Option<GroupGeometry>) -> Option<Row> {
        let group = usize::try_from(self.tag & !Self::EOF).ok()?;
        Row::from_offsets(group, group_at(group)?, self.fields.map(usize::from), self.tag & Self::EOF != 0)
    }
}

use crate::{
    macro_expansion::empty_exact as exact_rows,
    source_arena_credit::{SourceArenaCredit, SourceArenaWork},
};

struct PageFunding<'a> {
    work: &'a dyn SourceArenaWork,
    credit: &'a mut SourceArenaCredit,
}

impl PageFunding<'_> {
    fn allocate<T>(&mut self, capacity: usize, a: &SettingAdmission<'_>) -> io::Result<Vec<T>> {
        let bytes = std::alloc::Layout::array::<T>(capacity)
            .map_err(|_| io::ErrorKind::OutOfMemory)?.size();
        self.work.grow(self.credit, bytes)?;
        match exact_rows(capacity, a) {
            Ok(rows) => Ok(rows),
            Err(first) => {
                // No physical buffer was published; cleanup cannot replace
                // the first actual allocator error.
                let _ = self.work.shrink(self.credit, bytes);
                Err(first)
            }
        }
    }

    fn release<T>(&mut self, rows: Vec<T>) -> io::Result<()> {
        let bytes = rows.capacity() * std::mem::size_of::<T>();
        drop(rows);
        if bytes != 0 { self.work.shrink(self.credit, bytes)?; }
        Ok(())
    }
}

const ROW_PAGE_LEN: usize = 4096;
const _: () = assert!(std::mem::size_of::<NarrowRow>() == 5);
const _: () = assert!(std::mem::size_of::<MediumRow>() == 16);
const _: () = assert!(ROW_PAGE_LEN <= u16::MAX as usize);

type OriginPages<T> = FixedPages<T, ROW_PAGE_LEN>;
type EscapePages<T> = FixedPages<T, 128>;

/// Fixed-size allocations for the same ordered physical records. Ordinals
/// index the directory in constant time; neither trim nor publication flattens.
struct FixedPages<T, const PAGE_LEN: usize> {
    pages: Vec<Vec<T>>,
    len: usize,
}
impl<T, const PAGE_LEN: usize> FixedPages<T, PAGE_LEN> {
    fn new() -> Self {
        Self { pages: Vec::new(), len: 0 }
    }

    fn len(&self) -> usize { self.len }

    fn get(&self, index: usize) -> Option<&T> {
        if index >= self.len { return None; }
        self.pages.as_slice().get(index / PAGE_LEN)?.as_slice().get(index % PAGE_LEN)
    }

    fn get_mut(&mut self, index: usize) -> Option<&mut T> {
        if index >= self.len { return None; }
        self.pages.get_mut(index / PAGE_LEN)?.get_mut(index % PAGE_LEN)
    }

    fn last(&self) -> Option<&T> {
        self.pages.as_slice().last()?.as_slice().last()
    }

    fn push(&mut self, row: T, a: &SettingAdmission<'_>, funding: &mut PageFunding<'_>) -> io::Result<()> {
        a.checkpoint().map_err(|error| a.take_operational_error().unwrap_or(error))?;
        let len = self.len.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
        if self.len % PAGE_LEN == 0 {
            let mut page = funding.allocate(PAGE_LEN, a)?;
            page.push(row);
            if self.pages.len() == self.pages.capacity() {
                let capacity = self.pages.capacity().max(2).checked_mul(2)
                    .ok_or_else(|| io::Error::from(io::ErrorKind::OutOfMemory));
                let mut directory = match capacity.and_then(|n| funding.allocate(n, a)) {
                    Ok(directory) => directory,
                    Err(first) => {
                        let _ = funding.release(page);
                        return Err(first);
                    }
                };
                directory.append(&mut self.pages);
                let old = std::mem::replace(&mut self.pages, directory);
                funding.release(old)?;
            }
            self.pages.push(page);
        } else {
            self.pages.last_mut().expect("issued last origin page").push(row);
        }
        self.len = len;
        Ok(())
    }

    fn partition_point(&self, mut before: impl FnMut(usize, &T) -> bool) -> usize {
        let (mut left, mut right) = (0, self.len);
        while left < right {
            let mid = left + (right - left) / 2;
            if before(mid, self.get(mid).expect("issued origin row ordinal")) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }
        left
    }

    fn truncate(&mut self, len: usize, funding: &mut PageFunding<'_>) -> io::Result<()> {
        assert!(len <= self.len);
        // Drop the actual page allocations first. The directory and the last
        // partial page keep their existing capacity and corresponding charge.
        let keep = len.div_ceil(PAGE_LEN);
        let released = self.pages[keep..].iter().try_fold(0usize, |n, page| {
            page.capacity().checked_mul(std::mem::size_of::<T>())
                .and_then(|bytes| n.checked_add(bytes))
                .ok_or(io::ErrorKind::OutOfMemory)
        })?;
        self.pages.truncate(keep);
        let tail = len % PAGE_LEN;
        if tail != 0 {
            self.pages.last_mut().expect("issued partial origin page").truncate(tail);
        }
        self.len = len;
        if released != 0 { funding.work.shrink(funding.credit, released)?; }
        Ok(())
    }

    #[cfg(test)]
    fn iter(&self) -> impl Iterator<Item = &T> {
        self.pages.as_slice().iter().flat_map(|page| page.as_slice())
    }

    fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        if self.pages.capacity() != 0 {
            visit(self.pages.as_ptr() as usize, self.pages.len(),
                self.pages.capacity() * std::mem::size_of::<Vec<T>>());
        }
        for page in &self.pages {
            visit(page.as_ptr() as usize, page.len(), page.capacity() * std::mem::size_of::<T>());
        }
    }
}

// Group geometry is independent of the exact trace owner run. An inline
// cell shares the raw/decoded line base only after exact equality, and uses
// the physical/output line pair relative to this actual page. The escape
// stores an exact side ordinal, not a lookup or global geometry bound.
#[repr(transparent)]
struct PackedGroup([u32; 4]);
const _: () = assert!(std::mem::size_of::<PackedGroup>() == 16);

impl PackedGroup {
    const ESCAPE: u32 = u16::MAX as u32;

    fn escape(index: usize) -> io::Result<Self> {
        let index = u64::try_from(index).map_err(|_| io::ErrorKind::OutOfMemory)?;
        Ok(Self([Self::ESCAPE, index as u32, (index >> 32) as u32, 0]))
    }

    fn escape_index(&self) -> Option<usize> {
        let [tag, low, high, _] = self.0;
        if tag != Self::ESCAPE { return None; }
        usize::try_from(u64::from(low) | (u64::from(high) << 32)).ok()
    }
}

const TRACE_WORD_BITS: usize = u64::BITS as usize;
const TRACE_WORDS: usize = ROW_PAGE_LEN / TRACE_WORD_BITS;
const TRACE_DIRECTORY_PAGE_LEN: usize = 16;
const _: () = assert!(ROW_PAGE_LEN % TRACE_WORD_BITS == 0 && ROW_PAGE_LEN <= u16::MAX as usize);

// The bit marks a new exact owner. The per-word prefix and full-width page
// base locate the actual run with one masked popcount and no search.
struct GroupTracePage {
    before_page: usize,
    output_line_base: usize,
    bits: [u64; TRACE_WORDS],
    before_word: [u16; TRACE_WORDS],
}

impl GroupTracePage {
    fn new(before_page: usize, output_line_base: usize) -> Self {
        Self { before_page, output_line_base, bits: [0; TRACE_WORDS], before_word: [0; TRACE_WORDS] }
    }

    fn append(&mut self, index: usize, before: usize, changed: bool) {
        let word = index / TRACE_WORD_BITS;
        let bit = index % TRACE_WORD_BITS;
        if bit == 0 {
            self.before_word[word] = u16::try_from(before - self.before_page)
                .expect("page-relative run count");
        }
        if changed { self.bits[word] |= 1u64 << bit; }
    }

    fn run(&self, index: usize) -> Option<usize> {
        let word = index / TRACE_WORD_BITS;
        let bit = index % TRACE_WORD_BITS;
        let through = u64::MAX >> (TRACE_WORD_BITS - 1 - bit);
        self.before_page
            .checked_add(usize::from(self.before_word[word]))?
            .checked_add((self.bits[word] & through).count_ones() as usize)?
            .checked_sub(1)
    }

    fn truncate(&mut self, keep: usize) {
        let word = keep / TRACE_WORD_BITS;
        let bit = keep % TRACE_WORD_BITS;
        if bit == 0 {
            self.bits[word..].fill(0);
        } else {
            self.bits[word] &= (1u64 << bit) - 1;
            self.bits[word + 1..].fill(0);
        }
        // A later append reissues each word's count at its first bit.
    }
}
impl GroupGeometry {
    fn pack(self, output_line_base: usize) -> Option<PackedGroup> {
        if self.raw_base != self.decoded.start { return None; }
        let encounter = u16::try_from(self.encounter).ok()?;
        if encounter == u16::MAX { return None; }
        let width = u16::try_from(self.decoded.end.checked_sub(self.decoded.start)?).ok()?;
        let line = u16::try_from(self.line).ok()?;
        let output_line = u16::try_from(self.output_line.checked_sub(output_line_base)?).ok()?;
        Some(PackedGroup([
            u32::from(encounter) | (u32::from(width) << 16),
            u32::try_from(self.decoded.start).ok()?,
            u32::try_from(self.output_base).ok()?,
            u32::from(line) | (u32::from(output_line) << 16),
        ]))
    }

    fn unpack(packed: &PackedGroup, output_line_base: usize) -> Option<Self> {
        let [encounter_width, start, output_base, lines] = packed.0;
        let encounter = encounter_width as u16;
        if encounter == u16::MAX { return None; }
        let start = usize::try_from(start).ok()?;
        let end = start.checked_add((encounter_width >> 16) as usize)?;
        Some(Self {
            encounter: usize::from(encounter), decoded: Span::new(start, end),
            line: usize::from(lines as u16),
            output_line: output_line_base.checked_add((lines >> 16) as usize)?,
            output_base: usize::try_from(output_base).ok()?,
            raw_base: start,
        })
    }
}

struct OriginGroups {
    packed: OriginPages<PackedGroup>,
    full: EscapePages<(usize, GroupGeometry)>,
    trace_pages: FixedPages<GroupTracePage, TRACE_DIRECTORY_PAGE_LEN>,
    traces: EscapePages<OriginalMacroTrace>,
}
impl OriginGroups {
    fn new() -> Self {
        Self {
            packed: OriginPages::new(), full: EscapePages::new(),
            trace_pages: FixedPages::new(), traces: EscapePages::new(),
        }
    }

    fn len(&self) -> usize {
        self.packed.len()
    }

    fn trace_run(&self, ordinal: usize) -> Option<usize> {
        self.trace_pages.get(ordinal / ROW_PAGE_LEN)?.run(ordinal % ROW_PAGE_LEN)
    }

    fn get(&self, ordinal: usize) -> Option<(GroupGeometry, &OriginalMacroTrace)> {
        Some((self.geometry(ordinal)?, self.traces.get(self.trace_run(ordinal)?)?))
    }

    fn geometry(&self, ordinal: usize) -> Option<GroupGeometry> {
        let packed = self.packed.get(ordinal)?;
        if let Some(index) = packed.escape_index() {
            return self.full.get(index).filter(|(at, _)| *at == ordinal).map(|(_, geometry)| *geometry);
        }
        let page = self.trace_pages.get(ordinal / ROW_PAGE_LEN)?;
        GroupGeometry::unpack(packed, page.output_line_base)
    }

    fn last(&self) -> Option<(GroupGeometry, &OriginalMacroTrace)> {
        Some((self.geometry(self.len().checked_sub(1)?)?, self.traces.last()?))
    }

    fn push(
        &mut self, geometry: GroupGeometry, trace: OriginalMacroTrace,
        a: &SettingAdmission<'_>, funding: &mut PageFunding<'_>,
    ) -> io::Result<()> {
        let ordinal = self.len();
        let previous_full = self.full.len();
        let previous_pages = self.trace_pages.len();
        let before = self.traces.len();
        let changed = self.traces.last().is_none_or(|prior| !prior.same_owner(&trace));
        let new_page = ordinal % ROW_PAGE_LEN == 0;
        let output_line_base = if new_page {
            geometry.output_line
        } else {
            self.trace_pages.get(ordinal / ROW_PAGE_LEN)
                .expect("issued group trace rank page").output_line_base
        };
        let result = (|| {
            let cell = match geometry.pack(output_line_base) {
                Some(cell) => cell,
                None => {
                    let cell = PackedGroup::escape(previous_full)?;
                    self.full.push((ordinal, geometry), a, funding)?;
                    cell
                }
            };
            if new_page {
                self.trace_pages.push(GroupTracePage::new(before, output_line_base), a, funding)?;
            }
            if changed {
                self.traces.push(trace, a, funding)?;
            }
            self.packed.push(cell, a, funding)
        })();
        if let Err(first) = result {
            // No trace bit has been published. Drop only rows added by this
            // attempt and never replace the first original allocation error.
            let _ = self.full.truncate(previous_full, funding);
            let _ = self.traces.truncate(before, funding);
            let _ = self.trace_pages.truncate(previous_pages, funding);
            return Err(first);
        }
        self.trace_pages.get_mut(ordinal / ROW_PAGE_LEN).expect("issued trace rank page")
            .append(ordinal % ROW_PAGE_LEN, before, changed);
        Ok(())
    }

    fn truncate(&mut self, len: usize, funding: &mut PageFunding<'_>) -> io::Result<()> {
        if len == self.len() { return Ok(()); }
        let full = self.full.partition_point(|_, (at, _)| *at < len);
        let traces = match len.checked_sub(1) {
            Some(last) => self.trace_run(last).and_then(|run| run.checked_add(1)).ok_or(io::ErrorKind::InvalidData)?,
            None => 0,
        };
        let pages = len.div_ceil(ROW_PAGE_LEN);
        self.packed.truncate(len, funding)?;
        self.full.truncate(full, funding)?;
        self.traces.truncate(traces, funding)?;
        self.trace_pages.truncate(pages, funding)?;
        let tail = len % ROW_PAGE_LEN;
        if tail != 0 {
            self.trace_pages.get_mut(pages - 1).expect("issued partial trace rank page").truncate(tail);
        }
        Ok(())
    }

    #[cfg(test)]
    fn iter(&self) -> impl Iterator<Item = &PackedGroup> {
        self.packed.iter()
    }

    fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        self.packed.visit_storage(&mut visit);
        self.full.visit_storage(&mut visit);
        self.trace_pages.visit_storage(&mut visit);
        self.traces.visit_storage(visit);
    }

    #[cfg(debug_assertions)]
    fn trace_capacity(&self) -> (usize, usize, usize) {
        let (mut rank_bytes, mut run_bytes) = (0usize, 0usize);
        self.trace_pages.visit_storage(|_, _, bytes| rank_bytes = rank_bytes.saturating_add(bytes));
        self.traces.visit_storage(|_, _, bytes| run_bytes = run_bytes.saturating_add(bytes));
        (self.traces.len(), rank_bytes, run_bytes)
    }
}

#[derive(Clone, Copy)]
struct RowPageBase {
    group: usize,
    medium: usize,
    full: usize,
}

// Each successfully published row stays in the preceding group or starts
// its immediate successor. Rank counts transitions through an ordinal,
// including transitions introduced by medium/full cells.
struct RowGroupRank {
    bits: [u64; TRACE_WORDS],
    before_word: [u16; TRACE_WORDS],
}
impl RowGroupRank {
    fn new() -> Self { Self { bits: [0; TRACE_WORDS], before_word: [0; TRACE_WORDS] } }

    fn append(&mut self, index: usize, before: usize, changed: bool) {
        let word = index / TRACE_WORD_BITS;
        let bit = index % TRACE_WORD_BITS;
        if bit == 0 {
            self.before_word[word] = u16::try_from(before).expect("page-local group count");
        }
        if changed { self.bits[word] |= 1u64 << bit; }
    }

    fn through(&self, index: usize) -> usize {
        let word = index / TRACE_WORD_BITS;
        let bit = index % TRACE_WORD_BITS;
        let through = u64::MAX >> (TRACE_WORD_BITS - 1 - bit);
        usize::from(self.before_word[word]) + (self.bits[word] & through).count_ones() as usize
    }

    fn truncate(&mut self, keep: usize) {
        let word = keep / TRACE_WORD_BITS;
        let bit = keep % TRACE_WORD_BITS;
        if bit == 0 {
            self.bits[word..].fill(0);
        } else {
            self.bits[word] &= (1u64 << bit) - 1;
            self.bits[word + 1..].fill(0);
        }
        // Append reissues the count at the start of each discarded word.
    }
}

struct RawTokenRows {
    narrow: OriginPages<NarrowRow>,
    bases: Rows<RowPageBase>,
    ranks: FixedPages<RowGroupRank, TRACE_DIRECTORY_PAGE_LEN>,
    medium: EscapePages<MediumRow>,
    full: EscapePages<Row>,
    last_group: Option<usize>,
}
impl RawTokenRows {
    fn new(a: &SettingAdmission<'_>) -> io::Result<Self> {
        Ok(Self {
            narrow: OriginPages::new(),
            bases: Rows::new(a)?,
            ranks: FixedPages::new(),
            medium: EscapePages::new(),
            full: EscapePages::new(),
            last_group: None,
        })
    }

    fn len(&self) -> usize { self.narrow.len() }

    fn push(&mut self, row: Row, group: GroupGeometry, a: &SettingAdmission<'_>, funding: &mut PageFunding<'_>) -> io::Result<()> {
        let ordinal = self.len();
        let new_page = ordinal % ROW_PAGE_LEN == 0;
        let prior_group = self.last_group.unwrap_or(row.group);
        if row.group != prior_group && prior_group.checked_add(1) != Some(row.group) {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "origin row skipped its actual group"));
        }
        let medium_before = self.medium.len();
        let full_before = self.full.len();
        let ranks_before = self.ranks.len();
        let base = if new_page {
            let base = RowPageBase { group: row.group, medium: medium_before, full: full_before };
            self.bases.push(base, a)?;
            base
        } else {
            *self.bases.as_slice().last().expect("issued origin row page base")
        };
        let result = (|| {
            let fields = row.offsets(group);
            let cell = if let Some(narrow) = fields.and_then(|fields| NarrowRow::pack(row, fields)) {
                narrow
            } else if let Some(medium) = fields.and_then(|fields| MediumRow::pack(row, fields)) {
                let cell = NarrowRow::escape(NarrowRow::MEDIUM, medium_before - base.medium);
                self.medium.push(medium, a, funding)?;
                cell
            } else {
                let cell = NarrowRow::escape(NarrowRow::FULL, full_before - base.full);
                self.full.push(row, a, funding)?;
                cell
            };
            if new_page { self.ranks.push(RowGroupRank::new(), a, funding)?; }
            self.narrow.push(cell, a, funding)
        })();
        if let Err(first) = result {
            let _ = self.medium.truncate(medium_before, funding);
            let _ = self.full.truncate(full_before, funding);
            let _ = self.ranks.truncate(ranks_before, funding);
            if new_page { self.bases.pop(); }
            return Err(first);
        }
        let before = if new_page { 0 } else { prior_group - base.group };
        self.ranks.get_mut(ordinal / ROW_PAGE_LEN).expect("issued origin row group rank")
            .append(ordinal % ROW_PAGE_LEN, before, !new_page && row.group != prior_group);
        self.last_group = Some(row.group);
        Ok(())
    }

    fn group_at(&self, ordinal: usize) -> Option<usize> {
        if ordinal >= self.len() { return None; }
        let page = ordinal / ROW_PAGE_LEN;
        let base = self.bases.as_slice().get(page)?;
        base.group.checked_add(self.ranks.get(page)?.through(ordinal % ROW_PAGE_LEN))
    }

    fn decode(&self, ordinal: usize, cell: &NarrowRow, groups: &OriginGroups) -> Option<Row> {
        let base = self.bases.as_slice().get(ordinal / ROW_PAGE_LEN)?;
        let group = self.group_at(ordinal)?;
        let row = match cell.class() {
            NarrowRow::MEDIUM => self.medium.get(base.medium.checked_add(cell.escape_index())?)?
                .unpack(|actual| if actual == group { groups.geometry(group) } else { None }),
            NarrowRow::FULL => self.full.get(base.full.checked_add(cell.escape_index())?).copied(),
            class => Row::from_offsets(group, groups.geometry(group)?, cell.offsets(), class == NarrowRow::EOF),
        }?;
        (row.group == group).then_some(row)
    }

    fn get(&self, ordinal: usize, groups: &OriginGroups) -> Option<Row> {
        self.narrow.get(ordinal).map(|cell| {
            self.decode(ordinal, cell, groups).expect("issued raw origin cell coordinates")
        })
    }

    fn partition_point(&self, groups: &OriginGroups, mut before: impl FnMut(Row) -> bool) -> usize {
        self.narrow.partition_point(|ordinal, cell| {
            before(self.decode(ordinal, cell, groups).expect("issued raw origin cell coordinates"))
        })
    }

    fn truncate(&mut self, keep: usize, funding: &mut PageFunding<'_>) -> io::Result<()> {
        assert!(keep <= self.len());
        if keep == self.len() { return Ok(()); }
        // Page bases are the count before that page. Only its retained prefix
        // must be inspected to find the side-table suffixes to release.
        let last_group = match keep.checked_sub(1) {
            Some(last) => Some(self.group_at(last).ok_or(io::ErrorKind::InvalidData)?),
            None => None,
        };
        let page = keep / ROW_PAGE_LEN;
        let RowPageBase { mut medium, mut full, .. } = self.bases.as_slice()[page];
        for cell in &self.narrow.pages.as_slice()[page].as_slice()[..keep % ROW_PAGE_LEN] {
            match cell.class() {
                NarrowRow::MEDIUM => medium += 1,
                NarrowRow::FULL => full += 1,
                _ => {}
            }
        }
        let pages = keep.div_ceil(ROW_PAGE_LEN);
        self.narrow.truncate(keep, funding)?;
        self.bases.truncate(pages);
        self.ranks.truncate(pages, funding)?;
        let tail = keep % ROW_PAGE_LEN;
        if tail != 0 {
            self.ranks.get_mut(pages - 1).expect("issued partial row group rank").truncate(tail);
        }
        self.medium.truncate(medium, funding)?;
        self.full.truncate(full, funding)?;
        self.last_group = last_group;
        Ok(())
    }

    fn visit_compact_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        self.narrow.visit_storage(&mut visit);
        self.bases.visit_allocation(|pointer, bytes| visit(pointer, self.bases.len(), bytes));
        self.ranks.visit_storage(&mut visit);
        self.medium.visit_storage(&mut visit);
    }

    fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        self.visit_compact_storage(&mut visit);
        self.full.visit_storage(&mut visit);
    }
}

// Optional, allocation-free counts at the actual successful append. Used only
// by the producer failure report, before receiver trim discards lookahead.
#[cfg(debug_assertions)]
#[derive(Debug, Default)]
pub(super) struct RawRowGeometryCensus {
    previous_group: Option<usize>,
    group_jumps: usize,
    // Every array is [inline, medium, full], including the existing layout.
    current: [usize; 3],
    six_byte: [usize; 3],
    five_byte: [usize; 3],
    // [inline, full] under the 16-byte group shape. The base is reset on
    // each real group page, even if its first cell needs a full escape.
    group_16_byte: [usize; 2],
    group_count: usize,
    group_output_line_base: usize,
}

#[cfg(debug_assertions)]
impl RawRowGeometryCensus {
    fn observe_group(&mut self, geometry: GroupGeometry) {
        if self.group_count % ROW_PAGE_LEN == 0 {
            self.group_output_line_base = geometry.output_line;
        }
        self.group_count = self.group_count.saturating_add(1);
        let inline = geometry.raw_base == geometry.decoded.start
            && geometry.encounter < usize::from(u16::MAX)
            && geometry.decoded.end.checked_sub(geometry.decoded.start).is_some_and(|width| u16::try_from(width).is_ok())
            && u32::try_from(geometry.decoded.start).is_ok()
            && u32::try_from(geometry.output_base).is_ok()
            && u16::try_from(geometry.line).is_ok()
            && geometry.output_line.checked_sub(self.group_output_line_base).is_some_and(|delta| u16::try_from(delta).is_ok());
        let count = &mut self.group_16_byte[usize::from(!inline)];
        *count = count.saturating_add(1);
    }

    fn observe(&mut self, row: Row, geometry: GroupGeometry, page_base: usize) {
        if self.previous_group.is_some_and(|prior| row.group != prior && prior.checked_add(1) != Some(row.group)) {
            self.group_jumps = self.group_jumps.saturating_add(1);
        }
        self.previous_group = Some(row.group);
        let fields = row.offsets(geometry);
        let fallback = if fields.is_some_and(|fields| MediumRow::pack(row, fields).is_some()) { 1 } else { 2 };
        let current = fields.is_some_and(|fields| {
            row.group.checked_sub(page_base).is_some_and(|delta| delta < (1 << 14))
                && fields.into_iter().all(|value| value <= usize::from(u8::MAX))
        });
        let six = fields.is_some_and(|[output, cover, token, decoded, raw, width]| {
            cover.checked_sub(token).is_some_and(|trailing| trailing <= 1)
                && [output, token, decoded, raw, width].into_iter().all(|value| value <= usize::from(u8::MAX))
        });
        let five = six && fields.is_some_and(|[_, _, _, decoded, raw, _]| decoded == raw);
        for (counts, eligible) in [(&mut self.current, current), (&mut self.six_byte, six), (&mut self.five_byte, five)] {
            let count = &mut counts[if eligible { 0 } else { fallback }];
            *count = count.saturating_add(1);
        }
    }
}

pub(super) struct OriginalRawOrigins{
 #[cfg(debug_assertions)]
 row_geometry_census:Option<RawRowGeometryCensus>,
 rows:RawTokenRows,groups:OriginGroups,encounters:Rows<Encounter>,nonphysical:Rows<Span>,output:Option<super::original_prepared_output::OriginalOutputIdentity>,delivery_sealed:bool,domain:SettingRootLease,page_credit:SourceArenaCredit}
impl std::fmt::Debug for OriginalRawOrigins{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("OriginalRawOrigins").field("rows",&self.rows.len()).finish()}}
impl OriginalRawOrigins{
 pub(super) fn new(a:&SettingAdmission<'_>,work:&dyn SourceArenaWork)->io::Result<Self>{Ok(Self{
  #[cfg(debug_assertions)]
  row_geometry_census:std::env::var_os("DMB_ORIGINAL_TRACE_ROW_GEOMETRY").map(|_|RawRowGeometryCensus::default()),
  rows:RawTokenRows::new(a)?,groups:OriginGroups::new(),encounters:Rows::new(a)?,nonphysical:Rows::new(a)?,output:None,delivery_sealed:false,domain:a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?,page_credit:work.reserve(0)?})}
 /// The actual controller records once beside its final arena append. The
 /// private actual raw stack authenticates current occurrence/binding/point;
 /// the supplied source path and region come from that SAME DirectivePlan.
 pub(super) fn append_actual_using(&mut self,actual:&Token<'_>,token:Span,output_cover:Span,output_line:usize,region:usize,path:Arc<PathBuf>,trace:OriginalMacroTrace,lease:&SourceAcquisitionLease,provider:&dyn SourceProvider,inputs:&mut RawSourceDriver,a:&SettingAdmission<'_>,work:&dyn SourceArenaWork)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
  if self.delivery_sealed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"delivered origin rows are already finalized"))}
  if !self.is_admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}
  if token.start>=token.end||output_cover.start!=token.start||output_cover.end<token.end||self.row(self.rows.len().saturating_sub(1)).is_some_and(|row|row.output.end>output_cover.start){return Err(io::ErrorKind::InvalidInput.into())}
  let source=inputs.physical_row_using(actual.origin,lease,provider,a)?;
  match (&actual.lexical_frame,actual.lexical_span){(Some(frame),Some(_)) if frame.admitted_by(a)=>(),(None,None)=>(),_=>return Err(io::ErrorKind::InvalidData.into())};
  // Check every authority component even when reusing an encounter.
  // Never identify a source acquisition by its spelling or region alone.
  let share_encounter = self.encounters.as_slice().last().is_some_and(|last| {
   last.occurrence == actual.origin.occurrence && last.binding.matches(lease)
    && last.region == region && Arc::ptr_eq(&last.path, &path)
  });
  let share_group = share_encounter && self.groups.last().is_some_and(|(last, prior_trace)| {
   last.decoded == source.decoded && last.raw_base == source.raw.start
    && last.line == source.point.line && last.output_line == output_line
    && prior_trace.same_owner(&trace)
  });
  if !share_encounter {
   self.encounters.push(Encounter {
    occurrence: actual.origin.occurrence, binding: lease.identity(), path, region,
   }, a)?;
  }
  let mut funding = PageFunding { work, credit: &mut self.page_credit };
  if !share_group {
   let group = GroupGeometry {
    encounter: self.encounters.len() - 1, decoded: source.decoded,
    line: source.point.line, output_line, output_base: output_cover.start,
    raw_base: source.raw.start,
   };
   if let Err(error) = self.groups.push(group, trace, a, &mut funding) {
    if !share_encounter { self.encounters.pop(); }
    return Err(error);
   }
  }
  let group = self.groups.len() - 1;
  // Group sharing already requires the same source line, and validation
  // above requires the token and output cover to start at the same byte.
  let row=Row{
   group, output:output_cover, token_end:token.end, source_offset:source.point.source_offset,
   byte_column:source.point.byte_column, raw_extent:actual.origin.physical, actual_eof:source.actual_eof,
  };
  let geometry = self.groups.geometry(group).expect("issued origin group ordinal");
  let result = self.rows.push(row, geometry, a, &mut funding);
  #[cfg(debug_assertions)]
  if result.is_ok() {
   if let Some(census)=&mut self.row_geometry_census {
    if !share_group { census.observe_group(geometry); }
    census.observe(row,geometry,self.rows.bases.as_slice().last().expect("issued origin row page").group);
   }
  }
  if result.is_err() {
   if !share_group { let _ = self.groups.truncate(self.groups.len() - 1, &mut funding); }
   if !share_encounter { self.encounters.pop(); }
  }
  result
 }

 fn row(&self, index: usize) -> Option<Row> {
  self.rows.get(index, &self.groups)
 }

 /// The actual runner binds even an empty stream from its SAME cursor's zero
 /// receipt before lending that producer. No numeric offset issues this owner.
 pub(super) fn bind_output_using(&mut self,initial:&super::original_prepared_output::OriginalDeliveryFrontier,a:&SettingAdmission<'_>)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if self.delivery_sealed||(self.rows.len()!=0||self.nonphysical.len()!=0)||initial.end()!=0||!self.is_admitted_by(a)||!initial.owner().admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}
  match &self.output{Some(owner)if !initial.belongs_to(owner)=>Err(io::ErrorKind::InvalidInput.into()),Some(_)=>Ok(()),None=>{self.output=Some(initial.owner().clone());Ok(())}}
 }
 /// Actual token/interval/line belong to ONE prepared-output record. Pointer
 /// comparison authenticates those two private callback arguments only; source
 /// geometry is independently checked by the SAME raw frame/lease below.
 pub(super) fn append_produced_using(&mut self,actual:&Token<'static>,produced:super::original_prepared_output::OriginalProducedSpan<'_>,region:usize,path:Arc<PathBuf>,trace:OriginalMacroTrace,lease:&SourceAcquisitionLease,provider:&dyn SourceProvider,inputs:&mut RawSourceDriver,a:&SettingAdmission<'_>,work:&dyn SourceArenaWork)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
  let owner=self.output.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"origin owner lacks its actual output cursor"))?;
  if !owner.same(produced.owner())||!produced.owner().admitted_by(a)||!std::ptr::eq(actual,produced.actual()?){return Err(io::Error::new(io::ErrorKind::InvalidInput,"origin arguments differ from the SAME prepared token"))}
  self.append_actual_using(actual,produced.token().span,produced.cover(),produced.output_line(),region,path,trace,lease,provider,inputs,a,work)
 }
 /// Only the receiver's actual complete-append receipt can discard producer
 /// lookahead mappings. Acquisitions/notices/history remain genuine lookahead
 /// DATA; trimming mappings cannot grant primary/model/physical EOF.
 /// Authentic receiver coverage for a SAME issued default delimiter. It has
 /// no physical source row/line/column/token extent and is never returned by
 /// geometry/get/point as an origin or CODE grant.
 pub(super) fn append_default_semicolon_using(&mut self,produced:super::original_prepared_output::OriginalProducedSpan<'_>,a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;let owner=self.output.as_ref().ok_or(io::ErrorKind::InvalidInput)?;if self.delivery_sealed||!self.is_admitted_by(a)||!owner.same(produced.owner())||!produced.owner().admitted_by(a)||!produced.is_default_semicolon()||self.rows.len()!=0||self.nonphysical.len()!=0||produced.cover().start!=0{return Err(io::ErrorKind::InvalidInput.into())}self.nonphysical.push(produced.cover(),a)}
 pub(super) fn retain_delivered_using(&mut self,delivered:&super::original_prepared_output::OriginalDeliveryFrontier,a:&SettingAdmission<'_>,work:&dyn SourceArenaWork)->io::Result<usize>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;let owner=self.output.as_ref().ok_or(io::ErrorKind::InvalidInput)?;
  if self.delivery_sealed||!self.is_admitted_by(a)||!delivered.belongs_to(owner)||!delivered.owner().admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}
  let keep=self.rows.partition_point(&self.groups, |row|row.output.end<=delivered.end());
  let last=keep.checked_sub(1).and_then(|index|self.row(index));
  if delivered.end()!=0&&last.is_none_or(|row|row.output.end!=delivered.end())&&!self.nonphysical.as_slice().iter().any(|cover|cover.end==delivered.end()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"delivery receipt is not an actual recorded complete cover"))}
  let (groups, encounters) = match last {
   Some(row) => {
    let group = self.groups.geometry(row.group).ok_or(io::ErrorKind::InvalidData)?;
    (row.group.checked_add(1).ok_or(io::ErrorKind::InvalidData)?,
     group.encounter.checked_add(1).ok_or(io::ErrorKind::InvalidData)?)
   }
   None => (0, 0),
  };
  let mut funding=PageFunding{work,credit:&mut self.page_credit};self.rows.truncate(keep,&mut funding)?;self.groups.truncate(groups,&mut funding)?;self.encounters.truncate(encounters);let nonphysical=self.nonphysical.as_slice().partition_point(|cover|cover.end<=delivered.end());self.nonphysical.truncate(nonphysical);self.delivery_sealed=true;Ok(keep)
 }
 #[cfg(debug_assertions)]
 pub(super) fn trace_capacity(&self) -> (usize, usize, usize, usize, usize, usize) {
  let (mut compact_bytes, mut full_bytes, mut group_bytes) = (0usize, 0usize, 0usize);
  self.rows.visit_compact_storage(|_, _, capacity| compact_bytes = compact_bytes.saturating_add(capacity));
  self.rows.full.visit_storage(|_, _, capacity| full_bytes = full_bytes.saturating_add(capacity));
  self.groups.visit_storage(|_, _, capacity| group_bytes = group_bytes.saturating_add(capacity));
  (self.rows.len(), compact_bytes, self.groups.len(), group_bytes, self.encounters.len(), full_bytes)
 }
 #[cfg(debug_assertions)]
 pub(super) fn trace_run_capacity(&self) -> (usize, usize, usize) { self.groups.trace_capacity() }
 #[cfg(debug_assertions)]
 pub(super) fn trace_row_geometry_census(&self)->Option<&RawRowGeometryCensus>{self.row_geometry_census.as_ref()}
 pub(super) fn has_delivered_binding(&self)->bool{self.output.is_some()&&self.delivery_sealed}
 #[cfg(debug_assertions)]
 pub(super) fn source_page_bytes(&self)->usize{self.page_credit.reserved_bytes()}
 pub(super) fn is_admitted_by(&self,a:&SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.domain)}
 pub(super) fn geometry(&self,index:usize)->Option<(usize,OriginalByteCursor,Span,Span,bool)>{
  let row=self.row(index)?;
  let group=self.groups.geometry(row.group)?;
  let encounter = self.encounters.as_slice().get(group.encounter)?;
  Some((encounter.occurrence,row.point(group.line),row.token_span(),row.raw_extent,row.actual_eof))
 }
 pub(super) fn equivalent(&self,other:&Self)->bool{self.len()==other.len()&&self.nonphysical.as_slice()==other.nonphysical.as_slice()&&(0..self.len()).all(|index|self.geometry(index)==other.geometry(index))}
 pub(super) fn len(&self)->usize{self.rows.len()}
 pub(super) fn get(&self,index:usize)->Option<ExpandedOriginView<'_>>{
  let row = self.row(index)?;
  let (group, trace) = self.groups.get(row.group)?;
  let encounter = self.encounters.as_slice().get(group.encounter)?;
  Some(ExpandedOriginView {
   origin: OriginView { output_line: group.output_line, path: &encounter.path, source_line: group.line },
   output_span: row.output, source_span: group.decoded, region: encounter.region,
   macro_expansions: MacroTraceView::original(trace),
  })
 }
 /// Exact point projection only. Expanded grammar offsets inside a transformed
 /// token must never be mistaken for original source-byte deltas. Genuine raw
 /// EOF additionally lends its actual terminal point at the output boundary.
 pub(super) fn point(&self,index:usize,occurrence:usize,lease:&SourceAcquisitionLease,offset:usize)->Result<OriginalByteCursor,&'static str>{
  let row=self.row(index).ok_or("actual raw origin row absent")?;let group=self.groups.geometry(row.group).ok_or("actual raw origin metadata absent")?;let encounter=self.encounters.as_slice().get(group.encounter).ok_or("actual raw origin encounter absent")?;if encounter.occurrence!=occurrence||!encounter.binding.matches(lease){return Err("actual raw origin belongs to another source acquisition or occurrence")}
  if offset!=row.output.start&&!(row.actual_eof&&(offset==row.token_end||offset==row.output.end)){return Err("expanded byte has no exact issued raw token point")}
  Ok(row.point(group.line))
 }
 pub(super) fn source_end_at(&self,index:usize,offset:usize)->bool{self.row(index).is_some_and(|row|row.actual_eof&&(offset==row.output.start||offset==row.token_end||offset==row.output.end))}
 pub(super) fn policy_line(&self,index:usize,occurrence:usize,lease:&SourceAcquisitionLease,offset:usize)->Result<usize,&'static str>{let row=self.row(index).ok_or("actual raw origin row absent")?;let group=self.groups.geometry(row.group).ok_or("actual raw origin metadata absent")?;let encounter=self.encounters.as_slice().get(group.encounter).ok_or("actual raw origin encounter absent")?;if encounter.occurrence!=occurrence||!encounter.binding.matches(lease)||offset<row.output.start||offset>=row.output.end{return Err("actual raw policy point belongs to another input or interval")}Ok(group.line)}
 pub(super) fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
  self.nonphysical.visit_allocation(|p,n|visit(p,self.nonphysical.len()*std::mem::size_of::<Span>(),n));
  if let Some(output)=&self.output{output.visit_storage(&mut visit);}
  self.rows.visit_storage(&mut visit);self.groups.visit_storage(&mut visit);self.domain.visit_counter_storage(|p,n|visit(p,n,n));self.encounters.visit_allocation(|p,n|visit(p,self.encounters.len(),n));for encounter in self.encounters.as_slice(){encounter.binding.visit_storage(|storage|if let crate::source_acquisition::AcquisitionStorage::Object{address,bytes}=storage{visit(address,1,bytes)});}
  self.page_credit.visit_storage(&mut |pointer,bytes|visit(pointer,1,bytes));
 }
}

#[cfg(test)]mod tests{
 use super::*;use super::super::{original_driver::{DriverEvent,LogicalToken},original_raw_inputs::OriginalRawNoticeSink,original_macro_source::OriginalMacroHost,original_output_queue::OriginalOutputQueue,original_ordinary_output::OriginalOrdinaryOutput};
 use crate::{InitialEnvironment,macro_expansion::{OriginalMacroOrigin as Origin,OriginalMacroValue as Value,OriginalMacroNotice as MacroNotice}};
 use std::{path::Path,sync::{atomic::{AtomicUsize,Ordering},Arc}};
 struct File{raw:Vec<u8>,lease:SourceAcquisitionLease}
 impl File{fn new(raw:&[u8])->Self{Self{raw:raw.to_vec(),lease:SourceAcquisitionLease::from_raw_original_bytes(raw.to_vec(),17u64)}}}
 impl SourceProvider for File{
  fn initial_environment(&self)->InitialEnvironment{InitialEnvironment::OriginalChecker0290}
  fn read(&self,_:&Path)->Result<String,String>{panic!("raw mapping must not read/prepare another source")}
  fn original_source_bytes<'a>(&'a self,lease:&'a SourceAcquisitionLease)->io::Result<Option<&'a[u8]>>{if !lease.same_original_acquisition(&self.lease){return Err(io::ErrorKind::InvalidInput.into())}Ok(Some(&self.raw))}
 }
 struct Notices;
 impl OriginalRawNoticeSink for Notices{
  fn lexical(&mut self,_:&super::super::OriginalLexicalFrameIdentity,_:usize,_:super::super::original_raw_points::OriginalRawPoint,_:super::super::original_raw_frame::OriginalRawNotice,_:&SettingAdmission<'_>)->io::Result<()>{panic!("valid fixture has no lexical notice")}
  fn numeric(&mut self,_:&super::super::OriginalLexicalFrameIdentity,_:usize,_:super::super::original_raw_points::OriginalRawPoint,_:dm_syntax::OriginalLexicalNoticePoint,_:dm_syntax::numeric_form::OriginalNumberNotice<'_>,_:&SettingAdmission<'_>)->io::Result<()>{panic!("valid fixture has no numeric notice")}
 }
 struct Host{ordinary:OriginalOrdinaryOutput}
 impl OriginalMacroHost for Host{
  fn before_identifier(&mut self,name:&str,origin:Origin,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<()>{self.ordinary.before_identifier(name,origin,queue,a)}
  fn ordinary_token(&mut self,token:Token<'static>,queue:&mut OriginalOutputQueue<'static>,a:&SettingAdmission<'_>)->io::Result<()>{self.ordinary.ordinary_token(token,queue,a)}
  fn direct_noncall_output(&mut self,token:&Token<'static>,a:&SettingAdmission<'_>)->io::Result<()>{self.ordinary.direct_noncall_output(token,a)}
  fn dynamic(&mut self,_:bool,_:Origin,_:Option<usize>,_:Option<Origin>,_:&SettingAdmission<'_>)->io::Result<Token<'static>>{panic!("fixture has no dynamic macro")}
  fn invocation(&mut self,_:&str,_:Origin,_:&SettingAdmission<'_>)->io::Result<()>{Ok(())}
 }
 fn driver(a:&SettingAdmission<'_>)->RawSourceDriver{RawSourceDriver::new(InitialEnvironment::OriginalChecker0290,&std::collections::BTreeMap::new(),a,&mut|definition,a|super::super::original_token_factory::initial_definition_using(definition,a,&mut|_|panic!("fixed definitions have no lexical notice"),&mut|_,_|panic!("fixed definitions have no numeric notice"))).unwrap()}
 fn next(source:&mut RawSourceDriver,file:&File,host:&mut Host,a:&SettingAdmission<'_>)->Option<Token<'static>>{
  loop{match source.next_logical_using(file,&mut Notices,host,a).unwrap(){DriverEvent::Token(LogicalToken::Actual(token))=>return Some(token),DriverEvent::Token(LogicalToken::Delimiter{spelling,location})=>return Some(Token{value:Value::Punct(spelling),origin:location.expect("actual fixture delimiter point"),string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None}),DriverEvent::ActualEnd=>return None,DriverEvent::NeedInput=>continue,_=>panic!("fixture has no directives or notices")}}
 }
 #[test]fn actual_raw_arena_retains_exact_point_eof_and_credit_until_last_alias(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let file=File::new(b"\xef\xbb\xbfvar/value=7\r\n");let mut source=driver(&a);source.push_opened(&file,file.lease.clone(),0,&a).unwrap();let mut host=Host{ordinary:OriginalOrdinaryOutput::new(&a).unwrap()};let work=OutputWork(Arc::new(AtomicUsize::new(0)));let mut rows=OriginalRawOrigins::new(&a,&work).unwrap();
  // One bounded fixture metadata grant, before path/trace/anchor allocations.
  let metadata_credit=a.reserve(1024).unwrap();let path=Arc::new(PathBuf::from("actual-mapping.dm"));let trace=OriginalMacroTrace::empty();let mut offset=0;
  while let Some(actual)=next(&mut source,&file,&mut host,&a){rows.append_actual_using(&actual,Span::new(offset,offset+1),Span::new(offset,offset+1),1,0,path.clone(),trace.clone(),&file.lease,&file,&mut source,&a,&work).unwrap();offset+=1;}
  assert!(rows.len()>3);let mut saw_end=false;for index in 0..rows.len(){let(occurrence,point,span,_,eof)=rows.geometry(index).unwrap();assert_eq!(occurrence,0);assert_eq!(rows.point(index,0,&file.lease,span.start).unwrap(),point);if eof{saw_end=true;assert_eq!(rows.point(index,0,&file.lease,span.end).unwrap(),point)}else{assert!(rows.point(index,0,&file.lease,span.end).is_err())}}
  assert!(saw_end,"only the actual finished raw input can mark terminal rows");let metadata=dm_syntax::SharedSettingRetention::new(metadata_credit);let arena=super::super::ExpandedOriginArena::from_actual_raw_rows_using(rows,metadata,&a).unwrap();let alias=arena.clone();assert!(arena.same_owner(&alias));assert_eq!(arena.len(),offset);let page_charge=work.0.load(Ordering::Acquire);drop((source,host,path,trace,arena));assert!(used.load(Ordering::Acquire)>0,"last mapping alias must still pay for retained rows and metadata");assert_eq!(work.0.load(Ordering::Acquire),page_charge);drop(alias);assert_eq!(used.load(Ordering::Acquire),0);assert_eq!(work.0.load(Ordering::Acquire),0);
 }
 #[test]
 fn actual_non_ascii_source_uses_inline_utf8_and_exact_decoded_offset_escape() {
  for (raw, extra_decoded_bytes) in [
   (b"var/first=1; /*\xc3\xa9*/ var/after=7\n".as_slice(),0usize),
   (b"var/first=1; /*\x80*/ var/after=7\n".as_slice(),2usize),
  ] {
   let used=Arc::new(AtomicUsize::new(0));
   let a=SettingAdmission::new(&used,32<<20,&||Ok(()));
   let file=File::new(raw);
   let needle=b"var/after";
   let raw_at=raw.windows(needle.len()).position(|part|part==needle).unwrap();
   let decoded_at=file.lease.source_text().as_str().find("var/after").unwrap();
   assert_eq!(decoded_at,raw_at+extra_decoded_bytes);
   let mut source=driver(&a);
   source.push_opened(&file,file.lease.clone(),0,&a).unwrap();
   let mut host=Host{ordinary:OriginalOrdinaryOutput::new(&a).unwrap()};
   let work=OutputWork(Arc::new(AtomicUsize::new(0)));
   let mut rows=OriginalRawOrigins::new(&a,&work).unwrap();
   let metadata=a.reserve(1024).unwrap();
   let path=Arc::new(PathBuf::from("non-ascii-origin.dm"));
   let trace=OriginalMacroTrace::empty();
   let mut saw_after=false;
   while let Some(actual)=next(&mut source,&file,&mut host,&a) {
    let ordinal=rows.len();
    let span=Span::new(ordinal,ordinal+1);
    rows.append_actual_using(&actual,span,span,1,0,path.clone(),trace.clone(),
     &file.lease,&file,&mut source,&a,&work).unwrap();
    if actual.origin.physical.start==raw_at && matches!(&actual.value,Value::Ident{spelling,..}if spelling.get()=="var") {
     let row=rows.row(ordinal).unwrap();
     let class=rows.rows.narrow.get(ordinal).unwrap().class();
     assert_eq!(class,if extra_decoded_bytes==0 {0} else {NarrowRow::MEDIUM});
     assert_eq!(row.raw_extent,Span::new(raw_at,raw_at+3));
     assert_eq!(rows.point(ordinal,0,&file.lease,span.start).unwrap(),
      OriginalByteCursor{line:1,byte_column:raw_at+1,source_offset:decoded_at});
     saw_after=true;
    }
   }
   assert!(saw_after,"actual token after the non-ASCII comment was recorded");
   drop((rows,source,host,path,trace,metadata));
   assert_eq!(used.load(Ordering::Acquire),0);
   assert_eq!(work.0.load(Ordering::Acquire),0);
  }
 }

 #[test]
 fn narrow_origin_pages_charge_actual_capacity_and_do_not_replace_old_pages(){
  let used=Arc::new(AtomicUsize::new(0));
  let page_bytes=ROW_PAGE_LEN*std::mem::size_of::<NarrowRow>();
  let directory_bytes=4*std::mem::size_of::<Vec<NarrowRow>>();
  let cap=2*page_bytes+directory_bytes;
  for denied in [false,true] {
   let syntax=Arc::new(AtomicUsize::new(0));
   let a=SettingAdmission::new(&syntax,0,&||Ok(()));
   let work=CappedWork::new(Arc::clone(&used),cap-usize::from(denied));
   let mut credit=work.reserve(0).unwrap();
   let mut funding=PageFunding{work:&work,credit:&mut credit};
   let mut rows=OriginPages::new();
   let row=|at|{let [low,high]=u16::try_from(at).unwrap().to_le_bytes();NarrowRow{tag:0,fields:[low,high,0,0]}};
   let number=|row:&NarrowRow|u16::from_le_bytes([row.fields[0],row.fields[1]]);
   for at in 0..ROW_PAGE_LEN{rows.push(row(at),&a,&mut funding).unwrap();}
   let first=rows.get(0).unwrap() as *const NarrowRow;
   if denied{
    assert_eq!(rows.push(row(ROW_PAGE_LEN),&a,&mut funding).unwrap_err().kind(),io::ErrorKind::OutOfMemory);
    assert_eq!(rows.len(),ROW_PAGE_LEN);
    assert_eq!(used.load(Ordering::Acquire),page_bytes+directory_bytes);
   }else{
    rows.push(row(ROW_PAGE_LEN),&a,&mut funding).unwrap();
    rows.push(row(ROW_PAGE_LEN+1),&a,&mut funding).unwrap();
    assert_eq!(rows.len(),ROW_PAGE_LEN+2);
    assert_eq!(rows.partition_point(|_, row|number(row)<(ROW_PAGE_LEN+1) as u16),ROW_PAGE_LEN+1);
    assert_eq!(used.load(Ordering::Acquire),cap);
    let mut buffers=Vec::new();rows.visit_storage(|_,len,bytes|buffers.push((len,bytes)));
    assert_eq!(buffers,[(2,directory_bytes),(ROW_PAGE_LEN,page_bytes),(2,page_bytes)]);
    rows.truncate(ROW_PAGE_LEN+1,&mut funding).unwrap();
    assert_eq!(number(rows.last().unwrap()),ROW_PAGE_LEN as u16);
    assert_eq!(used.load(Ordering::Acquire),cap,"partial page remains charged at actual capacity");
    rows.truncate(ROW_PAGE_LEN,&mut funding).unwrap();
    assert_eq!(used.load(Ordering::Acquire),page_bytes+directory_bytes,"dead page releases only its own allocation");
   }
   assert_eq!(rows.get(0).unwrap() as *const NarrowRow,first);
   assert!(rows.get(ROW_PAGE_LEN).is_none());
   drop(rows);drop(credit);assert_eq!(used.load(Ordering::Acquire),0);assert_eq!(syntax.load(Ordering::Acquire),0);
  }
 }
 #[test]
 fn group_pages_charge_each_allocation_without_replacing_prior_metadata() {
  let used=Arc::new(AtomicUsize::new(0));
  let page_bytes=ROW_PAGE_LEN*std::mem::size_of::<PackedGroup>();
  let directory_bytes=4*std::mem::size_of::<Vec<PackedGroup>>();
  let rank_directory_bytes=4*std::mem::size_of::<Vec<GroupTracePage>>();
  let rank_page_bytes=TRACE_DIRECTORY_PAGE_LEN*std::mem::size_of::<GroupTracePage>();
  let run_directory_bytes=4*std::mem::size_of::<Vec<OriginalMacroTrace>>();
  let run_page_bytes=128*std::mem::size_of::<OriginalMacroTrace>();
  let trace_bytes=rank_directory_bytes+rank_page_bytes+run_directory_bytes+run_page_bytes;
  let cap=2*page_bytes+directory_bytes+trace_bytes;
  let trace=OriginalMacroTrace::empty();
  let group=|line|GroupGeometry{
   encounter:7,decoded:Span::new(line,line+1),
   line,output_line:line,output_base:line,raw_base:line,
  };
  for denied in [false,true] {
   let syntax=Arc::new(AtomicUsize::new(0));
   let a=SettingAdmission::new(&syntax,0,&||Ok(()));
   let work=CappedWork::new(Arc::clone(&used),cap-usize::from(denied));
   let mut credit=work.reserve(0).unwrap();
   let mut funding=PageFunding{work:&work,credit:&mut credit};
   let mut groups=OriginGroups::new();
   for line in 0..ROW_PAGE_LEN {
    groups.push(group(line),trace.clone(),&a,&mut funding).unwrap();
   }
   let first=groups.packed.get(0).unwrap() as *const PackedGroup;
   let next=groups.push(group(ROW_PAGE_LEN),trace.clone(),&a,&mut funding);
   if denied {
    assert_eq!(next.unwrap_err().kind(),io::ErrorKind::OutOfMemory);
    assert_eq!(groups.len(),ROW_PAGE_LEN);
   } else {
    next.unwrap();
    let (last, last_trace)=groups.get(ROW_PAGE_LEN).unwrap();
    assert_eq!(last.line,ROW_PAGE_LEN);
    assert_eq!(last.encounter,7);
    assert!(last_trace.same_owner(&trace));
    assert_eq!(used.load(Ordering::Acquire),cap);
    let mut buffers=Vec::new();
    groups.visit_storage(|_,len,bytes|buffers.push((len,bytes)));
    assert_eq!(buffers,[
     (2,directory_bytes),(ROW_PAGE_LEN,page_bytes),(1,page_bytes),
     (1,rank_directory_bytes),(2,rank_page_bytes),
     (1,run_directory_bytes),(1,run_page_bytes),
    ]);
    groups.truncate(ROW_PAGE_LEN,&mut funding).unwrap();
   }
   assert_eq!(groups.packed.get(0).unwrap() as *const PackedGroup,first);
   assert!(groups.get(ROW_PAGE_LEN).is_none());
   assert_eq!(groups.iter().count(),ROW_PAGE_LEN);
   assert_eq!(used.load(Ordering::Acquire),page_bytes+directory_bytes+trace_bytes);
   assert_eq!(groups.traces.len(),1,"one exact Arc is sufficient across both group pages");
   drop(groups);
   drop(credit);
   assert_eq!(used.load(Ordering::Acquire),0);
   assert_eq!(syntax.load(Ordering::Acquire),0);
  }
 }
 #[test]
 fn packed_group_width_and_encounter_bounds_preserve_original_coordinates() {
  let base=200_000;
  let normal=GroupGeometry{encounter:usize::from(u16::MAX)-1,
   decoded:Span::new(1,1+usize::from(u16::MAX)),line:27,
   output_line:base+usize::from(u16::MAX),output_base:200_003,raw_base:1};
  assert_eq!(GroupGeometry::unpack(&normal.pack(base).unwrap(),base),Some(normal));
  for wide in [
   GroupGeometry{encounter:usize::from(u16::MAX),..normal},
   GroupGeometry{decoded:Span::new(1,normal.decoded.end+1),..normal},
   GroupGeometry{decoded:Span::new(1,0),..normal},
   GroupGeometry{raw_base:3,..normal},
   GroupGeometry{line:usize::from(u16::MAX)+1,..normal},
   GroupGeometry{output_line:base-1,..normal},
   GroupGeometry{output_line:normal.output_line+1,..normal},
  ]{assert!(wide.pack(base).is_none());}
  assert_eq!(PackedGroup::escape(usize::MAX).unwrap().escape_index(),Some(usize::MAX));
 }
 #[test]
 fn packed_groups_preserve_wide_coordinates_and_refund_only_retired_owners() {
  let syntax=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&syntax,0,&||Ok(()));
  let source=Arc::new(AtomicUsize::new(0));
  let work=CappedWork::new(Arc::clone(&source),usize::MAX);
  let mut credit=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut credit};
  let trace=OriginalMacroTrace::empty();
  let distinct=OriginalMacroTrace::empty();
  let narrow=GroupGeometry{encounter:0,decoded:Span::new(2,5),line:1,output_line:4,output_base:12,raw_base:2};
  let wide=GroupGeometry{encounter:usize::MAX,decoded:Span::new(2,usize::MAX),
   output_base:usize::MAX,raw_base:usize::MAX,..narrow};
  let mut groups=OriginGroups::new();
  groups.push(narrow,trace.clone(),&a,&mut funding).unwrap();
  let narrow_bytes=source.load(Ordering::Acquire);
  work.limit.store(narrow_bytes,Ordering::Release);
  let denied=groups.push(wide,distinct.clone(),&a,&mut funding).unwrap_err();
  assert_eq!(denied.kind(),io::ErrorKind::OutOfMemory);
  assert_eq!(groups.len(),1);
  assert_eq!(groups.full.len(),0);
  assert_eq!(distinct.strong_count(),1);
  assert_eq!(source.load(Ordering::Acquire),narrow_bytes);

  work.limit.store(usize::MAX,Ordering::Release);
  groups.push(wide,distinct.clone(),&a,&mut funding).unwrap();
  groups.push(narrow,trace.clone(),&a,&mut funding).unwrap();
  let (issued, issued_trace)=groups.get(1).unwrap();
  assert_eq!(issued,wide);
  assert!(issued_trace.same_owner(&distinct));
  assert_eq!(groups.geometry(2),Some(narrow));
  let before=source.load(Ordering::Acquire);
  groups.truncate(1,&mut funding).unwrap();
  assert_eq!(before-source.load(Ordering::Acquire),128*std::mem::size_of::<(usize,GroupGeometry)>());
  assert_eq!(groups.full.len(),0);
  assert_eq!(distinct.strong_count(),1);
  assert_eq!(groups.geometry(0),Some(narrow));
  assert!(groups.get(0).unwrap().1.same_owner(&trace));
  drop(groups);
  drop(credit);
  assert_eq!(source.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),0);
 }

 #[test]
 fn group_page_geometry_escapes_keep_the_same_ordinals_after_partial_trim() {
  let syntax=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&syntax,0,&||Ok(()));
  let used=Arc::new(AtomicUsize::new(0));
  let work=OutputWork(Arc::clone(&used));
  let mut credit=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut credit};
  let trace=OriginalMacroTrace::empty();
  let ordinary=|line|GroupGeometry{encounter:7,decoded:Span::new(line,line+1),
   line,output_line:200_000+line,output_base:line*3,raw_base:line};
  let mut groups=OriginGroups::new();
  for index in 0..ROW_PAGE_LEN {
   let mut geometry=ordinary(index);
   if index==2{geometry.raw_base+=3;}
   groups.push(geometry,trace.clone(),&a,&mut funding).unwrap();
   assert_eq!(groups.geometry(index),Some(geometry));
  }
  let start=GroupGeometry{output_line:900_000,..ordinary(ROW_PAGE_LEN)};
  let shifted=GroupGeometry{output_line:start.output_line+65_536,..ordinary(ROW_PAGE_LEN+1)};
  groups.push(start,trace.clone(),&a,&mut funding).unwrap();
  groups.push(shifted,trace.clone(),&a,&mut funding).unwrap();
  assert_eq!(groups.full.len(),2);
  assert_eq!(groups.packed.get(2).unwrap().escape_index(),Some(0));
  assert_eq!(groups.packed.get(ROW_PAGE_LEN+1).unwrap().escape_index(),Some(1));
  assert_eq!(groups.geometry(ROW_PAGE_LEN),Some(start));
  assert_eq!(groups.geometry(ROW_PAGE_LEN+1),Some(shifted));

  groups.truncate(ROW_PAGE_LEN+1,&mut funding).unwrap();
  assert_eq!(groups.full.len(),1);
  let replacement=GroupGeometry{raw_base:7,output_line:start.output_line+1,..ordinary(ROW_PAGE_LEN+1)};
  groups.push(replacement,trace.clone(),&a,&mut funding).unwrap();
  assert_eq!(groups.packed.get(ROW_PAGE_LEN+1).unwrap().escape_index(),Some(1));
  assert_eq!(groups.geometry(ROW_PAGE_LEN+1),Some(replacement));
  assert!(groups.get(ROW_PAGE_LEN+1).unwrap().1.same_owner(&trace));

  groups.truncate(ROW_PAGE_LEN,&mut funding).unwrap();
  let new_start=GroupGeometry{output_line:2_000_000,..start};
  groups.push(new_start,trace.clone(),&a,&mut funding).unwrap();
  assert_eq!(groups.geometry(ROW_PAGE_LEN),Some(new_start));
  assert_eq!(groups.full.len(),1);
  assert_eq!(groups.geometry(2),Some(GroupGeometry{raw_base:5,..ordinary(2)}));
  drop((groups,credit));
  assert_eq!(used.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),0);
 }

 #[test]
 fn group_trace_rank_preserves_exact_owners_across_words_pages_and_trim() {
  let syntax=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&syntax,0,&||Ok(()));
  let used=Arc::new(AtomicUsize::new(0));
  let work=OutputWork(Arc::clone(&used));
  let mut credit=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut credit};
  let distinct_a=OriginalMacroTrace::empty();
  let distinct_b=OriginalMacroTrace::empty();
  let distinct_c=OriginalMacroTrace::empty();
  assert!(!distinct_a.same_owner(&distinct_b));
  let group=|line|GroupGeometry{encounter:7,decoded:Span::new(line,line+1),
   line,output_line:line,output_base:line,raw_base:line};
  let expected=|index|match index {
   0..=62 => &distinct_a,
   63..=64 => &distinct_b,
   65..=4096 => &distinct_a,
   _ => &distinct_c,
  };
  let mut groups=OriginGroups::new();
  for index in 0..ROW_PAGE_LEN+3 {
   groups.push(group(index),expected(index).clone(),&a,&mut funding).unwrap();
  }
  assert_eq!(groups.traces.len(),4);
  for index in 0..groups.len() {
   let (geometry, trace)=groups.get(index).unwrap();
   assert_eq!(geometry,group(index));
   assert!(trace.same_owner(expected(index)));
  }
  // Keep a partial second page whose first bit carries the preceding
  // page's owner. Removing a set bit must also clear it before a same-
  // owner append at the exact discarded index.
  groups.truncate(ROW_PAGE_LEN+1,&mut funding).unwrap();
  assert!(groups.get(ROW_PAGE_LEN).unwrap().1.same_owner(&distinct_a));
  assert_eq!(distinct_c.strong_count(),1);
  groups.push(group(ROW_PAGE_LEN+1),distinct_a.clone(),&a,&mut funding).unwrap();
  assert_eq!(groups.traces.len(),3);
  assert!(groups.get(ROW_PAGE_LEN+1).unwrap().1.same_owner(&distinct_a));
  groups.push(group(ROW_PAGE_LEN+2),distinct_c.clone(),&a,&mut funding).unwrap();
  assert_eq!(groups.traces.len(),4);
  assert!(groups.get(ROW_PAGE_LEN+2).unwrap().1.same_owner(&distinct_c));
  groups.truncate(64,&mut funding).unwrap();
  assert_eq!(groups.traces.len(),2);
  assert_eq!(distinct_c.strong_count(),1,"the discarded suffix must release its trace");
  groups.push(group(64),distinct_b.clone(),&a,&mut funding).unwrap();
  groups.push(group(65),distinct_c.clone(),&a,&mut funding).unwrap();
  assert!(groups.get(64).unwrap().1.same_owner(&distinct_b));
  assert!(groups.get(65).unwrap().1.same_owner(&distinct_c));
  groups.truncate(0,&mut funding).unwrap();
  assert!(groups.get(0).is_none());
  assert_eq!(groups.traces.len(),0);
  groups.push(group(0),distinct_c.clone(),&a,&mut funding).unwrap();
  assert!(groups.get(0).unwrap().1.same_owner(&distinct_c));
  drop(groups);
  drop(credit);
  assert_eq!(used.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),0);
 }

 #[test]
 fn group_trace_geometry_grow_failure_rolls_back_prepaid_trace_page_and_preserves_io() {
  use std::sync::atomic::AtomicBool;
  struct DenySecondGeometry {
   backing: OutputWork,
   absent: PathBuf,
   armed: AtomicBool,
   run_grows: AtomicUsize,
  }
  impl SourceArenaWork for DenySecondGeometry {
   fn checkpoint(&self)->io::Result<()>{self.backing.checkpoint()}
   fn reserve(&self,bytes:usize)->io::Result<SourceArenaCredit>{self.backing.reserve(bytes)}
   fn grow(&self,credit:&mut SourceArenaCredit,bytes:usize)->io::Result<()> {
    if self.armed.load(Ordering::Acquire) {
     if bytes==ROW_PAGE_LEN*std::mem::size_of::<PackedGroup>() {
      return std::fs::File::open(&self.absent).map(drop);
     }
     if bytes==128*std::mem::size_of::<OriginalMacroTrace>() {
      self.run_grows.fetch_add(1,Ordering::AcqRel);
     }
    }
    self.backing.grow(credit,bytes)
   }
   fn shrink(&self,credit:&mut SourceArenaCredit,bytes:usize)->io::Result<()>{self.backing.shrink(credit,bytes)}
  }
  // Obtain a genuine OS failure without relying on a platform-specific code.
  let absent=std::env::current_exe().unwrap().join("not-a-directory/origin-provider");
  let expected=std::fs::File::open(&absent).unwrap_err();
  let raw=expected.raw_os_error().expect("real filesystem open error");
  let syntax=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&syntax,0,&||Ok(()));
  let live=Arc::new(AtomicUsize::new(0));
  let work=DenySecondGeometry{backing:OutputWork(Arc::clone(&live)),absent,
   armed:AtomicBool::new(false),run_grows:AtomicUsize::new(0)};
  let mut credit=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut credit};
  let owner_a=OriginalMacroTrace::empty();
  let owner_b=OriginalMacroTrace::empty();
  let rejected=OriginalMacroTrace::empty();
  let group=|line|GroupGeometry{encounter:7,decoded:Span::new(line,line+1),
   line,output_line:line,output_base:line,raw_base:line};
  let mut groups=OriginGroups::new();
  for line in 0..ROW_PAGE_LEN {
   let owner=if line<128&&line%2==0{&owner_a}else{&owner_b};
   groups.push(group(line),owner.clone(),&a,&mut funding).unwrap();
  }
  assert_eq!(groups.traces.len(),128);
  assert_eq!(groups.trace_pages.len(),1);
  let before=live.load(Ordering::Acquire);
  work.armed.store(true,Ordering::Release);
  let first=groups.push(group(ROW_PAGE_LEN),rejected.clone(),&a,&mut funding).unwrap_err();
  assert_eq!(first.raw_os_error(),Some(raw));
  assert_eq!(first.kind(),expected.kind());
  assert_eq!(work.run_grows.load(Ordering::Acquire),1,"trace page was actually funded before refusal");
  assert_eq!(live.load(Ordering::Acquire),before,"discarded trace page was released");
  assert_eq!(groups.len(),ROW_PAGE_LEN);
  assert_eq!(groups.traces.len(),128);
  assert_eq!(groups.trace_pages.len(),1);
  assert_eq!(rejected.strong_count(),1);
  assert!(groups.get(0).unwrap().1.same_owner(&owner_a));
  assert!(groups.last().unwrap().1.same_owner(&owner_b));
  assert!(groups.get(ROW_PAGE_LEN).is_none());
  work.armed.store(false,Ordering::Release);
  groups.push(group(ROW_PAGE_LEN),owner_b.clone(),&a,&mut funding).unwrap();
  assert_eq!(groups.traces.len(),128);
  assert!(groups.get(ROW_PAGE_LEN).unwrap().1.same_owner(&owner_b));
  drop((groups,credit));
  assert_eq!(live.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),0);
 }

 #[test]
 fn packed_raw_rows_roundtrip_all_widths_page_bases_and_retained_suffix() {
  let used=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&used,4<<20,&||Ok(()));
  let work=OutputWork(Arc::new(AtomicUsize::new(0)));let mut credit=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut credit};
  let trace=OriginalMacroTrace::empty();
  let group=|output_base|GroupGeometry{encounter:2,decoded:Span::new(4,10),line:1,output_line:5,output_base,raw_base:3};
  let mut groups=OriginGroups::new();
  groups.push(group(usize::MAX-65535),trace.clone(),&a,&mut funding).unwrap();
  groups.push(group(0),trace.clone(),&a,&mut funding).unwrap();
  let start=groups.geometry(0).unwrap().output_base+7;
  let narrow=Row{group:0,output:Span::new(start,start+5),token_end:start+4,source_offset:6,byte_column:3,raw_extent:Span::new(5,10),actual_eof:true};
  let medium=Row{output:Span::new(start,start+300),token_end:start+260,..narrow};
  let wide=Row{output:Span::new(1,usize::MAX),token_end:usize::MAX-1,actual_eof:false,..narrow};
  let unusual_column=Row{byte_column:17,..narrow};
  let second_page=Row{group:1,output:Span::new(7,12),token_end:11,..narrow};
  let huge_ordinal=Row{group:usize::MAX,..narrow};
  let mut huge=RawTokenRows::new(&a).unwrap();
  huge.push(huge_ordinal,groups.geometry(0).unwrap(),&a,&mut funding).unwrap();
  assert_eq!(huge.group_at(0),Some(usize::MAX),"page group base stays full width");
  drop(huge);
  let mut rows=RawTokenRows::new(&a).unwrap();
  for row in [narrow,medium,wide,unusual_column] {
   rows.push(row,groups.geometry(0).unwrap(),&a,&mut funding).unwrap();
  }
  for _ in rows.len()..ROW_PAGE_LEN {
   rows.push(narrow,groups.geometry(0).unwrap(),&a,&mut funding).unwrap();
  }
  for row in [second_page,Row{byte_column:33,..second_page}] {
   rows.push(row,groups.geometry(1).unwrap(),&a,&mut funding).unwrap();
  }
  for (index,expected,class) in [
   (0,narrow,NarrowRow::EOF),(1,medium,NarrowRow::MEDIUM),(2,wide,NarrowRow::FULL),
   (3,unusual_column,NarrowRow::FULL),(ROW_PAGE_LEN,second_page,NarrowRow::EOF),
   (ROW_PAGE_LEN+1,Row{byte_column:33,..second_page},NarrowRow::FULL),
  ] {
   assert_eq!(rows.narrow.get(index).unwrap().class(),class);
   assert_eq!(rows.get(index,&groups),Some(expected));
  }
  assert_eq!(rows.bases.as_slice()[1].group,1);
  assert_eq!(rows.bases.as_slice()[1].full,2);
  rows.truncate(ROW_PAGE_LEN+1,&mut funding).unwrap();
  assert_eq!(rows.full.len(),2);
  assert_eq!(rows.get(ROW_PAGE_LEN,&groups),Some(second_page));
  rows.truncate(2,&mut funding).unwrap();
  assert_eq!(rows.full.len(),0);
  assert_eq!(rows.full.pages.len(),0);
  assert_eq!(rows.medium.len(),1);
  assert_eq!(rows.get(1,&groups),Some(medium));
  rows.truncate(1,&mut funding).unwrap();
  assert_eq!(rows.medium.len(),0);
  assert_eq!(rows.medium.pages.len(),0);
  assert_eq!(rows.get(0,&groups),Some(narrow));
  drop((rows,groups,trace));
  drop(credit);assert_eq!(work.0.load(Ordering::Acquire),0);
  assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]
 fn row_group_rank_tracks_wide_transitions_and_reissues_trimmed_suffix() {
  let syntax=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&syntax,4<<20,&||Ok(()));
  let live=Arc::new(AtomicUsize::new(0));
  let work=OutputWork(Arc::clone(&live));
  let mut credit=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut credit};
  let group=GroupGeometry{encounter:0,decoded:Span::new(0,8),line:1,output_line:1,output_base:0,raw_base:0};
  let trace=OriginalMacroTrace::empty();
  let mut groups=OriginGroups::new();
  for _ in 0..4{groups.push(group,trace.clone(),&a,&mut funding).unwrap();}
  let row=Row{group:0,output:Span::new(0,5),token_end:4,source_offset:0,
   byte_column:1,raw_extent:Span::new(0,1),actual_eof:false};
  let medium=Row{group:1,raw_extent:Span::new(0,300),..row};
  let full=Row{group:2,byte_column:4,..row};
  let mut rows=RawTokenRows::new(&a).unwrap();
  for _ in 0..63{rows.push(row,group,&a,&mut funding).unwrap();}
  rows.push(medium,group,&a,&mut funding).unwrap();
  rows.push(full,group,&a,&mut funding).unwrap();
  assert_eq!(rows.narrow.get(63).unwrap().class(),NarrowRow::MEDIUM);
  assert_eq!(rows.narrow.get(64).unwrap().class(),NarrowRow::FULL);
  assert_eq!(rows.get(63,&groups),Some(medium));
  assert_eq!(rows.get(64,&groups),Some(full));
  let inline=Row{group:2,..row};
  for _ in rows.len()..ROW_PAGE_LEN{rows.push(inline,group,&a,&mut funding).unwrap();}
  let next_page=Row{group:3,actual_eof:true,..row};
  rows.push(next_page,group,&a,&mut funding).unwrap();
  assert_eq!(rows.get(ROW_PAGE_LEN-1,&groups),Some(inline));
  assert_eq!(rows.get(ROW_PAGE_LEN,&groups),Some(next_page));

  rows.truncate(64,&mut funding).unwrap();
  assert_eq!(rows.ranks.len(),1);
  assert_eq!(rows.last_group,Some(1));
  assert_eq!(rows.full.len(),0);
  let replacement=Row{group:1,..row};
  rows.push(replacement,group,&a,&mut funding).unwrap();
  rows.push(inline,group,&a,&mut funding).unwrap();
  assert_eq!(rows.get(64,&groups),Some(replacement),"trim cleared the old bit at the word boundary");
  assert_eq!(rows.get(65,&groups),Some(inline));
  let refused=rows.push(Row{group:0,..row},group,&a,&mut funding).unwrap_err();
  assert_eq!(refused.kind(),io::ErrorKind::InvalidData);
  assert_eq!(rows.len(),66);
  let mut bytes=0;
  rows.visit_storage(|_,_,capacity|bytes+=capacity);
  let mut bases_bytes=0;
  rows.bases.visit_allocation(|_,capacity|bases_bytes+=capacity);
  assert_eq!(live.load(Ordering::Acquire),bytes-bases_bytes + {
   let mut groups_bytes=0;
   groups.visit_storage(|_,_,capacity|groups_bytes+=capacity);
   groups_bytes
  },"all real row/rank/escape pages and directories remain funded");
  drop((rows,groups,credit));
  assert_eq!(live.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),0);
 }

 #[test]
 fn failed_cell_page_append_does_not_publish_escape_or_replace_prior_cells() {
  let used=Arc::new(AtomicUsize::new(0));
  let initial=SettingAdmission::new(&used,4<<20,&||Ok(()));
  let source=Arc::new(AtomicUsize::new(0));let work=CappedWork::new(Arc::clone(&source),usize::MAX);
  let mut credit=work.reserve(0).unwrap();let mut funding=PageFunding{work:&work,credit:&mut credit};
  let group=GroupGeometry{encounter:0,decoded:Span::new(0,1),line:1,output_line:1,output_base:0,raw_base:0};
  let narrow=Row{group:0,output:Span::new(0,1),token_end:1,source_offset:0,byte_column:1,raw_extent:Span::new(0,1),actual_eof:false};
  let medium=Row{output:Span::new(0,300),..narrow};
  let mut rows=RawTokenRows::new(&initial).unwrap();
  rows.push(medium,group,&initial,&mut funding).unwrap();
  for _ in rows.len()..ROW_PAGE_LEN {
   rows.push(narrow,group,&initial,&mut funding).unwrap();
  }
  let first=rows.narrow.get(0).unwrap() as *const NarrowRow;
  let before=used.load(Ordering::Acquire);
  let source_before=source.load(Ordering::Acquire);work.limit.store(source_before,Ordering::Release);
  assert_eq!(rows.push(Row{group:1,..medium},group,&initial,&mut funding).unwrap_err().kind(),io::ErrorKind::OutOfMemory);
  assert_eq!(rows.len(),ROW_PAGE_LEN);
  assert_eq!(rows.bases.len(),1);
  assert_eq!(rows.medium.len(),1);
  assert_eq!(rows.ranks.len(),1);
  assert_eq!(rows.group_at(ROW_PAGE_LEN-1),Some(0));
  assert_eq!(rows.last_group,Some(0));
  assert_eq!(rows.narrow.get(0).unwrap() as *const NarrowRow,first);
  assert_eq!(used.load(Ordering::Acquire),before);
  assert_eq!(source.load(Ordering::Acquire),source_before);
  drop(rows);drop(credit);assert_eq!(source.load(Ordering::Acquire),0);
  assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]
 fn first_row_cell_failure_keeps_real_io_after_funding_rank_and_escape() {
  use std::sync::atomic::AtomicBool;
  struct DenyCell {
   backing: OutputWork,
   absent: PathBuf,
   armed: AtomicBool,
   ranks: AtomicUsize,
  }
  impl SourceArenaWork for DenyCell {
   fn checkpoint(&self)->io::Result<()>{self.backing.checkpoint()}
   fn reserve(&self,bytes:usize)->io::Result<SourceArenaCredit>{self.backing.reserve(bytes)}
   fn grow(&self,credit:&mut SourceArenaCredit,bytes:usize)->io::Result<()> {
    if self.armed.load(Ordering::Acquire) {
     if bytes==ROW_PAGE_LEN*std::mem::size_of::<NarrowRow>() {
      return std::fs::File::open(&self.absent).map(drop);
     }
     if bytes==TRACE_DIRECTORY_PAGE_LEN*std::mem::size_of::<RowGroupRank>() {
      self.ranks.fetch_add(1,Ordering::AcqRel);
     }
    }
    self.backing.grow(credit,bytes)
   }
   fn shrink(&self,credit:&mut SourceArenaCredit,bytes:usize)->io::Result<()>{self.backing.shrink(credit,bytes)}
  }
  let absent=std::env::current_exe().unwrap().join("not-a-directory/origin-row-provider");
  let expected=std::fs::File::open(&absent).unwrap_err();
  let syntax=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&syntax,4<<20,&||Ok(()));
  let live=Arc::new(AtomicUsize::new(0));
  let work=DenyCell{backing:OutputWork(Arc::clone(&live)),absent,
   armed:AtomicBool::new(true),ranks:AtomicUsize::new(0)};
  let mut credit=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut credit};
  let geometry=GroupGeometry{encounter:0,decoded:Span::new(0,1),line:1,output_line:1,output_base:0,raw_base:0};
  let medium=Row{group:0,output:Span::new(0,300),token_end:300,source_offset:0,
   byte_column:1,raw_extent:Span::new(0,1),actual_eof:false};
  let mut rows=RawTokenRows::new(&a).unwrap();
  let actual=rows.push(medium,geometry,&a,&mut funding).unwrap_err();
  assert_eq!(actual.kind(),expected.kind());
  assert_eq!(actual.raw_os_error(),expected.raw_os_error());
  assert!(actual.raw_os_error().is_some());
  assert_eq!(work.ranks.load(Ordering::Acquire),1,"rank page was funded before the actual cell failure");
  assert_eq!(rows.len(),0);
  assert_eq!(rows.ranks.len(),0);
  assert_eq!(rows.medium.len(),0);
  assert_eq!(rows.last_group,None);
  let mut retained_directories=0;
  rows.ranks.visit_storage(|_,len,bytes|{assert_eq!(len,0);retained_directories+=bytes;});
  rows.medium.visit_storage(|_,len,bytes|{assert_eq!(len,0);retained_directories+=bytes;});
  assert_eq!(live.load(Ordering::Acquire),retained_directories);

  work.armed.store(false,Ordering::Release);
  rows.push(medium,geometry,&a,&mut funding).unwrap();
  assert_eq!(rows.group_at(0),Some(0));
  assert_eq!(rows.medium.len(),1);
  drop((rows,credit));
  assert_eq!(live.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),0);
 }

 #[test]fn actual_raw_arena_rejects_equal_bytes_foreign_acquisition_and_nonexact_offsets(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let file=File::new(b"var/value=7\n");let foreign=File::new(b"var/value=7\n");let mut source=driver(&a);source.push_opened(&file,file.lease.clone(),0,&a).unwrap();let mut host=Host{ordinary:OriginalOrdinaryOutput::new(&a).unwrap()};let actual=next(&mut source,&file,&mut host,&a).unwrap();let work=OutputWork(Arc::new(AtomicUsize::new(0)));let mut rows=OriginalRawOrigins::new(&a,&work).unwrap();let credit=a.reserve(1024).unwrap();let path=Arc::new(PathBuf::from("same.dm"));let trace=OriginalMacroTrace::empty();rows.append_actual_using(&actual,Span::new(0,4),Span::new(0,5),1,0,path,trace,&file.lease,&file,&mut source,&a,&work).unwrap();assert!(rows.point(0,0,&foreign.lease,0).is_err());assert!(rows.point(0,1,&file.lease,0).is_err());assert!(rows.point(0,0,&file.lease,1).is_err());assert_eq!(rows.policy_line(0,0,&file.lease,3).unwrap(),1);assert!(rows.policy_line(0,0,&foreign.lease,3).is_err());drop((rows,source,host,credit));assert!(used.load(Ordering::Acquire)>0,"the still-owned emitted token must retain its own text credit");drop(actual);assert_eq!(used.load(Ordering::Acquire),0);
 }
 struct OutputCredit{bytes:std::sync::atomic::AtomicUsize,live:Arc<std::sync::atomic::AtomicUsize>}
 impl Drop for OutputCredit{fn drop(&mut self){self.live.fetch_sub(self.bytes.load(std::sync::atomic::Ordering::Acquire),std::sync::atomic::Ordering::AcqRel);}}
 impl crate::source_arena_credit::SourceArenaCreditOwner for OutputCredit{fn as_any(&self)->&dyn std::any::Any{self}fn reserved_bytes(&self)->usize{self.bytes.load(std::sync::atomic::Ordering::Acquire)}fn visit_storage(&self,_:&mut dyn FnMut(usize,usize)){}}
 struct OutputWork(Arc<std::sync::atomic::AtomicUsize>);
 impl crate::source_arena_credit::SourceArenaWork for OutputWork{
  fn checkpoint(&self)->io::Result<()>{Ok(())}fn reserve(&self,n:usize)->io::Result<crate::source_arena_credit::SourceArenaCredit>{self.0.fetch_add(n,std::sync::atomic::Ordering::AcqRel);Ok(crate::source_arena_credit::SourceArenaCredit::from_resource_owner(Arc::new(OutputCredit{bytes:std::sync::atomic::AtomicUsize::new(n),live:self.0.clone()})))}
  fn grow(&self,c:&mut crate::source_arena_credit::SourceArenaCredit,n:usize)->io::Result<()>{let own=c.owner().as_any().downcast_ref::<OutputCredit>().ok_or(io::ErrorKind::InvalidInput)?;if !Arc::ptr_eq(&own.live,&self.0){return Err(io::ErrorKind::InvalidInput.into())}own.bytes.fetch_add(n,std::sync::atomic::Ordering::AcqRel);self.0.fetch_add(n,std::sync::atomic::Ordering::AcqRel);Ok(())}
  fn shrink(&self,c:&mut crate::source_arena_credit::SourceArenaCredit,n:usize)->io::Result<()>{let own=c.owner().as_any().downcast_ref::<OutputCredit>().ok_or(io::ErrorKind::InvalidInput)?;if !Arc::ptr_eq(&own.live,&self.0){return Err(io::ErrorKind::InvalidInput.into())}own.bytes.fetch_update(std::sync::atomic::Ordering::AcqRel,std::sync::atomic::Ordering::Acquire,|v|v.checked_sub(n)).map_err(|_|io::ErrorKind::InvalidInput)?;self.0.fetch_sub(n,std::sync::atomic::Ordering::AcqRel);Ok(())}
 }
 struct CappedWork {
  backing: OutputWork,
  limit: std::sync::atomic::AtomicUsize,
 }
 impl CappedWork {
  fn new(live: Arc<std::sync::atomic::AtomicUsize>, limit: usize)->Self {
   Self{backing:OutputWork(live),limit:std::sync::atomic::AtomicUsize::new(limit)}
  }
  fn allow(&self, additional:usize)->io::Result<()> {
   use std::sync::atomic::Ordering;
   if self.backing.0.load(Ordering::Acquire).checked_add(additional).is_none_or(|n|n>self.limit.load(Ordering::Acquire)){
    return Err(io::ErrorKind::OutOfMemory.into());
   }
   Ok(())
  }
 }
 impl SourceArenaWork for CappedWork {
  fn checkpoint(&self)->io::Result<()>{Ok(())}
  fn reserve(&self, bytes:usize)->io::Result<SourceArenaCredit>{self.allow(bytes)?;self.backing.reserve(bytes)}
  fn grow(&self, credit:&mut SourceArenaCredit, bytes:usize)->io::Result<()>{self.allow(bytes)?;self.backing.grow(credit,bytes)}
  fn shrink(&self, credit:&mut SourceArenaCredit, bytes:usize)->io::Result<()>{self.backing.shrink(credit,bytes)}
 }
 #[test]
 fn page_directory_denial_drops_new_page_and_preserves_both_domains() {
  let syntax=Arc::new(AtomicUsize::new(0));
  let source=Arc::new(AtomicUsize::new(0));
  let work=CappedWork::new(Arc::clone(&source),ROW_PAGE_LEN*std::mem::size_of::<NarrowRow>());
  let a=SettingAdmission::new(&syntax,0,&||Ok(()));
  let mut credit=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut credit};
  let mut rows=OriginPages::new();
  let row=NarrowRow{tag:0,fields:[0;4]};
  assert_eq!(rows.push(row,&a,&mut funding).unwrap_err().kind(),io::ErrorKind::OutOfMemory);
  assert_eq!(rows.len(),0);
  assert_eq!(rows.pages.capacity(),0);
  assert_eq!(source.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),0);
 }
 #[test]fn actual_receiver_receipt_trims_raw_eof_lookahead_without_claiming_consumed_eof_and_rejects_foreign_same_end(){
  use super::super::{original_prepared_output::OriginalOutputCursor,original_source_arena::OriginalSourceArena};
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let mut text=format!("/datum/{}\n", "x".repeat(usize::from(u16::MAX)+1));text.push_str(&format!("/datum/{}\n","m".repeat(300)));text.push_str(&"var/x\n".repeat(ROW_PAGE_LEN));let file=File::new(text.as_bytes());let mut source=driver(&a);source.push_opened(&file,file.lease.clone(),0,&a).unwrap();let mut host=Host{ordinary:OriginalOrdinaryOutput::new(&a).unwrap()};let metadata=a.reserve(1024).unwrap();let path=Arc::new(PathBuf::from("delivery.dm"));let trace=OriginalMacroTrace::empty();let mut cursor=OriginalOutputCursor::new(&a).unwrap();let initial=cursor.initial_delivery().unwrap();let work=OutputWork(Arc::new(AtomicUsize::new(0)));let mut rows=OriginalRawOrigins::new(&a,&work).unwrap();rows.bind_output_using(&initial,&a).unwrap();let mut prepared=Vec::new();
  while let Some(actual)=next(&mut source,&file,&mut host,&a){
   let item=cursor.prepare(actual,&file,&a).unwrap();
   let region=usize::from(prepared.len() > ROW_PAGE_LEN);
   rows.append_produced_using(item.actual().unwrap(),item.produced(),region,path.clone(),trace.clone(),&file.lease,&file,&mut source,&a,&work).unwrap();
   prepared.push(item);
  }
  assert!(rows.groups.len() > ROW_PAGE_LEN);
  assert_eq!(rows.encounters.len(), 2, "physical rows and their traces share only the same encounter");
  assert_eq!(rows.get(rows.len() - 1).unwrap().region, 1);
  assert!(rows.len()>ROW_PAGE_LEN);
  let before_pages=rows.rows.narrow.pages.len();
  assert!(before_pages>1);
  assert!(rows.groups.packed.pages.len()>1);
  assert_eq!(rows.rows.narrow.get(0).unwrap().class(),0,"first short actual token uses the compact layout");
  assert!(rows.rows.medium.len()>0,"actual 300-byte token or row offset uses the medium fallback");
  assert!(rows.rows.full.len()>0,"actual wide token or row offset uses the full fallback");
  let wide_index=(0..rows.len()).find(|&at|rows.rows.narrow.get(at).unwrap().class()==NarrowRow::FULL).unwrap();
  let(wide_occurrence,wide_point,wide_token,wide_raw,_)=rows.geometry(wide_index).unwrap();
  assert_eq!(wide_occurrence,0);
  assert_eq!(rows.point(wide_index,0,&file.lease,wide_token.start).unwrap(),wide_point);
  assert!(wide_token.end-wide_token.start>usize::from(u16::MAX));
  assert_eq!(wide_raw.end-wide_raw.start,wide_token.end-wide_token.start);
  assert!((0..rows.len()).any(|at|rows.geometry(at).unwrap().4),"producer genuinely reached raw EOF before receiver starts");
  // A different actual cursor/receiver produces the SAME first span. Matching
  // numbers do not authorize trimming this producer's retained mappings.
  let mut foreign=OriginalOutputCursor::new(&a).unwrap();let foreign_item=foreign.prepare(prepared[0].actual().unwrap().duplicate(&a).unwrap(),&file,&a).unwrap();let mut foreign_arena=OriginalSourceArena::new(&work).unwrap();let mut foreign_primary=dm_syntax::OriginalPrimaryDemand::new(&a,None).unwrap();let(foreign_token,foreign_receipt)=foreign_item.into_delivery().adopt(&mut foreign_arena,&mut foreign_primary,&foreign.identity(),&a).unwrap();assert!(rows.retain_delivered_using(&foreign_receipt,&a,&work).is_err());
  let mut arena=OriginalSourceArena::new(&work).unwrap();let mut primary=dm_syntax::OriginalPrimaryDemand::new(&a,None).unwrap();let(first,receipt)=prepared.remove(0).into_delivery().adopt(&mut arena,&mut primary,&cursor.identity(),&a).unwrap();assert_eq!(receipt.end(),foreign_receipt.end());let full_charge=work.0.load(Ordering::Acquire);let keep=rows.retain_delivered_using(&receipt,&a,&work).unwrap();assert!(work.0.load(Ordering::Acquire)<full_charge,"actual unreceived page storage is refunded");assert_eq!(keep,1);assert_eq!(rows.len(),1);assert_eq!(rows.rows.narrow.pages.len(),1,"real receipt drops every undelivered packed page");assert_eq!(rows.groups.packed.pages.len(),1,"real receipt drops every undelivered group page");assert_eq!(rows.encounters.len(),1,"undelivered encounter drops with its rows");assert_eq!(rows.rows.medium.pages.len(),0,"unreceived medium pages are released");assert_eq!(rows.rows.full.pages.len(),0,"unreceived full pages are released");assert!(!rows.geometry(0).unwrap().4,"unreceived producer EOF cannot become received output EOF");assert!(rows.has_delivered_binding());assert!(rows.retain_delivered_using(&receipt,&a,&work).is_err());let item=&prepared[0];assert!(rows.append_produced_using(item.actual().unwrap(),item.produced(),0,path.clone(),trace.clone(),&file.lease,&file,&mut source,&a,&work).is_err());drop((source,host,rows,cursor,initial,prepared,first,receipt,foreign_token,foreign_receipt,foreign,foreign_primary,primary,arena,foreign_arena,path,trace,metadata));assert_eq!(used.load(Ordering::Acquire),0);assert_eq!(work.0.load(Ordering::Acquire),0);
 }
 #[test]fn same_actual_empty_delivery_discards_all_unreceived_rows_but_foreign_zero_cannot_bind(){
  use super::super::original_prepared_output::OriginalOutputCursor;let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let cursor=OriginalOutputCursor::new(&a).unwrap();let actual=cursor.initial_delivery().unwrap();let foreign=OriginalOutputCursor::new(&a).unwrap();let work=OutputWork(Arc::new(AtomicUsize::new(0)));let mut rows=OriginalRawOrigins::new(&a,&work).unwrap();rows.bind_output_using(&actual,&a).unwrap();assert!(rows.bind_output_using(&foreign.initial_delivery().unwrap(),&a).is_err());assert_eq!(rows.retain_delivered_using(&actual,&a,&work).unwrap(),0);assert!(rows.has_delivered_binding());drop((rows,actual,cursor,foreign));assert_eq!(used.load(Ordering::Acquire),0);
 }

}
