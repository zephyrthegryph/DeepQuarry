//! The session's query database (doc/incremental_core.md, migration step 1).
//!
//! One [`dm_query::Db`] per retained session. Each request is a revision: its inputs are the
//! prepared source files (`source(path)`, content-hashed) and the project configuration
//! (`project`). The derived `program` query reads every input in canonical order; it is green
//! exactly when no input changed. Later steps hang the frontend, per-unit and output queries off
//! these inputs and replace the per-stage stores.
use dm_query::{Db, Key, Kind, Outcome, QueryError, Value};
use std::collections::BTreeMap;
use std::path::PathBuf;
use dm_preprocess::regions::prepared_source::PreparedSource;
use std::sync::{Arc, Mutex};

const SOURCE: Kind = Kind(1);
const PROJECT: Kind = Kind(2);
const PROGRAM: Kind = Kind(3);

fn source_key(path: &std::path::Path) -> Key {
    Key::new(SOURCE, dm_query::hash_bytes(path.as_os_str().as_encoded_bytes()))
}
const PROJECT_KEY: Key = Key { kind: PROJECT, id: 0 };
const PROGRAM_KEY: Key = Key { kind: PROGRAM, id: 0 };

/// What one revision did.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Revision {
    pub revision: u64,
    pub sources: usize,
    pub changed: usize,
    pub removed: usize,
    /// The program query revalidated without running (no input changed).
    pub green: bool,
}

pub struct QueryDb {
    db: Db,
    /// Current answers of every query a stored unit read (see `answer` below).
    answers: Answers,
    /// Read lists of the stored lowering units, rebuilt only for new stored values.
    unit_proofs: UnitProofs,
    /// Sources of the previous revision by path: key, the prepared owner (held, so an unchanged
    /// capture is recognised by identity without rehashing) and its content hash.
    sources: Mutex<BTreeMap<PathBuf, (Key, Arc<PreparedSource>, u128)>>,
}
impl Default for QueryDb {
    fn default() -> Self {
        let db = Db::new();
        db.define_input(SOURCE, "source");
        db.define_input(PROJECT, "project");
        db.define(PROGRAM, "program", |ctx, params| {
            let keys = params
                .downcast_ref::<Vec<Key>>()
                .ok_or(QueryError::Missing(PROGRAM_KEY))?;
            let mut hasher = xxhash_rust::xxh3::Xxh3::new();
            hasher.update(&ctx.observe_input(PROJECT_KEY)?.to_le_bytes());
            for key in keys {
                hasher.update(&key.id.to_le_bytes());
                hasher.update(&ctx.observe_input(*key)?.to_le_bytes());
            }
            let hash = hasher.digest128();
            Ok(Outcome::new(hash, hash, 16))
        });
        Self {
            db,
            answers: Answers::default(),
            unit_proofs: UnitProofs::default(),
            sources: Mutex::new(BTreeMap::new()),
        }
    }
}
impl QueryDb {
    pub fn db(&self) -> &Db {
        &self.db
    }
    /// Advance to this request's inputs and revalidate the program query.
    pub fn revise(
        &self,
        sources: &dm_preprocess::regions::prepared_source::PreparedSources,
        project: u128,
    ) -> Result<Revision, QueryError> {
        let computed_before = self.db.stats(PROGRAM).computed;
        // A new request: every answer is proven again (or carried) before it is used.
        self.answers.next_request();
        let mut previous = self.sources.lock().unwrap_or_else(|error| error.into_inner());
        let mut current = BTreeMap::new();
        let mut changed = 0;
        for (path, source) in sources.iter() {
            let (key, hash) = match previous.get(path) {
                Some((key, held, hash)) if Arc::ptr_eq(held, source) => (*key, *hash),
                _ => (
                    source_key(path),
                    dm_query::hash_bytes(source.original().as_str().as_bytes()),
                ),
            };
            if self.db.set_input(key, (), hash) {
                changed += 1;
            }
            current.insert(path.clone(), (key, Arc::clone(source), hash));
        }
        let mut removed = 0;
        for (path, (key, _, _)) in previous.iter() {
            if !current.contains_key(path) && self.db.remove(*key) {
                removed += 1;
            }
        }
        if self.db.set_input(PROJECT_KEY, (), project) {
            // Defines and engine policy reach answers outside the declaration change set.
            self.answers.clear();
        }
        let keys: Vec<Key> = current.values().map(|(key, _, _)| *key).collect();
        let count = keys.len();
        *previous = current;
        drop(previous);
        let params: Value = Arc::new(keys);
        self.db.hash(PROGRAM_KEY, params)?;
        Ok(Revision {
            revision: self.db.revision(),
            sources: count,
            changed,
            removed,
            green: self.db.stats(PROGRAM).computed == computed_before,
        })
    }
}

// --- Answers (migration step 4) ------------------------------------------------------------
//
// `answer(query)` is the current meaning of one `ResolveQuery` in this revision, kept as its
// canonical hash. A stored unit (lowering record, initializer receipt, ABI receipt) is unchanged
// exactly when every answer it recorded equals the current one; there are no domain versions or
// certificates. Each answer is resolved at most once per request and shared by every stage. A
// positive structural answer the tree's classified declaration change cannot reach is carried
// from the tree it was last proven under without resolving it.

