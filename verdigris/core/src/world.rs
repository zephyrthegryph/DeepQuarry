//! The driver (`rust_architecture.md` §4.2–§4.9): **one** `World` per DLL.
//!
//! A domain registers declarations and laws with a [`WorldBuilder`]:
//!
//! ```ignore
//! let mut b = WorldBuilder::new(WorldConfig::default());
//! b.add_component::<Apc>();
//! b.add_network::<Cables>(Ownership::Main);
//! b.add_law::<ApcTick>();
//! b.add_law::<PowerBalance>().after::<ApcTick>();
//! b.conserve("energy", Tolerance::default());
//! let mut world = b.build()?;
//! ```
//!
//! and nothing else: no domain constructs a `Sim`, paces itself, keeps a
//! key/handle table, diffs display state or encodes a list for DM.
//!
//! # What the world owns
//!
//! - **Identity**: the one [`EntityTable`]. Every component row is indexed
//!   by its entity's slot ([`crate::store`]).
//! - **Stores**: one per component kind, in the phase its [`Ownership`]
//!   names. Worker kinds are domains of the one [`Sim`]; main kinds live on
//!   the main thread.
//! - **Networks** ([`NetworkHost`]) and **globals**, each in one phase.
//! - **Pacing**: the only [`Pacer`] (fixed dt, idle skip, backlog cap).
//! - **Laws**: compiled into [`Task`]s per phase, in declared order, with
//!   their read/write sets from their [`Query`] types, iterating only awake
//!   items ([`Activity`], `Settle::Sleep`, timers, wakes), on their
//!   [`Period`](crate::law::Period).
//! - **Events**: every law's typed events, concatenated into one wire list
//!   ([`World::drain_events`]).
//! - **Watches**: every component kind is watchable ([`World::watch`]);
//!   fired wakes are drained with [`World::drain_wakes`].
//! - **Conservation**: declared quantities are summed over every conserved
//!   component field, network payload and registered source after each
//!   frame and checked against the sources/sinks laws recorded plus DM's
//!   writes (crossings), per phase ([`World::violations`]).
//!
//! # One step
//!
//! [`World::tick`] (called once per DM tick) reclaims a finished frame,
//! pins every worker kind's newest view, collects the finished frame's
//! events, wakes and violations, feeds the elapsed time to the pacer, and,
//! if a step is owed and no frame is running, runs the **main phase**
//! (network commits, main-owned laws, main watches and conservation)
//! synchronously and dispatches the **worker phase** frame on the pool. The
//! two phases run in lockstep, one step per tick at most; DM never waits.

use std::any::{Any, TypeId};
use std::cmp::Reverse;
use std::collections::{BinaryHeap, HashMap};
use std::fmt;

use crate::activity::Activity;
use crate::channel::{ChannelInfo, Channels, channel_infos, validate_channels};
use crate::component::{Component, ComponentError, FieldId, FieldRole, Ownership, Schema};
use crate::conservation::{Conserved, Ledger, Tolerance, Totals, Violation};
use crate::entity::{EntityError, EntityId, EntityTable};
use crate::event::EventSink;
use crate::field::{FieldConfig, FieldKey, FieldKind};
use crate::grid::{Grid, GridDims};
use crate::frame::{FrameInfo, Ref, Res, ResourceId, Resources, Task, TaskCtx, run_sequential};
use crate::law::{Effects, Law, LawCtx, OrderCycle, Pacer, Settle, order_laws};
use crate::network::{NetworkHost, NetworkKind, RegionEvent, host::Transition};
use crate::outbox::{Lane, Outbox, Subscriber, Wake, WatchId};
use crate::owner::{Applied, Domain, DomainKey, DomainState, PortError};
use crate::query::{Access, Anchor, At, Catalog, ColumnSource, FrameData, Item, LawError, Phase, Query, QueryInit, RowsFn, WriteQuery};
use crate::sim::{BuildError, Sim, SimBuilder, SimConfig, WatchKey};
use crate::store::{MainKind, WorkerKind, kind_layout};
use crate::units::Seconds;
use crate::watch::{Cond, WatchError, WatchPort, WatchState};

/// A registered component kind, by registration order.
pub type KindId = u16;

/// The code DM uses for a kind: `domain << 8 | kind`.
#[must_use]
pub const fn kind_code(domain: u8, kind: u16) -> u32 {
    ((domain as u32) << 8) | (kind as u32 & 0xff)
}

/// World options.
#[derive(Clone, Debug)]
pub struct WorldConfig {
    /// Simulated seconds per step.
    pub dt: Seconds,
    /// Most steps owed at once; older owed time is dropped (the sim runs
    /// slow rather than spiralling).
    pub backlog_cap: u32,
    pub sim: SimConfig,
    /// Sum and check declared conserved quantities after every step. On in
    /// debug and test builds by default: the sums visit every conserved row.
    pub check_conservation: bool,
}

impl Default for WorldConfig {
    fn default() -> Self {
        Self {
            dt: Seconds(1.0),
            backlog_cap: 2,
            sim: SimConfig::default(),
            check_conservation: cfg!(debug_assertions),
        }
    }
}

/// Why a world call failed.
#[derive(Clone, Debug, PartialEq)]
pub enum WorldError {
    Entity(EntityError),
    Component(ComponentError),
    /// No kind is registered under that id or code.
    NoKind(u32),
    Watch(WatchError),
    Port(PortError),
    /// The data is owned by a worker frame and cannot be borrowed directly.
    WorkerOwned(&'static str),
}

impl fmt::Display for WorldError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Entity(e) => write!(f, "{e}"),
            Self::Component(e) => write!(f, "{e}"),
            Self::NoKind(k) => write!(f, "no component kind {k}"),
            Self::Watch(e) => write!(f, "{e}"),
            Self::Port(e) => write!(f, "{e}"),
            Self::WorkerOwned(what) => write!(f, "{what} is worker-owned; edit it through the queued path"),
        }
    }
}

impl std::error::Error for WorldError {}

impl From<EntityError> for WorldError {
    fn from(e: EntityError) -> Self {
        Self::Entity(e)
    }
}
impl From<ComponentError> for WorldError {
    fn from(e: ComponentError) -> Self {
        Self::Component(e)
    }
}
impl From<WatchError> for WorldError {
    fn from(e: WatchError) -> Self {
        Self::Watch(e)
    }
}
impl From<PortError> for WorldError {
    fn from(e: PortError) -> Self {
        Self::Port(e)
    }
}

/// Why [`WorldBuilder::build`] failed.
#[derive(Debug)]
pub enum WorldBuildError {
    Law(LawError),
    Sim(BuildError),
}

impl fmt::Display for WorldBuildError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Law(e) => write!(f, "{e}"),
            Self::Sim(e) => write!(f, "{e}"),
        }
    }
}

impl std::error::Error for WorldBuildError {}

impl From<LawError> for WorldBuildError {
    fn from(e: LawError) -> Self {
        Self::Law(e)
    }
}
impl From<BuildError> for WorldBuildError {
    fn from(e: BuildError) -> Self {
        Self::Sim(e)
    }
}

// --- Per-phase driver resources ---------------------------------------------

/// Entities woken for the coming step, by slot index: binds, DM writes and
/// laws' [`LawCtx::wake_entity`]. Every row law reads it and wakes the ones
/// it holds.
#[derive(Debug, Default)]
pub struct FrameWakes {
    pub entities: Vec<u32>,
}

/// What a phase's step produced for the main thread.
#[derive(Debug, Default)]
pub struct FrameOut {
    pub events: EventSink,
    pub violations: Vec<Violation>,
}

