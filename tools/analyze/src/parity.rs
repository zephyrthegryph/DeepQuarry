//! The parity harness: runs a legacy Python lint and its engine port on the same input and diffs
//! the findings. A lint is switched over only when every comparison here is empty.
//!
//! Comparisons (each is skipped when the lint's [`Parity`] spec has no such mode):
//!   * **default**: the old script's CI run versus `analyze check --lint x`: exit status, and the
//!     sites each reports as new (parsed from the printed `file:line:` lines).
//!   * **raw**: every site the lint finds with its baseline ignored (the old script run with its
//!     baseline files blanked, or its `--report`; the engine with `--raw`). Legacy ratchets hold
//!     hundreds of baselined sites, so this is the comparison that actually exercises a port.
//!   * **fixtures**: the same raw comparison on `tools/analyze/fixtures/<lint>/`, a small tree of
//!     positive/negative/edge-case files per lint. A lint with no sites in the real tree (a hard
//!     ban at zero) proves nothing on the real tree; the fixtures are what prove it. `--bless`
//!     writes the old script's findings to `expected.txt`, which `cargo test` then holds the engine
//!     to after the Python is gone.
//!   * **update**: the baseline file after the old `--update` versus after `analyze baseline
//!     --update`, byte for byte (and the same for `--seed`).
//!   * **selftest**: the old `--selftest` and the engine's fixtures both pass.
//!
//! The harness backs up and restores every baseline file it touches.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::baseline::Mode;
use crate::lint::{Lint, Policy};
use crate::pat::Pat;
use crate::run::{Engine, Options};

#[derive(Clone, Copy, Debug)]
pub enum ParseKind {
    /// `file:line: [label/rule] text`: compared on rule, file and line.
    Tagged,
    /// `file:line: anything`: compared on file and line.
    FileLine,
    /// `file:line: rule` (a `--report` listing): compared on rule, file and line.
    Report,
    /// `file:line` alone on a line (a bare site listing): compared on file and line.
    Bare,
    /// `  file.dm:line: text`, `file.dm:line text` or `file.dm:line` (indented or colon-less output,
    /// paths with spaces): compared on file and line.
    FileLineAny,
    /// `B1  file.dm:line: text`, `B6  file.dm:line emits X` or `B5  free text` (a `--report` listing
    /// whose lines start with the rule name): rule, file and line; a line with no file is compared
    /// by its text (the file field), line 0.
    RulePrefixed,
}

/// How to compare one lint with its legacy script. Paths are relative to the repo root.
#[derive(Clone, Copy, Debug)]
pub struct Parity {
    /// The old script and arguments for its CI run.
    pub old: &'static [&'static str],
    /// The old script's raw-sites invocations (each a `--report ...`), when it has ones that ignore
    /// baselines; their outputs are concatenated. Empty: use `blank` instead.
    pub old_raw: &'static [&'static [&'static str]],
    /// Baseline files to blank while running the old script raw (when it has no `--report`).
    pub blank: &'static [&'static str],
    pub parse: ParseKind,
    /// The old `--update` invocation.
    pub update: Option<&'static [&'static str]>,
    /// The old `--seed` invocation (written to the same files).
    pub seed: Option<&'static [&'static str]>,
    /// The baseline files `update`/`seed` rewrite.
    pub files: &'static [&'static str],
    /// The old `--selftest` invocation.
    pub selftest: Option<&'static [&'static str]>,
}

