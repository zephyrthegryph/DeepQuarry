//! Hosted analysis answers as queries (lean_unified "One program", 1+3 ENGINE): one `dm_query::Db` per project root, held by the
//! daemon, whose top query is a command's whole answer.
//!
//! Kinds, per root:
//!
//! * `TREE` (input): the files under the root. Its hash moves when the directory watcher (`fs_watch`) saw a change to anything under
//!   the root that can be an input (`relevant`); a lost event, another epoch or a root the watcher does not cover counts as a change.
//! * `ENV` (input): the request's whole environment.
//! * `VAR(name)` (derived from `ENV`): one variable's value. Early cutoff: a request whose environment differs only in variables the
//!   command never read leaves every `VAR` it read green.
//! * `ANSWER(argv, cwd)` (derived): the command's answer: its exit code, its stderr, its report (`dq_analyze::report`) and its stdout
//!   when it made no report. It reads `TREE` and the `VAR`s of the variables the run read (`dq_hostio::env_reads`); a run that started
//!   a child command also reads `ENV` whole.
//!
//! So a request whose files and read variables are unchanged is answered from memory without running analyze. Only commands
//! `dq_analyze::cli::rememberable` names are asked through the database; the rest run as before.
//!
//! What counts as a change (`relevant`): anything under the root except what no command reads: the watcher's own cookies
//! (`.dmbc`), `.git`, `data` (analyze's caches, test runs) and every `target` or `node_modules` directory.
//!
//! Persistence: a computed answer is also written to `answer-<key>.bin` beside the analysis stores' slots (this binary image's
//! directory under `E:/dq-cache/analysis`, `[cache.analysis]` in tools/ci/disk_budget.toml) with what it read: a fingerprint of every
//! file the watcher would report (`fingerprint`: path, size and modification time, taken as the run starts) and the variables it read.
//! `ANSWER`'s function looks there first, so a restarted daemon (an empty database, no watcher history) answers an unchanged request
//! from the file after one walk of the root instead of running the command. An answer is written only when the watcher saw no
//! relevant change while it was computed (else the fingerprint could name files newer than what the run read).
use dm_query::{Db, Hash, Key, Kind, Outcome, Value};
use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

const TREE: Kind = Kind(1);
const ENV: Kind = Kind(2);
const VAR: Kind = Kind(3);
const ANSWER: Kind = Kind(4);

/// A command's answer.
pub(super) struct Answer {
    pub code: u8,
    /// Its report, when it made one (then its stdout is the report rendered).
    pub report: Option<dq_analyze::report::Report>,
    /// Its stdout, when it made no report, or when the report does not render to what it printed (kept as printed then).
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    /// The `TREE` revision it was computed at (the revision its report is named by).
    pub revision: u64,
    /// What the run read, for its persisted copy (`None`: read back from one, or not to be persisted).
    persist: Option<Persisted>,
    /// The walk taking the root's fingerprint for `persist`, started with the run; joined after the reply (`answer`).
    walk: Mutex<Option<std::thread::JoinHandle<Option<Hash>>>>,
}

/// An answer on disk with what it read.
#[derive(serde::Serialize, serde::Deserialize, Clone)]
struct Persisted {
    root: String,
    argv: Vec<String>,
    cwd: String,
    fingerprint: Hash,
    env_reads: Vec<(String, Option<String>)>,
    code: u8,
    report: Option<dq_analyze::report::Report>,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}

struct Params {
    root: PathBuf,
    argv: Vec<String>,
    env: HashMap<String, String>,
    cwd: PathBuf,
    /// The first `TREE` revision of the root in this process: only then can an answer on disk be newer than what memory holds
    /// (a restarted daemon). Later the database knows every answer it gave, and a recomputed one is not read back.
    fresh: bool,
}

/// One project root's database and what the watcher last proved for it.
struct Root {
    db: Db,
    token: Option<crate::fs_watch::WatchToken>,
    /// The `TREE` revision: bumped on every relevant change.
    revision: u64,
    /// Reports by the revision they were made at, newest last (the base of "what changed since revision N").
    history: VecDeque<(u64, Arc<dq_analyze::report::Report>)>,
}

const HISTORY: usize = 16;

fn h(bytes: &[u8]) -> Hash {
    dm_query::hash_bytes(bytes)
}

fn var_key(name: &str) -> Key {
    Key::new(VAR, h(name.as_bytes()))
}

