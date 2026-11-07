use crate::{SettingAdmission, SettingRootLease, Span, SpanToken, TokenKind};
use std::{alloc::{alloc, Layout}, io, mem, ptr::NonNull};

const PAGE_ROWS: usize = 4096;
const KIND_BITS: u32 = 4;
const WIDTH_BITS: u32 = 8;
const START_SHIFT: u32 = KIND_BITS + WIDTH_BITS;
const WIDE_TAG: u32 = 15;
const MAX_WIDTH: usize = (1 << WIDTH_BITS) - 1;
const MAX_START_DELTA: usize = (1 << (u32::BITS - START_SHIFT)) - 1;

#[repr(transparent)]
struct PackedToken(u32);

const GROUP_ROWS: usize = 64;
const GROUPS_PER_PAGE: usize = PAGE_ROWS / GROUP_ROWS;
const MAX_GROUP_START: u32 = (1 << (24 - START_SHIFT)) - 1;

type ShortToken = [u8; 3];

struct CompactTokenGroup {
    // Delta from the existing page base. Full coordinates are never narrowed.
    start_delta: u32,
    rows: [ShortToken; GROUP_ROWS],
}

// A single funded byte buffer holds a full page and both narrow sides.
struct NarrowTokenPage(Vec<u8>);

const NARROW_WIDTH_BITS: u32 = 3;
const NARROW_WIDTH_ESCAPE: u32 = 7;
const NARROW_START_SHIFT: u32 = KIND_BITS + NARROW_WIDTH_BITS;
const GEOMETRY_TAG: u32 = 14;
const NARROW_GROUP_HEADER: usize = 4 + 2 + 8;
const NARROW_GROUP_BYTES: usize = NARROW_GROUP_HEADER + 2 * GROUP_ROWS;
const NARROW_FIXED_BYTES: usize = 2 + GROUPS_PER_PAGE * NARROW_GROUP_BYTES;

enum NarrowCell { Inline, WidthSide, GeometrySide, ExistingWide }

fn narrow_cell<const WIDTH: u32>(word: u32) -> NarrowCell {
    let max_start = (1 << (16 - KIND_BITS - WIDTH)) - 1;
    let width_escape = (1 << WIDTH) - 1;
    if word & 15 == WIDE_TAG {
        NarrowCell::ExistingWide
    } else if word >> START_SHIFT > max_start {
        NarrowCell::GeometrySide
    } else if ((word >> KIND_BITS) & MAX_WIDTH as u32) >= width_escape {
        NarrowCell::WidthSide
    } else {
        NarrowCell::Inline
    }
}

fn group_word(word: u32, start_delta: u32) -> u32 {
    if word & 15 == WIDE_TAG {
        word
    } else {
        let start = (word >> START_SHIFT) - start_delta;
        (word & ((1 << START_SHIFT) - 1)) | (start << START_SHIFT)
    }
}

impl NarrowTokenPage {
    fn read<const N: usize>(data: &[u8], offset: usize) -> [u8; N] {
        data[offset..offset + N].try_into().expect("issued narrow token field")
    }

    fn word(&self, index: usize) -> (u32, u32) {
        let group = 2 + (index / GROUP_ROWS) * NARROW_GROUP_BYTES;
        let local = index % GROUP_ROWS;
        let data = &self.0;
        let base = u32::from_le_bytes(Self::read(data, group));
        let word = u16::from_le_bytes(Self::read(data, group + NARROW_GROUP_HEADER + 2 * local)) as u32;
        let kind = word & 15;
        if kind == WIDE_TAG {
            return (word, base);
        }
        if kind == GEOMETRY_TAG {
            let width_total = u16::from_le_bytes(Self::read(data, 0)) as usize;
            let offset = NARROW_FIXED_BYTES + width_total + 3 * (word >> KIND_BITS) as usize;
            let [a, b, c] = Self::read(data, offset);
            return (u32::from_le_bytes([a, b, c, 0]), base);
        }
        let width = (word >> KIND_BITS) & NARROW_WIDTH_ESCAPE;
        let width = if width == NARROW_WIDTH_ESCAPE {
            let width_base = u16::from_le_bytes(Self::read(data, group + 4)) as usize;
            let mask = u64::from_le_bytes(Self::read(data, group + 6));
            let rank = (mask & ((1u64 << local) - 1)).count_ones() as usize;
            data[NARROW_FIXED_BYTES + width_base + rank] as u32
        } else {
            width
        };
        let start = word >> NARROW_START_SHIFT;
        (kind | (width << KIND_BITS) | (start << START_SHIFT), base)
    }

