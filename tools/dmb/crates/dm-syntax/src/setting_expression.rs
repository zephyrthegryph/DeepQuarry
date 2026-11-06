//! Shared setting syntax storage; ORIGINAL source authority is a separate owner receipt.
//! No raw Arc/Weak is exposed, so allocation credit follows every live alias.
use crate::Expr;
use std::{
    fmt,
    ops::Deref,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    },
};
/// Storage reservation only, never source/model authority. The native host must
/// issue it from its existing syntax budget before parsing or publication.
pub struct SettingRootLease {
    counter: Arc<AtomicUsize>,
    bytes: usize,
}
impl SettingRootLease {
    pub fn reserve(
        counter: &Arc<AtomicUsize>,
        limit: usize,
        bytes: usize,
    ) -> Result<Self, &'static str> {
        counter
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |used| {
                used.checked_add(bytes).filter(|next| *next <= limit)
            })
            .map_err(|_| "setting root retained syntax admission denied")?;
        Ok(Self {
            counter: Arc::clone(counter),
            bytes,
        })
    }
    pub fn bytes(&self) -> usize {
        self.bytes
    }
    pub fn visit_counter_storage(&self, mut visit: impl FnMut(usize, usize)) {
        visit(
            Arc::as_ptr(&self.counter) as usize,
            std::mem::size_of::<AtomicUsize>(),
        );
    }
}
impl Drop for SettingRootLease {
    fn drop(&mut self) {
        let old = self.counter.fetch_sub(self.bytes, Ordering::AcqRel);
        debug_assert!(old >= self.bytes);
    }
}

/// STACK operation-local admission. This capability controls storage only,
/// never source authority. No gate/query/reset is performed at a parser leaf.
pub struct SettingAdmission<'op> {
    counter: &'op Arc<AtomicUsize>,
    limit: usize,
    checkpoint: &'op dyn Fn() -> std::io::Result<()>,
    failure: std::cell::RefCell<Option<std::io::Error>>,
    stopped: std::cell::Cell<Option<std::io::ErrorKind>>,
    stack_used: std::cell::Cell<usize>,
    stack_allowance: usize,
}
impl<'op> SettingAdmission<'op> {
    /// Resource-domain equality only; no source/model grant.
    pub fn uses_counter(&self,expected:&Arc<AtomicUsize>)->bool{Arc::ptr_eq(self.counter,expected)}

