//! The runner: loads the tree once, runs every selected lint (in parallel, cached), applies each
//! lint's ratchet policy and assembles the report.

use std::collections::{HashMap, HashSet};
use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use rayon::prelude::*;

use crate::baseline::{self, Mode};
use crate::cache::Cache;
use crate::lint::{AllowUse, Cx, Lint, Meta, Policy, Registry, Run, ScanKind, Sink};
use crate::scopes::Scopes;
use crate::tree::{Plan, Tree};

#[derive(Clone, Debug, Default)]
pub struct Options {
    pub root: PathBuf,
    /// Lint names or group names; empty = every lint.
    pub lints: Vec<String>,
    /// Only report findings in files changed relative to the base branch (and the working tree).
    pub changed_only: bool,
    pub no_cache: bool,
    pub rehash: bool,
    /// Ignore every baseline: each site is "new" (the parity harness and `--report`).
    pub raw: bool,
    /// Emit `::group::` markers (CI logs).
    pub ci: bool,
    /// Read `tools/ci/lint_scopes.toml` from this repo root instead of `root` (fixture trees).
    pub scopes_from: Option<PathBuf>,
}

/// The first lint's start (`DQ_ANALYZE_TRACE_SPANS` prints each lint's span relative to it).
static SPAN_ORIGIN: std::sync::OnceLock<Instant> = std::sync::OnceLock::new();

/// Total time spent reading lint caches (`DQ_ANALYZE_TRACE`).
pub static LOAD_NS: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

#[derive(Clone, Debug, Default)]
pub struct Timing {
    pub total: Duration,
    pub files: usize,
    pub rescanned: usize,
    pub tree_memo_hit: bool,
}

pub struct Outcome {
    pub name: String,
    pub failed: bool,
    pub text: String,
    pub run: Run,
    pub allow_used: Vec<AllowUse>,
    pub timing: Timing,
    pub internal_error: Option<String>,
}

pub struct Engine {
    pub reg: Registry,
    pub scopes: Scopes,
    pub tree: Tree,
    pub cache: Cache,
    pub opts: Options,
    pub load_time: Duration,
    pub files_read: usize,
    meta: HashMap<String, crate::tree::FileMeta>,
    changed: Option<HashSet<String>>,
}

/// Every lint of the engine.
pub fn registry() -> Registry {
    let mut reg = Registry::default();
    crate::lints::register(&mut reg);
    reg
}

pub fn selected<'a>(reg: &'a Registry, names: &[String]) -> Vec<&'a dyn Lint> {
    // `-name` excludes a lint or group; with only exclusions every other lint is selected.
    let matches = |l: &dyn Lint, n: &str| l.meta().name == n || (!l.meta().group.is_empty() && l.meta().group == n);
    let include: Vec<&String> = names.iter().filter(|n| !n.starts_with('-')).collect();
    let exclude: Vec<&str> = names.iter().filter_map(|n| n.strip_prefix('-')).collect();
    reg.lints
        .iter()
        .map(|b| b.as_ref())
        .filter(|l| include.is_empty() || include.iter().any(|n| matches(*l, n)))
        .filter(|l| !exclude.iter().any(|n| matches(*l, n)))
        .collect()
}