    fn try_build(
        words: &[PackedToken], bases: &[u32; GROUPS_PER_PAGE], compact_bytes: usize,
        a: &SettingAdmission<'_>,
    ) -> io::Result<Option<(Self, SettingRootLease)>> {
        let mut widths = 0;
        let mut geometries = 0;
        for (group, &base) in words.chunks_exact(GROUP_ROWS).zip(bases) {
            for row in group {
                match narrow_cell::<NARROW_WIDTH_BITS>(group_word(row.0, base)) {
                    NarrowCell::WidthSide => widths += 1,
                    NarrowCell::GeometrySide => geometries += 1,
                    NarrowCell::Inline | NarrowCell::ExistingWide => {}
                }
            }
        }
        let bytes = NARROW_FIXED_BYTES + widths + 3 * geometries;
        if bytes >= compact_bytes {
            return Ok(None);
        }
        let Some(_scratch) = a.try_reserve_optimization(mem::size_of_val(bases)).map_err(|status| a.take_operational_error().unwrap_or(status))? else {
            return Ok(None);
        };
        let Some(credit) = a.try_reserve_optimization(bytes).map_err(|status| a.take_operational_error().unwrap_or(status))? else { return Ok(None) };
        let layout = Layout::array::<u8>(bytes).map_err(io::Error::other)?;
        let mut data = match alloc_funded_vec(bytes, layout) {
            Ok(rows) => rows,
            Err(error) if error.kind() == io::ErrorKind::OutOfMemory => return Ok(None),
            Err(error) => return Err(error),
        };
        data.resize(bytes, 0);
        data[..2].copy_from_slice(&(widths as u16).to_le_bytes());
        let mut next_width = 0;
        let mut next_geometry = 0;
        for (index, (group, &base)) in words.chunks_exact(GROUP_ROWS).zip(bases).enumerate() {
            let offset = 2 + index * NARROW_GROUP_BYTES;
            data[offset..offset + 4].copy_from_slice(&base.to_le_bytes());
            data[offset + 4..offset + 6].copy_from_slice(&(next_width as u16).to_le_bytes());
            let mut width_mask = 0u64;
            for (local, row) in group.iter().enumerate() {
                let word = group_word(row.0, base);
                let width = (word >> KIND_BITS) & MAX_WIDTH as u32;
                let kind = word & 15;
                let start = word >> START_SHIFT;
                let narrow = match narrow_cell::<NARROW_WIDTH_BITS>(word) {
                    NarrowCell::Inline => kind | (width << KIND_BITS) | (start << NARROW_START_SHIFT),
                    NarrowCell::WidthSide => {
                        data[NARROW_FIXED_BYTES + next_width] = width as u8;
                        next_width += 1;
                        width_mask |= 1u64 << local;
                        kind | (NARROW_WIDTH_ESCAPE << KIND_BITS) | (start << NARROW_START_SHIFT)
                    }
                    NarrowCell::GeometrySide => {
                        let side = NARROW_FIXED_BYTES + widths + 3 * next_geometry;
                        data[side..side + 3].copy_from_slice(&word.to_le_bytes()[..3]);
                        let narrow = GEOMETRY_TAG | ((next_geometry as u32) << KIND_BITS);
                        next_geometry += 1;
                        narrow
                    }
                    NarrowCell::ExistingWide => word,
                };
                let cell = offset + NARROW_GROUP_HEADER + 2 * local;
                debug_assert!(u16::try_from(narrow).is_ok());
                data[cell..cell + 2].copy_from_slice(&(narrow as u16).to_le_bytes());
            }
            data[offset + 6..offset + NARROW_GROUP_HEADER].copy_from_slice(&width_mask.to_le_bytes());
        }
        debug_assert_eq!((next_width, next_geometry), (widths, geometries));
        Ok(Some((Self(data), credit)))
    }
}

enum TokenPageRows {
    Words(Vec<PackedToken>),
    Compact(Vec<CompactTokenGroup>),
    Narrow(NarrowTokenPage),
}

struct TokenPage {
    rows: TokenPageRows,
    start_base: usize,
    wide_base: usize,
}

impl TokenPage {
    fn get(&self, index: usize, wide: &[SpanToken]) -> Option<SpanToken> {
        match &self.rows {
            TokenPageRows::Words(rows) => {
                let word = rows.get(index)?.0;
                Some(PackedToken::decode_word(word, self.start_base, self.wide_base, wide))
            }
            TokenPageRows::Narrow(page) => {
                let (word, start_delta) = page.word(index);
                let base = self.start_base.checked_add(start_delta as usize)
                    .expect("issued narrow group base");
                Some(PackedToken::decode_word(word, base, self.wide_base, wide))
            }
            TokenPageRows::Compact(groups) => {
                let group = groups.get(index / GROUP_ROWS)?;
                let [a, b, c] = group.rows[index % GROUP_ROWS];
                let word = u32::from_le_bytes([a, b, c, 0]);
                let base = self.start_base.checked_add(group.start_delta as usize)
                    .expect("issued compact group base");
                Some(PackedToken::decode_word(word, base, self.wide_base, wide))
            }
        }
    }

