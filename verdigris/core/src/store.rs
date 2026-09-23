//! A component kind's whole store (`rust_architecture.md` §4.2): entity-row
//! storage behind a [`MainPort`] (read-your-writes, R4), plus the row
//! allocator and the row→entity back-map events need. Generic over any
//! [`Domain`], so a component kind's generated FFI glue needs only one of
//! these — not its own `Sim`, `CellAllocator` and event queue, which used to
//! be hand-written per kind (`kind/pump.rs`'s old `World`).
//!
//! **Owner.** The same store and the same generated API serve both owners
//! (§4.2):
//! - `owner = worker`: registered with the driver's `Sim` and ticked every
//!   frame (physics laws read and write its rows there).
//! - `owner = main`: never ticked. Nothing ever ages its overlay, so every
//!   read reflects every earlier write with no staleness window at all —
//!   which is exactly "DM reads and writes it immediately, with no frame."
//!
//! A kind chooses by calling [`KindStore::tick`] every frame (worker) or
//! never (main); nothing else about the type differs.

use crate::cow::ChunkLayout;
use crate::entity::CellAllocator;
use crate::owner::{Applied, Domain, DomainKey, PortError};
use crate::sim::{Sim, SimBuilder, SimConfig};

/// Row capacity: matches [`crate::entity::MAX_SLOTS`], since a store never
/// needs to outlive the entities that could reference it.
const ROWS: u32 = crate::entity::MAX_SLOTS;

/// A component kind's store. See the module docs for `owner`.
pub struct KindStore<D: Domain> {
    sim: Sim,
    key: DomainKey<D>,
    rows: CellAllocator,
    /// The `vg_entity` (raw-plus-one; see `vg-ffi::entity`) bound at each
    /// row, so a law that only knows a row can still attribute an event to
    /// the right atom (§4.8). `None` for a free or never-allocated row.
    row_entity: Vec<Option<f32>>,
    /// Raised events not yet drained, as `(entity, event_id)` (§4.8).
    events: Vec<(f32, u8)>,
}

impl<D: Domain> Default for KindStore<D> {
    fn default() -> Self {
        Self::new()
    }
}

impl<D: Domain> KindStore<D> {
    /// A fresh, empty store. `threads` is the frame pool size for this
    /// kind's `Sim`; worker-owned kinds pass what their laws need (at least
    /// 1), main-owned kinds that never call [`tick`](Self::tick) can pass 1
    /// (the pool sits idle).
    #[must_use]
    pub fn new() -> Self {
        Self::with_threads(1)
    }

    #[must_use]
    pub fn with_threads(threads: usize) -> Self {
        let mut builder = SimBuilder::new(SimConfig {
            threads: threads.max(1),
            ..SimConfig::default()
        });
        let key = builder.add_domain::<D>(ChunkLayout::linear(ROWS));
        let sim = builder
            .build()
            .unwrap_or_else(|e| unreachable!("static kind store config always builds: {e}"));
        Self {
            sim,
            key,
            rows: CellAllocator::new(),
            row_entity: Vec::new(),
            events: Vec::new(),
        }
    }

    /// Allocates a row, seeds it with `value`, and records `entity` as the
    /// row's owner for event attribution. Returns the row.
    pub fn bind(&mut self, entity: f32, value: D::Value) -> Result<u32, PortError> {
        let row = self.rows.alloc();
        self.sim.port(self.key).put(row, value)?;
        self.set_row_entity(row, entity);
        Ok(row)
    }

    fn set_row_entity(&mut self, row: u32, entity: f32) {
        let index = row as usize;
        if self.row_entity.len() <= index {
            self.row_entity.resize(index + 1, None);
        }
        self.row_entity[index] = Some(entity);
    }

    /// What DM sees at `row` right now (this tick's writes over the pinned
    /// frame, R4 §6).
    #[must_use]
    pub fn read(&self, row: u32) -> Option<D::Value> {
        self.sim.port_ref(self.key).read(row)
    }

