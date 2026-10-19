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
    units_defined: std::sync::Once,
    /// Read lists of the stored lowering units, rebuilt only for new stored values.
    unit_proofs: UnitProofs,
    /// Tree whose answers the `answer` inputs hold, and which of them were positive.
    answered: Mutex<(Option<u128>, std::collections::HashMap<u128, bool>)>,
    /// Revision at which the `project` input last changed.
    project_changed_at: std::sync::atomic::AtomicU64,
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
            units_defined: std::sync::Once::new(),
            unit_proofs: UnitProofs::default(),
            answered: Mutex::new((None, Default::default())),
            project_changed_at: std::sync::atomic::AtomicU64::new(u64::MAX),
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
            self.project_changed_at
                .store(self.db.revision(), std::sync::atomic::Ordering::SeqCst);
            self.answered.lock().unwrap_or_else(|error| error.into_inner()).0 = None;
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

// --- Answers and stored-unit validity (migration step 4) -----------------------------------
//
// Every distinct `ResolveQuery` read by a stored unit is an input `answer(query)` whose hash is
// the canonical encoding of the current answer. A stored unit is a derived `unit` query over the
// answers it read, true when each still equals the recorded one. It reruns only when one of its
// answers changed, so an unchanged unit is proven by revalidation, without certificates.

const ANSWER: Kind = Kind(4);
const UNIT: Kind = Kind(5);

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
fn answer_hash(answer: &dm_ir::ResolvedMeaning) -> u128 {
    dm_query::hash_bytes(&answer.canonical_bytes())
}

/// A stored unit's recorded reads as (answer key, recorded answer hash), and its identity.
struct UnitReads {
    _owner: Arc<dyn std::any::Any + Send + Sync>,
    id: u128,
    reads: Arc<Vec<(Key, u128)>>,
    queries: Vec<dm_ir::ResolveQuery>,
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
    fn define_units(&self) {
        self.units_defined.call_once(|| {
            self.db.define_input(ANSWER, "answer");
            self.db.define(UNIT, "unit", |ctx, params| {
                let reads = params
                    .downcast_ref::<Vec<(Key, u128)>>()
                    .ok_or(QueryError::Missing(Key::new(UNIT, 0)))?;
                let mut unchanged = true;
                for (key, recorded) in reads.iter() {
                    if ctx.observe_input(*key)? != *recorded {
                        unchanged = false;
                        break;
                    }
                }
                Ok(Outcome::new(unchanged, u128::from(unchanged), 1))
            });
        });
    }