    fn seal_completed_using(&mut self, credit: &mut SettingRootLease, a: &SettingAdmission<'_>) -> io::Result<()> {
        let TokenPageRows::Words(words) = &self.rows else { return Ok(()) };
        if words.len() != PAGE_ROWS {
            return Err(io::ErrorKind::InvalidData.into());
        }

        // Every existing wide row keeps its original side-table address. A
        // page with any new unencodable common row keeps its original words.
        // Preflight retains no extra heap or parallel token representation.
        let mut bases = [0; GROUPS_PER_PAGE];
        for (group, base) in words.chunks_exact(GROUP_ROWS).zip(&mut bases) {
            let (lo, hi) = group.iter()
                .filter(|row| row.0 & 15 != WIDE_TAG)
                .map(|row| row.0 >> START_SHIFT)
                .fold((u32::MAX, 0), |(lo, hi), start| (lo.min(start), hi.max(start)));
            if lo == u32::MAX {
                continue; // All rows already have full-width side entries.
            }
            if hi - lo > MAX_GROUP_START {
                return Ok(());
            }
            *base = lo;
        }

        let layout = Layout::array::<CompactTokenGroup>(GROUPS_PER_PAGE).map_err(io::Error::other)?;
        let old_bytes = words.capacity() * mem::size_of::<PackedToken>();
        if layout.size() >= old_bytes {
            return Ok(());
        }
        if let Some((narrow, new_credit)) = NarrowTokenPage::try_build(words, &bases, layout.size(), a)? {
            return self.replace_completed(TokenPageRows::Narrow(narrow), new_credit, old_bytes, credit, a);
        }
        // The old words remain live through the whole conversion. New heap
        // and the bounded construction scratch need a separate actual grant.
        let scratch = mem::size_of_val(&bases) + mem::size_of::<CompactTokenGroup>();
        let Some(_scratch) = a.try_reserve_optimization(scratch).map_err(|status| a.take_operational_error().unwrap_or(status))? else { return Ok(()) };
        let Some(new_credit) = a.try_reserve_optimization(layout.size()).map_err(|status| a.take_operational_error().unwrap_or(status))? else { return Ok(()) };
        let mut compact = match alloc_funded_vec(GROUPS_PER_PAGE, layout) {
            Ok(rows) => rows,
            Err(error) if error.kind() == io::ErrorKind::OutOfMemory => return Ok(()),
            Err(error) => return Err(error),
        };
        for (group, start_delta) in words.chunks_exact(GROUP_ROWS).zip(bases) {
            let rows = std::array::from_fn(|index| {
                let compact = group_word(group[index].0, start_delta);
                let [a, b, c, high] = compact.to_le_bytes();
                debug_assert_eq!(high, 0, "preflighted group and existing side index");
                [a, b, c]
            });
            compact.push(CompactTokenGroup { start_delta, rows });
        }

        self.replace_completed(TokenPageRows::Compact(compact), new_credit, old_bytes, credit, a)
    }

    fn replace_completed(
        &mut self, next: TokenPageRows, mut new_credit: SettingRootLease,
        old_bytes: usize, credit: &mut SettingRootLease, a: &SettingAdmission<'_>,
    ) -> io::Result<()> {
        // Transfer the new grant only after successful construction. The
        // old grant stays with the tape until the old buffer has been freed.
        if let Err(error) = a.absorb(credit, &mut new_credit) {
            drop(next);
            return Err(error);
        }
        drop(mem::replace(&mut self.rows, next));
        a.shrink(credit, old_bytes).map_err(|status| a.take_operational_error().unwrap_or(status))?;
        Ok(())
    }
}

#[cfg(debug_assertions)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct NarrowTapeGeometry {
    inline: usize,
    width_side: usize,
    geometry_side: usize,
    existing_wide: usize,
    smaller_pages: usize,
    estimated_saved_bytes: usize,
}

#[cfg(debug_assertions)]
impl NarrowTapeGeometry {
    fn count<const WIDTH: u32>(&mut self, word: u32) {
        match narrow_cell::<WIDTH>(word) {
            NarrowCell::Inline => self.inline += 1,
            NarrowCell::WidthSide => self.width_side += 1,
            NarrowCell::GeometrySide => self.geometry_side += 1,
            NarrowCell::ExistingWide => self.existing_wide += 1,
        }
    }

    fn include_page(&mut self, page: Self) {
        self.inline += page.inline;
        self.width_side += page.width_side;
        self.geometry_side += page.geometry_side;
        self.existing_wide += page.existing_wide;
        // Byte-array design: u16 width total; per group, u32 start
        // base, u16 width side base, u64 width rank mask, and 64 u16s.
        // Full-width entries keep their current funded side-table address.
        let narrow = NARROW_FIXED_BYTES + page.width_side + 3 * page.geometry_side;
        let compact = GROUPS_PER_PAGE * mem::size_of::<CompactTokenGroup>();
        if narrow < compact {
            self.smaller_pages += 1;
            self.estimated_saved_bytes += compact - narrow;
        }
    }
}