const ANSWER_SHARDS: usize = 64;

#[derive(Clone, Copy)]
struct AnswerSlot {
    /// Request that last proved the slot.
    request: u64,
    /// Declaration identity of the tree it was proven under (0: unknown, never carried).
    tree: u128,
    /// Answer-world version it was proven under (0: unknown, never carried by world).
    world: u128,
    hash: u128,
    positive: bool,
    /// Request that first held this id (the slot is `fresh` in that request).
    born: u64,
    /// Request in which the hash last differed from the slot it replaced (0: never).
    changed: u64,
    /// The hash this slot had when the retained output was last published (0: the slot did not
    /// exist then, or no output is published). See [`QueryDb::mark_published`].
    base: u128,
    /// The question, so the whole table can be asked again (see [`QueryDb::prove_against_base`]).
    query: dm_ir::ResolveQuery,
}
impl AnswerSlot {
    /// The slot `proved` becomes when it replaces `self`: the same id, so `born` is kept and
    /// `changed` moves to this request when the answer's value differs.
    fn replaced_by(prior: Option<AnswerSlot>, mut proved: AnswerSlot) -> AnswerSlot {
        match prior {
            Some(prior) => {
                proved.born = prior.born;
                proved.base = prior.base;
                proved.changed = if prior.hash != proved.hash { proved.request } else { prior.changed };
            }
            None => proved.born = proved.request,
        }
        proved
    }
}
#[derive(Default)]
struct AnswerRequest {
    request: u64,
    tree: Option<Arc<dm_tree::SemanticTree>>,
    /// Version of every answer this request's resolvers give (the static resolver's
    /// `ReadDomain::Tree` version: declarations, procedure statics, engine configuration and
    /// catalogs); 0 when the resolver cannot version its answers.
    world: u128,
}
struct Answers {
    shards: Box<[Mutex<std::collections::HashMap<u128, AnswerSlot>>]>,
    current: std::sync::RwLock<AnswerRequest>,
    requests: std::sync::atomic::AtomicU64,
    resolved: std::sync::atomic::AtomicUsize,
    carried: std::sync::atomic::AtomicUsize,
    /// Answers a stage's own resolver disagreed with (verification only).
    mismatches: std::sync::atomic::AtomicUsize,
    /// Request that last dropped the whole table (project change); its slots are all fresh.
    cleared: std::sync::atomic::AtomicU64,
    /// How many times the whole table was dropped, and the count when the published output's
    /// answers were marked: unequal means the marks are gone.
    drops: std::sync::atomic::AtomicU64,
    marked_drops: std::sync::atomic::AtomicU64,
    /// Number of the last marking (0: none); a retained output holds the number of the marking
    /// made for it and is compared only while that is still the last.
    epoch: std::sync::atomic::AtomicU64,
    /// Every resource search the table holds: the world version does not cover the filesystem,
    /// so these are proven again when a request opens (see [`QueryDb::begin_answers`]).
    resource_queries: Mutex<std::collections::HashMap<u128, dm_ir::ResolveQuery>>,
}
impl Default for Answers {
    fn default() -> Self {
        Self {
            shards: (0..ANSWER_SHARDS).map(|_| Mutex::new(Default::default())).collect(),
            current: Default::default(),
            requests: std::sync::atomic::AtomicU64::new(0),
            resolved: Default::default(),
            carried: Default::default(),
            mismatches: Default::default(),
            cleared: Default::default(),
            drops: Default::default(),
            marked_drops: Default::default(),
            epoch: Default::default(),
            resource_queries: Default::default(),
        }
    }
}
impl Answers {
    fn next_request(&self) {
        use std::sync::atomic::Ordering;
        let request = self.requests.fetch_add(1, Ordering::SeqCst) + 1;
        *self.current.write().unwrap_or_else(|error| error.into_inner()) =
            AnswerRequest { request, tree: None, world: 0 };
        self.resolved.store(0, Ordering::Relaxed);
        self.carried.store(0, Ordering::Relaxed);
    }
    fn clear(&self) {
        let request = self.current.read().unwrap_or_else(|error| error.into_inner()).request;
        self.cleared.store(request, std::sync::atomic::Ordering::Relaxed);
        self.drops.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        for shard in self.shards.iter() {
            shard.lock().unwrap_or_else(|error| error.into_inner()).clear();
        }
        self.resource_queries.lock().unwrap_or_else(|error| error.into_inner()).clear();
    }
    fn len(&self) -> usize {
        self.shards
            .iter()
            .map(|shard| shard.lock().unwrap_or_else(|error| error.into_inner()).len())
            .sum()
    }
}

/// The answers of one request that differ from the table before it (see
/// [`QueryDb::answer_diff`]).
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub(crate) struct AnswerDiff {
    pub request: u64,
    /// Ids (`query_id`) of answers held before whose value changed, sorted.
    pub changed: Vec<u128>,
    /// Answers asked for the first time this request (or since the table was cleared) that equal
    /// what asked them recorded, or that nothing recorded.
    pub fresh: usize,
    /// The table was dropped when the request opened (project change): nothing is comparable.
    pub cleared: bool,
    /// Slots in the table.
    pub held: usize,
}
impl AnswerDiff {
    /// One line for a decline reason or a log.
    pub(crate) fn summary(&self) -> String {
        let shown: Vec<String> =
            self.changed.iter().take(8).map(|id| format!("{:08x}", (*id >> 96) as u32)).collect();
        format!(
            "request {}: {} answers changed [{}{}], {} fresh, {} held{}",
            self.request,
            self.changed.len(),
            shown.join(" "),
            if self.changed.len() > shown.len() { " ..." } else { "" },
            self.fresh,
            self.held,
            if self.cleared { ", table cleared" } else { "" },
        )
    }
}

