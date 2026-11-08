//! Exact borrowed token DATA from an independent retained physical owner.
use super::{packed_token_blocks::{one_more, poll}, PackedTokenBlocks};
use crate::{SettingAdmission, SettingRootLease, SpanToken};
use std::{io, mem};

pub const ORIGINAL_TOKEN_PAGE_ROWS: usize = 4096;

/// Read-only DATA. Implementations must keep the same geometry/owner for
/// every advertised row. The real producer authenticates its own source,
/// delivery, epoch and owner before providing a loan to the primary.
pub trait OriginalTokenPageData: Send + Sync + std::any::Any {
    fn get(&self, ordinal: usize) -> Option<SpanToken>;
    fn visit_storage(&self, visit: &mut dyn FnMut(usize, usize, usize));
}

pub struct OriginalTokenPageLoan {
    owner: Box<dyn OriginalTokenPageData>,
    credit: SettingRootLease,
}
impl OriginalTokenPageLoan {
    pub fn new<T: OriginalTokenPageData + 'static>(owner: T, a: &SettingAdmission<'_>) -> io::Result<Self> {
        let credit = a.reserve(mem::size_of::<T>()).map_err(|e| a.take_operational_error().unwrap_or(e))?;
        Ok(Self { owner: Box::new(owner), credit })
    }

    fn visit_storage(&self, visit: &mut dyn FnMut(usize, usize, usize), skip: &mut dyn FnMut(&dyn std::any::Any) -> bool) {
        let bytes = mem::size_of_val(self.owner.as_ref());
        if bytes != 0 { visit(self.owner.as_ref() as *const _ as *const () as usize, bytes, bytes); }
        if !skip(self.owner.as_ref()) { self.owner.visit_storage(visit); }
    }
}

pub(crate) struct LoanedTokenPages {
    pages: Vec<OriginalTokenPageLoan>,
    // Only the current incomplete physical page needs ordinary storage.
    tail: Option<PackedTokenBlocks>,
    adopted: usize,
    directory: SettingRootLease,
}

impl LoanedTokenPages {
    pub(crate) fn new(a: &SettingAdmission<'_>) -> io::Result<Self> {
        let directory = a.reserve(0).map_err(|e| a.take_operational_error().unwrap_or(e))?;
        Ok(Self { pages: Vec::new(), tail: None, adopted: 0, directory })
    }

    pub(crate) fn admitted_by(&self, a: &SettingAdmission<'_>) -> bool {
        a.matches_lease_domain(&self.directory)
    }

    pub(crate) fn len(&self) -> usize { self.adopted }

    pub(crate) fn get(&self, ordinal: usize) -> Option<SpanToken> {
        if ordinal >= self.adopted { return None; }
        let page = ordinal / ORIGINAL_TOKEN_PAGE_ROWS;
        let local = ordinal % ORIGINAL_TOKEN_PAGE_ROWS;
        match self.pages.get(page) {
            Some(loan) => loan.owner.get(local),
            None if page == self.pages.len() => self.tail.as_ref()?.get(local),
            None => None,
        }
    }