impl PackedToken {
    fn common(token: SpanToken, start_base: usize) -> Option<Self> {
        let start = token.span.start.checked_sub(start_base)?;
        let width = token.span.end.checked_sub(token.span.start)?;
        if start > MAX_START_DELTA || width > MAX_WIDTH {
            return None;
        }
        let kind = match token.kind {
            TokenKind::Ident => 0, TokenKind::Number => 1, TokenKind::String => 2,
            TokenKind::Resource => 3, TokenKind::Interpolation => 4, TokenKind::Operator => 5,
            TokenKind::Punctuation => 6, TokenKind::Whitespace => 7, TokenKind::Newline => 8,
            TokenKind::Comment => 9, TokenKind::Unknown => 10,
        };
        Some(Self(((start as u32) << START_SHIFT) | ((width as u32) << KIND_BITS) | kind))
    }

    fn wide(page_ordinal: usize) -> Self {
        // A page has at most one escape per actual row. The global side
        // ordinal is reconstructed from the separate, full-width page base.
        assert!(page_ordinal < PAGE_ROWS);
        Self(((page_ordinal as u32) << KIND_BITS) | WIDE_TAG)
    }

    fn decode_word(word: u32, start_base: usize, wide_base: usize, wide: &[SpanToken]) -> SpanToken {
        let kind = match word & 15 {
            0 => TokenKind::Ident, 1 => TokenKind::Number, 2 => TokenKind::String,
            3 => TokenKind::Resource, 4 => TokenKind::Interpolation, 5 => TokenKind::Operator,
            6 => TokenKind::Punctuation, 7 => TokenKind::Whitespace, 8 => TokenKind::Newline,
            9 => TokenKind::Comment, 10 => TokenKind::Unknown,
            WIDE_TAG => return wide[wide_base.checked_add((word >> KIND_BITS) as usize)
                .expect("issued wide token index")],
            _ => unreachable!("issued packed token kind"),
        };
        let start = start_base.checked_add((word >> START_SHIFT) as usize)
            .expect("issued packed token start");
        let width = ((word >> KIND_BITS) & MAX_WIDTH as u32) as usize;
        let end = start.checked_add(width).expect("issued packed token end");
        SpanToken { kind, span: Span::new(start, end) }
    }
}

pub(super) fn poll(a: &SettingAdmission<'_>) -> io::Result<()> {
    a.checkpoint().map_err(|status| a.take_operational_error().unwrap_or(status))
}

pub(super) fn exact_vec<T>(
    capacity: usize, credit: &mut SettingRootLease, a: &SettingAdmission<'_>,
) -> io::Result<Vec<T>> {
    if capacity == 0 {
        return Ok(Vec::new());
    }
    let layout = Layout::array::<T>(capacity).map_err(|e| io::Error::new(io::ErrorKind::OutOfMemory, e))?;
    if layout.size() == 0 {
        return Err(io::ErrorKind::InvalidInput.into());
    }
    a.grow(credit, layout.size()).map_err(|status| a.take_operational_error().unwrap_or(status))?;
    alloc_funded_vec(capacity, layout)
}

fn alloc_funded_vec<T>(capacity: usize, layout: Layout) -> io::Result<Vec<T>> {
    debug_assert_eq!(layout, Layout::array::<T>(capacity).expect("known row layout"));
    // Global allocation with the exact layout Vec uses. No element is initialized
    // yet. Retain the reservation until the caller drops this Vec or fails closed.
    let ptr = NonNull::new(unsafe { alloc(layout) }).ok_or(io::ErrorKind::OutOfMemory)?;
    Ok(unsafe { Vec::from_raw_parts(ptr.as_ptr().cast::<T>(), 0, capacity) })
}

pub(super) fn one_more<T>(rows: &mut Vec<T>, credit: &mut SettingRootLease, a: &SettingAdmission<'_>) -> io::Result<()> {
    if rows.len() == rows.capacity() {
        let capacity = rows.capacity().max(2).checked_mul(2).ok_or(io::ErrorKind::OutOfMemory)?;
        let old_bytes = rows.capacity().checked_mul(mem::size_of::<T>()).ok_or(io::ErrorKind::OutOfMemory)?;
        let mut next = exact_vec(capacity, credit, a)?;
        next.append(rows);
        drop(mem::replace(rows, next));
        a.shrink(credit, old_bytes).map_err(|status| a.take_operational_error().unwrap_or(status))?;
    }
    Ok(())
}

/// Only this owner carries the single packed tape and its funded buffers.
/// A borrow cannot outlive an append or become a second independent tape.
pub(crate) struct PackedTokenBlocks {
    pages: Vec<TokenPage>,
    wide: Vec<SpanToken>,
    len: usize,
    failed: bool,
    credit: SettingRootLease,
}

impl PackedTokenBlocks {
    pub(crate) fn new(a: &SettingAdmission<'_>) -> io::Result<Self> {
        let credit = a.reserve(0).map_err(|status| a.take_operational_error().unwrap_or(status))?;
        Ok(Self { pages: Vec::new(), wide: Vec::new(), len: 0, failed: false, credit })
    }