    pub fn new(
        counter: &'op Arc<AtomicUsize>,
        limit: usize,
        checkpoint: &'op dyn Fn() -> std::io::Result<()>,
    ) -> Self {
        Self::with_stack_allowance(counter, limit, 256 * 1024, checkpoint)
    }
    /// Native host supplies a conservative part of its EXISTING compiler-worker
    /// stack allocation. This is an operation resource allowance, never a DM
    /// nesting/syntax classification or a claim about standalone parsing.
    pub fn with_stack_allowance(
        counter: &'op Arc<AtomicUsize>,
        limit: usize,
        stack_allowance: usize,
        checkpoint: &'op dyn Fn() -> std::io::Result<()>,
    ) -> Self {
        Self {
            counter,
            limit,
            checkpoint,
            failure: std::cell::RefCell::new(None),
            stopped: std::cell::Cell::new(None),
            stack_used: std::cell::Cell::new(0),
            stack_allowance,
        }
    }
    /// One evaluator recursion frame on the SAME operation stack/counter.
    /// This is a resource capability only; it grants no source or scalar meaning.
    pub fn evaluation_frame(&self) -> std::io::Result<SettingEvaluationFrame<'_, 'op>> {
        let pending=self.parser_frame().map(|frame|SettingEvaluationFrame{_frame:frame});
        if let Some(actual)=self.take_operational_error(){return Err(actual)}
        pending
    }
    pub(crate) fn parser_frame(&self) -> std::io::Result<SettingParserFrame<'_, 'op>> {
        self.checkpoint()?;
        // Conservative coordination envelope for one primary recursive frame;
        // not an exact compiler stack-frame/RSS measurement. Both the host's
        // supplied stack allowance AND its same shared syntax counter admit it.
        const FRAME_BYTES: usize = 16 * 1024;
        let Some(next) = self
            .stack_used
            .get()
            .checked_add(FRAME_BYTES)
            .filter(|next| *next <= self.stack_allowance)
        else {
            self.record_operational_error(std::io::Error::new(
                std::io::ErrorKind::OutOfMemory,
                "setting parser stack-work allowance exhausted",
            ));
            return Err(std::io::ErrorKind::OutOfMemory.into());
        };
        let lease = self.reserve(FRAME_BYTES)?;
        self.stack_used.set(next);
        Ok(SettingParserFrame {
            admission: self,
            bytes: FRAME_BYTES,
            _lease: lease,
        })
    }
    pub(crate) fn admit_drop_depth(&self, depth: usize) -> std::io::Result<()> {
        self.checkpoint()?;
        let admitted = depth
            .checked_mul(16 * 1024)
            .and_then(|bytes| bytes.checked_add(self.stack_used.get()))
            .is_some_and(|bytes| bytes <= self.stack_allowance);
        if !admitted {
            self.record_operational_error(std::io::Error::new(
                std::io::ErrorKind::OutOfMemory,
                "setting AST cleanup stack-work allowance exhausted",
            ));
            return Err(std::io::ErrorKind::OutOfMemory.into());
        }
        Ok(())
    }
    pub fn record_operational_error(&self, error: std::io::Error) {
        if self.stopped.get().is_none() {
            self.stopped.set(Some(error.kind()));
            *self.failure.borrow_mut() = Some(error);
        }
    }
    pub fn take_operational_error(&self) -> Option<std::io::Error> {
        self.failure.borrow_mut().take()
    }
    pub fn is_stopped(&self) -> bool {
        self.stopped.get().is_some()
    }
    pub fn checkpoint(&self) -> std::io::Result<()> {
        if let Some(kind) = self.stopped.get() {
            return Err(kind.into());
        }
        match (self.checkpoint)() {
            Ok(()) => Ok(()),
            Err(error) => {
                let kind = error.kind();
                self.record_operational_error(error);
                Err(kind.into())
            }
        }
    }
    #[track_caller]
    pub fn reserve(&self, bytes: usize) -> std::io::Result<SettingRootLease> {
        self.checkpoint()?;
        match SettingRootLease::reserve(self.counter, self.limit, bytes) {
            Ok(lease) => Ok(lease),
            Err(message) => {
                let caller = std::panic::Location::caller();
                let retained = self.counter.load(Ordering::Acquire);
                self.record_operational_error(std::io::Error::new(
                    std::io::ErrorKind::OutOfMemory,
                    format!("{message} at {caller}: {bytes} requested, {retained} retained, {} limit", self.limit),
                ));
                Err(std::io::ErrorKind::OutOfMemory.into())
            }
        }
    }
    /// Grow ONE owner-lived metadata lease before allocating another slot.
    /// No intermediate Arc/control block or forgotten lease may survive merge.
    #[track_caller]
    pub fn grow(&self, lease: &mut SettingRootLease, bytes: usize) -> std::io::Result<()> {
        self.checkpoint()?;
        if !self.matches_lease_domain(lease) {
            self.record_operational_error(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "setting storage belongs to a foreign body budget",
            ));
            return Err(std::io::ErrorKind::InvalidInput.into());
        }
        let Some(total) = lease.bytes.checked_add(bytes) else {
            self.record_operational_error(std::io::Error::new(
                std::io::ErrorKind::OutOfMemory,
                "setting owner metadata capacity overflow",
            ));
            return Err(std::io::ErrorKind::OutOfMemory.into());
        };
        let mut additional = self.reserve(bytes)?;
        lease.bytes = total;
        // Transfer reserved bytes, then drop its counter Arc normally. Forgetting
        // the temporary would incorrectly retain a counter allocation forever.
        additional.bytes = 0;
        drop(additional);
        Ok(())
    }
    /// Release storage only after its unique native owner has actually dropped
    /// that allocation. This transfers no source/model/cache authority. A caller
    /// cannot shrink another admission domain or credit more than it owns.
    pub fn shrink(&self,lease:&mut SettingRootLease,bytes:usize)->std::io::Result<()>{
        self.checkpoint()?;
        if !self.matches_lease_domain(lease){let actual=std::io::Error::new(std::io::ErrorKind::InvalidInput,"setting release belongs to a foreign body budget");self.record_operational_error(actual);return Err(std::io::ErrorKind::InvalidInput.into())}
        let Some(remaining)=lease.bytes.checked_sub(bytes)else{let actual=std::io::Error::new(std::io::ErrorKind::InvalidInput,"setting owner release exceeds owned storage");self.record_operational_error(actual);return Err(std::io::ErrorKind::InvalidInput.into())};
        if lease.counter.fetch_update(Ordering::AcqRel,Ordering::Acquire,|used|used.checked_sub(bytes)).is_err(){let actual=std::io::Error::new(std::io::ErrorKind::InvalidData,"setting resource counter is below owned release");self.record_operational_error(actual);return Err(std::io::ErrorKind::InvalidData.into())}
        lease.bytes=remaining;Ok(())
    }
    /// Transfer already-funded allocation ownership within this SAME native
    /// resource root. No counter credit is created/released and no source,
    /// syntax, completion or model authority is transferred. On every failure
    /// both leases stay unchanged so both live payloads remain fully funded.
    pub fn absorb(&self,target:&mut SettingRootLease,source:&mut SettingRootLease)->std::io::Result<()>{
        if let Err(status)=self.checkpoint(){return Err(self.take_operational_error().unwrap_or(status))}
        let refuse=|kind,text:&'static str|{let actual=std::io::Error::new(kind,text);self.record_operational_error(actual);self.take_operational_error().unwrap_or_else(||kind.into())};
        if !self.matches_lease_domain(target)||!self.matches_lease_domain(source){return Err(refuse(std::io::ErrorKind::InvalidInput,"macro allocation credit belongs to a foreign native resource root"))}
        let total=target.bytes.checked_add(source.bytes).ok_or_else(||refuse(std::io::ErrorKind::OutOfMemory,"macro allocation ownership transfer overflow"))?;
        let held=self.counter.load(Ordering::Acquire);if held<total{return Err(refuse(std::io::ErrorKind::InvalidData,"native resource counter is below transferred allocation ownership"))}if held>self.limit{return Err(refuse(std::io::ErrorKind::OutOfMemory,"native allocation ownership exceeds this unchanged admission limit"))}
        target.bytes=total;source.bytes=0;Ok(())
    }
    /// Split actual same-counter storage ownership, without reserving/refunding
    /// any bytes or transferring syntax/source authority. Both the parent and
    /// counter stay unchanged on first IO, foreign domain, size or limit failure.
    pub fn split(&self,parent:&mut SettingRootLease,bytes:usize)->std::io::Result<SettingRootLease>{
        if let Err(status)=self.checkpoint(){return Err(self.take_operational_error().unwrap_or(status))}
        let refuse=|kind,message|{self.record_operational_error(std::io::Error::new(kind,message));self.take_operational_error().unwrap_or_else(||kind.into())};
        if !self.matches_lease_domain(parent){return Err(refuse(std::io::ErrorKind::InvalidInput,"split allocation belongs to a foreign native resource root"))}
        let remaining=parent.bytes.checked_sub(bytes).ok_or_else(||refuse(std::io::ErrorKind::InvalidInput,"split exceeds actual retained storage ownership"))?;
        let held=self.counter.load(Ordering::Acquire);
        if held<parent.bytes{return Err(refuse(std::io::ErrorKind::InvalidData,"native resource counter is below actual split ownership"))}
        if held>self.limit{return Err(refuse(std::io::ErrorKind::OutOfMemory,"split ownership exceeds this unchanged admission limit"))}
        let child=SettingRootLease{counter:Arc::clone(&parent.counter),bytes};parent.bytes=remaining;Ok(child)
    }
    pub fn matches_lease_domain(&self, lease: &SettingRootLease) -> bool {
        Arc::ptr_eq(self.counter, &lease.counter)
    }
}
/// Opaque evaluator work guard. Dropping it restores only this held frame's
/// stack and body-work reservation; no allowance resets across scalar roots.
pub struct SettingEvaluationFrame<'a,'op> { _frame: SettingParserFrame<'a,'op> }
pub(crate) struct SettingParserFrame<'a, 'op> {
    admission: &'a SettingAdmission<'op>,
    bytes: usize,
    _lease: SettingRootLease,
}
impl Drop for SettingParserFrame<'_, '_> {
    fn drop(&mut self) {
        self.admission
            .stack_used
            .set(self.admission.stack_used.get() - self.bytes);
    }
}
struct Retention {
    lease: SettingRootLease,
}
/// No-Weak storage-only anchor. Shared literal owners may outlive their root
/// handle; every original alias retains this SAME quota lease, with no source,
/// Expr, request, QueryDb or semantic model retained by the anchor.
pub struct SharedSettingRetention {
    owner: Option<Arc<Retention>>,
}
impl SharedSettingRetention {
    pub fn new(lease: SettingRootLease) -> Self {
        Self {
            owner: Some(Arc::new(Retention { lease })),
        }
    }
    fn payload(&self) -> &Retention {
        self.owner
            .as_deref()
            .expect("live setting retention anchor")
    }
    pub fn bytes(&self) -> usize {
        self.payload().lease.bytes()
    }
    pub fn same_owner(&self, other: &Self) -> bool {
        Arc::ptr_eq(self.owner.as_ref().unwrap(), other.owner.as_ref().unwrap())
    }
    pub fn is_admitted_by(&self, admission: &SettingAdmission<'_>) -> bool {
        admission.matches_lease_domain(&self.payload().lease)
    }
    /// Payload addresses only; caller inventories its conservative Arc header
    /// envelope separately. No Arc alias/Weak or source authority escapes.
    pub fn visit_storage(&self, mut visit: impl FnMut(usize, usize)) {
        visit(
            Arc::as_ptr(self.owner.as_ref().unwrap()) as usize,
            std::mem::size_of::<Retention>(),
        );
        visit(
            Arc::as_ptr(&self.payload().lease.counter) as usize,
            std::mem::size_of::<AtomicUsize>(),
        );
    }
}
impl Clone for SharedSettingRetention {
    fn clone(&self) -> Self {
        Self {
            owner: self.owner.as_ref().map(Arc::clone),
        }
    }
}
impl Drop for SharedSettingRetention {
    fn drop(&mut self) {
        // All aliases use into_inner; the anchor allocation/control block is
        // gone before its lease releases credit. Literal owners use the same
        // discipline before dropping their last anchor field.
        if let Some(owner) = self.owner.take() {
            if let Some(payload) = Arc::into_inner(owner) {
                drop(payload);
            }
        }
    }
}
impl fmt::Debug for SharedSettingRetention {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SharedSettingRetention")
            .field("bytes", &self.bytes())
            .finish_non_exhaustive()
    }
}
pub(crate) fn root_storage_envelope() -> usize {
    // Explicit bounded runtime std-Arc body-work policy, NOT a qualified source
    // allocation role or an assertion about allocator/RSS overhead.
    std::mem::size_of::<Root>()
        + std::mem::size_of::<Retention>()
        + 4 * std::mem::size_of::<usize>()
}
struct Root {
    expression: Expr,
    // LAST: original child allocations/anchors drop before this root alias.
    retention: Option<SharedSettingRetention>,
}
impl Drop for Root {
    fn drop(&mut self) {
        let expression = std::mem::replace(
            &mut self.expression,
            Expr {
                kind: crate::ExprKind::Ident(String::new()),
                span: crate::Span::new(0, 0),
            },
        );
        crate::setting_drop::drop_expression(expression, self.retention.take());
    }
}
/// Sealed no-Weak root handle. Equality/debug inspect syntax only; neither is an
/// original-source proof. Native consumers still require their exact site receipt.
pub struct SettingExpression {
    root: Option<Arc<Root>>,
    // Source projection only. The canonical Expr remains in ORIGINAL chunk coordinates.
    current_offset: usize,
    source_extent: usize,
}
impl SettingExpression {
    pub(crate) fn compatibility(expression: Expr) -> Self {
        let source_extent=expression.span.end;
        Self {
            root: Some(Arc::new(Root {
                expression,
                retention: None,
            })),
            current_offset: 0,
            source_extent,
        }
    }
    pub(crate) fn retained_with_anchor(
        expression: Expr,
        retention: SharedSettingRetention,
    ) -> Self {
        let source_extent=expression.span.end;
        Self {
            root: Some(Arc::new(Root {
                expression,
                retention: Some(retention),
            })),
            current_offset: 0,
            source_extent,
        }
    }
    #[cfg(test)]
    fn retained(expression: Expr, lease: SettingRootLease) -> Self {
        // Storage-only fixture helper; native producer must attach this SAME
        // anchor to original literal owners before root publication.
        Self::retained_with_anchor(expression, SharedSettingRetention::new(lease))
    }
    fn payload(&self) -> &Root {
        self.root.as_deref().expect("live setting syntax root")
    }
    /// Borrow ORIGINAL grammar syntax. Native clients must project locations with
    /// current_span_of; this method never copies/shifts the retained AST.
    pub fn original_expression(&self) -> &Expr {
        &self.payload().expression
    }
    pub fn current_projection(&self)->crate::SyntaxProjection{crate::SyntaxProjection::new(crate::Span::new(0,self.source_extent),crate::Span::new(self.current_offset,self.current_offset+self.source_extent)).expect("private checked root projection")}
    pub fn current_offset(&self) -> usize {
        self.current_offset
    }
    /// The owning current-source receipt proves every original root span is
    /// inside source_extent. This storage-only scalar check grants no authority.
    pub fn project_current(mut self, offset: usize, source_extent: usize) -> std::io::Result<Self> {
        offset.checked_add(source_extent).ok_or_else(|| {
            std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "setting source projection overflow",
            )
        })?;
        if self.payload().expression.span.end > source_extent {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "setting root exceeds original source extent",
            ));
        }
        self.current_offset = offset;
        self.source_extent = source_extent;
        Ok(self)
    }
    pub fn current_span_of(&self, expression: &Expr) -> Option<crate::Span> {
        self.current_projection().span(expression.span)
    }
    pub fn current_span(&self) -> crate::Span {
        self.current_span_of(self.original_expression())
            .expect("checked current root projection")
    }
    pub fn retained_charge(&self) -> Option<usize> {
        self.payload()
            .retention
            .as_ref()
            .map(SharedSettingRetention::bytes)
    }
    /// Storage-domain check only. Exact current source/body/metadata authority
    /// must already be established by the declaration owner before slot lookup.
    pub fn is_retained_in(&self, admission: &SettingAdmission<'_>) -> bool {
        self.payload()
            .retention
            .as_ref()
            .is_some_and(|owner| owner.is_admitted_by(admission))
    }
    /// Actual stable allocation identity plus payload bytes; the caller's census
    /// records the standard Arc control-block envelope separately, without an
    /// Arc reference escaping this sealed type.
    pub fn visit_root_storage(&self, mut visit: impl FnMut(usize, usize)) {
        visit(
            Arc::as_ptr(self.root.as_ref().unwrap()) as usize,
            std::mem::size_of::<Root>(),
        );
    }
    /// Borrow retained quota-counter storage for the existing address census.
    /// This reveals no Arc alias and is never a budget/source authority token.
    pub fn visit_retention_storage(&self, mut visit: impl FnMut(usize, usize)) {
        if let Some(owner) = &self.payload().retention {
            owner.visit_storage(&mut visit);
        }
    }
    pub fn same_root(&self, other: &Self) -> bool {
        Arc::ptr_eq(self.root.as_ref().unwrap(), other.root.as_ref().unwrap())
    }
}
impl Deref for SettingExpression {
    type Target = Expr;
    fn deref(&self) -> &Expr {
        &self.payload().expression
    }
}
impl Clone for SettingExpression {
    fn clone(&self) -> Self {
        Self {
            root: self.root.as_ref().map(Arc::clone),
            current_offset: self.current_offset,
            source_extent: self.source_extent,
        }
    }
}
impl Drop for SettingExpression {
    fn drop(&mut self) {
        // All aliases use into_inner and Weak cannot be created. The winner
        // obtains the payload only AFTER its Arc allocation/control block has
        // been released, then drops child AST storage and finally the lease.
        if let Some(root) = self.root.take() {
            if let Some(payload) = Arc::into_inner(root) {
                drop(payload);
            }
        }
    }
}
impl fmt::Debug for SettingExpression {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.deref().fmt(f)
    }
}
impl PartialEq for SettingExpression {
    fn eq(&self, other: &Self) -> bool {
        self.deref() == other.deref()
    }
}
impl Eq for SettingExpression {}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn operation_admission_preserves_first_error_and_cannot_restart_after_take() {
        let counter = Arc::new(AtomicUsize::new(37));
        let calls = std::cell::Cell::new(0);
        let checkpoint = || {
            calls.set(calls.get() + 1);
            Err(std::io::Error::new(
                std::io::ErrorKind::Interrupted,
                "actual first checkpoint",
            ))
        };
        let admission = SettingAdmission::new(&counter, 4096, &checkpoint);
        assert_eq!(
            admission.checkpoint().unwrap_err().kind(),
            std::io::ErrorKind::Interrupted
        );
        admission
            .record_operational_error(std::io::Error::other("later error must not replace first"));
        let actual = admission.take_operational_error().unwrap();
        assert_eq!(actual.kind(), std::io::ErrorKind::Interrupted);
        assert_eq!(actual.to_string(), "actual first checkpoint");
        assert!(admission.is_stopped());
        assert!(admission.reserve(16).is_err());
        assert_eq!(calls.get(), 1);
        assert!(admission.take_operational_error().is_none());
        assert_eq!(
            counter.load(Ordering::Acquire),
            37,
            "operation cannot reset shared body credit"
        );
    }
    #[test]
    fn metadata_lease_growth_is_atomic_same_domain_and_has_no_temporary_arc_leak() {
        let counter = Arc::new(AtomicUsize::new(0));
        let checkpoint = || Ok(());
        let admission = SettingAdmission::new(&counter, 100, &checkpoint);
        let mut lease = admission.reserve(40).unwrap();
        admission.grow(&mut lease, 30).unwrap();
        assert_eq!(lease.bytes(), 70);
        assert_eq!(counter.load(Ordering::Acquire), 70);
        assert_eq!(Arc::strong_count(&counter), 2);
        assert!(admission.grow(&mut lease, 31).is_err());
        assert_eq!(lease.bytes(), 70);
        assert_eq!(counter.load(Ordering::Acquire), 70);
        drop(lease);
        assert_eq!(counter.load(Ordering::Acquire), 0);
        assert_eq!(Arc::strong_count(&counter), 1);

        let other = Arc::new(AtomicUsize::new(0));
        let foreign_admission = SettingAdmission::new(&other, 100, &checkpoint);
        let mut foreign = foreign_admission.reserve(12).unwrap();
        let fresh = SettingAdmission::new(&counter, 100, &checkpoint);
        assert!(fresh.grow(&mut foreign, 1).is_err());
        assert_eq!(other.load(Ordering::Acquire), 12);
        assert_eq!(counter.load(Ordering::Acquire), 0);
    }
    #[test]
    fn setting_root_credit_remains_until_all_statement_aliases_release() {
        let counter = Arc::new(AtomicUsize::new(0));
        let lease = SettingRootLease::reserve(&counter, 4096, 1024).unwrap();
        let root =
            SettingExpression::retained(crate::parse_expression("list(1,2)").expr.unwrap(), lease);
        let second = root.clone();
        let third = second.clone();
        assert!(root.same_root(&third));
        drop(root);
        drop(second);
        assert_eq!(counter.load(Ordering::Acquire), 1024);
        drop(third);
        assert_eq!(counter.load(Ordering::Acquire), 0);
    }
    #[test]
    fn equal_counter_values_and_compatibility_roots_never_prove_native_storage_domain() {
        let own = Arc::new(AtomicUsize::new(0));
        let foreign = Arc::new(AtomicUsize::new(0));
        let checkpoint = || Ok(());
        let own_admission = SettingAdmission::new(&own, 4096, &checkpoint);
        let foreign_admission = SettingAdmission::new(&foreign, 4096, &checkpoint);
        let root = SettingExpression::retained(
            crate::parse_expression("1").expr.unwrap(),
            own_admission.reserve(64).unwrap(),
        );
        foreign.store(64, Ordering::Release);
        assert!(root.is_retained_in(&own_admission));
        assert!(!root.is_retained_in(&foreign_admission));
        let compatibility =
            SettingExpression::compatibility(crate::parse_expression("1").expr.unwrap());
        assert!(!compatibility.is_retained_in(&own_admission));
    }
    #[test]
    fn setting_root_reservation_denial_cannot_consume_or_reset_existing_credit() {
        let counter = Arc::new(AtomicUsize::new(0));
        let lease = SettingRootLease::reserve(&counter, 1024, 1000).unwrap();
        assert!(SettingRootLease::reserve(&counter, 1024, 25).is_err());
        assert_eq!(counter.load(Ordering::Acquire), 1000);
        drop(lease);
        assert_eq!(counter.load(Ordering::Acquire), 0);
    }
}

