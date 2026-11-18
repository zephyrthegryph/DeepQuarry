//! Lazy slots on an ORIGINAL declaration input; no semantic/source authority.
//! The original owner authenticates body/code/metadata/token membership before
//! every call. Native callers supply their SAME existing body-budget admission.
use crate::{SettingAdmission, SettingExpression, SettingRootLease, SettingSyntaxFailure};
use std::{io, mem::size_of, sync::Mutex};

const ROOT_PAGE_LEN: usize = 256;
const ROOT_WORD_BITS: usize = u64::BITS as usize;

/// The existing occupied slot owns its native observation; empty pages do not.
struct Ready{root:SettingExpression,native:crate::expression_parser::NativeExpressionParserState,constructors:crate::OriginalConstructorFacts}
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
        &mut self, local: usize, root: &SettingExpression, facts:Option<crate::NativeExpressionParserFacts>, products:crate::OriginalSettingProducts, a: &SettingAdmission<'_>,
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
        self.roots.insert(index,Ready{root:root.clone(),native:crate::expression_parser::NativeExpressionParserState::for_root(facts,root.original_expression().span).with_original_value(products.complete_at(root.original_expression().span)),constructors:products.constructors().clone()});
        self.mask[local / ROOT_WORD_BITS] |= 1u64 << (local % ROOT_WORD_BITS);
        Ok(())
    }
}

#[derive(Default)]
pub struct SettingExpressionSlots {
    state: Mutex<Option<Storage>>,
}
struct DimensionGroup{
    roots:Vec<Option<(crate::Span,Ready)>>,
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
      self.obtain_dimension_with_original_products(ordinal,count,dimension,dimensions,span,a,||produce().map(|root|(root,None,crate::OriginalSettingProducts::default()))).map(|(root,_,_)|root)
    }
    pub fn obtain_dimension_with_original_products(&self,ordinal:usize,count:usize,dimension:usize,dimensions:usize,span:crate::Span,a:&SettingAdmission<'_>,produce:impl FnOnce()->Result<(SettingExpression,Option<crate::NativeExpressionParserFacts>,crate::OriginalSettingProducts),SettingSyntaxFailure>)->Result<(SettingExpression,Option<crate::NativeExpressionParserFacts>,crate::OriginalSettingProducts),SettingSyntaxFailure>{
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
        let (mut roots,metadata)=dimension_rows::<Option<(crate::Span,Ready)>>(dimensions,size_of::<DimensionGroup>(),a)?;
        roots.resize_with(dimensions,||None);*selected=Some(DimensionGroup{roots,metadata});
      }
      let group=selected.as_mut().expect("dimension group admitted");
      if group.roots.len()!=dimensions||!a.matches_lease_domain(&group.metadata){return Err(denied(a,io::ErrorKind::InvalidInput,"dimension suffix count/domain differs"))}
      if let Some((original,ready))=&group.roots[dimension]{
        let root=&ready.root;
        if *original!=span||!root.is_retained_in(a)||root.current_offset()!=0{return Err(denied(a,io::ErrorKind::InvalidInput,"original dimension root source/domain differs"))}
        a.checkpoint().map_err(SettingSyntaxFailure::Operational)?;return Ok((root.clone(),ready.native.facts(Some(root.original_expression().span)),crate::OriginalSettingProducts::from_slot(ready.constructors.clone(),root.original_expression().span,ready.native.original_value_complete())))
      }
      let(root,facts,products)=produce()?;if !root.is_retained_in(a)||root.current_offset()!=0{return Err(denied(a,io::ErrorKind::InvalidInput,"unissued dimension cannot populate original slot"))}
      if facts.is_some_and(|f|f.complete_span().is_some_and(|span|span!=root.original_expression().span))||!products.constructors().is_admitted_by(a)||products.constructors().as_slice().iter().any(|row|row.span().start<root.original_expression().span.start||row.span().end>root.original_expression().span.end){return Err(denied(a,io::ErrorKind::InvalidInput,"dimension products differ from actual root resource/extent"))}
      a.checkpoint().map_err(SettingSyntaxFailure::Operational)?;group.roots[dimension]=Some((span,Ready{root:root.clone(),native:crate::expression_parser::NativeExpressionParserState::for_root(facts,root.original_expression().span).with_original_value(products.complete_at(root.original_expression().span)),constructors:products.constructors().clone()}));Ok((root,facts,products))
    }
    pub fn contains_dimension(&self,ordinal:usize,dimension:usize,span:crate::Span,root:&SettingExpression)->bool{
      self.state.lock().ok().and_then(|guard|guard.as_ref().and_then(|s|s.dimensions.as_ref()).and_then(|s|s.groups.get(ordinal)).and_then(Option::as_ref).and_then(|group|group.roots.get(dimension)).and_then(Option::as_ref).map(|(original,r)|*original==span&&r.root.same_root(root))).unwrap_or(false)
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
      self.obtain_with_original_products(ordinal,count,a,||produce().map(|(root,native)|(root,native,crate::OriginalSettingProducts::default()))).map(|(root,native,_)|(root,native))
    }
    /// SAME first-produced root plus constructor DATA. Empty facts cannot
    /// certify implicit-new argument presence, and cached unissued products
    /// never trigger a producer/reparse/upgrade.
    pub fn obtain_with_original_products(
      &self,ordinal:usize,count:usize,a:&SettingAdmission<'_>,
      produce:impl FnOnce()->Result<(SettingExpression,Option<crate::NativeExpressionParserFacts>,crate::OriginalSettingProducts),SettingSyntaxFailure>,
    )->Result<(SettingExpression,Option<crate::NativeExpressionParserFacts>,crate::OriginalSettingProducts),SettingSyntaxFailure>{
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
            return Ok((root.clone(),ready.native.facts(Some(root.original_expression().span)),crate::OriginalSettingProducts::from_slot(ready.constructors.clone(),root.original_expression().span,ready.native.original_value_complete())));
        }
        let(root,facts,products)=produce()?;
        if !root.is_retained_in(a) || root.current_offset() != 0 {
            return Err(denied(
                a,
                io::ErrorKind::InvalidInput,
                "unissued storage cannot populate native setting slot",
            ));
        }
        if facts.is_some_and(|f|(f.is_complete()&&f.complete_span()!=Some(root.original_expression().span))||f.complete_span().is_some_and(|span|span!=root.original_expression().span)){return Err(denied(a,io::ErrorKind::InvalidInput,"native slot observation differs from its actual produced root"))}
        if !products.constructors().is_admitted_by(a)||products.constructors().as_slice().iter().any(|row|row.span().start<root.original_expression().span.start||row.span().end>root.original_expression().span.end){return Err(denied(a,io::ErrorKind::InvalidInput,"constructor DATA differs from actual root resource/extent"))}
        page.insert(local,&root,facts,products.clone(),a)?;
        Ok((root,facts,products))
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
                        allocation(group.roots.as_ptr() as usize,group.roots.len()*size_of::<Option<(crate::Span,Ready)>>(),group.roots.capacity()*size_of::<Option<(crate::Span,Ready)>>());
                        for (_,value) in group.roots.iter().flatten(){root(&value.root);value.constructors.visit_storage(|p,n,cap|allocation(p,n,cap));}
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
                        value.constructors.visit_storage(|p,n,cap|allocation(p,n,cap));
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

