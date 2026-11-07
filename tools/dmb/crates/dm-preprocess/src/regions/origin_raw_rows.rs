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
struct GroupSourceGeometry {
    encounter: usize,
    decoded: Span,
    line: usize,
    output_line: usize,
    raw_base: usize,
}
impl GroupGeometry {
    fn source(self) -> GroupSourceGeometry {
        GroupSourceGeometry {
            encounter: self.encounter, decoded: self.decoded, line: self.line,
            output_line: self.output_line, raw_base: self.raw_base,
        }
    }
}
impl GroupSourceGeometry {
    fn with_output(self, output_base: usize) -> GroupGeometry {
        GroupGeometry {
            encounter: self.encounter, decoded: self.decoded, line: self.line,
            output_line: self.output_line, raw_base: self.raw_base, output_base,
        }
    }
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
#[derive(Clone,Copy)]
struct NarrowRow {
    tag: u8,
    fields: [u8; 3],
}
impl NarrowRow {
    const EOF: u8 = 1;
    const TRAILING: u8 = 2;
    const DUAL_WIDTH: u8 = 4;
    const SIDE_WIDTH: u8 = 8;
    const ESCAPE: u8 = 12;
    const MEDIUM: u8 = Self::ESCAPE;
    const FULL: u8 = Self::ESCAPE | Self::EOF;
    const MODE: u8 = 12;

    fn pack(row: Row, [output, cover, token, decoded, raw, raw_width]: [usize; 6]) -> Option<Self> {
        let trailing = cover.checked_sub(token)?;
        if trailing > 1 || decoded != raw { return None; }
        let (width, mode) = if let Some((width, dual)) = narrow_width_pair(token, raw_width) {
            (width, if dual { Self::DUAL_WIDTH } else { 0 })
        } else {
            // Retain every old inline geometry. Only its independent raw
            // width moves to the real page's ranked byte storage.
            u8::try_from(raw_width).ok()?;
            (u8::try_from(token).ok()?, Self::SIDE_WIDTH)
        };
        let fields = [u8::try_from(output).ok()?, u8::try_from(raw).ok()?, width];
        let tag = (if row.actual_eof { Self::EOF } else { 0 })
            | (if trailing != 0 { Self::TRAILING } else { 0 }) | mode;
        Some(Self { tag, fields })
    }

    fn escape(class: u8, index: usize) -> Self {
        // Each page contributes at most one side record per cell. Only the
        // page-local index is encoded in the payload.
        assert!(index < ROW_PAGE_LEN);
        let [low, high] = (index as u16).to_le_bytes();
        Self { tag: class, fields: [low, high, 0] }
    }

    fn with_projected_kind(mut self, kind: Option<dm_syntax::TokenKind>) -> Self {
        use dm_syntax::TokenKind::*;
        let code = match kind {
            None => 0,
            Some(Ident) => 1, Some(Number) => 2, Some(String) => 3,
            Some(Resource) => 4, Some(Interpolation) => 5, Some(Operator) => 6,
            Some(Punctuation) => 7, Some(Whitespace) => 8, Some(Newline) => 9,
            Some(Comment) => 10, Some(Unknown) => 11,
        };
        // Every physical escape still has this one central cell. Side rows
        // retain their entire old group index and coordinate geometry.
        self.tag |= code << 4;
        self
    }

    fn projected_kind(&self) -> Option<dm_syntax::TokenKind> {
        use dm_syntax::TokenKind::*;
        let code = (self.tag >> 4).checked_sub(1)? as usize;
        [Ident, Number, String, Resource, Interpolation, Operator, Punctuation,
         Whitespace, Newline, Comment, Unknown].get(code).copied()
    }

    fn class(&self) -> u8 {
        if self.tag & Self::MODE == Self::ESCAPE { self.tag & Self::FULL }
        else { self.tag & Self::EOF }
    }
    fn needs_raw_width(&self) -> bool { self.tag & Self::MODE == Self::SIDE_WIDTH }
    fn token_width(&self) -> usize {
        if self.tag & Self::MODE == Self::DUAL_WIDTH { usize::from(self.fields[2] >> 4) }
        else { usize::from(self.fields[2]) }
    }
    fn escape_index(&self) -> usize {
        usize::from(u16::from_le_bytes([self.fields[0], self.fields[1]]))
    }
    fn offsets(&self, side: impl FnOnce() -> Option<u8>) -> Option<[usize; 6]> {
        let output = usize::from(self.fields[0]);
        let raw = usize::from(self.fields[1]);
        let token = self.token_width();
        let width = match self.tag & Self::MODE {
            Self::DUAL_WIDTH => usize::from(self.fields[2] & 15),
            Self::SIDE_WIDTH => usize::from(side()?),
            _ => token,
        };
        Some([output, token + usize::from(self.tag & Self::TRAILING != 0), token, raw, raw, width])
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

    fn grow_rows<T>(&mut self, rows: &mut Vec<T>, extra: usize, a: &SettingAdmission<'_>) -> io::Result<()> {
        if rows.len() < rows.capacity() { return Ok(()); }
        let capacity = rows.capacity().checked_add(extra).ok_or(io::ErrorKind::OutOfMemory)?;
        let mut next = self.allocate(capacity, a)?;
        next.append(rows);
        let old = std::mem::replace(rows, next);
        self.release(old)
    }

    fn release<T>(&mut self, rows: Vec<T>) -> io::Result<()> {
        let bytes = rows.capacity() * std::mem::size_of::<T>();
        drop(rows);
        if bytes != 0 { self.work.shrink(self.credit, bytes)?; }
        Ok(())
    }
}

const ROW_PAGE_LEN: usize = 4096;
const _: () = assert!(std::mem::size_of::<NarrowRow>() == 4);
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

// Group geometry shares encounter and output-line bases from the rank
// page. The two reserved output words select ordered exact side storage.
#[repr(transparent)]
struct PackedGroup([u16; 4]);
const _: () = assert!(std::mem::size_of::<PackedGroup>() == 8);

impl PackedGroup {
    const OLD: u16 = u16::MAX - 1;
    const FULL: u16 = u16::MAX;

    fn pack(old: &OldPackedGroup) -> Option<Self> {
        let [low, high, width, line, output] = old.0;
        if high >= 1 << 8 || width >= 1 << 12 || line >= 1 << 12 || output >= Self::OLD {
            return None;
        }
        Some(Self([low, high | (width << 8), (width >> 8) | (line << 4), output]))
    }

    fn unpack(&self) -> Option<OldPackedGroup> {
        let [low, high, width_line, output] = self.0;
        if output >= Self::OLD { return None; }
        Some(OldPackedGroup([low, high & 255, (high >> 8) | ((width_line & 15) << 8),
            width_line >> 4, output]))
    }

    fn is_full(&self) -> bool { self.0[3] == Self::FULL }
    fn is_old(&self) -> bool { self.0[3] == Self::OLD }
    fn old() -> Self { Self([0, 0, 0, Self::OLD]) }
    fn full() -> Self { Self([0, 0, 0, Self::FULL]) }
}

#[repr(transparent)]
struct OldPackedGroup([u16; 5]);

// Keep the previous compact geometry for common, modest overflows without
// allocating a full source record. Only a larger group ordinal needs full.
#[repr(transparent)]
struct OldGroupSide([u16; 7]);
const _: () = assert!(std::mem::size_of::<OldGroupSide>() == 14);
impl OldGroupSide {
    fn new(ordinal: usize, row: &OldPackedGroup) -> Option<Self> {
        let ordinal = u32::try_from(ordinal).ok()?;
        let [a, b, c, d, e] = row.0;
        Some(Self([ordinal as u16, (ordinal >> 16) as u16, a, b, c, d, e]))
    }

    fn ordinal(&self) -> usize {
        (u32::from(self.0[0]) | (u32::from(self.0[1]) << 16)) as usize
    }

    fn row(&self) -> OldPackedGroup {
        let [_, _, a, b, c, d, e] = self.0;
        OldPackedGroup([a, b, c, d, e])
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
    encounter_base: usize,
    encounters: RowGroupRank,
    bits: [u64; TRACE_WORDS],
    before_word: [u16; TRACE_WORDS],
}

impl GroupTracePage {
    fn new(before_page: usize, output_line_base: usize, encounter_base: usize) -> Self {
        Self {
            before_page, output_line_base, encounter_base, encounters: RowGroupRank::new(),
            bits: [0; TRACE_WORDS], before_word: [0; TRACE_WORDS],
        }
    }

    fn encounter(&self, index: usize) -> Option<usize> {
        self.encounter_base.checked_add(self.encounters.through(index))
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
        self.encounters.truncate(keep);
        // A later append reissues each word's count at its first bit.
    }
}
impl GroupGeometry {
    fn pack(self, output_line_base: usize) -> Option<OldPackedGroup> {
        if self.raw_base != self.decoded.start { return None; }
        let width = u16::try_from(self.decoded.end.checked_sub(self.decoded.start)?).ok()?;
        let start = u32::try_from(self.decoded.start).ok()?;
        let line = u16::try_from(self.line).ok()?;
        let output_delta = u16::try_from(self.output_line.checked_sub(output_line_base)?).ok()?;
        if output_delta == PackedGroup::FULL { return None; }
        Some(OldPackedGroup([start as u16, (start >> 16) as u16, width, line, output_delta]))
    }

    fn unpack(packed: &OldPackedGroup, output_line_base: usize, encounter: usize) -> Option<GroupSourceGeometry> {
        let [low, high, width, line, output_delta] = packed.0;
        if output_delta == PackedGroup::FULL { return None; }
        let start = usize::try_from(u32::from(low) | (u32::from(high) << 16)).ok()?;
        let end = start.checked_add(usize::from(width))?;
        Some(GroupSourceGeometry {
            encounter, decoded: Span::new(start, end), line: usize::from(line),
            output_line: output_line_base.checked_add(usize::from(output_delta))?, raw_base: start,
        })
    }
}

// Match the physical trace page width. A short prefix is still directly
// indexed until a real, nonadjacent repeat of the exact empty owner occurs.
const TRACE_RUN_PAGE_LEN: usize = 128;

struct TraceRunRank {
    stored_before: usize,
    bits: [u64; 2],
}

impl TraceRunRank {
    fn new(stored_before: usize) -> Self {
        Self { stored_before, bits: [0; 2] }
    }

    fn stored(&self, local: usize) -> bool {
        self.bits[local / 64] & (1 << (local % 64)) != 0
    }

    fn before(&self, local: usize) -> usize {
        let word = local / 64;
        let mask = (1u64 << (local % 64)) - 1;
        let preceding_words = if word == 0 { 0 } else { self.bits[0].count_ones() as usize };
        self.stored_before + preceding_words + (self.bits[word] & mask).count_ones() as usize
    }

    fn append(&mut self, local: usize, stored: bool) {
        if stored { self.bits[local / 64] |= 1 << (local % 64); }
    }

    fn truncate(&mut self, keep: usize) {
        let word = keep / 64;
        self.bits[word] &= (1u64 << (keep % 64)) - 1;
        self.bits[word + 1..].fill(0);
    }
}

struct TraceRuns {
    stored: EscapePages<OriginalMacroTrace>,
    rank: FixedPages<TraceRunRank, TRACE_DIRECTORY_PAGE_LEN>,
    len: usize,
    mapped_from: Option<usize>,
    last_slot: Option<usize>,
    // Physical slot of the first actual empty owner. It stays in stored,
    // so even the canonical row keeps the original Arc and allocation.
    canonical: Option<usize>,
}

impl TraceRuns {
    fn new() -> Self {
        Self {
            stored: EscapePages::new(), rank: FixedPages::new(),
            len: 0, mapped_from: None, last_slot: None, canonical: None,
        }
    }

    fn len(&self) -> usize { self.len }

    fn physical_slot(&self, run: usize) -> Option<usize> {
        if run >= self.len { return None; }
        let Some(mapped) = self.mapped_from.and_then(|start| run.checked_sub(start)) else {
            return Some(run);
        };
        let page = self.rank.get(mapped / TRACE_RUN_PAGE_LEN)?;
        let local = mapped % TRACE_RUN_PAGE_LEN;
        if page.stored(local) { Some(page.before(local)) } else { self.canonical }
    }

    fn get(&self, run: usize) -> Option<&OriginalMacroTrace> {
        self.stored.get(self.physical_slot(run)?)
    }

    // The producer consults last on every token. Cache only the exact
    // physical index, with no new Arc alias or repeated rank lookup.
    fn last(&self) -> Option<&OriginalMacroTrace> { self.stored.get(self.last_slot?) }

    fn push(
        &mut self,
        trace: OriginalMacroTrace,
        a: &SettingAdmission<'_>,
        funding: &mut PageFunding<'_>,
    ) -> io::Result<()> {
        let len = self.len.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
        let old_rank = self.rank.len();
        let old_stored = self.stored.len();
        let repeated = self.canonical.and_then(|slot| self.stored.get(slot))
            .is_some_and(|empty| empty.same_owner(&trace));
        let first_empty = self.canonical.is_none() && trace.len() == 0;
        let mapped_from = self.mapped_from.or_else(|| repeated.then_some(self.len));
        let mapped = mapped_from.map(|start| self.len - start);

        if mapped.is_some_and(|at| at % TRACE_RUN_PAGE_LEN == 0) {
            self.rank.push(TraceRunRank::new(old_stored), a, funding)?;
        } else if repeated {
            a.checkpoint().map_err(|error| a.take_operational_error().unwrap_or(error))?;
        }
        if !repeated {
            if let Err(first) = self.stored.push(trace, a, funding) {
                let _ = self.rank.truncate(old_rank, funding);
                return Err(first);
            }
        }
        if let Some(at) = mapped {
            self.rank.get_mut(at / TRACE_RUN_PAGE_LEN).expect("issued trace run rank")
                .append(at % TRACE_RUN_PAGE_LEN, !repeated);
        }
        if first_empty { self.canonical = Some(old_stored); }
        self.mapped_from = mapped_from;
        self.last_slot = if repeated { self.canonical } else { Some(old_stored) };
        self.len = len;
        Ok(())
    }

    fn truncate(&mut self, len: usize, funding: &mut PageFunding<'_>) -> io::Result<()> {
        assert!(len <= self.len);
        if len == self.len { return Ok(()); }
        let mapped = self.mapped_from.map_or(0, |start| len.saturating_sub(start));
        let stored = if let Some(last) = mapped.checked_sub(1) {
            let page = self.rank.get(last / TRACE_RUN_PAGE_LEN).expect("issued trace run rank");
            let local = last % TRACE_RUN_PAGE_LEN;
            page.before(local) + usize::from(page.stored(local))
        } else {
            len
        };
        let pages = mapped.div_ceil(TRACE_RUN_PAGE_LEN);
        let last_slot = len.checked_sub(1).and_then(|run| self.physical_slot(run));
        let stored_status = self.stored.truncate(stored, funding);
        let rank_status = self.rank.truncate(pages, funding);
        if mapped == 0 {
            self.mapped_from = None;
        } else if mapped % TRACE_RUN_PAGE_LEN != 0 {
            self.rank.get_mut(pages - 1).expect("issued partial trace run rank")
                .truncate(mapped % TRACE_RUN_PAGE_LEN);
        }
        if self.canonical.is_some_and(|slot| slot >= stored) { self.canonical = None; }
        self.last_slot = last_slot;
        self.len = len;
        // Finish both geometry trims after physical releases. Preserve the
        // first error, including a failed source-credit reconciliation.
        stored_status.and(rank_status)
    }

    fn visit_storage(&self, visit: &mut impl FnMut(usize, usize, usize)) {
        self.stored.visit_storage(&mut *visit);
        self.rank.visit_storage(visit);
    }

    #[cfg(debug_assertions)]
    fn trace_capacity(&self) -> (usize, usize, usize) {
        let (mut owners, mut mapping) = (0usize, 0usize);
        self.stored.visit_storage(|_, _, bytes| owners = owners.saturating_add(bytes));
        self.rank.visit_storage(|_, _, bytes| mapping = mapping.saturating_add(bytes));
        (self.len - self.stored.len(), owners, mapping)
    }
}

struct OriginGroups {
    packed: OriginPages<PackedGroup>,
    old: EscapePages<OldGroupSide>,
    full: EscapePages<(usize, GroupGeometry)>,
    trace_pages: FixedPages<GroupTracePage, TRACE_DIRECTORY_PAGE_LEN>,
    traces: TraceRuns,
}
impl OriginGroups {
    fn new() -> Self {
        Self {
            packed: OriginPages::new(), old: EscapePages::new(), full: EscapePages::new(),
            trace_pages: FixedPages::new(), traces: TraceRuns::new(),
        }
    }

    fn len(&self) -> usize {
        self.packed.len()
    }

    fn trace_run(&self, ordinal: usize) -> Option<usize> {
        self.trace_pages.get(ordinal / ROW_PAGE_LEN)?.run(ordinal % ROW_PAGE_LEN)
    }

    fn get(&self, ordinal: usize) -> Option<(GroupSourceGeometry, &OriginalMacroTrace)> {
        Some((self.source_geometry(ordinal)?, self.traces.get(self.trace_run(ordinal)?)?))
    }

    fn source_geometry(&self, ordinal: usize) -> Option<GroupSourceGeometry> {
        let packed = self.packed.get(ordinal)?;
        if packed.is_full() {
            let at = self.full.partition_point(|_, (at, _)| *at < ordinal);
            return self.full.get(at).filter(|(at, _)| *at == ordinal).map(|(_, geometry)| geometry.source());
        }
        let old = if packed.is_old() {
            let at = self.old.partition_point(|_, row| row.ordinal() < ordinal);
            self.old.get(at).filter(|row| row.ordinal() == ordinal)?.row()
        } else {
            packed.unpack()?
        };
        let page = self.trace_pages.get(ordinal / ROW_PAGE_LEN)?;
        GroupGeometry::unpack(&old, page.output_line_base, page.encounter(ordinal % ROW_PAGE_LEN)?)
    }

    #[cfg(test)]
    fn last(&self) -> Option<(GroupSourceGeometry, &OriginalMacroTrace)> {
        Some((self.source_geometry(self.len().checked_sub(1)?)?, self.traces.last()?))
    }