/// Per-phase conservation state.
#[derive(Default)]
struct Conservation {
    ledger: Ledger,
    totals: Totals,
    /// Cumulative crossings seen so far, by `(kind index, quantity)`.
    seen: Vec<((usize, &'static str), f64)>,
    declared: Vec<(&'static str, Tolerance)>,
}

impl Conservation {
    fn credit_crossings(&mut self, kind: usize, cumulative: &[(&'static str, f64)]) {
        for &(name, total) in cumulative {
            let key = (kind, name);
            let last = match self.seen.iter_mut().find(|(k, _)| *k == key) {
                Some((_, v)) => std::mem::replace(v, total),
                None => {
                    self.seen.push((key, total));
                    0.0
                }
            };
            let delta = total - last;
            if delta != 0.0 {
                self.ledger.source(name, delta);
            }
        }
    }
}

/// One law's worker-side state.
#[derive(Default)]
struct LawState {
    activity: Activity,
    /// Network anchors: the revision each item last ran at, by slot index.
    seen: Vec<u64>,
    /// `(frame due, item)`.
    timers: BinaryHeap<Reverse<(u64, u32)>>,
    fx: Effects,
    items: Vec<Item>,
    scratch: Vec<u32>,
    /// Items stepped in the last run.
    stepped: u32,
}

/// A law's per-run statistics.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LawStats {
    pub name: &'static str,
    pub phase: Phase,
    /// Items stepped in the law's last run.
    pub stepped: u32,
    /// Items awake now.
    pub awake: u32,
}

/// Network slot index of an anchor item (raw handles carry 20 index bits;
/// entity indices have 19, so this is the identity for rows).
const fn slot_of(index: u32) -> u32 {
    index & ((1 << crate::slot::INDEX_BITS) - 1)
}

#[derive(Clone, Copy)]
enum PlanAnchor {
    Rows { rows: ResourceId, get: RowsFn },
    Network { host: ResourceId, list: crate::query::ListFn, revision: crate::query::RevFn },
    Global,
}

#[allow(clippy::too_many_lines)]
fn law_task<L: Law>(
    anchor: PlanAnchor,
    access: Access,
    r_state: <L::Reads as Query>::State,
    w_state: <L::Writes as Query>::State,
    state: Res<LawState>,
    wakes: Res<FrameWakes>,
    base_dt: f64,
) -> Task
where
    L::Reads: Query,
    L::Writes: WriteQuery,
{
    let period = L::PERIOD.frames();
    let law_dt = Seconds(base_dt * f64::from(period));
    let mut task_access = access.clone();
    task_access.write(state.id());
    task_access.read(wakes.id());
    let run = move |ctx: &TaskCtx<'_>| {
        let frame_no = ctx.frame();
        #[allow(clippy::cast_precision_loss)]
        let now = frame_no as f64 * base_dt;
        let woken = ctx.read(wakes);
        let mut guard = ctx.write(state);
        let ls = &mut *guard;
        let mut frame = FrameData::lock(ctx, &access);
        while let Some(&Reverse((due, item))) = ls.timers.peek() {
            if due > frame_no {
                break;
            }
            ls.timers.pop();
            ls.activity.wake_grow(slot_of(item));
        }
        ls.stepped = 0;
        let step_one = |ls: &mut LawState, frame: &mut FrameData<'_>, at: At, entity_value: f32| -> Option<Settle> {
            let reads = <L::Reads as Query>::fetch(&r_state, frame, at)?;
            let mut writes = <L::Writes as Query>::fetch(&w_state, frame, at)?;
            ls.fx.begin(at.index, entity_value, now);
            let settle = {
                let mut lc = LawCtx::new(&reads, &mut writes, &mut ls.fx);
                L::step(&mut lc, law_dt)
            };
            writes.write(&w_state, frame, at);
            ls.stepped += 1;
            Some(settle)
        };
        match anchor {
            PlanAnchor::Rows { rows, get } => {
                {
                    let held = get(&frame, rows);
                    for &e in &woken.entities {
                        if held.contains(e) {
                            ls.activity.wake_grow(e);
                        }
                    }
                    ls.scratch.clear();
                    ls.scratch.extend(ls.activity.iter());
                    ls.items.clear();
                    for &i in &ls.scratch {
                        ls.items.push(Item {
                            at: At { index: i, entity: Some(i) },
                            revision: u64::from(held.contains(i)),
                            entity_value: held.entity_value(i),
                        });
                    }
                }
                let items = std::mem::take(&mut ls.items);
                for item in &items {
                    let i = item.at.index;
                    if item.revision == 0 {
                        ls.activity.sleep(i);
                        continue;
                    }
                    match step_one(ls, &mut frame, item.at, item.entity_value) {
                        Some(Settle::Active) => {}
                        Some(Settle::Sleep) | None => {
                            ls.activity.sleep(i);
                        }
                    }
                }
                ls.items = items;
            }
            PlanAnchor::Network { host, list, revision } => {
                ls.items.clear();
                list(&frame, host, &mut ls.items);
                let items = std::mem::take(&mut ls.items);
                for item in &items {
                    let slot = slot_of(item.at.index) as usize;
                    if ls.seen.len() <= slot {
                        ls.seen.resize(slot + 1, u64::MAX);
                    }
                    #[allow(clippy::cast_possible_truncation)]
                    let awake = ls.activity.is_awake(slot as u32);
                    if !awake && ls.seen[slot] == item.revision {
                        continue;
                    }
                    let settle = step_one(ls, &mut frame, item.at, item.entity_value);
                    ls.seen[slot] = revision(&frame, host, item.at.index);
                    #[allow(clippy::cast_possible_truncation)]
                    match settle {
                        Some(Settle::Active) => {
                            ls.activity.wake_grow(slot as u32);
                        }
                        Some(Settle::Sleep) | None => {
                            ls.activity.sleep(slot as u32);
                        }
                    }
                }
                ls.items = items;
            }
            PlanAnchor::Global => {
                let _ = step_one(ls, &mut frame, At { index: 0, entity: None }, 0.0);
            }
        }
        for i in std::mem::take(&mut ls.fx.wakes) {
            ls.activity.wake_grow(slot_of(i));
        }
        for (at, i) in std::mem::take(&mut ls.fx.timers) {
            #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
            let due = if base_dt > 0.0 { (at / base_dt).ceil().max(0.0) as u64 } else { frame_no + 1 };
            ls.timers.push(Reverse((due.max(frame_no + 1), i)));
        }
    };
    let mut task = Task::new(L::NAME, run).every(period);
    for id in task_access.reads {
        task = task.reads(id);
    }
    for id in task_access.writes {
        task = task.writes(id);
    }
    task
}

// --- Kinds -------------------------------------------------------------------------

/// The type-erased operations the world performs on one component kind.
trait KindDyn: Any {
    fn name(&self) -> &'static str;
    fn schema(&self) -> Schema;
    fn code(&self) -> u32;
    fn owner(&self) -> Ownership;
    fn column(&self, phase: Phase) -> ColumnSource;
    fn holds(&self, main: &Resources, e: EntityId) -> bool;
    fn bind(&mut self, sim: &mut Sim, main: &mut Resources, e: EntityId, init: &[(FieldId, Option<usize>, f64)]) -> Result<(), WorldError>;
    fn unbind(&mut self, sim: &mut Sim, main: &mut Resources, e: EntityId);
    fn get(&self, sim: &Sim, main: &Resources, e: EntityId, field: FieldId, index: usize) -> Result<f64, WorldError>;
    fn set(&mut self, sim: &mut Sim, main: &mut Resources, e: EntityId, field: FieldId, index: Option<usize>, value: f64) -> Result<(), WorldError>;
    fn adjust(&mut self, sim: &mut Sim, main: &mut Resources, e: EntityId, field: FieldId, index: usize, delta: f64) -> Result<f32, WorldError>;
    fn describe(&self, sim: &Sim, main: &Resources, e: EntityId) -> Vec<(String, String)>;
    /// At dispatch: mirror rows (and a main-owned store's snapshot) into
    /// the worker side.
    fn sync(&mut self, main: &mut Resources, worker: &mut Resources);
    /// At the start of a tick: pin the worker view for main-phase readers
    /// and collect fired watch wakes.
    fn begin_tick(&mut self, sim: &mut Sim, main: &mut Resources, wakes: &mut Vec<Wake>);
    /// After the main phase: evaluate main-owned watches.
    fn after_main(&mut self, main: &Resources, wakes: &mut Vec<Wake>);
    fn channels(&self) -> Vec<ChannelInfo>;
    fn watch(&mut self, sim: &mut Sim, sub: Subscriber, lane: Lane, cond: &Cond) -> Result<WatchId, WorldError>;
    fn unwatch(&mut self, sim: &mut Sim, id: WatchId) -> Result<(), WorldError>;
    fn as_any(&self) -> &dyn Any;
}

struct MainWatches<C: Component> {
    state: WatchState<C::Kind>,
    port: WatchPort<C::Kind>,
    out: Outbox<C>,
}

struct KindEntry<C: Component> {
    main: Res<MainKind<C>>,
    worker: Res<WorkerKind<C>>,
    /// Worker-owned kinds: the domain in the one `Sim`.
    domain: Option<DomainKey<C::Kind>>,
    worker_watches: Option<WatchKey<C::Kind>>,
    main_watches: Option<MainWatches<C>>,
    /// Worker-owned kinds: the view pinned this tick.
    has_view: bool,
}

/// Applies a DM command to one row of kind `C` (either owner).
fn submit_row<C: Component>(
    main_res: Res<MainKind<C>>,
    domain: Option<DomainKey<C::Kind>>,
    sim: &mut Sim,
    main: &mut Resources,
    e: EntityId,
    cmd: &<C::Kind as Domain>::Command,
) -> Result<Applied, WorldError> {
    if !main.get(main_res).rows.holds(e) {
        return Err(ComponentError::Missing { kind: C::NAME }.into());
    }
    match domain {
        Some(key) => Ok(sim.port(key).submit(e.index(), cmd.clone())?),
        None => main
            .get_mut(main_res)
            .apply(e.index(), cmd)
            .ok_or(ComponentError::Missing { kind: C::NAME }.into()),
    }
}

impl<C: Component> KindEntry<C> {
    fn value(&self, sim: &Sim, main: &Resources, e: EntityId) -> Result<C, WorldError> {
        let mk = main.get(self.main);
        if !mk.rows.holds(e) {
            return Err(ComponentError::Missing { kind: C::NAME }.into());
        }
        match self.domain {
            Some(key) => sim
                .port_ref(key)
                .read(e.index())
                .ok_or(WorldError::Port(PortError::OutOfRange(e.index()))),
            None => mk.get(e.index()).ok_or(ComponentError::Missing { kind: C::NAME }.into()),
        }
    }
}

impl<C: Component> KindDyn for KindEntry<C> {
    fn name(&self) -> &'static str {
        C::NAME
    }
    fn schema(&self) -> Schema {
        Schema::of::<C>()
    }
    fn code(&self) -> u32 {
        kind_code(C::DOMAIN_ID, C::KIND)
    }
    fn owner(&self) -> Ownership {
        C::OWNER
    }
    fn column(&self, phase: Phase) -> ColumnSource {
        match (C::OWNER, phase, self.domain) {
            (Ownership::Worker, Phase::Worker, Some(key)) => ColumnSource::WorkerStore {
                store: key.state().id(),
                rows: self.worker.id(),
            },
            (Ownership::Worker, _, _) => ColumnSource::View { kind: self.main.id() },
            (Ownership::Main, Phase::Main, _) => ColumnSource::MainStore { kind: self.main.id() },
            (Ownership::Main, Phase::Worker, _) => ColumnSource::Snapshot { rows: self.worker.id() },
        }
    }
    fn holds(&self, main: &Resources, e: EntityId) -> bool {
        main.get(self.main).rows.holds(e)
    }
    fn bind(&mut self, sim: &mut Sim, main: &mut Resources, e: EntityId, init: &[(FieldId, Option<usize>, f64)]) -> Result<(), WorldError> {
        let mut value = C::default();
        for &(field, index, v) in init {
            let cmd = C::set_command(field, index, v)?;
            <C::Kind as Domain>::apply(&mut value, &cmd);
        }
        if let Some(key) = self.domain {
            sim.port(key).put(e.index(), value.clone())?;
        }
        main.get_mut(self.main).bind(e, value);
        Ok(())
    }
    fn unbind(&mut self, sim: &mut Sim, main: &mut Resources, e: EntityId) {
        let mk = main.get_mut(self.main);
        if !mk.rows.holds(e) {
            return;
        }
        mk.unbind(e.index());
        if let Some(key) = self.domain {
            let _ = sim.port(key).take(e.index());
        }
    }
    fn get(&self, sim: &Sim, main: &Resources, e: EntityId, field: FieldId, index: usize) -> Result<f64, WorldError> {
        self.value(sim, main, e)?
            .get_field(field, index)
            .ok_or(ComponentError::NoField { field }.into())
    }
    fn set(&mut self, sim: &mut Sim, main: &mut Resources, e: EntityId, field: FieldId, index: Option<usize>, value: f64) -> Result<(), WorldError> {
        let cmd = C::set_command(field, index, value)?;
        submit_row::<C>(self.main, self.domain, sim, main, e, &cmd).map(|_| ())
    }
    fn adjust(&mut self, sim: &mut Sim, main: &mut Resources, e: EntityId, field: FieldId, index: usize, delta: f64) -> Result<f32, WorldError> {
        let cmd = C::adjust_command(field, index, delta)?;
        submit_row::<C>(self.main, self.domain, sim, main, e, &cmd).map(|a| a.shortfall)
    }
    fn describe(&self, sim: &Sim, main: &Resources, e: EntityId) -> Vec<(String, String)> {
        let Ok(v) = self.value(sim, main, e) else {
            return Vec::new();
        };
        C::FIELDS
            .iter()
            .enumerate()
            .map(|(i, f)| {
                #[allow(clippy::cast_possible_truncation)]
                let id = i as FieldId;
                let unit = f.unit.map(|u| format!(" {u}")).unwrap_or_default();
                let text = if !f.numeric {
                    "(opaque)".to_owned()
                } else if f.len > 1 {
                    let parts: Vec<String> = (0..usize::from(f.len))
                        .filter_map(|k| v.get_field(id, k))
                        .map(|x| format!("{x}"))
                        .collect();
                    format!("[{}]{unit}", parts.join(", "))
                } else {
                    v.get_field(id, 0).map_or_else(|| "?".to_owned(), |x| format!("{x}{unit}"))
                };
                let marker = if f.role == FieldRole::Computed { "=" } else { "" };
                (format!("{}{marker}", f.name), text)
            })
            .collect()
    }
    fn sync(&mut self, main: &mut Resources, worker: &mut Resources) {
        let wk = worker.get_mut(self.worker);
        main.get_mut(self.main).sync_worker(wk);
    }
    fn begin_tick(&mut self, sim: &mut Sim, main: &mut Resources, wakes: &mut Vec<Wake>) {
        if let Some(key) = self.domain {
            let view = std::sync::Arc::clone(sim.port_ref(key).pinned());
            main.get_mut(self.main).set_view(view);
            self.has_view = true;
            let out = sim.drain(key);
            wakes.extend_from_slice(out.wakes());
        }
    }
    fn after_main(&mut self, main: &Resources, wakes: &mut Vec<Wake>) {
        let Some(w) = &mut self.main_watches else {
            return;
        };
        let mk = main.get(self.main);
        let Some(store) = mk.store() else {
            return;
        };
        w.port.dispatch(&mut w.state);
        w.state.evaluate(store, &mut w.out);
        w.port.filter(&mut w.out);
        wakes.extend_from_slice(w.out.wakes());
        w.out = Outbox::default();
    }
    fn channels(&self) -> Vec<ChannelInfo> {
        channel_infos::<C::Kind>()
    }
    fn watch(&mut self, sim: &mut Sim, sub: Subscriber, lane: Lane, cond: &Cond) -> Result<WatchId, WorldError> {
        if let Some(wk) = self.worker_watches {
            return Ok(sim.watches(wk).watch(sub, lane, cond)?);
        }
        match &mut self.main_watches {
            Some(w) => Ok(w.port.watch(sub, lane, cond)?),
            None => Err(WorldError::Watch(WatchError::BadSubscriber(sub))),
        }
    }
    fn unwatch(&mut self, sim: &mut Sim, id: WatchId) -> Result<(), WorldError> {
        if let Some(wk) = self.worker_watches {
            return Ok(sim.watches(wk).unwatch(id)?);
        }
        match &mut self.main_watches {
            Some(w) => Ok(w.port.unwatch(id)?),
            None => Err(WorldError::Watch(WatchError::StaleWatch(id))),
        }
    }
    fn as_any(&self) -> &dyn Any {
        self
    }
}

// --- Networks ------------------------------------------------------------------

trait NetDyn: Any {
    fn phase(&self) -> Phase;
    fn resource(&self) -> ResourceId;
    /// Commits pending topology in `res` (the network's phase resources)
    /// and keeps the transitions for DM.
    fn commit(&mut self, res: &mut Resources);
    fn as_any_mut(&mut self) -> &mut dyn Any;
}

type NetEdit<K> = Box<dyn FnOnce(&mut NetworkHost<K>) + Send>;

struct NetEntry<K: NetworkKind> {
    phase: Phase,
    host: Res<NetworkHost<K>>,
    /// Worker-owned: DM edits queued until the next dispatch.
    queued: Vec<NetEdit<K>>,
    transitions: Vec<Transition>,
    events: Vec<RegionEvent<K>>,
}

impl<K: NetworkKind> NetDyn for NetEntry<K> {
    fn phase(&self) -> Phase {
        self.phase
    }
    fn resource(&self) -> ResourceId {
        self.host.id()
    }
    fn commit(&mut self, res: &mut Resources) {
        let host = res.get_mut(self.host);
        for edit in self.queued.drain(..) {
            edit(host);
        }
        let events = host.commit();
        if !events.is_empty() {
            self.transitions.extend(host.transitions(&events));
            self.events.extend(events);
        }
    }
    fn as_any_mut(&mut self) -> &mut dyn Any {
        self
    }
}

// --- Builder ---------------------------------------------------------------------

type ConserveFn = Box<dyn Fn(&FrameData<'_>, &mut Totals, &mut Vec<(usize, &'static str, f64)>) + Send + Sync>;