fn answer_key(argv: &[String], cwd: &Path) -> Key {
    let mut b = Vec::new();
    for a in argv.iter().skip(1) {
        b.extend_from_slice(a.as_bytes());
        b.push(0);
    }
    b.extend_from_slice(cwd.to_string_lossy().as_bytes());
    Key::new(ANSWER, h(&b))
}

fn define(db: &Db, current_revision: Arc<Mutex<u64>>) {
    db.define_input(TREE, "analysis-tree");
    db.define_input(ENV, "analysis-env");
    db.define(VAR, "analysis-var", |ctx, params| {
        let name = params.downcast_ref::<String>().cloned().unwrap_or_default();
        let env = ctx.input::<HashMap<String, String>>(Key::new(ENV, 0))?;
        let value = dq_hostio::lookup(&env, &name).cloned();
        let hash = match &value {
            Some(v) => h(format!("={v}").as_bytes()),
            None => h(b"absent"),
        };
        Ok(Outcome::new(value, hash, 64))
    });
    db.define(ANSWER, "analysis-answer", move |ctx, params| {
        let Some(p) = params.downcast_ref::<Params>() else { return Err(dm_query::QueryError::Missing(Key::new(ANSWER, 0))) };
        ctx.observe_input(Key::new(TREE, 0))?;
        let revision = *current_revision.lock().unwrap_or_else(|e| e.into_inner());
        let root = p.root.clone();
        let walker = std::thread::Builder::new().name("analyze-fingerprint".into()).spawn(move || fingerprint(&root));
        let stored = if p.fresh { load(&p.root, &p.argv, &p.cwd) } else { None };
        let join = |w: std::io::Result<std::thread::JoinHandle<Option<Hash>>>| w.ok().and_then(|h| h.join().ok()).flatten();
        if let Some(rec) = stored {
            let fp = join(walker);
            let same_env = rec.env_reads.iter().all(|(k, v)| dq_hostio::lookup(&p.env, k) == v.as_ref());
            if fp == Some(rec.fingerprint) && same_env {
                for (name, _) in &rec.env_reads {
                    ctx.observe(var_key(name), Arc::new(name.clone()))?;
                }
                super::emit_stderr(format_args!("dmbd analyze: answer read back from disk (nothing it read changed)"));
                let hash = answer_hash(rec.code, &rec.stdout, &rec.stderr, rec.report.as_ref());
                let bytes = rec.stdout.len() + rec.stderr.len();
                let answer = Answer {
                    code: rec.code,
                    report: rec.report,
                    stdout: rec.stdout,
                    stderr: rec.stderr,
                    revision,
                    persist: None,
                    walk: Mutex::new(None),
                };
                return Ok(Outcome::new(answer, hash, bytes));
            }
            return compute_now(ctx, p, revision, fp);
        }
        // The fingerprint is for the persisted copy only: the reply does not wait for the walk (`answer` joins it afterwards).
        let mut outcome = compute_now(ctx, p, revision, None);
        if let (Ok(o), Ok(walker)) = (&mut outcome, walker) {
            if let Some(a) = Arc::get_mut(&mut o.value).and_then(|v| v.downcast_mut::<Answer>()) {
                if a.persist.is_some() {
                    *a.walk.get_mut().unwrap_or_else(|e| e.into_inner()) = Some(walker);
                }
            }
        }
        outcome
    });
}

fn answer_hash(code: u8, stdout: &[u8], stderr: &[u8], report: Option<&dq_analyze::report::Report>) -> Hash {
    let mut hb = Vec::with_capacity(stdout.len() + stderr.len() + 16);
    hb.push(code);
    hb.extend_from_slice(stdout);
    hb.extend_from_slice(stderr);
    if let Some(r) = report {
        hb.extend_from_slice(r.render().as_bytes());
    }
    h(&hb)
}

