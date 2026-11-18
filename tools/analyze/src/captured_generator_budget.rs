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
/// Opaque custody of already-transferred derived payload bytes. The owning
/// value drops its real payload/source credit BEFORE this field. A Weak binds
/// only the original budget; an ended scope cannot credit a later one.
#[derive(Debug)]
pub struct RetainedPayloadCharge{parent:std::sync::Weak<Budget>,bytes:usize}
impl RetainedPayloadCharge{
 /// Failed publication may leave an existing/escaped payload owner. Keep this
 /// failed operation's charge conservative; release only this Weak handle.
 pub fn keep_failed(mut self){self.bytes=0;}
}
impl Drop for RetainedPayloadCharge{
 fn drop(&mut self){if let Some(parent)=self.parent.upgrade(){
  parent.nested_retained.fetch_update(Ordering::AcqRel,Ordering::Acquire,|n|n.checked_sub(self.bytes)).expect("actual retained payload retires once");
  parent.used.fetch_update(Ordering::AcqRel,Ordering::Acquire,|n|n.checked_sub(self.bytes)).expect("retired payload was funded by its actual parent");
 }}
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
    /// Operation-local source scratch for shared policies and the native host. The caller must drop all scratch-owned values
    /// before the final Arc goes away; escaping graph facts are independently
    /// charged to the parent BEFORE copying. This grants no source authority.
    pub fn scoped_temporaries(parent: &Arc<Self>) -> Result<Arc<Self>, String> {
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
    pub(crate) fn is_root_or_direct_child(&self, root: &Arc<Self>) -> bool {
        std::ptr::eq(self, root.as_ref())
            || self.temporary_parent.as_ref().is_some_and(|parent|Arc::ptr_eq(parent,root))
    }

    /// An Err/panic may carry scratch-owned data beyond the source callback.
    /// Keep the conservative reservation for the rest of that failed operation.
    pub fn keep_failed_scratch(&self) {
        self.refund_temporaries.store(false, Ordering::Release);
    }
    #[track_caller]
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
        if let Err(used) = self.used.fetch_update(Ordering::AcqRel, Ordering::Acquire, |n| {
            n.checked_add(bytes).filter(|n| *n <= self.limit)
        }) {
            self.denied.store(true, Ordering::Release);
            let site = std::panic::Location::caller();
            return Err(format!(
                "captured generator allocation denied at {site} (used {used}, requested {bytes}, limit {})",
                self.limit
            ));
        }
        Ok(())
    }
    /// Nested derived values also live in the family's original retained charge.
    /// Exclude transferred bytes from the live TEMPORARY reservation before
    /// another child, while keeping them in used for this operation's limit.
    pub fn temporary_charge(&self)->usize{if let Some(parent)=&self.temporary_parent{return parent.temporary_charge()}self.used().saturating_sub(self.nested_retained.load(Ordering::Acquire))}
    pub fn retain_nested(&self,bytes:usize)->Result<(),String>{if let Some(parent)=&self.temporary_parent{return parent.retain_nested(bytes)}self.charge(bytes)?;self.nested_retained.fetch_add(bytes,Ordering::AcqRel);Ok(())}
    /// Validate the direct-child refund before its authenticated physical
    /// ledger changes. Own credit bytes remain live through this check.
    pub fn validate_scoped_refund(&self,bytes:usize)->Result<(),String>{
        let parent=self.temporary_parent.as_ref().ok_or("scratch refund requires its actual direct parent")?;
        let fixed=std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>();
        if self.used().checked_sub(bytes).is_none_or(|n|n<fixed)||parent.used()<bytes{return Err("scratch refund exceeds its own live payload".into())}Ok(())
    }
    /// Retire bytes from this exact direct scratch child after its physical
    /// source credit has shrunk. A root cannot manufacture a scratch refund.
    pub fn refund_scoped(&self,bytes:usize)->Result<(),String>{
        self.validate_scoped_refund(bytes)?;
        let parent=self.temporary_parent.as_ref().ok_or("scratch refund requires its actual direct parent")?;
        let fixed=std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>();
        self.used.fetch_update(Ordering::AcqRel,Ordering::Acquire,|n|n.checked_sub(bytes).filter(|n|*n>=fixed)).map_err(|_|"scratch refund exceeds its own live payload")?;
        if parent.used.fetch_update(Ordering::AcqRel,Ordering::Acquire,|n|n.checked_sub(bytes)).is_err(){self.used.fetch_add(bytes,Ordering::AcqRel);return Err("scratch parent refund invariant failed".into())}Ok(())
    }
    /// Transfer an already-funded retained payload to this child's exact
    /// parent. Parent used stays constant: there is no second allocation peak.
    pub fn transfer_scoped_retained(&self,parent:&Arc<Self>,bytes:usize)->Result<(),String>{
        if !self.temporary_parent.as_ref().is_some_and(|actual|Arc::ptr_eq(actual,parent)){return Err("retained transfer has a foreign scratch parent".into())}
        let fixed=std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>();
        self.used.fetch_update(Ordering::AcqRel,Ordering::Acquire,|n|n.checked_sub(bytes).filter(|n|*n>=fixed)).map_err(|_|"retained transfer exceeds this scratch payload")?;
        if parent.nested_retained.fetch_update(Ordering::AcqRel,Ordering::Acquire,|n|n.checked_add(bytes)).is_err(){self.used.fetch_add(bytes,Ordering::AcqRel);return Err("retained transfer overflow".into())}Ok(())
    }
    /// Same transfer, with exact value-owned retirement custody. Fixed wrapper
    /// metadata stays conservative when a Weak keeps an Arc control alive.
    pub fn transfer_scoped_retained_payload(&self,parent:&Arc<Self>,bytes:usize,payload:usize)->Result<RetainedPayloadCharge,String>{
        if payload>bytes{return Err("retired payload exceeds transferred retained bytes".into())}
        self.transfer_scoped_retained(parent,bytes)?;
        Ok(RetainedPayloadCharge{parent:Arc::downgrade(parent),bytes:payload})
    }
    pub fn denied(&self) -> bool {
        self.denied.load(Ordering::Acquire) || self.temporary_parent.as_ref().is_some_and(|parent|parent.denied())
    }
    /// Existing immutable operation cap, for proactive cache headroom policy.
    /// Reading it changes no reservation, authority or denial state.
    pub fn allocation_limit(&self)->usize{self.limit}
    pub fn remaining(&self)->usize{self.limit.saturating_sub(self.used())}
    pub fn used(&self) -> usize {
        self.used.load(Ordering::Acquire)
    }
    pub fn require(&self) -> Result<(), String> {
        // Positive reservations enforce the limit before mutating the count.
        // A checkpoint only observes the sticky denial, including its parent.
        if self.denied() {
            return Err("captured generator allocation denied".into());
        }
        Ok(())
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
    #[cfg(not(feature = "unified-oracle"))]
    pub(crate) fn row<T>(&self, rows: &mut Vec<T>) -> bool { self.row_inner(rows) }
    /// Frozen external oracle code only; ordinary builds retain crate visibility.
    #[cfg(feature = "unified-oracle")]
    pub fn row<T>(&self, rows: &mut Vec<T>) -> bool { self.row_inner(rows) }
    fn row_inner<T>(&self, rows: &mut Vec<T>) -> bool {
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

/// Operation-local preallocation window in the SAME existing Budget counter.
/// This is funding only, never a file/read/model/EOF or source-role receipt.
/// The owner must settle escaped physical backing before releasing its window.
pub struct ReservedWindow { budget: Arc<Budget>, bytes: usize, settled: bool, external_retained:usize, failed_loan:bool }
impl Budget {
    pub fn reserve_window(parent:&Arc<Self>,maximum:usize)->Result<ReservedWindow,String>{
        if parent.temporary_parent.is_some(){return Err("raw allocation window requires its actual operation budget".into())}
        parent.require()?;
        let bytes=parent.remaining().min(maximum);
        if bytes==0{return Err("raw allocation window has no remaining headroom".into())}
        parent.charge(bytes)?;
        Ok(ReservedWindow{budget:Arc::clone(parent),bytes,settled:false,external_retained:0,failed_loan:false})
    }
}
impl ReservedWindow {
    pub fn capacity(&self)->usize{self.bytes}
    /// Cleanup transaction: no cancellation checkpoint and no new allocation.
    /// Register the actual owner in its family's resource ledger FIRST. If a
    /// provider exceeded max_bytes, retain the whole original window and deny;
    /// the ledger still observes that real owner before this error escapes.
    pub fn settle(mut self,retained:usize)->Result<(),String>{
        self.settled=true;
        if self.failed_loan{return Err("failed prepaid loan keeps its genuine allocation window".into())}
        let retained=retained.checked_add(self.external_retained).ok_or_else(||{self.budget.deny();"prepaid retention overflow".to_owned()})?;
        if retained>self.bytes{self.budget.deny();return Err("raw provider exceeded its genuine reserved allocation window".into())}
        self.budget.used.fetch_sub(self.bytes-retained,Ordering::AcqRel);
        self.budget.nested_retained.fetch_add(self.external_retained,Ordering::AcqRel);
        Ok(())
    }
    /// Keep the original operation debit after successful settlement while
    /// identifying the already-registered external part. The caller must
    /// first publish that part's actual independently accounted owner.
    pub fn settle_registered(self, operation: &Arc<Budget>, retained: usize) -> Result<(), String> {
        if !Arc::ptr_eq(&self.budget, operation) {
            return self.settle(retained);
        }
        self.settle(retained)?;
        operation.nested_retained.fetch_add(retained, Ordering::AcqRel);
        Ok(())
    }
    /// An error with no allocated backing remaining may simply drop the window.
    /// If cleanup cannot prove the amount, keep the full admitted window instead.
    pub fn keep(mut self){self.settled=true;}
}
impl Drop for ReservedWindow {
    fn drop(&mut self){if !self.settled&&!self.failed_loan{self.budget.used.fetch_sub(self.bytes-self.external_retained,Ordering::AcqRel);self.budget.nested_retained.fetch_add(self.external_retained,Ordering::AcqRel);}}
}
#[cfg(test)]mod reserved_window_controls {
 use super::*;
 #[test]fn checkpoints_preserve_credit_and_observe_parent_denial(){
  let root=Budget::new(4096).unwrap();
  let child=Budget::scoped_temporaries(&root).unwrap();
  child.charge(256).unwrap();
  let funded=(root.used(),child.used());
  for _ in 0..1024{child.require().unwrap();root.require().unwrap();}
  assert_eq!((root.used(),child.used()),funded);
  assert!(root.charge(4096).is_err());
  assert!(child.require().is_err());
  assert!(root.require().is_err());
  assert_eq!((root.used(),child.used()),funded);
 }
 #[test]fn actual_operation_window_uses_remaining_counter_and_refunds_only_unused_credit(){
  let budget=Budget::new(4096).unwrap();let fixed=budget.used();budget.charge(800).unwrap();let before=budget.used();let window=Budget::reserve_window(&budget,64*1024*1024).unwrap();assert_eq!(window.capacity(),4096-before);assert_eq!(budget.remaining(),0);window.settle(300).unwrap();assert_eq!(budget.used(),before+300);let window=Budget::reserve_window(&budget,500).unwrap();assert_eq!(window.capacity(),500);drop(window);assert_eq!(budget.used(),before+300);assert_eq!(before,fixed+800);
 }
 #[test]fn exact_provider_excess_retains_admission_and_denies_without_hidden_refund(){
  let budget=Budget::new(2048).unwrap();let before=budget.used();let window=Budget::reserve_window(&budget,256).unwrap();assert!(window.settle(257).is_err());assert!(budget.denied());assert_eq!(budget.used(),before+256);let fresh=Budget::new(2048).unwrap();let before=fresh.used();Budget::reserve_window(&fresh,256).unwrap().keep();assert_eq!(fresh.used(),before+256);assert!(!fresh.denied());
 }
 #[test]fn window_refuses_nested_scratch_before_counter_mutation(){let parent=Budget::new(4096).unwrap();let child=Budget::scoped_temporaries(&parent).unwrap();let before=parent.used();assert!(Budget::reserve_window(&child,256).is_err());assert_eq!(parent.used(),before);}
}


