//! Port of `tools/ci/latent_lint.py` (roadmap C5, doc/rewrite/containment.md section 4.4).
//!
//! Holders with latent contents (`latent_contents = TRUE` in the type block) keep some of what they
//! hold as ledger entries, so a raw walk over their `contents` misses things. This flags raw walks in
//! procs of a latent holder type (or subtype) and raw walks through a variable typed as a holder.
//! `// ALLOW(latent): <reason>` keeps a site.
//!
//! Quirks kept from the Python: it reads files with `read().splitlines()` (so form feeds, `\x1c`..`\x1e`,
//! NEL and the Unicode line/paragraph separators also break lines, and there is no final empty line)
//! and `errors="ignore"` (the engine's text is lossy-replace, which only matters next to a bad byte);
//! an ALLOW line skips the whole line, header bookkeeping included; the `typed` variable names are
//! matched with a regex per name.

use std::collections::{BTreeMap, HashMap, HashSet};

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::Parity;
use crate::pat::Pat;
use crate::tree::{SourceFile, Select};
use crate::util::{is_py_space, py_lstrip};

const BASELINE: &str = "tools/ci/latent_baseline.txt";
const HINT: &str = "go through latent_materialize_all()/latent_entries()/slot_contents()";

static META: Meta = Meta {
    name: "latent",
    group: "",
    label: "latent",
    legacy: "tools/ci/latent_lint.py",
    // os.walk: dot-files and dot-directories included.
    select: Select { roots: &[("code", "dm")], hidden: true },
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: BASELINE,
        header: &[
            "Raw contents walks on latent holders (tools/ci/latent_lint.py). rule<TAB>file<TAB>normalized line.",
            "Shrink-only: fix a site through the ledger API, then `python tools/ci/latent_lint.py --update`.",
        ],
        banned: &[],
    },
    rules: &[RuleMeta { name: "raw_walks", hint: HINT }],
    allow: &["latent"],
    lists: &[],
};

struct Latent;

/// `str.splitlines()` (no final empty line; `\r` never occurs: the tree text is universal-newline).
fn py_splitlines(text: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut start = 0;
    for (i, c) in text.char_indices() {
        if matches!(c, '\n' | '\r' | '\u{0b}' | '\u{0c}' | '\u{1c}' | '\u{1d}' | '\u{1e}' | '\u{85}' | '\u{2028}' | '\u{2029}') {
            out.push(&text[start..i]);
            start = i + c.len_utf8();
        }
    }
    if start < text.len() {
        out.push(&text[start..]);
    }
    out
}

/// `allowed(lines, number, "latent")` over an arbitrary line list (the Python's own `splitlines`).
fn allowed_in(out: &mut Sink, f: &SourceFile, lines: &[&str], number: usize) -> bool {
    let keeps = |line: &str| -> Option<Option<String>> {
        match crate::allow::parse(line) {
            Some(a) if !a.reason.is_empty() && a.names.contains("latent") => Some(a.codes.get("latent").cloned()),
            _ => None,
        }
    };
    let mut hit: Option<(usize, Option<String>)> = None;
    if number >= 1 && number <= lines.len() {
        if let Some(code) = keeps(lines[number - 1]) {
            hit = Some((number, code));
        }
    }
    if hit.is_none() && number >= 2 {
        let above = lines.get(number - 2).copied().unwrap_or("");
        if py_lstrip(above).starts_with("//") {
            if let Some(code) = keeps(above) {
                hit = Some((number - 1, code));
            }
        }
    }
    match hit {
        Some((at, code)) => {
            let u = crate::lint::AllowUse { rel: f.rel.clone(), line: at as u32, name: "latent".to_string(), code: code.unwrap_or_default() };
            if !out.allow_used.contains(&u) {
                out.allow_used.push(u);
            }
            true
        }
        None => false,
    }
}

/// `under`: the longest root that is `path` or a path prefix of it.
fn under<'a>(path: &str, roots: &'a HashSet<String>) -> Option<&'a str> {
    let mut best: Option<&str> = None;
    for root in roots {
        if path == root || (path.starts_with(root.as_str()) && path.as_bytes().get(root.len()) == Some(&b'/')) {
            if best.map(|b| root.len() > b.len()).unwrap_or(true) {
                best = Some(root);
            }
        }
    }
    best
}

/// Nearest declaration wins: a subtype set back to FALSE is not a holder.
fn is_holder(path: &str, holders: &HashSet<String>, eager: &HashSet<String>) -> bool {
    let latent = under(path, holders);
    let opted_out = under(path, eager);
    match latent {
        Some(l) => opted_out.map(|o| l.len() > o.len()).unwrap_or(true),
        None => false,
    }
}