impl Engine {
    pub fn new(reg: Registry, opts: Options) -> Result<Engine, String> {
        let t0 = Instant::now();
        let scopes_root = opts.scopes_from.clone().unwrap_or_else(|| opts.root.clone());
        let scopes = Scopes::load(&scopes_root.join("tools").join("ci").join("lint_scopes.toml"))?;
        // Every ALLOW name some lint reads (the allow_annotations lint validates names against it).
        let mut known: std::collections::BTreeSet<String> = scopes.known_allow.iter().cloned().collect();
        for l in &reg.lints {
            for a in l.meta().allow {
                known.insert(a.to_string());
            }
        }
        crate::lints::allow_annotations::set_known(known);
        let cache = Cache::open(&opts.root, &scopes.hash, !opts.no_cache);
        let prior = cache.load_meta();
        let mut plan = Plan::default();
        let chosen = selected(&reg, &opts.lints);
        if chosen.is_empty() {
            return Err(format!("no lint matches {:?}", opts.lints));
        }
        for l in &chosen {
            for (dir, ext) in l.meta().select.roots {
                plan.add(dir, ext);
            }
        }
        let t_prior = t0.elapsed();
        let (tree, meta) = Tree::load(&opts.root, &plan, &prior, opts.rehash);
        let t_tree = t0.elapsed();
        // Persist the file table only when something changed (a rewrite costs more than a walk).
        if prior.len() != meta.len() || meta.iter().any(|(k, v)| prior.get(k) != Some(v)) {
            cache.save_meta(&meta);
        }
        if std::env::var("DQ_ANALYZE_TRACE").is_ok() {
            eprintln!("analyze: scopes+meta load {:.1?}, walk+hash {:.1?}, save {:.1?}", t_prior, t_tree - t_prior, t0.elapsed() - t_tree);
        }
        let t_lines = Instant::now();
        if let Some(dir) = crate::incr::dir() {
            tree.load_line_cache(&dir.join("linetext.bin"), cache.stamp());
        }
        if std::env::var("DQ_ANALYZE_TRACE").is_ok() {
            eprintln!("analyze: line cache load {:.1?}", t_lines.elapsed());
        }
        let changed = if opts.changed_only { Some(changed_files(&opts.root)) } else { None };
        let load_time = t0.elapsed();
        let files_read = tree.files.len();
        Ok(Engine { reg, scopes, tree, cache, opts, load_time, files_read, meta, changed })
    }

    pub fn meta_len(&self) -> usize {
        self.meta.len()
    }

    /// Fail fast on a lint whose scope section lacks a list it declares.
    pub fn validate_scopes(&self) -> Vec<String> {
        let mut problems = Vec::new();
        for l in &self.reg.lints {
            let m = l.meta();
            let scope = self.scopes.for_lint(m.name, m.group);
            for key in m.lists {
                if !scope.lists.contains_key(*key) {
                    problems.push(format!("lint_scopes.toml: [lint.{}.lists] is missing `{}`", m.name, key));
                }
            }
        }
        problems
    }

    fn baseline_path(&self, rel: &str) -> PathBuf {
        self.opts.root.join(rel)
    }