struct ConserveSource {
    phase: Phase,
    access: Access,
    sum: ConserveFn,
}

type LawBuildFn = Box<dyn for<'a> FnOnce(&dyn Catalog, &mut PhaseBuild<'a>, f64) -> Result<(Task, Res<LawState>), LawError>>;

struct LawDecl {
    name: &'static str,
    phase_of: Box<dyn Fn(&WorldBuilder) -> Result<Phase, LawError>>,
    build: LawBuildFn,
}

/// Where one law's resources and task go while building.
enum Target<'a> {
    Main(&'a mut Resources),
    Worker(&'a mut SimBuilder),
}

/// One phase while building a law.
struct PhaseBuild<'a> {
    phase: Phase,
    target: Target<'a>,
    wakes: Res<FrameWakes>,
}

impl PhaseBuild<'_> {
    fn insert<T: Any + Send + Sync>(&mut self, name: String, value: T) -> Res<T> {
        match &mut self.target {
            Target::Main(m) => m.insert(name, value),
            Target::Worker(s) => s.add_resource(name, value),
        }
    }
}

/// Registers kinds, networks, globals and laws, then builds the [`World`].
pub struct WorldBuilder {
    config: WorldConfig,
    sim: SimBuilder,
    main: Resources,
    kinds: Vec<Box<dyn KindDyn>>,
    kind_types: HashMap<TypeId, KindId>,
    networks: Vec<Box<dyn NetDyn>>,
    net_types: HashMap<TypeId, usize>,
    globals: HashMap<TypeId, (ResourceId, Phase)>,
    laws: Vec<LawDecl>,
    after: Vec<(&'static str, &'static str)>,
    sources: Vec<ConserveSource>,
    declared: Vec<(&'static str, Tolerance)>,
    main_wakes: Res<FrameWakes>,
    worker_wakes: Res<FrameWakes>,
    main_out: Res<FrameOut>,
    worker_out: Res<FrameOut>,
    /// `(main, worker snapshot)`.
    grid: Option<(Res<Grid>, Res<Grid>)>,
}

/// A registered law, for declaring its order.
pub struct LawRef<'a> {
    builder: &'a mut WorldBuilder,
    name: &'static str,
}

