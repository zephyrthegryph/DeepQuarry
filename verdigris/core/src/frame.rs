//! Frames and the task graph (`rust_core.md` §3.6).
//!
//! A frame is one simulation step, run as a small task graph. Each [`Task`]
//! declares the [`Resources`] it reads and writes; [`Schedule::build`] puts
//! every task after each earlier-declared task it conflicts with (one writes
//! what the other reads or writes) and groups the tasks into levels. Levels
//! run in order; the tasks in one level run in parallel with `rayon::scope`
//! on the frame pool (§3.7), and each task parallelises by chunk inside.
//!
//! Resources live in `RwLock`s only so that the borrow checker accepts
//! disjoint access from parallel tasks. The schedule guarantees the locks
//! are never contended, and access uses `try_read`/`try_write`, so a frame
//! never waits on a lock; contention would be a scheduler bug and panics.
//! None of this is reachable from the DM thread: the main thread only
//! touches resources while it holds the whole idle world by value
//! (`RwLock::get_mut`, which does not lock).

use std::any::Any;
use std::fmt;
use std::marker::PhantomData;
use std::ops::{Deref, DerefMut};
use std::sync::{Arc, PoisonError, RwLock, RwLockReadGuard, RwLockWriteGuard, TryLockError};

use crate::rng::{Rng, RngStreams, StreamId};

/// Index of a resource in a world's [`Resources`].
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct ResourceId(pub u16);

/// A typed key for a resource.
pub struct Res<T> {
    id: ResourceId,
    _marker: PhantomData<fn() -> T>,
}

impl<T> Res<T> {
    #[must_use]
    pub const fn id(self) -> ResourceId {
        self.id
    }

    /// Re-types a resource id. Only for registries that stored the id
    /// erased next to the type it was inserted with: a wrong `T` panics on
    /// first access (`resource type mismatch`), never reads garbage.
    #[must_use]
    pub const fn from_id(id: ResourceId) -> Self {
        Self {
            id,
            _marker: PhantomData,
        }
    }
}

impl<T> Clone for Res<T> {
    fn clone(&self) -> Self {
        *self
    }
}
impl<T> Copy for Res<T> {}
impl<T> fmt::Debug for Res<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Res({})", self.id.0)
    }
}

/// A resource as stored: boxed and type-erased.
pub type Erased = Box<dyn Any + Send + Sync>;

/// The worker-side state of a world: domain states, exchange buffers and
/// any other per-frame data, each one a resource.
#[derive(Default)]
pub struct Resources {
    slots: Vec<RwLock<Erased>>,
    names: Vec<String>,
}

impl Resources {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Adds a resource.
    ///
    /// # Panics
    /// If more than `u16::MAX` resources are added.
    pub fn insert<T: Any + Send + Sync>(&mut self, name: impl Into<String>, value: T) -> Res<T> {
        let id = ResourceId(u16::try_from(self.slots.len()).expect("too many resources"));
        self.slots.push(RwLock::new(Box::new(value)));
        self.names.push(name.into());
        Res {
            id,
            _marker: PhantomData,
        }
    }

    #[must_use]
    pub fn len(&self) -> usize {
        self.slots.len()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.slots.is_empty()
    }

    #[must_use]
    pub fn name(&self, id: ResourceId) -> &str {
        &self.names[usize::from(id.0)]
    }

    /// Exclusive access with no locking (the caller holds `&mut self`).
    ///
    /// # Panics
    /// If `res` is from another world (wrong type).
    pub fn get_mut<T: Any>(&mut self, res: Res<T>) -> &mut T {
        self.erased_mut(res.id)
            .downcast_mut()
            .expect("resource type mismatch")
    }

    /// Shared access from the main thread while it holds the idle world
    /// (no task can hold a conflicting guard then).
    ///
    /// # Panics
    /// If `res` is from another world (wrong type), or is being written.
    #[must_use]
    pub fn get<T: Any>(&self, res: Res<T>) -> Ref<'_, T> {
        let guard = match self.slots[usize::from(res.id.0)].try_read() {
            Ok(g) => g,
            Err(TryLockError::Poisoned(p)) => p.into_inner(),
            Err(TryLockError::WouldBlock) => panic!("resource `{}` is held", self.name(res.id)),
        };
        Ref {
            guard,
            _marker: PhantomData,
        }
    }

    pub(crate) fn erased_mut(&mut self, id: ResourceId) -> &mut (dyn Any + Send + Sync) {
        self.slots[usize::from(id.0)]
            .get_mut()
            .unwrap_or_else(PoisonError::into_inner)
            .as_mut()
    }
}

