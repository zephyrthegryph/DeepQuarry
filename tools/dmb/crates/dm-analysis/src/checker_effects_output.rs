//! Stack-local conservative execution admission, not retained semantic state.
//! Freed temporaries are deliberately never credited within one operation.
use super::*;
use std::{
    cell::Cell,
    fmt::{self, Write},
};
struct AdmissionControl{denied:std::sync::atomic::AtomicBool,external:std::sync::atomic::AtomicUsize}
#[derive(Clone)]
pub struct ExecutionAdmission{control:Arc<AdmissionControl>,limit:usize,external_base:usize}
impl Default for ExecutionAdmission{fn default()->Self{Self::with_limit(RESULT_BUDGET)}}
impl ExecutionAdmission{
 pub fn with_limit(bytes:usize)->Self{Self{control:Arc::new(AdmissionControl{denied:std::sync::atomic::AtomicBool::new(false),external:std::sync::atomic::AtomicUsize::new(0)}),limit:bytes.min(RESULT_BUDGET),external_base:0}}
 pub fn is_denied(&self)->bool{self.control.denied.load(Ordering::Relaxed)}
 fn deny(&self){self.control.denied.store(true,Ordering::Relaxed)}
 fn external_delta(&self)->usize{self.control.external.load(Ordering::Acquire).saturating_sub(self.external_base)}
 /// This view's remaining external allowance. Actual body loans receive a
 /// view ALREADY restricted by their live parent/visitor scratch budget.
 pub fn available(&self)->usize{self.limit.saturating_sub(self.external_delta())}
 pub(crate) fn current_view(&self)->Self{self.view_with_usage(self.limit,0)}
 fn view_with_usage(&self,limit:usize,used:usize)->Self{let external=self.control.external.load(Ordering::Acquire);Self{control:Arc::clone(&self.control),limit:limit.saturating_sub(used).saturating_sub(external.saturating_sub(self.external_base)),external_base:external}}
 pub(super) fn restricted(&self,bytes:usize)->Self{let mut view=self.current_view();view.limit=view.limit.min(bytes);view}
 pub(crate) fn same_control(&self,other:&Self)->bool{Arc::ptr_eq(&self.control,&other.control)}
 /// Monotone metadata reservation in this SAME operation admission. It never
 /// credits moved/freed payloads or creates another budget/cap/counter domain.
 /// Call before growing external ledger metadata, with a CURRENT scratch view.
 pub fn reserve_external(&self,bytes:usize)->std::io::Result<()>{
  if self.is_denied(){return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect shared operation already denied"))}
  let result=self.control.external.fetch_update(Ordering::AcqRel,Ordering::Acquire,|old|old.checked_add(bytes).filter(|next|next.saturating_sub(self.external_base)<=self.limit));
  if result.is_err(){self.deny();return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect external metadata and live scratch admission exhausted"))}
  if self.is_denied(){return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect shared operation already denied"))}Ok(())
 }
}
pub(crate) struct ReportBudget {
    used: Cell<usize>,
    limit: usize,
    denied: Cell<bool>,
    admission: ExecutionAdmission,
}
impl Default for ReportBudget {
    fn default() -> Self {
        Self::new(RESULT_BUDGET)
    }
}
impl ReportBudget {
    pub(crate) fn for_operation(admission: &ExecutionAdmission) -> Self {
        Self {
            used: Cell::new(0),
            limit: admission.limit,
            denied: Cell::new(admission.is_denied()),
            admission: admission.clone(),
        }
    }
    pub(super) fn used(&self)->usize{self.used.get()}
    pub(super) fn remaining(&self)->usize{self.limit.saturating_sub(self.used.get()).saturating_sub(self.admission.external_delta())}
    pub(crate) fn admission_view(&self)->ExecutionAdmission{self.admission.view_with_usage(self.limit,self.used.get())}
    pub(crate) fn deny(&self) {
        self.denied.set(true);
        self.admission.deny()
    }

    fn new(limit: usize) -> Self {
        Self {
            used: Cell::new(0),
            limit,
            denied: Cell::new(false),
            admission: ExecutionAdmission::default(),
        }
    }
    pub(crate) fn charge(&self, bytes: usize) -> Result<(), String> {
        if self.denied.get() || self.admission.is_denied() {
            return Err("effect transient execution admission exhausted".into());
        }
        let n = self
            .used
            .get()
            .checked_add(bytes)
            .filter(|n| n.checked_add(self.admission.external_delta()).is_some_and(|total|total<=self.limit));
        if let Some(n) = n {
            self.used.set(n);
            Ok(())
        } else {
            self.deny();
            Err("effect transient execution admission exhausted".into())
        }
    }
    pub(crate) fn format(&self, args: fmt::Arguments<'_>) -> Result<String, String> {
        struct Count {
            len: usize,
            limit: usize,
        }
        impl Write for Count {
            fn write_str(&mut self, s: &str) -> fmt::Result {
                self.len = self
                    .len
                    .checked_add(s.len())
                    .filter(|n| *n <= self.limit)
                    .ok_or(fmt::Error)?;
                Ok(())
            }
        }
        let remaining = self
            .limit
            .saturating_sub(self.used.get())
            .saturating_sub(64);
        let mut count = Count {
            len: 0,
            limit: remaining,
        };
        if fmt::write(&mut count, args).is_err() {
            self.deny();
            return Err("effect transient formatting admission exhausted".into());
        }
        self.charge(count.len.saturating_add(64))?;
        let mut s = String::new();
        s.try_reserve_exact(count.len).map_err(|_| {
            self.deny();
            "effect transient text allocation refused"
        })?;
        fmt::write(&mut s, args).map_err(|_| {
            self.deny();
            "effect transient text formatting failed"
        })?;
        if s.len() != count.len {
            self.deny();
            return Err("effect formatting changed between admission and execution".into());
        }
        Ok(s)
    }
    pub(crate) fn reserve_slot<T>(&self, v: &mut Vec<T>) -> Result<(), String> {
        if v.len() == v.capacity() {
            let cap = v.capacity().checked_mul(2).unwrap_or(usize::MAX).max(4);
            self.charge(
                cap.checked_mul(std::mem::size_of::<T>())
                    .and_then(|n| n.checked_add(64))
                    .ok_or("effect vector size overflow")?,
            )?;
            v.try_reserve_exact(cap.saturating_sub(v.len()))
                .map_err(|_| {
                    self.deny();
                    "effect transient vector allocation refused"
                })?;
        }
        Ok(())
    }
    pub(crate) fn push<T>(&self, v: &mut Vec<T>, value: T) -> Result<(), String> {
        self.reserve_slot(v)?;
        v.push(value);
        Ok(())
    }
    pub(crate) fn queue<T>(&self, v: &mut VecDeque<T>, value: T) -> Result<(), String> {
        if v.len() == v.capacity() {
            let cap = v.capacity().checked_mul(2).unwrap_or(usize::MAX).max(4);
            self.charge(
                cap.checked_mul(std::mem::size_of::<T>())
                    .and_then(|n| n.checked_add(64))
                    .ok_or("effect queue size overflow")?,
            )?;
            v.try_reserve_exact(cap.saturating_sub(v.len()))
                .map_err(|_| {
                    self.deny();
                    "effect transient queue allocation refused"
                })?;
        }
        v.push_back(value);
        Ok(())
    }
    pub(crate) fn insert<T: Ord>(&self, set: &mut BTreeSet<T>, value: T) -> Result<bool, String> {
        // Current Rust BTree node layout is private. This conservative bound
        // covers the fixed scalar EffectTarget/usize tuples admitted here.
        self.charge(1024usize.saturating_add(std::mem::size_of::<T>()))?;
        Ok(set.insert(value))
    }
    pub(crate) fn path(&self, path: &[CallEdge], edge: &CallEdge) -> Result<Vec<CallEdge>, String> {
        let len = path
            .len()
            .checked_add(1)
            .filter(|n| *n <= MAX_EVENTS)
            .ok_or("effect call path exceeds admission")?;
        self.charge(
            len.checked_mul(std::mem::size_of::<CallEdge>())
                .and_then(|n| n.checked_add(64))
                .ok_or("effect path size overflow")?,
        )?;
        let mut next = Vec::new();
        next.try_reserve_exact(len).map_err(|_| {
            self.deny();
            "effect path allocation refused"
        })?;
        next.extend_from_slice(path);
        next.push(edge.clone());
        Ok(next)
    }
    pub(crate) fn annotation(&self, note: &Note) -> Result<Vec<Note>, String> {
        let message = self.format(format_args!("{}", note.message))?;
        let mut notes = Vec::new();
        self.push(
            &mut notes,
            Note {
                message,
                source: note.source.clone(),
            },
        )?;
        Ok(notes)
    }
    pub(crate) fn diagnostic(&self, row: &Diagnostic) -> Result<Diagnostic, String> {
        let message = self.format(format_args!("{}", row.message))?;
        let mut notes = Vec::new();
        for n in &row.notes {
            self.push(
                &mut notes,
                Note {
                    message: self.format(format_args!("{}", n.message))?,
                    source: n.source.clone(),
                },
            )?
        }
        Ok(Diagnostic {
            family: row.family,
            severity: row.severity,
            span: row.span,
            expression_span: row.expression_span,
            message,
            notes,
        })
    }
}
pub(crate) fn initial_queue(
    calls: &[CallEdge],
    budget: &ReportBudget,
) -> Result<VecDeque<(EffectTarget, Vec<CallEdge>)>, String> {
    let mut queue = VecDeque::new();
    for edge in calls {
        budget.queue(&mut queue, (edge.callee, budget.path(&[], edge)?))?
    }
    Ok(queue)
}
/// Conservative source/event bound established BEFORE plan/SCC allocations.
/// It covers simultaneous edge clones, private BTree nodes and all scalar
/// traversal stacks. No source text, type table, or second graph is retained.
pub(crate) fn plan_admission(
    input: &EffectInput,
    bodies: &[Arc<BodyEffects>],
    admission: &ExecutionAdmission,
) -> Result<(), String> {
    let catalog = dm_tree::checker_builtins::pinned_catalog()
        .map_err(|_| "effect graph original builtin catalog unavailable")?;
    if catalog.profile != input.profile {
        return Err("effect graph builtin profile differs".into());
    }
    let builtin_rows = catalog.declarations.len();
    let n = bodies.len();
    let calls = bodies
        .iter()
        .try_fold(0usize, |n, b| n.checked_add(b.calls.len()))
        .ok_or("effect graph size overflow")?;
    let impure = bodies.iter().filter(|b| !b.direct.is_empty()).count();
    let edges = impure
        .checked_mul(n)
        .and_then(|x| x.checked_add(calls))
        .ok_or("effect graph size overflow")?;
    let bound = edges
        .checked_mul(2048)
        .and_then(|x| {
            n.checked_add(builtin_rows)
                .and_then(|n| n.checked_mul(4096))
                .and_then(|n| x.checked_add(n))
        })
        .ok_or("effect graph size overflow")?;
    let bound = bodies
        .iter()
        .try_fold(bound, |n, b| n.checked_add(b.charge()))
        .ok_or("effect graph size overflow")?;
    if bound > admission.limit {
        admission.deny();
        return Err("effect transient graph/SCC admission exhausted before construction".into());
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn formatted_text_is_counted_before_owned_allocation_and_denial_is_sticky() {
        let budget = ReportBudget::new(70);
        let text = "0123456789";
        assert!(budget.format(format_args!("{text}")).is_err());
        assert_eq!(budget.used.get(), 0);
        assert!(budget.format(format_args!("a")).is_err());
    }
    #[test]
    fn vectors_pre_admit_full_replacement_overlap_not_only_length() {
        let budget = ReportBudget::new(100);
        let mut v = Vec::<usize>::new();
        budget.push(&mut v, 1).unwrap();
        assert!(budget.used.get() >= 4 * std::mem::size_of::<usize>() + 64);
        for n in 2..=4 {
            budget.push(&mut v, n).unwrap()
        }
        assert!(budget.push(&mut v, 5).is_err());
        assert_eq!(v.len(), 4);
    }
    #[test]
    fn identical_small_messages_keep_exact_bytes_and_order() {
        let budget = ReportBudget::default();
        let mut rows = Vec::new();
        for n in 0..3 {
            budget
                .push(
                    &mut rows,
                    budget.format(format_args!("message {n}")).unwrap(),
                )
                .unwrap()
        }
        assert_eq!(rows, ["message 0", "message 1", "message 2"]);
    }
}

#[cfg(test)]mod external_metadata_tests{use super::*;
 #[test]fn metadata_delta_uses_current_nested_scratch_and_is_not_double_counted_in_children(){
  let admission=ExecutionAdmission::with_limit(1024);let page=ReportBudget::for_operation(&admission);page.charge(700).unwrap();let child=page.admission_view();let body=ReportBudget::for_operation(&child);body.charge(250).unwrap();let live=body.admission_view();assert_eq!(live.available(),74);assert!(live.reserve_external(75).is_err());assert!(admission.is_denied());
  let fresh=ExecutionAdmission::with_limit(1024);let page=ReportBudget::for_operation(&fresh);page.charge(700).unwrap();let child=page.admission_view();let body=ReportBudget::for_operation(&child);body.charge(250).unwrap();body.admission_view().reserve_external(64).unwrap();assert_eq!(body.remaining(),10);assert_eq!(page.remaining(),260);drop(body);let nested=page.admission_view();let next=ReportBudget::for_operation(&nested);next.charge(260).unwrap();assert_eq!(next.remaining(),0,"already excluded metadata must not be charged twice");
 }
}