// Native ordinary Code/Input demand uses this SAME mask/rank/funded-row
// mechanism. Empty pages contain no Arc payload. This is only storage; it
// cannot issue syntax/source/completion or choose a different admission domain.
fn ordinal_denied(a:&SettingAdmission<'_>,kind:io::ErrorKind,message:&'static str)->io::Error{a.record_operational_error(io::Error::new(kind,message));kind.into()}
fn ordinal_rows<T>(capacity:usize,fixed:usize,a:&SettingAdmission<'_>)->io::Result<(Vec<T>,SettingRootLease)>{match funded_rows(capacity,fixed,a){Ok(rows)=>Ok(rows),Err(SettingSyntaxFailure::Operational(actual))=>Err(actual),Err(SettingSyntaxFailure::Syntax(_))=>Err(ordinal_denied(a,io::ErrorKind::InvalidData,"storage allocator returned an impossible grammar failure"))}}
#[derive(Debug)]
pub enum OrdinalSlotFailure<E>{Admission(io::Error),Value(E)}
struct OrdinalPage<T>{mask:[u64;ROOT_PAGE_LEN/ROOT_WORD_BITS],values:Vec<std::sync::Arc<T>>,credit:Option<SettingRootLease>}
impl<T> Default for OrdinalPage<T>{fn default()->Self{Self{mask:[0;ROOT_PAGE_LEN/ROOT_WORD_BITS],values:Vec::new(),credit:None}}}
impl<T> OrdinalPage<T>{
 fn position(&self,local:usize)->(usize,bool){let word=local/ROOT_WORD_BITS;let bit=1u64<<(local%ROOT_WORD_BITS);let before=self.mask[..word].iter().map(|w|w.count_ones()).sum::<u32>();((before+(self.mask[word]&(bit-1)).count_ones())as usize,self.mask[word]&bit!=0)}
}
struct OrdinalStorage<T>{count:usize,pages:Vec<OrdinalPage<T>>,metadata:SettingRootLease}
/// Only a caller with an actual existing SettingAdmission can create this
/// sparse owner. Its own Arc/fixed containing bytes and all later buffers are
/// funded BEFORE allocation, under the SAME counter. Payloads precede leases.
pub struct AdmittedOrdinalSlots<T>{state:Mutex<Option<OrdinalStorage<T>>>,allocation:SettingRootLease}
impl<T> std::fmt::Debug for AdmittedOrdinalSlots<T>{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("AdmittedOrdinalSlots").finish_non_exhaustive()}}
impl<T> AdmittedOrdinalSlots<T>{
 pub fn new_shared(a:&SettingAdmission<'_>,fixed_containing_bytes:usize)->Result<std::sync::Arc<Self>,io::Error>{
  a.checkpoint()?;
  let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<Self>()).map_err(|_|ordinal_denied(a,io::ErrorKind::OutOfMemory,"ordinal slot owner layout overflow"))?;
  let bytes=layout.pad_to_align().size().checked_add(fixed_containing_bytes).ok_or_else(||ordinal_denied(a,io::ErrorKind::OutOfMemory,"ordinal slot fixed storage overflow"))?;
  let allocation=a.reserve(bytes)?;
  Ok(std::sync::Arc::new(Self{state:Mutex::new(None),allocation}))
 }
 /// Cache-admission observation only: no allocation, query, parser or I/O.
 /// None means no witnessed issued row; it is not an empty semantic result.
 pub fn issued(&self,ordinal:usize)->Option<std::sync::Arc<T>>{
  let guard=self.state.try_lock().ok()?;let storage=guard.as_ref()?;if ordinal>=storage.count{return None}let page=&storage.pages[ordinal/ROOT_PAGE_LEN];let(rank,occupied)=page.position(ordinal%ROOT_PAGE_LEN);occupied.then(||std::sync::Arc::clone(&page.values[rank]))
 }
 /// Genuine source binding only: wait for the short allocator publication,
 /// never mint/query/poll under the mutex, and preserve poison as operational.
 /// Cache-admission callers must keep using the conservative issued() peek.
 pub fn issued_for_binding(&self,ordinal:usize)->io::Result<Option<std::sync::Arc<T>>>{
  let guard=self.state.lock().map_err(|_|io::Error::new(io::ErrorKind::Other,"ordinal source-binding storage poisoned"))?;
  let Some(storage)=guard.as_ref()else{return Ok(None)};if ordinal>=storage.count{return Ok(None)}let page=&storage.pages[ordinal/ROOT_PAGE_LEN];let(rank,occupied)=page.position(ordinal%ROOT_PAGE_LEN);Ok(occupied.then(||std::sync::Arc::clone(&page.values[rank])))
 }
 pub fn issued_count(&self)->io::Result<usize>{let state=self.state.try_lock().map_err(|_|io::Error::new(io::ErrorKind::WouldBlock,"ordinal slot count already borrowed or poisoned"))?;Ok(state.as_ref().map_or(0,|s|s.pages.iter().map(|p|p.values.len()).sum()))}
 /// Caller must not query/parse/reenter this table from create. The real
 /// value constructor runs once while the paid page remains unpublished.
 pub fn get_or_create<E>(&self,count:usize,ordinal:usize,a:&SettingAdmission<'_>,create:impl FnOnce()->Result<std::sync::Arc<T>,E>)->Result<std::sync::Arc<T>,OrdinalSlotFailure<E>>{
  let admission=|error|OrdinalSlotFailure::Admission(error);
  a.checkpoint().map_err(admission)?;
  if ordinal>=count||!a.matches_lease_domain(&self.allocation){return Err(admission(ordinal_denied(a,io::ErrorKind::InvalidInput,"ordinal slot source count/domain differs")))}
  let mut guard=self.state.lock().map_err(|_|admission(ordinal_denied(a,io::ErrorKind::Other,"ordinal slot table poisoned")))?;
  // Serialize legitimate same/different-ordinal workers. The constructor is
  // short and must not parse/query/reenter slots. Recheck cancellation/first IO
  // after waiting, before reading a warm row or allocating any backing.
  a.checkpoint().map_err(admission)?;
  if guard.is_none(){let pages=count.div_ceil(ROOT_PAGE_LEN);let(mut directory,metadata)=ordinal_rows(pages,0,a).map_err(admission)?;directory.resize_with(pages,OrdinalPage::default);*guard=Some(OrdinalStorage{count,pages:directory,metadata});}
  let storage=guard.as_mut().expect("initialized admitted ordinal slots");
  if storage.count!=count||!a.matches_lease_domain(&storage.metadata){return Err(admission(ordinal_denied(a,io::ErrorKind::InvalidInput,"ordinal slot count/storage domain differs")))}
  let page=&mut storage.pages[ordinal/ROOT_PAGE_LEN];let local=ordinal%ROOT_PAGE_LEN;let(rank,occupied)=page.position(local);
  if occupied{return Ok(std::sync::Arc::clone(&page.values[rank]))}
  let replacement=if page.values.len()==page.values.capacity(){let cap=page.values.capacity().checked_mul(2).map(|n|n.max(1)).filter(|n|*n<=ROOT_PAGE_LEN).ok_or_else(||admission(ordinal_denied(a,io::ErrorKind::OutOfMemory,"ordinal slot occupied capacity overflow")))?;Some(ordinal_rows(cap,0,a).map_err(admission)?)}else{None};
  let value=create().map_err(OrdinalSlotFailure::Value)?;
  a.checkpoint().map_err(admission)?;
  if let Some((mut values,credit))=replacement{values.append(&mut page.values);drop(std::mem::replace(&mut page.values,values));page.credit=Some(credit);}
  page.values.insert(rank,std::sync::Arc::clone(&value));page.mask[local/ROOT_WORD_BITS]|=1u64<<(local%ROOT_WORD_BITS);Ok(value)
 }
 /// Only borrowed rows are visited. Callback must not query/reenter slots.
 pub fn visit_issued(&self,visit:&mut dyn FnMut(usize,&std::sync::Arc<T>))->Result<(),io::Error>{let guard=self.state.lock().map_err(|_|io::Error::new(io::ErrorKind::Other,"ordinal slot census poisoned"))?;if let Some(storage)=guard.as_ref(){for(page_no,page)in storage.pages.iter().enumerate(){let mut rank=0;for local in 0..ROOT_PAGE_LEN{if page.mask[local/ROOT_WORD_BITS]&(1u64<<(local%ROOT_WORD_BITS))!=0{visit(page_no*ROOT_PAGE_LEN+local,&page.values[rank]);rank+=1;}}}}Ok(())}
 pub fn visit_storage(&self,visit:&mut dyn FnMut(usize,usize,usize))->Result<(),io::Error>{
  let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<Self>()).expect("admitted ordinal owner layout");visit(self as *const Self as usize,size_of::<Self>(),layout.pad_to_align().size());self.allocation.visit_counter_storage(|p,n|visit(p,n,n));
  let guard=self.state.lock().map_err(|_|io::Error::new(io::ErrorKind::Other,"ordinal slot census poisoned"))?;
  if let Some(storage)=guard.as_ref(){let bytes=storage.pages.capacity()*size_of::<OrdinalPage<T>>();visit(storage.pages.as_ptr()as usize,bytes,bytes);storage.metadata.visit_counter_storage(|p,n|visit(p,n,n));for page in &storage.pages{let bytes=page.values.capacity()*size_of::<std::sync::Arc<T>>();visit(page.values.as_ptr()as usize,bytes,bytes);if let Some(credit)=&page.credit{credit.visit_counter_storage(|p,n|visit(p,n,n));}}}Ok(())
 }
}

