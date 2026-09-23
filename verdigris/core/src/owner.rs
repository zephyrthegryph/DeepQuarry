//! Owners, views, the overlay path and scratch values (`rust_core.md`
//! §3.1–§3.5, §3.10, §3.11).
//!
//! A [`Domain`] owns a per-cell store. Its state is split in two:
//! - [`DomainState`], the single writer, lives in the frame world and is
//!   only touched by frame tasks on the worker pool;
//! - [`MainPort`], the DM-facing side, lives on the main thread. It queues
//!   commands, keeps the overlay, and pins the newest published [`View`].
//!
//! The two sides share nothing but an atomic single-slot mailbox
//! ([`Latest`]) that carries each new view from worker to main, and the
//! command batch the main thread moves into the idle world at dispatch.
//! `MainPort` is `!Sync` and holds no lock, so every DM-facing call
//! (read, submit, pin) is lock-free by construction.

use std::any::Any;
use std::cell::Cell;
use std::collections::VecDeque;
use std::fmt;
use std::marker::PhantomData;
use std::sync::Arc;

use crate::arena::{Arena, ArenaError};
use crate::command::{CommandBuffer, Op, Seq, Sequenced};
use crate::cow::{ChunkLayout, CowStore};
use crate::frame::{Res, TaskCtx};
use crate::slot::Handle;
use crate::mailbox::Latest;
use crate::outbox::{Outbox, OutboxSlot, TakeResult};
use crate::overlay::{CellMap, Overlay};

/// A simulation domain: the value type of one cell and the commands DM can
/// send it. The physics lives in frame tasks; this trait only fixes how a
/// command changes one cell, which both the worker and the overlay use, so
/// the overlay can never disagree with the owner about a command's effect.
pub trait Domain: 'static {
    type Value: Clone + Default + PartialEq + fmt::Debug + Send + Sync + 'static;
    type Command: Clone + fmt::Debug + Send + Sync + 'static;
    const NAME: &'static str;

    /// Applies `cmd` to `value`. Must be deterministic. A removal that finds
    /// less than it asked for clamps and reports the shortfall (§3.10).
    fn apply(value: &mut Self::Value, cmd: &Self::Command) -> Applied;
}

/// The operation type queued for domain `D`.
pub type DomainOp<D> = Op<<D as Domain>::Value, <D as Domain>::Command>;

/// The result of applying one command.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Applied {
    /// How much of a removal could not be satisfied (domain units).
    pub shortfall: f32,
}

/// Applies an [`Op`] the way both the worker and the overlay do.
pub fn apply_op<D: Domain>(value: &mut D::Value, op: &DomainOp<D>) -> Applied {
    match op {
        Op::Put(v) => {
            value.clone_from(v);
            Applied::default()
        }
        Op::Take => {
            *value = D::Value::default();
            Applied::default()
        }
        Op::Apply(cmd) => D::apply(value, cmd),
    }
}

/// Who writes an entity (§3.1). Ownership moves by command: `Put` into a
/// domain transfers an entity in, `Take` transfers it out as a [`Scratch`]
/// value that DM can keep or promote to a main-owned slot.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Owner {
    /// The main thread: DM reads and writes it synchronously.
    Main,
    /// A domain's worker, by domain index.
    Domain(usize),
}

/// A typed key for a registered domain.
pub struct DomainKey<D: Domain> {
    pub(crate) index: usize,
    pub(crate) state: Res<DomainState<D>>,
}

impl<D: Domain> DomainKey<D> {
    /// The domain's index (its [`Owner::Domain`] number).
    #[must_use]
    pub const fn index(self) -> usize {
        self.index
    }

    /// The worker-side state, for declaring and accessing it in tasks.
    #[must_use]
    pub const fn state(self) -> Res<DomainState<D>> {
        self.state
    }

    #[must_use]
    pub const fn owner(self) -> Owner {
        Owner::Domain(self.index)
    }
}

impl<D: Domain> Clone for DomainKey<D> {
    fn clone(&self) -> Self {
        *self
    }
}
impl<D: Domain> Copy for DomainKey<D> {}
impl<D: Domain> fmt::Debug for DomainKey<D> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "DomainKey<{}>({})", D::NAME, self.index)
    }
}

/// An immutable snapshot of a domain after a frame (§3.3). Shares every
/// unchanged chunk with the live store and with older views.
#[derive(Clone, Debug)]
pub struct View<V> {
    store: CowStore<V>,
    version: u64,
    applied_through: Seq,
    shortfall_total: f64,
}

