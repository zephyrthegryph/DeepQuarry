//! Single-item diagnostic scopes never query CPU or process I/O clocks.
use super::*;
thread_local! { static ITEMS: RefCell<Vec<&'static str>> = const { RefCell::new(Vec::new()) }; }
pub struct ItemGuard {
    state: Option<Arc<State>>,
    name: &'static str,
    start: Instant,
    allocations: u64,
    bytes: u64,
    prior_peak: u64,
    aggregate: bool,
    entered: Option<tracing::span::EnteredSpan>,
    thread_bound: PhantomData<Rc<()>>,
}
pub fn item(name: &'static str) -> ItemGuard {
    item_with_state(name, request::active_state())
}
fn item_with_state(name: &'static str, state: Option<Arc<State>>) -> ItemGuard {
    let mut value = ItemGuard {
        state,
        name,
        start: Instant::now(),
        allocations: 0,
        bytes: 0,
        prior_peak: 0,
        aggregate: true,
        entered: None,
        thread_bound: PhantomData,
    };
    if let Some(state) = &value.state {
        value.aggregate = ITEMS.with(|stack| {
            let mut stack = stack.borrow_mut();
            let outermost = !stack.contains(&name);
            stack.push(name);
            outermost
        });
        memory::enter(state, name);
        (value.allocations, value.bytes, _) = allocator::snapshot();
        value.prior_peak = allocator::reset_peak();
        value.entered = Some(
            tracing::info_span!(
                "compiler_item",
                stage = name,
                cpu_measurement = "wall_allocations_only",
                allocated_bytes = tracing::field::Empty,
                allocations = tracing::field::Empty,
                peak_live_bytes = tracing::field::Empty
            )
            .entered(),
        );
    }
    value
}
impl Drop for ItemGuard {
    fn drop(&mut self) {
        let Some(state) = &self.state else {
            return;
        };
        ITEMS.with(|stack| {
            stack.borrow_mut().pop();
        });
        let (allocations, bytes, _) = allocator::snapshot();
        let peak = allocator::restore_peak(self.prior_peak);
        let mut entries = state
            .entries
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let entry = entries.entry(self.name).or_default();
        entry.active = entry.active.saturating_sub(1);
        entry.report.name = self.name.into();
        entry.report.calls += 1;
        if self.aggregate {
            entry.report.wall_s += self.start.elapsed().as_secs_f64();
            entry.report.allocations += allocations.saturating_sub(self.allocations);
            entry.report.allocated_bytes += bytes.saturating_sub(self.bytes);
        }
        entry.report.peak_live_bytes = entry.report.peak_live_bytes.max(peak);
        if let Some(span) = self.entered.take() {
            span.record("allocated_bytes", bytes.saturating_sub(self.bytes));
            span.record("allocations", allocations.saturating_sub(self.allocations));
            span.record("peak_live_bytes", peak);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn item_scope_leaves_cpu_parent_boundaries_and_clock_validity_untouched() {
        let state = Arc::new(State {
            calibration: clock::calibrate(),
            io_wait: io_wait::Ledger::default(),
            entries: Mutex::new(BTreeMap::new()),
            folded: Mutex::new(BTreeMap::new()),
            wall_folded: Mutex::new(BTreeMap::new()),
            finished: std::sync::atomic::AtomicBool::new(false),
            workers: std::sync::atomic::AtomicUsize::new(0),
            bindings: std::sync::atomic::AtomicUsize::new(0),
            dispatch: Mutex::new(None),
        });
        let wall = Instant::now();
        STACK.with(|stack| {
            stack.borrow_mut().push(Frame {
                name: "parent",
                last_cpu: Some(123),
                last_coarse_cpu: Some(123),
                last_wall: wall,
            })
        });
        {
            let _item = item_with_state("one_procedure", Some(Arc::clone(&state)));
        }
        STACK.with(|stack| {
            let frame = stack.borrow_mut().pop().unwrap();
            assert_eq!(frame.last_cpu, Some(123));
            assert_eq!(frame.last_coarse_cpu, Some(123));
            assert_eq!(frame.last_wall, wall);
        });
        let entries = state.entries.lock().unwrap();
        let entry = &entries["one_procedure"];
        assert_eq!(entry.report.calls, 1);
        assert!(!entry.cpu_stage && !entry.cpu_valid && !entry.cpu_missing);
        assert!(entry.intervals.is_empty() && entry.exclusive_intervals.is_empty());
        assert!(entry.report.cpu_s.is_none() && entry.report.cpu_bounds_s.is_none());
    }
}
