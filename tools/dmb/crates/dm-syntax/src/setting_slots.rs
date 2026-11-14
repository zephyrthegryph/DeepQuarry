//! Lazy slots on an ORIGINAL declaration input; no semantic/source authority.
//! The original owner authenticates body/code/metadata/token membership before
//! every call. Native callers supply their SAME existing body-budget admission.
use crate::{SettingAdmission, SettingExpression, SettingRootLease, SettingSyntaxFailure};
use std::{io, mem::size_of, sync::Mutex};

const ROOT_PAGE_LEN: usize = 256;
const ROOT_WORD_BITS: usize = u64::BITS as usize;

/// The existing occupied slot owns its native observation; empty pages do not.
struct Ready{root:SettingExpression,native:crate::expression_parser::NativeExpressionParserState}
/// The mask addresses original ordinals. Only published roots have a row.
#[derive(Default)]
struct RootPage {
    mask: [u64; ROOT_PAGE_LEN / ROOT_WORD_BITS],
    roots: Vec<Ready>,
    credit: Option<SettingRootLease>,
}

impl RootPage {
    fn position(&self, local: usize) -> (usize, bool) {
        let word = local / ROOT_WORD_BITS;
        let bit = 1u64 << (local % ROOT_WORD_BITS);
        let before = self.mask[..word].iter().map(|word| word.count_ones()).sum::<u32>();
        let rank = before + (self.mask[word] & (bit - 1)).count_ones();
        (rank as usize, self.mask[word] & bit != 0)
    }

    fn get(&self, local: usize) -> Option<&SettingExpression> {
        let (index, occupied) = self.position(local);
        occupied.then(|| &self.roots[index].root)
    }

    fn ready(&self,local:usize)->Option<&Ready>{let(index,occupied)=self.position(local);occupied.then(||&self.roots[index])}
    fn insert(
        &mut self, local: usize, root: &SettingExpression, facts:Option<crate::NativeExpressionParserFacts>, a: &SettingAdmission<'_>,
    ) -> Result<(), SettingSyntaxFailure> {
        let (index, occupied) = self.position(local);
        debug_assert!(!occupied);
        let replacement = if self.roots.len() == self.roots.capacity() {
            let capacity = (self.roots.capacity() * 2).max(1);
            debug_assert!(capacity <= ROOT_PAGE_LEN);
            Some(funded_rows(capacity, 0, a)?)
        } else {
            None
        };
        // Nothing has moved and no mask bit is visible until the last fallible
        // check. A failed replacement drops its allocation before its credit.
        a.checkpoint().map_err(SettingSyntaxFailure::Operational)?;
        if let Some((mut rows, credit)) = replacement {
            rows.append(&mut self.roots);
            drop(std::mem::replace(&mut self.roots, rows));
            self.credit = Some(credit);
        }
        self.roots.insert(index,Ready{root:root.clone(),native:crate::expression_parser::NativeExpressionParserState::for_root(facts,root.original_expression().span)});
        self.mask[local / ROOT_WORD_BITS] |= 1u64 << (local % ROOT_WORD_BITS);
        Ok(())
    }
}

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
    count: usize,
    roots: Vec<RootPage>,
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

