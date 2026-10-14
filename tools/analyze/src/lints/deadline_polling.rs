//! Port of `tools/ci/check_deadline_polling.py` (doc/rewrite/object_model_core.md sec 4.11, roadmap S3).
//!
//! A periodic body that compares `world.time` with a stored deadline is polling a timer; that
//! belongs in `om_after()`. The scan is shared with the sys rule `deadline_poll`
//! (`crate::dm::deadline`). A site that must stay carries `// ALLOW(sys_deadline_poll): <reason>`;
//! whole procs can still be listed in `tools/ci/deadline_polling_allowlist.txt` (`path:proc_path`
//! per line, a reason after `#`; a stale entry is an error, so the list only shrinks).
//!
//! Shape: every non-ALLOWed hit is a site keyed `path:proc_path`; `finish` reads the allowlist and
//! judges (the allowlist is a custom baseline format, so the policy is `Custom`). An allowlist entry
//! with no reason aborts the old script at once; `finish` does the same. The scan skips
//! `/unit_tests/` through `lint_scopes.toml`.

use std::collections::BTreeMap;
use std::fmt::Write as _;

use crate::baseline::Mode;
use crate::dm::deadline;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, Run, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::tree::{SourceFile, CODE_DM};
use crate::util::py_strip;

const ALLOWLIST: &str = "tools/ci/deadline_polling_allowlist.txt";
const HINT: &str = "Use om_after(src, deadline - world.time, PROC_REF(...)) instead (doc/rewrite/object_model_core.md sec 4.11), or allowlist with a reason.";

static META: Meta = Meta {
    name: "deadline_polling",
    group: "",
    label: "deadline_polling",
    legacy: "tools/ci/check_deadline_polling.py",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Custom,
    rules: &[RuleMeta { name: "deadline_poll", hint: HINT }],
    allow: &["sys_deadline_poll"],
    lists: &[],
};

struct DeadlinePolling;

/// `load_allowlist`: `{entry: line number}`, or the line that has no reason.
fn load_allowlist(path: &std::path::Path) -> Result<BTreeMap<String, usize>, (usize, String)> {
    let mut entries = BTreeMap::new();
    let Ok(text) = std::fs::read_to_string(path) else { return Ok(entries) };
    let text = crate::util::universal_newlines(text);
    // `for number, raw in enumerate(f, 1)`: the lines of a file (a final empty piece is not a line).
    let mut lines: Vec<&str> = text.split('\n').collect();
    if lines.last() == Some(&"") {
        lines.pop();
    }
    for (i, raw) in lines.iter().enumerate() {
        let line = py_strip(raw.split('#').next().unwrap_or(""));
        if line.is_empty() {
            continue;
        }
        if !raw.contains('#') {
            return Err((i + 1, line.to_string()));
        }
        entries.insert(line.to_string(), i + 1);
    }
    Ok(entries)
}

impl Lint for DeadlinePolling {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let lines = f.raw().lines_vec();
        for hit in deadline::scan_lines(&lines) {
            if out.allowed(f, hit.line, "sys_deadline_poll") {
                continue;
            }
            let key = format!("{}:{}", f.rel, hit.proc_path);
            out.site_keyed("deadline_poll", &f.rel, hit.line, format!("{} compares world.time with a stored deadline: {}", hit.proc_path, hit.text), key);
        }
    }

    fn finish(&self, cx: &Cx, run: &Run, text: &mut String) -> bool {
        let path = cx.tree.root.join(ALLOWLIST);
        let shown = path.to_string_lossy().to_string();
        let allow = match load_allowlist(&path) {
            Ok(a) => a,
            Err((number, line)) => {
                let _ = writeln!(text, "{}:{}: entry has no reason: {}", shown, number, line);
                return true;
            }
        };
        let mut findings: BTreeMap<&str, Vec<&crate::lint::Site>> = BTreeMap::new();
        for s in &run.sites {
            findings.entry(s.key.as_str()).or_default().push(s);
        }
        let mut bad: Vec<&crate::lint::Site> = Vec::new();
        for (key, hits) in &findings {
            if !allow.contains_key(*key) {
                bad.extend(hits.iter().copied());
            }
        }
        let stale: Vec<(&String, &usize)> = allow.iter().filter(|(k, _)| !findings.contains_key(k.as_str())).collect();
        for s in &bad {
            let _ = writeln!(text, "{}:{}: {}", s.rel, s.line, s.msg);
        }
        // Python iterates the allowlist dict in file order.
        let mut stale_in_order = stale.clone();
        stale_in_order.sort_by_key(|(_, n)| **n);
        for (key, number) in &stale_in_order {
            let _ = writeln!(text, "{}:{}: stale entry (nothing matches it any more): {}", shown, number, key);
        }
        let _ = writeln!(
            text,
            "Deadline polling: {} periodic bodies found, {} allowlisted, {} new finding(s), {} stale entr{}.",
            findings.len(),
            allow.len(),
            bad.len(),
            stale.len(),
            if stale.len() == 1 { "y" } else { "ies" }
        );
        if !bad.is_empty() || !stale.is_empty() {
            let _ = writeln!(text, "{}", HINT.replace("sec 4.11", "\u{a7}4.11"));
            return true;
        }
        false
    }

    fn update_baseline(&self, _cx: &Cx, _run: &Run, _mode: Mode) -> std::io::Result<String> {
        Ok("deadline_polling: the allowlist is hand-maintained (no --update)".to_string())
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/check_deadline_polling.py"],
            old_raw: &[],
            blank: &[ALLOWLIST],
            parse: ParseKind::FileLineAny,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(DeadlinePolling);
}
