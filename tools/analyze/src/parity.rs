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
    /// `file:line: [rule] text` (the old output tagged only with the rule, no `label/`): compared on
    /// rule, file and line. The engine's own `[label/rule]` lines are read as `Tagged`.
    Bracketed,
    /// `file:line: rule` (a `--report` listing): compared on rule, file and line.
    Report,
    /// `file:line` alone on a line (a bare site listing): compared on file and line.
    Bare,
    /// `  file:line text` (an indented listing with no colon after the line): compared on file and line.
    Indented,
    /// `  file.dm:line: text`, `file.dm:line text` or `file.dm:line` (indented or colon-less output,
    /// paths with spaces): compared on file and line.
    FileLineAny,
    /// `B1  file.dm:line: text`, `B6  file.dm:line emits X` or `B5  free text` (a `--report` listing
    /// whose lines start with the rule name): rule, file and line; a line with no file is compared
    /// by its text (the file field), line 0.
    RulePrefixed,
    /// `check_grep.sh`: ANSI-coloured `NN- title` part headers, hits as `file:line:text` (or
    /// `file:text` when the old rule printed no line numbers), a few counted ratchets. Findings are
    /// attributed to the part's slug; see [`parse_check_grep`].
    CheckGrep,
}

/// The rule name a part title maps to: lowercase, every run of non-alphanumerics one `_`.
pub fn slug(title: &str) -> String {
    let mut out = String::new();
    for c in title.chars() {
        if c.is_ascii_alphanumeric() {
            out.push(c.to_ascii_lowercase());
        } else if !out.ends_with('_') {
            out.push('_');
        }
    }
    out.trim_matches('_').to_string()
}

/// A rule with extra checks inside one part is `<slug>__<what>`: the part is the base.
pub fn base_rule(rule: &str) -> &str {
    rule.split("__").next().unwrap_or(rule)
}

/// Stand-in file of a finding that is a count (a ratchet that printed only its number).
pub const COUNT_PATH: &str = "(count)";
/// Stand-in file of a `*.dme` finding (the old output omits the file name for a single file).
pub const DME_PATH: &str = "(dme)";
/// Stand-in file of a `grep -R` finding over a single file operand (printed without the name).
pub const SINGLE_FILE_PATH: &str = "(file)";

fn strip_ansi(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\u{1b}' && chars.peek() == Some(&'[') {
            chars.next();
            while let Some(&n) = chars.peek() {
                chars.next();
                if n.is_ascii_alphabetic() {
                    break;
                }
            }
        } else {
            out.push(c);
        }
    }
    out
}