/// Storage-only bridge for the existing host census. It cannot attach owners or
/// expose a raw Arc; a surviving literal alias retains its original lease.
pub fn visit_setting_literal_retention(text: &crate::LiteralText, visit: impl FnMut(usize, usize)) {
    text.visit_setting_retention_storage(visit);
}

#[cfg(test)]
mod evaluation_frame_tests {
    use super::*;
    #[test]
    fn evaluation_frames_share_operation_stack_and_physical_counter_release_without_reset() {
        let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());
        let a=SettingAdmission::with_stack_allowance(&counter,1024*1024,32*1024,&poll);
        let first=a.evaluation_frame().unwrap();let second=a.evaluation_frame().unwrap();
        assert_eq!(counter.load(Ordering::Acquire),32*1024);
        let actual=a.evaluation_frame().err().expect("no fresh allowance for a transitive root");assert_eq!(actual.kind(),std::io::ErrorKind::OutOfMemory);
        drop(first);assert_eq!(counter.load(Ordering::Acquire),16*1024);drop(second);assert_eq!(counter.load(Ordering::Acquire),0);
        let fresh=SettingAdmission::with_stack_allowance(&counter,1024*1024,32*1024,&poll);let frame=fresh.evaluation_frame().unwrap();drop(frame);assert_eq!(counter.load(Ordering::Acquire),0);
    }
    #[test]
    fn evaluation_frame_restores_actual_operational_cause_before_any_work() {
        let counter=Arc::new(AtomicUsize::new(0));let poll=||Err(std::io::Error::from_raw_os_error(1450));
        let a=SettingAdmission::new(&counter,1024*1024,&poll);let actual=a.evaluation_frame().err().unwrap();assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),0);
    }
}