    /// Queues a command; applies to what DM sees immediately.
    ///
    /// # Errors
    /// If `row` is out of range.
    pub fn submit(&mut self, row: u32, cmd: D::Command) -> Result<Applied, PortError> {
        self.sim.port(self.key).submit(row, cmd)
    }

    /// Frees `row`: resets its value and returns the row for reuse.
    pub fn detach(&mut self, row: u32) {
        let _ = self.sim.port(self.key).take(row);
        self.rows.free_cell(row);
        if let Some(slot) = self.row_entity.get_mut(row as usize) {
            *slot = None;
        }
    }

    /// Raises `event_id` for the component at `row` (§4.8), attributed to
    /// whatever entity is currently bound there. A no-op if the row holds no
    /// live component (already detached): nothing left to notify.
    pub fn push_event(&mut self, row: u32, event_id: u8) {
        if let Some(entity) = self.row_entity.get(row as usize).copied().flatten() {
            self.events.push((entity, event_id));
        }
    }

    /// Moves every raised-and-not-yet-drained event into `out`, as
    /// `(entity, event_id)`.
    pub fn drain_events(&mut self, out: &mut Vec<(f32, u8)>) {
        out.append(&mut self.events);
    }

    /// Advances this store's `Sim` by one tick and dispatches a frame,
    /// publishing a view and pruning the overlay. Worker-owned kinds call
    /// this every frame; main-owned kinds never call it (module docs).
    pub fn tick(&mut self) {
        self.sim.begin_tick();
        self.sim.dispatch_frame();
    }

    /// The kind's `Sim`, for a domain that needs to add its own frame tasks
    /// (a worker-owned kind's laws) or watches beyond what this store alone
    /// provides.
    pub fn sim_mut(&mut self) -> &mut Sim {
        &mut self.sim
    }

    #[must_use]
    pub const fn key(&self) -> DomainKey<D> {
        self.key
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::owner::Applied;

    #[derive(Clone, Copy, Debug, Default, PartialEq)]
    struct Widget {
        n: f32,
    }

    #[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
    struct WidgetKind;

    #[derive(Clone, Debug, PartialEq)]
    enum WidgetCmd {
        Set(i32),
    }

    impl Domain for WidgetKind {
        type Value = Widget;
        type Command = WidgetCmd;
        const NAME: &'static str = "widget";
        fn apply(value: &mut Widget, cmd: &WidgetCmd) -> Applied {
            let WidgetCmd::Set(v) = cmd;
            #[allow(clippy::cast_precision_loss)]
            {
                value.n = *v as f32;
            }
            Applied::default()
        }
    }

    #[test]
    fn bind_read_write_detach_and_events_round_trip() {
        let mut store = KindStore::<WidgetKind>::new();
        let row = store.bind(42.0, Widget { n: 1.0 }).unwrap();
        assert_eq!(store.read(row), Some(Widget { n: 1.0 }));

        store.submit(row, WidgetCmd::Set(9)).unwrap();
        assert_eq!(store.read(row), Some(Widget { n: 9.0 }), "read-your-writes, no tick needed");

        store.push_event(row, 3);
        let mut out = Vec::new();
        store.drain_events(&mut out);
        assert_eq!(out, vec![(42.0, 3)]);

        store.detach(row);
        assert_eq!(store.read(row), Some(Widget::default()));
        store.push_event(row, 1);
        let mut out2 = Vec::new();
        store.drain_events(&mut out2);
        assert!(out2.is_empty(), "a detached row's event must not resurrect the old entity");

        // A never-ticked (main-owned) store still has no staleness window.
        let row2 = store.bind(7.0, Widget::default()).unwrap();
        store.submit(row2, WidgetCmd::Set(5)).unwrap();
        assert_eq!(store.read(row2).unwrap().n, 5.0);
    }

    #[test]
    fn worker_owned_kind_ticks_and_publishes_a_view() {
        let mut store = KindStore::<WidgetKind>::new();
        let row = store.bind(1.0, Widget::default()).unwrap();
        store.submit(row, WidgetCmd::Set(3)).unwrap();
        store.tick();
        store.tick();
        assert_eq!(store.read(row).unwrap().n, 3.0);
    }
}
