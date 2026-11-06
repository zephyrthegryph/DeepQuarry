use crate::{SettingAdmission, SettingRootLease, Span, SpanToken, TokenKind};
use std::{alloc::{alloc, Layout}, io, mem, ptr::NonNull};

const PAGE_ROWS: usize = 4096;
const WIDE_TAG: u64 = 15;
const MAX_WIDTH: usize = (1 << 28) - 1;

#[repr(transparent)]
struct PackedToken(u64);

impl PackedToken {
    fn common(token: SpanToken) -> Option<Self> {
        let start = u32::try_from(token.span.start).ok()?;
        let width = token.span.end.checked_sub(token.span.start)?;
        if width > MAX_WIDTH || start as usize > usize::MAX - width {
            return None;
        }
        let kind = match token.kind {
            TokenKind::Ident => 0, TokenKind::Number => 1, TokenKind::String => 2,
            TokenKind::Resource => 3, TokenKind::Interpolation => 4, TokenKind::Operator => 5,
            TokenKind::Punctuation => 6, TokenKind::Whitespace => 7, TokenKind::Newline => 8,
            TokenKind::Comment => 9, TokenKind::Unknown => 10,
        };
        Some(Self((u64::from(start) << 32) | ((width as u64) << 4) | kind))
    }

    fn wide(index: usize) -> io::Result<Self> {
        // A legal Vec<SpanToken> index is below isize::MAX / size_of::<SpanToken>(),
        // which fits the remaining 60 bits on both 64- and 32-bit hosts.
        let index = u64::try_from(index).ok().filter(|index| *index <= u64::MAX >> 4)
            .ok_or(io::ErrorKind::OutOfMemory)?;
        Ok(Self((index << 4) | WIDE_TAG))
    }

    fn decode(&self, wide: &[SpanToken]) -> SpanToken {
        let kind = match self.0 & 15 {
            0 => TokenKind::Ident, 1 => TokenKind::Number, 2 => TokenKind::String,
            3 => TokenKind::Resource, 4 => TokenKind::Interpolation, 5 => TokenKind::Operator,
            6 => TokenKind::Punctuation, 7 => TokenKind::Whitespace, 8 => TokenKind::Newline,
            9 => TokenKind::Comment, 10 => TokenKind::Unknown,
            WIDE_TAG => return wide[usize::try_from(self.0 >> 4).expect("issued wide token index")],
            _ => unreachable!("issued packed token kind"),
        };
        let start = (self.0 >> 32) as usize;
        let width = ((self.0 >> 4) & MAX_WIDTH as u64) as usize;
        SpanToken { kind, span: Span::new(start, start + width) }
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
    pages: Vec<Vec<PackedToken>>,
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
            self.pages.push(exact_vec(PAGE_ROWS, &mut self.credit, a)?);
        }
        let packed = match PackedToken::common(token) {
            Some(packed) => packed,
            None => {
                let packed = PackedToken::wide(self.wide.len())?;
                one_more(&mut self.wide, &mut self.credit, a)?;
                self.wide.push(token);
                packed
            }
        };
        self.pages.last_mut().expect("allocated packed token page").push(packed);
        self.len = len;
        Ok(())
    }

    pub(super) fn len(&self) -> usize {
        self.len
    }

    pub(super) fn get(&self, ordinal: usize) -> Option<SpanToken> {
        let row = self.pages.get(ordinal / PAGE_ROWS)?.get(ordinal % PAGE_ROWS)?;
        Some(row.decode(&self.wide))
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
        for page in &self.pages { rows(page, &mut visit); }
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
        assert_eq!(mem::size_of::<PackedToken>(), 8);
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
    fn packed_page_growth_fails_closed_one_byte_short_and_refunds_every_owner() {
        let used = Arc::new(AtomicUsize::new(0));
        let exact = 4 * mem::size_of::<Vec<PackedToken>>() + PAGE_ROWS * mem::size_of::<PackedToken>();
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