#[cfg(test)]mod physical_phase_refund_controls{
 use super::*;
 #[test]fn actual_child_retirement_and_retained_transfer_never_double_charge_or_refund_root(){
  let parent=Budget::new(1024).unwrap();let fixed=parent.used();let child=Budget::scoped_temporaries(&parent).unwrap();
  child.charge(700).unwrap();let before=parent.used();child.refund_scoped(200).unwrap();assert_eq!(parent.used(),before-200);
  let before=parent.used();child.transfer_scoped_retained(&parent,500).unwrap();assert_eq!(parent.used(),before,"transfer retains the SAME already-funded payload");
  drop(child);assert_eq!(parent.used(),2*fixed+500);assert_eq!(parent.temporary_charge(),2*fixed);
  assert!(parent.refund_scoped(1).is_err());let child=Budget::scoped_temporaries(&parent).unwrap();let before=parent.used();
  assert!(child.refund_scoped(1).is_err());let other=Budget::new(1024).unwrap();assert!(child.transfer_scoped_retained(&other,1).is_err());assert_eq!(parent.used(),before);
 }
 #[test]fn failed_child_keeps_real_funded_scratch_and_excess_transfer_cannot_mutate_counts(){
  let parent=Budget::new(1024).unwrap();let child=Budget::scoped_temporaries(&parent).unwrap();child.charge(400).unwrap();let before=parent.used();
  assert!(child.transfer_scoped_retained(&parent,401).is_err());assert_eq!(parent.used(),before);child.keep_failed_scratch();drop(child);assert_eq!(parent.used(),before);
 }
}