impl LawRef<'_> {
    /// This law runs after `A` (in the same phase; across phases the main
    /// phase always runs first).
    #[must_use]
    pub fn after<A: Law>(self) -> Self {
        self.builder.after.push((self.name, A::NAME));
        self
    }

    /// This law runs before `B`.
    #[must_use]
    pub fn before<B: Law>(self) -> Self {
        self.builder.after.push((B::NAME, self.name));
        self
    }
}

struct CatalogView<'a> {
    kinds: &'a [Box<dyn KindDyn>],
    kind_types: &'a HashMap<TypeId, KindId>,
    networks: &'a [Box<dyn NetDyn>],
    net_types: &'a HashMap<TypeId, usize>,
    globals: &'a HashMap<TypeId, (ResourceId, Phase)>,
}

impl Catalog for CatalogView<'_> {
    fn column(&self, component: TypeId, phase: Phase) -> Option<ColumnSource> {
        let k = *self.kind_types.get(&component)?;
        Some(self.kinds[usize::from(k)].column(phase))
    }
    fn network(&self, kind: TypeId) -> Option<(ResourceId, Phase)> {
        let n = &self.networks[*self.net_types.get(&kind)?];
        Some((n.resource(), n.phase()))
    }
    fn global(&self, ty: TypeId) -> Option<(ResourceId, Phase)> {
        self.globals.get(&ty).copied()
    }
}

impl WorldBuilder {
    #[must_use]
    pub fn new(config: WorldConfig) -> Self {
        let mut sim = SimBuilder::new(config.sim.clone());
        let mut main = Resources::new();
        let main_wakes = main.insert("wakes:main", FrameWakes::default());
        let main_out = main.insert("out:main", FrameOut::default());
        let worker_wakes = sim.add_resource("wakes:worker", FrameWakes::default());
        let worker_out = sim.add_resource("out:worker", FrameOut::default());
        Self {
            config,
            sim,
            main,
            kinds: Vec::new(),
            kind_types: HashMap::new(),
            networks: Vec::new(),
            net_types: HashMap::new(),
            globals: HashMap::new(),
            laws: Vec::new(),
            after: Vec::new(),
            sources: Vec::new(),
            declared: Vec::new(),
            main_wakes,
            worker_wakes,
            main_out,
            worker_out,
            grid: None,
        }
    }

    /// Registers component `C` (idempotent). Its rows live in the phase its
    /// `owner` names; every kind is watchable, and conserved fields join
    /// the conservation check of any quantity declared with
    /// [`conserve`](Self::conserve).
    pub fn add_component<C: Component>(&mut self) -> KindId {
        if let Some(&k) = self.kind_types.get(&TypeId::of::<C>()) {
            return k;
        }
        let main = self
            .main
            .insert(format!("kind:{}", C::NAME), MainKind::<C>::new(C::OWNER == Ownership::Main));
        let worker = self.sim.add_resource(format!("kind:{}", C::NAME), WorkerKind::<C>::default());
        let watchable = validate_channels::<C::Kind>().is_ok() && !<C::Kind as Channels>::CHANNELS.is_empty();
        let (domain, worker_watches, main_watches) = match C::OWNER {
            Ownership::Worker => {
                let key = self.sim.add_domain::<C::Kind>(kind_layout());
                let wk = watchable.then(|| self.sim.add_watches(key));
                (Some(key), wk, None)
            }
            Ownership::Main => (
                None,
                None,
                watchable.then(|| MainWatches {
                    state: WatchState::new(kind_layout()),
                    port: WatchPort::new(kind_layout()),
                    out: Outbox::default(),
                }),
            ),
        };
        let kind_index = self.kinds.len();
        if C::OWNER == Ownership::Main && <C::Kind as Domain>::CONSERVES {
            let mut access = Access::default();
            access.read(main.id());
            let main_id = main.id();
            self.sources.push(ConserveSource {
                phase: Phase::Main,
                access,
                sum: Box::new(move |frame, totals, crossings| {
                    let mk = frame.get::<MainKind<C>>(main_id);
                    for i in mk.rows.iter() {
                        if let Some(v) = mk.get_ref(i) {
                            v.conserved(&mut |n, a| totals.add(n, a));
                        }
                    }
                    for &(n, v) in mk.crossings() {
                        crossings.push((kind_index, n, v));
                    }
                }),
            });
        }
        if C::OWNER == Ownership::Worker && <C::Kind as Domain>::CONSERVES {
            let key = domain.expect("worker kind has a domain");
            let mut access = Access::default();
            access.read(key.state().id());
            access.read(worker.id());
            let (store_id, rows_id) = (key.state().id(), worker.id());
            self.sources.push(ConserveSource {
                phase: Phase::Worker,
                access,
                sum: Box::new(move |frame, totals, crossings| {
                    let st = frame.get::<DomainState<C::Kind>>(store_id);
                    let rows = &frame.get::<WorkerKind<C>>(rows_id).rows;
                    for i in rows.iter() {
                        st.store.with(i, |v| v.conserved(&mut |n, a| totals.add(n, a)));
                    }
                    for &(n, v) in st.crossings() {
                        crossings.push((kind_index, n, v));
                    }
                }),
            });
        }
        #[allow(clippy::cast_possible_truncation)]
        let id = self.kinds.len() as KindId;
        self.kinds.push(Box::new(KindEntry::<C> {
            main,
            worker,
            domain,
            worker_watches,
            main_watches,
            has_view: false,
        }));
        self.kind_types.insert(TypeId::of::<C>(), id);
        id
    }

    /// Registers network kind `K`, owned by `owner`'s phase: a main-owned
    /// network (pipes and cables, which DM edits and reads synchronously)
    /// is committed and stepped on the main thread; a worker-owned one in
    /// frames, with DM edits queued to the next dispatch.
    pub fn add_network<K: NetworkKind>(&mut self, owner: Ownership) {
        if self.net_types.contains_key(&TypeId::of::<K>()) {
            return;
        }
        let phase = Phase::of(owner);
        let name = format!("net:{}", K::NAME);
        let host = match phase {
            Phase::Main => self.main.insert(name, NetworkHost::<K>::new()),
            Phase::Worker => self.sim.add_resource(name, NetworkHost::<K>::new()),
        };
        self.net_types.insert(TypeId::of::<K>(), self.networks.len());
        self.networks.push(Box::new(NetEntry::<K> {
            phase,
            host,
            queued: Vec::new(),
            transitions: Vec::new(),
            events: Vec::new(),
        }));
    }

    /// Adds network `K`'s payloads to the conservation check.
    pub fn conserve_network<K: NetworkKind>(&mut self)
    where
        K::Payload: Conserved,
    {
        let Some(&n) = self.net_types.get(&TypeId::of::<K>()) else {
            return;
        };
        let entry = &self.networks[n];
        let (phase, id) = (entry.phase(), entry.resource());
        let mut access = Access::default();
        access.read(id);
        self.sources.push(ConserveSource {
            phase,
            access,
            sum: Box::new(move |frame, totals, _| {
                totals.add_source(frame.get::<NetworkHost<K>>(id));
            }),
        });
    }