/// A task body.
pub type TaskFn = Box<dyn Fn(&TaskCtx<'_>) + Send + Sync>;

/// One node of the frame graph.
pub struct Task {
    name: String,
    reads: Vec<ResourceId>,
    writes: Vec<ResourceId>,
    every: u32,
    run: TaskFn,
}

impl Task {
    pub fn new(
        name: impl Into<String>,
        run: impl Fn(&TaskCtx<'_>) + Send + Sync + 'static,
    ) -> Self {
        Self {
            name: name.into(),
            reads: Vec::new(),
            writes: Vec::new(),
            every: 1,
            run: Box::new(run),
        }
    }

    /// Declares a read.
    #[must_use]
    pub fn reads(mut self, id: ResourceId) -> Self {
        self.reads.push(id);
        self
    }

    /// Declares a write (which also allows reading).
    #[must_use]
    pub fn writes(mut self, id: ResourceId) -> Self {
        self.writes.push(id);
        self
    }

    /// Runs only on frames divisible by `n` (a slower domain skipping frames,
    /// §3.6). Coupled tasks must share a rate.
    #[must_use]
    pub fn every(mut self, n: u32) -> Self {
        self.every = n.max(1);
        self
    }

    #[must_use]
    pub fn name(&self) -> &str {
        &self.name
    }

    fn may_read(&self, id: ResourceId) -> bool {
        self.reads.contains(&id) || self.writes.contains(&id)
    }

    fn conflicts_with(&self, later: &Task) -> bool {
        self.writes.iter().any(|w| later.may_read(*w))
            || self.reads.iter().any(|r| later.writes.contains(r))
    }
}

impl fmt::Debug for Task {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Task")
            .field("name", &self.name)
            .field("reads", &self.reads)
            .field("writes", &self.writes)
            .field("every", &self.every)
            .finish_non_exhaustive()
    }
}

/// Tasks grouped into dependency levels.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Schedule {
    levels: Vec<Vec<usize>>,
}

impl Schedule {
    /// Each task goes one level below the deepest earlier task it conflicts
    /// with, so declaration order decides the order of conflicting tasks and
    /// independent tasks share a level.
    #[must_use]
    pub fn build(tasks: &[Task]) -> Self {
        let mut level = vec![0usize; tasks.len()];
        for j in 0..tasks.len() {
            for i in 0..j {
                if tasks[i].conflicts_with(&tasks[j]) {
                    level[j] = level[j].max(level[i] + 1);
                }
            }
        }
        let depth = level.iter().max().map_or(0, |d| d + 1);
        let mut levels = vec![Vec::new(); depth];
        for (task, &l) in level.iter().enumerate() {
            levels[l].push(task);
        }
        Self { levels }
    }

    /// Task indices per level, in execution order.
    #[must_use]
    pub fn levels(&self) -> &[Vec<usize>] {
        &self.levels
    }
}

/// Frame-wide inputs every task sees.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FrameInfo {
    pub frame: u64,
    pub seed: u64,
}

/// Views published at the end of the previous frame, by domain index: the
/// exchange buffers coupled domains read (§3.6).
pub type PrevViews = [Option<Arc<dyn Any + Send + Sync>>];

/// Runs every task of one frame. Must be called on the frame pool (inside
/// `ThreadPool::install` or a job spawned on it).
pub fn run_frame(
    tasks: &[Task],
    schedule: &Schedule,
    res: &Resources,
    prev: &PrevViews,
    info: FrameInfo,
) {
    for level in schedule.levels() {
        let mut active = level
            .iter()
            .map(|&i| &tasks[i])
            .filter(|t| info.frame % u64::from(t.every) == 0);
        match (active.next(), active.next()) {
            (None, _) => {}
            (Some(only), None) => run_task(only, res, prev, info),
            (Some(a), Some(b)) => rayon::scope(|s| {
                for task in [a, b].into_iter().chain(active) {
                    s.spawn(move |_| run_task(task, res, prev, info));
                }
            }),
        }
    }
}