impl<V: Clone + Default> View<V> {
    /// The empty view every port pins before the first frame.
    #[must_use]
    pub fn empty(layout: ChunkLayout) -> Self {
        Self {
            store: CowStore::new(layout),
            version: 0,
            applied_through: Seq(0),
            shortfall_total: 0.0,
        }
    }

    #[must_use]
    pub fn get(&self, cell: u32) -> Option<V> {
        self.store.get(cell)
    }

    #[must_use]
    pub fn store(&self) -> &CowStore<V> {
        &self.store
    }

    /// Frames published by this domain up to and including this view.
    #[must_use]
    pub const fn version(&self) -> u64 {
        self.version
    }

    /// The last command this view includes.
    #[must_use]
    pub const fn applied_through(&self) -> Seq {
        self.applied_through
    }

    /// Removal shortfall accumulated by the worker so far (§3.10).
    #[must_use]
    pub const fn shortfall_total(&self) -> f64 {
        self.shortfall_total
    }
}

/// The single writer of a domain: lives in the frame world, touched only by
/// frame tasks.
pub struct DomainState<D: Domain> {
    /// The live cells. Tasks declared as writers may change them freely.
    pub store: CowStore<D::Value>,
    pending: Vec<Sequenced<DomainOp<D>>>,
    applied_through: Seq,
    version: u64,
    shortfall_total: f64,
    views: Arc<Latest<Arc<View<D::Value>>>>,
    /// This frame's records (wakes, events, take results), published with
    /// the view.
    outbox: Outbox<D::Value>,
    outbox_slot: Arc<OutboxSlot<D::Value>>,
}

impl<D: Domain> DomainState<D> {
    pub(crate) fn new(
        layout: ChunkLayout,
        views: Arc<Latest<Arc<View<D::Value>>>>,
        outbox_slot: Arc<OutboxSlot<D::Value>>,
    ) -> Self {
        Self {
            store: CowStore::new(layout),
            pending: Vec::new(),
            applied_through: Seq(0),
            version: 0,
            shortfall_total: 0.0,
            views,
            outbox: Outbox::default(),
            outbox_slot,
        }
    }

    /// This frame's outbox, for tasks that emit domain events (§8).
    pub fn outbox_mut(&mut self) -> &mut Outbox<D::Value> {
        &mut self.outbox
    }

    /// The live store and the outbox at once (watch evaluation reads one
    /// and writes the other).
    pub fn store_and_outbox(&mut self) -> (&CowStore<D::Value>, &mut Outbox<D::Value>) {
        (&self.store, &mut self.outbox)
    }

    /// Applies every queued command in sequence order (§3.9). The built-in
    /// apply task calls this first thing each frame.
    pub fn apply_pending(&mut self) {
        debug_assert!(self.pending.windows(2).all(|w| w[0].seq < w[1].seq));
        for cmd in self.pending.drain(..) {
            let cell = self
                .store
                .get_mut(cmd.target)
                .expect("the port range-checks every command");
            if matches!(cmd.op, Op::Take) {
                // Transfer-out conserves: report exactly what was removed,
                // which may differ from what DM's pinned view showed (§3.10).
                self.outbox.push_take(TakeResult {
                    seq: cmd.seq,
                    cell: cmd.target,
                    value: cell.clone(),
                });
            }
            let applied = apply_op::<D>(cell, &cmd.op);
            self.shortfall_total += f64::from(applied.shortfall);
            self.applied_through = cmd.seq;
        }
    }

    #[must_use]
    pub const fn applied_through(&self) -> Seq {
        self.applied_through
    }

    pub(crate) fn enqueue(&mut self, batch: Vec<Sequenced<DomainOp<D>>>) {
        if self.pending.is_empty() {
            self.pending = batch;
        } else {
            self.pending.extend(batch);
        }
    }

    pub(crate) fn install(&mut self, store: CowStore<D::Value>) {
        self.store = store;
    }

