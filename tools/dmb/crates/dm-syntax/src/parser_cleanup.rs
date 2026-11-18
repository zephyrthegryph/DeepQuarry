//! Temporary, operation-owned cleanup for private parser expression roots.
//! It grants no token, syntax, source, or model authority.
use crate::{Expr, SettingAdmission, SettingRootLease};
use crate::pratt_continuations::PrattContinuations;
use std::{cell::RefCell, io, sync::Arc};

struct Payload<'a, 'op> {
    // Scratch allocation and payloads die before the control-block credit.
    work: RefCell<PrattContinuations<'a, 'op, Expr>>,
    admission: Option<&'a SettingAdmission<'op>>,
    _control_credit: Option<SettingRootLease>,
}

pub(crate) struct ParserCleanup<'a, 'op> {
    // No Weak escapes. Final into_inner frees the Arc allocation before the
    // moved Payload drops its buffers and then its control-block credit.
    owner: Option<Arc<Payload<'a, 'op>>>,
}

impl<'a, 'op> ParserCleanup<'a, 'op> {
    pub(crate) fn new(admission: Option<&'a SettingAdmission<'op>>) -> io::Result<Self> {
        let bytes = std::mem::size_of::<Payload<'a, 'op>>()
            .checked_add(2 * std::mem::size_of::<usize>())
            .ok_or(io::ErrorKind::OutOfMemory)?;
        let control_credit = match admission { Some(a) => Some(a.reserve(bytes)?), None => None };
        Ok(Self { owner: Some(Arc::new(Payload {
            work: RefCell::new(PrattContinuations::new(admission)),
            admission,
            _control_credit: control_credit,
        })) })
    }

    fn payload(&self) -> &Payload<'a, 'op> { self.owner.as_deref().expect("live parser cleanup owner") }

    /// BEFORE assembling or accepting a root, its parser computes a checked
    /// bound on the live LIFO work frontier in release_child_roots push order.
    /// A total node count is conservative; private parser owners retain the
    /// exact maximum pending roots instead (unary chains need one slot).
    /// Literals remain atomic: their existing owners perform their own paid,
    /// iterative destruction, including any escaped template aliases.
    pub(crate) fn ensure_nodes(&self, admission: Option<&SettingAdmission<'_>>, nodes: usize) -> io::Result<()> {
        let payload = self.payload();
        let same = match (payload.admission, admission) {
            (None, None) => true,
            (Some(owned), Some(actual)) => std::ptr::eq(owned, actual),
            _ => false,
        };
        if !same {
            let error = io::Error::new(io::ErrorKind::InvalidInput, "parser cleanup has a foreign operation");
            if let Some(a) = admission.or(payload.admission) { a.record_operational_error(error); }
            return Err(io::ErrorKind::InvalidInput.into());
        }
        // The private parser never exposes this context/root to a resource
        // callback. Normal/error drop cannot overlap active buffer growth.
        payload.work.borrow_mut().reserve_total(nodes)
    }

    /// Only private parser RAII owners call this, after ensure_nodes admitted
    /// their checked bound. No polling, reservation, token pull or allocation
    /// occurs in this parser worklist drain. Do NOT hold cleanup_gate: an
    /// atomic Literal may enter its own existing serialized cleanup domain.
    pub(crate) fn drop_expression(&self, expression: Expr) {
        let mut work = self.payload().work.borrow_mut();
        assert!(work.is_empty(), "exclusive parser cleanup worklist");
        work.push_preallocated(expression);
        while let Some(value) = work.pop() {
            crate::setting_drop::release_child_roots(value.kind, |child| work.push_preallocated(child));
        }
    }
}

impl Clone for ParserCleanup<'_, '_> {
    fn clone(&self) -> Self { Self { owner: self.owner.as_ref().map(Arc::clone) } }
}

impl Drop for ParserCleanup<'_, '_> {
    fn drop(&mut self) {
        if let Some(owner) = self.owner.take() {
            if let Some(payload) = Arc::into_inner(owner) { drop(payload); }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{ExprKind, Span};
    use std::cell::Cell;
    use std::sync::atomic::Ordering;

    #[test]
    fn parser_cleanup_uses_paid_nonrecursive_storage_and_keeps_alias_credit() {
        let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let fixed = counter.load(Ordering::Acquire);
        let polls = Cell::new(0);
        let stop = Cell::new(false);
        let poll = || {
            polls.set(polls.get() + 1);
            if stop.get() { Err(io::Error::from_raw_os_error(1450)) } else { Ok(()) }
        };
        let a = SettingAdmission::new(&counter, 32 << 20, &poll);
        let cleanup = ParserCleanup::new(Some(&a)).unwrap();
        let alias = cleanup.clone();
        let nodes = 20_001usize;
        cleanup.ensure_nodes(Some(&a), nodes).unwrap();
        let payload_credit = a.reserve(nodes * std::mem::size_of::<Expr>() + 1).unwrap();
        let mut value = Expr { span: Span::new(0, 1), kind: ExprKind::Ident("x".into()) };
        for _ in 1..nodes { value = Expr { span: Span::new(0, 1), kind: ExprKind::Group(Box::new(value)) }; }
        let held = counter.load(Ordering::Acquire);
        let before_drop = polls.get();
        stop.set(true);
        cleanup.drop_expression(value);
        assert_eq!(polls.get(), before_drop, "cleanup never polls a canceled operation");
        assert!(!a.is_stopped());
        assert_eq!(counter.load(Ordering::Acquire), held, "scratch and payload credit remain until their actual owners retire");
        drop(payload_credit);
        drop(cleanup);
        assert!(counter.load(Ordering::Acquire) > fixed, "last context alias retains the paid scratch/control owner");
        drop(alias);
        assert_eq!(counter.load(Ordering::Acquire), fixed);
    }

    #[test]
    fn parser_cleanup_rejects_foreign_operation_and_refunds_denied_growth() {
        let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let fixed = counter.load(Ordering::Acquire);
        let a = SettingAdmission::new(&counter, fixed + 4096, &|| Ok(()));
        let cleanup = ParserCleanup::new(Some(&a)).unwrap();
        let held = counter.load(Ordering::Acquire);
        assert!(cleanup.ensure_nodes(Some(&a), 20_000).is_err());
        assert_eq!(counter.load(Ordering::Acquire), held);
        assert_eq!(a.take_operational_error().unwrap().kind(), io::ErrorKind::OutOfMemory);
        drop(cleanup);
        assert_eq!(counter.load(Ordering::Acquire), fixed);
        let good = SettingAdmission::new(&counter, 1 << 20, &|| Ok(()));
        let foreign = SettingAdmission::new(&counter, 1 << 20, &|| Ok(()));
        let cleanup = ParserCleanup::new(Some(&good)).unwrap();
        assert_eq!(cleanup.ensure_nodes(Some(&foreign), 1).unwrap_err().kind(), io::ErrorKind::InvalidInput);
        assert_eq!(foreign.take_operational_error().unwrap().kind(), io::ErrorKind::InvalidInput);
        assert!(!good.is_stopped());
        cleanup.ensure_nodes(Some(&good), 1).unwrap();
        cleanup.drop_expression(Expr { span: Span::new(0, 0), kind: ExprKind::Ident(String::new()) });
        drop(cleanup);
        assert_eq!(counter.load(Ordering::Acquire), fixed);
    }
}
