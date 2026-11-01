//! Port of `tools/ci/allow_annotations.py`: every `// ALLOW(lint): reason` must be well formed,
//! name a known lint, carry a real reason (at least 20 characters and 3 words; no allowlist talk,
//! "see above", "not edited here", plan-phase labels or plan item codes), and, over a full run,
//! must actually keep a site (an annotation no lint used is stale).
//!
//! The per-annotation checks are this lint. The unused-annotation check needs the usage every
//! other lint recorded in the same run, so it is `unused()` below, called by `analyze check` after
//! all lints ran (a full run only; `check_ratchets.sh` still has the Python do it while legacy
//! lints remain, via DQ_ALLOW_USAGE).

use std::collections::{BTreeMap, BTreeSet};

use crate::allow;
use crate::lint::{AllowUse, Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{Tree, CODE_MAPS_DM};
use crate::util::py_split;

const MIN_REASON: usize = 20;
const MIN_REASON_WORDS: usize = 3;

/// Lints whose annotations the usage check cannot observe: check_grep reads the same line only and
/// doc_snippets reads the design docs, not the .dm tree.
pub const UNOBSERVED: &[&str] = &["check_grep", "doc_snippets"];

static KNOWN: std::sync::OnceLock<BTreeSet<String>> = std::sync::OnceLock::new();

/// The ALLOW names every lint reads (set once by the engine: registered lints' `Meta::allow` plus
/// `[allow] known` in lint_scopes.toml).
pub fn set_known(names: BTreeSet<String>) {
    let _ = KNOWN.set(names);
}

pub fn known() -> &'static BTreeSet<String> {
    KNOWN.get_or_init(BTreeSet::new)
}

fn vague() -> &'static [(Pat, &'static str)] {
    static V: std::sync::LazyLock<Vec<(Pat, &'static str)>> = std::sync::LazyLock::new(|| {
        vec![
            (Pat::new(r"(?i)\ballowlist(?:s|ed)?\b"), "there is no allowlist: say why this site stays"),
            (Pat::new(r"(?i)\b(?:see|as) (?:above|below)\b"), "say the reason here, not on another line"),
            (Pat::new(r"(?i)\bnot edited here\b"), "a deferred conversion is not a reason: convert the site or say why it must stay"),
            (Pat::new(r"(?i)\bS\d+\b|\bwave F\d+|\bsec(?:tion)? \d|\bphase \d"), "a plan-phase label names the plan, not the reason"),
            (Pat::new(r"\b[A-Z]\d{1,2}[a-z]?(?:/[A-Z]?\d{1,2}[a-z]?)*\b"), "a plan item code (M1a, C9, P3, ...) names the plan, not the reason"),
        ]
    });
    &V
}

/// Why `reason` is not a reason, or None (`reason_problem`).
pub fn reason_problem(reason: &str) -> Option<String> {
    let text = crate::util::py_strip(reason);
    if text.chars().count() < MIN_REASON || py_split(text).count() < MIN_REASON_WORDS {
        return Some(format!(
            "reason {} is too short to explain anything (at least {} characters and {} words)",
            py_repr(text),
            MIN_REASON,
            MIN_REASON_WORDS
        ));
    }
    for (pattern, why) in vague() {
        if pattern.is_match(text) {
            let shown = if text.chars().count() <= 70 { text.to_string() } else { format!("{}...", text.chars().take(67).collect::<String>()) };
            return Some(format!("reason {}: {}", py_repr(&shown), why));
        }
    }
    None
}

/// Python's `%r` of a str (single quotes unless the text has a single and no double quote).
fn py_repr(s: &str) -> String {
    let quote = if s.contains('\'') && !s.contains('"') { '"' } else { '\'' };
    let mut out = String::new();
    out.push(quote);
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            c if c == quote => {
                out.push('\\');
                out.push(c);
            }
            c => out.push(c),
        }
    }
    out.push(quote);
    out
}

static META: Meta = Meta {
    name: "allow_annotations",
    group: "",
    label: "allow_annotations",
    legacy: "tools/ci/allow_annotations.py",
    select: CODE_MAPS_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "malformed", hint: "" },
        RuleMeta { name: "no_lint", hint: "" },
        RuleMeta { name: "unknown_lint", hint: "" },
        RuleMeta { name: "no_reason", hint: "" },
        RuleMeta { name: "weak_reason", hint: "" },
    ],
    allow: &[],
    lists: &[],
};

struct AllowAnnotations;