    pub(crate) fn push(&mut self, token: SpanToken, a: &SettingAdmission<'_>) -> io::Result<()> {
        if self.failed {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        let result = self.push_inner(token, a);
        if result.is_err() {
            self.failed = true;
        }
        result
    }

    fn push_inner(&mut self, token: SpanToken, a: &SettingAdmission<'_>) -> io::Result<()> {
        poll(a)?;
        if !self.admitted_by(a) {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        let len = self.len.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
        if self.len % PAGE_ROWS == 0 {
            if let Some(previous) = self.pages.last_mut() {
                // A completed page is immutable. Sealing the previous page
                // here never changes this token's ordinal or partial cutoff.
                previous.seal_completed_using(&mut self.credit, a)?;
            }
            one_more(&mut self.pages, &mut self.credit, a)?;
            self.pages.push(TokenPage {
                rows: TokenPageRows::Words(exact_vec(PAGE_ROWS, &mut self.credit, a)?),
                start_base: token.span.start,
                wide_base: self.wide.len(),
            });
        }
        let page = self.pages.last_mut().expect("allocated packed token page");
        let packed = match PackedToken::common(token, page.start_base) {
            Some(packed) => packed,
            None => {
                let packed = PackedToken::wide(self.wide.len() - page.wide_base);
                one_more(&mut self.wide, &mut self.credit, a)?;
                self.wide.push(token);
                packed
            }
        };
        let TokenPageRows::Words(rows) = &mut page.rows else {
            unreachable!("the active token page is still writable")
        };
        rows.push(packed);
        self.len = len;
        Ok(())
    }

    pub(super) fn len(&self) -> usize {
        self.len
    }

    pub(super) fn get(&self, ordinal: usize) -> Option<SpanToken> {
        let page = self.pages.get(ordinal / PAGE_ROWS)?;
        page.get(ordinal % PAGE_ROWS, &self.wide)
    }

    pub(super) fn admitted_by(&self, a: &SettingAdmission<'_>) -> bool {
        a.matches_lease_domain(&self.credit)
    }

    pub(super) fn failed(&self) -> bool { self.failed }

    pub(super) fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        fn rows<T>(rows: &Vec<T>, visit: &mut impl FnMut(usize, usize, usize)) {
            if rows.capacity() != 0 {
                visit(rows.as_ptr() as usize, rows.len() * mem::size_of::<T>(), rows.capacity() * mem::size_of::<T>());
            }
        }
        rows(&self.pages, &mut visit);
        for page in &self.pages {
            match &page.rows {
                TokenPageRows::Words(words) => rows(words, &mut visit),
                TokenPageRows::Compact(groups) => rows(groups, &mut visit),
                TokenPageRows::Narrow(page) => rows(&page.0, &mut visit),
            }
        }
        rows(&self.wide, &mut visit);
        self.credit.visit_counter_storage(|address, bytes| {
            let bytes = bytes + 2 * mem::size_of::<usize>();
            visit(address, bytes, bytes);
        });
    }

    #[cfg(debug_assertions)]
    pub(crate) fn trace_retention(&self) -> impl std::fmt::Debug {
        struct Tape {
            rows: usize,
            word_pages: usize,
            compact_pages: usize,
            narrow_pages: usize,
            narrow_geometry_width_bits_2_3_4: Option<[NarrowTapeGeometry; 3]>,
            page_buffer_bytes: usize,
            wide_rows: usize,
            wide_capacity_bytes: usize,
            directory_capacity_bytes: usize,
            total_reserved: usize,
        }
        impl std::fmt::Debug for Tape {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.debug_struct("PrimaryTokenTape")
                    .field("rows", &self.rows)
                    .field("word_pages", &self.word_pages)
                    .field("compact_pages", &self.compact_pages)
                    .field("narrow_pages", &self.narrow_pages)
                    .field("narrow_geometry_width_bits_2_3_4", &self.narrow_geometry_width_bits_2_3_4)
                    .field("page_buffer_bytes", &self.page_buffer_bytes)
                    .field("wide_rows", &self.wide_rows)
                    .field("wide_capacity_bytes", &self.wide_capacity_bytes)
                    .field("directory_capacity_bytes", &self.directory_capacity_bytes)
                    .field("total_reserved", &self.total_reserved)
                    .finish()
            }
        }
        let mut report = Tape {
            rows: self.len, word_pages: 0, compact_pages: 0, narrow_pages: 0, page_buffer_bytes: 0,
            narrow_geometry_width_bits_2_3_4: std::env::var_os("DMB_ORIGINAL_TRACE_TOKEN_GEOMETRY")
                .map(|_| [NarrowTapeGeometry::default(); 3]),
            wide_rows: self.wide.len(), wide_capacity_bytes: self.wide.capacity() * mem::size_of::<SpanToken>(),
            directory_capacity_bytes: self.pages.capacity() * mem::size_of::<TokenPage>(),
            total_reserved: self.credit.bytes(),
        };
        for page in &self.pages {
            match &page.rows {
                TokenPageRows::Words(words) => {
                    report.word_pages += 1;
                    report.page_buffer_bytes += words.capacity() * mem::size_of::<PackedToken>();
                }
                TokenPageRows::Narrow(page) => {
                    report.narrow_pages += 1;
                    report.page_buffer_bytes += page.0.capacity();
                    if let Some(totals) = &mut report.narrow_geometry_width_bits_2_3_4 {
                        let mut geometry = [NarrowTapeGeometry::default(); 3];
                        for index in 0..PAGE_ROWS {
                            let (word, _) = page.word(index);
                            geometry[0].count::<2>(word);
                            geometry[1].count::<3>(word);
                            geometry[2].count::<4>(word);
                        }
                        for (total, page) in totals.iter_mut().zip(geometry) {
                            total.include_page(page);
                        }
                    }
                }
                TokenPageRows::Compact(groups) => {
                    report.compact_pages += 1;
                    report.page_buffer_bytes += groups.capacity() * mem::size_of::<CompactTokenGroup>();
                    if let Some(totals) = &mut report.narrow_geometry_width_bits_2_3_4 {
                        let mut page = [NarrowTapeGeometry::default(); 3];
                        for group in groups {
                            for &[a, b, c] in &group.rows {
                                let word = u32::from_le_bytes([a, b, c, 0]);
                                page[0].count::<2>(word);
                                page[1].count::<3>(word);
                                page[2].count::<4>(word);
                            }
                        }
                        for (total, page) in totals.iter_mut().zip(page) {
                            total.include_page(page);
                        }
                    }
                }
            }
        }
        report
    }