#[cfg(test)]mod root_projection_storage_tests{use super::*;
 #[test]fn current_projection_borrows_same_original_root_and_retention_without_reparse_or_copy(){let counter=Arc::new(AtomicUsize::new(0));let lease=SettingRootLease::reserve(&counter,8192,1024).unwrap();let expression=crate::parse_expression("list(1,2)").expr.unwrap();let extent=expression.span.end;let root=SettingExpression::retained(expression,lease);let current=root.clone().project_current(200,extent).unwrap();assert!(root.same_root(&current));assert!(std::ptr::eq(root.original_expression(),current.original_expression()));assert_eq!(current.current_projection().original(),crate::Span::new(0,extent));assert_eq!(current.current_projection().current(),crate::Span::new(200,200+extent));assert_eq!(current.current_span(),crate::Span::new(200,200+extent));assert_eq!(counter.load(Ordering::Acquire),1024);drop(root);assert_eq!(counter.load(Ordering::Acquire),1024);drop(current);assert_eq!(counter.load(Ordering::Acquire),0);}
}

#[cfg(test)]mod native_owner_storage_release_tests{
 use super::*;
 #[test]fn existing_admission_releases_only_the_unique_owners_real_storage(){
  let counter=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&counter,4096,&||Ok(()));let mut first=a.reserve(100).unwrap();let second=a.reserve(250).unwrap();a.shrink(&mut first,75).unwrap();assert_eq!(first.bytes(),25);assert_eq!(counter.load(Ordering::Acquire),275);drop(second);assert_eq!(counter.load(Ordering::Acquire),25);drop(first);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn owner_release_refuses_foreign_domain_underflow_and_first_operational_failure(){
  let counter=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&counter,4096,&||Ok(()));let mut lease=a.reserve(100).unwrap();assert_eq!(a.shrink(&mut lease,101).err().unwrap().kind(),std::io::ErrorKind::InvalidInput);assert_eq!(lease.bytes(),100);assert_eq!(counter.load(Ordering::Acquire),100);a.take_operational_error().unwrap();
  let foreign=Arc::new(AtomicUsize::new(0));let b=SettingAdmission::new(&foreign,4096,&||Ok(()));assert_eq!(b.shrink(&mut lease,10).err().unwrap().kind(),std::io::ErrorKind::InvalidInput);assert_eq!(lease.bytes(),100);assert_eq!(foreign.load(Ordering::Acquire),0);b.take_operational_error().unwrap();
  let fault=||Err(std::io::Error::from_raw_os_error(1450));let c=SettingAdmission::new(&counter,4096,&fault);let status=c.shrink(&mut lease,10).err().unwrap();assert_eq!(status.kind(),std::io::Error::from_raw_os_error(1450).kind());let actual=c.take_operational_error().unwrap();assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(lease.bytes(),100);assert_eq!(counter.load(Ordering::Acquire),100);drop(lease);assert_eq!(counter.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod allocation_absorb_tests{
 use super::*;
 #[test]fn actual_same_root_absorb_preserves_counter_until_final_output_owner_drops(){let counter=Arc::new(AtomicUsize::new(0));let healthy=||Ok(());let a=SettingAdmission::new(&counter,4096,&healthy);let mut text=a.reserve(400).unwrap();let mut points=a.reserve(600).unwrap();a.absorb(&mut text,&mut points).unwrap();assert_eq!(text.bytes(),1000);assert_eq!(points.bytes(),0);assert_eq!(counter.load(Ordering::Acquire),1000);drop(points);assert_eq!(counter.load(Ordering::Acquire),1000);drop(a);assert_eq!(counter.load(Ordering::Acquire),1000,"actual output can outlive the temporary operation");drop(text);assert_eq!(counter.load(Ordering::Acquire),0);}
 #[test]fn absorb_foreign_limit_and_first_real_io_leave_both_payload_credits_unchanged(){let counter=Arc::new(AtomicUsize::new(0));let other=Arc::new(AtomicUsize::new(0));let healthy=||Ok(());let a=SettingAdmission::new(&counter,4096,&healthy);let b=SettingAdmission::new(&other,4096,&healthy);let mut x=a.reserve(400).unwrap();let mut y=b.reserve(600).unwrap();assert_eq!(a.absorb(&mut x,&mut y).unwrap_err().kind(),std::io::ErrorKind::InvalidInput);assert_eq!((x.bytes(),y.bytes()),(400,600));assert_eq!((counter.load(Ordering::Acquire),other.load(Ordering::Acquire)),(400,600));let c=SettingAdmission::new(&counter,4096,&healthy);let mut z=c.reserve(300).unwrap();let low=SettingAdmission::new(&counter,500,&healthy);assert_eq!(low.absorb(&mut x,&mut z).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!((x.bytes(),z.bytes()),(400,300));let fault=||Err(std::io::Error::from_raw_os_error(1450));let failed=SettingAdmission::new(&counter,4096,&fault);let error=failed.absorb(&mut x,&mut z).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!((x.bytes(),z.bytes()),(400,300));drop((x,y,z));assert_eq!((counter.load(Ordering::Acquire),other.load(Ordering::Acquire)),(0,0));}
}

#[cfg(test)]mod actual_split_ownership_tests{
 use super::*;
 #[test]fn actual_split_and_absorb_transfer_without_changing_counter_and_drop_tracks_each_live_payload(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,4096,&||Ok(()));let mut parent=a.reserve(1000).unwrap();let mut child=a.split(&mut parent,400).unwrap();assert_eq!((parent.bytes(),child.bytes(),used.load(Ordering::Acquire)),(600,400,1000));a.absorb(&mut parent,&mut child).unwrap();assert_eq!((parent.bytes(),child.bytes(),used.load(Ordering::Acquire)),(1000,0,1000));let child=a.split(&mut parent,700).unwrap();drop(parent);assert_eq!(used.load(Ordering::Acquire),700);drop(child);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn split_first_io_foreign_overdraw_and_lower_limit_leave_parent_and_counter_intact(){let used=Arc::new(AtomicUsize::new(0));let other=Arc::new(AtomicUsize::new(0));let good=SettingAdmission::new(&used,4096,&||Ok(()));let mut parent=good.reserve(1000).unwrap();let fault=||Err(std::io::Error::from_raw_os_error(1450));let fail=SettingAdmission::new(&used,4096,&fault);assert_eq!(fail.split(&mut parent,100).err().unwrap().raw_os_error(),Some(1450));assert_eq!((parent.bytes(),used.load(Ordering::Acquire)),(1000,1000));let foreign=SettingAdmission::new(&other,4096,&||Ok(()));assert_eq!(foreign.split(&mut parent,100).err().unwrap().kind(),std::io::ErrorKind::InvalidInput);assert_eq!(good.split(&mut parent,1001).err().unwrap().kind(),std::io::ErrorKind::InvalidInput);let low=SettingAdmission::new(&used,500,&||Ok(()));assert_eq!(low.split(&mut parent,100).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!((parent.bytes(),used.load(Ordering::Acquire),other.load(Ordering::Acquire)),(1000,1000,0));let fresh=SettingAdmission::new(&used,4096,&||Ok(()));drop(fresh.split(&mut parent,100).unwrap());assert_eq!((parent.bytes(),used.load(Ordering::Acquire)),(900,900));drop(parent);assert_eq!(used.load(Ordering::Acquire),0);}
}
