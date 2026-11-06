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

struct TokenPage {
    rows: Vec<PackedToken>,
    start_base: usize,
    wide_base: usize,
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

    fn decode(&self, page: &TokenPage, wide: &[SpanToken]) -> SpanToken {
        let kind = match self.0 & 15 {
            0 => TokenKind::Ident, 1 => TokenKind::Number, 2 => TokenKind::String,
            3 => TokenKind::Resource, 4 => TokenKind::Interpolation, 5 => TokenKind::Operator,
            6 => TokenKind::Punctuation, 7 => TokenKind::Whitespace, 8 => TokenKind::Newline,
            9 => TokenKind::Comment, 10 => TokenKind::Unknown,
            WIDE_TAG => return wide[page.wide_base.checked_add((self.0 >> KIND_BITS) as usize)
                .expect("issued wide token index")],
            _ => unreachable!("issued packed token kind"),
        };
        let start = page.start_base.checked_add((self.0 >> START_SHIFT) as usize)
            .expect("issued packed token start");
        let width = ((self.0 >> KIND_BITS) & MAX_WIDTH as u32) as usize;
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
    // Global allocation with the exact layout Vec uses. No element is initialized
    // yet. Retain the reservation until the caller drops this Vec or fails closed.
    let ptr = NonNull::new(unsafe { alloc(layout) }).ok_or(io::ErrorKind::OutOfMemory)?;
    Ok(unsafe { Vec::from_raw_parts(ptr.as_ptr().cast::<T>(), 0, capacity) })
}

fn one_more<T>(rows: &mut Vec<T>, credit: &mut SettingRootLease, a: &SettingAdmission<'_>) -> io::Result<()> {
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
            one_more(&mut self.pages, &mut self.credit, a)?;
            self.pages.push(TokenPage {
                rows: exact_vec(PAGE_ROWS, &mut self.credit, a)?,
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
        page.rows.push(packed);
        self.len = len;
        Ok(())
    }

    pub(super) fn len(&self) -> usize {
        self.len
    }

    pub(super) fn get(&self, ordinal: usize) -> Option<SpanToken> {
        let page = self.pages.get(ordinal / PAGE_ROWS)?;
        let row = page.rows.get(ordinal % PAGE_ROWS)?;
        Some(row.decode(page, &self.wide))
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
        for page in &self.pages { rows(&page.rows, &mut visit); }
        rows(&self.wide, &mut visit);
        self.credit.visit_counter_storage(|address, bytes| {
            let bytes = bytes + 2 * mem::size_of::<usize>();
            visit(address, bytes, bytes);
        });
    }

    pub(crate) fn window(&self) -> super::TokenWindow<'_> {
        super::TokenWindow::from_packed(self)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, atomic::{AtomicUsize, Ordering}};

    #[test]
    fn packed_windows_preserve_page_boundaries_and_wide_actual_values() {
        assert_eq!(mem::size_of::<PackedToken>(), 4);
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut tape = PackedTokenBlocks::new(&a).unwrap();
        for at in 0..PAGE_ROWS + 3 {
            tape.push(SpanToken { kind: TokenKind::Ident, span: Span::new(at * 2, at * 2 + 1) }, &a).unwrap();
        }
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
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn page_local_token_bits_preserve_zero_endpoints_and_every_full_width_escape() {
        let used = Arc::new(AtomicUsize::new(0));
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
        assert_eq!(tape.pages[0].rows[0].0, 0);
        assert_eq!(tape.pages[0].rows[1].0, WIDE_TAG);
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
        assert_eq!(tape.pages[1].rows[0].0, WIDE_TAG);
        assert_eq!(tape.pages[1].wide_base, 4);
        assert_eq!(tape.get(PAGE_ROWS), Some(first));
        assert_eq!(tape.get(PAGE_ROWS + 1), Some(token(TokenKind::Punctuation, 0, 1)));
        assert_eq!(tape.get(PAGE_ROWS + 2), None);
        drop(tape);
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn packed_page_growth_fails_closed_one_byte_short_and_refunds_every_owner() {
        let used = Arc::new(AtomicUsize::new(0));
        let exact = 4 * mem::size_of::<TokenPage>() + PAGE_ROWS * mem::size_of::<PackedToken>();
        let a = SettingAdmission::new(&used, exact - 1, &|| Ok(()));
        let mut tape = PackedTokenBlocks::new(&a).unwrap();
        let token = SpanToken { kind: TokenKind::Punctuation, span: Span::new(0, 1) };
        assert_eq!(tape.push(token, &a).unwrap_err().kind(), io::ErrorKind::OutOfMemory);
        assert!(tape.window().is_empty());
        assert_eq!(tape.push(token, &a).unwrap_err().kind(), io::ErrorKind::InvalidInput);
        drop(tape);
        assert_eq!(used.load(Ordering::Acquire), 0);
        let a = SettingAdmission::new(&used, exact, &|| Ok(()));
        let mut tape = PackedTokenBlocks::new(&a).unwrap();
        tape.push(token, &a).unwrap();
        assert_eq!(used.load(Ordering::Acquire), exact);
        drop(tape);
        assert_eq!(used.load(Ordering::Acquire), 0);
    }
}