impl Parity {
    /// The common case: `python <script>` with ratchet output, blanking the given baselines for raw.
    pub const fn ratchet(script: &'static [&'static str], baselines: &'static [&'static str]) -> Parity {
        Parity {
            old: script,
            old_raw: &[],
            blank: baselines,
            parse: ParseKind::Tagged,
            update: None,
            seed: None,
            files: baselines,
            selftest: None,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Finding {
    pub rule: String,
    pub rel: String,
    pub line: u32,
}

pub fn parse_findings(text: &str, kind: ParseKind) -> Vec<Finding> {
    // A path may contain spaces ("id cards"), so the file part is anything up to `:line: [`.
    let tagged = Pat::new(r"^([^\s:][^:]*?):(\d+): \[([\w/.\-]+)/(\w+)\]");
    let plain = Pat::new(r"^([^\s:]+\.[A-Za-z]+):(\d+):");
    // Like `plain`, for output indented or without a colon after the line, and paths with spaces.
    let any = Pat::new(r"^\s*([^\s:][^:]*?\.[A-Za-z]+):(\d+)(?::|\s|$)");
    let report = Pat::new(r"^([^\s:]+):(\d+): (\w+)\s*$");
    let bare = Pat::new(r"^\s*([^\s:]+\.[A-Za-z]+):(\d+)\s*$");
    let prefixed = Pat::new(r"^(\w+)  (.*)$");
    let prefixed_site = Pat::new(r"^(.+?\.dm):(\d+)(?::|\s+emits)");
    let mut out = Vec::new();
    for l in text.lines() {
        let l = l.trim_end();
        let mk = |rule: &str, rel: &str, line: &str| Finding { rule: rule.to_string(), rel: rel.to_string(), line: line.parse().unwrap_or(0) };
        if let Some(c) = tagged.captures(l) {
            out.push(mk(c.s(4), c.s(1), c.s(2)));
            continue;
        }
        match kind {
            ParseKind::Tagged => {}
            ParseKind::FileLine => {
                if let Some(c) = plain.captures(l) {
                    out.push(mk("", c.s(1), c.s(2)));
                }
            }
            ParseKind::Report => {
                if let Some(c) = report.captures(l) {
                    out.push(mk(c.s(3), c.s(1), c.s(2)));
                }
            }
            ParseKind::RulePrefixed => {
                if let Some(c) = prefixed.captures(l) {
                    match prefixed_site.captures(c.s(2)) {
                        Some(p) => out.push(mk(c.s(1), p.s(1), p.s(2))),
                        None => out.push(Finding { rule: c.s(1).to_string(), rel: c.s(2).to_string(), line: 0 }),
                    }
                }
            }
            ParseKind::FileLineAny => {
                if let Some(c) = any.captures(l) {
                    out.push(mk("", c.s(1), c.s(2)));
                }
            }
            ParseKind::Bare => {
                if let Some(c) = bare.captures(l) {
                    out.push(mk("", c.s(1), c.s(2)));
                }
            }
        }
    }
    // A script run on Windows may print `os.path.relpath` unconverted (`code\modules\a.dm`).
    for f in &mut out {
        if f.rel.contains('\\') {
            f.rel = f.rel.replace('\\', "/");
        }
    }
    out.sort();
    out
}

fn python() -> String {
    if let Ok(p) = std::env::var("PYTHON") {
        return p;
    }
    for cand in ["python3", "python"] {
        if Command::new(cand).arg("--version").output().map(|o| o.status.success()).unwrap_or(false) {
            return cand.to_string();
        }
    }
    "python3".to_string()
}

struct Output {
    code: i32,
    text: String,
}

fn run_old(root: &Path, args: &[&str]) -> Output {
    let out = Command::new(python())
        .args(args)
        .current_dir(root)
        .env("PYTHONIOENCODING", "utf-8")
        .env("PYTHONUTF8", "1")
        .output()
        .unwrap_or_else(|e| panic!("cannot run python: {}", e));
    let mut text = String::from_utf8_lossy(&out.stdout).into_owned();
    text.push_str(&String::from_utf8_lossy(&out.stderr));
    Output { code: out.status.code().unwrap_or(-1), text }
}

/// Backs up files and restores them on drop.
struct Guard {
    saved: Vec<(PathBuf, Option<Vec<u8>>)>,
}

impl Guard {
    fn new(root: &Path, files: &[&str]) -> Guard {
        let saved = files
            .iter()
            .map(|f| {
                let p = root.join(f);
                let content = std::fs::read(&p).ok();
                (p, content)
            })
            .collect();
        Guard { saved }
    }

    fn blank(&self) {
        for (p, _) in &self.saved {
            if let Some(parent) = p.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            let _ = std::fs::write(p, "# blanked by analyze parity\n");
        }
    }

    fn restore(&self) {
        for (p, content) in &self.saved {
            match content {
                Some(c) => {
                    let _ = std::fs::write(p, c);
                }
                None => {
                    let _ = std::fs::remove_file(p);
                }
            }
        }
    }

    fn read_all(&self) -> Vec<Option<Vec<u8>>> {
        self.saved.iter().map(|(p, _)| std::fs::read(p).ok()).collect()
    }
}

impl Drop for Guard {
    fn drop(&mut self) {
        self.restore();
    }
}

pub struct Report {
    pub lint: String,
    pub checks: Vec<(String, bool, String)>,
}

impl Report {
    pub fn ok(&self) -> bool {
        self.checks.iter().all(|c| c.1)
    }
}

fn multiset_diff(a: &[Finding], b: &[Finding], limit: usize) -> Vec<String> {
    let mut counts: BTreeMap<&Finding, (i64, i64)> = BTreeMap::new();
    for f in a {
        counts.entry(f).or_default().0 += 1;
    }
    for f in b {
        counts.entry(f).or_default().1 += 1;
    }
    let mut out = Vec::new();
    for (f, (x, y)) in counts {
        if x != y {
            out.push(format!("  {}:{} [{}]  old x{}, engine x{}", f.rel, f.line, f.rule, x, y));
        }
    }
    let total = out.len();
    out.truncate(limit);
    if total > limit {
        out.push(format!("  ... and {} more", total - limit));
    }
    out
}

/// Compares findings, ignoring the rule when either side has none.
fn compare(old: &[Finding], new: &[Finding], what: &str) -> (bool, String) {
    let strip = old.iter().any(|f| f.rule.is_empty()) || new.iter().any(|f| f.rule.is_empty());
    let (a, b): (Vec<Finding>, Vec<Finding>) = if strip {
        let mut a: Vec<Finding> = old.iter().map(|f| Finding { rule: String::new(), ..f.clone() }).collect();
        let mut b: Vec<Finding> = new.iter().map(|f| Finding { rule: String::new(), ..f.clone() }).collect();
        a.sort();
        b.sort();
        (a, b)
    } else {
        (old.to_vec(), new.to_vec())
    };
    if a == b {
        return (true, format!("{}: {} findings identical", what, a.len()));
    }
    let d = multiset_diff(&a, &b, 40);
    (false, format!("{}: old {} findings, engine {}; differences:\n{}", what, a.len(), b.len(), d.join("\n")))
}

fn engine_output(engine: &Engine, lint: &dyn Lint, raw: bool) -> (i32, String) {
    let (run, _, _) = engine.scan(lint);
    let (failed, text) = engine.judge_with(lint, &run, raw);
    (if failed { 1 } else { 0 }, text)
}

/// Every raw site the engine finds for a lint.
pub fn engine_raw_findings(engine: &Engine, lint: &dyn Lint) -> Vec<Finding> {
    let (run, _, _) = engine.scan(lint);
    let mut v: Vec<Finding> = run.sites.iter().map(|s| Finding { rule: s.rule.clone(), rel: s.rel.clone(), line: s.line }).collect();
    v.sort();
    v
}

/// Every raw site the old script finds (baselines ignored), run in `root`.
pub fn old_raw_findings(root: &Path, spec: &Parity) -> Vec<Finding> {
    let text = if !spec.old_raw.is_empty() {
        spec.old_raw.iter().map(|args| run_old(root, args).text).collect::<Vec<_>>().join("\n")
    } else {
        let g = Guard::new(root, spec.blank);
        g.blank();
        let t = run_old(root, spec.old).text;
        g.restore();
        t
    };
    parse_findings(&text, spec.parse)
}

/// Runs every comparison for one lint against an already-built engine on the real tree.
pub fn check_lint(engine: &Engine, lint: &dyn Lint, spec: &Parity) -> Report {
    let root = &engine.opts.root;
    let meta = lint.meta();
    let mut report = Report { lint: meta.name.to_string(), checks: Vec::new() };

    // default
    {
        let old = run_old(root, spec.old);
        let (code, text) = engine_output(engine, lint, false);
        let (ok, msg) = compare(&parse_findings(&old.text, spec.parse), &parse_findings(&text, spec.parse), "default run");
        let code_ok = old.code == code;
        report.checks.push((
            "default".to_string(),
            ok && code_ok,
            format!("{}; exit old {} engine {}{}", msg, old.code, code, if code_ok { "" } else { "  <-- EXIT CODE DIFFERS" }),
        ));
    }

    // raw
    if !spec.old_raw.is_empty() || !spec.blank.is_empty() {
        let old = old_raw_findings(root, spec);
        let new = engine_raw_findings(engine, lint);
        let (ok, msg) = compare(&old, &new, "raw sites (baselines ignored)");
        report.checks.push(("raw".to_string(), ok, msg));
    }

    // update / seed
    for (label, args, mode) in [("update", spec.update, Mode::Update), ("seed", spec.seed, Mode::Seed)] {
        let Some(args) = args else { continue };
        if spec.files.is_empty() {
            continue;
        }
        let g = Guard::new(root, spec.files);
        run_old(root, args);
        let after_old = g.read_all();
        g.restore();
        let res = engine.update_baseline(lint, mode);
        let after_new = g.read_all();
        g.restore();
        let ok = res.is_ok() && after_old == after_new;
        let mut msg = format!("baseline {}: {}", label, if ok { "byte-identical" } else { "DIFFERS" });
        if !ok {
            if let Err(e) = res {
                msg.push_str(&format!(" (engine error: {})", e));
            }
            for (i, (a, b)) in after_old.iter().zip(after_new.iter()).enumerate() {
                if a != b {
                    let la = a.as_ref().map(|v| String::from_utf8_lossy(v).into_owned()).unwrap_or_default();
                    let lb = b.as_ref().map(|v| String::from_utf8_lossy(v).into_owned()).unwrap_or_default();
                    let sa: std::collections::BTreeSet<&str> = la.lines().collect();
                    let sb: std::collections::BTreeSet<&str> = lb.lines().collect();
                    msg.push_str(&format!("\n  file {}: old {} lines, engine {} lines", spec.files[i], la.lines().count(), lb.lines().count()));
                    for l in sa.difference(&sb).take(6) {
                        msg.push_str(&format!("\n    - old only: {}", l));
                    }
                    for l in sb.difference(&sa).take(6) {
                        msg.push_str(&format!("\n    + engine only: {}", l));
                    }
                }
            }
        }
        report.checks.push((label.to_string(), ok, msg));
    }

    // selftest
    if let Some(args) = spec.selftest {
        let old = run_old(root, args);
        let new = lint.selftest();
        let ok = old.code == 0 && new.is_ok();
        report.checks.push((
            "selftest".to_string(),
            ok,
            format!(
                "old exit {}, engine {}",
                old.code,
                match &new {
                    Ok(s) => format!("ok {}", s),
                    Err(e) => format!("FAILED: {}", e),
                }
            ),
        ));
    }
    report
}

// ---- fixtures ---------------------------------------------------------------------------------

/// `tools/analyze/fixtures/<lint>/` (a `/` in a lint name becomes `__`).
pub fn fixture_dir(root: &Path, lint_name: &str) -> PathBuf {
    root.join("tools").join("analyze").join("fixtures").join(lint_name.replace('/', "__"))
}

fn copy_dir(from: &Path, to: &Path, skip: &dyn Fn(&Path) -> bool) -> std::io::Result<()> {
    std::fs::create_dir_all(to)?;
    for entry in std::fs::read_dir(from)? {
        let entry = entry?;
        let p = entry.path();
        if skip(&p) {
            continue;
        }
        let dest = to.join(entry.file_name());
        if p.is_dir() {
            copy_dir(&p, &dest, skip)?;
        } else {
            std::fs::copy(&p, &dest)?;
        }
    }
    Ok(())
}

pub fn format_expected(findings: &[Finding]) -> String {
    let mut s = String::new();
    for f in findings {
        s.push_str(&format!("{}\t{}\t{}\n", f.rule, f.rel, f.line));
    }
    s
}

pub fn read_expected(path: &Path) -> Option<Vec<Finding>> {
    let text = std::fs::read_to_string(path).ok()?;
    let mut v: Vec<Finding> = text
        .lines()
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .filter_map(|l| {
            let mut p = l.splitn(3, '\t');
            Some(Finding { rule: p.next()?.to_string(), rel: p.next()?.to_string(), line: p.next()?.parse().ok()? })
        })
        .collect();
    v.sort();
    Some(v)
}

/// The engine's raw findings on a fixture tree rooted at `root` (no cache).
pub fn engine_on_fixture(root: &Path, scopes_from: Option<&Path>, lint_name: &str) -> Result<Vec<Finding>, String> {
    let opts = Options {
        root: root.to_path_buf(),
        lints: vec![lint_name.to_string()],
        no_cache: true,
        raw: true,
        scopes_from: scopes_from.map(|p| p.to_path_buf()),
        ..Default::default()
    };
    let engine = Engine::new(crate::run::registry(), opts)?;
    let lint = engine.reg.find(lint_name).ok_or_else(|| format!("no lint {}", lint_name))?;
    Ok(engine_raw_findings(&engine, lint))
}

/// The fixture comparison: stage the fixtures into a scratch repo (with a copy of `tools/ci` so the
/// old script resolves its ROOT there), run the old script and the engine, compare. With `bless`,
/// a clean comparison writes `expected.txt`.
pub fn check_fixtures(real_root: &Path, lint: &dyn Lint, spec: &Parity, bless: bool) -> Option<(bool, String)> {
    let name = lint.meta().name;
    let fdir = fixture_dir(real_root, name);
    if !fdir.exists() {
        return None;
    }
    let tmp = std::env::temp_dir().join(format!("dq-analyze-fix-{}-{}", name.replace('/', "_"), std::process::id()));
    let _ = std::fs::remove_dir_all(&tmp);
    let staged = (|| -> std::io::Result<()> {
        copy_dir(&fdir, &tmp, &|p| p.file_name().map(|n| n == "expected.txt").unwrap_or(false))?;
        copy_dir(&real_root.join("tools").join("ci"), &tmp.join("tools").join("ci"), &|p| {
            p.file_name().map(|n| n == "__pycache__").unwrap_or(false)
        })?;
        if real_root.join("tools").join("dx").exists() {
            copy_dir(&real_root.join("tools").join("dx"), &tmp.join("tools").join("dx"), &|p| p.file_name().map(|n| n == "__pycache__").unwrap_or(false))?;
        }
        std::fs::write(tmp.join("deepquarry.dme"), "")?;
        Ok(())
    })();
    if let Err(e) = staged {
        return Some((false, format!("fixtures: cannot stage: {}", e)));
    }
    let old = old_raw_findings(&tmp, spec);
    let new = match engine_on_fixture(&tmp, None, name) {
        Ok(v) => v,
        Err(e) => {
            let _ = std::fs::remove_dir_all(&tmp);
            return Some((false, format!("fixtures: engine error: {}", e)));
        }
    };
    let (ok, mut msg) = compare(&old, &new, "fixtures");
    if ok && bless {
        let _ = std::fs::write(fdir.join("expected.txt"), format_expected(&new));
        msg.push_str("; blessed expected.txt");
    }
    let _ = std::fs::remove_dir_all(&tmp);
    Some((ok, msg))
}

pub fn run(opts: &Options, names: &[String], bless: bool, no_real: bool) -> i32 {
    let reg = crate::run::registry();
    let mut o = opts.clone();
    o.lints = names.to_vec();
    let engine = match Engine::new(reg, o) {
        Ok(e) => e,
        Err(e) => {
            eprintln!("{}", e);
            return 2;
        }
    };
    let chosen = crate::run::selected(&engine.reg, &engine.opts.lints);
    let mut failed = 0;
    let mut skipped = Vec::new();
    for lint in chosen {
        let Some(spec) = lint.parity() else {
            skipped.push(lint.meta().name);
            continue;
        };
        let mut report = if no_real { Report { lint: lint.meta().name.to_string(), checks: Vec::new() } } else { check_lint(&engine, lint, &spec) };
        match check_fixtures(&engine.opts.root, lint, &spec, bless) {
            Some((ok, msg)) => report.checks.push(("fixtures".to_string(), ok, msg)),
            None => report.checks.push(("fixtures".to_string(), true, "no fixtures yet (tools/analyze/fixtures/<lint>/)".to_string())),
        }
        println!("== parity {}: {}", report.lint, if report.ok() { "PASS" } else { "FAIL" });
        for (name, ok, msg) in &report.checks {
            println!("  [{}] {}: {}", if *ok { "ok" } else { "DIFF" }, name, msg);
        }
        if !report.ok() {
            failed += 1;
        }
    }
    if !skipped.is_empty() {
        println!("no parity spec (not compared): {}", skipped.join(", "));
    }
    if failed > 0 {
        1
    } else {
        0
    }
}

/// Policy -> the baseline file a Sites/Ceilings lint rewrites.
pub fn baseline_file(lint: &dyn Lint) -> Option<&'static str> {
    match lint.meta().policy {
        Policy::Sites { baseline, .. } | Policy::Ceilings { baseline, .. } => Some(baseline),
        _ => None,
    }
}