/// `DMB_QUERY_VERIFY=1` (and every debug build) re-resolves each shared or carried answer through
/// the asking stage's resolver.
fn verify_answers() -> bool {
    static VERIFY: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *VERIFY.get_or_init(|| {
        cfg!(debug_assertions) || std::env::var_os("DMB_QUERY_VERIFY").is_some_and(|value| value == "1")
    })
}
fn query_id(query: &dm_ir::ResolveQuery) -> u128 {
    use std::hash::{Hash, Hasher};
    let mut low = std::collections::hash_map::DefaultHasher::new();
    (0u8, query).hash(&mut low);
    let mut high = std::collections::hash_map::DefaultHasher::new();
    (1u8, query).hash(&mut high);
    (u128::from(high.finish()) << 64) | u128::from(low.finish())
}
fn positive_answer(answer: &dm_ir::ResolvedMeaning) -> bool {
    !matches!(
        answer,
        dm_ir::ResolvedMeaning::Missing
            | dm_ir::ResolvedMeaning::Presence(false)
            | dm_ir::ResolvedMeaning::Unsupported(_)
    )
}
/// Whether a classified declaration change can alter a positive structural answer to `query`.
/// Value-bearing queries (constants, defaults, globals) and every other kind always resolve.
fn answer_reachable(
    change: &dm_tree::change_set::ChangeSince,
    tree: &dm_tree::SemanticTree,
    query: &dm_ir::ResolveQuery,
) -> bool {
    use dm_ir::ResolveQuery as Q;
    match *query {
        Q::HasMemberVar { owner, name }
        | Q::DeclaredVarType { owner, name }
        | Q::VarStorage { owner, name }
        | Q::StaticVar { owner, name }
        | Q::HasMemberProc { owner, name }
        | Q::Proc { owner, name, .. }
        | Q::ProcedureValue { owner, name, .. }
        | Q::OverrideChain { owner, name, .. }
        | Q::MethodProcedureValue { owner, name, .. }
        | Q::DeclarationChain { owner, name, .. } => change.owner_name_dirty(tree, owner, name),
        Q::Type(path) | Q::Parent(path) | Q::Ancestry(path) => {
            change.owner_name_dirty(tree, path, dm_ir::SymbolId::of("\0dm-query-no-member"))
        }
        _ => true,
    }
}
pub(crate) fn answer_hash(answer: &dm_ir::ResolvedMeaning) -> u128 {
    dm_query::hash_bytes(&answer.canonical_bytes())
}