    /// Publishes a view (§3.3) to the main thread and returns it type-erased
    /// for the next frame's exchange buffers.
    pub(crate) fn publish(any: &mut (dyn Any + Send + Sync)) -> Arc<dyn Any + Send + Sync> {
        let state = any
            .downcast_mut::<Self>()
            .expect("domain state type mismatch");
        state.version += 1;
        let view = Arc::new(View {
            store: state.store.snapshot(),
            version: state.version,
            applied_through: state.applied_through,
            shortfall_total: state.shortfall_total,
        });
        state.views.put(Arc::clone(&view));
        let mut outbox = std::mem::take(&mut state.outbox);
        outbox.stamp(state.version);
        state.outbox_slot.publish(outbox);
        view
    }
}

impl TaskCtx<'_> {
    /// Domain `key`'s view from the end of the previous frame: the exchange
    /// buffer coupled domains read instead of each other's live state (§3.6).
    #[must_use]
    pub fn prev_view<D: Domain>(&self, key: DomainKey<D>) -> Option<Arc<View<D::Value>>> {
        Arc::clone(self.prev_erased(key.index)?)
            .downcast::<View<D::Value>>()
            .ok()
    }
}

/// A value taken out of a domain for DM to inspect, react, breathe or merge
/// elsewhere (§3.5). It has no slot anywhere; drop it, hand it back with
/// [`MainPort::assume`], or keep it past the tick by promoting it to a
/// main-owned slot.
#[must_use]
#[derive(Clone, Debug, PartialEq)]
pub struct Scratch<V>(V);

impl<V> Scratch<V> {
    pub const fn new(value: V) -> Self {
        Self(value)
    }

    pub const fn get(&self) -> &V {
        &self.0
    }

    pub fn get_mut(&mut self) -> &mut V {
        &mut self.0
    }

    pub fn into_inner(self) -> V {
        self.0
    }

    /// Makes the value a main-owned entity (§3.1): DM reads and writes it
    /// synchronously through `arena`, with no staleness.
    ///
    /// # Errors
    /// If the arena is full.
    pub fn promote(self, arena: &mut Arena<V>) -> Result<Handle<V>, ArenaError> {
        arena.insert(self.0)
    }
}

/// A DM-facing error.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PortError {
    /// The cell index is outside the domain's layout.
    OutOfRange(u32),
}

impl fmt::Display for PortError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::OutOfRange(cell) => write!(f, "cell {cell} is outside the domain"),
        }
    }
}

impl std::error::Error for PortError {}

/// Main-thread state for the fallback path (§3.11): DM owns the live store,
/// frames simulate a snapshot and return deltas, and the main thread applies
/// them one piece (chunk) at a time within a budget, rejecting any piece DM
/// wrote since the snapshot.
struct Fallback<V> {
    live: CowStore<V>,
    /// The snapshot the in-flight frame started from.
    base: Option<CowStore<V>>,
    pieces: VecDeque<Vec<(u32, V)>>,
    written_since_dispatch: CellMap<()>,
    applied_pieces: u64,
    rejected_pieces: u64,
}

/// Fallback-path counters.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct FallbackStats {
    pub pending_pieces: usize,
    pub applied_pieces: u64,
    pub rejected_pieces: u64,
}

/// The DM-facing side of a domain. Main thread only (`!Sync`); no locks.
pub struct MainPort<D: Domain> {
    layout: ChunkLayout,
    commands: CommandBuffer<DomainOp<D>>,
    overlay: Overlay<D::Value>,
    pinned: Arc<View<D::Value>>,
    inbox: Arc<Latest<Arc<View<D::Value>>>>,
    outbox_inbox: Arc<OutboxSlot<D::Value>>,
    /// Outbox records collected at pin time and not yet drained.
    collected: Outbox<D::Value>,
    state: Res<DomainState<D>>,
    fallback: Option<Fallback<D::Value>>,
    ticks_since_view: u32,
    _main_thread_only: PhantomData<Cell<()>>,
}

impl<D: Domain> MainPort<D> {
    pub(crate) fn new(
        layout: ChunkLayout,
        inbox: Arc<Latest<Arc<View<D::Value>>>>,
        outbox_inbox: Arc<OutboxSlot<D::Value>>,
        state: Res<DomainState<D>>,
        fallback: bool,
    ) -> Self {
        Self {
            layout,
            commands: CommandBuffer::new(),
            overlay: Overlay::new(),
            pinned: Arc::new(View::empty(layout)),
            inbox,
            outbox_inbox,
            collected: Outbox::default(),
            state,
            fallback: fallback.then(|| Fallback {
                live: CowStore::new(layout),
                base: None,
                pieces: VecDeque::new(),
                written_since_dispatch: CellMap::default(),
                applied_pieces: 0,
                rejected_pieces: 0,
            }),
            ticks_since_view: 0,
            _main_thread_only: PhantomData,
        }
    }