/// An opaque synchronous allocation loan from the unused portion of ONE real
/// prepaid window. This subledger is bounded by that already-debited extent;
/// it cannot borrow another operation's allowance or escape the window.
pub struct ReservedWindowLoan<'a>{window:&'a mut ReservedWindow,budget:Option<Arc<Budget>>,held:usize,finished:bool}
impl ReservedWindow {
    pub fn loan_unused<'a>(&'a mut self,operation:&Arc<Budget>,held:usize)->Result<ReservedWindowLoan<'a>,String>{
        if !Arc::ptr_eq(&self.budget,operation)||self.settled||self.failed_loan{return Err("prepaid loan requires its actual live operation window".into())}
        let room=self.bytes.checked_sub(held).and_then(|n|n.checked_sub(self.external_retained)).ok_or("prepaid loan overlaps existing capture or escaped allocations")?;
        let budget=Budget::new(room)?;
        Ok(ReservedWindowLoan{window:self,budget:Some(budget),held,finished:false})
    }
}
impl ReservedWindowLoan<'_>{
    pub fn require_operation(&self,operation:&Arc<Budget>)->Result<(),String>{
        if !Arc::ptr_eq(&self.window.budget,operation)||self.finished||self.window.failed_loan{return Err("prepaid loan belongs to a different operation or is closed".into())}Ok(())
    }
    pub fn budget(&self)->&Arc<Budget>{self.budget.as_ref().expect("live prepaid allocation loan")}
    /// The included bytes will be counted by the enclosing capture's own exact
    /// retained census. Everything else remains escrowed by the SAME window:
    /// actual cached programs, Params, ledger/control allocations and existing
    /// conservative fixed scratch metadata. No such debit is refunded early.
    pub fn finish_included(mut self,included:usize)->Result<usize,String>{
        self.budget().require()?;
        // Cached payloads may hold Weak refund coordinates. Retire the last
        // strong owner ATOMICALLY before reading the final debit: a concurrent
        // Weak upgrade either prevents this unwrap, or can never succeed again.
        let mut budget=self.budget.take().expect("live prepaid allocation loan");
        // get_mut atomically proves BOTH strong and weak exclusivity. A sampled
        // weak_count alone is insufficient: a racing strong borrower could
        // create a Weak before releasing its last competing strong handle.
        let reclaim_metadata=Arc::get_mut(&mut budget).is_some();
        let budget=match Arc::try_unwrap(budget){Ok(budget)=>budget,Err(alias)=>{self.budget=Some(alias);return Err("prepaid allocation budget still has a live alias".into())}};
        budget.require()?;
        // Any surviving Weak keeps the allocation/control block physically
        // live. Conservatively escrow its ENTIRE originally funded metadata;
        // no late weak-drop can refund this window or a different scope.
        let own=if reclaim_metadata{std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>()}else{0};
        let external=budget.used().checked_sub(own).and_then(|n|n.checked_sub(included)).ok_or("included capture allocation exceeds prepaid loan")?;
        let total=self.window.external_retained.checked_add(external).ok_or("prepaid escaped retention overflow")?;
        if self.held.checked_add(total).is_none_or(|n|n>self.window.bytes){return Err("prepaid escaped allocations exceed actual window".into())}
        self.window.external_retained=total;self.finished=true;Ok(external)
    }
}
impl Drop for ReservedWindowLoan<'_>{fn drop(&mut self){if !self.finished{self.window.failed_loan=true;}}}