/// One request's view of the answer table: the resolver that answers a query not yet proven in
/// this request. Every stage of a request uses the same semantic resolver.
pub(crate) struct RequestAnswers<'a> {
    db: &'a QueryDb,
    answer: &'a (dyn Fn(&dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning + Sync),
}
impl RequestAnswers<'_> {
    /// The current answer hash of `query` (`id` is its [`query_id`]).
    fn current(&self, id: u128, query: &dm_ir::ResolveQuery) -> u128 {
        let answers = &self.db.answers;
        let current = answers.current.read().unwrap_or_else(|error| error.into_inner());
        let identity = current.tree.as_ref().map_or(0, |tree| tree.declaration_identity());
        let shard = &answers.shards[(id as usize) % ANSWER_SHARDS];
        let prior;
        {
            let mut slots = shard.lock().unwrap_or_else(|error| error.into_inner());
            prior = slots.get(&id).copied();
            if let Some(slot) = slots.get_mut(&id) {
                if slot.request == current.request && slot.tree == identity {
                    let hash = slot.hash;
                    drop(slots);
                    if verify_answers() {
                        self.verify(query, hash, "proven earlier in this request");
                    }
                    return hash;
                }
                // The same resolver inputs give the same answer: carry it without resolving.
                // Resource searches read the filesystem, which the world version does not cover.
                let same_world = current.world != 0
                    && slot.world == current.world
                    && slot.tree == identity
                    && !matches!(query.domain(), dm_ir::ReadDomain::ResourceSearch);
                if same_world {
                    slot.request = current.request;
                    let hash = slot.hash;
                    drop(slots);
                    answers.carried.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    if verify_answers() {
                        self.verify(query, hash, "carried from the same answer world");
                    }
                    return hash;
                }
                let carried = slot.positive
                    && identity != 0
                    && slot.tree != 0
                    && current.tree.as_ref().is_some_and(|tree| {
                        // The same declarations are an empty structural change.
                        static UNCHANGED: std::sync::LazyLock<dm_tree::change_set::ChangeSince> =
                            std::sync::LazyLock::new(|| dm_tree::change_set::ChangeSince {
                                from_identity: 0,
                                set: Default::default(),
                            });
                        if slot.tree == identity {
                            return !answer_reachable(&UNCHANGED, tree, query);
                        }
                        tree.change_since().is_some_and(|change| {
                            change.from_identity == slot.tree && !answer_reachable(change, tree, query)
                        })
                    });
                if carried {
                    slot.request = current.request;
                    slot.tree = identity;
                    slot.world = current.world;
                    answers.carried.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    return slot.hash;
                }
            }
        }
        static RESOLVE: dm_profile::Accumulator = dm_profile::Accumulator::new("query.answer.resolve");
        let timer = RESOLVE.time();
        let meaning = (self.answer)(query);
        drop(timer);
        let slot = AnswerSlot::replaced_by(
            prior,
            AnswerSlot {
                request: current.request,
                tree: identity,
                world: current.world,
                hash: answer_hash(&meaning),
                positive: positive_answer(&meaning),
                born: 0,
                changed: 0,
                base: 0,
                query: *query,
            },
        );
        answers.resolved.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        if matches!(query.domain(), dm_ir::ReadDomain::ResourceSearch) {
            answers
                .resource_queries
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .insert(id, *query);
        }
        shard.lock().unwrap_or_else(|error| error.into_inner()).insert(id, slot);
        slot.hash
    }
    /// Every stage shares one answer per query, so every stage's resolver must give it: a
    /// stage reading an answer another stage proved (or one carried from an earlier request)
    /// resolves it again through its own resolver and must find the same meaning.
    fn verify(&self, query: &dm_ir::ResolveQuery, hash: u128, how: &str) {
        let own = answer_hash(&(self.answer)(query));
        if own != hash {
            let mismatches = self.db.answers.mismatches.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            if mismatches < 8 {
                eprintln!("native answer mismatch ({how}): {query:?}");
            }
            debug_assert_eq!(own, hash, "answer resolvers disagree ({how}) on {query:?}");
        }
    }
    /// Whether the current answer to `query` has the recorded hash.
    pub(crate) fn unchanged_hash(&self, query: &dm_ir::ResolveQuery, recorded: u128) -> bool {
        self.matches(query_id(query), query, recorded)
    }
    /// Whether the current answer has the hash a stored unit recorded. A different value marks
    /// the slot changed in this request: the slot is created by the first stage to ask, so the
    /// recorded hash is the only earlier value there is to compare with.
    fn matches(&self, id: u128, query: &dm_ir::ResolveQuery, recorded: u128) -> bool {
        let hash = self.current(id, query);
        if hash == recorded {
            return true;
        }
        let answers = &self.db.answers;
        let request = answers.current.read().unwrap_or_else(|error| error.into_inner()).request;
        let shard = &answers.shards[(id as usize) % ANSWER_SHARDS];
        if let Some(slot) = shard.lock().unwrap_or_else(|error| error.into_inner()).get_mut(&id) {
            slot.changed = request;
        }
        false
    }
}
impl dm_session::AnswerOracle<dm_ir::ResolveQuery, dm_ir::ResolvedMeaning> for RequestAnswers<'_> {
    fn unchanged(
        &self,
        query: &dm_ir::ResolveQuery,
        recorded: &dm_ir::ResolvedMeaning,
    ) -> Option<bool> {
        Some(self.unchanged_hash(query, answer_hash(recorded)))
    }
}

/// A stored unit's recorded reads as (query id, query, recorded answer hash).
struct UnitReads {
    _owner: Arc<dyn std::any::Any + Send + Sync>,
    reads: Vec<(u128, dm_ir::ResolveQuery, u128)>,
}

/// Read lists of stored units, by stored value address; the held owner keeps the address from
/// being reused while the entry lives.
#[derive(Default)]
pub(crate) struct UnitProofs {
    units: Mutex<std::collections::HashMap<usize, Arc<UnitReads>>>,
}

pub(crate) type Stored<T> = (
    Arc<[u8]>,
    dm_session::ObservedArtifact<T, dm_ir::ResolveQuery, dm_ir::ResolvedMeaning, dm_ir::ReadDomain>,
);