    /// Scans one lint (cached) and returns its raw sites.
    pub fn scan(&self, lint: &dyn Lint) -> (Run, Vec<AllowUse>, Timing) {
        let t0 = Instant::now();
        let meta = lint.meta();
        let scope = self.scopes.for_lint(meta.name, meta.group);
        let cx = Cx { tree: &self.tree, meta, scope: &scope };
        let t_load = Instant::now();
        let mut lc = self.cache.load_lint(meta.name);
        LOAD_NS.fetch_add(t_load.elapsed().as_nanos() as u64, std::sync::atomic::Ordering::Relaxed);
        let mut timing = Timing::default();
        let mut sites = Vec::new();
        let mut notes = Vec::new();
        let mut allow_used: Vec<AllowUse> = Vec::new();
        let mut dirty = false;

        if matches!(meta.scan, ScanKind::File | ScanKind::Both) {
            let files = cx.files();
            timing.files = files.len();
            let results: Vec<(Sink, bool)> = files
                .par_iter()
                .map(|f| {
                    if lc.clean.contains(&f.fkey) {
                        return (Sink::new(), false);
                    }
                    if let Some(s) = lc.per_file.get(&f.fkey) {
                        return (s.clone(), false);
                    }
                    let mut sink = Sink::new();
                    sink.cur = f.rel.clone();
                    lint.scan_file(&cx, f, &mut sink);
                    (sink, true)
                })
                .collect();
            let mut per_file = HashMap::new();
            let mut clean = HashSet::new();
            for (f, (sink, fresh)) in files.iter().zip(results) {
                if fresh {
                    timing.rescanned += 1;
                    dirty = true;
                }
                sites.extend(sink.sites.iter().cloned());
                notes.extend(sink.notes.iter().cloned());
                allow_used.extend(sink.allow_used.iter().cloned());
                if sink.sites.is_empty() && sink.allow_used.is_empty() && sink.notes.is_empty() {
                    clean.insert(f.fkey);
                } else {
                    per_file.insert(f.fkey, sink);
                }
            }
            if per_file.len() != lc.per_file.len() || clean.len() != lc.clean.len() {
                dirty = true;
            }
            lc.per_file = per_file;
            lc.clean = clean;
        }

        if matches!(meta.scan, ScanKind::Tree | ScanKind::Both) {
            let files = cx.all_files();
            let mut h = blake3::Hasher::new();
            h.update(meta.name.as_bytes());
            for f in &files {
                h.update(&f.fkey.to_le_bytes());
            }
            for rel in lint.extra_inputs(&self.tree) {
                h.update(rel.as_bytes());
                match std::fs::read(self.tree.root.join(&rel)) {
                    Ok(bytes) => {
                        h.update(blake3::hash(&bytes).as_bytes());
                    }
                    Err(_) => {
                        h.update(b"\0missing");
                    }
                }
            }
            let key = u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap());
            let sink = match &lc.tree {
                Some((k, s)) if *k == key => {
                    timing.tree_memo_hit = true;
                    s.clone()
                }
                _ => {
                    let mut sink = Sink::new();
                    // Never from a rayon worker: the prewarm's own par_iter can steal a lint job that
                    // re-enters this call and waits on the cell this thread is initializing. run_all
                    // prewarms from the main thread (`prepare`) before it fans out.
                    if rayon::current_thread_index().is_none() && self.tree.fresh_count() > 64 {
                        self.tree.prewarm();
                    }
                    lint.scan_tree(&cx, &mut sink);
                    lc.tree = Some((key, sink.clone()));
                    dirty = true;
                    sink
                }
            };
            sites.extend(sink.sites);
            notes.extend(sink.notes);
            allow_used.extend(sink.allow_used);
        }