/// Reads the legacy `check_grep.sh` output (or the engine's text for the same lint).
///
/// Old output: hits are attributed to the slug of the `NN- title` header above them; a repeated
/// title (the script lists some checks twice) is skipped. Lines without a line number (`grep -P`
/// without `-n`) become line 0, which `compare` treats as "any line of that file". A ratchet that
/// printed its count instead of its sites becomes one `(count)` finding whose line is the count.
/// Engine output: `file:line: [check_grep/rule]` lines, and ceiling status lines for the counts.
pub fn parse_check_grep(text: &str) -> Vec<Finding> {
    let header = Pat::new(r"^\s*\d\d- (.+?)\s*$");
    let lineful = Pat::new(r"^((?:code|maps|tgui|html|config)/[^:]*?\.[A-Za-z]+|[^/:]+\.dme):(\d+):");
    let lineless = Pat::new(r"^((?:code|maps)/[^:]*?\.dmm?|[^/:]+\.dme):");
    let tagged = Pat::new(r"^(.+?):(\d+): \[check_grep/(\w+)\]");
    let ceiling = Pat::new(r"^check_grep (\S+)\s+(\d+)\s+\(ceiling \d+\)\s+(\S+)");
    let dme_bare = Pat::new(r"maps\\.*test");
    let bare_numbered = Pat::new(r"^(\d+):");
    let html_file = Pat::new(r"^(code[\\/].*\.dm)$");
    let html_line = Pat::new(r"^\t\tLine (\d+)$");
    let counts = [
        Pat::new(r"^ERROR: (\d+) check_rights\( calls"),
        Pat::new(r"^ERROR: (\d+) raw \.holder reads"),
        Pat::new(r"^ERROR: (\d+) 'rights & R_' tests"),
        Pat::new(r"^ERROR: (\d+) fire_act\(\) overrides"),
        Pat::new(r"^ERROR: (\d+) non-turf ex_act\(\) overrides"),
        Pat::new(r"^ERROR: (\d+) atom_break\(\)/set_broken\(\) overrides"),
    ];
    let expecting = Pat::new(r"^(\d+) (?:escapes|New|raw slot_flags reads) \(expecting (\d+) or less\)");
    let mut out: Vec<Finding> = Vec::new();
    let mut seen = std::collections::BTreeSet::new();
    let mut cur = String::new();
    let mut skip = false;
    let mut ceiling_skip = String::new();
    let mut html_cur = String::new();
    for raw in text.lines() {
        let clean = strip_ansi(raw);
        // `rg` over a directory prints native separators (`code\modules\x.dm:12:`) on Windows.
        let unslashed;
        let mut l = clean.trim_start_matches('\0').trim_end();
        if let Some(i) = l.find(':') {
            if l[..i].contains('\\') && (l.starts_with("code") || l.starts_with("maps") || l.starts_with("tgui")) {
                unslashed = format!("{}{}", l[..i].replace('\\', "/"), &l[i..]);
                l = &unslashed;
            }
        }
        let mk = |rule: &str, rel: &str, line: u32| Finding { rule: rule.to_string(), rel: rel.replace('\\', "/"), line };
        if let Some(c) = header.captures(l) {
            cur = slug(c.s(1));
            skip = !seen.insert(cur.clone());
            continue;
        }
        if let Some(c) = tagged.captures(l) {
            let rule = base_rule(c.s(3)).to_string();
            if c.s(3) == ceiling_skip {
                continue;
            }
            let rel = if rule == "test_map_included" { DME_PATH } else { c.s(1) };
            out.push(mk(&rule, rel, c.s(2).parse().unwrap_or(0)));
            continue;
        }
        if let Some(c) = ceiling.captures(l) {
            let rule = base_rule(c.s(1)).to_string();
            if c.s(3) == "FAIL" {
                out.push(mk(&rule, COUNT_PATH, c.s(2).parse().unwrap_or(0)));
                ceiling_skip = c.s(1).to_string();
            } else {
                ceiling_skip.clear();
            }
            continue;
        }
        if cur.is_empty() {
            continue;
        }
        for p in &counts {
            if let Some(c) = p.captures(l) {
                out.push(mk(&cur, COUNT_PATH, c.s(1).parse().unwrap_or(0)));
            }
        }
        if let Some(c) = expecting.captures(l) {
            let (n, max): (u32, u32) = (c.s(1).parse().unwrap_or(0), c.s(2).parse().unwrap_or(0));
            if n > max {
                out.push(mk(&cur, COUNT_PATH, n));
            }
            continue;
        }
        if skip {
            continue;
        }
        match cur.as_str() {
            "html_tag_matching" => {
                if let Some(c) = html_file.captures(l) {
                    html_cur = c.s(1).replace('\\', "/");
                } else if let Some(c) = html_line.captures(l) {
                    out.push(mk(&cur, &html_cur, c.s(1).parse().unwrap_or(0)));
                }
                continue;
            }
            "typescript_react_files" => {
                if l.starts_with("tgui/") && l.ends_with(".jsx") {
                    out.push(mk(&cur, l, 0));
                }
                continue;
            }
            "changelog" => {
                if let Some(rel) = l.strip_suffix(": FAILED") {
                    out.push(mk(&cur, rel, 0));
                }
                continue;
            }
            "blocking_shell_toast_enabled_in_example_config" => {
                if l.starts_with("config/example/config.txt enables") {
                    out.push(mk(&cur, "config/example/config.txt", 0));
                }
                continue;
            }
            "test_map_included" => {
                if dme_bare.is_match(l) {
                    out.push(mk(&cur, DME_PATH, 0));
                }
                continue;
            }
            // `grep -R` over one file operand prints `12:text`, without the file name.
            "separate_object_health_pools" => {
                if let Some(c) = bare_numbered.captures(l) {
                    out.push(mk(&cur, SINGLE_FILE_PATH, c.s(1).parse().unwrap_or(0)));
                    continue;
                }
            }
            "tgm" => {
                if l.starts_with("maps/") && l.ends_with(".dmm") && !l.contains(':') {
                    out.push(mk(&cur, l, 0));
                }
                continue;
            }
            _ => {}
        }
        if let Some(c) = lineful.captures(l) {
            out.push(mk(&cur, c.s(1), c.s(2).parse().unwrap_or(0)));
        } else if let Some(c) = lineless.captures(l) {
            out.push(mk(&cur, c.s(1), 0));
        }
    }
    // The script lists some checks twice; a site with a line number counts once.
    out.sort();
    out.dedup_by(|a, b| a.line > 0 && a == b);
    out
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
    let tagged = Pat::new(r"^([^:]+?):(\d+): \[([\w/.\-]+)/(\w+)\]");
    if matches!(kind, ParseKind::CheckGrep) {
        return parse_check_grep(text);
    }
    let tagged = Pat::new(r"^([^\s:]+):(\d+): \[([\w/.\-]+)/(\w+)\]");
    let plain = Pat::new(r"^([^\s:]+\.[A-Za-z]+):(\d+):");
    let report = Pat::new(r"^([^:]+?):(\d+): (\w+)\s*$");
    let bracketed = Pat::new(r"^([^\s:]+):(\d+): \[(\w+)\]");
    let bare =Pat::new(r"^\s*([^\s:]+\.[A-Za-z]+):(\d+)\s*$");
    let indented = Pat::new(r"^\s+([^\s:]+\.[A-Za-z]+):(\d+)(?:\s|$)");
    // A path may contain spaces ("id cards"), so the file part is anything up to `:line: [`.
    // Like `plain`, for output indented or without a colon after the line, and paths with spaces.
    let any = Pat::new(r"^\s*([^\s:][^:]*?\.[A-Za-z]+):(\d+)(?::|\s|$)");
    let prefixed = Pat::new(r"^(\w+)  (.*)$");
    let prefixed_site = Pat::new(r"^(.+?\.dm):(\d+)(?::|\s+emits)");
    let mut out = Vec::new();
    for l in text.lines() {
        let l = l.trim_end();
        let mk = |rule: &str, rel: &str, line: &str| Finding { rule: rule.to_string(), rel: rel.replace('\\', "/"), line: line.parse().unwrap_or(0) };
        if let Some(c) = tagged.captures(l) {
            out.push(mk(c.s(4), c.s(1), c.s(2)));
            continue;
        }
        match kind {
            ParseKind::Tagged | ParseKind::CheckGrep => {}
            ParseKind::FileLine => {
                if let Some(c) = plain.captures(l) {
                    out.push(mk("", c.s(1), c.s(2)));
                }
            }
            ParseKind::Bracketed => {
                if let Some(c) = bracketed.captures(l) {
                    out.push(mk(c.s(3), c.s(1), c.s(2)));
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
            ParseKind::Indented => {
                if let Some(c) = indented.captures(l) {
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

/// A legacy shell script (`check_grep.sh`). It runs under bash from the repo root, as a copy
/// without `errexit` (the script aborts at its first hit otherwise, hiding every later check), with a
/// UTF-8 locale (`grep -P` needs one). `DQ_BASH` names the bash to use (on Windows the first `bash`
/// that `Command` finds can be the WSL launcher).
fn run_old_sh(root: &Path, args: &[&str]) -> Output {
    let src = std::fs::read_to_string(root.join(args[0])).unwrap_or_default();
    let patched = src.replace("set -euo pipefail", "set -uo pipefail");
    let name = Path::new(args[0]).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let tmp = std::env::temp_dir().join(format!("dq-analyze-old-{}-{}", std::process::id(), name));
    let _ = std::fs::write(&tmp, patched);
    let bash = std::env::var("DQ_BASH").unwrap_or_else(|_| "bash".to_string());
    let out = Command::new(bash)
        .arg(tmp.to_string_lossy().replace('\\', "/"))
        .args(&args[1..])
        .current_dir(root)
        .env("LC_ALL", "C.UTF-8")
        .env("PYTHONIOENCODING", "utf-8")
        .env("PYTHONUTF8", "1")
        .output()
        .unwrap_or_else(|e| panic!("cannot run bash: {}", e));
    let _ = std::fs::remove_file(&tmp);
    let mut text = String::from_utf8_lossy(&out.stdout).into_owned();
    text.push_str(&String::from_utf8_lossy(&out.stderr));
    Output { code: out.status.code().unwrap_or(-1), text }
}

fn run_old(root: &Path, args: &[&str]) -> Output {
    if args.first().map(|a| a.ends_with(".sh")).unwrap_or(false) {
        return run_old_sh(root, args);
    }
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
    // An old finding with line 0 had no line number (`grep` without `-n`): it stands for "a hit in
    // that file", so the engine's findings for the same (rule, file) compare without their lines.
    let wild: std::collections::BTreeSet<(&str, &str)> = old.iter().filter(|f| f.line == 0).map(|f| (f.rule.as_str(), f.rel.as_str())).collect();
    let unwilded: Vec<Finding>;
    let new = if wild.is_empty() {
        new
    } else {
        unwilded = new
            .iter()
            .map(|f| if wild.contains(&(f.rule.as_str(), f.rel.as_str())) { Finding { line: 0, ..f.clone() } } else { f.clone() })
            .collect();
        &unwilded[..]
    };
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
    let meta = lint.meta();
    let scope = engine.scopes.for_lint(meta.name, meta.group);
    let mut v = lint.parity_normalize(&engine.opts.root, &scope, v);
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
        if real_root.join("tools").join("TagMatcher").exists() {
            copy_dir(&real_root.join("tools").join("TagMatcher"), &tmp.join("tools").join("TagMatcher"), &|p| p.file_name().map(|n| n == "__pycache__").unwrap_or(false))?;
        }
        if !tmp.join("deepquarry.dme").exists() {
            std::fs::write(tmp.join("deepquarry.dme"), "")?;
        }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slug_collapses_punctuation() {
        assert_eq!(slug("step_[xy]"), "step_xy");
        assert_eq!(slug(".proc ref syntax"), slug("proc ref syntax"));
        assert_eq!(slug("one revive path: return_from_death()"), "one_revive_path_return_from_death");
        assert_eq!(base_rule("a_b__2"), "a_b");
    }

    #[test]
    fn check_grep_output_is_read_per_part() {
        let old = "\u{1b}[0;32m 01- step_[xy]\u{1b}[0m\nmaps/a.dmm:12:step_x = 1\nmaps/a.dmm:12:step_x = 1\n\u{1b}[0;32m 02- ambiguous bitwise or\u{1b}[0m\ncode/a.dm:\tif(a & B | C)\n\u{1b}[0;32m 03- ambiguous bitwise or\u{1b}[0m\ncode/a.dm:\tif(a & B | C)\n\u{1b}[0;32m 04- changelog\u{1b}[0m\nhtml/changelogs/example.yml: FAILED\n\u{1b}[0;32m 05- color macros\u{1b}[0m\n3 escapes (expecting 1 or less)\n\u{1b}[0;32m 06- tools: act\u{1b}[0m\ncode\\x\\y.dm:7:text\n";
        let got = parse_check_grep(old);
        let f = |r: &str, rel: &str, line: u32| Finding { rule: r.into(), rel: rel.into(), line };
        let mut want = vec![
            f("step_xy", "maps/a.dmm", 12),
            f("ambiguous_bitwise_or", "code/a.dm", 0),
            f("changelog", "html/changelogs/example.yml", 0),
            f("color_macros", COUNT_PATH, 3),
            f("tools_act", "code/x/y.dm", 7),
        ];
        want.sort();
        assert_eq!(got, want);
        let new = "check_grep heat_ratchet__x      9  (ceiling 6)  FAIL (rose above its ceiling 6)\ncode/a.dm:1: [check_grep/heat_ratchet__x] t -- h\ncode/b.dm:2: [check_grep/other] t -- h\n";
        assert_eq!(parse_check_grep(new), vec![f("heat_ratchet", COUNT_PATH, 9), f("other", "code/b.dm", 2)]);
    }
}