    fn push(
        &mut self, geometry: GroupGeometry, trace: OriginalMacroTrace,
        a: &SettingAdmission<'_>, funding: &mut PageFunding<'_>,
    ) -> io::Result<()> {
        let ordinal = self.len();
        let previous_old = self.old.len();
        let previous_full = self.full.len();
        let previous_pages = self.trace_pages.len();
        let before = self.traces.len();
        let changed = self.traces.last().is_none_or(|prior| !prior.same_owner(&trace));
        let local = ordinal % ROW_PAGE_LEN;
        let new_page = local == 0;
        let (output_line_base, encounter, encounter_count) = if new_page {
            (geometry.output_line, geometry.encounter, 0)
        } else {
            let page = self.trace_pages.get(ordinal / ROW_PAGE_LEN)
                .expect("issued group trace rank page");
            let count = page.encounters.through(local - 1);
            let encounter = page.encounter_base.checked_add(count).ok_or(io::ErrorKind::InvalidData)?;
            (page.output_line_base, encounter, count)
        };
        // The real append path reuses its current encounter or creates its
        // immediate successor. Preserve any other exact geometry in the
        // existing full escape without letting it change the rank cursor.
        let encounter_changed = encounter.checked_add(1) == Some(geometry.encounter);
        let inline_encounter = encounter == geometry.encounter || encounter_changed;
        let packed = if inline_encounter { geometry.pack(output_line_base) } else { None };
        let result = (|| {
            let cell = if let Some(cell) = packed.as_ref().and_then(PackedGroup::pack) {
                cell
            } else if let Some(side) = packed.as_ref().and_then(|row| OldGroupSide::new(ordinal, row)) {
                self.old.push(side, a, funding)?;
                PackedGroup::old()
            } else {
                self.full.push((ordinal, geometry), a, funding)?;
                PackedGroup::full()
            };
            if new_page {
                self.trace_pages.push(GroupTracePage::new(before, output_line_base, geometry.encounter), a, funding)?;
            }
            if changed {
                self.traces.push(trace, a, funding)?;
            }
            self.packed.push(cell, a, funding)
        })();
        if let Err(first) = result {
            // No trace bit has been published. Drop only rows added by this
            // attempt and never replace the first original allocation error.
            let _ = self.old.truncate(previous_old, funding);
            let _ = self.full.truncate(previous_full, funding);
            let _ = self.traces.truncate(before, funding);
            let _ = self.trace_pages.truncate(previous_pages, funding);
            return Err(first);
        }
        let page = self.trace_pages.get_mut(ordinal / ROW_PAGE_LEN).expect("issued trace rank page");
        page.append(local, before, changed);
        page.encounters.append(local, encounter_count, encounter_changed);
        Ok(())
    }

    fn truncate(&mut self, len: usize, funding: &mut PageFunding<'_>) -> io::Result<()> {
        if len == self.len() { return Ok(()); }
        let old = self.old.partition_point(|_, row| row.ordinal() < len);
        let full = self.full.partition_point(|_, (at, _)| *at < len);
        let traces = match len.checked_sub(1) {
            Some(last) => self.trace_run(last).and_then(|run| run.checked_add(1)).ok_or(io::ErrorKind::InvalidData)?,
            None => 0,
        };
        let pages = len.div_ceil(ROW_PAGE_LEN);
        self.packed.truncate(len, funding)?;
        self.old.truncate(old, funding)?;
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
        self.old.visit_storage(&mut visit);
        self.full.visit_storage(&mut visit);
        self.trace_pages.visit_storage(&mut visit);
        self.traces.visit_storage(&mut visit);
    }

    #[cfg(debug_assertions)]
    fn trace_capacity(&self) -> (usize, usize, usize) {
        if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some() {
            let mut central = 0usize;
            let mut old = 0usize;
            let mut full = 0usize;
            self.packed.visit_storage(|_, _, n| central = central.saturating_add(n));
            self.old.visit_storage(|_, _, n| old = old.saturating_add(n));
            self.full.visit_storage(|_, _, n| full = full.saturating_add(n));
            eprintln!("ORIGINAL_ORIGIN_GROUP_GEOMETRY central_bytes={central} old_side_bytes={old} full_side_bytes={full}");
        }
        let mut rank_bytes = 0usize;
        self.trace_pages.visit_storage(|_, _, bytes| rank_bytes = rank_bytes.saturating_add(bytes));
        let (_, owners, mapping) = self.traces.trace_capacity();
        (self.traces.len(), rank_bytes, owners.saturating_add(mapping))
    }
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

// One physical row page owns its output bases in group-rank order. The
// first group can continue the preceding page. Anchors are its actual
// absolute values, and a wide cell keeps its exact local rank and base.
struct RowOutputBases {
    compact: Vec<u16>,
    anchors: Vec<usize>,
    wide: Vec<WideOutputBase>,
}

#[repr(transparent)]
struct WideOutputBase([u16; 5]);
const _: () = assert!(std::mem::size_of::<WideOutputBase>() == 10);

impl WideOutputBase {
    fn new(rank: usize, value: usize) -> io::Result<Self> {
        let rank = u16::try_from(rank).map_err(|_| io::ErrorKind::InvalidData)?;
        let value = u64::try_from(value).map_err(|_| io::ErrorKind::InvalidData)?;
        Ok(Self([rank, value as u16, (value >> 16) as u16,
            (value >> 32) as u16, (value >> 48) as u16]))
    }

    fn rank(&self) -> usize { usize::from(self.0[0]) }

    fn value(&self) -> Option<usize> {
        let [_, a, b, c, d] = self.0;
        usize::try_from(u64::from(a) | (u64::from(b) << 16)
            | (u64::from(c) << 32) | (u64::from(d) << 48)).ok()
    }
}

impl RowOutputBases {
    const BLOCK: usize = 128;
    const ESCAPE: u16 = u16::MAX;

    fn new() -> Self {
        Self { compact: Vec::new(), anchors: Vec::new(), wide: Vec::new() }
    }

    fn push(&mut self, value: usize, a: &SettingAdmission<'_>, funding: &mut PageFunding<'_>) -> io::Result<()> {
        let rank = self.compact.len();
        let starts_block = rank % Self::BLOCK == 0;
        let delta = if starts_block {
            0
        } else {
            value.checked_sub(self.anchors[rank / Self::BLOCK])
                .and_then(|delta| u16::try_from(delta).ok())
                .unwrap_or(Self::ESCAPE)
        };
        funding.grow_rows(&mut self.compact, Self::BLOCK, a)?;
        if starts_block {
            funding.grow_rows(&mut self.anchors, 4, a)?;
            self.anchors.push(value);
        } else if delta == Self::ESCAPE {
            let escape = WideOutputBase::new(rank, value)?;
            funding.grow_rows(&mut self.wide, 16, a)?;
            self.wide.push(escape);
        }
        // The anchor/escape is funded and the compact cell cannot fail.
        self.compact.push(delta);
        Ok(())
    }

    fn get(&self, rank: usize) -> Option<usize> {
        let delta = *self.compact.get(rank)?;
        if delta == Self::ESCAPE {
            let index = self.wide.binary_search_by_key(&rank, WideOutputBase::rank).ok()?;
            self.wide[index].value()
        } else {
            self.anchors.get(rank / Self::BLOCK)?.checked_add(usize::from(delta))
        }
    }

    fn truncate(&mut self, keep: usize, funding: &mut PageFunding<'_>) -> io::Result<()> {
        self.compact.truncate(keep);
        self.anchors.truncate(keep.div_ceil(Self::BLOCK));
        let wide = self.wide.partition_point(|escape| escape.rank() < keep);
        if wide == 0 { funding.release(std::mem::take(&mut self.wide))?; }
        else { self.wide.truncate(wide); }
        Ok(())
    }

    fn visit_storage(&self, visit: &mut impl FnMut(usize, usize, usize)) {
        fn rows<T>(rows: &Vec<T>, visit: &mut impl FnMut(usize, usize, usize)) {
            if rows.capacity() != 0 {
                visit(rows.as_ptr() as usize, rows.len(),
                    rows.capacity() * std::mem::size_of::<T>());
            }
        }
        rows(&self.compact, visit);
        rows(&self.anchors, visit);
        rows(&self.wide, visit);
    }
}

struct RankedRawWidths {
    rank: RowGroupRank,
    widths: Vec<u8>,
}
impl RankedRawWidths {
    fn new(a: &SettingAdmission<'_>, funding: &mut PageFunding<'_>) -> io::Result<Box<Self>> {
        // The standard Box takes the same one-element Global allocation.
        let mut backing = funding.allocate::<Self>(1, a)?;
        backing.push(Self { rank: RowGroupRank::new(), widths: Vec::new() });
        let pointer = backing.as_mut_ptr();
        std::mem::forget(backing);
        // SAFETY: allocation has exactly Layout::array::<Self>(1), with its
        // sole Self initialized. Box uses the identical Global drop layout.
        Ok(unsafe { Box::from_raw(pointer) })
    }

    fn get(&self, local: usize) -> Option<u8> {
        self.widths.get(self.rank.through(local).checked_sub(1)?).copied()
    }
}

// Same NarrowRow tags and exact [6,6,4] payload geometry. Only the
// unchanged medium/full escape cells and non-fitting original cells use
// the independent 4B column.
#[repr(transparent)]
struct ShortOriginCell([u8;3]);
impl ShortOriginCell {
    fn pack(row: NarrowRow) -> Option<Self> {
        if row.tag & NarrowRow::MODE == NarrowRow::ESCAPE { return None; }
        let [out, raw, width] = row.fields;
        let width = if row.tag & NarrowRow::MODE == NarrowRow::DUAL_WIDTH {
            let (token, raw) = (width >> 4, width & 15);
            if token >= 4 || raw >= 4 { return None; }
            (token << 2) | raw
        } else { width };
        if out >= 64 || raw >= 64 || width >= 16 { return None; }
        let payload = u16::from(out) | (u16::from(raw) << 6) | (u16::from(width) << 12);
        let [lo, hi] = payload.to_le_bytes();
        Some(Self([row.tag, lo, hi]))
    }
    fn unpack(&self) -> NarrowRow {
        let [tag, lo, hi] = self.0;
        let payload = u16::from_le_bytes([lo, hi]);
        let mut width = (payload >> 12) as u8;
        if tag & NarrowRow::MODE == NarrowRow::DUAL_WIDTH {
            width = ((width >> 2) << 4) | (width & 3);
        }
        NarrowRow { tag, fields:[(payload & 63) as u8, ((payload >> 6) & 63) as u8, width] }
    }
}
const _: () = assert!(std::mem::size_of::<ShortOriginCell>() == 3);

struct MixedOriginCells {
    // Rank contains the count of unchanged four-byte cells through local.
    rank: RowGroupRank,
    short: Vec<ShortOriginCell>,
    four: Vec<NarrowRow>,
}
impl MixedOriginCells {
    fn len(&self) -> usize { self.short.len() + self.four.len() }
    fn cell(&self, local: usize) -> Option<NarrowRow> {
        if local >= self.len() { return None; }
        let four = self.rank.through(local);
        if self.rank.bits[local / TRACE_WORD_BITS] & (1 << (local % TRACE_WORD_BITS)) != 0 {
            self.four.get(four - 1).copied()
        } else {
            self.short.get(local - four).map(ShortOriginCell::unpack)
        }
    }
    fn bytes(&self) -> usize {
        std::mem::size_of::<Self>() + self.short.capacity() * std::mem::size_of::<ShortOriginCell>()
            + self.four.capacity() * std::mem::size_of::<NarrowRow>()
    }
    fn truncate(&mut self, keep: usize) {
        let four = self.rank.through(keep - 1);
        self.short.truncate(keep - four);
        self.four.truncate(four);
        self.rank.truncate(keep);
    }
}

// One source-budget owner for one physical token page and all of its exact
// token geometry. Global source groups/trace owners and the page directory
// are deliberately outside this owner.
struct PhysicalOriginPage {
    narrow: Vec<NarrowRow>,
    mixed: Option<Box<MixedOriginCells>>,
    rank: RowGroupRank,
    output_bases: RowOutputBases,
    raw_widths: Option<Box<RankedRawWidths>>,
    medium: FixedPages<MediumRow, 16>,
    full: FixedPages<Row, 16>,
    group_base: usize,
    credit: SourceArenaCredit,
}

impl PhysicalOriginPage {
    fn control_bytes() -> usize {
        use std::alloc::Layout;
        Layout::new::<[usize; 2]>().extend(Layout::new::<Self>())
            .expect("physical page Arc layout").0.pad_to_align().size()
    }

    fn new(group_base: usize, work: &dyn SourceArenaWork) -> io::Result<Self> {
        let credit = work.reserve_original_origin_storage(Self::control_bytes())?;
        Ok(Self {
            narrow: Vec::new(), mixed: None, rank: RowGroupRank::new(),
            output_bases: RowOutputBases::new(), raw_widths: None,
            medium: FixedPages::new(), full: FixedPages::new(), group_base, credit,
        })
    }

    fn len(&self) -> usize { self.mixed.as_ref().map_or(self.narrow.len(), |mixed| mixed.len()) }

    fn cell(&self, local: usize) -> Option<NarrowRow> {
        match &self.mixed {
            Some(mixed) => mixed.cell(local),
            None => self.narrow.get(local).copied(),
        }
    }

    fn settle_full_columns(&mut self, a: &SettingAdmission<'_>, work: &dyn SourceArenaWork) -> io::Result<()> {
        if self.mixed.is_some() || self.narrow.len() != ROW_PAGE_LEN { return Ok(()); }
        let short = self.narrow.iter().filter(|&&row| ShortOriginCell::pack(row).is_some()).count();
        let four = ROW_PAGE_LEN - short;
        let box_bytes = std::mem::size_of::<MixedOriginCells>();
        let bytes = box_bytes + short * std::mem::size_of::<ShortOriginCell>()
            + four * std::mem::size_of::<NarrowRow>();
        let old = self.narrow.capacity() * std::mem::size_of::<NarrowRow>();
        if bytes >= old || !work.try_grow_original_origin_storage(&mut self.credit, bytes)? { return Ok(()); }

        let build = || -> io::Result<Box<MixedOriginCells>> {
            a.checkpoint().map_err(|error| a.take_operational_error().unwrap_or(error))?;
            let mut packed = exact_rows(short, a)?;
            let mut old_cells = exact_rows(four, a)?;
            let mut rank = RowGroupRank::new();
            for (at, &row) in self.narrow.iter().enumerate() {
                let before = old_cells.len();
                if let Some(cell) = ShortOriginCell::pack(row) { packed.push(cell); }
                else { old_cells.push(row); }
                rank.append(at, before, before != old_cells.len());
            }
            // The optional family grant includes the exact nonzero Global
            // layout. No old physical storage is returned on first failure.
            let pointer = std::ptr::NonNull::new(unsafe { std::alloc::alloc(
                std::alloc::Layout::new::<MixedOriginCells>()) }.cast::<MixedOriginCells>())
                .ok_or(io::ErrorKind::OutOfMemory)?;
            // SAFETY: pointer is one funded Global cell; write once before
            // Box assumes its ordinary drop layout.
            Ok(unsafe {
                pointer.as_ptr().write(MixedOriginCells { rank, short: packed, four: old_cells });
                Box::from_raw(pointer.as_ptr())
            })
        };
        let mixed = match build() {
            Ok(mixed) => mixed,
            Err(first) => { let _=work.shrink(&mut self.credit, bytes); return Err(first); }
        };
        self.mixed = Some(mixed);
        drop(std::mem::take(&mut self.narrow));
        work.shrink(&mut self.credit, old)
    }

    fn resume_dense_after_trim(&mut self, a: &SettingAdmission<'_>, work: &dyn SourceArenaWork) -> io::Result<()> {
        let Some(mixed) = &self.mixed else { return Ok(()); };
        if mixed.len() == ROW_PAGE_LEN { return Err(io::ErrorKind::InvalidInput.into()); }
        let mut funding = PageFunding { work, credit: &mut self.credit };
        let mut dense = funding.allocate(ROW_PAGE_LEN, a)?;
        dense.extend((0..mixed.len()).map(|at|mixed.cell(at).expect("issued original cell")));
        let mixed = self.mixed.take().expect("actual compact cell owner");
        let bytes = mixed.bytes();
        self.narrow = dense;
        drop(mixed);
        funding.work.shrink(funding.credit, bytes)
    }

    fn push(
        &mut self, row: Row, geometry: GroupGeometry, prior_group: usize,
        kind: Option<dm_syntax::TokenKind>, a: &SettingAdmission<'_>, work: &dyn SourceArenaWork,
    ) -> io::Result<()> {
        self.resume_dense_after_trim(a, work)?;
        let local = self.narrow.len();
        assert!(local < ROW_PAGE_LEN);
        let medium_before = self.medium.len();
        let full_before = self.full.len();
        let widths_before = self.raw_widths.as_ref().map_or(0, |side| side.widths.len());
        let mut funding = PageFunding { work, credit: &mut self.credit };
        let result = (|| {
            let fields = row.offsets(geometry);
            let cell = if let Some(narrow) = fields.and_then(|fields| NarrowRow::pack(row, fields)) {
                narrow
            } else if let Some(medium) = fields.and_then(|fields| MediumRow::pack(row, fields)) {
                self.medium.push(medium, a, &mut funding)?;
                NarrowRow::escape(NarrowRow::MEDIUM, medium_before)
            } else {
                self.full.push(row, a, &mut funding)?;
                NarrowRow::escape(NarrowRow::FULL, full_before)
            };
            if cell.needs_raw_width() {
                if self.raw_widths.is_none() {
                    self.raw_widths = Some(RankedRawWidths::new(a, &mut funding)?);
                }
                let side = self.raw_widths.as_mut().expect("funded ranked raw widths");
                funding.grow_rows(&mut side.widths, 16, a)?;
                let width = fields.ok_or(io::ErrorKind::InvalidData)?[5];
                side.widths.push(u8::try_from(width).map_err(|_|io::ErrorKind::InvalidData)?);
            }
            a.checkpoint().map_err(|error| a.take_operational_error().unwrap_or(error))?;
            if self.narrow.capacity() == 0 {
                self.narrow = funding.allocate(ROW_PAGE_LEN, a)?;
            }
            if local == 0 || row.group != prior_group {
                self.output_bases.push(geometry.output_base, a, &mut funding)?;
            }
            self.narrow.push(cell.with_projected_kind(kind));
            Ok(())
        })();
        if let Err(first) = result {
            let _ = self.medium.truncate(medium_before, &mut funding);
            let _ = self.full.truncate(full_before, &mut funding);
            if widths_before == 0 {
                let _ = Self::release_raw_widths(&mut self.raw_widths, &mut funding);
            } else if let Some(side) = &mut self.raw_widths {
                side.widths.truncate(widths_before);
            }
            return Err(first);
        }
        if let Some(side) = &mut self.raw_widths {
            side.rank.append(local, widths_before, self.narrow[local].needs_raw_width());
        }
        let before = if local == 0 { 0 } else { prior_group - self.group_base };
        self.rank.append(local, before, local != 0 && row.group != prior_group);
        Ok(())
    }