#[cfg(test)]mod native_ordinal_slot_controls{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 struct Value{number:usize,_credit:SettingRootLease}
 fn value(a:&SettingAdmission<'_>,number:usize)->io::Result<Arc<Value>>{let(layout,_)=std::alloc::Layout::new::<[AtomicUsize;2]>().extend(std::alloc::Layout::new::<Value>()).unwrap();let credit=a.reserve(layout.pad_to_align().size())?;Ok(Arc::new(Value{number,_credit:credit}))}
 #[test]fn actual_sparse_ordinal_same_counter_two_workers_coalesce_one_constructor_and_refund(){
  let root=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(root).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&counter,4<<20,&poll);let slots=AdmittedOrdinalSlots::<Value>::new_shared(&a,0).unwrap();
  let ctors=AtomicUsize::new(0);let(entered_tx,entered_rx)=std::sync::mpsc::channel();let(release_tx,release_rx)=std::sync::mpsc::channel();let(started_tx,started_rx)=std::sync::mpsc::channel();let(done_tx,done_rx)=std::sync::mpsc::channel();
  let(first,second)=std::thread::scope(|scope|{
   let counter=&counter;let slots=&slots;let ctors=&ctors;
   let first=scope.spawn(move||{let poll=||Ok(());let a=SettingAdmission::new(counter,4<<20,&poll);slots.get_or_create(513,256,&a,||{ctors.fetch_add(1,Ordering::AcqRel);assert!(slots.issued(256).is_none(),"fallible creator cannot publish early");entered_tx.send(()).unwrap();release_rx.recv_timeout(std::time::Duration::from_secs(5)).unwrap();value(&a,17)}).unwrap()});
   entered_rx.recv_timeout(std::time::Duration::from_secs(5)).unwrap();
   let second=scope.spawn(move||{let poll=||Ok(());let a=SettingAdmission::new(counter,4<<20,&poll);started_tx.send(()).unwrap();let answer=slots.get_or_create(513,256,&a,||{ctors.fetch_add(1,Ordering::AcqRel);value(&a,99)});done_tx.send(()).unwrap();answer.unwrap()});
   started_rx.recv_timeout(std::time::Duration::from_secs(5)).unwrap();assert!(done_rx.recv_timeout(std::time::Duration::from_millis(20)).is_err(),"legitimate concurrent admission serializes rather than sticky WouldBlock");release_tx.send(()).unwrap();(first.join().unwrap(),second.join().unwrap())
  });
  assert_eq!(ctors.load(Ordering::Acquire),1);assert_eq!(slots.issued_count().unwrap(),1);assert_eq!(first.number,17);assert!(Arc::ptr_eq(&first,&second));
  let value_bytes={let(layout,_)=std::alloc::Layout::new::<[AtomicUsize;2]>().extend(std::alloc::Layout::new::<Value>()).unwrap();layout.pad_to_align().size()};
  drop(slots);assert_eq!(counter.load(Ordering::Acquire),root+value_bytes,"real returned alias keeps only its own actual allocation grant");drop(first);drop(second);assert_eq!(counter.load(Ordering::Acquire),root);
 }
 #[test]fn actual_sparse_ordinal_old_new_growth_denial_keeps_rows_first_io_domain_and_recovery(){
  let root=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(root).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&counter,4<<20,&poll);let slots=AdmittedOrdinalSlots::<Value>::new_shared(&a,0).unwrap();
  let first=slots.get_or_create(256,0,&a,||value(&a,1)).unwrap();let second=slots.get_or_create(256,1,&a,||value(&a,2)).unwrap();let before=counter.load(Ordering::Acquire);
  let tight=SettingAdmission::new(&counter,before+4*size_of::<Arc<Value>>()-1,&poll);let touched=std::cell::Cell::new(false);let error=slots.get_or_create(256,2,&tight,||{touched.set(true);value(&tight,3)}).err().unwrap();assert!(matches!(error,OrdinalSlotFailure::Admission(ref actual)if actual.kind()==io::ErrorKind::OutOfMemory));assert!(!touched.get());assert_eq!(slots.issued_count().unwrap(),2);assert_eq!(counter.load(Ordering::Acquire),before,"denied replacement cannot move/refund old backing");assert!(slots.issued(2).is_none());
  let fresh=SettingAdmission::new(&counter,4<<20,&poll);let error=slots.get_or_create(256,2,&fresh,||->io::Result<Arc<Value>>{fresh.record_operational_error(io::Error::from_raw_os_error(1450));Err(io::ErrorKind::Other.into())}).err().unwrap();assert!(matches!(error,OrdinalSlotFailure::Value(_)));assert_eq!(fresh.take_operational_error().unwrap().raw_os_error(),Some(1450));assert!(slots.issued(2).is_none());assert_eq!(counter.load(Ordering::Acquire),before);
  let healthy=SettingAdmission::new(&counter,4<<20,&poll);let third=slots.get_or_create(256,2,&healthy,||value(&healthy,3)).unwrap();assert_eq!(third.number,3);assert!(Arc::ptr_eq(&slots.issued(0).unwrap(),&first));assert!(Arc::ptr_eq(&slots.issued(1).unwrap(),&second));
  let foreign=crate::SettingChargeCounter::try_new(root).unwrap();let other=SettingAdmission::new(&foreign,4<<20,&poll);let error=slots.get_or_create(256,0,&other,||value(&other,999)).err().unwrap();assert!(matches!(error,OrdinalSlotFailure::Admission(ref actual)if actual.kind()==io::ErrorKind::InvalidInput));assert_eq!(foreign.load(Ordering::Acquire),root);
  drop((first,second,third,slots));assert_eq!(counter.load(Ordering::Acquire),root);
 }
}