#[cfg(test)]mod prepaid_window_loan_controls{
 use super::*;
 #[test]fn actual_full_window_geometry_funds_one_shared_prefix_and_escaped_owner(){
  let parent=Budget::new(4_439_631).unwrap();let before=parent.used();let mut window=Budget::reserve_window(&parent,64*1024*1024).unwrap();assert_eq!(parent.remaining(),0);
  let loan=window.loan_unused(&parent,1_552_664).unwrap();let loan_fixed=loan.budget().used();loan.budget().charge(400_000).unwrap();
  let output=Budget::scoped_temporaries(loan.budget()).unwrap();output.charge(1024).unwrap();output.transfer_scoped_retained(loan.budget(),1024).unwrap();drop(output);
  let external=loan.finish_included(1024).unwrap();assert!(external>=400_000);assert_eq!(parent.remaining(),0,"no second debit or premature window refund");
  window.settle(1_552_664+1024).unwrap();assert_eq!(parent.used(),before+1_552_664+1024+external);assert!(loan_fixed>0);
 }
 #[test]fn foreign_parent_overlap_and_overspend_cannot_create_capacity(){
  let parent=Budget::new(4096).unwrap();let foreign=Budget::new(4096).unwrap();let mut window=Budget::reserve_window(&parent,2048).unwrap();let before=parent.used();
  assert!(window.loan_unused(&foreign,0).is_err());assert!(window.loan_unused(&parent,2049).is_err());assert_eq!(parent.used(),before);
  let loan=window.loan_unused(&parent,512).unwrap();assert!(loan.budget().charge(2048).is_err());drop(loan);assert!(window.settle(0).is_err());assert_eq!(parent.used(),before,"a failed loan cannot refund potentially escaped bytes");
 }
 #[test]fn live_budget_alias_failed_callback_and_unwind_keep_actual_window(){
  let parent=Budget::new(8192).unwrap();let mut window=Budget::reserve_window(&parent,2048).unwrap();let before=parent.used();let loan=window.loan_unused(&parent,0).unwrap();let alias=Arc::clone(loan.budget());assert!(loan.finish_included(0).is_err());drop(alias);drop(window);assert_eq!(parent.used(),before);
  let mut window=Budget::reserve_window(&parent,1024).unwrap();let before=parent.used();let failure=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{let loan=window.loan_unused(&parent,0).unwrap();loan.budget().charge(100).unwrap();panic!("actual interrupted loan");}));assert!(failure.is_err());drop(window);assert_eq!(parent.used(),before);
 }
 #[test]fn completed_loan_keeps_escaped_extent_even_when_window_is_dropped(){
  let parent=Budget::new(4096).unwrap();let before=parent.used();let mut window=Budget::reserve_window(&parent,2048).unwrap();let loan=window.loan_unused(&parent,0).unwrap();loan.budget().charge(256).unwrap();let external=loan.finish_included(0).unwrap();drop(window);assert_eq!(parent.used(),before+external);
 }
}