        if dirty {
            lc.dirty = true;
            self.cache.save_lint(meta.name, &lc);
        }
        timing.total = t0.elapsed();
        (Run { sites, notes }, allow_used, timing)
    }

    /// Applies the lint's ratchet policy to a scan and returns (failed, report text).
    pub fn judge(&self, lint: &dyn Lint, run: &Run) -> (bool, String) {
        self.judge_with(lint, run, self.opts.raw)
    }

    /// `judge` with an explicit raw switch (`raw`: ignore baselines, every site is new).
    pub fn judge_with(&self, lint: &dyn Lint, run: &Run, raw: bool) -> (bool, String) {
        let meta = lint.meta();
        let scope = self.scopes.for_lint(meta.name, meta.group);
        let cx = Cx { tree: &self.tree, meta, scope: &scope };
        let mut text = String::new();
        for n in &run.notes {
            let _ = writeln!(text, "{}", n);
        }
        // `--changed-only`: judge only the sites in files that changed.
        let filtered: Run;
        let run = match &self.changed {
            Some(changed) => {
                filtered = Run { sites: run.sites.iter().filter(|s| changed.contains(&s.rel)).cloned().collect(), notes: run.notes.clone() };
                &filtered
            }
            None => run,
        };
        let mut by_rule = run.by_rule(meta);
        let hints = |rule: &str| meta.rule(rule).map(|r| r.hint.to_string()).unwrap_or_default();
        // Rules with a configured ceiling (`[lint.<name>.ceilings]`) are judged by their count.
        let mut ceiling_failed = false;
        if !raw && matches!(meta.policy, Policy::Sites { .. } | Policy::Hard) && !scope.ceilings.is_empty() {
            let (with, without): (Vec<_>, Vec<_>) = by_rule.into_iter().partition(|(r, _)| scope.ceilings.contains_key(*r));
            by_rule = without;
            for (rule, found) in &with {
                let ceiling = scope.ceilings[*rule];
                let count = found.len() as i64;
                let status = if count > ceiling {
                    ceiling_failed = true;
                    format!("FAIL (rose above its ceiling {})", ceiling)
                } else if count < ceiling {
                    format!("below ceiling {}: lower it with `analyze baseline --update`", ceiling)
                } else {
                    "ok".to_string()
                };
                let _ = writeln!(text, "{} {:<19} {:>6}  (ceiling {})  {}", meta.label, rule, count, ceiling, status);
                if count > ceiling {
                    let hint = hints(rule);
                    let suffix = if hint.is_empty() { String::new() } else { format!(" -- {}", hint) };
                    for s in found.iter().take(60) {
                        let body = if s.msg.is_empty() { self.tree.site_text(&s.rel, s.line as usize) } else { s.msg.clone() };
                        let _ = writeln!(text, "{}:{}: [{}/{}] {}{}", s.rel, s.line, meta.label, rule, body, suffix);
                    }
                    if found.len() > 60 {
                        let _ = writeln!(text, "... and {} more", found.len() - 60);
                    }
                }
            }
        }
        let failed = ceiling_failed | match meta.policy {
            Policy::Sites { baseline, banned, .. } => {
                let path = if raw { PathBuf::from("") } else { self.baseline_path(baseline) };
                baseline::check_sites(meta.label, &self.tree, &by_rule, &hints, &path, banned, &mut text)
            }
            Policy::Ceilings { baseline, .. } => {
                let path = if raw { PathBuf::from("") } else { self.baseline_path(baseline) };
                let rules: Vec<&str> = meta.rules.iter().map(|r| r.name).collect();
                baseline::check_ceilings(meta.label, &run.sites, &rules, &path, &mut text)
            }
            Policy::Hard => {
                let mut failed = false;
                for (rule, found) in &by_rule {
                    let _ = writeln!(text, "{}: {} {} {}", meta.label, rule, found.len(), if found.is_empty() { "OK" } else { "FAIL" });
                    let hint = hints(rule);
                    for s in found {
                        failed = true;
                        let body = if s.msg.is_empty() { self.tree.site_text(&s.rel, s.line as usize) } else { s.msg.clone() };
                        let suffix = if hint.is_empty() { String::new() } else { format!(" -- {}", hint) };
                        let _ = writeln!(text, "{}:{}: [{}/{}] {}{}", s.rel, s.line, meta.label, rule, body, suffix);
                    }
                }
                failed
            }
            Policy::Custom => lint.finish_raw(&cx, run, &mut text, raw),
        };
        let failed = if matches!(meta.policy, Policy::Custom) { failed } else { lint.post_judge(&cx, run, &mut text) | failed };
        (failed, text)
    }

    pub fn run_one(&self, lint: &dyn Lint) -> Outcome {
        let name = lint.meta().name.to_string();
        let t_start = Instant::now();
        let out = self.run_one_inner(lint, name);
        if std::env::var("DQ_ANALYZE_TRACE_SPANS").is_ok() {
            let t0 = *SPAN_ORIGIN.get_or_init(Instant::now);
            eprintln!("span {:>7.0}..{:>7.0} ms  {}", t_start.saturating_duration_since(t0).as_secs_f64() * 1000.0, t0.elapsed().as_secs_f64() * 1000.0, out.name);
        }
        out
    }

    fn run_one_inner(&self, lint: &dyn Lint, name: String) -> Outcome {
        let res = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let (run, allow_used, timing) = self.scan(lint);
            let (failed, text) = self.judge(lint, &run);
            (run, allow_used, timing, failed, text)
        }));
        match res {
            Ok((run, allow_used, timing, failed, text)) => {
                Outcome { name, failed, text, run, allow_used, timing, internal_error: None }
            }
            Err(e) => {
                let msg = e
                    .downcast_ref::<String>()
                    .cloned()
                    .or_else(|| e.downcast_ref::<&str>().map(|s| s.to_string()))
                    .unwrap_or_else(|| "panic".to_string());
                Outcome {
                    name: name.clone(),
                    failed: true,
                    text: format!("{}: INTERNAL ERROR in the engine port: {}\n", name, msg),
                    run: Run::default(),
                    allow_used: Vec::new(),
                    timing: Timing::default(),
                    internal_error: Some(msg),
                }
            }
        }
    }

    /// Runs every selected lint in parallel; outcomes come back in registry order.
    pub fn run_all(&self) -> Vec<Outcome> {
        let chosen = selected(&self.reg, &self.opts.lints);
        self.prepare(&chosen);
        let _ = SPAN_ORIGIN.get_or_init(Instant::now);
        // Longest first: with ~50 lints on 16 cores the slowest whole-tree lints are the critical
        // path, so start them before the quick ones (durations remembered from the last real run).
        let durations = self.cache.load_durations();
        let mut order: Vec<(usize, &dyn Lint)> = chosen.iter().copied().enumerate().collect();
        order.sort_by_key(|(_, l)| std::cmp::Reverse(durations.get(l.meta().name).copied().unwrap_or(u64::MAX)));
        let mut outcomes: Vec<(usize, Outcome)> = order.par_iter().map(|(i, l)| (*i, self.run_one(*l))).collect();
        outcomes.sort_by_key(|(i, _)| *i);
        let outcomes: Vec<Outcome> = outcomes.into_iter().map(|(_, o)| o).collect();
        // Remember how long each lint took when it actually scanned (a memo hit says nothing).
        let mut merged = durations;
        for o in &outcomes {
            if o.timing.rescanned > 0 || (!o.timing.tree_memo_hit && o.timing.total.as_millis() > 20) {
                merged.insert(o.name.clone(), o.timing.total.as_micros() as u64);
            }
        }
        self.cache.save_durations(&merged);
        if let Some(dir) = crate::incr::dir() {
            self.tree.save_line_cache(&dir.join("linetext.bin"), self.cache.stamp());
        }
        if std::env::var("DQ_ANALYZE_TRACE").is_ok() {
            eprintln!("analyze: lint cache loads {:.1}ms (summed over threads)", LOAD_NS.load(std::sync::atomic::Ordering::Relaxed) as f64 / 1e6);
        }
        outcomes
    }

    /// On the main thread, before the parallel run: when many files are new or changed (a cold run,
    /// a branch switch), load every file once in parallel so the sequential lints don't each wait on
    /// a single thread reading and stripping the tree. After a small edit nothing is read up front:
    /// the per-file caches answer for every unchanged file, and a lint that does need a file loads it.
    pub fn prepare(&self, lints: &[&dyn Lint]) {
        let wants_tree = lints.iter().any(|l| matches!(l.meta().scan, ScanKind::Tree | ScanKind::Both));
        if wants_tree && self.tree.fresh_count() > 64 {
            self.tree.prewarm();
        }
    }

    /// `baseline --update|--seed` for one lint. Returns a one-line report.
    pub fn update_baseline(&self, lint: &dyn Lint, mode: Mode) -> std::io::Result<String> {
        let meta = lint.meta();
        let (run, _, _) = self.scan(lint);
        let scope = self.scopes.for_lint(meta.name, meta.group);
        let cx = Cx { tree: &self.tree, meta, scope: &scope };
        let by_rule = run.by_rule(meta);
        // Per-rule ceilings live in lint_scopes.toml: lower them (--update) or set them (--seed).
        let mut ceiling_note = String::new();
        if matches!(meta.policy, Policy::Sites { .. } | Policy::Hard) {
            let scopes_root = self.opts.scopes_from.clone().unwrap_or_else(|| self.opts.root.clone());
            let scopes_path = scopes_root.join("tools").join("ci").join("lint_scopes.toml");
            for (rule, found) in &by_rule {
                let Some(&ceiling) = scope.ceilings.get(*rule) else { continue };
                let count = found.len() as i64;
                let new = match mode {
                    Mode::Update => ceiling.min(count),
                    Mode::Seed => count,
                };
                if new != ceiling {
                    crate::scopes::write_ceiling(&scopes_path, meta.name, rule, new)?;
                    ceiling_note.push_str(&format!(" ceiling {} {} -> {};", rule, ceiling, new));
                }
            }
        }
        let by_rule_for_baseline: Vec<(&str, Vec<&crate::lint::Site>)> =
            by_rule.iter().filter(|(r, _)| !scope.ceilings.contains_key(*r)).map(|(r, s)| (*r, s.clone())).collect();
        let by_rule = if matches!(meta.policy, Policy::Sites { .. }) { by_rule_for_baseline } else { by_rule };
        match meta.policy {
            Policy::Sites { baseline, header, banned } => {
                let rules: Vec<&str> = meta
                    .rules
                    .iter()
                    .map(|r| r.name)
                    .filter(|r| !banned.contains(r) && !scope.ceilings.contains_key(*r))
                    .collect();
                let n = baseline::write_sites(&self.baseline_path(baseline), header, &self.tree, &by_rule, &rules, mode)?;
                let counts: Vec<String> = by_rule.iter().map(|(r, s)| format!("{} {}", r, s.len())).collect();
                Ok(format!("{}: baseline {} ({} rows; {});{}", meta.name, baseline, n, counts.join(", "), ceiling_note))
            }
            Policy::Ceilings { baseline, header } => {
                let path = self.baseline_path(baseline);
                let n = match mode {
                    Mode::Update => baseline::update_ceilings(&path, header, &run.sites)?,
                    Mode::Seed => {
                        let counts = baseline::key_counts(&run.sites);
                        baseline::write_ceilings(&path, header, &counts)?;
                        counts.len()
                    }
                };
                Ok(format!("{}: baseline {} ({} entries)", meta.name, baseline, n))
            }
            Policy::Hard => Ok(format!("{}: no baseline (hard ban);{}", meta.name, ceiling_note)),
            Policy::Custom => lint.update_baseline(&cx, &run, mode),
        }
    }
}

