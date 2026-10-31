//! Lazy slots on an ORIGINAL declaration input; no semantic/source authority.
//! The original owner authenticates body/code/metadata/token membership before
//! every call. Native callers supply their SAME existing body-budget admission.
use crate::{SettingAdmission, SettingExpression, SettingRootLease, SettingSyntaxFailure};
use std::{io, mem::size_of, sync::Mutex};
#[derive(Default)]
pub struct SettingExpressionSlots {
    state: Mutex<Option<Storage>>,
}
struct DimensionGroup{
    roots:Vec<Option<(crate::Span,SettingExpression)>>,
    metadata:SettingRootLease,
}
struct DimensionStorage{
    groups:Vec<Option<DimensionGroup>>,
    // LAST: group roots and directory Vec physically free before credit.
    metadata:SettingRootLease,
}
struct Storage {
    roots: Vec<Option<SettingExpression>>,
    dimensions:Option<DimensionStorage>,
    // Last: actual Vec allocation and original root aliases die before credit.
    metadata: SettingRootLease,
}
impl std::fmt::Debug for SettingExpressionSlots {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SettingExpressionSlots")
            .finish_non_exhaustive()
    }
}
fn denied(
    a: &SettingAdmission<'_>,
    kind: io::ErrorKind,
    message: &'static str,
) -> SettingSyntaxFailure {
    a.record_operational_error(io::Error::new(kind, message));
    SettingSyntaxFailure::Operational(kind.into())
}
/// Same conservative4x requested-capacity envelope BEFORE allocation. Exposed
/// excess refuses before publication; no post-allocation charge is its proof.
fn dimension_rows<T>(count:usize,fixed:usize,a:&SettingAdmission<'_>)->Result<(Vec<T>,SettingRootLease),SettingSyntaxFailure>{
 let bytes=count.checked_mul(4).and_then(|n|n.checked_mul(size_of::<T>())).and_then(|n|n.checked_add(fixed)).ok_or_else(||denied(a,io::ErrorKind::OutOfMemory,"dimension slot capacity overflow"))?;
 let metadata=a.reserve(bytes).map_err(SettingSyntaxFailure::Operational)?;let mut rows=Vec::new();
 rows.try_reserve_exact(count).map_err(|_|denied(a,io::ErrorKind::OutOfMemory,"dimension slot allocation refused"))?;
 let actual=rows.capacity().checked_mul(size_of::<T>()).and_then(|n|n.checked_add(fixed)).ok_or_else(||denied(a,io::ErrorKind::OutOfMemory,"dimension slot exposed capacity overflow"))?;
 if actual>bytes{return Err(denied(a,io::ErrorKind::OutOfMemory,"dimension slot exposed capacity exceeds reserved envelope"))}
 Ok((rows,metadata))
}
impl SettingExpressionSlots {
    fn lock_storage<'slot>(&'slot self,count:usize,a:&SettingAdmission<'_>)->Result<std::sync::MutexGuard<'slot,Option<Storage>>,SettingSyntaxFailure>{
        a.checkpoint().map_err(SettingSyntaxFailure::Operational)?;
        let mut guard = self.state.lock().map_err(|_| {
            denied(
                a,
                io::ErrorKind::Other,
                "original setting slot lock poisoned",
            )
        })?;
        if guard.is_none() {
            // Reserve BEFORE Vec allocation; admit any exposed allocator excess
            // before it can survive this call. No source/profile cap is changed.
            let bytes = count
                .checked_mul(size_of::<Option<SettingExpression>>())
                .and_then(|n| n.checked_add(size_of::<Storage>()))
                .ok_or_else(|| {
                    denied(
                        a,
                        io::ErrorKind::OutOfMemory,
                        "setting slot capacity overflow",
                    )
                })?;
            let mut metadata = a
                .reserve(bytes)
                .map_err(SettingSyntaxFailure::Operational)?;
            let mut roots = Vec::new();
            roots.try_reserve_exact(count).map_err(|_| {
                denied(
                    a,
                    io::ErrorKind::OutOfMemory,
                    "setting slot allocation refused",
                )
            })?;
            let actual = roots
                .capacity()
                .checked_mul(size_of::<Option<SettingExpression>>())
                .and_then(|n| n.checked_add(size_of::<Storage>()))
                .ok_or_else(|| {
                    denied(
                        a,
                        io::ErrorKind::OutOfMemory,
                        "setting slot exposed capacity overflow",
                    )
                })?;
            if actual > bytes {
                a.grow(&mut metadata, actual - bytes)
                    .map_err(SettingSyntaxFailure::Operational)?;
            }
            roots.resize_with(count, || None);
            *guard = Some(Storage { roots, dimensions:None, metadata });
        }
        let storage = guard.as_mut().expect("initialized original slots");
        // Check actual counter identity BEFORE reading a warm root. A prepared
        // original owner cannot migrate silently to another budget/provider Db.
        if storage.roots.len() != count || !a.matches_lease_domain(&storage.metadata) {
            return Err(denied(
                a,
                io::ErrorKind::InvalidInput,
                "original setting slot budget domain differs",
            ));
        }
        Ok(guard)
    }
    /// Header/suffix ordinals address the SAME original slot family directly.
    /// Only the enclosing immutable source receipt authenticates those axes.
    pub fn obtain_dimension(&self,ordinal:usize,count:usize,dimension:usize,dimensions:usize,span:crate::Span,a:&SettingAdmission<'_>,produce:impl FnOnce()->Result<SettingExpression,SettingSyntaxFailure>)->Result<SettingExpression,SettingSyntaxFailure>{
      if ordinal>=count||dimension>=dimensions||span.start>=span.end{return Err(denied(a,io::ErrorKind::InvalidInput,"original dimension coordinate unavailable"))}
      let mut guard=self.lock_storage(count,a)?;let storage=guard.as_mut().expect("initialized original slot family");
      if storage.dimensions.is_none(){
        let (mut groups,metadata)=dimension_rows::<Option<DimensionGroup>>(count,size_of::<DimensionStorage>(),a)?;
        groups.resize_with(count,||None);storage.dimensions=Some(DimensionStorage{groups,metadata});
      }
      let rows=storage.dimensions.as_mut().expect("dimension directory admitted");
      if rows.groups.len()!=count||!a.matches_lease_domain(&rows.metadata){return Err(denied(a,io::ErrorKind::InvalidInput,"dimension directory source/domain differs"))}
      let selected=&mut rows.groups[ordinal];
      if selected.is_none(){
        let (mut roots,metadata)=dimension_rows::<Option<(crate::Span,SettingExpression)>>(dimensions,size_of::<DimensionGroup>(),a)?;
        roots.resize_with(dimensions,||None);*selected=Some(DimensionGroup{roots,metadata});
      }
      let group=selected.as_mut().expect("dimension group admitted");
      if group.roots.len()!=dimensions||!a.matches_lease_domain(&group.metadata){return Err(denied(a,io::ErrorKind::InvalidInput,"dimension suffix count/domain differs"))}
      if let Some((original,root))=&group.roots[dimension]{
        if *original!=span||!root.is_retained_in(a)||root.current_offset()!=0{return Err(denied(a,io::ErrorKind::InvalidInput,"original dimension root source/domain differs"))}
        a.checkpoint().map_err(SettingSyntaxFailure::Operational)?;return Ok(root.clone())
      }
      let root=produce()?;if !root.is_retained_in(a)||root.current_offset()!=0{return Err(denied(a,io::ErrorKind::InvalidInput,"unissued dimension cannot populate original slot"))}
      a.checkpoint().map_err(SettingSyntaxFailure::Operational)?;group.roots[dimension]=Some((span,root.clone()));Ok(root)
    }
    pub fn contains_dimension(&self,ordinal:usize,dimension:usize,span:crate::Span,root:&SettingExpression)->bool{
      self.state.lock().ok().and_then(|guard|guard.as_ref().and_then(|s|s.dimensions.as_ref()).and_then(|s|s.groups.get(ordinal)).and_then(Option::as_ref).and_then(|group|group.roots.get(dimension)).and_then(Option::as_ref).map(|(original,r)|*original==span&&r.same_root(root))).unwrap_or(false)
    }
    /// No leaf QueryDb/gate/reset call. This lock serializes only this original
    /// declaration's root publication, and is never held by the outer host gate.
    /// Genuine syntax rejection stays uncached here. Operational failure leaves
    /// the selected slot EMPTY; no error text can poison same-input retry.
    pub fn obtain(
        &self,
        ordinal: usize,
        count: usize,
        a: &SettingAdmission<'_>,
        produce: impl FnOnce() -> Result<SettingExpression, SettingSyntaxFailure>,
    ) -> Result<SettingExpression, SettingSyntaxFailure> {
        a.checkpoint().map_err(SettingSyntaxFailure::Operational)?;
        if ordinal >= count {
            return Err(denied(
                a,
                io::ErrorKind::InvalidInput,
                "setting slot ordinal unavailable",
            ));
        }
        let mut guard=self.lock_storage(count,a)?;
        let storage=guard.as_mut().expect("initialized original slots");
        if let Some(root) = &storage.roots[ordinal] {
            if !root.is_retained_in(a) || root.current_offset() != 0 {
                return Err(denied(
                    a,
                    io::ErrorKind::InvalidInput,
                    "original setting slot root domain differs",
                ));
            }
            a.checkpoint().map_err(SettingSyntaxFailure::Operational)?;
            return Ok(root.clone());
        }
        let root = produce()?;
        if !root.is_retained_in(a) || root.current_offset() != 0 {
            return Err(denied(
                a,
                io::ErrorKind::InvalidInput,
                "unissued storage cannot populate native setting slot",
            ));
        }
        a.checkpoint().map_err(SettingSyntaxFailure::Operational)?;
        storage.roots[ordinal] = Some(root.clone());
        Ok(root)
    }
    /// Storage identity only. The enclosing ORIGINAL source receipt must bind
    /// this particular slot before it checks a host's returned sealed handle.
    pub fn contains_original(&self, ordinal: usize, root: &SettingExpression) -> bool {
        self.state
            .lock()
            .ok()
            .and_then(|guard| {
                guard
                    .as_ref()
                    .and_then(|s| s.roots.get(ordinal))
                    .and_then(Option::as_ref)
                    .map(|original| original.same_root(root))
            })
            .unwrap_or(false)
    }
    /// Actual backing storage and quota counter only. Root/anchor/Expr/literal
    /// allocations are forwarded by borrowed references into the caller's SAME
    /// pointer-deduplicating census; charged admission != exact allocator/RSS.
    pub fn visit_storage(
        &self,
        mut allocation: impl FnMut(usize, usize, usize),
        mut root: impl FnMut(&SettingExpression),
    ) {
        if let Ok(guard) = self.state.lock() {
            if let Some(storage) = guard.as_ref() {
                storage
                    .metadata
                    .visit_counter_storage(|p, n| allocation(p, n, n));
                allocation(
                    storage.roots.as_ptr() as usize,
                    storage.roots.len() * size_of::<Option<SettingExpression>>(),
                    storage.roots.capacity() * size_of::<Option<SettingExpression>>(),
                );
                if let Some(dimensions)=&storage.dimensions{
                    dimensions.metadata.visit_counter_storage(|p,n|allocation(p,n,n));
                    allocation(dimensions.groups.as_ptr() as usize,dimensions.groups.len()*size_of::<Option<DimensionGroup>>(),dimensions.groups.capacity()*size_of::<Option<DimensionGroup>>());
                    for group in dimensions.groups.iter().flatten(){
                        group.metadata.visit_counter_storage(|p,n|allocation(p,n,n));
                        allocation(group.roots.as_ptr() as usize,group.roots.len()*size_of::<Option<(crate::Span,SettingExpression)>>(),group.roots.capacity()*size_of::<Option<(crate::Span,SettingExpression)>>());
                        for (_,value) in group.roots.iter().flatten(){root(value);}
                    }
                }
                for value in storage.roots.iter().flatten() {
                    root(value);
                }
            }
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        cell::Cell,
        sync::{
            atomic::{AtomicUsize, Ordering},
            Arc,
        },
    };
    fn prepare(
        a: &SettingAdmission<'_>,
        text: &str,
    ) -> Result<SettingExpression, SettingSyntaxFailure> {
        let input = crate::lex_spans(text);
        assert!(input.diagnostics.is_empty());
        crate::prepare_setting_expression(text, &input.tokens, crate::Span::new(0, text.len()), a)
    }
    #[test]
    fn warm_original_setting_slot_projects_offsets_without_second_parse_or_ast_shift() {
        let counter = Arc::new(AtomicUsize::new(0));
        let checkpoint = || Ok(());
        let a = SettingAdmission::with_stack_allowance(
            &counter,
            8 * 1024 * 1024,
            1024 * 1024,
            &checkpoint,
        );
        let slots = SettingExpressionSlots::default();
        let calls = Cell::new(0);
        let first = slots
            .obtain(0, 1, &a, || {
                calls.set(calls.get() + 1);
                prepare(&a, "(1 + 2)")
            })
            .unwrap();
        let current = slots
            .obtain(0, 1, &a, || panic!("warm original RHS cannot parse again"))
            .unwrap()
            .project_current(400, 7)
            .unwrap();
        assert!(first.same_root(&current));
        assert_eq!(calls.get(), 1);
        assert_eq!(
            first.original_expression().span,
            current.original_expression().span
        );
        assert_eq!(
            current.current_span().start,
            first.current_span().start + 400
        );
        assert_eq!(current.current_span().end, first.current_span().end + 400);
        drop(slots);
        assert!(counter.load(Ordering::Acquire) > 0);
        drop(first);
        assert!(counter.load(Ordering::Acquire) > 0);
        drop(current);
        assert_eq!(counter.load(Ordering::Acquire), 0);
    }
    #[test]
    fn original_slot_refuses_foreign_budget_before_warm_lookup_and_compat_storage() {
        let counter = Arc::new(AtomicUsize::new(0));
        let other = Arc::new(AtomicUsize::new(0));
        let checkpoint = || Ok(());
        let a = SettingAdmission::new(&counter, 8 * 1024 * 1024, &checkpoint);
        let slots = SettingExpressionSlots::default();
        let first = slots.obtain(0, 1, &a, || prepare(&a, "1")).unwrap();
        let foreign = SettingAdmission::new(&other, 8 * 1024 * 1024, &checkpoint);
        assert!(
            matches!(slots.obtain(0,1,&foreign,||panic!("must refuse before producer")),
            Err(SettingSyntaxFailure::Operational(ref e)) if e.kind()==io::ErrorKind::InvalidInput)
        );
        assert!(first.is_retained_in(&a));
        let fresh = SettingExpressionSlots::default();
        let retry = SettingAdmission::new(&counter, 8 * 1024 * 1024, &checkpoint);
        let compat = crate::parse_expression("1").expr.unwrap();
        assert!(matches!(
            fresh.obtain(0, 1, &retry, || Ok(SettingExpression::compatibility(
                compat
            ))),
            Err(SettingSyntaxFailure::Operational(_))
        ));
    }
    #[test]
    fn aborted_original_slot_has_no_error_outcome_and_same_input_retry_succeeds() {
        let counter = Arc::new(AtomicUsize::new(0));
        let checkpoint = || Ok(());
        let slots = SettingExpressionSlots::default();
        let a = SettingAdmission::new(&counter, 8 * 1024 * 1024, &checkpoint);
        let error = slots.obtain(0, 1, &a, || {
            a.record_operational_error(io::Error::new(
                io::ErrorKind::Interrupted,
                "actual parser cancellation",
            ));
            Err(SettingSyntaxFailure::Operational(
                io::ErrorKind::Interrupted.into(),
            ))
        });
        assert!(matches!(error, Err(SettingSyntaxFailure::Operational(_))));
        assert_eq!(
            a.take_operational_error().unwrap().to_string(),
            "actual parser cancellation"
        );
        let retry = SettingAdmission::new(&counter, 8 * 1024 * 1024, &checkpoint);
        let result = slots.obtain(0, 1, &retry, || prepare(&retry, "1")).unwrap();
        assert!(result.is_retained_in(&retry));
    }
    #[test]
    fn dimension_rows_share_original_family_retry_and_counter_without_aliasing_rhs(){
      let counter=Arc::new(AtomicUsize::new(0));let healthy=||Ok(());let a=SettingAdmission::new(&counter,8*1024*1024,&healthy);let slots=SettingExpressionSlots::default();
      let rhs=slots.obtain(0,2,&a,||prepare(&a,"null")).unwrap();let span=crate::Span::new(10,13);
      let dimension=slots.obtain_dimension(0,2,0,2,span,&a,||prepare(&a,"1+2")).unwrap();
      assert!(!rhs.same_root(&dimension));assert!(slots.contains_original(0,&rhs));assert!(slots.contains_dimension(0,0,span,&dimension));
      let warm=slots.obtain_dimension(0,2,0,2,span,&a,||panic!("same dimension cannot parse twice")).unwrap();assert!(dimension.same_root(&warm));
      let other=Arc::new(AtomicUsize::new(0));let foreign=SettingAdmission::new(&other,8*1024*1024,&healthy);
      assert!(matches!(slots.obtain_dimension(0,2,0,2,span,&foreign,||panic!("foreign warm domain cannot produce")),Err(SettingSyntaxFailure::Operational(_))));
      let stop=||Err(io::Error::from_raw_os_error(1450));let failed=SettingAdmission::new(&counter,8*1024*1024,&stop);
      let next=crate::Span::new(20,23);assert!(slots.obtain_dimension(0,2,1,2,next,&failed,||panic!("actual entry stop precedes parser")).is_err());
      assert_eq!(failed.take_operational_error().unwrap().raw_os_error(),Some(1450));
      let recovered=slots.obtain_dimension(0,2,1,2,next,&a,||prepare(&a,"3+4")).unwrap();assert!(!dimension.same_root(&recovered));
      drop(rhs);drop(dimension);drop(warm);drop(recovered);drop(slots);assert_eq!(counter.load(Ordering::Acquire),0,"dimension aliases/metadata physically release original credit");
    }

}