#[cfg(test)]mod ordinal_semantic_binding_controls{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 struct Value{number:usize,_credit:SettingRootLease}
 fn value(a:&SettingAdmission<'_>,number:usize)->io::Result<Arc<Value>>{let(layout,_)=std::alloc::Layout::new::<[AtomicUsize;2]>().extend(std::alloc::Layout::new::<Value>()).unwrap();let credit=a.reserve(layout.pad_to_align().size())?;Ok(Arc::new(Value{number,_credit:credit}))}
 #[test]fn actual_binding_waits_for_publication_while_other_ordinal_serializes_without_false_absence(){
  let root=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(root).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&counter,4<<20,&poll);let slots=AdmittedOrdinalSlots::<Value>::new_shared(&a,0).unwrap();let initial=slots.get_or_create(513,0,&a,||value(&a,1)).unwrap();
  let(entered_tx,entered_rx)=std::sync::mpsc::channel();let(release_tx,release_rx)=std::sync::mpsc::channel();let(bind_started_tx,bind_started_rx)=std::sync::mpsc::channel();let(bind_done_tx,bind_done_rx)=std::sync::mpsc::channel();let(other_started_tx,other_started_rx)=std::sync::mpsc::channel();let(other_done_tx,other_done_rx)=std::sync::mpsc::channel();
  let(first,bound,other)=std::thread::scope(|scope|{
   let slots=&slots;let counter=&counter;
   let first=scope.spawn(move||{let poll=||Ok(());let a=SettingAdmission::new(counter,4<<20,&poll);slots.get_or_create(513,256,&a,||{entered_tx.send(()).unwrap();release_rx.recv_timeout(std::time::Duration::from_secs(5)).unwrap();value(&a,2)}).unwrap()});entered_rx.recv_timeout(std::time::Duration::from_secs(5)).unwrap();
   assert!(slots.issued(0).is_none(),"pure cache admission may conservatively miss while actual storage is borrowed");
   let binding=scope.spawn(move||{bind_started_tx.send(()).unwrap();let row=slots.issued_for_binding(0).unwrap().expect("semantic binding must observe the real published row");bind_done_tx.send(()).unwrap();row});
   let other=scope.spawn(move||{let poll=||Ok(());let a=SettingAdmission::new(counter,4<<20,&poll);other_started_tx.send(()).unwrap();let row=slots.get_or_create(513,512,&a,||value(&a,3)).unwrap();other_done_tx.send(()).unwrap();row});
   bind_started_rx.recv_timeout(std::time::Duration::from_secs(5)).unwrap();other_started_rx.recv_timeout(std::time::Duration::from_secs(5)).unwrap();assert!(bind_done_rx.recv_timeout(std::time::Duration::from_millis(20)).is_err());assert!(other_done_rx.recv_timeout(std::time::Duration::from_millis(20)).is_err());release_tx.send(()).unwrap();(first.join().unwrap(),binding.join().unwrap(),other.join().unwrap())
  });
  assert!(Arc::ptr_eq(&initial,&bound));assert_eq!((initial.number,first.number,other.number),(1,2,3));assert_eq!(slots.issued_count().unwrap(),3);drop((initial,first,bound,other,slots));assert_eq!(counter.load(Ordering::Acquire),root);
 }
 #[test]fn actual_poisoned_binding_is_operational_error_and_never_semantic_none(){
  let root=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(root).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&counter,4<<20,&poll);let slots=AdmittedOrdinalSlots::<Value>::new_shared(&a,0).unwrap();
  let failed=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{let _:Result<Arc<Value>,OrdinalSlotFailure<io::Error>>=slots.get_or_create(1,0,&a,||panic!("actual failed creator poisons only its owned table"));}));assert!(failed.is_err());assert!(slots.issued(0).is_none());let actual=slots.issued_for_binding(0).err().expect("semantic reader must retain the operational poison error");assert_eq!(actual.kind(),io::ErrorKind::Other);drop(slots);assert_eq!(counter.load(Ordering::Acquire),root);
 }
}