impl QueryDb {
    /// Bind this request's answers to `tree`: answers proven under an older tree are carried only
    /// through its classified change. Called once per request (after [`Self::revise`] opened it)
    /// before any stage reads; without it nothing is carried.
    /// `world` versions every answer the request's resolvers give (see `AnswerRequest::world`);
    /// an answer proven under the same tree and world is carried without resolving.
    ///
    /// Resource searches read the filesystem, which the world does not version: every one the
    /// table holds is proven again here through `resolve`.
    pub(crate) fn begin_answers(
        &self,
        tree: &Arc<dm_tree::SemanticTree>,
        world: Option<u128>,
        resolve: &dyn Fn(&dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning,
    ) {
        let world = world.unwrap_or(0);
        let identity = tree.declaration_identity();
        let request = {
            let mut current =
                self.answers.current.write().unwrap_or_else(|error| error.into_inner());
            current.tree = Some(Arc::clone(tree));
            current.world = world;
            current.request
        };
        let queries: Vec<(u128, dm_ir::ResolveQuery)> = self
            .answers
            .resource_queries
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .iter()
            .map(|(id, query)| (*id, *query))
            .collect();
        for (id, query) in queries {
            let meaning = resolve(&query);
            let shard = &self.answers.shards[(id as usize) % ANSWER_SHARDS];
            let mut slots = shard.lock().unwrap_or_else(|error| error.into_inner());
            let prior = slots.get(&id).copied();
            slots.insert(
                id,
                AnswerSlot::replaced_by(
                    prior,
                    AnswerSlot {
                        request,
                        tree: identity,
                        world,
                        hash: answer_hash(&meaning),
                        positive: positive_answer(&meaning),
                        born: 0,
                        changed: 0,
                        base: 0,
                        query,
                    },
                ),
            );
        }
    }
    /// The version of every answer the table holds now: the tree, the answer world and each
    /// resource search's current answer (None when the resolver does not version its answers).
    /// Equal versions at two points mean every answer read in between and still held is equal,
    /// so a stage whose other inputs are equal too may reuse its whole earlier output.
    pub(crate) fn answers_version(&self) -> Option<u128> {
        let identity = {
            let current = self.answers.current.read().unwrap_or_else(|error| error.into_inner());
            current.tree.as_ref()?.declaration_identity()
        };
        let context = self.answers_context()?;
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        hash.update(b"dm-answers-version-v2 ");
        hash.update(&identity.to_le_bytes());
        hash.update(&context.to_le_bytes());
        Some(hash.digest128())
    }
    /// What `answers_version` holds besides the tree: the answer world and each resource
    /// search's current answer. Two requests with equal contexts and different trees may still
    /// give every answer the same value; [`Self::prove_against_base`] decides that per answer.
    pub(crate) fn answers_context(&self) -> Option<u128> {
        let world = {
            let current = self.answers.current.read().unwrap_or_else(|error| error.into_inner());
            current.tree.as_ref()?;
            current.world
        };
        if world == 0 {
            return None;
        }
        let mut resources: Vec<(u128, u128)> = {
            let queries =
                self.answers.resource_queries.lock().unwrap_or_else(|error| error.into_inner());
            queries
                .keys()
                .map(|id| {
                    let shard = &self.answers.shards[(*id as usize) % ANSWER_SHARDS];
                    let slots = shard.lock().unwrap_or_else(|error| error.into_inner());
                    (*id, slots.get(id).map_or(0, |slot| slot.hash))
                })
                .collect()
        };
        resources.sort_unstable();
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        hash.update(b"dm-answers-context-v1 ");
        hash.update(&world.to_le_bytes());
        for (id, answer) in resources {
            hash.update(&id.to_le_bytes());
            hash.update(&answer.to_le_bytes());
        }
        Some(hash.digest128())
    }
    /// Record every held answer as the answer of the output that was just published. Called
    /// once the request's output is the retained one (its tree is the current tree, so each
    /// slot a stage asked holds the value that output was built from). The number returned
    /// goes with that output: a later marking (for another output) retires it.
    pub(crate) fn mark_published(&self) -> u64 {
        use std::sync::atomic::Ordering::Relaxed;
        for shard in self.answers.shards.iter() {
            for slot in shard.lock().unwrap_or_else(|error| error.into_inner()).values_mut() {
                slot.base = slot.hash;
            }
        }
        self.answers.marked_drops.store(self.answers.drops.load(Relaxed), Relaxed);
        self.answers.epoch.fetch_add(1, Relaxed) + 1
    }
    /// Ask again, under this request's tree, every answer the published output was built from
    /// and compare with the value it had then. This is the per-answer form of "the answers are
    /// the same", independent of which stage asked what this request: every slot marked at
    /// publication is asked, so no unasked answer is assumed equal. `Ok` carries the number of
    /// answers asked; `Err` says why the published output cannot stand on the answers.
    ///
    /// Answers asked for the first time after the mark (no base) cannot have been read by the
    /// published output's units, so they are not compared; a unit that reads them is new and
    /// is lowered by the caller.
    pub(crate) fn prove_against_base(
        &self,
        answers: &RequestAnswers<'_>,
        marks: u64,
        workers: usize,
    ) -> Result<usize, String> {
        static PROVE: dm_profile::Accumulator = dm_profile::Accumulator::new("query.answer.prove_base");
        let _timer = PROVE.time();
        use std::sync::atomic::Ordering::Relaxed;
        if marks == 0 || self.answers.epoch.load(Relaxed) != marks {
            return Err("the published answers were marked for another output".into());
        }
        if self.answers.drops.load(Relaxed) != self.answers.marked_drops.load(Relaxed) {
            return Err("the answer table was dropped since the output was published".into());
        }
        let mut held: Vec<(u128, dm_ir::ResolveQuery, u128)> = Vec::new();
        for shard in self.answers.shards.iter() {
            let slots = shard.lock().unwrap_or_else(|error| error.into_inner());
            held.extend(
                slots.iter().filter(|(_, slot)| slot.base != 0).map(|(id, slot)| (*id, slot.query, slot.base)),
            );
        }
        let threads = workers.clamp(1, 16);
        let chunk = held.len().div_ceil(threads).max(1);
        let differing: usize = std::thread::scope(|scope| {
            let handles: Vec<_> = held
                .chunks(chunk)
                .map(|part| {
                    scope.spawn(move || {
                        part.iter().filter(|(id, query, base)| !answers.matches(*id, query, *base)).count()
                    })
                })
                .collect();
            handles.into_iter().map(|handle| handle.join().expect("answer proof worker")).sum()
        });
        if differing > 0 {
            return Err(format!("{differing} of {} published answers changed", held.len()));
        }
        Ok(held.len())
    }
    /// Which answers this request holds with a value different from the one before it: from the
    /// slot this table held, else from the hash a stored unit recorded when a proof asked it
    /// (`matches`). It is the per-slot form of what [`Self::answers_version`] compares as one
    /// hash. Only answers some stage asked are slots, and a proof stops at the first differing
    /// read of a unit, so the set is the changed answers the request's stages met, not every
    /// answer the edit could reach.
    pub(crate) fn answer_diff(&self) -> AnswerDiff {
        static DIFF: dm_profile::Accumulator = dm_profile::Accumulator::new("query.answer.diff");
        let _timer = DIFF.time();
        use std::sync::atomic::Ordering;
        let request = self.answers.current.read().unwrap_or_else(|error| error.into_inner()).request;
        let cleared = self.answers.cleared.load(Ordering::Relaxed) == request;
        let mut diff = AnswerDiff { request, cleared, ..Default::default() };
        for shard in self.answers.shards.iter() {
            let slots = shard.lock().unwrap_or_else(|error| error.into_inner());
            diff.held += slots.len();
            for (id, slot) in slots.iter() {
                if slot.changed == request {
                    diff.changed.push(*id);
                } else if slot.born == request {
                    diff.fresh += 1;
                }
            }
        }
        diff.changed.sort_unstable();
        diff
    }
    /// Answers a stage's resolver disagreed with in verification (see [`RequestAnswers`]).
    pub(crate) fn answer_mismatches(&self) -> usize {
        self.answers.mismatches.load(std::sync::atomic::Ordering::Relaxed)
    }
    /// Open a request without source inputs (fixtures): every answer is proven again.
    #[cfg(test)]
    pub(crate) fn next_request(&self) {
        self.answers.next_request();
    }
    /// This request's answers, resolving through `answer`.
    pub(crate) fn request_answers<'a>(
        &'a self,
        answer: &'a (dyn Fn(&dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning + Sync),
    ) -> RequestAnswers<'a> {
        RequestAnswers { db: self, answer }
    }
    /// `(resolved, carried, held)` answers of the current request.
    pub(crate) fn answer_counts(&self) -> (usize, usize, usize) {
        use std::sync::atomic::Ordering::Relaxed;
        (
            self.answers.resolved.load(Relaxed),
            self.answers.carried.load(Relaxed),
            self.answers.len(),
        )
    }

    /// The stored units whose every recorded answer equals the current one.
    pub(crate) fn proven_unchanged<T: Send + Sync + 'static>(
        &self,
        stored: Vec<Stored<T>>,
        answers: &RequestAnswers<'_>,
        workers: usize,
    ) -> Vec<Stored<T>> {
        let detail = std::env::var_os("DMB_TIMINGS_DETAIL").is_some_and(|value| value == "1");
        let started = std::time::Instant::now();
        // Each unit's read list, built once per stored value.
        let units: Vec<Arc<UnitReads>> = {
            let mut cache = self.unit_proofs.units.lock().unwrap_or_else(|error| error.into_inner());
            let mut live = std::collections::HashMap::with_capacity(stored.len());
            let units = stored
                .iter()
                .map(|(_, artifact)| {
                    let address = Arc::as_ptr(&artifact.value) as *const () as usize;
                    let unit = cache.remove(&address).unwrap_or_else(|| {
                        let reads = artifact
                            .reads
                            .iter()
                            .map(|read| (query_id(&read.query), read.query, answer_hash(&read.answer)))
                            .collect();
                        let owner: Arc<dyn std::any::Any + Send + Sync> = artifact.value.clone();
                        Arc::new(UnitReads { _owner: owner, reads })
                    });
                    live.insert(address, Arc::clone(&unit));
                    unit
                })
                .collect();
            *cache = live;
            units
        };
        let after_units = started.elapsed();
        let threads = workers.clamp(1, 16);
        let chunk = units.len().div_ceil(threads).max(1);
        let verdicts: Vec<bool> = std::thread::scope(|scope| {
            let handles: Vec<_> = units
                .chunks(chunk)
                .map(|part| {
                    scope.spawn(move || {
                        part.iter()
                            .map(|unit| {
                                unit.reads
                                    .iter()
                                    .all(|(id, query, recorded)| answers.matches(*id, query, *recorded))
                            })
                            .collect::<Vec<_>>()
                    })
                })
                .collect();
            handles
                .into_iter()
                .flat_map(|handle| handle.join().expect("unit proof worker"))
                .collect()
        });
        let proven: Vec<Stored<T>> = stored
            .into_iter()
            .zip(verdicts)
            .filter_map(|(item, unchanged)| unchanged.then_some(item))
            .collect();
        if detail {
            let (resolved, carried, held) = self.answer_counts();
            eprintln!("detail query answers: {}", self.answer_diff().summary());
            eprintln!(
                "detail query units: stored={} proven={} answers resolved={} carried={} held={} mismatches={} reads={:.3}s check={:.3}s",
                units.len(),
                proven.len(),
                resolved,
                carried,
                held,
                self.answer_mismatches(),
                after_units.as_secs_f64(),
                (started.elapsed() - after_units).as_secs_f64(),
            );
        }
        proven
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_preprocess::regions::prepared_source::PreparedSources;

    fn sources(files: &[(&str, &str)]) -> PreparedSources {
        PreparedSources::from_prepared(files.iter().map(|(path, text)| {
            (PathBuf::from(path), Arc::new(PreparedSource::new(Arc::from(*text))))
        }))
        .unwrap()
    }

    #[test]
    fn program_is_green_only_when_no_input_changed() {
        let db = QueryDb::default();
        let first = db.revise(&sources(&[("a.dm", "x"), ("b.dm", "y")]), 1).unwrap();
        assert!(!first.green);
        assert_eq!((first.sources, first.changed), (2, 2));
        let same = db.revise(&sources(&[("a.dm", "x"), ("b.dm", "y")]), 1).unwrap();
        assert!(same.green, "{same:?}");
        let edited = db.revise(&sources(&[("a.dm", "x2"), ("b.dm", "y")]), 1).unwrap();
        assert!(!edited.green);
        assert_eq!(edited.changed, 1);
        let removed = db.revise(&sources(&[("a.dm", "x2")]), 1).unwrap();
        assert!(!removed.green);
        assert_eq!(removed.removed, 1);
        let project = db.revise(&sources(&[("a.dm", "x2")]), 2).unwrap();
        assert!(!project.green);
        assert!(db.revise(&sources(&[("a.dm", "x2")]), 2).unwrap().green);
    }

    struct Text(String);
    impl dm_preprocess::SourceProvider for Text {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(self.0.clone())
        }
    }
    fn tree(text: &str) -> Arc<dm_tree::SemanticTree> {
        let engine = crate::runner_host::EnginePayload::capture(
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
            1,
            true,
            0,
        )
        .unwrap();
        let seed = engine.snapshot.frontend_seed();
        let front = dm_tree::frontend::build_with_config(
            std::path::Path::new("slots.dme"),
            &Text(text.into()),
            &Default::default(),
            dm_tree::frontend::FrontendConfig { workers: 1, engine: Some(&seed), observer: None },
        )
        .unwrap();
        Arc::clone(&front.snapshot.tree)
    }
    fn symbol(text: &str) -> dm_ir::SymbolId {
        dm_ir::SymbolId::of(text)
    }
    /// The queries a unit reading `/datum/a`'s default, its proc and a neighbour would ask.
    fn asked() -> Vec<dm_ir::ResolveQuery> {
        use dm_ir::ResolveQuery as Q;
        let owner = symbol("/datum/a");
        vec![
            Q::Var { owner, name: symbol("charges") },
            Q::Var { owner, name: symbol("label") },
            Q::HasMemberVar { owner, name: symbol("charges") },
            Q::HasMemberProc { owner, name: symbol("run") },
            Q::HasMemberProc { owner, name: symbol("extra") },
            Q::Proc { owner, name: symbol("run"), verb: false },
        ]
    }
    /// Open a request on `text`, ask every query, and return the diff against the request before.
    fn request(db: &QueryDb, text: &str) -> (AnswerDiff, Vec<(u128, u128)>) {
        let tree = tree(text);
        db.next_request();
        db.begin_answers(&tree, None, &|query| dm_ir::Resolver::resolve(tree.as_ref(), *query));
        let resolver = |query: &dm_ir::ResolveQuery| dm_ir::Resolver::resolve(tree.as_ref(), *query);
        let answers = db.request_answers(&resolver);
        let hashes = asked().iter().map(|q| (query_id(q), answers.current(query_id(q), q))).collect();
        (db.answer_diff(), hashes)
    }
    const BASE: &str = "/datum/a
	var/charges = 25
	var/label = \"x\"
