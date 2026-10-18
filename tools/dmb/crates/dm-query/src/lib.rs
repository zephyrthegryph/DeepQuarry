//! Memoized query database (doc/incremental_core.md).
//!
//! A [`Db`] holds *inputs* (values set from outside) and *derived* queries (values computed by a
//! registered function that reads other queries through a [`Ctx`]). Every derived value records the
//! queries it read. A global revision counter advances whenever an input changes. Fetching a derived
//! query in a newer revision revalidates it:
//!
//! 1. verified in this revision: green, nothing runs;
//! 2. no recorded dependency changed after the revision it was verified at: green, nothing runs
//!    (dependencies are revalidated first, recursively);
//! 3. otherwise it reruns; when the new value hashes equal to the old one `changed_at` is kept
//!    (early cutoff), so its dependants stay green.
//!
//! Values may be evicted ([`Db::evict_values`]); the hash, dependencies and stamps stay, so
//! revalidation still works and a later read recomputes only the value.
//! Reverse edges are kept: [`Db::dependants`] answers "what depends on X" without a scan.
//!
//! Threads: queries may be fetched from several threads. A query being computed by one thread makes
//! other readers of it wait. Two threads computing queries that read each other deadlock; the graph
//! of a well-formed compile has no cycles (a same-thread cycle returns [`QueryError::Cycle`]).
use std::any::Any;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread::ThreadId;

pub type Hash = u128;
pub type Value = Arc<dyn Any + Send + Sync>;

/// Content hash helper (xxh3-128).
pub fn hash_bytes(bytes: &[u8]) -> Hash {
    xxhash_rust::xxh3::xxh3_128(bytes)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Kind(pub u16);

/// Identity of one query: its kind and a hash of its parameters.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Key {
    pub kind: Kind,
    pub id: u128,
}
impl Key {
    pub fn new(kind: Kind, id: u128) -> Self {
        Self { kind, id }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum QueryError {
    /// The query (transitively) read itself.
    Cycle(Key),
    /// A dependency was removed or never defined and no parameters were supplied.
    Missing(Key),
    /// The kind has no registered function.
    UnknownKind(Kind),
}

/// Result of one computation: the value, its content hash and an estimate of its size.
pub struct Outcome {
    pub value: Value,
    pub hash: Hash,
    pub bytes: usize,
}
impl Outcome {
    pub fn new<T: Any + Send + Sync>(value: T, hash: Hash, bytes: usize) -> Self {
        Self { value: Arc::new(value), hash, bytes }
    }
}

type ComputeFn = dyn Fn(&mut Ctx<'_>, &Value) -> Result<Outcome, QueryError> + Send + Sync;

struct KindDef {
    name: &'static str,
    compute: Option<Box<ComputeFn>>,
}

struct Node {
    params: Value,
    input: bool,
    value: Option<Value>,
    hash: Hash,
    bytes: usize,
    deps: Vec<Key>,
    /// Revision this node was last proven current at (0: never computed).
    verified_at: u64,
    /// Revision its value hash last changed at.
    changed_at: u64,
    busy: Option<ThreadId>,
}

#[derive(Default)]
struct State {
    revision: u64,
    nodes: HashMap<Key, Node>,
    rdeps: HashMap<Key, HashSet<Key>>,
    stats: BTreeMap<Kind, KindStats>,
}

/// Per-kind counters since creation.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct KindStats {
    /// Revalidated without running (all dependencies unchanged or cut off).
    pub green: u64,
    /// Computed (first time, after a dependency changed, or to refill an evicted value).
    pub computed: u64,
    /// Computed and found equal to the previous value: dependants stayed green.
    pub cutoff: u64,
    /// Values dropped by eviction.
    pub evicted: u64,
}

pub struct Db {
    state: Mutex<State>,
    wake: Condvar,
    kinds: Mutex<HashMap<Kind, Arc<KindDef>>>,
    verify: AtomicBool,
    verify_failures: Mutex<Vec<String>>,
}

impl Default for Db {
    fn default() -> Self {
        Self::new()
    }
}

struct Done {
    value: Option<Value>,
    hash: Hash,
    changed_at: u64,
}

/// Clears a node's busy mark on every exit, including a panic in a query function.
struct Busy<'a> {
    db: &'a Db,
    key: Key,
    armed: bool,
}
impl Drop for Busy<'_> {
    fn drop(&mut self) {
        if self.armed {
            let mut state = self.db.lock();
            if let Some(node) = state.nodes.get_mut(&self.key) {
                node.busy = None;
            }
            drop(state);
            self.db.wake.notify_all();
        }
    }
}