/// Files changed relative to the base branch, plus the working tree (`--changed-only`).
pub fn changed_files(root: &Path) -> HashSet<String> {
    let mut out = HashSet::new();
    let git = |args: &[&str]| -> Vec<String> {
        std::process::Command::new("git")
            .args(args)
            .current_dir(root)
            .output()
            .ok()
            .filter(|o| o.status.success())
            .map(|o| String::from_utf8_lossy(&o.stdout).lines().map(|l| l.to_string()).collect())
            .unwrap_or_default()
    };
    let base = git(&["merge-base", "HEAD", "origin/master"]).into_iter().next().unwrap_or_else(|| "HEAD".to_string());
    for l in git(&["diff", "--name-only", &base]) {
        out.insert(l.replace('\\', "/"));
    }
    for l in git(&["status", "--porcelain"]) {
        if l.len() > 3 {
            let path = l[3..].rsplit(" -> ").next().unwrap_or("").trim_matches('"');
            out.insert(path.replace('\\', "/"));
        }
    }
    out
}

/// Prints outcomes the way `check_ratchets.sh` did. Returns the names of failed lints.
pub fn render(outcomes: &[Outcome], ci: bool) -> (String, Vec<String>) {
    let mut s = String::new();
    let mut failed = Vec::new();
    for o in outcomes {
        if ci {
            let _ = writeln!(s, "::group::{}", o.name);
        }
        s.push_str(&o.text);
        if ci {
            let _ = writeln!(s, "::endgroup::");
        }
        if o.failed {
            failed.push(o.name.clone());
        }
    }
    (s, failed)
}

pub fn meta_of<'a>(reg: &'a Registry, name: &str) -> Option<&'a Meta> {
    reg.find(name).map(|l| l.meta())
}