    /// The stored units whose every recorded answer equals the current answer of `answer`.
    pub(crate) fn proven_unchanged<T: Send + Sync + 'static>(
        &self,
        stored: Vec<Stored<T>>,
        answer: &(dyn Fn(&dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning + Sync),
        tree: Option<&dm_tree::SemanticTree>,
        workers: usize,
    ) -> Vec<Stored<T>> {
        self.define_units();
        let detail = std::env::var_os("DMB_TIMINGS_DETAIL").is_some_and(|value| value == "1");
        let started = std::time::Instant::now();
        // 1. Each unit's read list, built once per stored value.
        let units: Vec<Arc<UnitReads>> = {
            let mut cache = self.unit_proofs.units.lock().unwrap_or_else(|error| error.into_inner());
            let mut live = std::collections::HashMap::with_capacity(stored.len());
            let units = stored
                .iter()
                .map(|(key, artifact)| {
                    let address = Arc::as_ptr(&artifact.value) as *const () as usize;
                    let unit = cache.remove(&address).unwrap_or_else(|| {
                        let mut reads = Vec::new();
                        let mut queries = Vec::new();
                        let mut id = xxhash_rust::xxh3::Xxh3::new();
                        id.update(key);
                        for read in artifact.reads.iter() {
                            let query = query_id(&read.query);
                            let recorded = answer_hash(&read.answer);
                            id.update(&query.to_le_bytes());
                            id.update(&recorded.to_le_bytes());
                            reads.push((Key::new(ANSWER, query), recorded));
                            queries.push(read.query);
                        }
                        let owner: Arc<dyn std::any::Any + Send + Sync> = artifact.value.clone();
                        Arc::new(UnitReads {
                            _owner: owner,
                            id: id.digest128(),
                            reads: Arc::new(reads),
                            queries,
                        })
                    });
                    live.insert(address, Arc::clone(&unit));
                    unit
                })
                .collect();
            *cache = live;
            units
        };
        let after_units = started.elapsed();
        // 2. Current answers of every distinct query.
        let mut distinct: std::collections::HashMap<u128, dm_ir::ResolveQuery> =
            std::collections::HashMap::new();
        for unit in &units {
            for ((key, _), query) in unit.reads.iter().zip(&unit.queries) {
                distinct.entry(key.id).or_insert(*query);
            }
        }
        let distinct: Vec<(u128, dm_ir::ResolveQuery)> = distinct.into_iter().collect();
        let threads = workers.clamp(1, 16);
        let chunk = distinct.len().div_ceil(threads).max(1);
        // A positive answer about an owner/name the declaration change cannot reach is still
        // current: skip resolving it. Only when the inputs hold exactly the previous tree.
        let mut answered = self.answered.lock().unwrap_or_else(|error| error.into_inner());
        // The same declaration identity (a body-only edit reusing the tree) is an empty change.
        let unchanged = dm_tree::change_set::ChangeSince {
            from_identity: 0,
            set: Default::default(),
        };
        let change = tree.and_then(|tree| {
            if answered.0 == Some(tree.declaration_identity()) {
                return Some((&unchanged, tree));
            }
            tree.change_since()
                .filter(|change| answered.0 == Some(change.from_identity))
                .map(|change| (change.as_ref(), tree))
        });
        let previous = &answered.1;
        let skipped = std::sync::atomic::AtomicUsize::new(0);
        let positives: Vec<Vec<(u128, bool)>> = std::thread::scope(|scope| {
            let handles: Vec<_> = distinct
                .chunks(chunk)
                .map(|part| {
                    let skipped = &skipped;
                    scope.spawn(move || {
                    let mut positives = Vec::with_capacity(part.len());
                    static RESOLVE: dm_profile::Accumulator = dm_profile::Accumulator::new("query.answer.resolve");
                    static HASH: dm_profile::Accumulator = dm_profile::Accumulator::new("query.answer.hash");
                    static SET: dm_profile::Accumulator = dm_profile::Accumulator::new("query.answer.set");
                    for (id, query) in part {
                        if let Some((change, tree)) = change {
                            if previous.get(id) == Some(&true) && !answer_reachable(change, tree, query) {
                                skipped.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                                positives.push((*id, true));
                                continue;
                            }
                        }
                        let timer = RESOLVE.time();
                        let current = answer(query);
                        drop(timer);
                        let timer = HASH.time();
                        let hash = answer_hash(&current);
                        drop(timer);
                        let _timer = SET.time();
                        self.db.set_input(Key::new(ANSWER, *id), (), hash);
                        positives.push((*id, positive_answer(&current)));
                    }
                    positives
                    })
                })
                .collect();
            handles.into_iter().map(|handle| handle.join().expect("answer worker")).collect()
        });
        let skipped = skipped.into_inner();
        answered.0 = tree.map(|tree| tree.declaration_identity());
        answered.1 = positives.into_iter().flatten().collect();
        drop(answered);
        let after_answers = started.elapsed();
        // 3. Revalidate every unit.
        let chunk = units.len().div_ceil(threads).max(1);
        let verdicts: Vec<bool> = std::thread::scope(|scope| {
            let handles: Vec<_> = units
                .chunks(chunk)
                .map(|part| {
                    scope.spawn(move || {
                        part.iter()
                            .map(|unit| {
                                let params: Value = unit.reads.clone();
                                self.db
                                    .get::<bool>(Key::new(UNIT, unit.id), params)
                                    .is_ok_and(|unchanged| *unchanged)
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
            eprintln!(
                "detail query units: stored={} answers={} skipped={} proven={} reads={:.3}s answers={:.3}s units={:.3}s computed={}",
                units.len(),
                distinct.len(),
                skipped,
                proven.len(),
                after_units.as_secs_f64(),
                (after_answers - after_units).as_secs_f64(),
                (started.elapsed() - after_answers).as_secs_f64(),
                self.db.stats(UNIT).computed,
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
}