/// Runs the command now. `fp`: the root's fingerprint when it was already taken (before the run started), else filled in by the
/// caller once its walk ends.
fn compute_now(ctx: &mut dm_query::Ctx<'_>, p: &Params, revision: u64, fp: Option<Hash>) -> Result<Outcome, dm_query::QueryError> {
    {
        let (done, stdout, stderr) = super::analysis::run_request(p.argv.clone(), p.env.clone(), p.cwd.clone());
        if done.spawned_child {
            ctx.observe_input(Key::new(ENV, 0))?;
        }
        for (name, _) in &done.env_reads {
            ctx.observe(var_key(name), Arc::new(name.clone()))?;
        }
        let persist = (!done.spawned_child).then(|| Persisted {
            root: p.root.to_string_lossy().into_owned(),
            argv: p.argv.clone(),
            cwd: p.cwd.to_string_lossy().into_owned(),
            fingerprint: fp.unwrap_or(0),
            env_reads: done.env_reads.clone(),
            code: done.code,
            report: None,
            stdout: Vec::new(),
            stderr: Vec::new(),
        });
        let mut answer = Answer { code: done.code, report: done.report, stdout, stderr, revision, persist, walk: Mutex::new(None) };
        if let Some(r) = &answer.report {
            if r.render().as_bytes() == answer.stdout.as_slice() {
                answer.stdout = Vec::new();
            } else {
                super::emit_stderr(format_args!(
                    "dmbd analyze: WARNING the report does not render to what the command printed; keeping its printed output"
                ));
                answer.report = None;
            }
        }
        let hash = answer_hash(answer.code, &answer.stdout, &answer.stderr, answer.report.as_ref());
        let bytes = answer.stdout.len() + answer.stderr.len();
        Ok(Outcome::new(answer, hash, bytes))
    }
}

/// Where answers persist: the analysis stores' directory (this binary image's), if they persist.
fn answer_dir() -> Option<PathBuf> {
    super::analysis::stores_dir().map(Path::to_path_buf)
}

fn answer_file(dir: &Path, root: &Path, argv: &[String], cwd: &Path) -> PathBuf {
    let mut b = root.to_string_lossy().into_owned().into_bytes();
    b.push(0);
    b.extend_from_slice(&answer_key(argv, cwd).id.to_le_bytes());
    dir.join(format!("answer-{:032x}.bin", h(&b)))
}

fn load(root: &Path, argv: &[String], cwd: &Path) -> Option<Persisted> {
    let dir = answer_dir()?;
    let bytes = std::fs::read(answer_file(&dir, root, argv, cwd)).ok()?;
    let rec: Persisted = dq_analyze::incr::de(&bytes).ok()?;
    (rec.root == root.to_string_lossy() && rec.argv == argv && rec.cwd == cwd.to_string_lossy()).then_some(rec)
}

fn save(root: &Path, argv: &[String], cwd: &Path, rec: &Persisted) {
    let Some(dir) = answer_dir() else { return };
    let _ = std::fs::create_dir_all(&dir);
    let path = answer_file(&dir, root, argv, cwd);
    if let Ok(bytes) = dq_analyze::incr::ser(rec) {
        let tmp = path.with_extension(format!("tmp{}", std::process::id()));
        if std::fs::write(&tmp, &bytes).is_err() || std::fs::rename(&tmp, &path).is_err() {
            let _ = std::fs::remove_file(&tmp);
        }
    }
}

/// A digest of every file under `root` a relevant change could name (`relevant`): its path, size and modification time. Links are
/// not followed (the watcher reports nothing behind one either). `None` when a directory cannot be read.
pub(super) fn fingerprint(root: &Path) -> Option<Hash> {
    let mut rows: Vec<(String, u64, u128)> = Vec::new();
    let mut stack: Vec<(PathBuf, String)> = vec![(root.to_path_buf(), String::new())];
    while let Some((dir, rel)) = stack.pop() {
        for entry in std::fs::read_dir(&dir).ok()? {
            let entry = entry.ok()?;
            let name = entry.file_name().to_string_lossy().to_ascii_lowercase();
            let child = if rel.is_empty() { name.clone() } else { format!("{rel}\\{name}") };
            if rel.is_empty() && matches!(name.as_str(), ".dmbc" | ".git" | "data") {
                continue;
            }
            if name == "target" || name == "node_modules" {
                continue;
            }
            let kind = entry.file_type().ok()?;
            if kind.is_symlink() {
                continue;
            }
            if kind.is_dir() {
                stack.push((entry.path(), child));
                continue;
            }
            let meta = entry.metadata().ok()?;
            let modified = meta.modified().ok().and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map_or(0, |d| d.as_nanos());
            rows.push((child, meta.len(), modified));
        }
    }
    rows.sort();
    let mut hasher = xxhash_rust::xxh3::Xxh3::new();
    for (path, len, modified) in &rows {
        hasher.update(path.as_bytes());
        hasher.update(&len.to_le_bytes());
        hasher.update(&modified.to_le_bytes());
    }
    Some(hasher.digest128())
}