impl Db {
    pub fn new() -> Self {
        Self {
            state: Mutex::new(State { revision: 1, ..Default::default() }),
            wake: Condvar::new(),
            kinds: Mutex::new(HashMap::new()),
            verify: AtomicBool::new(false),
            verify_failures: Mutex::new(Vec::new()),
        }
    }

    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|error| error.into_inner())
    }

    /// Register an input kind (values set with [`Db::set_input`]).
    pub fn define_input(&self, kind: Kind, name: &'static str) {
        self.kinds
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .insert(kind, Arc::new(KindDef { name, compute: None }));
    }

    /// Register a derived kind. `compute` must be deterministic in the values it reads.
    pub fn define(
        &self,
        kind: Kind,
        name: &'static str,
        compute: impl Fn(&mut Ctx<'_>, &Value) -> Result<Outcome, QueryError> + Send + Sync + 'static,
    ) {
        self.kinds
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .insert(kind, Arc::new(KindDef { name, compute: Some(Box::new(compute)) }));
    }

    fn kind_def(&self, kind: Kind) -> Result<Arc<KindDef>, QueryError> {
        self.kinds
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .get(&kind)
            .cloned()
            .ok_or(QueryError::UnknownKind(kind))
    }

    pub fn revision(&self) -> u64 {
        self.lock().revision
    }

    /// Recompute every green query once and record mismatches ([`Db::verify_failures`]).
    pub fn set_verify(&self, on: bool) {
        self.verify.store(on, Ordering::Relaxed);
    }
    pub fn verify_failures(&self) -> Vec<String> {
        self.verify_failures.lock().unwrap_or_else(|error| error.into_inner()).clone()
    }

    /// Set an input. Returns whether it changed (the revision advances only then).
    pub fn set_input<T: Any + Send + Sync>(&self, key: Key, value: T, hash: Hash) -> bool {
        let mut state = self.lock();
        if let Some(node) = state.nodes.get(&key) {
            if node.input && node.hash == hash && node.value.is_some() {
                return false;
            }
        }
        state.revision += 1;
        let revision = state.revision;
        let params: Value = Arc::new(());
        let node = state.nodes.entry(key).or_insert_with(|| Node {
            params,
            input: true,
            value: None,
            hash: 0,
            bytes: 0,
            deps: Vec::new(),
            verified_at: 0,
            changed_at: 0,
            busy: None,
        });
        node.input = true;
        node.value = Some(Arc::new(value));
        node.hash = hash;
        node.verified_at = revision;
        node.changed_at = revision;
        true
    }

    /// Remove a query (an input, or a derived node that no longer exists, such as a deleted file's
    /// declarations). Dependants see it as missing and rerun.
    pub fn remove(&self, key: Key) -> bool {
        let mut state = self.lock();
        let Some(node) = state.nodes.remove(&key) else {
            return false;
        };
        state.revision += 1;
        for dep in node.deps {
            if let Some(set) = state.rdeps.get_mut(&dep) {
                set.remove(&key);
            }
        }
        true
    }

    /// Fetch a query's value, revalidating it first. `params` are the parameters the function
    /// receives; they are kept on the node so later revalidations can recompute it.
    pub fn get<T: Any + Send + Sync>(&self, key: Key, params: Value) -> Result<Arc<T>, QueryError> {
        let done = self.ensure(key, Some(params), true)?;
        downcast(done.value, key)
    }

    /// Value of an input.
    pub fn input<T: Any + Send + Sync>(&self, key: Key) -> Option<Arc<T>> {
        let done = self.ensure(key, None, true).ok()?;
        downcast(done.value, key).ok()
    }

    /// Revalidate and return only the content hash.
    pub fn hash(&self, key: Key, params: Value) -> Result<Hash, QueryError> {
        Ok(self.ensure(key, Some(params), false)?.hash)
    }

    fn ensure(&self, key: Key, params: Option<Value>, need_value: bool) -> Result<Done, QueryError> {
        let me = std::thread::current().id();
        loop {
            let mut state = self.lock();
            let revision = state.revision;
            let Some(node) = state.nodes.get_mut(&key) else {
                let Some(params) = params else {
                    return Err(QueryError::Missing(key));
                };
                let def = self.kind_def(key.kind)?;
                if def.compute.is_none() {
                    return Err(QueryError::Missing(key));
                }
                state.nodes.insert(
                    key,
                    Node {
                        params: params.clone(),
                        input: false,
                        value: None,
                        hash: 0,
                        bytes: 0,
                        deps: Vec::new(),
                        verified_at: 0,
                        changed_at: 0,
                        busy: Some(me),
                    },
                );
                drop(state);
                return self.run(key, &params, revision, true);
            };
            if node.input {
                return Ok(Done { value: node.value.clone(), hash: node.hash, changed_at: node.changed_at });
            }
            if let Some(params) = params.clone() {
                node.params = params;
            }
            match node.busy {
                Some(owner) if owner == me => return Err(QueryError::Cycle(key)),
                Some(_) => {
                    let _state = self.wake.wait(state).unwrap_or_else(|error| error.into_inner());
                    continue;
                }
                None => {}
            }
            if node.verified_at == revision && node.verified_at != 0 {
                if need_value && node.value.is_none() {
                    node.busy = Some(me);
                    let params = node.params.clone();
                    drop(state);
                    return self.run(key, &params, revision, false);
                }
                return Ok(Done { value: node.value.clone(), hash: node.hash, changed_at: node.changed_at });
            }
            node.busy = Some(me);
            let deps = node.deps.clone();
            let verified = node.verified_at;
            let params = node.params.clone();
            let never = verified == 0;
            drop(state);
            let mut guard = Busy { db: self, key, armed: true };
            let mut clean = !never;
            if clean {
                for dep in deps {
                    match self.ensure(dep, None, false) {
                        Ok(done) => {
                            if done.changed_at > verified {
                                clean = false;
                                break;
                            }
                        }
                        Err(QueryError::Missing(_)) | Err(QueryError::UnknownKind(_)) => {
                            clean = false;
                            break;
                        }
                        Err(error) => return Err(error),
                    }
                }
            }
            if !clean {
                guard.armed = false;
                return self.run(key, &params, revision, false);
            }
            let mut state = self.lock();
            let done;
            {
                let node = state.nodes.get_mut(&key).expect("busy node stays");
                node.verified_at = revision;
                node.busy = None;
                done = Done { value: node.value.clone(), hash: node.hash, changed_at: node.changed_at };
            }
            state.stats.entry(key.kind).or_default().green += 1;
            let have_value = done.value.is_some();
            let hash = done.hash;
            drop(state);
            guard.armed = false;
            self.wake.notify_all();
            if self.verify.load(Ordering::Relaxed) {
                self.verify_green(key, &params, hash);
            }
            if need_value && !have_value {
                let mut state = self.lock();
                let node = state.nodes.get_mut(&key).expect("node stays");
                if node.busy.is_some() {
                    continue;
                }
                node.busy = Some(me);
                drop(state);
                return self.run(key, &params, revision, false);
            }
            return Ok(done);
        }
    }

    fn verify_green(&self, key: Key, params: &Value, hash: Hash) {
        let Ok(def) = self.kind_def(key.kind) else { return };
        let Some(compute) = &def.compute else { return };
        let mut ctx = Ctx { db: self, deps: Vec::new(), seen: HashSet::new() };
        let message = match compute(&mut ctx, params) {
            Ok(outcome) if outcome.hash == hash => return,
            Ok(_) => format!("{} {:x}: green but recomputed value differs", def.name, key.id),
            Err(error) => format!("{} {:x}: green but recompute failed: {error:?}", def.name, key.id),
        };
        self.verify_failures.lock().unwrap_or_else(|error| error.into_inner()).push(message);
    }

    /// Run the function of a node already marked busy by this thread.
    fn run(&self, key: Key, params: &Value, revision: u64, fresh: bool) -> Result<Done, QueryError> {
        let mut guard = Busy { db: self, key, armed: true };
        let fail = |db: &Db, guard: &mut Busy<'_>, error: QueryError| {
            if fresh {
                db.drop_fresh(key);
                guard.armed = false;
            }
            Err(error)
        };
        let def = match self.kind_def(key.kind) {
            Ok(def) => def,
            Err(error) => return fail(self, &mut guard, error),
        };
        let Some(compute) = def.compute.as_ref() else {
            return fail(self, &mut guard, QueryError::UnknownKind(key.kind));
        };
        let mut ctx = Ctx { db: self, deps: Vec::new(), seen: HashSet::new() };
        let result = compute(&mut ctx, params);
        let deps = ctx.deps;
        let outcome = match result {
            Ok(outcome) => outcome,
            Err(error) => return fail(self, &mut guard, error),
        };
        let mut state = self.lock();
        let old_deps;
        let done;
        let cutoff;
        {
            let Some(node) = state.nodes.get_mut(&key) else {
                guard.armed = false;
                return Ok(Done { value: Some(outcome.value), hash: outcome.hash, changed_at: revision });
            };
            cutoff = node.verified_at != 0 && node.hash == outcome.hash;
            if !cutoff {
                node.changed_at = revision;
            }
            node.hash = outcome.hash;
            node.value = Some(outcome.value.clone());
            node.bytes = outcome.bytes;
            old_deps = std::mem::replace(&mut node.deps, deps.clone());
            node.verified_at = revision;
            node.busy = None;
            done = Done { value: Some(outcome.value), hash: outcome.hash, changed_at: node.changed_at };
        }
        for dep in &old_deps {
            if !deps.contains(dep) {
                if let Some(set) = state.rdeps.get_mut(dep) {
                    set.remove(&key);
                }
            }
        }
        for dep in &deps {
            state.rdeps.entry(*dep).or_default().insert(key);
        }
        let stats = state.stats.entry(key.kind).or_default();
        stats.computed += 1;
        if cutoff {
            stats.cutoff += 1;
        }
        drop(state);
        guard.armed = false;
        self.wake.notify_all();
        Ok(done)
    }

    fn drop_fresh(&self, key: Key) {
        let mut state = self.lock();
        state.nodes.remove(&key);
        drop(state);
        self.wake.notify_all();
    }

    /// Queries that read `roots` directly or transitively (the red candidates of a change).
    pub fn dependants(&self, roots: &[Key]) -> Vec<Key> {
        let state = self.lock();
        let mut seen: HashSet<Key> = HashSet::new();
        let mut stack: Vec<Key> = roots.to_vec();
        let mut out = Vec::new();
        while let Some(key) = stack.pop() {
            if let Some(set) = state.rdeps.get(&key) {
                for &next in set {
                    if seen.insert(next) {
                        out.push(next);
                        stack.push(next);
                    }
                }
            }
        }
        out.sort();
        out
    }

    /// Drop the stored values of derived queries of the given kinds (all kinds when empty).
    /// Returns the estimated bytes freed. Hashes, dependencies and stamps are kept.
    pub fn evict_values(&self, kinds: &[Kind]) -> usize {
        let mut state = self.lock();
        let mut freed = 0usize;
        let mut counts: BTreeMap<Kind, u64> = BTreeMap::new();
        for (key, node) in state.nodes.iter_mut() {
            if node.input || node.busy.is_some() || node.value.is_none() {
                continue;
            }
            if !kinds.is_empty() && !kinds.contains(&key.kind) {
                continue;
            }
            node.value = None;
            freed += std::mem::take(&mut node.bytes);
            *counts.entry(key.kind).or_default() += 1;
        }
        for (kind, count) in counts {
            state.stats.entry(kind).or_default().evicted += count;
        }
        freed
    }

    /// Estimated bytes held by derived values.
    pub fn value_bytes(&self) -> usize {
        self.lock().nodes.values().map(|node| node.bytes).sum()
    }

    pub fn len(&self) -> usize {
        self.lock().nodes.len()
    }
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn stats(&self, kind: Kind) -> KindStats {
        self.lock().stats.get(&kind).copied().unwrap_or_default()
    }

    pub fn kind_name(&self, kind: Kind) -> &'static str {
        self.kind_def(kind).map(|def| def.name).unwrap_or("?")
    }
}