    /// Registers a global resource in `owner`'s phase: state a once-per-step
    /// law reads or writes through [`crate::query::Global`] (which needs
    /// `Clone + PartialEq`), or host state the FFI layer keeps in the world
    /// instead of a static ([`World::global_mut`]).
    pub fn add_global<T: Any + Send + Sync>(&mut self, owner: Ownership, value: T) {
        let phase = Phase::of(owner);
        let name = format!("global:{}", std::any::type_name::<T>());
        let id = match phase {
            Phase::Main => self.main.insert(name, value).id(),
            Phase::Worker => self.sim.add_resource(name, value).id(),
        };
        self.globals.insert(TypeId::of::<T>(), (id, phase));
    }

    /// Gives the world its one [`Grid`] (block layers and z links,
    /// `rust_architecture.md` §4.6). DM edits it on the main thread
    /// ([`World::edit_grid`]); worker readers (fields) see a copy-on-write
    /// snapshot taken at each dispatch that follows a change.
    pub fn add_grid(&mut self, dims: GridDims) -> Res<Grid> {
        let main = self.main.insert("grid:main", Grid::new(dims));
        let worker = self.sim.add_resource("grid:worker", Grid::new(dims));
        self.grid = Some((main, worker));
        worker
    }

    /// Registers field kind `K` over the world's grid (its blocked faces
    /// come from layer `K::BLOCK`), with its quantities in the conservation
    /// check when `K::QUANTITY_NAMES` names them.
    ///
    /// # Panics
    /// If no grid was added first ([`add_grid`](Self::add_grid)).
    pub fn add_field<K: FieldKind>(&mut self, config: FieldConfig) -> FieldKey<K> {
        let (_, grid) = self.grid.expect("add_grid before add_field");
        let dims = self.main.get(self.grid.expect("checked").0).dims();
        let key = crate::field::add_field::<K>(&mut self.sim, dims, config, Some(grid));
        if !K::QUANTITY_NAMES.is_empty() {
            // Crossings are keyed by source; fields use keys from the top so
            // they never meet a component kind's index.
            let crossing_key = usize::MAX - self.sources.len();
            let (cells, geom, state) = (key.cells.state().id(), key.geometry.state().id(), key.state.id());
            let mut access = Access::default();
            access.read(cells);
            access.read(geom);
            access.read(state);
            self.sources.push(ConserveSource {
                phase: Phase::Worker,
                access,
                sum: Box::new(move |frame, totals, crossings| {
                    let c = frame.get::<DomainState<K>>(cells);
                    let g = frame.get::<DomainState<crate::field::Geometry<K>>>(geom);
                    let st = frame.get::<crate::field::FieldState<K>>(state);
                    let sums = crate::field::FieldState::<K>::totals(&c.store, &g.store);
                    for ((name, sum), reservoir) in K::QUANTITY_NAMES.iter().zip(sums).zip(st.ledger()) {
                        totals.add(name, sum + reservoir);
                    }
                    for &(n, v) in c.crossings() {
                        crossings.push((crossing_key, n, v));
                    }
                }),
            });
        }
        key
    }

    /// Adds any worker resource that holds conserved quantities (a field's
    /// state, say) to the conservation check.
    pub fn conserve_resource<T: Conserved + Any + Send + Sync>(&mut self, phase: Phase, res: Res<T>) {
        let mut access = Access::default();
        access.read(res.id());
        let id = res.id();
        self.sources.push(ConserveSource {
            phase,
            access,
            sum: Box::new(move |frame, totals, _| totals.add_source(frame.get::<T>(id))),
        });
    }

    /// Declares a conserved quantity the driver checks after every step
    /// (when [`WorldConfig::check_conservation`] is on).
    pub fn conserve(&mut self, quantity: &'static str, tolerance: Tolerance) -> &mut Self {
        if !self.declared.iter().any(|(n, _)| *n == quantity) {
            self.declared.push((quantity, tolerance));
        }
        self
    }

    /// Registers law `L`. Its phase follows its anchor: the owner of the
    /// component, network or global it iterates. Order within a phase is
    /// registration order unless constrained with
    /// [`LawRef::after`]/[`LawRef::before`].
    pub fn add_law<L: Law>(&mut self) -> LawRef<'_>
    where
        L::Reads: Query,
        L::Writes: WriteQuery,
    {
        let anchor = <L::Writes as Query>::anchor().or_else(<L::Reads as Query>::anchor);
        let phase_of = Box::new(move |b: &WorldBuilder| -> Result<Phase, LawError> {
            let unregistered = |what| LawError::Unregistered { law: L::NAME, what };
            match anchor {
                None => Err(LawError::NoAnchor { law: L::NAME }),
                Some(Anchor::Rows { component, name, .. }) => {
                    let k = b.kind_types.get(&component).ok_or_else(|| unregistered(name))?;
                    Ok(Phase::of(b.kinds[usize::from(*k)].owner()))
                }
                Some(Anchor::Network { kind, name, .. }) => {
                    let n = b.net_types.get(&kind).ok_or_else(|| unregistered(name))?;
                    Ok(b.networks[*n].phase())
                }
                Some(Anchor::Global { ty, name }) => b.globals.get(&ty).map(|g| g.1).ok_or_else(|| unregistered(name)),
            }
        });
        let build: LawBuildFn = Box::new(move |catalog, pb, dt| {
            let mut access = Access::default();
            let mut init = QueryInit {
                catalog,
                phase: pb.phase,
                access: &mut access,
                law: L::NAME,
            };
            let r_state = <L::Reads as Query>::init(&mut init, false)?;
            let w_state = <L::Writes as Query>::init(&mut init, true)?;
            let plan = match anchor.ok_or(LawError::NoAnchor { law: L::NAME })? {
                Anchor::Rows { resolve, name, .. } => {
                    let (rows, get) = resolve(catalog, pb.phase).ok_or(LawError::Unregistered { law: L::NAME, what: name })?;
                    access.read(rows);
                    PlanAnchor::Rows { rows, get }
                }
                Anchor::Network { kind, name, list, revision } => {
                    let (host, _) = catalog.network(kind).ok_or(LawError::Unregistered { law: L::NAME, what: name })?;
                    access.read(host);
                    PlanAnchor::Network { host, list, revision }
                }
                Anchor::Global { .. } => PlanAnchor::Global,
            };
            let state = pb.insert(format!("law:{}", L::NAME), LawState::default());
            let task = law_task::<L>(plan, access, r_state, w_state, state, pb.wakes, dt);
            Ok((task, state))
        });
        self.laws.push(LawDecl {
            name: L::NAME,
            phase_of,
            build,
        });
        LawRef {
            builder: self,
            name: L::NAME,
        }
    }

    /// The frame builder, for registering things the world does not wrap
    /// (a [`crate::field::FieldKind`] via `field::add_field`, extra
    /// resources).
    pub fn sim(&mut self) -> &mut SimBuilder {
        &mut self.sim
    }

    /// Builds the world: instantiates every law in declared order per phase
    /// and appends each phase's collect and conservation tasks.
    ///
    /// # Errors
    /// [`WorldBuildError`] for a law that names unregistered or other-phase
    /// data, an ordering cycle, or a bad sim configuration.
    #[allow(clippy::too_many_lines)]
    pub fn build(mut self) -> Result<World, WorldBuildError> {
        // Order laws.
        let names: Vec<&'static str> = self.laws.iter().map(|l| l.name).collect();
        let order = order_laws(&names, &self.after).map_err(|c: OrderCycle| LawError::Ordering(c))?;
        let mut phases = Vec::with_capacity(self.laws.len());
        for l in &self.laws {
            phases.push((l.phase_of)(&self)?);
        }
        let mut decls: Vec<Option<(LawDecl, Phase)>> = self.laws.drain(..).zip(phases).map(Some).collect();
        let dt = self.config.dt.0;
        let mut main_tasks = Vec::new();
        let mut main_laws = Vec::new();
        let mut worker_laws = Vec::new();
        let mut law_meta = Vec::new();
        {
            let catalog = CatalogView {
                kinds: &self.kinds,
                kind_types: &self.kind_types,
                networks: &self.networks,
                net_types: &self.net_types,
                globals: &self.globals,
            };
            for name in order {
                let i = names.iter().position(|n| *n == name).expect("ordered from names");
                let (decl, phase) = decls[i].take().expect("each law once");
                let mut pb = PhaseBuild {
                    phase,
                    target: match phase {
                        Phase::Main => Target::Main(&mut self.main),
                        Phase::Worker => Target::Worker(&mut self.sim),
                    },
                    wakes: match phase {
                        Phase::Main => self.main_wakes,
                        Phase::Worker => self.worker_wakes,
                    },
                };
                let (task, state) = (decl.build)(&catalog, &mut pb, dt)?;
                law_meta.push((decl.name, phase, state));
                match phase {
                    Phase::Main => {
                        main_tasks.push(task);
                        main_laws.push(state);
                    }
                    Phase::Worker => {
                        self.sim.add_task(task);
                        worker_laws.push(state);
                    }
                }
            }
        }

        // Conservation state and the per-phase collect/check tasks.
        let check = self.config.check_conservation;
        let declared = self.declared.clone();
        let main_cons = self.main.insert(
            "conservation:main",
            Conservation {
                declared: declared.clone(),
                ..Conservation::default()
            },
        );
        let worker_cons = self.sim.add_resource(
            "conservation:worker",
            Conservation {
                declared,
                ..Conservation::default()
            },
        );
        let mut main_sources = Vec::new();
        let mut worker_sources = Vec::new();
        for s in self.sources.drain(..) {
            match s.phase {
                Phase::Main => main_sources.push(s),
                Phase::Worker => worker_sources.push(s),
            }
        }
        main_tasks.push(collect_task("collect:main", &main_laws, self.main_wakes, self.main_out, main_cons));
        let main_check = check.then(|| conserve_task("conserve:main", main_sources, main_cons, self.main_out));
        self.sim
            .add_task(collect_task("collect:worker", &worker_laws, self.worker_wakes, self.worker_out, worker_cons));
        if check {
            self.sim
                .add_task(conserve_task("conserve:worker", worker_sources, worker_cons, self.worker_out));
        }

        let sim = self.sim.build()?;
        Ok(World {
            pacer: Pacer::new(self.config.dt, self.config.backlog_cap),
            config: self.config,
            sim,
            main: self.main,
            main_tasks,
            main_check,
            entities: EntityTable::new(),
            kinds: self.kinds,
            kind_types: self.kind_types,
            networks: self.networks,
            net_types: self.net_types,
            globals: self.globals,
            laws: law_meta,
            main_wakes: self.main_wakes,
            worker_wakes: self.worker_wakes,
            main_out: self.main_out,
            worker_out: self.worker_out,
            pending_worker_wakes: Vec::new(),
            grid: self.grid,
            grid_synced: 0,
            owed: 0,
            frame: 0,
            events: EventSink::new(),
            wakes: Vec::new(),
            violations: Vec::new(),
        })
    }
}