    /// What DM sees at `cell` right now: its own writes this tick, else the
    /// pinned view (or, on the fallback path, the live store). `None` only
    /// outside the layout.
    #[must_use]
    pub fn read(&self, cell: u32) -> Option<D::Value> {
        if let Some(fb) = &self.fallback {
            return fb.live.get(cell);
        }
        match self.overlay.get(cell) {
            Some(v) => Some(v.clone()),
            None => self.pinned.get(cell),
        }
    }

    /// Queues a domain command and applies it to what DM sees immediately.
    ///
    /// # Errors
    /// If `cell` is outside the layout.
    pub fn submit(&mut self, cell: u32, cmd: D::Command) -> Result<Applied, PortError> {
        self.push(cell, Op::Apply(cmd))
    }

    /// Sets a cell (registration, or transferring an entity in, §3.1).
    ///
    /// # Errors
    /// If `cell` is outside the layout.
    pub fn put(&mut self, cell: u32, value: D::Value) -> Result<(), PortError> {
        self.push(cell, Op::Put(value)).map(|_| ())
    }

    /// Transfers a cell's value out to the main thread and resets the cell.
    /// The value is what DM sees now; with the overlay it can be up to one
    /// frame behind the worker (§3.10).
    ///
    /// # Errors
    /// If `cell` is outside the layout.
    pub fn take(&mut self, cell: u32) -> Result<Scratch<D::Value>, PortError> {
        let value = self.read(cell).ok_or(PortError::OutOfRange(cell))?;
        self.push(cell, Op::Take)?;
        Ok(Scratch(value))
    }

    /// Removes part of a cell as a scratch value (§3.5). `split` computes,
    /// from the value DM sees, the removal command with absolute amounts and
    /// the value removed; one command is queued.
    ///
    /// # Errors
    /// If `cell` is outside the layout.
    pub fn extract(
        &mut self,
        cell: u32,
        split: impl FnOnce(&D::Value) -> (D::Command, D::Value),
    ) -> Result<Scratch<D::Value>, PortError> {
        let current = self.read(cell).ok_or(PortError::OutOfRange(cell))?;
        let (cmd, removed) = split(&current);
        self.submit(cell, cmd)?;
        Ok(Scratch(removed))
    }

    /// Merges a scratch value into a cell as a single command (§3.5).
    ///
    /// # Errors
    /// If `cell` is outside the layout.
    pub fn assume(
        &mut self,
        cell: u32,
        scratch: Scratch<D::Value>,
        merge: impl FnOnce(D::Value) -> D::Command,
    ) -> Result<Applied, PortError> {
        self.submit(cell, merge(scratch.0))
    }

    fn push(&mut self, cell: u32, op: DomainOp<D>) -> Result<Applied, PortError> {
        if self.layout.locate(cell).is_none() {
            return Err(PortError::OutOfRange(cell));
        }
        if let Some(fb) = &mut self.fallback {
            self.commands.issue();
            fb.written_since_dispatch.insert(cell, ());
            let value = fb.live.get_mut(cell).expect("range checked");
            return Ok(apply_op::<D>(value, &op));
        }
        let (seq, op) = self.commands.push_ref(cell, op);
        let pinned = &self.pinned;
        let value = self
            .overlay
            .write(cell, seq, || pinned.get(cell).unwrap_or_default());
        Ok(apply_op::<D>(value, op))
    }

    /// Everything the domain's frames sent since the last drain: wakes,
    /// events and `Take` results (§8). Unfiltered; [`Sim::drain`] also drops
    /// stale watch records.
    ///
    /// [`Sim::drain`]: crate::sim::Sim::drain
    pub fn take_outbox(&mut self) -> Outbox<D::Value> {
        std::mem::take(&mut self.collected)
    }

    /// The view pinned for this tick.
    #[must_use]
    pub fn pinned(&self) -> &Arc<View<D::Value>> {
        &self.pinned
    }

    #[must_use]
    pub const fn layout(&self) -> ChunkLayout {
        self.layout
    }

    /// The last sequence number issued.
    #[must_use]
    pub const fn last_seq(&self) -> Seq {
        self.commands.last_issued()
    }

