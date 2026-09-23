//! The simulation driver: domains, the frame pool, backpressure, recording
//! and replay (`rust_core.md` §3.6–§3.9, §3.11).
//!
//! A [`Sim`] lives on the main thread. Each tick DM calls
//! [`begin_tick`](Sim::begin_tick) (reclaim a finished frame, pin the newest
//! views), reads and writes through each domain's [`MainPort`], and on frame
//! ticks calls [`dispatch_frame`](Sim::dispatch_frame). Dispatch moves the
//! queued command batches into the idle frame world and spawns the frame on
//! the dedicated pool; the world comes back through an atomic mailbox. If
//! the previous frame is still running, dispatch does nothing and commands
//! keep queuing (§3.8): DM never waits.

use std::any::Any;
use std::cell::Cell;
use std::marker::PhantomData;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::cow::ChunkLayout;
use crate::frame::{FrameInfo, Res, ResourceId, Resources, Schedule, Task, run_frame};
use crate::mailbox::Latest;
use crate::owner::{Domain, DomainKey, DomainState, MainPort};

/// How DM writes to worker-owned cells are handled.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    /// Commands, views and the overlay (§3.2–§3.4).
    Overlay,
    /// The main-thread fallback (§3.11): DM owns live state, frames return
    /// deltas, and the main thread applies at most `budget_cells` changed
    /// cells per tick, one chunk-sized piece at a time.
    Fallback { budget_cells: usize },
}

/// Construction options.
#[derive(Clone, Debug)]
pub struct SimConfig {
    /// Frame pool threads. The default leaves two cores for BYOND (§3.7).
    pub threads: usize,
    /// World seed for [`TaskCtx::rng`](crate::frame::TaskCtx::rng).
    pub seed: u64,
    pub mode: Mode,
    /// Keep a flight-recorder log of every dispatched batch (§3.9, §11).
    pub record: bool,
    /// View age (in ticks) past which a tick counts as over budget (§3.8).
    pub view_age_budget_ticks: u32,
}

impl Default for SimConfig {
    fn default() -> Self {
        Self {
            threads: std::thread::available_parallelism()
                .map_or(1, |n| n.get().saturating_sub(2))
                .max(1),
            seed: 0,
            mode: Mode::Overlay,
            record: false,
            view_age_budget_ticks: 4,
        }
    }
}

/// Backpressure and frame metrics (§3.8). Plain main-thread data.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct SimMetrics {
    pub ticks: u64,
    pub frames_dispatched: u64,
    pub frames_completed: u64,
    /// Dispatches skipped because a frame was still running.
    pub dispatches_skipped: u64,
    pub last_frame: Duration,
    pub max_frame: Duration,
    /// Commands issued but not yet in a pinned view, over all domains.
    pub command_backlog: u64,
    /// Largest per-domain view age this tick.
    pub view_age_ticks: u32,
    /// Ticks whose view age exceeded the budget.
    pub view_age_over_budget: u64,
    pub overlay_entries: usize,
    pub frame_panics: u64,
    pub last_panic: Option<String>,
}

/// One dispatched frame in the flight recorder: its number and each
/// domain's command batch (type-erased, by domain index).
pub struct FrameRecord {
    pub frame: u64,
    batches: Vec<Option<Box<dyn Any + Send + Sync>>>,
}

impl FrameRecord {
    /// A record from its parts (the replay codec's decoder builds these).
    #[must_use]
    pub fn new(frame: u64, batches: Vec<Option<Box<dyn Any + Send + Sync>>>) -> Self {
        Self { frame, batches }
    }

    /// Each domain's batch, by domain index (`None`: no commands).
    #[must_use]
    pub fn batches(&self) -> &[Option<Box<dyn Any + Send + Sync>>] {
        &self.batches
    }
}

/// The flight-recorder log (§3.9): enough to replay a session.
#[derive(Default)]
pub struct FrameLog {
    pub seed: u64,
    pub frames: Vec<FrameRecord>,
}

type PublishFn = fn(&mut (dyn Any + Send + Sync)) -> Arc<dyn Any + Send + Sync>;

/// The worker-side world: moved into a frame job while it runs, and back to
/// the main thread when it finishes.
struct World {
    resources: Resources,
    tasks: Vec<Task>,
    schedule: Schedule,
    publishers: Vec<(ResourceId, PublishFn)>,
    prev: Vec<Option<Arc<dyn Any + Send + Sync>>>,
    seed: u64,
    last_duration: Duration,
    panic: Option<String>,
}