impl Lint for Latent {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let type_header = crate::pat_match!(r"(/[\w/]+)\s*$");
        let proc_header = crate::pat_match!(r"(/[\w/]+?)/(?:proc/|verb/)?(\w+)\(");
        let latent_decl = crate::pat_match!(r"\s+latent_contents\s*=\s*(TRUE|FALSE)");
        let own_walk = crate::pat!(
            r"\bin\s+(?:src\.)?contents\b|\bin\s+src\s*\)|(?<![\w.])contents\.len\b|length\(\s*(?:src\.)?contents\s*\)"
        );
        let typed_var = crate::pat!(r"var/([\w/]+)/(\w+)");
        let legacy_loop = crate::pat!(r"\bfor\s*\(.*\bin\s+(?:[\w.]+\.)?contents\b");

        let files = cx.files();
        let all_lines: Vec<Vec<&str>> = files.iter().map(|f| py_splitlines(f.text())).collect();

        // latent_holders
        let mut holders: HashSet<String> = HashSet::new();
        let mut eager: HashSet<String> = HashSet::new();
        for lines in &all_lines {
            let mut current: Option<String> = None;
            for line in lines {
                if let Some(h) = type_header.captures(line) {
                    current = Some(h.s(1).to_string());
                    continue;
                }
                if !line.is_empty() && !line.chars().next().map(is_py_space).unwrap_or(false) {
                    current = None;
                }
                if let Some(cur) = &current {
                    if let Some(d) = latent_decl.captures(line) {
                        if d.s(1) == "TRUE" {
                            holders.insert(cur.clone());
                        } else {
                            eager.insert(cur.clone());
                        }
                    }
                }
            }
        }

        let mut where_: BTreeMap<&str, Vec<usize>> = BTreeMap::new();
        let mut legacy = 0usize;
        let mut dynamic: HashMap<String, Pat> = HashMap::new();
        for (f, lines) in files.iter().zip(&all_lines) {
            for line in lines {
                if legacy_loop.is_match(line) {
                    legacy += 1;
                }
            }
            // scan
            let mut sites: Vec<usize> = Vec::new();
            let mut owner: Option<String> = None;
            let mut typed: Vec<String> = Vec::new();
            for (i, line) in lines.iter().enumerate() {
                let number = i + 1;
                if allowed_in(out, f, lines, number) {
                    continue;
                }
                if let Some(h) = proc_header.captures(line) {
                    owner = Some(h.s(1).to_string());
                    typed.clear();
                } else if !line.is_empty() && !line.chars().next().map(is_py_space).unwrap_or(false) && !line.starts_with("//") {
                    owner = None;
                    typed.clear();
                }
                let code = line.split("//").next().unwrap_or("");
                for m in typed_var.captures_iter(code) {
                    let var_type = format!("/{}", m.s(1).trim_start_matches('/'));
                    if is_holder(&var_type, &holders, &eager) && !typed.iter().any(|t| t == m.s(2)) {
                        typed.push(m.s(2).to_string());
                    }
                }
                if let Some(o) = &owner {
                    if is_holder(o, &holders, &eager) && own_walk.is_match(code) {
                        sites.push(number);
                        continue;
                    }
                }
                for name in &typed {
                    let p = dynamic
                        .entry(name.clone())
                        .or_insert_with(|| Pat::new(&format!(r"\b{0}\.contents\b|\bin\s+{0}\s*\)", name)));
                    if p.is_match(code) {
                        sites.push(number);
                        break;
                    }
                }
            }
            if !sites.is_empty() {
                where_.insert(f.rel.as_str(), sites);
            }
        }
        let total: usize = where_.values().map(|v| v.len()).sum();
        for (rel, nums) in &where_ {
            for n in nums {
                out.site_in("raw_walks", rel, *n);
            }
        }
        out.note(format!(
            "latent lint: {} latent holder roots ({} opted out), {} sites in {} files, {} legacy contents loops tree-wide",
            holders.len(),
            eager.len(),
            total,
            where_.len(),
            legacy
        ));
    }

    fn parity(&self) -> Option<Parity> {
        let mut p = Parity::ratchet(&["tools/ci/latent_lint.py"], &[BASELINE]);
        p.update = Some(&["tools/ci/latent_lint.py", "--update"]);
        p.seed = Some(&["tools/ci/latent_lint.py", "--seed"]);
        Some(p)
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Latent);
}