    fn release_raw_widths(side: &mut Option<Box<RankedRawWidths>>, funding: &mut PageFunding<'_>) -> io::Result<()> {
        if let Some(side) = side.take() {
            let bytes = std::mem::size_of::<RankedRawWidths>() + side.widths.capacity();
            drop(side);
            funding.work.shrink(funding.credit, bytes)?;
        }
        Ok(())
    }

    fn group_at(&self, local: usize) -> Option<usize> {
        if local >= self.len() { return None; }
        self.group_base.checked_add(self.rank.through(local))
    }

    fn group_geometry(&self, local: usize, groups: &OriginGroups) -> Option<GroupGeometry> {
        if local >= self.len() { return None; }
        let rank = self.rank.through(local);
        let group = self.group_base.checked_add(rank)?;
        self.geometry_at_rank(rank, group, groups)
    }

    fn geometry_at_rank(&self, rank: usize, group: usize, groups: &OriginGroups) -> Option<GroupGeometry> {
        Some(groups.source_geometry(group)?.with_output(self.output_bases.get(rank)?))
    }

    fn decode(&self, local: usize, groups: &OriginGroups) -> Option<Row> {
        let cell = self.cell(local)?;
        let rank = self.rank.through(local);
        let group = self.group_base.checked_add(rank)?;
        let geometry = || self.geometry_at_rank(rank, group, groups);
        let row = match cell.class() {
            NarrowRow::MEDIUM => self.medium.get(cell.escape_index())?
                .unpack(|actual| if actual == group { geometry() } else { None }),
            NarrowRow::FULL => Some(*self.full.get(cell.escape_index())?),
            class => Row::from_offsets(group, geometry()?, cell.offsets(|| self.raw_widths.as_ref()?.get(local))?, class == NarrowRow::EOF),
        }?;
        (row.group == group).then_some(row)
    }

    // Reads only this exact page's issued geometry. No source-group/trace
    // loan, source provider, re-lex, or frontier/EOF grant.
    fn projected_token(&self, local: usize) -> Option<dm_syntax::SpanToken> {
        let cell = self.cell(local)?;
        let kind = cell.projected_kind()?;
        let rank = self.rank.through(local);
        let span = match cell.class() {
            NarrowRow::MEDIUM => {
                let row = self.medium.get(cell.escape_index())?;
                if usize::try_from(row.tag & !MediumRow::EOF).ok()? != self.group_base.checked_add(rank)? {
                    return None;
                }
                let start = self.output_bases.get(rank)?.checked_add(usize::from(row.fields[0]))?;
                Span::new(start, start.checked_add(usize::from(row.fields[2]))?)
            }
            NarrowRow::FULL => {
                let row = self.full.get(cell.escape_index())?;
                if row.group != self.group_base.checked_add(rank)? { return None; }
                row.token_span()
            }
            _ => {
                let start = self.output_bases.get(rank)?.checked_add(usize::from(cell.fields[0]))?;
                Span::new(start, start.checked_add(cell.token_width())?)
            }
        };
        Some(dm_syntax::SpanToken { kind, span })
    }

    fn truncate(&mut self, keep: usize, work: &dyn SourceArenaWork) -> io::Result<()> {
        assert!(keep > 0 && keep < self.len());
        let rank = self.rank.through(keep - 1);
        let (mut medium, mut full, mut widths) = (0, 0, 0);
        for local in 0..keep {
            let cell = self.cell(local).expect("issued retained row");
            widths += usize::from(cell.needs_raw_width());
            match cell.class() {
                NarrowRow::MEDIUM => medium += 1,
                NarrowRow::FULL => full += 1,
                _ => {}
            }
        }
        let mut funding = PageFunding { work, credit: &mut self.credit };
        self.output_bases.truncate(rank + 1, &mut funding)?;
        self.medium.truncate(medium, &mut funding)?;
        self.full.truncate(full, &mut funding)?;
        if widths == 0 {
            Self::release_raw_widths(&mut self.raw_widths, &mut funding)?;
        } else if let Some(side) = &mut self.raw_widths {
            side.widths.truncate(widths);
            side.rank.truncate(keep);
        }
        if let Some(mixed) = &mut self.mixed { mixed.truncate(keep); }
        else { self.narrow.truncate(keep); }
        self.rank.truncate(keep);
        Ok(())
    }
}

// No Arc/Weak escapes. The control allocation and physical page storage
// disappear before the last exact SourceArenaCredit is released.
struct PhysicalOriginPageOwner(Option<Arc<PhysicalOriginPage>>);

impl PhysicalOriginPageOwner {
    fn new(page: PhysicalOriginPage) -> Self { Self(Some(Arc::new(page))) }

    fn get(&self) -> &PhysicalOriginPage { self.0.as_deref().expect("live physical origin page") }

    fn get_mut(&mut self) -> io::Result<&mut PhysicalOriginPage> {
        Arc::get_mut(self.0.as_mut().expect("live physical origin page"))
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "shared physical origin page cannot change"))
    }

    fn loan_full(&self) -> Option<Self> {
        (self.get().len() == ROW_PAGE_LEN)
            .then(|| Self(Some(Arc::clone(self.0.as_ref().expect("live physical origin page")))))
    }

    fn visit_compact_storage(&self, visit: &mut impl FnMut(usize, usize, usize)) {
        let page = self.get();
        let bytes = PhysicalOriginPage::control_bytes();
        visit(page as *const PhysicalOriginPage as usize, bytes, bytes);
        fn column<T>(rows: &[T], capacity: usize, visit: &mut impl FnMut(usize,usize,usize)) {
            if capacity == 0 { return; }
            visit(rows.as_ptr() as usize, rows.len(), capacity * std::mem::size_of::<T>());
        }
        column(&page.narrow, page.narrow.capacity(), visit);
        if let Some(mixed) = &page.mixed {
            let bytes = std::mem::size_of::<MixedOriginCells>();
            visit(mixed.as_ref() as *const _ as usize, bytes, bytes);
            column(&mixed.short, mixed.short.capacity(), visit);
            column(&mixed.four, mixed.four.capacity(), visit);
        }
        page.output_bases.visit_storage(visit);
        if let Some(side) = &page.raw_widths {
            let bytes = std::mem::size_of::<RankedRawWidths>();
            visit(side.as_ref() as *const RankedRawWidths as usize, bytes, bytes);
            if side.widths.capacity() != 0 {
                visit(side.widths.as_ptr() as usize, side.widths.len(), side.widths.capacity());
            }
        }
        page.medium.visit_storage(visit);
    }
}

impl dm_syntax::OriginalTokenPageData for PhysicalOriginPageOwner {
    fn get(&self, ordinal: usize) -> Option<dm_syntax::SpanToken> {
        self.get().projected_token(ordinal)
    }

    fn visit_storage(&self, visit: &mut dyn FnMut(usize, usize, usize)) {
        let mut visit = visit;
        self.visit_compact_storage(&mut visit);
        self.get().full.visit_storage(&mut visit);
        self.get().credit.visit_storage(&mut |pointer, bytes| visit(pointer, 1, bytes));
    }
}

impl Drop for PhysicalOriginPageOwner {
    fn drop(&mut self) {
        if let Some(owner) = self.0.take() {
            if let Some(page) = Arc::into_inner(owner) { drop(page); }
        }
    }
}

struct RawTokenRows {
    pages: FixedPages<PhysicalOriginPageOwner, TRACE_DIRECTORY_PAGE_LEN>,
    len: usize,
    last_group: Option<usize>,
}
impl RawTokenRows {
    fn new(a: &SettingAdmission<'_>) -> io::Result<Self> {
        a.checkpoint().map_err(|error| a.take_operational_error().unwrap_or(error))?;
        Ok(Self { pages: FixedPages::new(), len: 0, last_group: None })
    }

    fn len(&self) -> usize { self.len }

    fn page(&self, index: usize) -> Option<&PhysicalOriginPage> {
        self.pages.get(index).map(PhysicalOriginPageOwner::get)
    }

    #[cfg(test)]
    fn push(&mut self, row: Row, group: GroupGeometry, a: &SettingAdmission<'_>, funding: &mut PageFunding<'_>) -> io::Result<()> {
        self.push_projected(row, group, None, a, funding)
    }

    fn push_projected(
        &mut self, row: Row, group: GroupGeometry, kind: Option<dm_syntax::TokenKind>,
        a: &SettingAdmission<'_>, funding: &mut PageFunding<'_>,
    ) -> io::Result<()> {
        let len = self.len.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
        let prior = self.last_group.unwrap_or(row.group);
        if row.group != prior && prior.checked_add(1) != Some(row.group) {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "origin row skipped its actual group"));
        }
        if self.len % ROW_PAGE_LEN == 0 {
            let mut page = PhysicalOriginPageOwner::new(PhysicalOriginPage::new(row.group, funding.work)?);
            page.get_mut()?.push(row, group, prior, kind, a, funding.work)?;
            self.pages.push(page, a, funding)?;
        } else {
            self.pages.get_mut(self.len / ROW_PAGE_LEN).expect("issued active physical page")
                .get_mut()?.push(row, group, prior, kind, a, funding.work)?;
        }
        self.len = len;
        self.last_group = Some(row.group);
        Ok(())
    }

    fn group_at(&self, ordinal: usize) -> Option<usize> {
        self.page(ordinal / ROW_PAGE_LEN)?.group_at(ordinal % ROW_PAGE_LEN)
    }

    fn group_geometry(&self, ordinal: usize, groups: &OriginGroups) -> Option<GroupGeometry> {
        self.page(ordinal / ROW_PAGE_LEN)?.group_geometry(ordinal % ROW_PAGE_LEN, groups)
    }

    fn get(&self, ordinal: usize, groups: &OriginGroups) -> Option<Row> {
        self.page(ordinal / ROW_PAGE_LEN)?.decode(ordinal % ROW_PAGE_LEN, groups)
    }

    #[cfg(any(test, debug_assertions))]
    fn projected_token(&self, ordinal: usize) -> Option<dm_syntax::SpanToken> {
        self.page(ordinal / ROW_PAGE_LEN)?.projected_token(ordinal % ROW_PAGE_LEN)
    }

    fn partition_point(&self, groups: &OriginGroups, mut before: impl FnMut(Row) -> bool) -> usize {
        let (mut left, mut right) = (0, self.len);
        while left < right {
            let mid = left + (right - left) / 2;
            if before(self.get(mid, groups).expect("issued raw origin cell coordinates")) {
                left = mid + 1;
            } else { right = mid; }
        }
        left
    }

    fn truncate(&mut self, keep: usize, funding: &mut PageFunding<'_>) -> io::Result<()> {
        assert!(keep <= self.len);
        if keep == self.len { return Ok(()); }
        let pages = keep.div_ceil(ROW_PAGE_LEN);
        let tail = keep % ROW_PAGE_LEN;
        let last_group = match keep.checked_sub(1) {
            Some(last) => Some(self.group_at(last).ok_or(io::ErrorKind::InvalidData)?),
            None => None,
        };
        // Check uniqueness before retiring any producer lookahead. A later
        // consumer must release its loan before a partial page can be edited.
        if tail != 0 {
            self.pages.get_mut(pages - 1).expect("issued partial physical page")
                .get_mut()?.truncate(tail, funding.work)?;
        }
        self.pages.truncate(pages, funding)?;
        self.len = keep;
        self.last_group = last_group;
        Ok(())
    }

    fn visit_compact_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        self.pages.visit_storage(&mut visit);
        for page in self.pages.iter() { page.visit_compact_storage(&mut visit); }
    }

    fn visit_full_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        for page in self.pages.iter() { page.get().full.visit_storage(&mut visit); }
    }

    fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        self.visit_compact_storage(&mut visit);
        self.visit_full_storage(&mut visit);
        for page in self.pages.iter() {
            page.get().credit.visit_storage(&mut |pointer, bytes| visit(pointer, 1, bytes));
        }
    }

    #[cfg(debug_assertions)]
    fn page_payload_bytes(&self) -> usize {
        self.pages.iter().map(|page| page.get().credit.reserved_bytes()).sum()
    }

    #[cfg(test)]
    fn cell(&self, ordinal: usize) -> Option<&NarrowRow> {
        self.page(ordinal / ROW_PAGE_LEN)?.narrow.get(ordinal % ROW_PAGE_LEN)
    }

    #[cfg(test)]
    fn medium_len(&self) -> usize {
        self.pages.iter().map(|page| page.get().medium.len()).sum()
    }

    #[cfg(test)]
    fn full_len(&self) -> usize {
        self.pages.iter().map(|page| page.get().full.len()).sum()
    }
}

// Shared exact width encoding for physical rows and the projection census.
fn narrow_width_pair(token: usize, raw: usize) -> Option<(u8, bool)> {
    if token == raw {
        return Some((u8::try_from(token).ok()?, false));
    }
    if token > 15 || raw > 15 { return None; }
    Some((((token as u8) << 4) | raw as u8, true))
}

// Optional, allocation-free counts at the actual successful append. Used only
// by the producer failure report, before receiver trim discards lookahead.
#[cfg(debug_assertions)]
#[derive(Debug, Default)]
struct ProjectedOriginRowCost {
    narrow_bytes: usize,
    medium_bytes: usize,
    full_bytes: usize,
    escape_directory_bytes: usize,
    // Current physical origin page only. Reset at the real page boundary.
    medium: usize,
    full: usize,
}
#[cfg(debug_assertions)]
impl ProjectedOriginRowCost {
    fn observe(&mut self, local: usize, cell_bytes: usize, class: usize) {
        const SIDE_PAGE: usize = 16;
        if local == 0 {
            self.narrow_bytes += ROW_PAGE_LEN * cell_bytes;
            self.medium = 0;
            self.full = 0;
        }
        let (side_count, row_bytes) = match class {
            1 => (&mut self.medium, std::mem::size_of::<MediumRow>()),
            2 => (&mut self.full, std::mem::size_of::<Row>()),
            _ => return,
        };
        if *side_count % SIDE_PAGE == 0 {
            let pages = *side_count / SIDE_PAGE;
            let slot_bytes = std::mem::size_of::<Vec<Row>>();
            if pages == 0 {
                self.escape_directory_bytes += 4 * slot_bytes;
            } else if pages >= 4 && pages.is_power_of_two() {
                self.escape_directory_bytes += pages * slot_bytes;
            }
            let bytes = SIDE_PAGE * row_bytes;
            if class == 1 { self.medium_bytes += bytes; }
            else { self.full_bytes += bytes; }
        }
        *side_count += 1;
    }
}
// Model two exact width-only side storage choices. Sparse adds an inline
// Vec header per page and a packed (u16 ordinal, u8 width) row with alignment.
// Ranked adds an optional pointer per page, an exact rank + Vec box on first
// use, and the one-byte payload. Both Vec capacities grow in 16-row steps.
#[cfg(debug_assertions)]
#[repr(C)]
struct ProjectedSparseWidth { local: u16, raw_width: u8 }
#[cfg(debug_assertions)]
struct ProjectedRankedWidths { _rank: RowGroupRank, _widths: Vec<u8> }
#[cfg(debug_assertions)]
#[derive(Debug, Default)]
struct ProjectedWidthOnlyCost {
    rows: usize,
    pages_with_side: usize,
    sparse_bytes: usize,
    ranked_bytes: usize,
    adaptive_steady_lower_bound_bytes: usize,
    page_side_rows: usize,
}
#[cfg(debug_assertions)]
impl ProjectedWidthOnlyCost {
    fn page_bytes(rows: usize) -> [usize; 3] {
        let capacity = rows.div_ceil(16) * 16;
        let sparse = std::mem::size_of::<Vec<ProjectedSparseWidth>>()
            + capacity * std::mem::size_of::<ProjectedSparseWidth>();
        let ranked = std::mem::size_of::<Option<Box<ProjectedRankedWidths>>>()
            + if rows == 0 { 0 } else { std::mem::size_of::<ProjectedRankedWidths>() + capacity };
        [sparse, ranked, sparse.min(ranked)]
    }

    fn observe(&mut self, local: usize, side: bool) {
        if local == 0 {
            self.page_side_rows = 0;
            self.add(Self::page_bytes(0));
        }
        if side {
            let before = Self::page_bytes(self.page_side_rows);
            if self.page_side_rows == 0 { self.pages_with_side += 1; }
            self.rows += 1;
            self.page_side_rows += 1;
            let after = Self::page_bytes(self.page_side_rows);
            self.add(std::array::from_fn(|i| after[i] - before[i]));
        }
    }

    fn add(&mut self, [sparse, ranked, adaptive]: [usize; 3]) {
        self.sparse_bytes += sparse;
        self.ranked_bytes += ranked;
        self.adaptive_steady_lower_bound_bytes += adaptive;
    }
}

/// Measure lossless 3B cells while keeping current medium/full and
/// raw-width side ownership. A new escape may refer to one exact old 4B
/// narrow row, whose own raw-width bit remains in the existing rank.
#[cfg(debug_assertions)]
#[derive(Debug)]
struct ProjectedThreeByteRows {
    bits: [u8;3],
    direct_rows: usize,
    old_narrow_escapes: usize,
    unchanged_medium_full: usize,
    useful_full_pages: usize,
    fallback_full_pages: usize,
    old_narrow_side_bytes: usize,
    projected_full_page_savings: usize,
    local_escapes: usize,
}
#[cfg(debug_assertions)]
impl ProjectedThreeByteRows {
    fn new(bits: [u8;3]) -> Self {
        Self { bits, direct_rows:0, old_narrow_escapes:0, unchanged_medium_full:0,
            useful_full_pages:0, fallback_full_pages:0, old_narrow_side_bytes:0,
            projected_full_page_savings:0, local_escapes:0 }
    }
    fn observe(&mut self, local: usize, fields: Option<[usize;6]>, old_narrow: bool, old_inline_width: bool) {
        if local == 0 { self.local_escapes = 0; }
        if old_narrow {
            let [out_bits, raw_bits, width_bits]=self.bits;
            let fits=fields.is_some_and(|[out, _, token, _, raw, raw_width]|{
                out < (1 << out_bits) && raw < (1 << raw_bits)
                    && if token != raw_width && old_inline_width {
                        token < (1 << (width_bits / 2)) && raw_width < (1 << (width_bits - width_bits / 2))
                    } else {
                        token < (1 << width_bits)
                    }
            });
            if fits { self.direct_rows += 1; }
            else { self.old_narrow_escapes += 1; self.local_escapes += 1; }
        } else {
            self.unchanged_medium_full += 1;
        }
        if local + 1 != ROW_PAGE_LEN { return; }
        // An in-cell 12-bit escape ordinal addresses the exact old rows.
        // Model a single exact-fit Vec for these immutable fallback rows,
        // one Vec Box payload only when nonempty, and a pointer per row page.
        let side = if self.local_escapes == 0 { 0 } else {
            self.local_escapes * std::mem::size_of::<NarrowRow>()
                + std::mem::size_of::<Vec<NarrowRow>>()
        };
        let savings = ROW_PAGE_LEN.saturating_sub(side + std::mem::size_of::<usize>());
        if savings == 0 { self.fallback_full_pages += 1; }
        else {
            self.useful_full_pages += 1;
            self.old_narrow_side_bytes += side;
            self.projected_full_page_savings += savings;
        }
    }
}