impl World {
    /// Runs one frame and publishes every domain's view. Call on the pool.
    fn run(&mut self, frame: u64) {
        let start = Instant::now();
        let info = FrameInfo {
            frame,
            seed: self.seed,
        };
        let result = catch_unwind(AssertUnwindSafe(|| {
            run_frame(
                &self.tasks,
                &self.schedule,
                &self.resources,
                &self.prev,
                info,
            );
        }));
        if let Err(payload) = result {
            self.panic = Some(
                payload
                    .downcast_ref::<&str>()
                    .map(ToString::to_string)
                    .or_else(|| payload.downcast_ref::<String>().cloned())
                    .unwrap_or_else(|| "frame task panicked".to_owned()),
            );
        }
        for (domain, (res, publish)) in self.publishers.iter().enumerate() {
            self.prev[domain] = Some(publish(self.resources.erased_mut(*res)));
        }
        self.last_duration = start.elapsed();
    }
}

/// The main-thread half of a port, type-erased so the `Sim` can hold ports
/// of every domain.
trait PortDyn: Any {
    fn begin_tick(&mut self, budget: &mut usize);
    fn ready(&self) -> bool;
    fn dispatch(&mut self, res: &mut Resources, record: bool)
    -> Option<Box<dyn Any + Send + Sync>>;
    fn load_recorded(&self, res: &mut Resources, batch: &(dyn Any + Send + Sync));
    fn backlog(&self) -> u64;
    fn view_age(&self) -> u32;
    fn overlay_len(&self) -> usize;
    fn as_any_mut(&mut self) -> &mut dyn Any;
    fn as_any(&self) -> &dyn Any;
}

impl<D: Domain> PortDyn for MainPort<D> {
    fn begin_tick(&mut self, budget: &mut usize) {
        MainPort::begin_tick(self, budget);
    }
    fn ready(&self) -> bool {
        MainPort::ready(self)
    }
    fn dispatch(
        &mut self,
        res: &mut Resources,
        record: bool,
    ) -> Option<Box<dyn Any + Send + Sync>> {
        let state = res.get_mut(self.state_res());
        MainPort::dispatch(self, state, record)
    }
    fn load_recorded(&self, res: &mut Resources, batch: &(dyn Any + Send + Sync)) {
        let batch = batch
            .downcast_ref::<Vec<crate::command::Sequenced<crate::owner::DomainOp<D>>>>()
            .expect("recorded batch type mismatch");
        res.get_mut(self.state_res()).enqueue(batch.clone());
    }
    fn backlog(&self) -> u64 {
        MainPort::backlog(self)
    }
    fn view_age(&self) -> u32 {
        self.view_age_ticks()
    }
    fn overlay_len(&self) -> usize {
        MainPort::overlay_len(self)
    }
    fn as_any_mut(&mut self) -> &mut dyn Any {
        self
    }
    fn as_any(&self) -> &dyn Any {
        self
    }
}

/// Registers domains, resources and tasks, then [`build`](Self::build)s.
pub struct SimBuilder {
    config: SimConfig,
    resources: Resources,
    apply_tasks: Vec<Task>,
    tasks: Vec<Task>,
    publishers: Vec<(ResourceId, PublishFn)>,
    ports: Vec<Box<dyn PortDyn>>,
}

impl SimBuilder {
    #[must_use]
    pub fn new(config: SimConfig) -> Self {
        Self {
            config,
            resources: Resources::new(),
            apply_tasks: Vec::new(),
            tasks: Vec::new(),
            publishers: Vec::new(),
            ports: Vec::new(),
        }
    }

    /// Registers a domain with one cell per index of `layout`. Its apply
    /// task runs before every other task each frame.
    pub fn add_domain<D: Domain>(&mut self, layout: ChunkLayout) -> DomainKey<D> {
        let outbox = Arc::new(Latest::new());
        let state = self
            .resources
            .insert(D::NAME, DomainState::<D>::new(layout, Arc::clone(&outbox)));
        let index = self.ports.len();
        self.apply_tasks.push(
            Task::new(format!("apply:{}", D::NAME), move |ctx| {
                ctx.write(state).apply_pending();
            })
            .writes(state.id()),
        );
        self.publishers
            .push((state.id(), DomainState::<D>::publish));
        let fallback = matches!(self.config.mode, Mode::Fallback { .. });
        self.ports.push(Box::new(MainPort::<D>::new(
            layout, outbox, state, fallback,
        )));
        DomainKey { index, state }
    }