    /// Commands issued that the pinned view does not include yet (0 on the
    /// fallback path, where writes apply immediately).
    #[must_use]
    pub fn backlog(&self) -> u64 {
        if self.fallback.is_some() {
            0
        } else {
            self.commands
                .last_issued()
                .0
                .saturating_sub(self.pinned.applied_through.0)
        }
    }

    /// Commands queued for the next dispatch.
    #[must_use]
    pub fn queued(&self) -> usize {
        self.commands.len()
    }

    #[must_use]
    pub fn overlay_len(&self) -> usize {
        self.overlay.len()
    }

    /// Ticks since a new view was last pinned.
    #[must_use]
    pub const fn view_age_ticks(&self) -> u32 {
        self.ticks_since_view
    }

    #[must_use]
    pub const fn is_fallback(&self) -> bool {
        self.fallback.is_some()
    }

    /// Fallback-path counters (`None` in overlay mode).
    #[must_use]
    pub fn fallback_stats(&self) -> Option<FallbackStats> {
        self.fallback.as_ref().map(|fb| FallbackStats {
            pending_pieces: fb.pieces.len(),
            applied_pieces: fb.applied_pieces,
            rejected_pieces: fb.rejected_pieces,
        })
    }

    /// Start of tick: pin the newest view, drop overlay entries it includes;
    /// on the fallback path, turn a finished frame into pieces and apply
    /// what fits in `budget` cells.
    pub(crate) fn begin_tick(&mut self, budget: &mut usize) {
        let new_view = self.inbox.take();
        // Collect after the view: a batch published with a view is always
        // collected no later than that view is pinned.
        if let Some(batch) = self.outbox_inbox.collect() {
            self.collected.append(batch);
        }
        match &new_view {
            Some(_) => self.ticks_since_view = 0,
            None => self.ticks_since_view = self.ticks_since_view.saturating_add(1),
        }
        let Some(fb) = &mut self.fallback else {
            if let Some(view) = new_view {
                self.pinned = view;
                self.overlay.prune(self.pinned.applied_through);
            }
            return;
        };
        if let Some(view) = new_view {
            let base = fb
                .base
                .take()
                .expect("a view arrived for a dispatched frame");
            for chunk in view.store.chunks_differing_from(&base) {
                let piece: Vec<(u32, D::Value)> = (0..self.layout.chunk_len())
                    .filter_map(|cell| {
                        let index = self.layout.index_of(chunk, cell)?;
                        let new = view.store.get(index)?;
                        (base.get(index)? != new).then_some((index, new))
                    })
                    .collect();
                if !piece.is_empty() {
                    fb.pieces.push_back(piece);
                }
            }
            self.pinned = view;
        }
        let mut first = true;
        while let Some(piece) = fb.pieces.front() {
            if piece.len() > *budget && !first {
                break;
            }
            first = false;
            let piece = fb.pieces.pop_front().expect("front exists");
            *budget = budget.saturating_sub(piece.len());
            if piece
                .iter()
                .any(|(cell, _)| fb.written_since_dispatch.contains_key(cell))
            {
                fb.rejected_pieces += 1;
                continue;
            }
            for (cell, value) in piece {
                fb.live.set(cell, value);
            }
            fb.applied_pieces += 1;
        }
    }

    /// Whether this port can join a new frame (the fallback path waits until
    /// the previous frame's pieces are all applied).
    pub(crate) fn ready(&self) -> bool {
        self.fallback
            .as_ref()
            .is_none_or(|fb| fb.base.is_none() && fb.pieces.is_empty())
    }

    /// Frame boundary: move this tick's commands into the worker state (or,
    /// on the fallback path, hand the worker a snapshot of the live store).
    /// Returns the batch for the flight recorder when `record` is set.
    pub(crate) fn dispatch(
        &mut self,
        state: &mut DomainState<D>,
        record: bool,
    ) -> Option<Box<dyn Any + Send + Sync>> {
        if let Some(fb) = &mut self.fallback {
            state.install(fb.live.snapshot());
            fb.base = Some(fb.live.snapshot());
            fb.written_since_dispatch.clear();
            return None;
        }
        let batch = self.commands.take();
        let recorded = record.then(|| Box::new(batch.clone()) as Box<dyn Any + Send + Sync>);
        state.enqueue(batch);
        recorded
    }

    pub(crate) const fn state_res(&self) -> Res<DomainState<D>> {
        self.state
    }
}