#[cfg(test)]mod prepaid_window_weak_alias_control{
 use super::*;
 #[test]fn weak_budget_alias_keeps_actual_arc_control_funded_until_cleanup(){
  let parent=Budget::new(4096).unwrap();let baseline=parent.used();let mut window=Budget::reserve_window(&parent,2048).unwrap();let before=parent.used();
  let loan=window.loan_unused(&parent,0).unwrap();loan.budget().charge(256).unwrap();let charged=loan.budget().used();let weak=Arc::downgrade(loan.budget());
  let external=loan.finish_included(0).unwrap();assert_eq!(external,charged,"the full metadata debit remains escrowed");assert!(weak.upgrade().is_none());assert_eq!(parent.used(),before);
  window.settle(0).unwrap();assert_eq!(parent.used(),baseline+charged);drop(weak);assert_eq!(parent.used(),baseline+charged,"late Weak cleanup never fabricates a refund");
 }
 #[test]fn concurrent_weak_upgrade_cannot_escape_atomic_prepaid_retirement(){
  for _ in 0..64{
   let parent=Budget::new(8192).unwrap();let baseline=parent.used();let mut window=Budget::reserve_window(&parent,4096).unwrap();let before=parent.used();let loan=window.loan_unused(&parent,0).unwrap();loan.budget().charge(256).unwrap();let charged=loan.budget().used();
   let weak=Arc::downgrade(loan.budget());let barrier=Arc::new(std::sync::Barrier::new(2));let worker_barrier=Arc::clone(&barrier);
   // The returned strong alias stays alive until the join result is inspected.
   let worker_weak=weak.clone();let worker=std::thread::spawn(move||{worker_barrier.wait();worker_weak.upgrade()});barrier.wait();let result=loan.finish_included(0);let upgraded=worker.join().unwrap();
   match result{Ok(external)=>{assert!(upgraded.is_none());assert_eq!(external,charged);window.settle(0).unwrap();assert_eq!(parent.used(),baseline+charged);},Err(_)=>{assert!(upgraded.is_some());assert!(window.settle(0).is_err());assert_eq!(parent.used(),before);}}
   drop(upgraded);assert!(weak.upgrade().is_none());drop(weak);
  }
 }
}