    pub(crate) fn stage(
        &mut self, first: usize, loan: OriginalTokenPageLoan, a: &SettingAdmission<'_>,
    ) -> io::Result<()> {
        poll(a)?;
        let next = self.pages.len().checked_mul(ORIGINAL_TOKEN_PAGE_ROWS).ok_or(io::ErrorKind::OutOfMemory)?;
        let retained = self.adopted.checked_sub(next).ok_or(io::ErrorKind::InvalidInput)?;
        if !self.admitted_by(a) || !a.matches_lease_domain(&loan.credit)
            || first != next || retained >= ORIGINAL_TOKEN_PAGE_ROWS
            || self.tail.as_ref().map_or(0, PackedTokenBlocks::len) != retained
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "foreign or misaligned original token page"));
        }
        if let Some(tail) = &self.tail {
            for (local, token) in tail.window().iter().enumerate() {
                if local % 64 == 0 { poll(a)?; }
                if loan.owner.get(local) != Some(token) {
                    return Err(io::Error::new(io::ErrorKind::InvalidData, "original page differs from adopted local prefix"));
                }
            }
        }
        one_more(&mut self.pages, &mut self.directory, a)?;
        self.pages.push(loan);
        self.tail = None;
        Ok(())
    }

    pub(crate) fn push(&mut self, token: SpanToken, a: &SettingAdmission<'_>) -> io::Result<()> {
        let count = self.adopted.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
        let page = self.adopted / ORIGINAL_TOKEN_PAGE_ROWS;
        let local = self.adopted % ORIGINAL_TOKEN_PAGE_ROWS;
        if let Some(loan) = self.pages.get(page) {
            // Keep the live demand checkpoint and compare the actual
            // transport tuple before the grammar can see this ordinal.
            poll(a)?;
            if !self.admitted_by(a) || loan.owner.get(local) != Some(token) {
                return Err(io::Error::new(io::ErrorKind::InvalidData, "original page differs from actual adopted token"));
            }
        } else {
            if !self.admitted_by(a) || page != self.pages.len() {
                return Err(io::Error::new(io::ErrorKind::InvalidInput, "original token tail exceeds one physical page"));
            }
            if self.tail.is_none() { self.tail = Some(PackedTokenBlocks::new(a)?); }
            self.tail.as_mut().expect("current token tail").push(token, a)?;
        }
        self.adopted = count;
        Ok(())
    }

    pub(crate) fn retain_adopted_prefix(&mut self, a: &SettingAdmission<'_>) -> io::Result<()> {
        if !self.admitted_by(a) { return Err(io::ErrorKind::InvalidInput.into()); }
        let whole = self.adopted / ORIGINAL_TOKEN_PAGE_ROWS;
        let retained = self.adopted % ORIGINAL_TOKEN_PAGE_ROWS;
        if self.pages.len() == whole { return Ok(()); }
        if self.pages.len() != whole + 1 || self.tail.is_some() {
            return Err(io::ErrorKind::InvalidData.into());
        }
        // Never retain unread cells by aliasing the last physical page. Only
        // the already adopted prefix (bounded to one page) is copied here.
        if retained != 0 {
            let last = self.pages.last().expect("issued partial token loan");
            let mut tail = PackedTokenBlocks::new(a)?;
            for local in 0..retained {
                tail.push(last.owner.get(local).ok_or(io::ErrorKind::InvalidData)?, a)?;
            }
            self.tail = Some(tail);
        }
        self.pages.pop();
        Ok(())
    }

    pub(crate) fn try_visit_backing_owners(
        &self,
        visit: &mut dyn FnMut(&dyn std::any::Any) -> io::Result<()>,
    ) -> io::Result<()> {
        for page in &self.pages {
            visit(page.owner.as_ref())?;
        }
        Ok(())
    }

    pub(crate) fn visit_storage(&self, visit: &mut dyn FnMut(usize, usize, usize), skip: &mut dyn FnMut(&dyn std::any::Any) -> bool) {
        let width = mem::size_of::<OriginalTokenPageLoan>();
        if self.pages.capacity() != 0 {
            visit(self.pages.as_ptr() as usize, self.pages.len() * width, self.pages.capacity() * width);
        }
        for page in &self.pages { page.visit_storage(visit, skip); }
        if let Some(tail) = &self.tail { tail.visit_storage(visit); }
    }

    #[cfg(debug_assertions)]
    pub(crate) fn trace_retention(&self) -> impl std::fmt::Debug + '_ {
        struct Tape<'a>(&'a LoanedTokenPages);
        impl std::fmt::Debug for Tape<'_> {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.debug_struct("PrimaryLoanedTokenTape")
                    .field("rows", &self.0.adopted)
                    .field("loaned_pages", &self.0.pages.len())
                    .field("directory_bytes", &self.0.directory.bytes())
                    .field("tail_rows", &self.0.tail.as_ref().map_or(0, PackedTokenBlocks::len))
                    .finish()
            }
        }
        Tape(self)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{SharedSpanTokens, Span, TokenKind, TokenWindow};
    use std::sync::{Arc, atomic::{AtomicUsize, Ordering}};

    fn row(at: usize) -> SpanToken {
        SpanToken { kind: TokenKind::Ident, span: Span::new(2 * at, 2 * at + 1) }
    }

    struct Page { first: usize, releases: Arc<AtomicUsize> }
    impl Drop for Page {
        fn drop(&mut self) { self.releases.fetch_add(1, Ordering::AcqRel); }
    }
    impl OriginalTokenPageData for Page {
        fn get(&self, ordinal: usize) -> Option<SpanToken> {
            (ordinal < ORIGINAL_TOKEN_PAGE_ROWS).then(|| row(self.first + ordinal))
        }
        fn visit_storage(&self, _: &mut dyn FnMut(usize, usize, usize)) {}
    }

    #[test]
    fn loans_only_expose_adopted_ordinals_and_release_unread_final_page() {
        let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let releases = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut tape = LoanedTokenPages::new(&a).unwrap();
        let make = |first| OriginalTokenPageLoan::new(Page { first, releases: releases.clone() }, &a).unwrap();
        tape.push(row(0), &a).unwrap(); // existing adopted prefix in bounded local tail
        let wrong = tape.stage(0, make(1), &a).unwrap_err();
        assert_eq!(wrong.kind(), io::ErrorKind::InvalidData);
        assert_eq!(tape.get(0), Some(row(0)));
        assert_eq!(releases.load(Ordering::Acquire), 1);
        tape.stage(0, make(0), &a).unwrap();
        assert_eq!(tape.get(1), None, "staged data cannot advance the actual parser");
        for index in 1..ORIGINAL_TOKEN_PAGE_ROWS { tape.push(row(index), &a).unwrap(); }
        tape.stage(ORIGINAL_TOKEN_PAGE_ROWS, make(ORIGINAL_TOKEN_PAGE_ROWS), &a).unwrap();
        tape.push(row(ORIGINAL_TOKEN_PAGE_ROWS), &a).unwrap();
        assert!(TokenWindow::from_loaned(&tape).iter().eq((0..=ORIGINAL_TOKEN_PAGE_ROWS).map(row)));
        let tokens = SharedSpanTokens::from_loaned_using(tape, &a).unwrap();
        assert_eq!(releases.load(Ordering::Acquire), 2, "partial seal drops the unread physical loan");
        assert_eq!(tokens.window().last(), Some(row(ORIGINAL_TOKEN_PAGE_ROWS)));
        let alias = tokens.clone();
        drop(tokens);
        assert_eq!(releases.load(Ordering::Acquire), 2);
        assert_eq!(alias.window().get(0), Some(row(0)));
        drop(alias);
        assert_eq!(releases.load(Ordering::Acquire), 3);
        assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }
}