fn collect_task(name: &str, laws: &[Res<LawState>], wakes: Res<FrameWakes>, out: Res<FrameOut>, cons: Res<Conservation>) -> Task {
    let laws: Vec<Res<LawState>> = laws.to_vec();
    let ids: Vec<ResourceId> = laws.iter().map(|l| l.id()).collect();
    let mut task = Task::new(name, move |ctx| {
        let mut next = Vec::new();
        let mut o = ctx.write(out);
        let mut c = ctx.write(cons);
        for &l in &laws {
            let mut ls = ctx.write(l);
            o.events.append(&mut ls.fx.events);
            next.extend(ls.fx.entity_wakes.drain(..).map(EntityId::index));
            c.ledger.absorb(&mut ls.fx.ledger);
        }
        next.sort_unstable();
        next.dedup();
        ctx.write(wakes).entities = next;
    })
    .writes(wakes.id())
    .writes(out.id())
    .writes(cons.id());
    for id in ids {
        task = task.writes(id);
    }
    task
}

fn conserve_task(name: &str, sources: Vec<ConserveSource>, cons: Res<Conservation>, out: Res<FrameOut>) -> Task {
    let mut access = Access::default();
    for s in &sources {
        for &r in &s.access.reads {
            access.read(r);
        }
    }
    let sums: Vec<ConserveFn> = sources.into_iter().map(|s| s.sum).collect();
    let data_access = access.clone();
    let mut task = Task::new(name, move |ctx| {
        let frame = FrameData::lock(ctx, &data_access);
        let mut c = ctx.write(cons);
        let c = &mut *c;
        c.totals.clear();
        let mut crossings = Vec::new();
        for sum in &sums {
            sum(&frame, &mut c.totals, &mut crossings);
        }
        for (kind, name, total) in crossings {
            c.credit_crossings(kind, &[(name, total)]);
        }
        let declared = c.declared.clone();
        let violations = c.ledger.check_all(&c.totals, &declared);
        if !violations.is_empty() {
            ctx.write(out).violations.extend(violations);
        }
    })
    .writes(cons.id())
    .writes(out.id());
    for r in access.reads {
        task = task.reads(r);
    }
    task
}

// --- World ------------------------------------------------------------------------

/// The one simulation world (see the module docs).
pub struct World {
    config: WorldConfig,
    pacer: Pacer,
    sim: Sim,
    main: Resources,
    main_tasks: Vec<Task>,
    main_check: Option<Task>,
    entities: EntityTable,
    kinds: Vec<Box<dyn KindDyn>>,
    kind_types: HashMap<TypeId, KindId>,
    networks: Vec<Box<dyn NetDyn>>,
    net_types: HashMap<TypeId, usize>,
    globals: HashMap<TypeId, (ResourceId, Phase)>,
    laws: Vec<(&'static str, Phase, Res<LawState>)>,
    main_wakes: Res<FrameWakes>,
    worker_wakes: Res<FrameWakes>,
    main_out: Res<FrameOut>,
    worker_out: Res<FrameOut>,
    /// DM-originated wakes for the next worker frame.
    pending_worker_wakes: Vec<u32>,
    grid: Option<(Res<Grid>, Res<Grid>)>,
    /// The main grid's revision at the last worker snapshot.
    grid_synced: u64,
    owed: u32,
    /// Steps completed by the main phase (== frames dispatched).
    frame: u64,
    events: EventSink,
    wakes: Vec<Wake>,
    violations: Vec<Violation>,
}

impl World {
    // ---- Stepping ------------------------------------------------------

    /// One DM tick (see the module docs). Returns whether a step ran.
    pub fn tick(&mut self, elapsed: Seconds) -> bool {
        self.begin_tick();
        self.owed = (self.owed + self.pacer.advance(elapsed)).min(self.config.backlog_cap.max(1));
        if self.owed == 0 || self.sim.frame_running() {
            return false;
        }
        if self.step() {
            self.owed -= 1;
            true
        } else {
            false
        }
    }

    /// Runs one step now regardless of pacing and waits for its worker
    /// frame (tests, replay, shutdown; never on a DM tick).
    pub fn step_blocking(&mut self) {
        self.sim.wait_for_frame();
        self.begin_tick();
        self.step();
        self.sim.wait_for_frame();
        self.begin_tick();
    }

    fn begin_tick(&mut self) {
        self.sim.begin_tick();
        let (sim, main, kinds, wakes) = (&mut self.sim, &mut self.main, &mut self.kinds, &mut self.wakes);
        for k in kinds.iter_mut() {
            k.begin_tick(sim, main, wakes);
        }
        let out = self.worker_out;
        let (events, violations) = (&mut self.events, &mut self.violations);
        sim.with_idle_world(|res| {
            let o = res.get_mut(out);
            events.append(&mut o.events);
            violations.append(&mut o.violations);
        });
    }

    /// The main phase, then the worker dispatch. Returns whether the step
    /// ran (the worker frame could be dispatched).
    fn step(&mut self) -> bool {
        if self.sim.frame_running() {
            return false;
        }
        let frame = self.sim.next_frame();
        // Main phase: commits, laws, collect, conservation, watches.
        for n in &mut self.networks {
            if n.phase() == Phase::Main {
                n.commit(&mut self.main);
            }
        }
        let info = FrameInfo {
            frame,
            seed: self.config.sim.seed,
        };
        run_sequential(&self.main_tasks, &self.main, info);
        if let Some(check) = &self.main_check {
            run_sequential(std::slice::from_ref(check), &self.main, info);
        }
        {
            let o = self.main.get_mut(self.main_out);
            self.events.append(&mut o.events);
            self.violations.append(&mut o.violations);
        }
        for k in &mut self.kinds {
            k.after_main(&self.main, &mut self.wakes);
        }
        // Worker phase.
        let (main, kinds, networks) = (&mut self.main, &mut self.kinds, &mut self.networks);
        let (pending, wakes_res, out) = (&mut self.pending_worker_wakes, self.worker_wakes, self.worker_out);
        let (events, violations) = (&mut self.events, &mut self.violations);
        let (grid, grid_synced) = (self.grid, &mut self.grid_synced);
        let dispatched = self.sim.dispatch_frame_with(|res| {
            if let Some((main_grid, worker_grid)) = grid {
                let g = main.get(main_grid);
                if g.revision() != *grid_synced {
                    *grid_synced = g.revision();
                    let snapshot = g.clone();
                    drop(g);
                    *res.get_mut(worker_grid) = snapshot;
                }
            }
            for k in kinds.iter_mut() {
                k.sync(main, res);
            }
            for n in networks.iter_mut() {
                if n.phase() == Phase::Worker {
                    n.commit(res);
                }
            }
            let w = res.get_mut(wakes_res);
            w.entities.append(pending);
            w.entities.sort_unstable();
            w.entities.dedup();
            let o = res.get_mut(out);
            events.append(&mut o.events);
            violations.append(&mut o.violations);
        });
        if dispatched {
            self.frame = frame + 1;
        }
        dispatched
    }

    /// Runs steps (waiting for each frame) until every DM command is in a
    /// pinned view. Tests and replay only.
    pub fn settle(&mut self) {
        self.sim.settle();
        self.begin_tick();
    }