/datum/a/proc/run()
	return 1
";

    #[test]
    fn one_edited_default_changes_exactly_one_answer() {
        let db = QueryDb::default();
        let (first, base) = request(&db, BASE);
        assert_eq!((first.changed.len(), first.fresh), (0, asked().len()), "{first:?}");
        let (same, _) = request(&db, BASE);
        assert_eq!(same.changed, Vec::<u128>::new(), "{same:?}");
        assert_eq!(same.fresh, 0);
        let (edited, now) = request(&db, &BASE.replace("= 25", "= 26"));
        let differing: Vec<u128> =
            base.iter().zip(&now).filter(|(a, b)| a.1 != b.1).map(|(a, _)| a.0).collect();
        assert_eq!(edited.changed, differing, "{edited:?}");
        assert_eq!(edited.changed.len(), 1, "{edited:?}");
        assert_eq!(edited.changed[0], query_id(&asked()[0]));
        assert!(!edited.cleared);
    }

    #[test]
    fn an_edited_body_changes_no_declaration_answer() {
        let db = QueryDb::default();
        request(&db, BASE);
        let (edited, _) = request(&db, &BASE.replace("return 1", "return 2"));
        assert_eq!(edited.changed, Vec::<u128>::new(), "{edited:?}");
        assert_eq!(edited.fresh, 0);
    }

    #[test]
    fn an_added_proc_changes_only_the_answers_that_named_it() {
        let db = QueryDb::default();
        request(&db, BASE);
        let (added, _) = request(&db, &format!("{BASE}/datum/a/proc/extra()
	return 3
"));
        assert_eq!(added.changed, vec![query_id(&asked()[4])], "{added:?}");
        assert!(added.summary().contains(": 1 answers changed"), "{}", added.summary());
    }

    #[test]
    fn dropping_the_table_makes_every_answer_fresh() {
        let db = QueryDb::default();
        request(&db, BASE);
        db.answers.next_request();
        db.answers.clear();
        let diff = db.answer_diff();
        assert!(diff.cleared);
        assert_eq!(diff.held, 0);
    }

    #[test]
    fn a_fresh_table_reports_the_answers_that_differ_from_what_units_recorded() {
        // A table that never saw the earlier revision (a proof opens the slots): the recorded
        // hashes of the earlier revision are the only earlier values.
        let (_, recorded) = request(&QueryDb::default(), BASE);
        let db = QueryDb::default();
        let edited = tree(&BASE.replace("= 25", "= 26"));
        db.next_request();
        db.begin_answers(&edited, None, &|query| dm_ir::Resolver::resolve(edited.as_ref(), *query));
        let resolver = |query: &dm_ir::ResolveQuery| dm_ir::Resolver::resolve(edited.as_ref(), *query);
        let answers = db.request_answers(&resolver);
        for (query, (id, hash)) in asked().iter().zip(&recorded) {
            assert_eq!(answers.matches(*id, query, *hash), *id != query_id(&asked()[0]));
        }
        let diff = db.answer_diff();
        assert_eq!(diff.changed, vec![query_id(&asked()[0])], "{diff:?}");
        assert_eq!(diff.fresh, asked().len() - 1);
    }

    /// Open a request on `text` and ask again every answer marked for the output (`marks`).
    fn prove(db: &QueryDb, text: &str, marks: u64) -> Result<usize, String> {
        let tree = tree(text);
        db.next_request();
        db.begin_answers(&tree, None, &|query| dm_ir::Resolver::resolve(tree.as_ref(), *query));
        let resolver = |query: &dm_ir::ResolveQuery| dm_ir::Resolver::resolve(tree.as_ref(), *query);
        db.prove_against_base(&db.request_answers(&resolver), marks, 2)
    }

    #[test]
    fn a_tree_that_differs_but_gives_every_marked_answer_again_is_admitted() {
        let db = QueryDb::default();
        request(&db, BASE);
        let marks = db.mark_published();
        // A body edit, and a proc nothing marked asked about: the declaration identity differs
        // for the second, every marked answer is the same.
        assert_eq!(prove(&db, &BASE.replace("return 1", "return 2"), marks), Ok(asked().len()));
        let unrelated = format!("{BASE}/datum/a/proc/other()
	return 3
");
        assert_ne!(tree(BASE).declaration_identity(), tree(&unrelated).declaration_identity());
        assert_eq!(prove(&db, &unrelated, marks), Ok(asked().len()));
    }

    #[test]
    fn an_edited_default_or_an_added_proc_that_was_asked_about_is_declined() {
        let db = QueryDb::default();
        request(&db, BASE);
        let marks = db.mark_published();
        let default = prove(&db, &BASE.replace("= 25", "= 26"), marks).unwrap_err();
        assert!(default.starts_with("1 of "), "{default}");
        let proc = prove(&db, &format!("{BASE}/datum/a/proc/extra()
	return 3
"), marks).unwrap_err();
        assert!(proc.starts_with("1 of "), "{proc}");
    }

    #[test]
    fn the_proof_asks_answers_no_stage_asked_this_request() {
        // Nothing asks the answers in the proving request except the proof itself: the edited
        // default is still found, because the proof walks the marked table, not the asked set.
        let db = QueryDb::default();
        request(&db, BASE);
        let marks = db.mark_published();
        assert!(prove(&db, &BASE.replace("= 25", "= 27"), marks).is_err());
        assert!(db.answer_diff().changed.contains(&query_id(&asked()[0])));
    }

    #[test]
    fn marks_that_no_longer_describe_the_output_are_declined() {
        let db = QueryDb::default();
        assert!(prove(&db, BASE, 0).is_err(), "nothing marked");
        request(&db, BASE);
        let first = db.mark_published();
        let second = db.mark_published();
        assert!(prove(&db, BASE, first).unwrap_err().contains("another output"));
        assert!(prove(&db, BASE, second).is_ok());
        db.answers.clear();
        assert!(prove(&db, BASE, second).unwrap_err().contains("dropped"));
    }

    #[test]
    fn an_answer_first_asked_after_the_mark_is_not_compared() {
        let db = QueryDb::default();
        request(&db, BASE);
        let marks = db.mark_published();
        // A stage asks something new in the next request (a new unit's read): it has no base.
        let tree = tree(BASE);
        db.next_request();
        db.begin_answers(&tree, None, &|query| dm_ir::Resolver::resolve(tree.as_ref(), *query));
        let resolver = |query: &dm_ir::ResolveQuery| dm_ir::Resolver::resolve(tree.as_ref(), *query);
        let answers = db.request_answers(&resolver);
        let novel = dm_ir::ResolveQuery::HasMemberVar { owner: symbol("/datum/a"), name: symbol("novel") };
        answers.current(query_id(&novel), &novel);
        assert_eq!(db.prove_against_base(&answers, marks, 1), Ok(asked().len()));
    }
}