    /// Adds a worker-side resource (an exchange buffer, an active set, ...).
    pub fn add_resource<T: Any + Send + Sync>(
        &mut self,
        name: impl Into<String>,
        value: T,
    ) -> Res<T> {
        self.resources.insert(name, value)
    }

    /// Adds a frame task. Conflicting tasks run in declaration order.
    pub fn add_task(&mut self, task: Task) -> &mut Self {
        self.tasks.push(task);
        self
    }

    /// Builds the pool and the world.
    ///
    /// # Errors
    /// If the thread pool cannot be created.
    pub fn build(self) -> Result<Sim, rayon::ThreadPoolBuildError> {
        let pool = rayon::ThreadPoolBuilder::new()
            .num_threads(self.config.threads.max(1))
            .thread_name(|i| format!("vg-frame-{i}"))
            .build()?;
        let mut tasks = self.apply_tasks;
        tasks.extend(self.tasks);
        let schedule = Schedule::build(&tasks);
        let domains = self.publishers.len();
        let world = World {
            resources: self.resources,
            tasks,
            schedule,
            publishers: self.publishers,
            prev: vec![None; domains],
            seed: self.config.seed,
            last_duration: Duration::ZERO,
            panic: None,
        };
        let log = self.config.record.then(|| FrameLog {
            seed: self.config.seed,
            frames: Vec::new(),
        });
        Ok(Sim {
            pool: Arc::new(pool),
            world: Some(Box::new(world)),
            done: Arc::new(Latest::new()),
            ports: self.ports,
            next_frame: 0,
            metrics: SimMetrics::default(),
            log,
            config: self.config,
            _main_thread_only: PhantomData,
        })
    }
}

/// The main-thread simulation handle. `!Send + !Sync`: it belongs to the
/// DM thread, and nothing it does on that thread takes a lock.
pub struct Sim {
    config: SimConfig,
    pool: Arc<rayon::ThreadPool>,
    /// `Some` while no frame is running.
    world: Option<Box<World>>,
    done: Arc<Latest<Box<World>>>,
    ports: Vec<Box<dyn PortDyn>>,
    next_frame: u64,
    metrics: SimMetrics,
    log: Option<FrameLog>,
    _main_thread_only: PhantomData<*const Cell<()>>,
}

impl Sim {
    /// Start of a DM tick: reclaim a finished frame if there is one, pin
    /// every domain's newest view, prune overlays, and (fallback) apply
    /// deltas within budget. Never waits.
    pub fn begin_tick(&mut self) {
        self.metrics.ticks += 1;
        self.reclaim();
        let mut budget = match self.config.mode {
            Mode::Overlay => usize::MAX,
            Mode::Fallback { budget_cells } => budget_cells,
        };
        let mut backlog = 0;
        let mut age = 0;
        let mut overlay = 0;
        for port in &mut self.ports {
            port.begin_tick(&mut budget);
            backlog += port.backlog();
            age = age.max(port.view_age());
            overlay += port.overlay_len();
        }
        self.metrics.command_backlog = backlog;
        self.metrics.view_age_ticks = age;
        self.metrics.overlay_entries = overlay;
        if age > self.config.view_age_budget_ticks {
            self.metrics.view_age_over_budget += 1;
        }
    }

    /// Frame boundary: if no frame is running, hand every queued command
    /// batch to the world and start the next frame on the pool. Returns
    /// `false` (and changes nothing) if a frame is still running (§3.8).
    pub fn dispatch_frame(&mut self) -> bool {
        self.reclaim();
        if self.world.is_none() || !self.ports.iter().all(|p| p.ready()) {
            self.metrics.dispatches_skipped += 1;
            return false;
        }
        let mut world = self.world.take().expect("checked above");
        let frame = self.next_frame;
        self.next_frame += 1;
        let record = self.log.is_some();
        let batches: Vec<_> = self
            .ports
            .iter_mut()
            .map(|p| p.dispatch(&mut world.resources, record))
            .collect();
        if let Some(log) = &mut self.log {
            log.frames.push(FrameRecord { frame, batches });
        }
        let done = Arc::clone(&self.done);
        self.pool.spawn(move || {
            world.run(frame);
            done.put(world);
        });
        self.metrics.frames_dispatched += 1;
        true
    }

