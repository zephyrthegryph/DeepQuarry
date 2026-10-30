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
    pub fn reserve(&self, bytes: usize) -> std::io::Result<SettingRootLease> {
        self.checkpoint()?;
        match SettingRootLease::reserve(self.counter, self.limit, bytes) {
            Ok(lease) => Ok(lease),
            Err(message) => {
                self.record_operational_error(std::io::Error::new(
                    std::io::ErrorKind::OutOfMemory,
                    message,
                ));
                Err(std::io::ErrorKind::OutOfMemory.into())
            }
        }
    }
    /// Grow ONE owner-lived metadata lease before allocating another slot.
    /// No intermediate Arc/control block or forgotten lease may survive merge.
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
    pub fn matches_lease_domain(&self, lease: &SettingRootLease) -> bool {
        Arc::ptr_eq(self.counter, &lease.counter)
    }
}
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
}
impl SettingExpression {
    pub(crate) fn compatibility(expression: Expr) -> Self {
        Self {
            root: Some(Arc::new(Root {
                expression,
                retention: None,
            })),
            current_offset: 0,
        }
    }
    pub(crate) fn retained_with_anchor(
        expression: Expr,
        retention: SharedSettingRetention,
    ) -> Self {
        Self {
            root: Some(Arc::new(Root {
                expression,
                retention: Some(retention),
            })),
            current_offset: 0,
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
        Ok(self)
    }
    pub fn current_span_of(&self, expression: &Expr) -> Option<crate::Span> {
        Some(crate::Span::new(
            expression.span.start.checked_add(self.current_offset)?,
            expression.span.end.checked_add(self.current_offset)?,
        ))
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