    /// Simulated time of the next step, s.
    #[must_use]
    #[allow(clippy::cast_precision_loss)]
    pub fn now(&self) -> f64 {
        self.frame as f64 * self.config.dt.0
    }

    /// Steps run so far.
    #[must_use]
    pub const fn frame(&self) -> u64 {
        self.frame
    }

    #[must_use]
    pub const fn config(&self) -> &WorldConfig {
        &self.config
    }

    /// The underlying frame driver (metrics, fields registered through
    /// [`WorldBuilder::sim`]).
    #[must_use]
    pub const fn sim(&self) -> &Sim {
        &self.sim
    }

    pub fn sim_mut(&mut self) -> &mut Sim {
        &mut self.sim
    }

    // ---- Identity ------------------------------------------------------------

    #[must_use]
    pub const fn entities(&self) -> &EntityTable {
        &self.entities
    }

    /// The entity table, for hosts not yet on the world that attach their
    /// own per-domain slots ([`crate::entity::ComponentRef`]).
    pub fn entities_mut(&mut self) -> &mut EntityTable {
        &mut self.entities
    }

    /// A new entity with no components (a reactor token, a probe): the
    /// generic handle every subsystem uses instead of its own slab.
    ///
    /// # Errors
    /// [`EntityError::Full`].
    pub fn spawn(&mut self) -> Result<EntityId, WorldError> {
        Ok(self.entities.bind()?)
    }

    /// Detaches every component the entity has (in this world) and frees it.
    ///
    /// # Errors
    /// A stale or unknown entity.
    pub fn despawn(&mut self, entity: EntityId) -> Result<(), WorldError> {
        self.detach_all(entity)?;
        self.entities.unbind(entity)?;
        Ok(())
    }

    /// Detaches every component the entity has in this world, leaving the
    /// entity itself (other attachments are the caller's).
    ///
    /// # Errors
    /// A stale or unknown entity.
    pub fn detach_all(&mut self, entity: EntityId) -> Result<(), WorldError> {
        if !self.entities.contains(entity) {
            return Err(EntityError::Stale.into());
        }
        let (sim, main) = (&mut self.sim, &mut self.main);
        for k in &mut self.kinds {
            k.unbind(sim, main, entity);
        }
        Ok(())
    }

    // ---- Kinds ----------------------------------------------------------------

    /// The id of registered component `C`.
    #[must_use]
    pub fn kind_of<C: Component>(&self) -> Option<KindId> {
        self.kind_types.get(&TypeId::of::<C>()).copied()
    }

    /// The kind DM names by `domain << 8 | kind` ([`kind_code`]).
    #[must_use]
    pub fn kind_by_code(&self, code: u32) -> Option<KindId> {
        #[allow(clippy::cast_possible_truncation)]
        self.kinds.iter().position(|k| k.code() == code).map(|i| i as KindId)
    }

    /// Every registered kind's schema.
    pub fn schemas(&self) -> impl Iterator<Item = (KindId, Schema)> + '_ {
        #[allow(clippy::cast_possible_truncation)]
        self.kinds.iter().enumerate().map(|(i, k)| (i as KindId, k.schema()))
    }

    fn kind(&self, kind: KindId) -> Result<&dyn KindDyn, WorldError> {
        self.kinds
            .get(usize::from(kind))
            .map(AsRef::as_ref)
            .ok_or(WorldError::NoKind(u32::from(kind)))
    }

    fn live(&self, entity: EntityId) -> Result<(), WorldError> {
        if self.entities.contains(entity) {
            Ok(())
        } else {
            Err(EntityError::Stale.into())
        }
    }

    fn wake(&mut self, kind: KindId, entity: EntityId) {
        let phase = Phase::of(self.kinds[usize::from(kind)].owner());
        match phase {
            Phase::Worker => self.pending_worker_wakes.push(entity.index()),
            Phase::Main => self.main.get_mut(self.main_wakes).entities.push(entity.index()),
        }
    }

    /// Binds `kind` to `entity` (a fresh entity if `None`), starting from
    /// the component's defaults with `init` applied as DM writes (validated
    /// like any `set`). Returns the entity.
    ///
    /// # Errors
    /// A stale entity, an unknown kind or a rejected init value.
    pub fn bind(&mut self, entity: Option<EntityId>, kind: KindId, init: &[(FieldId, Option<usize>, f64)]) -> Result<EntityId, WorldError> {
        self.kind(kind)?;
        let e = match entity {
            Some(e) => {
                self.live(e)?;
                e
            }
            None => self.entities.bind()?,
        };
        let (sim, main) = (&mut self.sim, &mut self.main);
        if let Err(err) = self.kinds[usize::from(kind)].bind(sim, main, e, init) {
            if entity.is_none() {
                let _ = self.entities.unbind(e);
            }
            return Err(err);
        }
        self.wake(kind, e);
        Ok(e)
    }

    /// Typed bind of a whole value.
    ///
    /// # Errors
    /// As [`bind`](Self::bind).
    pub fn bind_value<C: Component>(&mut self, entity: Option<EntityId>, value: C) -> Result<EntityId, WorldError> {
        let kind = self.kind_of::<C>().ok_or(WorldError::NoKind(kind_code(C::DOMAIN_ID, C::KIND)))?;
        let e = self.bind(entity, kind, &[])?;
        self.put(e, value)?;
        Ok(e)
    }

    /// Detaches `kind` from `entity`.
    ///
    /// # Errors
    /// A stale entity or unknown kind.
    pub fn detach(&mut self, entity: EntityId, kind: KindId) -> Result<(), WorldError> {
        self.live(entity)?;
        self.kind(kind)?;
        let (sim, main) = (&mut self.sim, &mut self.main);
        self.kinds[usize::from(kind)].unbind(sim, main, entity);
        Ok(())
    }

    /// Whether `entity` has a `kind` component.
    #[must_use]
    pub fn has(&self, entity: EntityId, kind: KindId) -> bool {
        self.kind(kind).is_ok_and(|k| k.holds(&self.main, entity))
    }