/// Runs every task in declaration order on the calling thread: the
/// main-thread phase of the driver ([`crate::world`]) runs main-owned laws
/// this way, with the same [`Task`]/[`TaskCtx`] contract as a frame.
pub fn run_sequential(tasks: &[Task], res: &Resources, info: FrameInfo) {
    for task in tasks {
        if info.frame % u64::from(task.every) == 0 {
            run_task(task, res, &[], info);
        }
    }
}

fn run_task(task: &Task, res: &Resources, prev: &PrevViews, info: FrameInfo) {
    let ctx = TaskCtx {
        task,
        res,
        prev,
        info,
    };
    (task.run)(&ctx);
}

/// What a running task can reach: its declared resources, the previous
/// frame's views, and deterministic randomness.
pub struct TaskCtx<'a> {
    task: &'a Task,
    res: &'a Resources,
    prev: &'a PrevViews,
    info: FrameInfo,
}

impl<'a> TaskCtx<'a> {
    #[must_use]
    pub fn frame(&self) -> u64 {
        self.info.frame
    }

    /// A random stream that depends only on the world seed, the frame number
    /// and `id` (§3.9): never on thread timing.
    #[must_use]
    pub fn rng(&self, id: StreamId) -> Rng {
        RngStreams::new(self.info.seed).stream(StreamId(
            id.0 ^ self.info.frame.wrapping_mul(0x9e37_79b9_7f4a_7c15),
        ))
    }

    /// Shared access to a declared resource.
    ///
    /// # Panics
    /// If the task did not declare `res`, or (a scheduler bug) it is held
    /// by a conflicting task.
    #[must_use]
    pub fn read<T: Any>(&self, res: Res<T>) -> Ref<'a, T> {
        assert!(
            self.task.may_read(res.id),
            "task `{}` reads undeclared resource `{}`",
            self.task.name,
            self.res.name(res.id)
        );
        let guard = match self.res.slots[usize::from(res.id.0)].try_read() {
            Ok(g) => g,
            Err(TryLockError::Poisoned(p)) => p.into_inner(),
            Err(TryLockError::WouldBlock) => self.contended(res.id),
        };
        Ref {
            guard,
            _marker: PhantomData,
        }
    }

    /// Exclusive access to a declared written resource.
    ///
    /// # Panics
    /// As [`read`](Self::read), for writes.
    #[must_use]
    pub fn write<T: Any>(&self, res: Res<T>) -> Mut<'a, T> {
        assert!(
            self.task.writes.contains(&res.id),
            "task `{}` writes undeclared resource `{}`",
            self.task.name,
            self.res.name(res.id)
        );
        let guard = match self.res.slots[usize::from(res.id.0)].try_write() {
            Ok(g) => g,
            Err(TryLockError::Poisoned(p)) => p.into_inner(),
            Err(TryLockError::WouldBlock) => self.contended(res.id),
        };
        Mut {
            guard,
            _marker: PhantomData,
        }
    }

    /// The previous frame's published view of domain `domain` (type-erased;
    /// see `TaskCtx::prev_view` in `owner`).
    #[must_use]
    pub fn prev_erased(&self, domain: usize) -> Option<&Arc<dyn Any + Send + Sync>> {
        self.prev.get(domain)?.as_ref()
    }

    /// Shared access to a declared resource by id, type-erased (the law
    /// driver's [`crate::law::FrameData`] holds one guard per declared
    /// resource and downcasts per query).
    ///
    /// # Panics
    /// As [`read`](Self::read).
    pub fn read_erased(&self, id: ResourceId) -> RwLockReadGuard<'a, Erased> {
        assert!(
            self.task.may_read(id),
            "task `{}` reads undeclared resource `{}`",
            self.task.name,
            self.res.name(id)
        );
        match self.res.slots[usize::from(id.0)].try_read() {
            Ok(g) => g,
            Err(TryLockError::Poisoned(p)) => p.into_inner(),
            Err(TryLockError::WouldBlock) => self.contended(id),
        }
    }

    /// Exclusive access to a declared written resource by id, type-erased.
    ///
    /// # Panics
    /// As [`write`](Self::write).
    pub fn write_erased(&self, id: ResourceId) -> RwLockWriteGuard<'a, Erased> {
        assert!(
            self.task.writes.contains(&id),
            "task `{}` writes undeclared resource `{}`",
            self.task.name,
            self.res.name(id)
        );
        match self.res.slots[usize::from(id.0)].try_write() {
            Ok(g) => g,
            Err(TryLockError::Poisoned(p)) => p.into_inner(),
            Err(TryLockError::WouldBlock) => self.contended(id),
        }
    }

    /// Whether this task declared a write of `id`.
    #[must_use]
    pub fn declares_write(&self, id: ResourceId) -> bool {
        self.task.writes.contains(&id)
    }

    fn contended(&self, id: ResourceId) -> ! {
        panic!(
            "scheduler bug: task `{}` found resource `{}` held by a concurrent task",
            self.task.name,
            self.res.name(id)
        )
    }
}