/// Whether a change the watcher logged (a key under `root_key`, the watcher's spelling) can change an answer.
fn relevant(root_key: &str, key: &str, subtree: bool) -> bool {
    let Some(rel) = key.strip_prefix(root_key) else {
        // Not under this root: a change to an ancestor's whole subtree covers the root too.
        return subtree && root_key.starts_with(key) && root_key.as_bytes().get(key.len()) == Some(&b'\\');
    };
    let rel = rel.trim_start_matches('\\');
    if rel.is_empty() {
        // The root itself: its listing changed (an entry appeared or went), or with `subtree` everything below may have.
        return true;
    }
    if !key[root_key.len()..].starts_with('\\') {
        // A sibling whose name starts with the root's (`pool-3x`).
        return false;
    }
    let mut parts = rel.split('\\');
    let first = parts.next().unwrap_or("");
    if matches!(first, ".dmbc" | ".git" | "data") {
        return false;
    }
    !rel.split('\\').any(|c| c == "target" || c == "node_modules")
}

struct Roots {
    roots: HashMap<PathBuf, Root>,
}

fn roots() -> &'static Mutex<Roots> {
    static ROOTS: std::sync::OnceLock<Mutex<Roots>> = std::sync::OnceLock::new();
    ROOTS.get_or_init(|| Mutex::new(Roots { roots: HashMap::new() }))
}

/// The revision the answer being computed is made at (read by `ANSWER`'s function; requests run one at a time).
fn current() -> &'static Arc<Mutex<u64>> {
    static CURRENT: std::sync::OnceLock<Arc<Mutex<u64>>> = std::sync::OnceLock::new();
    CURRENT.get_or_init(|| Arc::new(Mutex::new(0)))
}

/// The answer to one request, from memory when nothing it read changed. Also returns the report made at `since`, when the
/// history still holds it, and whether the answer was computed now.
pub(super) fn answer(
    root: &Path,
    argv: Vec<String>,
    env: HashMap<String, String>,
    cwd: PathBuf,
    since: Option<u64>,
) -> (Arc<Answer>, Option<Arc<dq_analyze::report::Report>>, bool) {
    let mut all = roots().lock().unwrap_or_else(|e| e.into_inner());
    let entry = all.roots.entry(root.to_path_buf()).or_insert_with(|| {
        let db = Db::new();
        define(&db, Arc::clone(current()));
        Root { db, token: None, revision: 0, history: VecDeque::new() }
    });
    // Order this request after every write under the root, then ask the watcher what changed since the last request.
    crate::fs_watch::arm(root);
    crate::fs_watch::sync(root);
    let now = crate::fs_watch::token();
    let root_key = crate::fs_watch::watch_key(root);
    let covered = crate::fs_watch::covered(root);
    let changed: Option<usize> = match (entry.token, now, &root_key) {
        (Some(since), Some(now), Some(rk)) if covered => crate::fs_watch::changed_entries_since(since, now)
            .map(|entries| entries.iter().filter(|(k, subtree)| relevant(rk, k, *subtree)).count()),
        _ => None,
    };
    if changed != Some(0) || entry.revision == 0 {
        entry.revision += 1;
        entry.db.set_input(Key::new(TREE, 0), entry.revision, entry.revision as Hash);
    }
    entry.token = if covered { now } else { None };
    let mut sorted: Vec<(&String, &String)> = env.iter().collect();
    sorted.sort();
    let env_hash = h(format!("{sorted:?}").as_bytes());
    entry.db.set_input(Key::new(ENV, 0), env.clone(), env_hash);
    *current().lock().unwrap_or_else(|e| e.into_inner()) = entry.revision;
    let key = answer_key(&argv, &cwd);
    let before = entry.db.stats(ANSWER).computed;
    let (argv_kept, cwd_kept) = (argv.clone(), cwd.clone());
    let params: Value = Arc::new(Params { root: root.to_path_buf(), argv, env, cwd, fresh: entry.revision == 1 });
    let got = entry.db.get::<Answer>(key, params);
    let computed = entry.db.stats(ANSWER).computed > before;
    let answer = match got {
        Ok(a) => a,
        Err(error) => {
            super::emit_stderr(format_args!("dmbd analyze: answer query failed ({error:?})"));
            Arc::new(Answer {
                code: 70,
                report: None,
                stdout: Vec::new(),
                stderr: b"analyze: the daemon could not answer\n".to_vec(),
                revision: entry.revision,
                persist: None,
                walk: Mutex::new(None),
            })
        }
    };
    // Persist what was just computed, unless the watcher saw a relevant change while it ran (its fingerprint could be newer than
    // what it read) or it read something the record cannot name.
    // The fingerprint walk of a computed answer (started with its run) is joined on a thread of its own, so the reply does not wait
    // for it; "quiet" is judged when the walk has ended.
    if computed {
        if let (Some(rec), Some(start), Some(rk)) = (&answer.persist, now, root_key.clone()) {
            let walk = answer.walk.lock().unwrap_or_else(|e| e.into_inner()).take();
            let mut rec = rec.clone();
            rec.code = answer.code;
            rec.report = answer.report.clone();
            rec.stdout = answer.stdout.clone();
            rec.stderr = answer.stderr.clone();
            let root = root.to_path_buf();
            let persist = move || {
                if let Some(fp) = walk.and_then(|w| w.join().ok()).flatten() {
                    rec.fingerprint = fp;
                }
                let quiet = crate::fs_watch::token()
                    .and_then(|end| crate::fs_watch::changed_entries_since(start, end))
                    .is_some_and(|entries| !entries.iter().any(|(k, subtree)| relevant(&rk, k, *subtree)));
                if quiet && rec.fingerprint != 0 {
                    save(&root, &argv_kept, &cwd_kept, &rec);
                }
            };
            if std::thread::Builder::new().name("analyze-persist-answer".into()).spawn(persist).is_err() {
                super::emit_stderr(format_args!("dmbd analyze: could not start the thread that persists the answer"));
            }
        }
    }
    if let Some(r) = &answer.report {
        if entry.history.back().is_none_or(|(rev, _)| *rev != answer.revision) {
            entry.history.push_back((answer.revision, Arc::new(r.clone())));
            while entry.history.len() > HISTORY {
                entry.history.pop_front();
            }
        }
    }
    let base = since.and_then(|n| entry.history.iter().find(|(rev, _)| *rev == n).map(|(_, r)| Arc::clone(r)));
    (answer, base, computed)
}