#[cfg(debug_assertions)]
#[derive(Debug)]
pub(super) struct RawRowGeometryCensus {
    previous_group: Option<usize>,
    group_jumps: usize,
    // Every array is [inline, medium, full], including the existing layout.
    current: [usize; 3],
    six_byte: [usize; 3],
    five_byte: [usize; 3],
    four_byte: [usize; 3],
    five_page_cost: ProjectedOriginRowCost,
    four_page_cost: ProjectedOriginRowCost,
    // Add each width_side storage estimate to this shared 4B+geometry cost.
    four_width_side_base_cost: ProjectedOriginRowCost,
    width_side: ProjectedWidthOnlyCost,
    // [inline, full] under the 16-byte group shape. The base is reset on
    // each real group page, even if its first cell needs a full escape.
    group_16_byte: [usize; 2],
    group_10_byte: [usize; 2],
    // [inline 8, exact old 10 on the side, full geometry].
    group_8_byte: [usize; 3],
    group_count: usize,
    group_output_line_base: usize,
    three_byte_models: [ProjectedThreeByteRows;4],
}

#[cfg(debug_assertions)]
impl Default for RawRowGeometryCensus {
    fn default() -> Self {
        Self {
            previous_group: None, group_jumps: 0, current: [0;3], six_byte: [0;3], five_byte: [0;3], four_byte: [0;3],
            five_page_cost: Default::default(), four_page_cost: Default::default(),
            four_width_side_base_cost: Default::default(), width_side: Default::default(),
            group_16_byte: [0;2], group_10_byte: [0;2], group_8_byte: [0;3],
            group_count: 0, group_output_line_base: 0,
            three_byte_models: [
                ProjectedThreeByteRows::new([6,6,4]), ProjectedThreeByteRows::new([7,5,4]),
                ProjectedThreeByteRows::new([7,6,3]), ProjectedThreeByteRows::new([5,7,4]),
            ],
        }
    }
}