impl Lint for AllowAnnotations {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &crate::tree::SourceFile, out: &mut Sink) {
        if !f.text().contains("ALLOW(") {
            return;
        }
        let known = known();
        for (number, line) in f.raw().numbered() {
            if !line.contains("ALLOW(") {
                continue;
            }
            let Some(a) = allow::parse(line) else {
                out.site_msg("malformed", number, "malformed ALLOW annotation; write `// ALLOW(<lint>[, <lint>]): <reason>`");
                continue;
            };
            if a.names.is_empty() {
                out.site_msg("no_lint", number, "ALLOW() names no lint");
            }
            for name in a.names.iter().filter(|n| !known.contains(*n)) {
                let list: Vec<&str> = known.iter().map(|s| s.as_str()).collect();
                out.site_msg("unknown_lint", number, format!("ALLOW({}): unknown lint; known: {}", name, list.join(", ")));
            }
            let names: Vec<&str> = a.names.iter().map(|s| s.as_str()).collect();
            if a.reason.is_empty() {
                out.site_msg("no_reason", number, format!("ALLOW({}) has no reason after the colon", names.join(", ")));
            } else if let Some(weak) = reason_problem(&a.reason) {
                out.site_msg("weak_reason", number, format!("ALLOW({}): {}", names.join(", "), weak));
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/allow_annotations.py"],
            old_raw: &[],
            blank: &[],
            parse: ParseKind::FileLine,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(AllowAnnotations);
}

/// The unused-ALLOW check over a full run: every annotation naming a known lint whose lint ran and
/// recorded usage, but not for this annotation, is stale. A name with annotations but no recorded
/// usage at all is reported once ("no lint run used any"). Returns the problem lines.
pub fn unused(tree: &Tree, used: &[AllowUse], extra_used: &[(String, String, u32)], digest: &dyn Fn(&str) -> String) -> Vec<String> {
    let known = known();
    let mut used_set: BTreeSet<(String, String, u32)> = BTreeSet::new();
    let mut seen: BTreeSet<String> = BTreeSet::new();
    for u in used {
        used_set.insert((u.name.clone(), u.rel.clone(), u.line));
        seen.insert(u.name.clone());
    }
    // Rows another process recorded (legacy lints): keyed by file digest, mapped back to files.
    let mut by_digest: BTreeMap<String, String> = BTreeMap::new();
    for (name, d, line) in extra_used {
        seen.insert(name.clone());
        if !by_digest.contains_key(d) {
            for f in tree.select(&CODE_MAPS_DM) {
                if f.text().contains("ALLOW(") && digest(&f.rel) == *d {
                    by_digest.insert(d.clone(), f.rel.clone());
                    break;
                }
            }
        }
        if let Some(rel) = by_digest.get(d) {
            used_set.insert((name.clone(), rel.clone(), *line));
        }
    }
    let mut problems = Vec::new();
    let mut quiet: BTreeMap<String, usize> = BTreeMap::new();
    // The annotations of each file, read once per content change (not per run).
    let files = tree.select(&CODE_MAPS_DM);
    let per_file: Vec<Vec<(u32, Vec<String>)>> = crate::incr::facts("allow-annotations", &files, |f| {
        let mut out: Vec<(u32, Vec<String>)> = Vec::new();
        if !f.text().contains("ALLOW(") {
            return out;
        }
        for (number, line) in f.raw().numbered() {
            let Some(a) = (if line.contains("ALLOW(") { allow::parse(line) } else { None }) else { continue };
            out.push((number as u32, a.names.iter().cloned().collect()));
        }
        out
    });
    for (f, anns) in files.iter().zip(per_file) {
        for (number, names) in anns {
            for name in names.iter().filter(|n| known.contains(*n)) {
                if UNOBSERVED.contains(&name.as_str()) {
                    continue;
                }
                if !seen.contains(name) {
                    *quiet.entry(name.clone()).or_insert(0) += 1;
                    continue;
                }
                if !used_set.contains(&(name.clone(), f.rel.clone(), number)) {
                    problems.push(format!(
                        "{}:{}: ALLOW({}) is unused: no longer triggers the {} lint; delete the annotation (or the site's reason is stale)",
                        f.rel, number, name, name
                    ));
                }
            }
        }
    }
    for (name, count) in quiet {
        problems.push(format!(
            "ALLOW({}): {} annotation{}, but no lint run used any: the {} lint is not run, or every one of them is stale",
            name,
            count,
            if count == 1 { "" } else { "s" },
            name
        ));
    }
    problems
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reason_quality_rules() {
        assert!(reason_problem("short").unwrap().contains("too short"));
        assert!(reason_problem("the allowlist keeps this one around").unwrap().contains("no allowlist"));
        assert!(reason_problem("see above for the reason here ok").unwrap().contains("say the reason here"));
        assert!(reason_problem("wave F3 will convert this call site").unwrap().contains("plan-phase"));
        assert!(reason_problem("kept until M1a lands in the tree ok").unwrap().contains("plan item code"));
        assert!(reason_problem("world.Export() is a blocking external call").is_none());
    }

    #[test]
    fn repr_matches_python() {
        assert_eq!(py_repr("a b"), "'a b'");
        assert_eq!(py_repr("it's"), "\"it's\"");
    }
}