#[cfg(test)]
mod tests {
    use super::relevant;

    #[test]
    fn changes_that_no_command_reads_are_not_relevant() {
        let root = r"e:\projects\dq-wt\pool-3";
        assert!(relevant(root, r"e:\projects\dq-wt\pool-3\code\a.dm", false));
        assert!(relevant(root, r"e:\projects\dq-wt\pool-3\tools\ci\lint_scopes.toml", false));
        assert!(relevant(root, root, false));
        assert!(relevant(root, r"e:\projects\dq-wt", true));
        assert!(!relevant(root, r"e:\projects\dq-wt", false));
        assert!(!relevant(root, r"e:\projects\dq-wt\pool-3\.dmbc\watch-cookie-1-2", false));
        assert!(!relevant(root, r"e:\projects\dq-wt\pool-3\data\analyze-cache\meta.bin", false));
        assert!(!relevant(root, r"e:\projects\dq-wt\pool-3\tools\analyze\target\x", false));
        assert!(!relevant(root, r"e:\projects\dq-wt\pool-3\tgui\node_modules\y", true));
        assert!(!relevant(root, r"e:\projects\dq-wt\pool-30\code\a.dm", false));
    }

    /// The fingerprint names what a relevant change names: an edit, a new file or a removed one moves it; a write where no command
    /// reads (`data`, a `target`, the watcher's cookies) does not.
    #[test]
    fn the_fingerprint_moves_with_relevant_files_only() {
        let root = crate::test_scratch::dir("analysis-fingerprint");
        std::fs::create_dir_all(root.join("code")).unwrap();
        std::fs::write(root.join("code").join("a.dm"), "x").unwrap();
        let base = super::fingerprint(&root).unwrap();
        for ignored in ["data/analyze-cache/meta.bin", "tools/analyze/target/x", ".dmbc/watch-cookie-1"] {
            let path = root.join(ignored);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(&path, "y").unwrap();
        }
        assert_eq!(super::fingerprint(&root), Some(base));
        std::fs::write(root.join("code").join("a.dm"), "xy").unwrap();
        let edited = super::fingerprint(&root).unwrap();
        assert_ne!(edited, base);
        std::fs::write(root.join("code").join("b.dm"), "").unwrap();
        let added = super::fingerprint(&root).unwrap();
        assert_ne!(added, edited);
        std::fs::remove_file(root.join("code").join("b.dm")).unwrap();
        assert_eq!(super::fingerprint(&root), Some(edited));
    }
}