fn downcast<T: Any + Send + Sync>(value: Option<Value>, key: Key) -> Result<Arc<T>, QueryError> {
    value
        .and_then(|value| value.downcast::<T>().ok())
        .ok_or(QueryError::Missing(key))
}

/// Handed to a query function: reads go through it so they are recorded as dependencies.
pub struct Ctx<'a> {
    db: &'a Db,
    deps: Vec<Key>,
    seen: HashSet<Key>,
}
impl Ctx<'_> {
    fn note(&mut self, key: Key) {
        if self.seen.insert(key) {
            self.deps.push(key);
        }
    }

    /// Read a derived query's value.
    pub fn get<T: Any + Send + Sync>(&mut self, key: Key, params: Value) -> Result<Arc<T>, QueryError> {
        self.note(key);
        self.db.get(key, params)
    }

    /// Read an input's value.
    pub fn input<T: Any + Send + Sync>(&mut self, key: Key) -> Result<Arc<T>, QueryError> {
        self.note(key);
        self.db.input(key).ok_or(QueryError::Missing(key))
    }

    /// Depend on a query's content hash without needing its value (cheaper when evicted).
    pub fn observe(&mut self, key: Key, params: Value) -> Result<Hash, QueryError> {
        self.note(key);
        self.db.hash(key, params)
    }

    /// Depend on an input's hash only.
    pub fn observe_input(&mut self, key: Key) -> Result<Hash, QueryError> {
        self.note(key);
        Ok(self.db.ensure(key, None, false)?.hash)
    }
}

#[cfg(test)]
mod tests;