/// A read guard for a resource.
pub struct Ref<'a, T> {
    guard: RwLockReadGuard<'a, Erased>,
    _marker: PhantomData<&'a T>,
}

impl<T: Any> Deref for Ref<'_, T> {
    type Target = T;
    fn deref(&self) -> &T {
        self.guard.downcast_ref().expect("resource type mismatch")
    }
}

/// A write guard for a resource.
pub struct Mut<'a, T> {
    guard: RwLockWriteGuard<'a, Erased>,
    _marker: PhantomData<&'a mut T>,
}

impl<T: Any> Deref for Mut<'_, T> {
    type Target = T;
    fn deref(&self) -> &T {
        self.guard.downcast_ref().expect("resource type mismatch")
    }
}

impl<T: Any> DerefMut for Mut<'_, T> {
    fn deref_mut(&mut self) -> &mut T {
        self.guard.downcast_mut().expect("resource type mismatch")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn id(n: u16) -> ResourceId {
        ResourceId(n)
    }

    #[test]
    fn schedule_orders_conflicts_and_groups_independent_tasks() {
        let noop = |_: &TaskCtx<'_>| {};
        let tasks = vec![
            Task::new("apply gas", noop).writes(id(0)),
            Task::new("apply heat", noop).writes(id(1)),
            Task::new("devices", noop).writes(id(0)).reads(id(2)),
            Task::new("gas field", noop).writes(id(0)),
            Task::new("heat field", noop).writes(id(1)).reads(id(0)),
            Task::new("power", noop).writes(id(2)),
            Task::new("watch gas", noop).reads(id(0)),
            Task::new("watch heat", noop).reads(id(1)),
        ];
        let schedule = Schedule::build(&tasks);
        assert_eq!(
            schedule.levels(),
            &[vec![0, 1], vec![2], vec![3, 5], vec![4, 6], vec![7]]
        );
    }

    #[test]
    fn tasks_run_in_parallel_on_the_pool_and_respect_order() {
        let mut res = Resources::new();
        let a = res.insert("a", Vec::<u32>::new());
        let b = res.insert("b", 0u64);
        let tasks = vec![
            Task::new("push1", move |ctx| ctx.write(a).push(1)).writes(a.id()),
            Task::new("count", move |ctx| *ctx.write(b) += 10).writes(b.id()),
            Task::new("push2", move |ctx| {
                let n = ctx.read(b);
                ctx.write(a).push(u32::try_from(*n).unwrap());
            })
            .writes(a.id())
            .reads(b.id()),
            Task::new("even frames only", move |ctx| *ctx.write(b) += 1)
                .writes(b.id())
                .every(2),
        ];
        let schedule = Schedule::build(&tasks);
        let pool = rayon::ThreadPoolBuilder::new()
            .num_threads(2)
            .build()
            .unwrap();
        for frame in 0..2 {
            pool.install(|| {
                run_frame(&tasks, &schedule, &res, &[], FrameInfo { frame, seed: 1 });
            });
        }
        assert_eq!(res.get_mut(a), &vec![1, 10, 1, 21]);
        assert_eq!(*res.get_mut(b), 21);
    }

    #[test]
    #[should_panic(expected = "undeclared")]
    fn undeclared_access_panics() {
        let mut res = Resources::new();
        let a = res.insert("a", 0u8);
        let tasks = vec![Task::new("sneaky", move |ctx| *ctx.write(a) = 1)];
        run_frame(
            &tasks,
            &Schedule::build(&tasks),
            &res,
            &[],
            FrameInfo { frame: 0, seed: 0 },
        );
    }
}