    pub(crate) fn window(&self) -> super::TokenWindow<'_> {
        super::TokenWindow::from_packed(self)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{atomic::{Ordering}};

    #[test]
    fn packed_windows_preserve_page_boundaries_and_wide_actual_values() {
        assert_eq!(mem::size_of::<PackedToken>(), 4);
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut tape = PackedTokenBlocks::new(&a).unwrap();
        for at in 0..PAGE_ROWS + 3 {
            tape.push(SpanToken { kind: TokenKind::Ident, span: Span::new(at * 2, at * 2 + 1) }, &a).unwrap();
        }
        assert!(matches!(&tape.pages[0].rows, TokenPageRows::Narrow(_)));
        let wide = SpanToken { kind: TokenKind::String, span: Span::new(usize::MAX - MAX_WIDTH - 1, usize::MAX) };
        tape.push(wide, &a).unwrap();
        assert_eq!(tape.window().last(), Some(wide));
        let window = tape.window().range(PAGE_ROWS - 2, PAGE_ROWS + 2).unwrap();
        let mut rows = window.iter();
        assert_eq!(rows.nth(1).unwrap().span.start, (PAGE_ROWS - 1) * 2);
        assert_eq!(rows.next_back().unwrap().span.start, (PAGE_ROWS + 1) * 2);
        assert_eq!(rows.next().unwrap().span.start, PAGE_ROWS * 2);
        assert_eq!(rows.next(), None);
        assert_eq!(window.partition_point(|token| token.span.start < PAGE_ROWS * 2), 2);
        assert!(window.same_interval(tape.window().range(PAGE_ROWS - 2, PAGE_ROWS + 2).unwrap()));
        assert!(!window.same_interval(tape.window().range(PAGE_ROWS - 1, PAGE_ROWS + 3).unwrap()));
        let before = used.load(Ordering::Acquire);
        window.with_dense_using(&a, |dense| {
            assert_eq!(used.load(Ordering::Acquire), before + mem::size_of_val(dense));
            assert!(dense.iter().copied().eq(window.iter()));
            Ok(())
        }).unwrap();
        assert_eq!(used.load(Ordering::Acquire), before);
        let error = window.with_dense_using(&a, |_| Err::<(), _>(io::Error::from_raw_os_error(1450))).unwrap_err();
        assert_eq!(error.raw_os_error(), Some(1450));
        assert_eq!(used.load(Ordering::Acquire), before);
        drop(rows);
        let shared = super::super::SharedSpanTokens::from_packed_using(tape, &a).unwrap();
        let alias = shared.clone();
        assert!(shared.window().same_interval(alias.window()));
        assert!(shared.window().as_dense_slice().is_none());
        assert_eq!(alias.window().last(), Some(wide));
        let retained = used.load(Ordering::Acquire);
        drop(shared);
        assert_eq!(used.load(Ordering::Acquire), retained);
        drop(alias);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn page_local_token_bits_preserve_zero_endpoints_and_every_full_width_escape() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut tape = PackedTokenBlocks::new(&a).unwrap();
        let token = |kind, start, end| SpanToken { kind, span: Span::new(start, end) };
        let base = usize::MAX - MAX_START_DELTA - MAX_WIDTH - 2;
        let inputs = [
            token(TokenKind::Ident, base, base), // Packed zero must remain a real row.
            token(TokenKind::String, base, base + MAX_WIDTH + 1),
            token(TokenKind::Whitespace, base + MAX_START_DELTA, base + MAX_START_DELTA + MAX_WIDTH),
            token(TokenKind::Comment, base + MAX_START_DELTA + 1, base + MAX_START_DELTA + 2),
            token(TokenKind::Operator, base - 1, base), // Below this page's base.
            token(TokenKind::Unknown, base, base - 1), // Preexisting raw fallback for reversed spans.
        ];
        for value in inputs {
            tape.push(value, &a).unwrap();
        }
        let TokenPageRows::Words(words) = &tape.pages[0].rows else { panic!("active page") };
        assert_eq!(words[0].0, 0);
        assert_eq!(words[1].0, WIDE_TAG);
        assert_eq!(tape.wide, [inputs[1], inputs[3], inputs[4], inputs[5]]);
        assert!(tape.window().iter().eq(inputs));

        for _ in inputs.len()..PAGE_ROWS {
            tape.push(inputs[0], &a).unwrap();
        }
        // Another page resets the relative coordinate and side ordinal,
        // independently of the preceding page's wide records.
        let first = token(TokenKind::Resource, 0, MAX_WIDTH + 1);
        tape.push(first, &a).unwrap();
        tape.push(token(TokenKind::Punctuation, 0, 1), &a).unwrap();
        assert!(matches!(&tape.pages[0].rows, TokenPageRows::Words(_)),
            "a genuine large common delta retains the original page without new wide rows");
        let TokenPageRows::Words(words) = &tape.pages[1].rows else { panic!("active page") };
        assert_eq!(words[0].0, WIDE_TAG);
        assert_eq!(tape.pages[1].wide_base, 4);
        assert_eq!(tape.get(PAGE_ROWS), Some(first));
        assert_eq!(tape.get(PAGE_ROWS + 1), Some(token(TokenKind::Punctuation, 0, 1)));
        assert_eq!(tape.get(PAGE_ROWS + 2), None);
        drop(tape);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn completed_page_seal_exactly_accounts_overlap_and_keeps_existing_wide_ordinals() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut tape = PackedTokenBlocks::new(&a).unwrap();
        let expected = |at: usize| {
            let group = at / GROUP_ROWS;
            let local = at % GROUP_ROWS;
            let start = 100 + 10_000 * group + local * 2;
            match local {
                2 => SpanToken { kind: TokenKind::String, span: Span::new(usize::MAX - 1024, usize::MAX) },
                3 => SpanToken { kind: TokenKind::Unknown, span: Span::new(start, start - 1) },
                _ => SpanToken { kind: TokenKind::Ident, span: Span::new(start, start + 1) },
            }
        };
        for at in 0..PAGE_ROWS {
            tape.push(expected(at), &a).unwrap();
        }
        let old = used.load(Ordering::Acquire);
        let old_rows = PAGE_ROWS * mem::size_of::<PackedToken>();
        let new_rows = NARROW_FIXED_BYTES;
        let scratch = mem::size_of::<[u32; GROUPS_PER_PAGE]>();
        assert_eq!(old_rows - new_rows, 7294);

        let tight = SettingAdmission::new(&used, old + new_rows + scratch - 1, &|| Ok(()));
        tape.pages[0].seal_completed_using(&mut tape.credit, &tight).unwrap();
        assert!(!tight.is_stopped());
        assert_eq!(used.load(Ordering::Acquire), old);
        assert!(matches!(&tape.pages[0].rows, TokenPageRows::Words(_)));

        for fail_at in 1..=3 {
            let checks = std::cell::Cell::new(0);
            let first_error = || {
                checks.set(checks.get() + 1);
                if checks.get() == fail_at {
                    Err(io::Error::from_raw_os_error(1450))
                } else {
                    Ok(())
                }
            };
            let failing = SettingAdmission::new(&used, old + new_rows + scratch, &first_error);
            let error = tape.pages[0].seal_completed_using(&mut tape.credit, &failing).unwrap_err();
            assert_eq!(error.raw_os_error(), Some(1450));
            assert_eq!(checks.get(), fail_at, "failed OS checks never try the compact fallback");
            assert_eq!(used.load(Ordering::Acquire), old, "replacement dropped before its separate grant");
            assert!(tape.window().iter().eq((0..PAGE_ROWS).map(expected)));
        }

        let just = SettingAdmission::new(&used, old + new_rows + scratch, &|| Ok(()));
        let wide_before = tape.wide.as_ptr();
        tape.pages[0].seal_completed_using(&mut tape.credit, &just).unwrap();
        assert_eq!(tape.wide.as_ptr(), wide_before);
        assert_eq!(used.load(Ordering::Acquire), old - old_rows + new_rows);
        assert!(tape.window().iter().eq((0..PAGE_ROWS).map(expected)));
        assert_eq!(tape.window().get(GROUP_ROWS - 1), Some(expected(GROUP_ROWS - 1)));
        assert_eq!(tape.window().get(GROUP_ROWS), Some(expected(GROUP_ROWS)));
        drop(tape);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn narrow_completed_pages_keep_width_geometry_and_original_wide_sides_exact() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut tape = PackedTokenBlocks::new(&a).unwrap();
        let expected = |at: usize| {
            let group = at / GROUP_ROWS;
            let local = at % GROUP_ROWS;
            let base = 100 + group * 800;
            let (kind, start, width) = match local {
                0 => (TokenKind::Ident, base, 0),
                1 => (TokenKind::Punctuation, base + 511, 6),
                2 => (TokenKind::String, base + 511, 7),
                3 => (TokenKind::Comment, base + 512, 255),
                4..=8 => (TokenKind::Resource, base + 512, 256 + local),
                63 => (TokenKind::Whitespace, base + 500, 255),
                _ => (TokenKind::Ident, base + local, 1),
            };
            SpanToken { kind, span: Span::new(start, start + width) }
        };
        for at in 0..=PAGE_ROWS {
            tape.push(expected(at), &a).unwrap();
        }
        let TokenPageRows::Narrow(page) = &tape.pages[0].rows else { panic!("sealed narrow page") };
        assert_eq!(page.0.capacity(), NARROW_FIXED_BYTES + 5 * GROUPS_PER_PAGE);
        assert_eq!(tape.wide.len(), 5 * GROUPS_PER_PAGE);
        assert!(matches!(&tape.pages[1].rows, TokenPageRows::Words(_)));
        assert_eq!(tape.get(PAGE_ROWS + 1), None);
        assert!(tape.window().iter().eq((0..=PAGE_ROWS).map(expected)));
        let mut storage = 0;
        tape.visit_storage(|_, _, cap| storage += cap);
        assert_eq!(storage, used.load(Ordering::Acquire));
        drop(tape);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn narrow_unprofitable_pages_keep_the_exact_three_byte_fallback() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut tape = PackedTokenBlocks::new(&a).unwrap();
        let expected = |at: usize| {
            let local = at % GROUP_ROWS;
            let start = 100 + if local == 0 { 0 } else { 700 + local };
            SpanToken { kind: TokenKind::Ident, span: Span::new(start, start + 1) }
        };
        for at in 0..=PAGE_ROWS {
            tape.push(expected(at), &a).unwrap();
        }
        assert!(matches!(&tape.pages[0].rows, TokenPageRows::Compact(_)));
        assert!(tape.window().iter().eq((0..=PAGE_ROWS).map(expected)));
        drop(tape);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }

    #[cfg(debug_assertions)]
    #[test]
    fn narrow_tape_geometry_estimates_width_and_start_fallback_independently() {
        let word = |start: u32, width: u32| (start << START_SHIFT) | (width << KIND_BITS);
        let mut page = NarrowTapeGeometry::default();
        page.count::<3>(word(511, 6));
        page.count::<3>(word(511, 7));
        page.count::<3>(word(512, 255));
        page.count::<3>(PackedToken::wide(PAGE_ROWS - 1).0);
        assert_eq!(page, NarrowTapeGeometry {
            inline: 1, width_side: 1, geometry_side: 1, existing_wide: 1,
            ..NarrowTapeGeometry::default()
        });
        let mut total = NarrowTapeGeometry::default();
        total.include_page(page);
        assert_eq!(total.smaller_pages, 1);
        assert_eq!(total.estimated_saved_bytes, 3450);
        total.include_page(NarrowTapeGeometry { geometry_side: PAGE_ROWS, ..NarrowTapeGeometry::default() });
        assert_eq!(total.smaller_pages, 1);
        assert_eq!(total.estimated_saved_bytes, 3450);
    }

    #[test]
    fn packed_page_growth_fails_closed_one_byte_short_and_refunds_every_owner() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let exact = 4 * mem::size_of::<TokenPage>() + PAGE_ROWS * mem::size_of::<PackedToken>();
        let a = SettingAdmission::new(&used, crate::SettingChargeCounter::root_allocation_bytes() + (exact - 1), &|| Ok(()));
        let mut tape = PackedTokenBlocks::new(&a).unwrap();
        let token = SpanToken { kind: TokenKind::Punctuation, span: Span::new(0, 1) };
        assert_eq!(tape.push(token, &a).unwrap_err().kind(), io::ErrorKind::OutOfMemory);
        assert!(tape.window().is_empty());
        assert_eq!(tape.push(token, &a).unwrap_err().kind(), io::ErrorKind::InvalidInput);
        drop(tape);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
        let a = SettingAdmission::new(&used, crate::SettingChargeCounter::root_allocation_bytes() + (exact), &|| Ok(()));
        let mut tape = PackedTokenBlocks::new(&a).unwrap();
        tape.push(token, &a).unwrap();
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (exact));
        drop(tape);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }
}
