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
}

struct Params {
    argv: Vec<String>,
    env: HashMap<String, String>,
    cwd: PathBuf,
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
        let (done, stdout, stderr) = super::analysis::run_request(p.argv.clone(), p.env.clone(), p.cwd.clone());
        if done.spawned_child {
            ctx.observe_input(Key::new(ENV, 0))?;
        }
        for (name, _) in &done.env_reads {
            ctx.observe(var_key(name), Arc::new(name.clone()))?;
        }
        let mut answer = Answer { code: done.code, report: done.report, stdout, stderr, revision };
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
        let mut hb = Vec::with_capacity(answer.stdout.len() + answer.stderr.len() + 16);
        hb.push(answer.code);
        hb.extend_from_slice(&answer.stdout);
        hb.extend_from_slice(&answer.stderr);
        if let Some(r) = &answer.report {
            hb.extend_from_slice(r.render().as_bytes());
        }
        let bytes = hb.len();
        Ok(Outcome::new(answer, h(&hb), bytes))
    });
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
    let params: Value = Arc::new(Params { argv, env, cwd });
    let got = entry.db.get::<Answer>(key, params);
    let computed = entry.db.stats(ANSWER).computed > before;
    let answer = match got {
        Ok(a) => a,
        Err(error) => {
            super::emit_stderr(format_args!("dmbd analyze: answer query failed ({error:?})"));
            Arc::new(Answer { code: 70, report: None, stdout: Vec::new(), stderr: b"analyze: the daemon could not answer\n".to_vec(), revision: entry.revision })
        }
    };
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
}