fn funded_rows<T>(
    capacity: usize, fixed: usize, a: &SettingAdmission<'_>,
) -> Result<(Vec<T>, SettingRootLease), SettingSyntaxFailure> {
    let overflow = || denied(a, io::ErrorKind::OutOfMemory, "setting slot capacity overflow");
    let layout = std::alloc::Layout::array::<T>(capacity).map_err(|_| overflow())?;
    let bytes = layout.size().checked_add(fixed).ok_or_else(overflow)?;
    let credit = a.reserve(bytes).map_err(SettingSyntaxFailure::Operational)?;
    if layout.size() == 0 {
        return Ok((Vec::new(), credit));
    }
    // SAFETY: the exact nonzero Global array layout is already funded.
    let pointer = std::ptr::NonNull::new(unsafe { std::alloc::alloc(layout) }.cast::<T>())
        .ok_or_else(|| denied(a, io::ErrorKind::OutOfMemory, "setting slot allocation refused"))?;
    // SAFETY: no elements are initialized yet. The unique Vec will free the
    // same layout when it drops, before the associated lease.
    let rows = unsafe { Vec::from_raw_parts(pointer.as_ptr(), 0, capacity) };
    Ok((rows, credit))
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
            let pages = count.div_ceil(ROOT_PAGE_LEN);
            let (mut roots, metadata) = funded_rows(pages, size_of::<Storage>(), a)?;
            roots.resize_with(pages, RootPage::default);
            *guard = Some(Storage { count, roots, dimensions:None, metadata });
        }
        let storage = guard.as_mut().expect("initialized original slots");
        // Check actual counter identity BEFORE reading a warm root. A prepared
        // original owner cannot migrate silently to another budget/provider Db.
        if storage.count != count || !a.matches_lease_domain(&storage.metadata) {
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
      self.obtain_with_native_observation(ordinal,count,a,||produce().map(|root|(root,None))).map(|(root,_)|root)
    }
    /// Same authentic occupied slot, with DATA from its actual first producer.
    /// Cached absent observations remain absent; this never reparses.
    pub fn obtain_with_native_observation(
      &self,ordinal:usize,count:usize,a:&SettingAdmission<'_>,
      produce:impl FnOnce()->Result<(SettingExpression,Option<crate::NativeExpressionParserFacts>),SettingSyntaxFailure>,
    )->Result<(SettingExpression,Option<crate::NativeExpressionParserFacts>),SettingSyntaxFailure>{
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
        let page = &mut storage.roots[ordinal / ROOT_PAGE_LEN];
        let local = ordinal % ROOT_PAGE_LEN;
        if let Some(ready) = page.ready(local) {
            let root=&ready.root;
            if !root.is_retained_in(a) || root.current_offset() != 0 {
                return Err(denied(
                    a,
                    io::ErrorKind::InvalidInput,
                    "original setting slot root domain differs",
                ));
            }
            a.checkpoint().map_err(SettingSyntaxFailure::Operational)?;
            return Ok((root.clone(),ready.native.facts(Some(root.original_expression().span))));
        }
        let(root,facts)=produce()?;
        if !root.is_retained_in(a) || root.current_offset() != 0 {
            return Err(denied(
                a,
                io::ErrorKind::InvalidInput,
                "unissued storage cannot populate native setting slot",
            ));
        }
        if facts.is_some_and(|f|(f.is_complete()&&f.complete_span()!=Some(root.original_expression().span))||f.complete_span().is_some_and(|span|span!=root.original_expression().span)){return Err(denied(a,io::ErrorKind::InvalidInput,"native slot observation differs from its actual produced root"))}
        page.insert(local,&root,facts,a)?;
        Ok((root,facts))
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
                    .filter(|storage| ordinal < storage.count)
                    .and_then(|storage| storage.roots[ordinal / ROOT_PAGE_LEN].get(ordinal % ROOT_PAGE_LEN))
                    .map(|original| original.same_root(root))
            })
            .unwrap_or(false)
    }
    /// Debug-only actual Vec container geometry, never AST payload or quota.
    /// Rows are (nonempty allocation count, logical bytes, capacity bytes):
    /// page directory, root leaves, dimension directory, dimension leaves.
    #[cfg(debug_assertions)]
    pub fn container_geometry_for_trace(&self) -> Option<[(usize, usize, usize); 4]> {
        fn add<T>(row: &mut (usize, usize, usize), values: &Vec<T>) -> Option<()> {
            if values.capacity() == 0 { return Some(()); }
            row.0 = row.0.checked_add(1)?;
            row.1 = row.1.checked_add(values.len().checked_mul(size_of::<T>())?)?;
            row.2 = row.2.checked_add(values.capacity().checked_mul(size_of::<T>())?)?;
            Some(())
        }
        let guard = self.state.lock().ok()?;
        let mut rows = [(0, 0, 0); 4];
        if let Some(storage) = guard.as_ref() {
            add(&mut rows[0], &storage.roots)?;
            for page in &storage.roots { add(&mut rows[1], &page.roots)?; }
            if let Some(dimensions) = &storage.dimensions {
                add(&mut rows[2], &dimensions.groups)?;
                for group in dimensions.groups.iter().flatten() {
                    add(&mut rows[3], &group.roots)?;
                }
            }
        }
        Some(rows)
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
                    storage.roots.len() * size_of::<RootPage>(),
                    storage.roots.capacity() * size_of::<RootPage>(),
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
                for page in &storage.roots {
                    if let Some(credit) = &page.credit {
                        credit.visit_counter_storage(|p, n| allocation(p, n, n));
                        allocation(
                            page.roots.as_ptr() as usize,
                            page.roots.len() * size_of::<Ready>(),
                            page.roots.capacity() * size_of::<Ready>(),
                        );
                    }
                    for value in &page.roots {
                        root(&value.root);
                    }
                }
            }
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::{cell::Cell, sync::{atomic::{Ordering}}};
    fn prepare(
        a: &SettingAdmission<'_>,
        text: &str,
    ) -> Result<SettingExpression, SettingSyntaxFailure> {
        let input = crate::lex_spans(text);
        assert!(input.diagnostics.is_empty());
        crate::prepare_setting_expression(text, &input.tokens, crate::Span::new(0, text.len()), a)
    }

    #[test]
    #[cfg(debug_assertions)]
    fn initializer_slot_container_trace_is_scalar_only_and_does_not_poll_or_charge() {
        let fixed = crate::SettingChargeCounter::root_allocation_bytes();
        let counter = crate::SettingChargeCounter::try_new(fixed).unwrap();
        let polls = Cell::new(0usize);
        let poll = || { polls.set(polls.get() + 1); Ok(()) };
        let a = SettingAdmission::new(&counter, 1024 * 1024, &poll);
        let slots = SettingExpressionSlots::default();
        assert_eq!(slots.container_geometry_for_trace(), Some([(0, 0, 0); 4]));
        let value = prepare(&a, "1").unwrap();
        for ordinal in [0, 1, 2, 512] {
            slots.obtain(ordinal, 513, &a, || Ok(value.clone())).unwrap();
        }
        slots.obtain_dimension(2, 513, 0, 2, crate::Span::new(0, 1), &a, || Ok(value.clone())).unwrap();
        let before = counter.load(Ordering::Acquire);
        let poll_count = polls.get();
        let geometry = slots.container_geometry_for_trace().unwrap();
        assert_eq!(geometry[0], (1, 3 * size_of::<RootPage>(), 3 * size_of::<RootPage>()));
        assert_eq!(geometry[1], (2, 4 * size_of::<Ready>(), 5 * size_of::<Ready>()));
        assert_eq!((geometry[2].0, geometry[2].1), (1, 513 * size_of::<Option<DimensionGroup>>()));
        assert!(geometry[2].2 >= geometry[2].1);
        assert_eq!((geometry[3].0, geometry[3].1), (1, 2 * size_of::<Option<(crate::Span, SettingExpression)>>()));
        assert!(geometry[3].2 >= geometry[3].1);
        assert_eq!(counter.load(Ordering::Acquire), before);
        assert_eq!(polls.get(), poll_count);
        assert!(slots.contains_original(512, &value));
        assert!(slots.contains_dimension(2, 0, crate::Span::new(0, 1), &value));
        drop(slots); drop(value);
        assert_eq!(counter.load(Ordering::Acquire), fixed);
    }
    #[test]
    fn sparse_initializer_slots_fund_only_occupied_pages_and_keep_high_ordinals() {
        let fixed = crate::SettingChargeCounter::root_allocation_bytes();
        let counter = crate::SettingChargeCounter::try_new(fixed).unwrap();
        let a = SettingAdmission::new(&counter, 256 * 1024, &|| Ok(()));
        let slots = SettingExpressionSlots::default();
        let count: usize = 400_001;
        let ordinals = [count - 1, ROOT_PAGE_LEN, ROOT_PAGE_LEN - 1, 64, 63, 0];
        let value = prepare(&a, "1").unwrap();
        let base = counter.load(Ordering::Acquire);
        for ordinal in ordinals {
            let root = slots.obtain(ordinal, count, &a, || Ok(value.clone())).unwrap();
            assert!(root.same_root(&value));
            assert!(slots.contains_original(ordinal, &value));
        }
        let directories = count.div_ceil(ROOT_PAGE_LEN) * size_of::<RootPage>();
        let leaf_capacity = (4 + 1 + 1) * size_of::<Ready>();
        assert_eq!(counter.load(Ordering::Acquire) - base,
            size_of::<Storage>() + directories + leaf_capacity);
        let mut visited = 0;
        slots.visit_storage(|_, _, _| {}, |root| {
            assert!(root.same_root(&value));
            visited += 1;
        });
        assert_eq!(visited, ordinals.len());
        assert!(!slots.contains_original(65, &value));
        assert!(!slots.contains_original(count, &value));
        for ordinal in ordinals {
            assert!(slots.obtain(ordinal, count, &a, || panic!("warm root was already issued"))
                .unwrap().same_root(&value));
        }
        let wrong_count = SettingAdmission::new(&counter, 256 * 1024, &|| Ok(()));
        assert!(matches!(slots.obtain(0, count + 1, &wrong_count, || panic!("foreign ordinal domain")),
            Err(SettingSyntaxFailure::Operational(ref e)) if e.kind() == io::ErrorKind::InvalidInput));
        drop(slots);
        assert_eq!(counter.load(Ordering::Acquire), base);
        drop(value);
        assert_eq!(counter.load(Ordering::Acquire), fixed);
    }

    #[test]
    fn sparse_initializer_growth_refusal_and_late_stop_leave_the_old_page_exact() {
        let fixed = crate::SettingChargeCounter::root_allocation_bytes();
        let counter = crate::SettingChargeCounter::try_new(fixed).unwrap();
        let a = SettingAdmission::new(&counter, 8 * 1024 * 1024, &|| Ok(()));
        let slots = SettingExpressionSlots::default();
        let first = prepare(&a, "1").unwrap();
        let second = prepare(&a, "2").unwrap();
        let count = 1024;
        let later = count - 1;
        let earlier = later - 1;
        slots.obtain(later, count, &a, || Ok(first.clone())).unwrap();
        let before = counter.load(Ordering::Acquire);
        let limited = SettingAdmission::new(&counter,
            before + 2 * size_of::<Ready>() - 1, &|| Ok(()));
        assert!(matches!(slots.obtain(earlier, count, &limited, || Ok(second.clone())),
            Err(SettingSyntaxFailure::Operational(ref e)) if e.kind() == io::ErrorKind::OutOfMemory));
        assert_eq!(counter.load(Ordering::Acquire), before);
        assert!(slots.contains_original(later, &first));
        assert!(!slots.contains_original(earlier, &second));

        let stop_after_overlap = || {
            if counter.load(Ordering::Acquire) > before {
                Err(io::Error::from_raw_os_error(1450))
            } else {
                Ok(())
            }
        };
        let stopped = SettingAdmission::new(&counter, 8 * 1024 * 1024, &stop_after_overlap);
        assert!(slots.obtain(earlier, count, &stopped, || Ok(second.clone())).is_err());
        assert_eq!(stopped.take_operational_error().unwrap().raw_os_error(), Some(1450));
        assert_eq!(counter.load(Ordering::Acquire), before);
        assert!(slots.contains_original(later, &first));
        assert!(!slots.contains_original(earlier, &second));
        assert!(slots.obtain(earlier, count, &a, || Ok(second.clone())).unwrap().same_root(&second));
        assert!(slots.contains_original(later, &first));
        drop((slots, first, second));
        assert_eq!(counter.load(Ordering::Acquire), fixed);
    }

    #[test]
    fn warm_original_setting_slot_projects_offsets_without_second_parse_or_ast_shift() {
        let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
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
        assert!(counter.load(Ordering::Acquire) > crate::SettingChargeCounter::root_allocation_bytes());
        drop(first);
        assert!(counter.load(Ordering::Acquire) > crate::SettingChargeCounter::root_allocation_bytes());
        drop(current);
        assert_eq!(counter.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }
    #[test]
    fn original_slot_refuses_foreign_budget_before_warm_lookup_and_compat_storage() {
        let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let other = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
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
        let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
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
      let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let healthy=||Ok(());let a=SettingAdmission::new(&counter,8*1024*1024,&healthy);let slots=SettingExpressionSlots::default();
      let rhs=slots.obtain(0,2,&a,||prepare(&a,"null")).unwrap();let span=crate::Span::new(10,13);
      let dimension=slots.obtain_dimension(0,2,0,2,span,&a,||prepare(&a,"1+2")).unwrap();
      assert!(!rhs.same_root(&dimension));assert!(slots.contains_original(0,&rhs));assert!(slots.contains_dimension(0,0,span,&dimension));
      let warm=slots.obtain_dimension(0,2,0,2,span,&a,||panic!("same dimension cannot parse twice")).unwrap();assert!(dimension.same_root(&warm));
      let other=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let foreign=SettingAdmission::new(&other,8*1024*1024,&healthy);
      assert!(matches!(slots.obtain_dimension(0,2,0,2,span,&foreign,||panic!("foreign warm domain cannot produce")),Err(SettingSyntaxFailure::Operational(_))));
      let stop=||Err(io::Error::from_raw_os_error(1450));let failed=SettingAdmission::new(&counter,8*1024*1024,&stop);
      let next=crate::Span::new(20,23);assert!(slots.obtain_dimension(0,2,1,2,next,&failed,||panic!("actual entry stop precedes parser")).is_err());
      assert_eq!(failed.take_operational_error().unwrap().raw_os_error(),Some(1450));
      let recovered=slots.obtain_dimension(0,2,1,2,next,&a,||prepare(&a,"3+4")).unwrap();assert!(!dimension.same_root(&recovered));
      drop(rhs);drop(dimension);drop(warm);drop(recovered);drop(slots);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes(),"dimension aliases/metadata physically release original credit");
    }

}