    /// Takes back a finished world, if any.
    fn reclaim(&mut self) {
        if self.world.is_some() {
            return;
        }
        if let Some(mut world) = self.done.take() {
            self.metrics.frames_completed += 1;
            self.metrics.last_frame = world.last_duration;
            self.metrics.max_frame = self.metrics.max_frame.max(world.last_duration);
            if let Some(panic) = world.panic.take() {
                self.metrics.frame_panics += 1;
                self.metrics.last_panic = Some(panic);
            }
            self.world = Some(world);
        }
    }

    /// Whether a frame is running.
    #[must_use]
    pub fn frame_running(&self) -> bool {
        self.world.is_none() && !self.done.is_full()
    }

    /// Blocks (yielding) until the running frame finishes. For tests,
    /// replay and shutdown only: never call it on a DM tick.
    pub fn wait_for_frame(&mut self) {
        while self.world.is_none() && !self.done.is_full() {
            std::thread::yield_now();
        }
        self.reclaim();
    }

    /// Runs ticks (waiting for each frame) until every command issued so far
    /// is in a pinned view and every overlay is empty. For tests and replay.
    pub fn settle(&mut self) {
        loop {
            self.wait_for_frame();
            self.begin_tick();
            let caught_up = self.metrics.command_backlog == 0
                && self.metrics.overlay_entries == 0
                && self.ports.iter().all(|p| p.ready());
            if caught_up {
                return;
            }
            self.dispatch_frame();
        }
    }

    /// A domain's DM-facing port.
    ///
    /// # Panics
    /// If `key` is from another `Sim`.
    pub fn port<D: Domain>(&mut self, key: DomainKey<D>) -> &mut MainPort<D> {
        self.ports[key.index]
            .as_any_mut()
            .downcast_mut()
            .expect("domain key from another Sim")
    }

    /// Shared access to a domain's port.
    ///
    /// # Panics
    /// If `key` is from another `Sim`.
    #[must_use]
    pub fn port_ref<D: Domain>(&self, key: DomainKey<D>) -> &MainPort<D> {
        self.ports[key.index]
            .as_any()
            .downcast_ref()
            .expect("domain key from another Sim")
    }

    #[must_use]
    pub const fn metrics(&self) -> &SimMetrics {
        &self.metrics
    }

    #[must_use]
    pub const fn config(&self) -> &SimConfig {
        &self.config
    }

    /// The flight-recorder log, if recording.
    #[must_use]
    pub const fn log(&self) -> Option<&FrameLog> {
        self.log.as_ref()
    }

    /// Takes the flight-recorder log (recording continues into a new one).
    pub fn take_log(&mut self) -> Option<FrameLog> {
        let seed = self.config.seed;
        self.log.as_mut().map(|log| {
            std::mem::replace(
                log,
                FrameLog {
                    seed,
                    frames: Vec::new(),
                },
            )
        })
    }

    /// Replays a recorded log into a freshly built sim (same domains and
    /// tasks, in the same order), running each frame synchronously on its
    /// pool, and pins the final views. Commands are applied in sequence
    /// order and tasks are deterministic, so the views match the recorded
    /// session bit for bit (§3.9).
    ///
    /// # Errors
    /// If the thread pool cannot be created.
    ///
    /// # Panics
    /// If the builder is in fallback mode, or its domains differ from the
    /// recorded ones.
    pub fn replay(
        mut builder: SimBuilder,
        log: &FrameLog,
    ) -> Result<Sim, rayon::ThreadPoolBuildError> {
        assert_eq!(
            builder.config.mode,
            Mode::Overlay,
            "replay needs overlay mode"
        );
        builder.config.seed = log.seed;
        builder.config.record = false;
        let mut sim = builder.build()?;
        for record in &log.frames {
            let mut world = sim.world.take().expect("replay runs frames synchronously");
            assert_eq!(
                record.batches.len(),
                sim.ports.len(),
                "domain count differs"
            );
            for (port, batch) in sim.ports.iter().zip(&record.batches) {
                if let Some(batch) = batch {
                    port.load_recorded(&mut world.resources, batch.as_ref());
                }
            }
            sim.pool.install(|| world.run(record.frame));
            sim.world = Some(world);
            sim.next_frame = record.frame + 1;
            sim.metrics.frames_dispatched += 1;
            sim.metrics.frames_completed += 1;
        }
        sim.begin_tick();
        Ok(sim)
    }
}