    /// Every kind attached to `entity`.
    pub fn kinds_of(&self, entity: EntityId) -> impl Iterator<Item = KindId> + '_ {
        #[allow(clippy::cast_possible_truncation)]
        self.kinds
            .iter()
            .enumerate()
            .filter(move |(_, k)| k.holds(&self.main, entity))
            .map(|(i, _)| i as KindId)
    }

    /// DM's read of one field (what DM sees now: its own writes over the
    /// pinned frame).
    ///
    /// # Errors
    /// A stale entity, missing component or unknown field.
    pub fn get(&self, entity: EntityId, kind: KindId, field: FieldId, index: usize) -> Result<f64, WorldError> {
        self.live(entity)?;
        self.kind(kind)?.get(&self.sim, &self.main, entity, field, index)
    }

    /// DM's write of one field (validated; wakes the entity's laws).
    ///
    /// # Errors
    /// A stale entity, missing component, read-only field or rejected
    /// value.
    pub fn set(&mut self, entity: EntityId, kind: KindId, field: FieldId, index: Option<usize>, value: f64) -> Result<(), WorldError> {
        self.live(entity)?;
        self.kind(kind)?;
        let (sim, main) = (&mut self.sim, &mut self.main);
        self.kinds[usize::from(kind)].set(sim, main, entity, field, index, value)?;
        self.wake(kind, entity);
        Ok(())
    }

    /// DM's take/give on a conserved field (take reconciliation, §4.2):
    /// adds `delta` to the owner's current value; returns the removal
    /// shortfall as DM's view saw it.
    ///
    /// # Errors
    /// As [`set`](Self::set), or a field that is not conserved.
    pub fn adjust(&mut self, entity: EntityId, kind: KindId, field: FieldId, index: usize, delta: f64) -> Result<f32, WorldError> {
        self.live(entity)?;
        self.kind(kind)?;
        let (sim, main) = (&mut self.sim, &mut self.main);
        let shortfall = self.kinds[usize::from(kind)].adjust(sim, main, entity, field, index, delta)?;
        self.wake(kind, entity);
        Ok(shortfall)
    }

    /// Typed read of a whole row.
    #[must_use]
    pub fn read<C: Component>(&self, entity: EntityId) -> Option<C> {
        let k = self.kind_of::<C>()?;
        let entry = self.kinds[usize::from(k)].as_any().downcast_ref::<KindEntry<C>>()?;
        entry.value(&self.sim, &self.main, entity).ok()
    }

    /// Typed command (a law-free write from Rust: tests, bridges).
    ///
    /// # Errors
    /// A stale entity or missing component.
    pub fn submit<C: Component>(&mut self, entity: EntityId, cmd: &<C::Kind as Domain>::Command) -> Result<Applied, WorldError> {
        self.live(entity)?;
        let k = self.kind_of::<C>().ok_or(WorldError::NoKind(kind_code(C::DOMAIN_ID, C::KIND)))?;
        let entry = self.kinds[usize::from(k)]
            .as_any()
            .downcast_ref::<KindEntry<C>>()
            .expect("kind type");
        let (main_res, domain) = (entry.main, entry.domain);
        let applied = submit_row::<C>(main_res, domain, &mut self.sim, &mut self.main, entity, cmd)?;
        self.wake(k, entity);
        Ok(applied)
    }

    /// Replaces a whole row (a transfer in: `Op::Put` for worker kinds).
    ///
    /// # Errors
    /// A stale entity or missing component.
    pub fn put<C: Component>(&mut self, entity: EntityId, value: C) -> Result<(), WorldError> {
        self.live(entity)?;
        let k = self.kind_of::<C>().ok_or(WorldError::NoKind(kind_code(C::DOMAIN_ID, C::KIND)))?;
        let entry = self.kinds[usize::from(k)]
            .as_any()
            .downcast_ref::<KindEntry<C>>()
            .expect("kind type");
        let (main_res, domain) = (entry.main, entry.domain);
        let mk = self.main.get_mut(main_res);
        if !mk.rows.holds(entity) {
            return Err(ComponentError::Missing { kind: C::NAME }.into());
        }
        match domain {
            Some(key) => self.sim.port(key).put(entity.index(), value)?,
            None => {
                if let Some(slot) = mk.get_mut(entity.index()) {
                    *slot = value;
                }
            }
        }
        self.wake(k, entity);
        Ok(())
    }

    /// `vg_describe`: every attached component's fields as text.
    #[must_use]
    pub fn describe(&self, entity: EntityId) -> Vec<(&'static str, Vec<(String, String)>)> {
        self.kinds
            .iter()
            .filter(|k| k.holds(&self.main, entity))
            .map(|k| (k.name(), k.describe(&self.sim, &self.main, entity)))
            .collect()
    }

    // ---- Watches and events ------------------------------------------------------

    /// Registers a watch on `kind`'s rows (a condition over its field
    /// channels; cells are entity slot indices). Fired wakes arrive through
    /// [`drain_wakes`](Self::drain_wakes).
    ///
    /// # Errors
    /// An unknown kind, a kind without channels, or an invalid condition.
    pub fn watch(&mut self, kind: KindId, subscriber: Subscriber, lane: Lane, cond: &Cond) -> Result<WatchId, WorldError> {
        self.kind(kind)?;
        self.kinds[usize::from(kind)].watch(&mut self.sim, subscriber, lane, cond)
    }

    /// Removes a watch.
    ///
    /// # Errors
    /// An unknown kind or a stale watch.
    pub fn unwatch(&mut self, kind: KindId, id: WatchId) -> Result<(), WorldError> {
        self.kind(kind)?;
        self.kinds[usize::from(kind)].unwatch(&mut self.sim, id)
    }

    /// `kind`'s watch channels (one per numeric field).
    ///
    /// # Errors
    /// An unknown kind.
    pub fn channels(&self, kind: KindId) -> Result<Vec<ChannelInfo>, WorldError> {
        Ok(self.kind(kind)?.channels())
    }

    /// Every typed event produced since the last drain, in wire form
    /// ([`crate::event`]): the one event list DM receives.
    pub fn drain_events(&mut self) -> EventSink {
        std::mem::take(&mut self.events)
    }

    /// Every watch wake fired since the last drain (feed them to the
    /// reactor's lanes).
    pub fn drain_wakes(&mut self, out: &mut Vec<Wake>) {
        out.append(&mut self.wakes);
    }

    /// Conservation violations found since the last call.
    pub fn violations(&mut self) -> Vec<Violation> {
        std::mem::take(&mut self.violations)
    }

    /// Per-law statistics (items stepped last run, items awake).
    #[must_use]
    pub fn law_stats(&mut self) -> Vec<LawStats> {
        let laws = self.laws.clone();
        let main = &self.main;
        let mut out = Vec::with_capacity(laws.len());
        for (name, phase, state) in laws {
            let stat = |ls: &LawState| LawStats {
                name,
                phase,
                stepped: ls.stepped,
                awake: ls.activity.awake_count(),
            };
            let s = match phase {
                Phase::Main => Some(stat(&main.get(state))),
                Phase::Worker => self.sim.with_idle_world(|res| stat(res.get_mut(state))),
            };
            if let Some(s) = s {
                out.push(s);
            }
        }
        out
    }

    // ---- Networks and globals ------------------------------------------------------

    fn net_entry<K: NetworkKind>(&mut self) -> Option<&mut NetEntry<K>> {
        let n = *self.net_types.get(&TypeId::of::<K>())?;
        self.networks[n].as_any_mut().downcast_mut::<NetEntry<K>>()
    }

    /// Shared access to a main-owned network.
    ///
    /// # Errors
    /// [`WorldError::WorkerOwned`] for a worker network, `NoKind` if
    /// unregistered.
    pub fn network<K: NetworkKind>(&self) -> Result<Ref<'_, NetworkHost<K>>, WorldError> {
        let n = *self.net_types.get(&TypeId::of::<K>()).ok_or(WorldError::NoKind(0))?;
        let entry = &self.networks[n];
        if entry.phase() != Phase::Main {
            return Err(WorldError::WorkerOwned(K::NAME));
        }
        Ok(self.main.get(Res::<NetworkHost<K>>::from_id(entry.resource())))
    }

    /// Edits a network: at once for a main-owned network (DM binds nodes,
    /// reads and writes region payloads synchronously), queued to the next
    /// dispatch for a worker-owned one. Topology is committed at the next
    /// step either way.
    ///
    /// # Errors
    /// `NoKind` if unregistered.
    pub fn edit_network<K: NetworkKind>(&mut self, edit: impl FnOnce(&mut NetworkHost<K>) + Send + 'static) -> Result<(), WorldError> {
        let entry = self.net_entry::<K>().ok_or(WorldError::NoKind(0))?;
        match entry.phase {
            Phase::Main => {
                let host = entry.host;
                edit(self.main.get_mut(host));
            }
            Phase::Worker => entry.queued.push(Box::new(edit)),
        }
        Ok(())
    }

    /// Commits a main-owned network's pending topology now (DM wants the
    /// new regions this tick rather than at the next step).
    pub fn commit_network<K: NetworkKind>(&mut self) {
        let Some(&n) = self.net_types.get(&TypeId::of::<K>()) else {
            return;
        };
        if self.networks[n].phase() == Phase::Main {
            self.networks[n].commit(&mut self.main);
        }
    }

    /// Region transitions since the last drain (DM rebuilds wrappers).
    pub fn drain_transitions<K: NetworkKind>(&mut self) -> Vec<Transition> {
        self.net_entry::<K>().map(|e| std::mem::take(&mut e.transitions)).unwrap_or_default()
    }

    /// Raw region events since the last drain.
    pub fn drain_region_events<K: NetworkKind>(&mut self) -> Vec<RegionEvent<K>> {
        self.net_entry::<K>().map(|e| std::mem::take(&mut e.events)).unwrap_or_default()
    }

    /// The world's grid (main thread, authoritative).
    ///
    /// # Errors
    /// `NoKind(0)` if the world has no grid.
    pub fn grid(&self) -> Result<Ref<'_, Grid>, WorldError> {
        let (main, _) = self.grid.ok_or(WorldError::NoKind(0))?;
        Ok(self.main.get(main))
    }

    /// Edits the grid (a door closing, a wall built, z links at map load).
    /// Worker readers see the change from the next dispatch.
    ///
    /// # Errors
    /// `NoKind(0)` if the world has no grid.
    pub fn edit_grid<R>(&mut self, edit: impl FnOnce(&mut Grid) -> R) -> Result<R, WorldError> {
        let (main, _) = self.grid.ok_or(WorldError::NoKind(0))?;
        Ok(edit(self.main.get_mut(main)))
    }

    /// A main-owned global.
    ///
    /// # Errors
    /// Unregistered or worker-owned.
    pub fn global<T: Any + Send + Sync>(&self) -> Result<Ref<'_, T>, WorldError> {
        let &(id, phase) = self.globals.get(&TypeId::of::<T>()).ok_or(WorldError::NoKind(0))?;
        if phase != Phase::Main {
            return Err(WorldError::WorkerOwned(std::any::type_name::<T>()));
        }
        Ok(self.main.get(Res::<T>::from_id(id)))
    }

    /// Mutable access to a main-owned global.
    ///
    /// # Errors
    /// Unregistered or worker-owned.
    pub fn global_mut<T: Any + Send + Sync>(&mut self) -> Result<&mut T, WorldError> {
        let &(id, phase) = self.globals.get(&TypeId::of::<T>()).ok_or(WorldError::NoKind(0))?;
        if phase != Phase::Main {
            return Err(WorldError::WorkerOwned(std::any::type_name::<T>()));
        }
        Ok(self.main.get_mut(Res::<T>::from_id(id)))
    }
}