#[cfg(test)]mod retained_payload_charge_controls{
 use super::*;
 #[test]fn retained_payload_charge_requires_actual_parent_and_refunds_only_once_after_real_payload_drop(){
  let parent=Budget::new(1<<20).unwrap();let other=Budget::new(1<<20).unwrap();let child=Budget::scoped_temporaries(&parent).unwrap();child.charge(65536).unwrap();let payload=vec![3u8;65536];let before=parent.used();assert!(child.transfer_scoped_retained_payload(&other,65536,65536).is_err());assert_eq!(parent.used(),before);assert!(child.transfer_scoped_retained_payload(&parent,65536,65537).is_err());assert_eq!(parent.used(),before);
  let lease=child.transfer_scoped_retained_payload(&parent,65536,65536).unwrap();drop(child);assert_eq!(parent.used(),before);assert_eq!(payload[65535],3);drop(payload);drop(lease);assert_eq!(parent.used(),before-65536);assert!(!parent.denied());
 }
}

#[cfg(all(test,feature="native-policy"))]
mod sys_reactive_sibling_scan_scratch_controls {
 use super::*;
 #[test]
 fn actual_scanned_fixture_sibling_scratch_keeps_first_io_and_same_root_accounting() {
  let root=Budget::new(4096).unwrap();let fixed=root.used();
  let phase=Budget::scoped_temporaries(&root).unwrap();phase.charge(256).unwrap();
  let before=root.used();
  assert!(Budget::scoped_temporaries(&phase).is_err(),"the unsupported nested-scope rule stays strict");
  assert_eq!(root.used(),before);
  let scratch=Budget::scoped_temporaries(&root).unwrap();scratch.charge(128).unwrap();
  assert_eq!(root.used(),before+fixed+128,"both live sibling scopes debit ONE original root");
  let poll=||Err(std::io::Error::from_raw_os_error(1450));
  let fixture=crate::raw_fixture_policy::Fixture::native(&scratch,&poll);
  let failure=fixture.finish_scan().unwrap_err();
  assert!(matches!(failure,crate::derived_selftest_policy::Failure::Operational(ref error)if error.raw_os_error()==Some(1450)));
  drop(fixture);drop(scratch);
  assert_eq!(root.used(),before+fixed,"only scoped scratch payload retires; existing fixed metadata policy is unchanged");
  phase.require().unwrap();root.require().unwrap();
  drop(phase);assert_eq!(root.used(),3*fixed);
 }
 #[test]
 fn actual_sibling_scratch_cannot_multiply_root_capacity() {
  let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();
  let root=Budget::new(3*fixed+256+128).unwrap();
  let phase=Budget::scoped_temporaries(&root).unwrap();phase.charge(256).unwrap();
  let scratch=Budget::scoped_temporaries(&root).unwrap();scratch.charge(128).unwrap();
  assert_eq!(root.remaining(),0);let before=root.used();
  assert!(scratch.charge(1).is_err());assert_eq!(root.used(),before);
  assert!(root.denied()&&phase.denied()&&scratch.denied(),"same original cap and sticky denial apply to both siblings");
 }
}