#[cfg(test)]mod observed_slot_owner_controls{
 use super::*;use std::{cell::Cell,sync::atomic::Ordering};
 fn actual(text:&str,a:&SettingAdmission<'_>)->Result<(SettingExpression,Option<crate::NativeExpressionParserFacts>),SettingSyntaxFailure>{let lexed=crate::lex_spans(text);crate::prepare_setting_expression_with_original_literal_facts_and_native_observation(text,&lexed.tokens,crate::Span::new(0,text.len()),a,None)}
 #[test]fn actual_slot_observation_belongs_to_same_cached_root_without_reparse_or_new_empty_page_bytes(){
  struct PriorPage{mask:[u64;4],roots:Vec<SettingExpression>,credit:Option<SettingRootLease>}
  assert_eq!(size_of::<RootPage>(),size_of::<PriorPage>());assert!(size_of::<Ready>()<=size_of::<SettingExpression>()+size_of::<usize>());
  eprintln!("NATIVE_SETTING_READY_SIZE prior={} current={} page={}",size_of::<SettingExpression>(),size_of::<Ready>(),size_of::<RootPage>());
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let slots=SettingExpressionSlots::default();let calls=Cell::new(0);
  let(root,facts)=slots.obtain_with_native_observation(0,1,&a,||{calls.set(calls.get()+1);actual("value+1",&a)}).unwrap();assert!(facts.unwrap().is_complete());let before=used.load(Ordering::Acquire);
  let(cached,again)=slots.obtain_with_native_observation(0,1,&a,||panic!("cached observation cannot reparse")).unwrap();assert!(root.same_root(&cached));assert_eq!(again,facts);assert_eq!(again.unwrap().complete_span(),Some(cached.original_expression().span));assert_eq!(used.load(Ordering::Acquire),before);assert_eq!(calls.get(),1);drop((slots,root,cached));assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 #[test]fn actual_slot_observation_rejects_another_parsers_span_before_publishing_or_leaking_credit(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let used=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let(root,_)=actual("value+1",&a).unwrap();let(other,wrong)=actual("long_value+1",&a).unwrap();let slots=SettingExpressionSlots::default();
  assert!(matches!(slots.obtain_with_native_observation(0,1,&a,||Ok((root.clone(),wrong))),Err(SettingSyntaxFailure::Operational(_))));assert_eq!(a.take_operational_error().unwrap().kind(),io::ErrorKind::InvalidInput);assert!(!slots.contains_original(0,&root));
  let fresh=SettingAdmission::new(&used,8<<20,&||Ok(()));let(ok,facts)=slots.obtain_with_native_observation(0,1,&fresh,||actual("value+1",&fresh)).unwrap();assert!(facts.unwrap().is_complete());assert!(slots.contains_original(0,&ok));drop((root,other,ok,slots));assert_eq!(used.load(Ordering::Acquire),fixed);
 }
}
