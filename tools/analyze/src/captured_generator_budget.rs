//! Operation-local captured generator admission, not a semantic cache/RSS metric.
//! Legacy row builders use no budget and keep their original behavior.
use std::sync::{
    atomic::{AtomicBool, AtomicUsize, Ordering},
    Arc,
};
pub const MAX_ROWS: usize = 10_000;
#[derive(Debug)]
pub struct Budget {
    limit: usize,
    temporary_parent: Option<Arc<Budget>>,
    refund_temporaries: AtomicBool,
    used: AtomicUsize,
    nested_retained: AtomicUsize,
    denied: AtomicBool,
}
impl Budget {
    pub fn new(limit: usize) -> Result<Arc<Self>, String> {
        let fixed = std::mem::size_of::<Self>() + 2 * std::mem::size_of::<usize>();
        if fixed > limit {
            return Err("captured generator budget metadata denied before allocation".into());
        }
        Ok(Arc::new(Self {
            limit,
            temporary_parent: None,
            refund_temporaries: AtomicBool::new(true),
            used: AtomicUsize::new(fixed),
            nested_retained: AtomicUsize::new(0),
            denied: AtomicBool::new(false),
        }))
    }
    /// Internal scratch only. The caller must drop all scratch-owned values
    /// before the final Arc goes away; escaping graph facts are independently
    /// charged to the parent BEFORE copying. This grants no source authority.
    pub(crate) fn scoped_temporaries(parent: &Arc<Self>) -> Result<Arc<Self>, String> {
        if parent.temporary_parent.is_some() {
            return Err("nested source scratch scopes are not supported".into());
        }
        let fixed = std::mem::size_of::<Self>() + 2 * std::mem::size_of::<usize>();
        parent.charge(fixed)?;
        Ok(Arc::new(Self {
            limit: parent.limit,
            temporary_parent: Some(Arc::clone(parent)),
            refund_temporaries: AtomicBool::new(true),
            used: AtomicUsize::new(fixed),
            nested_retained: AtomicUsize::new(0),
            denied: AtomicBool::new(false),
        }))
    }
    /// An Err/panic may carry scratch-owned data beyond the source callback.
    /// Keep the conservative reservation for the rest of that failed operation.
    pub(crate) fn keep_failed_scratch(&self) {
        self.refund_temporaries.store(false, Ordering::Release);
    }
    pub fn charge(&self, bytes: usize) -> Result<(), String> {
        if self.denied() {
            return Err("captured generator allocation denied".into());
        }
        if let Some(parent) = &self.temporary_parent {
            parent.charge(bytes)?;
            self.used.fetch_update(Ordering::AcqRel, Ordering::Acquire, |n| n.checked_add(bytes))
                .expect("funded scratch cannot exceed its live parent's bound");
            return Ok(());
        }
        if self
            .used
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |n| {
                n.checked_add(bytes).filter(|n| *n <= self.limit)
            })
            .is_err()
        {
            self.denied.store(true, Ordering::Release);
            return Err("captured generator allocation denied".into());
        }
        Ok(())
    }
    /// Nested derived values also live in the family's original retained charge.
    /// Exclude transferred bytes from the live TEMPORARY reservation before
    /// another child, while keeping them in used for this operation's limit.
    pub fn temporary_charge(&self)->usize{if let Some(parent)=&self.temporary_parent{return parent.temporary_charge()}self.used().saturating_sub(self.nested_retained.load(Ordering::Acquire))}
    pub fn retain_nested(&self,bytes:usize)->Result<(),String>{if let Some(parent)=&self.temporary_parent{return parent.retain_nested(bytes)}self.charge(bytes)?;self.nested_retained.fetch_add(bytes,Ordering::AcqRel);Ok(())}
    pub fn denied(&self) -> bool {
        self.denied.load(Ordering::Acquire) || self.temporary_parent.as_ref().is_some_and(|parent|parent.denied())
    }
    pub fn used(&self) -> usize {
        self.used.load(Ordering::Acquire)
    }
    pub fn require(&self) -> Result<(), String> {
        self.charge(0)
    }
    pub fn deny(&self) {
        self.denied.store(true, Ordering::Release);
        if let Some(parent)=&self.temporary_parent{parent.deny()}
    }
    pub(crate) fn string(&self, body: &mut String, text: &str) -> bool {
        if self.require().is_err() {
            return false;
        }
        let Some(need) = body.len().checked_add(text.len()) else {
            self.deny();
            return false;
        };
        if need > body.capacity() {
            let cap = need.max(body.capacity().saturating_mul(2)).max(64);
            if self.charge(cap.saturating_add(64)).is_err() {
                return false;
            }
            if body.try_reserve_exact(cap - body.len()).is_err() {
                self.deny();
                return false;
            }
        }
        body.push_str(text);
        true
    }
    pub(crate) fn append_fmt(&self, body: &mut String, args: std::fmt::Arguments<'_>) -> bool {
        struct Writer<'a> {
            budget: &'a Budget,
            text: &'a mut String,
        }
        impl std::fmt::Write for Writer<'_> {
            fn write_str(&mut self, s: &str) -> std::fmt::Result {
                if self.budget.string(self.text, s) {
                    Ok(())
                } else {
                    Err(std::fmt::Error)
                }
            }
        }
        let ok = std::fmt::write(
            &mut Writer {
                budget: self,
                text: body,
            },
            args,
        )
        .is_ok();
        if !ok {
            self.deny();
        }
        ok
    }
    /// Existing split_args may produce L+1 empty arguments. Its geometric
    /// Vec grows with old+new overlap up to3N String slots; content/cur/last
    /// temporaries need at most4L bytes. Reserve this BEFORE invoking it.
    pub(crate) fn split_args(&self, width: usize) -> Result<(), String> {
        let bytes = width
            .checked_add(1)
            .and_then(|n| n.checked_mul(3 * std::mem::size_of::<String>()))
            .and_then(|n| n.checked_add(width.checked_mul(4)?))
            .and_then(|n| n.checked_add(256))
            .ok_or("generator argument temporary overflow")?;
        self.charge(bytes)
    }
    pub(crate) fn row<T>(&self, rows: &mut Vec<T>) -> bool {
        if self.require().is_err() {
            return false;
        }
        if rows.len() == rows.capacity() {
            let cap = rows.capacity().saturating_mul(2).max(4);
            let Some(bytes) = cap
                .checked_mul(std::mem::size_of::<T>())
                .and_then(|n| n.checked_add(64))
            else {
                self.deny();
                return false;
            };
            if self.charge(bytes).is_err() {
                return false;
            }
            if rows.try_reserve_exact(cap - rows.len()).is_err() {
                self.deny();
                return false;
            }
        }
        true
    }
}
/// Captured final-file renderer. Every write checks the actual requested
/// String growth before reserving; no arbitrary closure or guessed header cap.
pub struct BudgetedText<'a> {
    budget: &'a Budget,
    text: String,
}
impl<'a> BudgetedText<'a> {
    pub fn new(budget: &'a Budget) -> Self {
        Self {
            budget,
            text: String::new(),
        }
    }
    pub fn finish(self) -> Result<String, String> {
        self.budget.require()?;
        Ok(self.text)
    }
}
impl std::fmt::Write for BudgetedText<'_> {
    fn write_str(&mut self, text: &str) -> std::fmt::Result {
        if self.budget.string(&mut self.text, text) {
            Ok(())
        } else {
            Err(std::fmt::Error)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn denied_output_cannot_become_empty_success() {
        assert!(Budget::new(0).is_err());
        let b = Budget::new(64).unwrap();
        let mut text = String::new();
        assert!(!b.string(&mut text, "x"));
        assert!(text.is_empty());
        assert!(b.require().is_err());
        assert!(BudgetedText::new(&b).finish().is_err());
    }
    #[test]
    fn actual_capacity_growth_is_admitted_before_retention() {
        let b = Budget::new(512).unwrap();
        let mut text = String::new();
        assert!(b.string(&mut text, "abc"));
        let old = text.clone();
        assert!(!b.string(&mut text, &"x".repeat(4096)));
        assert_eq!(text, old);
        assert!(b.used() >= text.capacity());
    }
}

#[cfg(test)]
mod writer_tests {
    use super::*;
    use std::fmt::Write;
    #[test]
    fn oversized_actual_chunk_is_denied_before_string_growth() {
        let b = Budget::new(256).unwrap();
        let mut text = BudgetedText::new(&b);
        assert!(text.write_str(&"x".repeat(4096)).is_err());
        assert_eq!(text.text.capacity(), 0);
        assert!(text.finish().is_err());
    }
}

#[cfg(test)]
mod splitter_tests {
    use super::*;
    #[test]
    fn empty_argument_vector_peak_is_reserved_before_existing_splitter() {
        let input = ",".repeat(4096);
        let small = Budget::new(128).unwrap();
        assert!(small.split_args(input.len()).is_err());
        let enough = Budget::new(1024 * 1024).unwrap();
        enough.split_args(input.len()).unwrap();
        let args = crate::raw_marker_policy::split_args(&input);
        assert_eq!(args.len(), input.len() + 1);
        assert!(
            enough.used()
                >= args.capacity() * std::mem::size_of::<String>()
                    + args.iter().map(String::capacity).sum::<usize>()
        );
    }
}

impl Drop for Budget {
    fn drop(&mut self) {
        if let Some(parent) = &self.temporary_parent {
            if !self.refund_temporaries.load(Ordering::Acquire) || std::thread::panicking() { return }
            // Keep fixed Arc/payload metadata conservatively charged: its
            // allocator/header lifetime is not certified by this destructor.
            let fixed = std::mem::size_of::<Self>() + 2 * std::mem::size_of::<usize>();
            let released = self.used().checked_sub(fixed).expect("scratch metadata was funded");
            parent.used.fetch_update(Ordering::AcqRel, Ordering::Acquire, |n| n.checked_sub(released))
                .expect("scratch release must correspond to actual parent reservations");
        }
    }
}
#[cfg(test)]
mod scoped_scratch_tests {
    use super::*;
    #[test]
    fn pages_share_live_graph_limit_and_only_dropped_scratch_is_credited() {
        let parent=Budget::new(4096).unwrap();let fixed=parent.used();
        parent.charge(700).unwrap();
        {
            let page=Budget::scoped_temporaries(&parent).unwrap();
            assert_eq!(parent.used(),fixed*2+700);
            let mut scratch=String::new();assert!(page.string(&mut scratch,"page-local name"));
            assert_eq!(page.temporary_charge(),parent.temporary_charge());
            parent.charge(211).unwrap(); // independently charged escaping graph fact
            page.retain_nested(128).unwrap();
            assert_eq!(page.temporary_charge(),parent.used()-128);
            drop(scratch);drop(page);
        }
        assert_eq!(parent.used(),fixed*2+700+211+128);
        assert_eq!(parent.temporary_charge(),fixed*2+700+211);
        let next=Budget::scoped_temporaries(&parent).unwrap();
        assert!(next.charge(4096).is_err());assert!(parent.denied());
    }
    #[test]
    fn scratch_failure_and_unwind_keep_reservations_for_escaping_error_payloads() {
        let parent=Budget::new(4096).unwrap();let fixed=parent.used();parent.charge(300).unwrap();
        let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{
            let page=Budget::scoped_temporaries(&parent).unwrap();
            let mut text=String::new();assert!(page.string(&mut text,"scratch"));
            parent.charge(77).unwrap();panic!("real scoped unwind");
        }));assert!(result.is_err());assert_eq!(parent.used(),fixed*2+300+77+128);
        assert!(!parent.denied());
        let page=Budget::scoped_temporaries(&parent).unwrap();page.charge(90).unwrap();page.keep_failed_scratch();drop(page);
        assert_eq!(parent.used(),fixed*3+300+77+128+90);
        let page=Budget::scoped_temporaries(&parent).unwrap();page.deny();drop(page);assert!(parent.denied());
    }
}