#[cfg(debug_assertions)]
impl RawRowGeometryCensus {
    fn observe_group(&mut self, geometry: GroupGeometry, cell: &PackedGroup) {
        self.group_10_byte[usize::from(cell.is_full())] += 1;
        self.group_8_byte[if cell.is_full() { 2 } else { usize::from(cell.is_old()) }] += 1;
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

    fn observe(&mut self, row: Row, geometry: GroupGeometry, page_base: usize, local: usize) {
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
        let four = five && fields.is_some_and(|[_, _, token, _, _, width]| narrow_width_pair(token, width).is_some());
        self.five_page_cost.observe(local, 5, if five { 0 } else { fallback });
        self.four_page_cost.observe(local, 4, if four { 0 } else { fallback });
        self.four_width_side_base_cost.observe(local, 4, if five { 0 } else { fallback });
        self.width_side.observe(local, five && !four);
        for model in &mut self.three_byte_models { model.observe(local,fields,five,four); }
        for (counts, eligible) in [(&mut self.current, current), (&mut self.six_byte, six),
                                   (&mut self.five_byte, five), (&mut self.four_byte, four)] {
            let count = &mut counts[if eligible { 0 } else { fallback }];
            *count = count.saturating_add(1);
        }
    }
}

/// The exact last successful producer append. Never a published mapping
/// or a source authorization; all current acquisition/point checks still run.
#[derive(Clone, Copy)]
struct LastEmitted {
    geometry: GroupGeometry,
    cover_end: usize,
}

#[derive(Clone, Copy)]
struct NonphysicalToken {
    token: dm_syntax::SpanToken,
    cover: Span,
}

pub(super) struct OriginalRawOrigins{
 last_emitted:Option<LastEmitted>,
 #[cfg(debug_assertions)]
 row_geometry_census:Option<RawRowGeometryCensus>,
 rows:RawTokenRows,groups:OriginGroups,encounters:Rows<Encounter>,nonphysical:Rows<NonphysicalToken>,output:Option<super::original_prepared_output::OriginalOutputIdentity>,delivered_end:Option<usize>,domain:SettingRootLease,page_credit:SourceArenaCredit}
impl std::fmt::Debug for OriginalRawOrigins{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("OriginalRawOrigins").field("rows",&self.rows.len()).finish()}}
impl OriginalRawOrigins{
 pub(super) fn new(a:&SettingAdmission<'_>,work:&dyn SourceArenaWork)->io::Result<Self>{Ok(Self{
  last_emitted:None,
  #[cfg(debug_assertions)]
  row_geometry_census:std::env::var_os("DMB_ORIGINAL_TRACE_ROW_GEOMETRY").map(|_|RawRowGeometryCensus::default()),
  rows:RawTokenRows::new(a)?,groups:OriginGroups::new(),encounters:Rows::new(a)?,nonphysical:Rows::new(a)?,output:None,delivered_end:None,domain:a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?,page_credit:work.reserve_original_origin_storage(0)?})}
 /// The actual controller records once beside its final arena append. The
 /// private actual raw stack authenticates current occurrence/binding/point;
 /// the supplied source path and region come from that SAME DirectivePlan.
 #[cfg(test)]
 pub(super) fn append_actual_using(&mut self,actual:&Token<'_>,token:Span,output_cover:Span,output_line:usize,region:usize,path:Arc<PathBuf>,trace:OriginalMacroTrace,lease:&SourceAcquisitionLease,provider:&dyn SourceProvider,inputs:&mut RawSourceDriver,a:&SettingAdmission<'_>,work:&dyn SourceArenaWork)->io::Result<()>{
  self.append_geometry_using(actual,token,None,output_cover,output_line,region,&path,&trace,lease,provider,inputs,None,a,work)
 }
 fn append_geometry_using(&mut self,actual:&Token<'_>,token:Span,kind:Option<dm_syntax::TokenKind>,output_cover:Span,output_line:usize,region:usize,path:&Arc<PathBuf>,trace:&OriginalMacroTrace,lease:&SourceAcquisitionLease,provider:&dyn SourceProvider,inputs:&mut RawSourceDriver,prior:Option<&super::original_raw_inputs::OriginalPhysicalRowObservation<'_>>,a:&SettingAdmission<'_>,work:&dyn SourceArenaWork)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
  if self.delivered_end.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"delivered origin rows are already finalized"))}
  if !self.is_admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}
  let cover_end = self.last_emitted.map(|prior|prior.cover_end).or_else(|| {
   self.rows.len().checked_sub(1).and_then(|index|self.row(index)).map(|row|row.output.end)
  });
  if token.start>=token.end||output_cover.start!=token.start||output_cover.end<token.end
   ||cover_end.is_some_and(|end|end>output_cover.start){return Err(io::ErrorKind::InvalidInput.into())}
  let source=inputs.observe_physical_row_using(actual.origin,lease,provider,prior,a)?.into_row();
  match (&actual.lexical_frame,actual.lexical_span){(Some(frame),Some(_)) if frame.admitted_by(a)=>(),(None,None)=>(),_=>return Err(io::ErrorKind::InvalidData.into())};
  // Check every authority component even when reusing an encounter.
  // Never identify a source acquisition by its spelling or region alone.
  let share_encounter = self.encounters.as_slice().last().is_some_and(|last| {
   last.occurrence == actual.origin.occurrence && last.binding.matches(lease)
    && last.region == region && Arc::ptr_eq(&last.path, path)
  });
  let prior_group = share_encounter.then(|| {
   self.last_emitted.map(|prior|prior.geometry).or_else(|| {
    self.rows.len().checked_sub(1).and_then(|index|self.rows.group_geometry(index,&self.groups))
   })
  }).flatten().filter(|last| {
   last.decoded == source.decoded && last.raw_base == source.raw.start
    && last.line == source.point.line && last.output_line == output_line
    && self.groups.traces.last().is_some_and(|prior_trace|prior_trace.same_owner(trace))
  });
  let share_group = prior_group.is_some();
  if !share_encounter {
   self.encounters.push(Encounter {
    occurrence: actual.origin.occurrence, binding: lease.identity(), path: Arc::clone(path), region,
   }, a)?;
  }
  let mut funding = PageFunding { work, credit: &mut self.page_credit };
  let geometry = if let Some(prior) = prior_group {
   prior
  } else {
   let geometry = GroupGeometry {
    encounter: self.encounters.len() - 1, decoded: source.decoded,
    line: source.point.line, output_line, output_base: output_cover.start,
    raw_base: source.raw.start,
   };
   if let Err(error) = self.groups.push(geometry, trace.clone(), a, &mut funding) {
    if !share_encounter { self.encounters.pop(); }
    return Err(error);
   }
   geometry
  };
  let group = self.groups.len() - 1;
  // Group sharing already requires the same source line, and validation
  // above requires the token and output cover to start at the same byte.
  let row=Row{
   group, output:output_cover, token_end:token.end, source_offset:source.point.source_offset,
   byte_column:source.point.byte_column, raw_extent:actual.origin.physical, actual_eof:source.actual_eof,
  };
  let result = self.rows.push_projected(row, geometry, kind, a, &mut funding);
  #[cfg(debug_assertions)]
  if result.is_ok() {
   if let Some(census)=&mut self.row_geometry_census {
    if !share_group {
    let cell = self.groups.packed.get(group).expect("issued group");
    census.observe_group(geometry, cell);
   }
    let ordinal=self.rows.len()-1;
    census.observe(row,geometry,self.rows.page(ordinal/ROW_PAGE_LEN).expect("issued origin row page").group_base,ordinal%ROW_PAGE_LEN);
   }
  }
  if result.is_err() {
   if !share_group { let _ = self.groups.truncate(self.groups.len() - 1, &mut funding); }
   if !share_encounter { self.encounters.pop(); }
  } else {
   self.last_emitted = Some(LastEmitted { geometry, cover_end: output_cover.end });
  }
  result
 }

 fn row(&self, index: usize) -> Option<Row> {
  self.rows.get(index, &self.groups)
 }

 /// The actual runner binds even an empty stream from its SAME cursor's zero
 /// receipt before lending that producer. No numeric offset issues this owner.
 pub(super) fn bind_output_using(&mut self,initial:&super::original_prepared_output::OriginalDeliveryFrontier,a:&SettingAdmission<'_>)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if self.delivered_end.is_some()||(self.rows.len()!=0||self.nonphysical.len()!=0)||initial.end()!=0||!self.is_admitted_by(a)||!initial.owner().admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}
  match &self.output{Some(owner)if !initial.belongs_to(owner)=>Err(io::ErrorKind::InvalidInput.into()),Some(_)=>Ok(()),None=>{self.output=Some(initial.owner().clone());Ok(())}}
 }
 /// Actual token/interval/line belong to ONE prepared-output record. Pointer
 /// comparison authenticates those two private callback arguments only; source
 /// geometry is independently checked by the SAME raw frame/lease below.
 pub(super) fn append_produced_using(&mut self,actual:&Token<'static>,produced:super::original_prepared_output::OriginalProducedSpan<'_>,region:usize,path:&Arc<PathBuf>,trace:&OriginalMacroTrace,lease:&SourceAcquisitionLease,provider:&dyn SourceProvider,inputs:&mut RawSourceDriver,prior:Option<&super::original_raw_inputs::OriginalPhysicalRowObservation<'_>>,a:&SettingAdmission<'_>,work:&dyn SourceArenaWork)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
  let owner=self.output.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"origin owner lacks its actual output cursor"))?;
  if !owner.same(produced.owner())||!produced.owner().admitted_by(a)||!std::ptr::eq(actual,produced.actual()?){return Err(io::Error::new(io::ErrorKind::InvalidInput,"origin arguments differ from the SAME prepared token"))}
  let token=produced.token();
  self.append_geometry_using(actual,token.span,Some(token.kind),produced.cover(),produced.output_line(),region,path,trace,lease,provider,inputs,prior,a,work)
 }
 /// Only the receiver's actual complete-append receipt can discard producer
 /// lookahead mappings. Acquisitions/notices/history remain genuine lookahead
 /// DATA; trimming mappings cannot grant primary/model/physical EOF.
 /// Authentic receiver coverage for a SAME issued default delimiter. It has
 /// no physical source row/line/column/token extent and is never returned by
 /// geometry/get/point as an origin or CODE grant.
 pub(super) fn append_default_semicolon_using(&mut self,produced:super::original_prepared_output::OriginalProducedSpan<'_>,a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;let owner=self.output.as_ref().ok_or(io::ErrorKind::InvalidInput)?;if self.delivered_end.is_some()||!self.is_admitted_by(a)||!owner.same(produced.owner())||!produced.owner().admitted_by(a)||!produced.is_default_semicolon()||self.rows.len()!=0||self.nonphysical.len()!=0||produced.cover().start!=0{return Err(io::ErrorKind::InvalidInput.into())}self.nonphysical.push(NonphysicalToken{token:produced.token(),cover:produced.cover()},a)}
 pub(super) fn retain_delivered_using(&mut self,delivered:&super::original_prepared_output::OriginalDeliveryFrontier,a:&SettingAdmission<'_>,work:&dyn SourceArenaWork)->io::Result<usize>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;let owner=self.output.as_ref().ok_or(io::ErrorKind::InvalidInput)?;
  if self.delivered_end.is_some()||!self.is_admitted_by(a)||!delivered.belongs_to(owner)||!delivered.owner().admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}
  let keep=self.rows.partition_point(&self.groups, |row|row.output.end<=delivered.end());
  let last=keep.checked_sub(1).and_then(|index|self.row(index));
  if delivered.end()!=0&&last.is_none_or(|row|row.output.end!=delivered.end())&&!self.nonphysical.as_slice().iter().any(|row|row.cover.end==delivered.end()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"delivery receipt is not an actual recorded complete cover"))}
  let (groups, encounters) = match last {
   Some(row) => {
    let group = self.groups.source_geometry(row.group).ok_or(io::ErrorKind::InvalidData)?;
    (row.group.checked_add(1).ok_or(io::ErrorKind::InvalidData)?,
     group.encounter.checked_add(1).ok_or(io::ErrorKind::InvalidData)?)
   }
   None => (0, 0),
  };
  // Shrinking can fail after dropping a suffix. An aborted trim must
  // never leave a cached pre-trim frontier for a later checked operation.
  self.last_emitted=None;
  let mut funding=PageFunding{work,credit:&mut self.page_credit};self.rows.truncate(keep,&mut funding)?;self.groups.truncate(groups,&mut funding)?;self.encounters.truncate(encounters);let nonphysical=self.nonphysical.as_slice().partition_point(|row|row.cover.end<=delivered.end());self.nonphysical.truncate(nonphysical);self.delivered_end=Some(delivered.end());Ok(keep)
 }
 // This loan is issued only at the existing complete-batch send boundary.
 // No source read or lexer/indent demand can occur here.
 pub(super) fn batch_token_pages(
  &mut self, owner:&super::original_prepared_output::OriginalOutputIdentity,
  end:usize, count:usize, a:&SettingAdmission<'_>, work:&dyn SourceArenaWork,
 )->io::Result<[Option<super::original_prepared_output::OriginalBatchTokenPage>;2]> {
  use super::original_prepared_output::OriginalBatchTokenPage;
  const _: () = assert!(ROW_PAGE_LEN == dm_syntax::ORIGINAL_TOKEN_PAGE_ROWS);
  let mut pages=[None,None];
  if self.delivered_end.is_some() || !self.is_admitted_by(a)
     || !owner.admitted_by(a) || self.output.as_ref().is_none_or(|actual|!actual.same(owner)){
   return Err(io::ErrorKind::InvalidInput.into());
  }
  // OriginalIndent emits the default location only at End without a real
  // input token. Keep this nonphysical route on the ordinary local tape.
  if self.nonphysical.len()!=0 { return Ok(pages); }
  let total=self.rows.len();
  let first=total.checked_sub(count).ok_or(io::ErrorKind::InvalidData)?;
  if first % ROW_PAGE_LEN != 0 || self.last_emitted.is_none_or(|last| last.cover_end!=end) {
   return Err(io::Error::new(io::ErrorKind::InvalidData,"batch differs from actual physical output frontier"));
  }
  let first_page=first/ROW_PAGE_LEN;
  let last_page=total/ROW_PAGE_LEN;
  if last_page-first_page>pages.len(){return Err(io::ErrorKind::InvalidData.into());}
  for (slot,page) in (first_page..last_page).enumerate(){
   let page_owner=self.rows.pages.get_mut(page).ok_or(io::ErrorKind::InvalidData)?;
   // A replay can reuse the same completed loan. An existing immutable
   // alias prevents relocation, but never prevents issuing that loan.
   if let Ok(page)=page_owner.get_mut(){page.settle_full_columns(a,work)?;}
   let actual=page_owner.loan_full().ok_or(io::ErrorKind::InvalidData)?;
   pages[slot]=Some(OriginalBatchTokenPage{
    first:page*ROW_PAGE_LEN, within_batch:(page-first_page)*ROW_PAGE_LEN,
    loan:dm_syntax::OriginalTokenPageLoan::new(actual,a)?,
   });
  }
  Ok(pages)
 }

 // This observational view requires the actual same-output sealed frontier.
 // Its projected coordinates carry no new source or primary authority.
 #[cfg(any(test, debug_assertions))]
 pub(super) fn delivered_tokens(
  &self, delivered:&super::original_prepared_output::OriginalDeliveryFrontier, a:&SettingAdmission<'_>,
 )->Result<impl ExactSizeIterator<Item=Option<dm_syntax::SpanToken>> + '_, &'static str>{
  let owner=self.output.as_ref().ok_or("origin projection has no actual output")?;
  if self.delivered_end!=Some(delivered.end())||!delivered.belongs_to(owner)
      ||!owner.admitted_by(a)||!self.is_admitted_by(a){
   return Err("origin projection has a foreign or unsealed delivery frontier");
  }
  let prefix=self.nonphysical.as_slice();
  let count=prefix.len().checked_add(self.rows.len()).ok_or("origin projection length overflow")?;
  Ok((0..count).map(move |index| {
   if let Some(row)=prefix.get(index){return Some(row.token)}
   let ordinal=index-prefix.len();
   self.rows.projected_token(ordinal)
  }))
 }
 #[cfg(debug_assertions)]
 pub(super) fn trace_capacity(&self) -> (usize, usize, usize, usize, usize, usize) {
  let (mut compact_bytes, mut full_bytes, mut group_bytes) = (0usize, 0usize, 0usize);
  self.rows.visit_compact_storage(|_, _, capacity| compact_bytes = compact_bytes.saturating_add(capacity));
  self.rows.visit_full_storage(|_, _, capacity| full_bytes = full_bytes.saturating_add(capacity));
  self.groups.visit_storage(|_, _, capacity| group_bytes = group_bytes.saturating_add(capacity));
  (self.rows.len(), compact_bytes, self.groups.len(), group_bytes, self.encounters.len(), full_bytes)
 }
 #[cfg(debug_assertions)]
 pub(super) fn trace_run_capacity(&self) -> (usize, usize, usize) { self.groups.trace_capacity() }
 #[cfg(debug_assertions)]
 pub(super) fn trace_output_base_capacity(&self) -> (usize, usize, usize, usize, usize) {
    self.rows.pages.iter().fold((0, 0, 0, 0, 0), |totals, page| {
        let bases = &page.get().output_bases;
        (
            totals.0 + bases.compact.len(),
            totals.1 + bases.compact.capacity() * std::mem::size_of::<u16>(),
            totals.2 + bases.anchors.capacity() * std::mem::size_of::<usize>(),
            totals.3 + bases.wide.len(),
            totals.4 + bases.wide.capacity() * std::mem::size_of::<WideOutputBase>(),
        )
    })
 }
 #[cfg(debug_assertions)]
 pub(super) fn trace_run_compaction_capacity(&self) -> (usize, usize, usize) {
    self.groups.traces.trace_capacity()
 }
 #[cfg(debug_assertions)]
 pub(super) fn trace_row_geometry_census(&self)->Option<&RawRowGeometryCensus>{self.row_geometry_census.as_ref()}
 pub(super) fn has_delivered_binding(&self)->bool{self.output.is_some()&&self.delivered_end.is_some()}
 #[cfg(debug_assertions)]
 pub(super) fn source_page_bytes(&self)->usize{self.page_credit.reserved_bytes().saturating_add(self.rows.page_payload_bytes())}
 pub(super) fn is_admitted_by(&self,a:&SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.domain)}
 pub(super) fn geometry(&self,index:usize)->Option<(usize,OriginalByteCursor,Span,Span,bool)>{
  let row=self.row(index)?;
  let group=self.groups.source_geometry(row.group)?;
  let encounter = self.encounters.as_slice().get(group.encounter)?;
  Some((encounter.occurrence,row.point(group.line),row.token_span(),row.raw_extent,row.actual_eof))
 }
 pub(super) fn equivalent(&self,other:&Self)->bool{self.len()==other.len()&&self.nonphysical.as_slice().iter().map(|row|row.cover).eq(other.nonphysical.as_slice().iter().map(|row|row.cover))&&(0..self.len()).all(|index|self.geometry(index)==other.geometry(index))}
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
  let row=self.row(index).ok_or("actual raw origin row absent")?;let group=self.groups.source_geometry(row.group).ok_or("actual raw origin metadata absent")?;let encounter=self.encounters.as_slice().get(group.encounter).ok_or("actual raw origin encounter absent")?;if encounter.occurrence!=occurrence||!encounter.binding.matches(lease){return Err("actual raw origin belongs to another source acquisition or occurrence")}
  if offset!=row.output.start&&!(row.actual_eof&&(offset==row.token_end||offset==row.output.end)){return Err("expanded byte has no exact issued raw token point")}
  Ok(row.point(group.line))
 }
 pub(super) fn source_end_at(&self,index:usize,offset:usize)->bool{self.row(index).is_some_and(|row|row.actual_eof&&(offset==row.output.start||offset==row.token_end||offset==row.output.end))}
 pub(super) fn policy_line(&self,index:usize,occurrence:usize,lease:&SourceAcquisitionLease,offset:usize)->Result<usize,&'static str>{let row=self.row(index).ok_or("actual raw origin row absent")?;let group=self.groups.source_geometry(row.group).ok_or("actual raw origin metadata absent")?;let encounter=self.encounters.as_slice().get(group.encounter).ok_or("actual raw origin encounter absent")?;if encounter.occurrence!=occurrence||!encounter.binding.matches(lease)||offset<row.output.start||offset>=row.output.end{return Err("actual raw policy point belongs to another input or interval")}Ok(group.line)}
 pub(super) fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
  self.nonphysical.visit_allocation(|p,n|visit(p,self.nonphysical.len()*std::mem::size_of::<NonphysicalToken>(),n));
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
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let file=File::new(b"\xef\xbb\xbfvar/value=7\r\n");let mut source=driver(&a);source.push_opened(&file,file.lease.clone(),0,&a).unwrap();let mut host=Host{ordinary:OriginalOrdinaryOutput::new(&a).unwrap()};let work=OutputWork(Arc::new(AtomicUsize::new(0)));let mut rows=OriginalRawOrigins::new(&a,&work).unwrap();
  // One bounded fixture metadata grant, before path/trace/anchor allocations.
  let metadata_credit=a.reserve(1024).unwrap();let path=Arc::new(PathBuf::from("actual-mapping.dm"));let trace=OriginalMacroTrace::empty();let mut offset=0;
  while let Some(actual)=next(&mut source,&file,&mut host,&a){rows.append_actual_using(&actual,Span::new(offset,offset+1),Span::new(offset,offset+1),1,0,path.clone(),trace.clone(),&file.lease,&file,&mut source,&a,&work).unwrap();offset+=1;}
  assert!(rows.len()>3);let mut saw_end=false;for index in 0..rows.len(){let(occurrence,point,span,_,eof)=rows.geometry(index).unwrap();assert_eq!(occurrence,0);assert_eq!(rows.point(index,0,&file.lease,span.start).unwrap(),point);if eof{saw_end=true;assert_eq!(rows.point(index,0,&file.lease,span.end).unwrap(),point)}else{assert!(rows.point(index,0,&file.lease,span.end).is_err())}}
  assert!(saw_end,"only the actual finished raw input can mark terminal rows");let metadata=dm_syntax::SharedSettingRetention::new(metadata_credit);let arena=super::super::ExpandedOriginArena::from_actual_raw_rows_using(rows,metadata,&a).unwrap();let alias=arena.clone();assert!(arena.same_owner(&alias));assert_eq!(arena.len(),offset);let page_charge=work.0.load(Ordering::Acquire);drop((source,host,path,trace,arena));assert!(used.load(Ordering::Acquire)>dm_syntax::SettingChargeCounter::root_allocation_bytes(),"last mapping alias must still pay for retained rows and metadata");assert_eq!(work.0.load(Ordering::Acquire),page_charge);drop(alias);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.0.load(Ordering::Acquire),0);
 }
 #[test]
 fn actual_non_ascii_source_uses_inline_utf8_and_exact_decoded_offset_escape() {
  for (raw, extra_decoded_bytes) in [
   (b"var/first=1; /*\xc3\xa9*/ var/after=7\n".as_slice(),0usize),
   (b"var/first=1; /*\x80*/ var/after=7\n".as_slice(),2usize),
  ] {
   let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
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
     let class=rows.rows.cell(ordinal).unwrap().class();
     assert_eq!(class,if extra_decoded_bytes==0 {0} else {NarrowRow::MEDIUM});
     assert_eq!(row.raw_extent,Span::new(raw_at,raw_at+3));
     assert_eq!(rows.point(ordinal,0,&file.lease,span.start).unwrap(),
      OriginalByteCursor{line:1,byte_column:raw_at+1,source_offset:decoded_at});
     saw_after=true;
    }
   }
   assert!(saw_after,"actual token after the non-ASCII comment was recorded");
   drop((rows,source,host,path,trace,metadata));
   assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
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
   let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
   let a=SettingAdmission::new(&syntax,dm_syntax::SettingChargeCounter::root_allocation_bytes(),&||Ok(()));
   let work=CappedWork::new(Arc::clone(&used),cap-usize::from(denied));
   let mut credit=work.reserve(0).unwrap();
   let mut funding=PageFunding{work:&work,credit:&mut credit};
   let mut rows=OriginPages::new();
   let row=|at|{let [low,high]=u16::try_from(at).unwrap().to_le_bytes();NarrowRow{tag:0,fields:[low,high,0]}};
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
   drop(rows);drop(credit);assert_eq!(used.load(Ordering::Acquire),0);assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
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
   line:line.min(4095),output_line:line,output_base:line,raw_base:line,
  };
  for denied in [false,true] {
   let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
   let a=SettingAdmission::new(&syntax,dm_syntax::SettingChargeCounter::root_allocation_bytes(),&||Ok(()));
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
    assert_eq!(last.line,4095);
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
   assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
  }
 }
 #[test]
 fn eight_byte_groups_keep_exact_edges_and_both_escape_rosters() {
    let fixed = dm_syntax::SettingChargeCounter::root_allocation_bytes();
    let syntax = dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();
    let a = SettingAdmission::new(&syntax, fixed, &|| Ok(()));
    let used = Arc::new(AtomicUsize::new(0));
    let work = OutputWork(Arc::clone(&used));
    let mut credit = work.reserve(0).unwrap();
    let mut funding = PageFunding { work: &work, credit: &mut credit };
    let trace = OriginalMacroTrace::empty();
    let mut groups = OriginGroups::new();
    let start = (1 << 24) - 1;
    let base = GroupGeometry {
        encounter: 0, decoded: Span::new(start, start+4095), line: 4095,
        raw_base: start, output_line: 50, output_base: 0,
    };
    let cases = [
        (base, false, false),
        (GroupGeometry { output_line: 50 + 65_533, ..base }, false, false),
        (GroupGeometry { output_line: 50 + 65_534, ..base }, true, false),
        (GroupGeometry { output_line: 50 + 65_535, ..base }, false, true),
        (GroupGeometry { raw_base: start + 1, decoded: Span::new(start+1,start+2), ..base }, true, false),
        (GroupGeometry { decoded: Span::new(start,start+4096), ..base }, true, false),
        (GroupGeometry { line: 4096, ..base }, true, false),
    ];
    for (at, (row, old, full)) in cases.into_iter().enumerate() {
        groups.push(row, trace.clone(), &a, &mut funding).unwrap();
        assert_eq!(groups.source_geometry(at), Some(row.source()));
        assert_eq!(groups.packed.get(at).unwrap().is_old(), old);
        assert_eq!(groups.packed.get(at).unwrap().is_full(), full);
        assert!(groups.get(at).unwrap().1.same_owner(&trace));
    }
    assert_eq!(groups.old.len(), 4);
    assert_eq!(groups.full.len(), 1);
    groups.truncate(2,&mut funding).unwrap();
    assert_eq!(groups.old.len(), 0);
    assert_eq!(groups.full.len(), 0);
    groups.push(cases[6].0,trace.clone(),&a,&mut funding).unwrap();
    assert_eq!(groups.old.get(0).unwrap().ordinal(),2);
    assert_eq!(groups.source_geometry(2),Some(cases[6].0.source()));
    assert!(groups.source_geometry(3).is_none());
    drop((groups,credit));
    assert_eq!(used.load(Ordering::Acquire),0);
    assert_eq!(syntax.load(Ordering::Acquire),fixed);
 }
 #[test]
 fn packed_group_width_and_encounter_bounds_preserve_original_coordinates() {
  let base=200_000;
  let normal=GroupGeometry{encounter:usize::MAX,
   decoded:Span::new(1,1+usize::from(u16::MAX)),line:27,
   output_line:base+usize::from(u16::MAX)-1,output_base:200_003,raw_base:1};
  assert_eq!(GroupGeometry::unpack(&normal.pack(base).unwrap(),base,normal.encounter),Some(normal.source()));
  for wide in [
   GroupGeometry{decoded:Span::new(1,normal.decoded.end+1),..normal},
   GroupGeometry{decoded:Span::new(1,0),..normal},
   GroupGeometry{raw_base:3,..normal},
   GroupGeometry{line:usize::from(u16::MAX)+1,..normal},
   GroupGeometry{output_line:base-1,..normal},
   GroupGeometry{output_line:normal.output_line+1,..normal},
  ]{assert!(wide.pack(base).is_none());}
  assert!(PackedGroup::pack(&normal.pack(base).unwrap()).is_none());
 }
 #[test]
 fn packed_groups_preserve_wide_coordinates_and_refund_only_retired_owners() {
  let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=SettingAdmission::new(&syntax,dm_syntax::SettingChargeCounter::root_allocation_bytes(),&||Ok(()));
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
  assert_eq!(issued,wide.source());
  assert!(issued_trace.same_owner(&distinct));
  assert_eq!(groups.source_geometry(2),Some(narrow.source()));
  let before=source.load(Ordering::Acquire);
  groups.truncate(1,&mut funding).unwrap();
  assert_eq!(before-source.load(Ordering::Acquire),128*std::mem::size_of::<(usize,GroupGeometry)>());
  assert_eq!(groups.full.len(),0);
  assert_eq!(distinct.strong_count(),1);
  assert_eq!(groups.source_geometry(0),Some(narrow.source()));
  assert!(groups.get(0).unwrap().1.same_owner(&trace));
  drop(groups);
  drop(credit);
  assert_eq!(source.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn group_page_geometry_escapes_keep_the_same_ordinals_after_partial_trim() {
  let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=SettingAdmission::new(&syntax,dm_syntax::SettingChargeCounter::root_allocation_bytes(),&||Ok(()));
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
   assert_eq!(groups.source_geometry(index),Some(geometry.source()));
  }
  let start=GroupGeometry{output_line:900_000,..ordinary(ROW_PAGE_LEN)};
  let shifted=GroupGeometry{output_line:start.output_line+65_536,..ordinary(ROW_PAGE_LEN+1)};
  groups.push(start,trace.clone(),&a,&mut funding).unwrap();
  groups.push(shifted,trace.clone(),&a,&mut funding).unwrap();
  assert_eq!(groups.full.len(),2);
  assert!(groups.packed.get(2).unwrap().is_full());
  assert_eq!(groups.full.get(0).unwrap().0,2);
  assert!(groups.packed.get(ROW_PAGE_LEN+1).unwrap().is_full());
  assert_eq!(groups.full.get(1).unwrap().0,ROW_PAGE_LEN+1);
  assert_eq!(groups.source_geometry(ROW_PAGE_LEN),Some(start.source()));
  assert_eq!(groups.source_geometry(ROW_PAGE_LEN+1),Some(shifted.source()));

  groups.truncate(ROW_PAGE_LEN+1,&mut funding).unwrap();
  assert_eq!(groups.full.len(),1);
  let replacement=GroupGeometry{raw_base:7,output_line:start.output_line+1,..ordinary(ROW_PAGE_LEN+1)};
  groups.push(replacement,trace.clone(),&a,&mut funding).unwrap();
  assert!(groups.packed.get(ROW_PAGE_LEN+1).unwrap().is_full());
  assert_eq!(groups.full.get(1).unwrap().0,ROW_PAGE_LEN+1);
  assert_eq!(groups.source_geometry(ROW_PAGE_LEN+1),Some(replacement.source()));
  assert!(groups.get(ROW_PAGE_LEN+1).unwrap().1.same_owner(&trace));

  groups.truncate(ROW_PAGE_LEN,&mut funding).unwrap();
  let new_start=GroupGeometry{output_line:2_000_000,..start};
  groups.push(new_start,trace.clone(),&a,&mut funding).unwrap();
  assert_eq!(groups.source_geometry(ROW_PAGE_LEN),Some(new_start.source()));
  assert_eq!(groups.full.len(),1);
  assert_eq!(groups.source_geometry(2),Some(GroupGeometry{raw_base:5,..ordinary(2)}.source()));
  drop((groups,credit));
  assert_eq!(used.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn group_encounter_rank_survives_escapes_word_and_page_boundaries_and_reappend() {
    let fixed = dm_syntax::SettingChargeCounter::root_allocation_bytes();
    let syntax = dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();
    let a = SettingAdmission::new(&syntax, fixed, &|| Ok(()));
    let used = Arc::new(AtomicUsize::new(0));
    let work = OutputWork(Arc::clone(&used));
    let mut credit = work.reserve(0).unwrap();
    let mut funding = PageFunding { work: &work, credit: &mut credit };
    let trace = OriginalMacroTrace::empty();
    let mut groups = OriginGroups::new();
    let geometry = |index, encounter| GroupGeometry {
        encounter, decoded: Span::new(index, index + 1), raw_base: index,
        line: index, output_line: 500_000 + index, output_base: index * 2,
    };
    for index in 0..=ROW_PAGE_LEN {
        let encounter = match index {
            62 => 501,
            63 | 65 => 101,
            64 | 66..=4094 => 102,
            4095 => 103,
            4096 => usize::MAX,
            _ => 100,
        };
        let mut row = geometry(index, encounter);
        if index == 63 { row.raw_base += 3; }
        groups.push(row, trace.clone(), &a, &mut funding).unwrap();
        let (actual, actual_trace) = groups.get(index).unwrap();
        assert_eq!(actual, row.source(), "group {index}");
        assert!(actual_trace.same_owner(&trace));
        assert_eq!(
            groups.packed.get(index).unwrap().is_full(),
            matches!(index, 62 | 63 | 65),
        );
    }
    let same_max = geometry(ROW_PAGE_LEN + 1, usize::MAX);
    groups.push(same_max, trace.clone(), &a, &mut funding).unwrap();
    assert_eq!(groups.source_geometry(ROW_PAGE_LEN + 1), Some(same_max.source()));
    assert!(!groups.packed.get(ROW_PAGE_LEN + 1).unwrap().is_full());
    let would_wrap = geometry(ROW_PAGE_LEN + 2, 0);
    groups.push(would_wrap, trace.clone(), &a, &mut funding).unwrap();
    assert_eq!(groups.source_geometry(ROW_PAGE_LEN + 2), Some(would_wrap.source()));
    assert!(groups.packed.get(ROW_PAGE_LEN + 2).unwrap().is_full());

    // A new page establishes its own base, including a lower encounter.
    groups.truncate(ROW_PAGE_LEN, &mut funding).unwrap();
    let first = geometry(ROW_PAGE_LEN, 77);
    groups.push(first, trace.clone(), &a, &mut funding).unwrap();
    assert_eq!(groups.source_geometry(ROW_PAGE_LEN), Some(first.source()));
    assert!(!groups.packed.get(ROW_PAGE_LEN).unwrap().is_full());

    // Trimming the first bit of a word must keep the prior escaped +1.
    groups.truncate(64, &mut funding).unwrap();
    let at_word = geometry(64, 102);
    groups.push(at_word, trace.clone(), &a, &mut funding).unwrap();
    assert_eq!(groups.source_geometry(64), Some(at_word.source()));
    assert!(!groups.packed.get(64).unwrap().is_full());

    // Now remove the escaped +1 too, and issue that rank again.
    groups.truncate(63, &mut funding).unwrap();
    let before_word = geometry(63, 101);
    groups.push(before_word, trace.clone(), &a, &mut funding).unwrap();
    groups.push(at_word, trace.clone(), &a, &mut funding).unwrap();
    assert_eq!(groups.source_geometry(63), Some(before_word.source()));
    assert_eq!(groups.source_geometry(64), Some(at_word.source()));
    assert!(!groups.packed.get(63).unwrap().is_full());
    assert_eq!(groups.full.len(), 1);
    assert_eq!(groups.source_geometry(62), Some(geometry(62, 501).source()));
    drop((groups, credit));
    assert_eq!(used.load(Ordering::Acquire), 0);
    assert_eq!(syntax.load(Ordering::Acquire), fixed);
 }

 #[test]
 fn compact_trace_runs_preserve_logical_ordinals_exact_empty_owners_and_trim() {
    let fixed = dm_syntax::SettingChargeCounter::root_allocation_bytes();
    let syntax = dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();
    let a = SettingAdmission::new(&syntax, fixed, &|| Ok(()));
    let live = Arc::new(AtomicUsize::new(0));
    let work = CappedWork::new(Arc::clone(&live), usize::MAX);
    let mut credit = work.reserve(0).unwrap();
    let mut funding = PageFunding { work: &work, credit: &mut credit };
    let canonical = OriginalMacroTrace::empty();
    let distinct = OriginalMacroTrace::empty();
    let mut runs = TraceRuns::new();
    for ordinal in 0..=260 {
        let expected = if ordinal % 2 == 0 { &canonical } else { &distinct };
        runs.push(expected.clone(), &a, &mut funding).unwrap();
        assert!(runs.get(ordinal).unwrap().same_owner(expected), "logical run {ordinal}");
    }
    assert_eq!(runs.len(), 261);
    assert_eq!(runs.stored.len(), 131);
    assert_eq!(runs.mapped_from, Some(2));
    assert_eq!(runs.rank.len(), 3);
    assert_eq!(canonical.strong_count(), 2, "one real canonical owner slot");
    assert_eq!(distinct.strong_count(), 131, "different empty identity stays full");

    // Remove a word boundary and a subsequent page. Reappend must reissue
    // the physical bit even when the old slot held the canonical owner.
    runs.truncate(66, &mut funding).unwrap();
    assert_eq!(runs.rank.len(), 1);
    runs.push(distinct.clone(), &a, &mut funding).unwrap();
    assert!(runs.last().unwrap().same_owner(&distinct));
    assert_eq!(runs.stored.len(), 35);

    runs.truncate(2, &mut funding).unwrap();
    assert!(runs.mapped_from.is_none());
    assert_eq!(runs.rank.len(), 0);
    assert_eq!(runs.stored.len(), 2);
    assert!(runs.last().unwrap().same_owner(&distinct));
    let before = live.load(Ordering::Acquire);
    work.limit.store(before, Ordering::Release);
    let failure = runs.push(canonical.clone(), &a, &mut funding).unwrap_err();
    assert_eq!(failure.kind(), io::ErrorKind::OutOfMemory);
    assert_eq!(live.load(Ordering::Acquire), before);
    assert_eq!(runs.len(), 2);
    assert!(runs.mapped_from.is_none());
    assert!(runs.last().unwrap().same_owner(&distinct));

    work.limit.store(usize::MAX, Ordering::Release);
    runs.push(canonical.clone(), &a, &mut funding).unwrap();
    assert!(runs.last().unwrap().same_owner(&canonical));
    runs.truncate(0, &mut funding).unwrap();
    assert!(runs.canonical.is_none());
    assert_eq!(canonical.strong_count(), 1);
    assert_eq!(distinct.strong_count(), 1);
    runs.push(distinct.clone(), &a, &mut funding).unwrap();
    assert!(runs.last().unwrap().same_owner(&distinct));
    drop((runs, credit));
    assert_eq!(live.load(Ordering::Acquire), 0);
    assert_eq!(syntax.load(Ordering::Acquire), fixed);
 }

 #[test]
 fn group_trace_rank_preserves_exact_owners_across_words_pages_and_trim() {
  let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=SettingAdmission::new(&syntax,dm_syntax::SettingChargeCounter::root_allocation_bytes(),&||Ok(()));
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
   assert_eq!(geometry,group(index).source());
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
  assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
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
  let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=SettingAdmission::new(&syntax,dm_syntax::SettingChargeCounter::root_allocation_bytes(),&||Ok(()));
  let live=Arc::new(AtomicUsize::new(0));
  let work=DenySecondGeometry{backing:OutputWork(Arc::clone(&live)),absent,
   armed:AtomicBool::new(false),run_grows:AtomicUsize::new(0)};
  let mut credit=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut credit};
  let owner_a=OriginalMacroTrace::empty();
  let owner_b=OriginalMacroTrace::empty();
  let rejected=OriginalMacroTrace::empty();
  let group=|line|GroupGeometry{encounter:7,decoded:Span::new(line,line+1),
   line:line.min(4095),output_line:line,output_base:line,raw_base:line,};
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
  assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 #[cfg(debug_assertions)]
 #[test]
 fn raw_width_side_projection_accounts_for_per_page_blocks_and_controls() {
  let mut cost=ProjectedWidthOnlyCost::default();
  for local in 0..17 { cost.observe(local,true); }
  cost.observe(0,false);
  cost.observe(1,false);
  cost.observe(0,true);
  let page_costs=[17,0,1].map(ProjectedWidthOnlyCost::page_bytes);
  assert_eq!(cost.rows,18);
  assert_eq!(cost.pages_with_side,2);
  assert_eq!(cost.sparse_bytes,page_costs.iter().map(|p|p[0]).sum::<usize>());
  assert_eq!(cost.ranked_bytes,page_costs.iter().map(|p|p[1]).sum::<usize>());
  assert_eq!(cost.adaptive_steady_lower_bound_bytes,page_costs.iter().map(|p|p[2]).sum::<usize>());
  assert!(ProjectedWidthOnlyCost::page_bytes(1)[0]<ProjectedWidthOnlyCost::page_bytes(1)[1]);
  assert!(ProjectedWidthOnlyCost::page_bytes(4096)[0]>ProjectedWidthOnlyCost::page_bytes(4096)[1]);
 }

 #[test]
 fn ranked_raw_width_cells_keep_page_edges_and_token_loans_without_side_reads() {
  let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=SettingAdmission::new(&syntax,8<<20,&||Ok(()));
  let work=OutputWork(Arc::new(AtomicUsize::new(0)));
  let mut credit=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut credit};
  let geometry=GroupGeometry{encounter:0,decoded:Span::new(0,255),line:1,output_line:1,output_base:0,raw_base:0};
  let mut groups=OriginGroups::new();
  groups.push(geometry,OriginalMacroTrace::empty(),&a,&mut funding).unwrap();
  let mut rows=RawTokenRows::new(&a).unwrap();
  let make=|index:usize|{
   let raw=if matches!(index,0|63|64)||index==ROW_PAGE_LEN-1||index==ROW_PAGE_LEN{255}else{80};
   Row{group:0,output:Span::new(0,81),token_end:80,source_offset:0,byte_column:1,
    raw_extent:Span::new(0,raw),actual_eof:index==ROW_PAGE_LEN-1}
  };
  for i in 0..=ROW_PAGE_LEN {
   rows.push_projected(make(i),geometry,Some(dm_syntax::TokenKind::String),&a,&mut funding).unwrap();
  }
  assert_eq!(rows.medium_len(),0);
  assert_eq!(rows.full_len(),0);
  for index in [0,62,63,64,65,ROW_PAGE_LEN-1,ROW_PAGE_LEN] {
   assert_eq!(rows.get(index,&groups),Some(make(index)));
   assert_eq!(rows.projected_token(index),Some(dm_syntax::SpanToken{kind:dm_syntax::TokenKind::String,span:Span::new(0,80)}));
  }
  let page=rows.pages.get_mut(0).unwrap().get_mut().unwrap();
  assert_eq!(page.raw_widths.as_ref().unwrap().widths.len(),4);
  let side=page.raw_widths.take();
  assert_eq!(page.projected_token(63).unwrap().span,Span::new(0,80),"token-only loan never reads raw-width storage");
  assert!(page.decode(63,&groups).is_none(),"full geometry requires its actual raw width");
  page.raw_widths=side;
  rows.truncate(64,&mut funding).unwrap();
  assert_eq!(rows.page(0).unwrap().raw_widths.as_ref().unwrap().widths.len(),2);
  assert_eq!(rows.get(63,&groups),Some(make(63)));
  rows.push_projected(make(64),geometry,Some(dm_syntax::TokenKind::String),&a,&mut funding).unwrap();
  assert_eq!(rows.get(64,&groups),Some(make(64)));
  drop((rows,groups,credit));
  assert_eq!(work.0.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn ranked_raw_width_rollback_preserves_real_io_and_accepts_same_row_after_repair() {
  use std::sync::atomic::AtomicBool;
  struct FailingWidth{backing:OutputWork,armed:AtomicBool,absent:PathBuf}
  impl SourceArenaWork for FailingWidth {
   fn checkpoint(&self)->io::Result<()>{self.backing.checkpoint()}
   fn reserve(&self,n:usize)->io::Result<SourceArenaCredit>{self.backing.reserve(n)}
   fn grow(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{
    if n==16&&self.armed.load(Ordering::Acquire){return std::fs::File::open(&self.absent).map(drop)}
    self.backing.grow(c,n)
   }
   fn shrink(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{self.backing.shrink(c,n)}
  }
  let absent=std::env::current_exe().unwrap().join("missing-width/input");
  let expected=std::fs::File::open(&absent).unwrap_err();
  let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=SettingAdmission::new(&syntax,8<<20,&||Ok(()));
  let work=FailingWidth{backing:OutputWork(Arc::new(AtomicUsize::new(0))),armed:AtomicBool::new(true),absent};
  let mut credit=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut credit};
  let geometry=GroupGeometry{encounter:0,decoded:Span::new(0,255),line:1,output_line:1,output_base:0,raw_base:0};
  let row=Row{group:0,output:Span::new(0,80),token_end:80,source_offset:0,byte_column:1,
   raw_extent:Span::new(0,255),actual_eof:false};
  let mut page=PhysicalOriginPage::new(0,&work).unwrap();
  let before=work.backing.0.load(Ordering::Acquire);
  let actual=page.push(row,geometry,0,Some(dm_syntax::TokenKind::Number),&a,&work).unwrap_err();
  assert_eq!(actual.raw_os_error(),expected.raw_os_error());
  assert!(page.raw_widths.is_none());
  assert!(page.narrow.is_empty());
  assert!(page.output_bases.compact.is_empty());
  assert_eq!(work.backing.0.load(Ordering::Acquire),before);
  work.armed.store(false,Ordering::Release);
  page.push(row,geometry,0,Some(dm_syntax::TokenKind::Number),&a,&work).unwrap();
  let mut groups=OriginGroups::new();
  groups.push(geometry,OriginalMacroTrace::empty(),&a,&mut funding).unwrap();
  assert_eq!(page.decode(0,&groups),Some(row));
  for class in [NarrowRow::MEDIUM,NarrowRow::FULL] {
   let escaped=NarrowRow::escape(class,ROW_PAGE_LEN-1).with_projected_kind(Some(dm_syntax::TokenKind::Unknown));
   assert_eq!(escaped.class(),class);
   assert_eq!(escaped.escape_index(),ROW_PAGE_LEN-1);
   assert_eq!(escaped.projected_kind(),Some(dm_syntax::TokenKind::Unknown));
  }
  drop((page,groups,credit));
  assert_eq!(work.backing.0.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 struct RankedWidthFailureWork {
  backing:OutputWork,
  absent:PathBuf,
  fail_bytes:AtomicUsize,
  first_width_allocations:AtomicUsize,
 }
 impl RankedWidthFailureWork {
  fn new(fail_bytes:usize)->Self{
   Self{backing:OutputWork(Arc::new(AtomicUsize::new(0))),
    absent:std::env::current_exe().unwrap().join("missing-ranked-phase/input"),
    fail_bytes:AtomicUsize::new(fail_bytes),first_width_allocations:AtomicUsize::new(0)}
  }
 }
 impl SourceArenaWork for RankedWidthFailureWork {
  fn checkpoint(&self)->io::Result<()>{self.backing.checkpoint()}
  fn reserve(&self,n:usize)->io::Result<SourceArenaCredit>{self.backing.reserve(n)}
  fn grow(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{
   if n==16{self.first_width_allocations.fetch_add(1,Ordering::AcqRel);}
   if n==self.fail_bytes.load(Ordering::Acquire){
    return std::fs::File::open(&self.absent).map(drop)
   }
   self.backing.grow(c,n)
  }
  fn shrink(&self,c:&mut SourceArenaCredit,n:usize)->io::Result<()>{self.backing.shrink(c,n)}
 }
 fn ranked_test_geometry()->GroupGeometry{
  GroupGeometry{encounter:0,decoded:Span::new(0,255),line:1,output_line:1,output_base:0,raw_base:0}
 }
 fn ranked_test_row(side:bool)->Row{
  Row{group:0,output:Span::new(0,80),token_end:80,source_offset:0,byte_column:1,
   raw_extent:Span::new(0,if side{255}else{80}),actual_eof:false}
 }

 #[test]
 fn ranked_raw_width_staging_rolls_back_when_later_cell_or_output_base_allocation_fails(){
  for fail_bytes in [ROW_PAGE_LEN*std::mem::size_of::<NarrowRow>(),RowOutputBases::BLOCK*std::mem::size_of::<u16>()]{
   let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
   let a=SettingAdmission::new(&syntax,8<<20,&||Ok(()));
   let work=RankedWidthFailureWork::new(fail_bytes);
   let expected=std::fs::File::open(&work.absent).unwrap_err();
   let mut page=PhysicalOriginPage::new(0,&work).unwrap();
   let baseline=work.backing.0.load(Ordering::Acquire);
   let error=page.push(ranked_test_row(true),ranked_test_geometry(),0,None,&a,&work).unwrap_err();
   assert_eq!(error.raw_os_error(),expected.raw_os_error());
   assert_eq!(work.first_width_allocations.load(Ordering::Acquire),1,"width was physically staged first");
   assert!(page.raw_widths.is_none());
   assert!(page.narrow.is_empty());
   assert!(page.output_bases.compact.is_empty());
   assert_eq!(work.backing.0.load(Ordering::Acquire),
    baseline+page.narrow.capacity()*std::mem::size_of::<NarrowRow>());
   work.fail_bytes.store(0,Ordering::Release);
   page.push(ranked_test_row(true),ranked_test_geometry(),0,None,&a,&work).unwrap();
   assert_eq!(page.raw_widths.as_ref().unwrap().widths.as_slice(),[255]);
   assert_eq!(page.raw_widths.as_ref().unwrap().rank.through(0),1);
   assert_eq!(page.narrow.len(),1);
   assert_eq!(page.output_bases.compact.len(),1);
   drop(page);
   assert_eq!(work.backing.0.load(Ordering::Acquire),0);
   assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
  }
 }

 #[test]
 fn ranked_raw_width_existing_vector_growth_failure_keeps_prior_rank_and_capacity(){
  let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=SettingAdmission::new(&syntax,8<<20,&||Ok(()));
  let work=RankedWidthFailureWork::new(0);
  let mut page=PhysicalOriginPage::new(0,&work).unwrap();
  for _ in 0..16{page.push(ranked_test_row(true),ranked_test_geometry(),0,None,&a,&work).unwrap();}
  let before=work.backing.0.load(Ordering::Acquire);
  assert_eq!(page.raw_widths.as_ref().unwrap().widths.capacity(),16);
  work.fail_bytes.store(32,Ordering::Release);
  let expected=std::fs::File::open(&work.absent).unwrap_err();
  let error=page.push(ranked_test_row(true),ranked_test_geometry(),0,None,&a,&work).unwrap_err();
  assert_eq!(error.raw_os_error(),expected.raw_os_error());
  assert_eq!(page.narrow.len(),16);
  let side=page.raw_widths.as_ref().unwrap();
  assert_eq!(side.widths.len(),16);
  assert_eq!(side.widths.capacity(),16);
  assert_eq!(side.rank.through(15),16);
  assert_eq!(side.rank.through(16),16,"failed occurrence publishes no rank bit");
  assert_eq!(work.backing.0.load(Ordering::Acquire),before);
  work.fail_bytes.store(0,Ordering::Release);
  page.push(ranked_test_row(true),ranked_test_geometry(),0,None,&a,&work).unwrap();
  assert_eq!(page.raw_widths.as_ref().unwrap().widths.len(),17);
  assert_eq!(page.raw_widths.as_ref().unwrap().rank.through(16),17);
  drop(page);
  assert_eq!(work.backing.0.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn ranked_raw_width_trim_drops_last_side_and_recreates_at_nonword_boundary(){
  let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=SettingAdmission::new(&syntax,8<<20,&||Ok(()));
  let work=RankedWidthFailureWork::new(0);
  let mut credit=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut credit};
  let mut groups=OriginGroups::new();
  groups.push(ranked_test_geometry(),OriginalMacroTrace::empty(),&a,&mut funding).unwrap();
  let mut page=PhysicalOriginPage::new(0,&work).unwrap();
  for _ in 0..11{page.push(ranked_test_row(false),ranked_test_geometry(),0,None,&a,&work).unwrap();}
  page.push(ranked_test_row(true),ranked_test_geometry(),0,None,&a,&work).unwrap();
  page.push(ranked_test_row(false),ranked_test_geometry(),0,None,&a,&work).unwrap();
  let before=work.backing.0.load(Ordering::Acquire);
  let side_bytes=std::mem::size_of::<RankedRawWidths>()+page.raw_widths.as_ref().unwrap().widths.capacity();
  page.truncate(11,&work).unwrap();
  assert!(page.raw_widths.is_none());
  assert_eq!(before-work.backing.0.load(Ordering::Acquire),side_bytes);
  assert_eq!(page.decode(10,&groups),Some(ranked_test_row(false)));
  page.push(ranked_test_row(false),ranked_test_geometry(),0,None,&a,&work).unwrap();
  page.push(ranked_test_row(true),ranked_test_geometry(),0,None,&a,&work).unwrap();
  assert_eq!(page.raw_widths.as_ref().unwrap().widths.as_slice(),[255]);
  assert_eq!(page.raw_widths.as_ref().unwrap().rank.through(12),1);
  assert_eq!(page.decode(11,&groups),Some(ranked_test_row(false)));
  assert_eq!(page.decode(12,&groups),Some(ranked_test_row(true)));
  drop((page,groups,credit));
  assert_eq!(work.backing.0.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn packed_raw_rows_roundtrip_all_widths_page_bases_and_retained_suffix() {
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=SettingAdmission::new(&used,4<<20,&||Ok(()));
  let work=OutputWork(Arc::new(AtomicUsize::new(0)));let mut credit=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut credit};
  let trace=OriginalMacroTrace::empty();
  let group=|output_base|GroupGeometry{encounter:2,decoded:Span::new(4,10),line:1,output_line:5,output_base,raw_base:3};
  let mut groups=OriginGroups::new();
  groups.push(group(usize::MAX-65535),trace.clone(),&a,&mut funding).unwrap();
  groups.push(group(0),trace.clone(),&a,&mut funding).unwrap();
  let start=group(usize::MAX-65535).output_base+7;
  let narrow=Row{group:0,output:Span::new(start,start+5),token_end:start+4,source_offset:6,byte_column:3,raw_extent:Span::new(5,10),actual_eof:true};
  let medium=Row{output:Span::new(start,start+300),token_end:start+260,..narrow};
  let wide=Row{output:Span::new(1,usize::MAX),token_end:usize::MAX-1,actual_eof:false,..narrow};
  let unusual_column=Row{byte_column:17,..narrow};
  let second_page=Row{group:1,output:Span::new(7,12),token_end:11,..narrow};
  let huge_ordinal=Row{group:usize::MAX,..narrow};
  let mut huge=RawTokenRows::new(&a).unwrap();
  huge.push(huge_ordinal,group(usize::MAX-65535),&a,&mut funding).unwrap();
  assert_eq!(huge.group_at(0),Some(usize::MAX),"page group base stays full width");
  drop(huge);
  let mut rows=RawTokenRows::new(&a).unwrap();
  for row in [narrow,medium,wide,unusual_column] {
   rows.push(row,group(usize::MAX-65535),&a,&mut funding).unwrap();
  }
  for _ in rows.len()..ROW_PAGE_LEN {
   rows.push(narrow,group(usize::MAX-65535),&a,&mut funding).unwrap();
  }
  for row in [second_page,Row{byte_column:33,..second_page}] {
   rows.push(row,group(0),&a,&mut funding).unwrap();
  }
  for (index,expected,class) in [
   (0,narrow,NarrowRow::EOF),(1,medium,NarrowRow::MEDIUM),(2,wide,NarrowRow::FULL),
   (3,unusual_column,NarrowRow::FULL),(ROW_PAGE_LEN,second_page,NarrowRow::EOF),
   (ROW_PAGE_LEN+1,Row{byte_column:33,..second_page},NarrowRow::FULL),
  ] {
   assert_eq!(rows.cell(index).unwrap().class(),class);
   assert_eq!(rows.get(index,&groups),Some(expected));
  }
  assert_eq!(rows.page(1).unwrap().group_base,1);
  assert_eq!(rows.page(1).unwrap().full.len(),1);
  rows.truncate(ROW_PAGE_LEN+1,&mut funding).unwrap();
  assert_eq!(rows.full_len(),2);
  assert_eq!(rows.get(ROW_PAGE_LEN,&groups),Some(second_page));
  rows.truncate(2,&mut funding).unwrap();
  assert_eq!(rows.full_len(),0);
  assert_eq!(rows.page(0).unwrap().full.pages.len(),0);
  assert_eq!(rows.medium_len(),1);
  assert_eq!(rows.get(1,&groups),Some(medium));
  rows.truncate(1,&mut funding).unwrap();
  assert_eq!(rows.medium_len(),0);
  assert_eq!(rows.page(0).unwrap().medium.pages.len(),0);
  assert_eq!(rows.get(0,&groups),Some(narrow));
  drop((rows,groups,trace));
  drop(credit);assert_eq!(work.0.load(Ordering::Acquire),0);
  assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn mixed_origin_columns_preserve_page_ordinals_credit_and_trim_reappend() {
  use dm_syntax::TokenKind::{Ident,Number,Resource};
  let fixed=dm_syntax::SettingChargeCounter::root_allocation_bytes();
  let syntax=dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();
  let a=SettingAdmission::new(&syntax,4<<20,&||Ok(()));
  let live=Arc::new(AtomicUsize::new(0));
  let work=CappedWork::new(Arc::clone(&live),usize::MAX);
  let group=GroupGeometry{encounter:0,decoded:Span::new(0,800),line:1,output_line:1,
   output_base:0,raw_base:0};
  let short=Row{group:0,output:Span::new(3,6),token_end:6,source_offset:2,byte_column:3,
   raw_extent:Span::new(2,3),actual_eof:false};
  let medium=Row{output:Span::new(3,301),token_end:300,..short};
  let full=Row{byte_column:99,..short};
  let escaped=Row{output:Span::new(64,67),token_end:67,..short};
  let ranked_width=Row{raw_extent:Span::new(2,33),..short};
  let eof=Row{output:Span::new(3,7),actual_eof:true,..short};
  let expected=|at| match at {
   63 => (medium,Resource),
   64 => (full,Number),
   65 => (ranked_width,Ident),
   66 => (eof,Ident),
   4095 => (escaped,Ident),
   _ => (short,Ident),
  };
  let mut page=PhysicalOriginPageOwner::new(PhysicalOriginPage::new(0,&work).unwrap());
  for at in 0..ROW_PAGE_LEN {
   let (row,kind)=expected(at);
   page.get_mut().unwrap().push(row,group,0,Some(kind),&a,&work).unwrap();
  }
  let exact_cells=[0,63,64,65,66,4095].map(|at|(at,page.get().cell(at).unwrap()));
  let before=live.load(Ordering::Acquire);
  work.limit.store(before,Ordering::Release);
  page.get_mut().unwrap().settle_full_columns(&a,&work).unwrap();
  assert!(page.get().mixed.is_none());
  assert_eq!(live.load(Ordering::Acquire),before);
  work.limit.store(usize::MAX,Ordering::Release);
  page.get_mut().unwrap().settle_full_columns(&a,&work).unwrap();
  let mixed=page.get().mixed.as_ref().unwrap();
  assert_eq!((mixed.short.len(),mixed.four.len()),(ROW_PAGE_LEN-3,3));
  for (at, old) in exact_cells {
   let actual=mixed.cell(at).unwrap();
   assert_eq!((actual.tag,actual.fields),(old.tag,old.fields));
  }
  let after=before-ROW_PAGE_LEN*std::mem::size_of::<NarrowRow>()+mixed.bytes();
  assert_eq!(live.load(Ordering::Acquire),after);
  let loan=page.loan_full().unwrap();
  assert!(std::ptr::eq(page.get(),loan.get()));
  assert!(page.get_mut().is_err());
  for at in 0..ROW_PAGE_LEN {
   let (row,kind)=expected(at);
   assert_eq!(loan.get().projected_token(at),Some(dm_syntax::SpanToken{kind,span:row.token_span()}));
  }
  assert!(loan.get().projected_token(ROW_PAGE_LEN).is_none());
  drop(loan);
  let page_mut=page.get_mut().unwrap();
  page_mut.truncate(65,&work).unwrap();
  assert_eq!(page_mut.len(),65);
  assert!(page_mut.projected_token(65).is_none());
  page_mut.push(short,group,0,Some(Ident),&a,&work).unwrap();
  assert!(page_mut.mixed.is_none());
  assert_eq!(page_mut.projected_token(65).unwrap().span,short.token_span());
  drop(page);
  assert_eq!(live.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),fixed);
 }

 #[test]
 fn completed_physical_page_loan_keeps_one_exact_credit_without_producer_or_groups() {
  let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=SettingAdmission::new(&syntax,4<<20,&||Ok(()));
  let live=Arc::new(AtomicUsize::new(0));
  let work=OutputWork(Arc::clone(&live));
  let mut directory=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut directory};
  let mut rows=RawTokenRows::new(&a).unwrap();
  let group=GroupGeometry{encounter:0,decoded:Span::new(0,8),line:1,output_line:1,
   output_base:usize::MAX-1024,raw_base:0};
  let inline=Row{group:0,output:Span::new(group.output_base+1,group.output_base+5),
   token_end:group.output_base+4,source_offset:0,byte_column:1,raw_extent:Span::new(0,1),actual_eof:false};
  let medium=Row{output:Span::new(group.output_base+1,group.output_base+300),
   token_end:group.output_base+299,..inline};
  let full=Row{byte_column:17,..inline};
  use dm_syntax::TokenKind::{Ident,Resource,Number};
  rows.push_projected(inline,group,Some(Ident),&a,&mut funding).unwrap();
  assert!(rows.pages.get(0).unwrap().loan_full().is_none());
  rows.push_projected(medium,group,Some(Resource),&a,&mut funding).unwrap();
  rows.push_projected(full,group,Some(Number),&a,&mut funding).unwrap();
  for _ in rows.len()..ROW_PAGE_LEN {
   rows.push_projected(inline,group,Some(Ident),&a,&mut funding).unwrap();
  }
  let before_loan=live.load(Ordering::Acquire);
  let loan=rows.pages.get(0).unwrap().loan_full().unwrap();
  assert!(std::ptr::eq(rows.page(0).unwrap(),loan.get()));
  assert_eq!(live.load(Ordering::Acquire),before_loan);
  rows.push_projected(inline,group,Some(Ident),&a,&mut funding).unwrap();
  assert!(rows.pages.get(1).unwrap().loan_full().is_none());
  let before_failed_trim=live.load(Ordering::Acquire);
  assert_eq!(rows.truncate(ROW_PAGE_LEN-1,&mut funding).unwrap_err().kind(),io::ErrorKind::InvalidInput);
  assert_eq!(rows.len(),ROW_PAGE_LEN+1);
  assert_eq!(live.load(Ordering::Acquire),before_failed_trim);
  rows.truncate(ROW_PAGE_LEN,&mut funding).unwrap();
  assert_eq!(rows.len(),ROW_PAGE_LEN);
  for (ordinal,row,kind) in [(0,inline,Ident),(1,medium,Resource),(2,full,Number)] {
   assert_eq!(loan.get().projected_token(ordinal),Some(dm_syntax::SpanToken{kind,span:row.token_span()}));
  }
  assert!(loan.get().projected_token(ROW_PAGE_LEN).is_none());
  let payload=loan.get().credit.reserved_bytes();
  drop((rows,directory));
  assert_eq!(live.load(Ordering::Acquire),payload);
  drop(loan);
  assert_eq!(live.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn anchored_output_bases_preserve_exact_escape_and_reissue_trimmed_block() {
    let fixed = dm_syntax::SettingChargeCounter::root_allocation_bytes();
    let syntax = dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();
    let a = SettingAdmission::new(&syntax, fixed, &|| Ok(()));
    let used = Arc::new(AtomicUsize::new(0));
    let work = CappedWork::new(Arc::clone(&used), usize::MAX);
    let mut credit = work.reserve(0).unwrap();
    let mut funding = PageFunding { work: &work, credit: &mut credit };
    let mut bases = RowOutputBases::new();
    let base = 99_000;
    for rank in 0..RowOutputBases::BLOCK {
        let value = match rank {
            1 => base + usize::from(u16::MAX) - 1,
            2 => base + usize::from(u16::MAX),
            3 => base - 1,
            _ => base + rank,
        };
        bases.push(value, &a, &mut funding).unwrap();
        assert_eq!(bases.get(rank), Some(value));
    }
    assert_eq!(bases.wide.iter().map(WideOutputBase::rank).collect::<Vec<_>>(), [2, 3]);
    bases.push(usize::MAX, &a, &mut funding).unwrap();
    bases.push(usize::MAX, &a, &mut funding).unwrap();
    assert_eq!(bases.get(128), Some(usize::MAX));
    assert_eq!(bases.get(129), Some(usize::MAX));
    bases.truncate(128, &mut funding).unwrap();
    assert_eq!(bases.anchors, [base]);
    bases.push(17, &a, &mut funding).unwrap();
    bases.push(18, &a, &mut funding).unwrap();
    assert_eq!(bases.get(128), Some(17));
    assert_eq!(bases.get(129), Some(18));
    let before = used.load(Ordering::Acquire);
    let escaped_bytes = bases.wide.capacity() * std::mem::size_of::<WideOutputBase>();
    bases.truncate(2, &mut funding).unwrap();
    assert_eq!(used.load(Ordering::Acquire), before - escaped_bytes);
    assert_eq!(bases.get(2), None);
    assert!(bases.wide.is_empty());
    work.limit.store(used.load(Ordering::Acquire), Ordering::Release);
    assert_eq!(bases.push(base - 1, &a, &mut funding).unwrap_err().kind(), io::ErrorKind::OutOfMemory);
    assert_eq!(bases.get(1), Some(base + usize::from(u16::MAX) - 1));
    assert_eq!(bases.get(2), None);
    work.limit.store(usize::MAX, Ordering::Release);
    bases.push(base - 1, &a, &mut funding).unwrap();
    assert_eq!(bases.get(2), Some(base - 1));
    drop((bases, credit));
    assert_eq!(used.load(Ordering::Acquire), 0);
    assert_eq!(syntax.load(Ordering::Acquire), fixed);
 }

 #[test]
 fn physical_output_bases_keep_continued_groups_and_exact_wide_offsets() {
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=SettingAdmission::new(&used,4<<20,&||Ok(()));
  let work=OutputWork(Arc::new(AtomicUsize::new(0)));
  let mut credit=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut credit};
  let mut groups=OriginGroups::new();
  let trace=OriginalMacroTrace::empty();
  let group=GroupGeometry{encounter:0,decoded:Span::new(0,8),line:1,output_line:1,
   output_base:usize::MAX-512,raw_base:0};
  let replacement=GroupGeometry{output_base:31,..group};
  groups.push(group,trace.clone(),&a,&mut funding).unwrap();
  groups.push(replacement,trace,&a,&mut funding).unwrap();
  assert!(!groups.packed.get(0).unwrap().is_full(),"wide output base is independent of compact source geometry");
  let row=Row{group:0,output:Span::new(group.output_base+1,group.output_base+5),
   token_end:group.output_base+4,source_offset:0,byte_column:1,raw_extent:Span::new(0,1),actual_eof:false};
  let next=Row{group:1,output:Span::new(32,36),token_end:35,..row};
  let mut rows=RawTokenRows::new(&a).unwrap();
  for _ in 0..=ROW_PAGE_LEN { rows.push(row,group,&a,&mut funding).unwrap(); }
  rows.push(next,replacement,&a,&mut funding).unwrap();
  for page in 0..2 {
   let output=&rows.page(page).unwrap().output_bases;
   assert_eq!(output.get(0),Some(group.output_base));
   assert_eq!(output.anchors, [group.output_base]);
   assert_eq!(output.wide.len(), page);
   if page == 1 {
    assert_eq!(output.wide[0].rank(), 1);
    assert_eq!(output.wide[0].value(), Some(replacement.output_base));
   }
  }
  assert_eq!(rows.get(ROW_PAGE_LEN-1,&groups),Some(row));
  assert_eq!(rows.get(ROW_PAGE_LEN,&groups),Some(row));
  assert_eq!(rows.get(ROW_PAGE_LEN+1,&groups),Some(next));
  rows.truncate(ROW_PAGE_LEN+1,&mut funding).unwrap();
  assert_eq!(rows.page(1).unwrap().output_bases.get(1),None);
  rows.push(next,replacement,&a,&mut funding).unwrap();
  assert_eq!(rows.get(ROW_PAGE_LEN+1,&groups),Some(next));
  let before=work.0.load(Ordering::Acquire);
  rows.truncate(ROW_PAGE_LEN,&mut funding).unwrap();
  assert!(work.0.load(Ordering::Acquire)<before);
  assert_eq!(rows.pages.len(),1);
  drop((rows,groups,credit));
  assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
  assert_eq!(work.0.load(Ordering::Acquire),0);
 }

 #[test]
 fn failed_wide_output_base_keeps_preceding_row_and_rank() {
  let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=SettingAdmission::new(&syntax,4<<20,&||Ok(()));
  let live=Arc::new(AtomicUsize::new(0));
  let work=CappedWork::new(Arc::clone(&live),usize::MAX);
  let mut credit=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut credit};
  let group=GroupGeometry{encounter:0,decoded:Span::new(0,2),line:1,output_line:1,output_base:0,raw_base:0};
  let wide=GroupGeometry{output_base:usize::MAX-2,..group};
  let mut groups=OriginGroups::new();
  let trace=OriginalMacroTrace::empty();
  groups.push(group,trace.clone(),&a,&mut funding).unwrap();
  groups.push(wide,trace,&a,&mut funding).unwrap();
  let first=Row{group:0,output:Span::new(0,1),token_end:1,source_offset:0,
   byte_column:1,raw_extent:Span::new(0,1),actual_eof:false};
  let next=Row{group:1,output:Span::new(usize::MAX-2,usize::MAX),token_end:usize::MAX,..first};
  let mut rows=RawTokenRows::new(&a).unwrap();
  rows.push(first,group,&a,&mut funding).unwrap();
  let before=live.load(Ordering::Acquire);
  work.limit.store(before,Ordering::Release);
  assert_eq!(rows.push(next,wide,&a,&mut funding).unwrap_err().kind(),io::ErrorKind::OutOfMemory);
  assert_eq!(rows.len(),1);
  assert_eq!(rows.get(0,&groups),Some(first));
  assert_eq!(rows.group_at(1),None);
  assert_eq!(live.load(Ordering::Acquire),before);
  work.limit.store(usize::MAX,Ordering::Release);
  rows.push(next,wide,&a,&mut funding).unwrap();
  assert_eq!(rows.get(1,&groups),Some(next));
  drop((rows,groups,credit));
  assert_eq!(live.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn row_group_rank_tracks_wide_transitions_and_reissues_trimmed_suffix() {
  let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
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
  assert_eq!(rows.cell(63).unwrap().class(),NarrowRow::MEDIUM);
  assert_eq!(rows.cell(64).unwrap().class(),NarrowRow::FULL);
  assert_eq!(rows.get(63,&groups),Some(medium));
  assert_eq!(rows.get(64,&groups),Some(full));
  let inline=Row{group:2,..row};
  for _ in rows.len()..ROW_PAGE_LEN{rows.push(inline,group,&a,&mut funding).unwrap();}
  let next_page=Row{group:3,actual_eof:true,..row};
  rows.push(next_page,group,&a,&mut funding).unwrap();
  assert_eq!(rows.get(ROW_PAGE_LEN-1,&groups),Some(inline));
  assert_eq!(rows.get(ROW_PAGE_LEN,&groups),Some(next_page));

  rows.truncate(64,&mut funding).unwrap();
  assert_eq!(rows.pages.len(),1);
  assert_eq!(rows.last_group,Some(1));
  assert_eq!(rows.full_len(),0);
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
  assert_eq!(live.load(Ordering::Acquire),bytes + {
   let mut groups_bytes=0;
   groups.visit_storage(|_,_,capacity|groups_bytes+=capacity);
   groups_bytes
  },"all real row/rank/escape pages and directories remain funded");
  drop((rows,groups,credit));
  assert_eq!(live.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn failed_cell_page_append_does_not_publish_escape_or_replace_prior_cells() {
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
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
  let first=rows.cell(0).unwrap() as *const NarrowRow;
  let before=used.load(Ordering::Acquire);
  let source_before=source.load(Ordering::Acquire);work.limit.store(source_before,Ordering::Release);
  assert_eq!(rows.push(Row{group:1,..medium},group,&initial,&mut funding).unwrap_err().kind(),io::ErrorKind::OutOfMemory);
  assert_eq!(rows.len(),ROW_PAGE_LEN);
  assert_eq!(rows.pages.len(),1);
  assert_eq!(rows.medium_len(),1);
  assert_eq!(rows.pages.len(),1);
  assert_eq!(rows.group_at(ROW_PAGE_LEN-1),Some(0));
  assert_eq!(rows.last_group,Some(0));
  assert_eq!(rows.cell(0).unwrap() as *const NarrowRow,first);
  assert_eq!(used.load(Ordering::Acquire),before);
  assert_eq!(source.load(Ordering::Acquire),source_before);
  drop(rows);drop(credit);assert_eq!(source.load(Ordering::Acquire),0);
  assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
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
   fn reserve(&self,bytes:usize)->io::Result<SourceArenaCredit>{
    if self.armed.load(Ordering::Acquire) && bytes==PhysicalOriginPage::control_bytes() {
     self.ranks.fetch_add(1,Ordering::AcqRel);
    }
    self.backing.reserve(bytes)
   }
   fn grow(&self,credit:&mut SourceArenaCredit,bytes:usize)->io::Result<()> {
    if self.armed.load(Ordering::Acquire) {
     if bytes==ROW_PAGE_LEN*std::mem::size_of::<NarrowRow>() {
      return std::fs::File::open(&self.absent).map(drop);
     }
    }
    self.backing.grow(credit,bytes)
   }
   fn shrink(&self,credit:&mut SourceArenaCredit,bytes:usize)->io::Result<()>{self.backing.shrink(credit,bytes)}
  }
  let absent=std::env::current_exe().unwrap().join("not-a-directory/origin-row-provider");
  let expected=std::fs::File::open(&absent).unwrap_err();
  let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
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
  assert_eq!(rows.pages.len(),0);
  assert_eq!(rows.medium_len(),0);
  assert_eq!(rows.last_group,None);
  assert_eq!(live.load(Ordering::Acquire),0,"unpublished page drops every local buffer and its source credit");

  work.armed.store(false,Ordering::Release);
  rows.push(medium,geometry,&a,&mut funding).unwrap();
  assert_eq!(rows.group_at(0),Some(0));
  assert_eq!(rows.medium_len(),1);
  drop((rows,credit));
  assert_eq!(live.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]
 fn actual_append_frontier_keeps_last_published_geometry_on_row_refusal() {
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=SettingAdmission::new(&used,32<<20,&||Ok(()));
  let file=File::new(b"var/value=7\n");
  let mut source=driver(&a);
  source.push_opened(&file,file.lease.clone(),0,&a).unwrap();
  let mut host=Host{ordinary:OriginalOrdinaryOutput::new(&a).unwrap()};
  let first=next(&mut source,&file,&mut host,&a).unwrap();
  let second=next(&mut source,&file,&mut host,&a).unwrap();
  let live=Arc::new(AtomicUsize::new(0));
  let work=CappedWork::new(Arc::clone(&live),usize::MAX);
  let mut rows=OriginalRawOrigins::new(&a,&work).unwrap();
  let metadata=a.reserve(1024).unwrap();
  let path=Arc::new(PathBuf::from("actual-frontier.dm"));
  let trace=OriginalMacroTrace::empty();
  rows.append_actual_using(&first,Span::new(0,1),Span::new(0,1),1,0,path.clone(),trace.clone(),
   &file.lease,&file,&mut source,&a,&work).unwrap();
  let before=rows.last_emitted.unwrap();
  let funded=live.load(Ordering::Acquire);
  work.limit.store(funded,Ordering::Release);
  // A different region and line publish a speculative group/encounter.
  // A wide cover needs a new side-page allocation, which is denied.
  let error=rows.append_actual_using(&second,Span::new(1,2),Span::new(1,302),2,1,path.clone(),trace.clone(),
   &file.lease,&file,&mut source,&a,&work).unwrap_err();
  assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);
  assert_eq!(rows.len(),1);
  assert_eq!(rows.groups.len(),1);
  assert_eq!(rows.encounters.len(),1);
  assert_eq!(rows.last_emitted.unwrap().geometry,before.geometry);
  assert_eq!(rows.last_emitted.unwrap().cover_end,1);
  assert_eq!(live.load(Ordering::Acquire),funded);

  work.limit.store(usize::MAX,Ordering::Release);
  rows.append_actual_using(&second,Span::new(1,2),Span::new(1,2),1,0,path.clone(),trace.clone(),
   &file.lease,&file,&mut source,&a,&work).unwrap();
  assert_eq!(rows.groups.len(),1,"retry reuses the last actually published group");
  assert_eq!(rows.last_emitted.unwrap().geometry,rows.rows.group_geometry(0,&rows.groups).unwrap());
  assert_eq!(rows.last_emitted.unwrap().cover_end,2);
  assert_eq!(rows.row(1).unwrap().output,Span::new(1,2));
  drop((rows,source,host,path,trace,first,second,metadata));
  assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
  assert_eq!(live.load(Ordering::Acquire),0);
 }

 #[test]fn actual_raw_arena_rejects_equal_bytes_foreign_acquisition_and_nonexact_offsets(){
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let file=File::new(b"var/value=7\n");let foreign=File::new(b"var/value=7\n");let mut source=driver(&a);source.push_opened(&file,file.lease.clone(),0,&a).unwrap();let mut host=Host{ordinary:OriginalOrdinaryOutput::new(&a).unwrap()};let actual=next(&mut source,&file,&mut host,&a).unwrap();let work=OutputWork(Arc::new(AtomicUsize::new(0)));let mut rows=OriginalRawOrigins::new(&a,&work).unwrap();let credit=a.reserve(1024).unwrap();let path=Arc::new(PathBuf::from("same.dm"));let trace=OriginalMacroTrace::empty();rows.append_actual_using(&actual,Span::new(0,4),Span::new(0,5),1,0,path,trace,&file.lease,&file,&mut source,&a,&work).unwrap();assert!(rows.point(0,0,&foreign.lease,0).is_err());assert!(rows.point(0,1,&file.lease,0).is_err());assert!(rows.point(0,0,&file.lease,1).is_err());assert_eq!(rows.policy_line(0,0,&file.lease,3).unwrap(),1);assert!(rows.policy_line(0,0,&foreign.lease,3).is_err());drop((rows,source,host,credit));assert!(used.load(Ordering::Acquire)>dm_syntax::SettingChargeCounter::root_allocation_bytes(),"the still-owned emitted token must retain its own text credit");drop(actual);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
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
  fn try_grow_original_origin_storage(&self, credit:&mut SourceArenaCredit, bytes:usize)->io::Result<bool>{
   if self.allow(bytes).is_err(){return Ok(false)}
   self.backing.grow(credit,bytes)?;
   Ok(true)
  }
  fn reserve(&self, bytes:usize)->io::Result<SourceArenaCredit>{self.allow(bytes)?;self.backing.reserve(bytes)}
  fn grow(&self, credit:&mut SourceArenaCredit, bytes:usize)->io::Result<()>{self.allow(bytes)?;self.backing.grow(credit,bytes)}
  fn shrink(&self, credit:&mut SourceArenaCredit, bytes:usize)->io::Result<()>{self.backing.shrink(credit,bytes)}
 }
 #[test]
 fn page_directory_denial_drops_new_page_and_preserves_both_domains() {
  let syntax=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let source=Arc::new(AtomicUsize::new(0));
  let work=CappedWork::new(Arc::clone(&source),ROW_PAGE_LEN*std::mem::size_of::<NarrowRow>());
  let a=SettingAdmission::new(&syntax,dm_syntax::SettingChargeCounter::root_allocation_bytes(),&||Ok(()));
  let mut credit=work.reserve(0).unwrap();
  let mut funding=PageFunding{work:&work,credit:&mut credit};
  let mut rows=OriginPages::new();
  let row=NarrowRow{tag:0,fields:[0;3]};
  assert_eq!(rows.push(row,&a,&mut funding).unwrap_err().kind(),io::ErrorKind::OutOfMemory);
  assert_eq!(rows.len(),0);
  assert_eq!(rows.pages.capacity(),0);
  assert_eq!(source.load(Ordering::Acquire),0);
  assert_eq!(syntax.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn actual_receiver_receipt_trims_raw_eof_lookahead_without_claiming_consumed_eof_and_rejects_foreign_same_end(){
  use super::super::{original_prepared_output::OriginalOutputCursor,original_source_arena::OriginalSourceArena};
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let mut text=format!("/datum/{}\n", "x".repeat(usize::from(u16::MAX)+1));text.push_str(&format!("/datum/{}\n","m".repeat(300)));text.push_str(&"var/x\n".repeat(ROW_PAGE_LEN));let file=File::new(text.as_bytes());let mut source=driver(&a);source.push_opened(&file,file.lease.clone(),0,&a).unwrap();let mut host=Host{ordinary:OriginalOrdinaryOutput::new(&a).unwrap()};let metadata=a.reserve(1024).unwrap();let path=Arc::new(PathBuf::from("delivery.dm"));let trace=OriginalMacroTrace::empty();let mut cursor=OriginalOutputCursor::new(&a).unwrap();let initial=cursor.initial_delivery().unwrap();let work=OutputWork(Arc::new(AtomicUsize::new(0)));let mut rows=OriginalRawOrigins::new(&a,&work).unwrap();rows.bind_output_using(&initial,&a).unwrap();let mut prepared=Vec::new();
  while let Some(actual)=next(&mut source,&file,&mut host,&a){
   let item=cursor.prepare(actual,&file,&a).unwrap();
   let region=usize::from(prepared.len() > ROW_PAGE_LEN);
   rows.append_produced_using(item.actual().unwrap(),item.produced(),region,&path,&trace,&file.lease,&file,&mut source,None,&a,&work).unwrap();
   prepared.push(item);
  }
  assert!(rows.groups.len() > ROW_PAGE_LEN);
  assert_eq!(rows.encounters.len(), 2, "physical rows and their traces share only the same encounter");
  assert_eq!(rows.get(rows.len() - 1).unwrap().region, 1);
  assert!(rows.len()>ROW_PAGE_LEN);
  let before_pages=rows.rows.pages.len();
  assert!(before_pages>1);
  assert!(rows.groups.packed.pages.len()>1);
  assert_eq!(rows.rows.cell(0).unwrap().class(),0,"first short actual token uses the compact layout");
  assert!(rows.rows.medium_len()>0,"actual 300-byte token or row offset uses the medium fallback");
  assert!(rows.rows.full_len()>0,"actual wide token or row offset uses the full fallback");
  for (index, item) in prepared.iter().enumerate() {
   let cell=rows.rows.cell(index).unwrap();
   assert_eq!(cell.projected_kind(),Some(item.token().kind));
   assert_eq!(rows.row(index).unwrap().token_span(),item.token().span);
  }
  let wide_index=(0..rows.len()).find(|&at|rows.rows.cell(at).unwrap().class()==NarrowRow::FULL).unwrap();
  let(wide_occurrence,wide_point,wide_token,wide_raw,_)=rows.geometry(wide_index).unwrap();
  assert_eq!(wide_occurrence,0);
  assert_eq!(rows.point(wide_index,0,&file.lease,wide_token.start).unwrap(),wide_point);
  assert!(wide_token.end-wide_token.start>usize::from(u16::MAX));
  assert_eq!(wide_raw.end-wide_raw.start,wide_token.end-wide_token.start);
  assert!((0..rows.len()).any(|at|rows.geometry(at).unwrap().4),"producer genuinely reached raw EOF before receiver starts");
  // A different actual cursor/receiver produces the SAME first span. Matching
  // numbers do not authorize trimming this producer's retained mappings.
  let mut foreign=OriginalOutputCursor::new(&a).unwrap();let foreign_item=foreign.prepare(prepared[0].actual().unwrap().duplicate(&a).unwrap(),&file,&a).unwrap();let mut foreign_arena=OriginalSourceArena::new(&work).unwrap();let mut foreign_primary=dm_syntax::OriginalPrimaryDemand::new(&a,None).unwrap();let(foreign_token,foreign_receipt)=foreign_item.into_delivery().adopt(&mut foreign_arena,&mut foreign_primary,&foreign.identity(),&a).unwrap();assert!(rows.retain_delivered_using(&foreign_receipt,&a,&work).is_err());
  let mut arena=OriginalSourceArena::new(&work).unwrap();let mut primary=dm_syntax::OriginalPrimaryDemand::new(&a,None).unwrap();let(first,receipt)=prepared.remove(0).into_delivery().adopt(&mut arena,&mut primary,&cursor.identity(),&a).unwrap();assert_eq!(receipt.end(),foreign_receipt.end());let full_charge=work.0.load(Ordering::Acquire);let keep=rows.retain_delivered_using(&receipt,&a,&work).unwrap();assert!(work.0.load(Ordering::Acquire)<full_charge,"actual unreceived page storage is refunded");assert_eq!(keep,1);assert_eq!(rows.len(),1);assert_eq!(rows.rows.pages.len(),1,"real receipt drops every undelivered packed page");assert_eq!(rows.groups.packed.pages.len(),1,"real receipt drops every undelivered group page");assert_eq!(rows.encounters.len(),1,"undelivered encounter drops with its rows");assert_eq!(rows.rows.page(0).unwrap().medium.pages.len(),0,"unreceived medium pages are released");assert_eq!(rows.rows.page(0).unwrap().full.pages.len(),0,"unreceived full pages are released");assert!(!rows.geometry(0).unwrap().4,"unreceived producer EOF cannot become received output EOF");assert!(rows.has_delivered_binding());assert!(rows.delivered_tokens(&foreign_receipt,&a).is_err());assert!(rows.delivered_tokens(&initial,&a).is_err());assert!(rows.delivered_tokens(&receipt,&a).unwrap().eq([Some(first.token)]));assert!(rows.retain_delivered_using(&receipt,&a,&work).is_err());let item=&prepared[0];assert!(rows.append_produced_using(item.actual().unwrap(),item.produced(),0,&path,&trace,&file.lease,&file,&mut source,None,&a,&work).is_err());drop((source,host,rows,cursor,initial,prepared,first,receipt,foreign_token,foreign_receipt,foreign,foreign_primary,primary,arena,foreign_arena,path,trace,metadata));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert_eq!(work.0.load(Ordering::Acquire),0);
 }
 #[test]
 fn exact_issued_default_token_survives_without_a_physical_origin() {
  use super::super::{original_prepared_output::OriginalOutputCursor,original_source_arena::OriginalSourceArena};
  let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a=SettingAdmission::new(&used,8<<20,&||Ok(()));
  let work=OutputWork(Arc::new(AtomicUsize::new(0)));
  let mut rows=OriginalRawOrigins::new(&a,&work).unwrap();
  let mut cursor=OriginalOutputCursor::new(&a).unwrap();
  let initial=cursor.initial_delivery().unwrap();
  rows.bind_output_using(&initial,&a).unwrap();
  assert!(rows.delivered_tokens(&initial,&a).is_err());
  let prepared=cursor.prepare_default_semicolon(&a).unwrap();
  rows.append_default_semicolon_using(prepared.produced(),&a).unwrap();
  let mut arena=OriginalSourceArena::new(&work).unwrap();
  let mut primary=dm_syntax::OriginalPrimaryDemand::new(&a,None).unwrap();
  let (actual,receipt)=prepared.into_delivery().adopt(&mut arena,&mut primary,&cursor.identity(),&a).unwrap();
  assert_eq!(rows.retain_delivered_using(&receipt,&a,&work).unwrap(),0);
  assert!(rows.delivered_tokens(&receipt,&a).unwrap().eq([Some(actual.token)]));
  assert_eq!(primary.span_tokens().last(),Some(actual.token));
  assert_eq!(arena.as_str(),";\n");
  assert_eq!(rows.len(),0);
  assert!(rows.geometry(0).is_none());
  drop((rows,cursor,initial,receipt,actual,arena,primary));
  assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
  assert_eq!(work.0.load(Ordering::Acquire),0);
 }

 #[test]fn same_actual_empty_delivery_discards_all_unreceived_rows_but_foreign_zero_cannot_bind(){
  use super::super::original_prepared_output::OriginalOutputCursor;let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let cursor=OriginalOutputCursor::new(&a).unwrap();let actual=cursor.initial_delivery().unwrap();let foreign=OriginalOutputCursor::new(&a).unwrap();let work=OutputWork(Arc::new(AtomicUsize::new(0)));let mut rows=OriginalRawOrigins::new(&a,&work).unwrap();rows.bind_output_using(&actual,&a).unwrap();assert!(rows.bind_output_using(&foreign.initial_delivery().unwrap(),&a).is_err());assert_eq!(rows.retain_delivered_using(&actual,&a,&work).unwrap(),0);assert!(rows.has_delivered_binding());drop((rows,actual,cursor,foreign));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }

}
