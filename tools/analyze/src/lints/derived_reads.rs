//! Port of `tools/ci/derived_reads_lint.py`: the declared-dependencies lint
//! (doc/rewrite/dx_conventions.md, "Declared dependencies").
//!
//! A type lists what its derived procs read in `derived()`; the lint checks the declaration against
//! the bodies (undeclared_read), that declared vars can notify (declared_untracked, hop_not_relation),
//! that an exact type does not override `on_state_changed` (exact_on_state_changed) and that a
//! presentation reaction only reads published vars (reaction_read_untracked). The CI run also fails
//! when the committed `code/_generated/reads.dm` is stale (`post_judge`).
//!
//! Not ported: `--report`, `--fix`, `--fix-generated` (they stay in the Python script). `fix_texts`
//! is ported only because the self-test exercises it. `chain()` is the port of
//! `state_schema_lint.chain`, kept private here.
//!
//! Quirks kept: a global `/proc/foo(` has owner `/proc` (the lazy owner group) and is treated like
//! a type; `exact()` is false for a `derived()` that lists nothing; `model.entries` keys keep the
//! empty list of such a `derived()`; the CI run (`generated_covers`) skips a type with no `derived()`.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::fmt::Write as _;
use std::sync::Arc;


use crate::lint::{Cx, Lint, Meta, Policy, Registry, Run, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{SourceFile, Tree, CODE_DM};
use crate::util::{is_py_space, py_lstrip, py_rstrip, py_strip};
use crate::{pat, pat_match};

const LINT: &str = "derived_reads";
const SKIP_SITE_DIRS: &[&str] = &["code/modules/unit_tests/"];
const GENERATED_SKIP_DIRS: &[&str] = &["code/modules/unit_tests/", "code/modules/benchmarks/"];
pub(crate) const GENERATED_REL: &str = "code/_generated/reads.dm";
const EXEMPT_VARS: &[&str] = &["cap_state", "cap_data"];
const MODIFIERS: &[&str] = &["tmp", "static", "global", "const", "final"];
const OBJECT_ROOTS: &[&str] = &["datum", "obj", "mob", "atom", "turf", "area", "client", "image", "list"];
const REACTION_OWNER_ROOT: &str = "/mob";

const H_UNDECLARED: &str = "declare it in derived() (`--fix` adds it), or keep with // ALLOW(derived_reads): <reason>";
const H_UNTRACKED: &str = "make it TRACKED / SETTER, a derive() value or a declared relation (OWN / REL)";
const H_HOP: &str = "declare the link var REL / REL_LIST / OWN; a hop only follows a declared relation";
const H_REACTION: &str = "make the var TRACKED / SETTER / an OM field or a relation, or name the key its producer publishes with PUBLISHED_BY(T, var, KEY)";
const H_UI_UNTRACKED: &str = "make the var TRACKED / SETTER (and write it through its setter), a derive() value or a declared relation (REL / OWN): a window host must track what its ui_data() shows, or the window never hears it change";
const H_EXACT: &str = "use push_to_rust() with rust_push(...): an exact type is not woken for on_state_changed";

static META: Meta = Meta {
    name: "derived_reads",
    group: "",
    label: "derived_reads",
    legacy: "tools/ci/derived_reads_lint.py",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: "tools/ci/derived_reads_baseline.txt",
        header: &[
            "Legacy derived-proc reads a type's derived() doesn't declare (tools/ci/derived_reads_lint.py).",
            "rule<TAB>file<TAB>normalized line. Shrink-only: after a sweep, `python tools/ci/derived_reads_lint.py --update`.",
        ],
        banned: &[],
    },
    rules: &[
        RuleMeta { name: "undeclared_read", hint: H_UNDECLARED },
        RuleMeta { name: "declared_untracked", hint: H_UNTRACKED },
        RuleMeta { name: "hop_not_relation", hint: H_HOP },
        RuleMeta { name: "reaction_read_untracked", hint: H_REACTION },
        RuleMeta { name: "untracked_ui_read", hint: H_UI_UNTRACKED },
        RuleMeta { name: "exact_on_state_changed", hint: H_EXACT },
    ],
    allow: &["derived_reads"],
    lists: &["ui_hosts"],
};

// ---- small mappings ---------------------------------------------------------------------------

fn proc_kind(name: &str) -> Option<&'static str> {
    match name {
        "should_run" => Some("runs"),
        "draw" | "hidden_verbs" => Some("drawn"),
        "tgui_data" | "ui_data" => Some("ui"),
        "push_to_rust" => Some("push"),
        _ => None,
    }
}

fn entry_kind(call: &str) -> &'static str {
    match call {
        "runs_while" => "runs",
        "drawn_from" => "drawn",
        "ui_from" => "ui",
        "rust_push" => "push",
        _ => "derive",
    }
}

fn kind_call(kind: &str) -> Option<&'static str> {
    match kind {
        "runs" => Some("runs_while"),
        "drawn" => Some("drawn_from"),
        "ui" => Some("ui_from"),
        "push" => Some("rust_push"),
        _ => None,
    }
}

fn reaction_kind_flag(call: &str) -> &'static str {
    match call {
        "every" => "RXB_EVERY",
        "on_cross" => "RXB_CROSS",
        "on_notice" => "RXB_NOTICE",
        _ => unreachable!("reaction kind {call}"),
    }
}

/// `(kind, handler, roots, output vars)` in `REACTION_OUTPUTS` order.
const REACTION_OUTPUTS: &[(&str, &str, &[&str], &[&str])] = &[
    (
        "hud",
        "life_hud_changed",
        &["life_hud", "life_hud_health_icons", "life_hud_darksight"],
        &[
            "dsoverlay", "health_doll_key", "healths", "damageoverlaytemp", "global_hud_claims", "alerts", "screens", "hud_list",
            "hud_used", "belly_overlay_tgui", "card", "borer_chem_display", "pai_fold_display",
        ],
    ),
    ("vision", "life_vision_changed", &["life_vision"], &["plane_holder", "global_hud_claims", "hud_used", "seer"]),
    (
        "canmove",
        "life_canmove_changed",
        &["life_canmove", "update_canmove"],
        &["canmove", "lying", "lying_prev", "passtable_crawl_checked", "passtable_reset", "pass_flags"],
    ),
];

fn starts_any(rel: &str, dirs: &[&str]) -> bool {
    dirs.iter().any(|d| rel.starts_with(d))
}

// ---- types ------------------------------------------------------------------------------------

/// `state_schema_lint.ancestors`: every path prefix, shortest first.
fn path_prefixes(path: &str) -> Vec<String> {
    let segs: Vec<&str> = path.trim_matches('/').split('/').collect();
    (1..=segs.len()).map(|i| format!("/{}", segs[..i].join("/"))).collect()
}

/// `state_schema_lint.chain`: the type and its ancestors, root first, with DM's implicit parents.
fn chain(path: &str) -> Vec<String> {
    let mut out = path_prefixes(path);
    if out[0] != "/datum" {
        let first = out[0].clone();
        if matches!(first.as_str(), "/obj" | "/mob" | "/turf" | "/area") {
            let n = if first == "/obj" || first == "/mob" { 3 } else { 2 };
            let mut pre: Vec<String> = ["/datum", "/atom", "/atom/movable"][..n].iter().map(|s| s.to_string()).collect();
            pre.extend(out);
            out = pre;
        } else if first == "/atom" {
            out.insert(0, "/datum".to_string());
        }
    }
    out
}

// ---- parsing ----------------------------------------------------------------------------------

type VarTable = HashMap<String, HashSet<String>>;

fn decl_name(segs: &[&str]) -> Option<String> {
    let mut i = 0;
    while i < segs.len() && MODIFIERS.contains(&segs[i]) {
        i += 1;
    }
    segs[i..].last().map(|s| s.to_string())
}

fn note_typed(typed: &mut VarTable, owner: &str, segs: &[&str], name: &str) {
    let segs: Vec<&&str> = segs.iter().filter(|s| !s.is_empty() && !MODIFIERS.contains(*s)).collect();
    if segs.len() > 1 && OBJECT_ROOTS.contains(segs[0]) {
        typed.entry(owner.to_string()).or_default().insert(name.to_string());
    }
}

/// `parse_vars`: `{type: var names}` declared in one file's `code_only` lines; `typed` collects the
/// object-typed ones.
fn parse_vars(lines: &[&str], typed: &mut VarTable) -> VarTable {
    let mut found: VarTable = HashMap::new();
    let mut cur: Option<String> = None;
    let mut in_proc = false;
    let mut block_indent: Option<usize> = None;
    for raw in lines {
        if py_strip(raw).is_empty() {
            continue;
        }
        let stripped = raw.trim_start_matches(['\t', ' ']);
        let indent = raw.len() - stripped.len();
        let text = py_rstrip(stripped);
        if text.starts_with('#') {
            continue;
        }
        if indent == 0 {
            block_indent = None;
            in_proc = false;
            cur = None;
            let Some(m) = pat_match!(r"(/?[A-Za-z_][\w/]*)\s*(?:$|=|\()").captures(text) else { continue };
            let g1 = m.s(1);
            let full = if g1.starts_with('/') { g1.to_string() } else { format!("/{}", g1) };
            let segs: Vec<&str> = full.trim_matches('/').split('/').collect();
            if segs.contains(&"proc") || segs.contains(&"verb") || py_lstrip(&text[m.end(1)..]).starts_with('(') {
                in_proc = true;
                continue;
            }
            if let Some(k) = segs.iter().position(|s| *s == "var") {
                if let Some(name) = decl_name(&segs[k + 1..]) {
                    let owner = format!("/{}", segs[..k].join("/"));
                    found.entry(owner.clone()).or_default().insert(name.clone());
                    note_typed(typed, &owner, &segs[k + 1..], &name);
                }
                continue;
            }
            cur = Some(full.trim_end_matches('/').to_string());
            continue;
        }
        if in_proc {
            continue;
        }
        let Some(owner) = cur.clone() else { continue };
        if let Some(bi) = block_indent {
            if indent > bi {
                if let Some(m) = pat_match!(r"((?:[A-Za-z_]\w*/)*[A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*(?:=|$)").captures(text) {
                    let segs: Vec<&str> = m.s(1).split('/').collect();
                    if let Some(name) = decl_name(&segs) {
                        found.entry(owner.clone()).or_default().insert(name.clone());
                        note_typed(typed, &owner, &segs, &name);
                    }
                }
                continue;
            }
        }
        block_indent = None;
        if indent != 1 && !raw.starts_with("    ") {
            continue;
        }
        if pat_match!(r"var(/(tmp|static|global|const))*\s*$").is_match(text) {
            block_indent = Some(indent);
            continue;
        }
        if let Some(m) = pat_match!(r"var((?:/[A-Za-z_]\w*)+)\s*(?:\[[^\]]*\])?\s*(?:=|$|as\b)").captures(text) {
            let segs: Vec<&str> = m.s(1).trim_matches('/').split('/').collect();
            if let Some(name) = decl_name(&segs) {
                found.entry(owner.clone()).or_default().insert(name.clone());
                note_typed(typed, &owner, &segs, &name);
            }
        }
    }
    found
}

#[derive(Clone, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
struct Proc {
    rel: String,
    owner: String,
    name: String,
    /// The text after the `(` of the head.
    args: String,
    start: usize,
    body: Vec<(usize, String)>,
}

fn helper_name(name: &str) -> bool {
    pat_match!(r"(?:life_hud|life_vision|life_canmove|update_canmove|hud_available|process_glasses|process_nifsoft_vision|pain_knockout_fraction|set_fullscreen|life_placed)")
        .is_match(name)
}

/// Whether a proc's body is read after parsing (the rest are kept without a body, to save memory).
fn keeps_body(name: &str) -> bool {
    name == "derived" || name == "reactions" || proc_kind(name).is_some() || name.starts_with("derive_") || helper_name(name)
}

/// Whether any rule, generator or fix reads a proc of this name from the model: the reactive kinds,
/// `derived` / `reactions` / `on_state_changed`, `derive_<x>` values and the reaction helpers. The
/// other procs are dropped at parse time (they are most of them).
fn keeps_model_proc(name: &str) -> bool {
    keeps_body(name) || name == "on_state_changed"
}

/// `parse_procs`: every top-level proc of one file's `code_only` lines.
fn parse_procs(rel: &str, code: &crate::tree::View) -> Vec<Proc> {
    let mut out = Vec::new();
    let mut cur: Option<Proc> = None;
    for (number, line) in code.numbered() {
        if line.chars().next().map(|c| !is_py_space(c)).unwrap_or(false) {
            if let Some(p) = cur.take() {
                out.push(p);
            }
            let text = py_rstrip(line);
            if text.starts_with('#') || pat_match!(r"/[\w/]+\s*$").is_match(text) {
                continue;
            }
            if let Some(m) = pat_match!(r"(/[\w/]*?)/(?:(?:proc|verb)/)?(\w+)\s*\((.*)$").captures(text) {
                let owner = if m.s(1).is_empty() { "/" } else { m.s(1) };
                cur = Some(Proc { rel: rel.to_string(), owner: owner.to_string(), name: m.s(2).to_string(), args: m.s(3).to_string(), start: number, body: Vec::new() });
            }
            continue;
        }
        if let Some(p) = cur.as_mut() {
            if !py_strip(line).is_empty() {
                p.body.push((number, line.to_string()));
            }
        }
    }
    if let Some(p) = cur.take() {
        out.push(p);
    }
    out
}

/// `split_args`: top-level comma split of the inside of a call.
fn split_args(text: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut depth = 0i32;
    let mut cur = String::new();
    for ch in text.chars() {
        if "([{".contains(ch) {
            depth += 1;
        } else if ")]}".contains(ch) {
            depth -= 1;
        }
        if ch == ',' && depth == 0 {
            parts.push(std::mem::take(&mut cur));
        } else {
            cur.push(ch);
        }
    }
    if !py_strip(&cur).is_empty() {
        parts.push(cur);
    }
    parts.iter().map(|p| py_strip(p).to_string()).collect()
}

/// `call_args`: the text between the paren at `open` and its match, and the index after the match.
fn paren_args(text: &str, open: usize) -> (&str, usize) {
    let b = text.as_bytes();
    let mut depth = 0i32;
    for i in open..b.len() {
        if b[i] == b'(' {
            depth += 1;
        } else if b[i] == b')' {
            depth -= 1;
            if depth == 0 {
                return (&text[open + 1..i], i + 1);
            }
        }
    }
    (&text[open + 1..], text.len())
}

#[derive(Clone, Debug)]
struct Entry {
    rel: String,
    line: usize,
    kind: &'static str,
    name: Option<String>,
    local: BTreeSet<String>,
    remote: Vec<(Option<String>, String)>,
    hops: Vec<String>,
}

const NAMEOF: &str = r"nameof\(\s*(?:(/[\w/]+)::)?(\w+)\s*\)$";

/// `parse_entries`: the entries of one `derived()` body.
fn parse_entries(proc: &Proc) -> Vec<Entry> {
    let text = proc.body.iter().map(|(_, t)| t.as_str()).collect::<Vec<_>>().join("\n");
    let mut starts = Vec::new();
    let mut offset = 0usize;
    for (_, line) in &proc.body {
        starts.push(offset);
        offset += line.len() + 1;
    }
    let mut entries = Vec::new();
    let mut pos = 0usize;
    loop {
        let Some(m) = pat!(r"(?<![\w.])(runs_while|drawn_from|ui_from|rust_push|derive)\s*\(").captures_at(&text, pos) else { break };
        let (inner, end) = paren_args(&text, m.end(0) - 1);
        pos = end;
        let kind = entry_kind(m.s(1));
        let mut args = split_args(inner);
        let mut name = None;
        if kind == "derive" {
            let first = if args.is_empty() { None } else { pat_match!(NAMEOF).captures(&args[0]) };
            name = first.map(|f| f.s(2).to_string());
            if !args.is_empty() {
                args.remove(0);
            }
        }
        let mut local = BTreeSet::new();
        let mut remote = Vec::new();
        let mut hops = Vec::new();
        for arg in &args {
            if let Some(n) = pat_match!(NAMEOF).captures(arg) {
                local.insert(n.s(2).to_string());
                continue;
            }
            if let Some(h) = pat_match!(r"(?s)(rel|rel_each)\((.*)\)$").captures(arg) {
                let parts = split_args(h.s(2));
                let link = parts.first().and_then(|p| pat_match!(NAMEOF).captures(p));
                let far = parts.get(1).and_then(|p| pat_match!(NAMEOF).captures(p));
                if let Some(l) = link {
                    hops.push(l.s(2).to_string());
                    local.insert(l.s(2).to_string());
                }
                if let Some(f) = far {
                    remote.push((f.get(1).map(|s| s.to_string()), f.s(2).to_string()));
                }
            }
        }
        let idx = starts.partition_point(|&s| s <= m.start(0));
        let line = if proc.body.is_empty() { proc.start } else { proc.body[idx - 1].0 };
        entries.push(Entry { rel: proc.rel.clone(), line, kind, name, local, remote, hops });
    }
    entries
}

/// `body_reads`: `(var, first line)` for each var in `known` the proc body reads, in read order.
fn body_reads(proc: &Proc, known: &HashSet<String>) -> Vec<(String, usize)> {
    let mut locals: HashSet<String> = HashSet::new();
    let mut depth = 0i32;
    let mut cur = String::new();
    let mut params: Vec<String> = Vec::new();
    for ch in proc.args.chars() {
        if ch == '(' {
            depth += 1;
        } else if ch == ')' {
            if depth == 0 {
                break;
            }
            depth -= 1;
        }
        if ch == ',' && depth == 0 {
            params.push(std::mem::take(&mut cur));
        } else {
            cur.push(ch);
        }
    }
    params.push(cur);
    for p in &params {
        let before_eq = py_strip(p.split('=').next().unwrap_or(""));
        let piece = match pat!(r"\s+as\s+").find(before_eq) {
            Some(m) => &before_eq[..m.start],
            None => before_eq,
        };
        if !piece.is_empty() {
            locals.insert(py_strip(piece.rsplit('/').next().unwrap_or("")).to_string());
        }
    }
    let mut reads: Vec<(String, usize)> = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();
    for (number, line) in &proc.body {
        if py_lstrip(line).starts_with('#') {
            continue;
        }
        let mut cur_line = line.clone();
        loop {
            let next = pat!(r"\b(?:nameof|initial)\s*\([^()]*\)").replace_all(&cur_line, "");
            if next == cur_line {
                break;
            }
            cur_line = next;
        }
        for m in pat!(r"\bvar/(?:[\w/]*/)?(\w+)").captures_iter(&cur_line) {
            locals.insert(m.s(1).to_string());
        }
        for m in pat!(r"(?<![\w.:/])(?:src\.)?([A-Za-z_]\w*)\b(?!\s*\()(?!\s*::)(?!\s*=(?!=))").captures_iter(&cur_line) {
            let name = m.s(1);
            if known.contains(name) && !locals.contains(name) && !seen.contains(name) && !EXEMPT_VARS.contains(&name) {
                seen.insert(name.to_string());
                reads.push((name.to_string(), *number));
            }
        }
    }
    reads
}

// ---- the model --------------------------------------------------------------------------------

struct Parts {
    vars: VarTable,
    typed: VarTable,
    tracked: VarTable,
    relations: VarTable,
    published: Vec<(String, String, String)>,
    procs: Vec<Proc>,
    entries: Vec<(usize, Vec<Entry>)>,
}

fn parse_file(f: &SourceFile) -> Parts {
    let code = f.code();
    let lines: Vec<&str> = code.lines_vec();
    let mut typed = VarTable::new();
    let vars = parse_vars(&lines, &mut typed);
    let mut tracked = VarTable::new();
    let mut relations = VarTable::new();
    let mut published = Vec::new();
    let mut caps_owner: Option<String> = None;
    for line in &lines {
        if line.starts_with('#') {
            continue;
        }
        // A CAPABILITIES(/type) block declares relations with ref_one / ref_many / rel_one / rel_many / own_one / own_many (nameof(var), ...).
        if let Some(m) = pat_match!(r"^CAPABILITIES\(\s*(/[\w/]+)").captures(line) {
            caps_owner = Some(m.s(1).to_string());
        } else if !line.starts_with('\t') && !line.starts_with(' ') && !line.is_empty() {
            caps_owner = None;
        } else if let Some(owner) = &caps_owner {
            if let Some(m) = pat_match!(r"^\s+(?:ref|rel|own)_(?:one|many)\(\s*nameof\(\s*(\w+)\s*\)").captures(line) {
                relations.entry(owner.clone()).or_default().insert(m.s(1).to_string());
            }
        }
        if let Some(m) = pat_match!(r"(?:TRACKED|TRACKED_BRIDGED|SETTER)\(\s*(/[\w/]+)\s*,\s*(\w+)").captures(line) {
            tracked.entry(m.s(1).to_string()).or_default().insert(m.s(2).to_string());
        }
        if let Some(m) = pat_match!(
            r"(?:OWN|OWN_POLICY|OWN_IF|REL|REL_LIST|REL_PAIR|REL_PAIR_LIST|REL_SET|REL_KEYED|REL_KEYED_LIST)\(\s*(/[\w/]+)\s*,\s*(\w+)"
        )
        .captures(line)
        {
            relations.entry(m.s(1).to_string()).or_default().insert(m.s(2).to_string());
        }
        let om = pat_match!(r"(?:OM_FIELD|OM_FLAG_FIELD|OM_FLAG_FIELD_BITS|OM_FIELD_SETTER)\(\s*(/[\w/]+)\s*,\s*(\w+)")
            .captures(line)
            .or_else(|| pat_match!(r"OM_FIELD_TYPED\(\s*(/[\w/]+)\s*,\s*[\w/]+\s*,\s*(\w+)").captures(line));
        if let Some(m) = om {
            tracked.entry(m.s(1).to_string()).or_default().insert(m.s(2).to_string());
        }
        if let Some(m) = pat_match!(r"PUBLISHED_BY\(\s*(/[\w/]+)\s*,\s*(\w+)\s*,\s*(\w+)\s*\)").captures(line) {
            published.push((m.s(1).to_string(), m.s(2).to_string(), m.s(3).to_string()));
        }
    }
    let mut procs = Vec::new();
    let mut entries = Vec::new();
    for mut proc in parse_procs(&f.rel, code) {
        let trimmed = proc.owner.trim_end_matches('/');
        proc.owner = if trimmed.is_empty() { "/".to_string() } else { trimmed.to_string() };
        if proc.name == "relations" && proc.owner != "/" {
            for (_n, text) in &proc.body {
                for m in pat!(r"\brel_(?:one|many)\(\s*nameof\(\s*(\w+)\s*\)").captures_iter(text) {
                    relations.entry(proc.owner.clone()).or_default().insert(m.s(1).to_string());
                }
            }
        }
        if proc.name == "derived" && proc.owner != "/" {
            entries.push((procs.len(), parse_entries(&proc)));
        }
        if !keeps_model_proc(&proc.name) {
            continue; // no rule or generator ever reads this proc
        }
        if !keeps_body(&proc.name) {
            proc.body = Vec::new();
        }
        procs.push(proc);
    }
    Parts { vars, typed, tracked, relations, published, procs, entries }
}

/// An [`Entry`] in its cache form (`kind` as text, the set sorted).
#[derive(Clone, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
struct StoredEntry {
    rel: String,
    line: usize,
    kind: String,
    name: Option<String>,
    local: Vec<String>,
    remote: Vec<(Option<String>, String)>,
    hops: Vec<String>,
}

type StoredTable = Vec<(String, Vec<String>)>;

/// One file's [`Parts`], cached by content: tables as sorted vectors, entries in their stored form.
#[derive(Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
struct StoredParts {
    vars: StoredTable,
    typed: StoredTable,
    tracked: StoredTable,
    relations: StoredTable,
    published: Vec<(String, String, String)>,
    procs: Vec<Proc>,
    entries: Vec<(usize, Vec<StoredEntry>)>,
}

fn store_table(t: &VarTable) -> StoredTable {
    let mut v: StoredTable = t
        .iter()
        .map(|(k, set)| {
            let mut names: Vec<String> = set.iter().cloned().collect();
            names.sort();
            (k.clone(), names)
        })
        .collect();
    v.sort();
    v
}

fn load_table(t: StoredTable) -> VarTable {
    t.into_iter().map(|(k, v)| (k, v.into_iter().collect())).collect()
}

fn intern_kind(kind: &str) -> &'static str {
    match kind {
        "runs" => "runs",
        "drawn" => "drawn",
        "ui" => "ui",
        "push" => "push",
        _ => "derive",
    }
}

impl StoredParts {
    fn from(p: Parts) -> StoredParts {
        StoredParts {
            vars: store_table(&p.vars),
            typed: store_table(&p.typed),
            tracked: store_table(&p.tracked),
            relations: store_table(&p.relations),
            published: p.published,
            procs: p.procs,
            entries: p
                .entries
                .into_iter()
                .map(|(i, es)| {
                    let es = es
                        .into_iter()
                        .map(|e| StoredEntry {
                            rel: e.rel,
                            line: e.line,
                            kind: e.kind.to_string(),
                            name: e.name,
                            local: e.local.into_iter().collect(),
                            remote: e.remote,
                            hops: e.hops,
                        })
                        .collect();
                    (i, es)
                })
                .collect(),
        }
    }

    fn into_parts(self) -> Parts {
        Parts {
            vars: load_table(self.vars),
            typed: load_table(self.typed),
            tracked: load_table(self.tracked),
            relations: load_table(self.relations),
            published: self.published,
            procs: self.procs,
            entries: self
                .entries
                .into_iter()
                .map(|(i, es)| {
                    let es = es
                        .into_iter()
                        .map(|e| Entry {
                            rel: e.rel,
                            line: e.line,
                            kind: intern_kind(&e.kind),
                            name: e.name,
                            local: e.local.into_iter().collect(),
                            remote: e.remote,
                            hops: e.hops,
                        })
                        .collect();
                    (i, es)
                })
                .collect(),
        }
    }
}

fn merge(into: &mut VarTable, from: VarTable) {
    for (k, v) in from {
        into.entry(k).or_default().extend(v);
    }
}

#[derive(Default)]
struct Model {
    vars: VarTable,
    tracked: VarTable,
    relations: VarTable,
    object_vars: VarTable,
    published: HashMap<String, HashMap<String, String>>,
    procs: Vec<Proc>,
    entries: HashMap<String, Vec<Entry>>,
    /// Owners in the order their first `derived()` was seen (`model.entries` insertion order).
    entry_order: Vec<String>,
    /// Owner -> index into `procs` of its (last) `derived()`.
    derived_procs: HashMap<String, usize>,
}

impl Model {
    fn build(files: &[&SourceFile]) -> Model {
        let kept: Vec<&SourceFile> = files.iter().copied().filter(|f| f.rel != GENERATED_REL).collect();
        let parts: Vec<Parts> = crate::incr::facts("derived-reads-parts", &kept, |f| StoredParts::from(parse_file(f))).into_iter().map(StoredParts::into_parts).collect();
        let mut m = Model::default();
        for p in parts {
            let base = m.procs.len();
            merge(&mut m.vars, p.vars);
            merge(&mut m.object_vars, p.typed);
            merge(&mut m.tracked, p.tracked);
            merge(&mut m.relations, p.relations);
            for (owner, var, key) in p.published {
                m.published.entry(owner).or_default().insert(var, key);
            }
            for (idx, ents) in p.entries {
                let owner = p.procs[idx].owner.clone();
                m.derived_procs.insert(owner.clone(), base + idx);
                if !m.entries.contains_key(&owner) {
                    m.entry_order.push(owner.clone());
                }
                m.entries.entry(owner).or_default().extend(ents);
            }
            m.procs.extend(p.procs);
        }
        m
    }

    fn get(tree: &Tree, files: &[&SourceFile]) -> Arc<Model> {
        let mut h = blake3::Hasher::new();
        h.update(b"derived-reads-model");
        for f in files {
            h.update(&f.fkey.to_le_bytes());
        }
        let key = h.finalize().to_hex().to_string();
        tree.memo(&key, || Model::build(files))
    }

    fn union(&self, table: &VarTable, path: &str) -> HashSet<String> {
        let mut out = HashSet::new();
        for a in chain(path) {
            if let Some(s) = table.get(&a) {
                out.extend(s.iter().cloned());
            }
        }
        out
    }

    /// The vars the type (and its ancestors) declare for `kind` (not "derive").
    fn declared(&self, path: &str, kind: &str) -> HashSet<String> {
        let mut out = HashSet::new();
        for a in chain(path) {
            for e in self.entries.get(&a).map(|v| v.as_slice()).unwrap_or(&[]) {
                if e.kind == kind {
                    out.extend(e.local.iter().cloned());
                }
            }
        }
        out
    }

    /// For derive: `{value: its reads}`.
    fn declared_derive(&self, path: &str) -> HashMap<String, HashSet<String>> {
        let mut out: HashMap<String, HashSet<String>> = HashMap::new();
        for a in chain(path) {
            for e in self.entries.get(&a).map(|v| v.as_slice()).unwrap_or(&[]) {
                if e.kind == "derive" {
                    if let Some(n) = e.name.as_ref().filter(|n| !n.is_empty()) {
                        out.entry(n.clone()).or_default().extend(e.local.iter().cloned());
                    }
                }
            }
        }
        out
    }

    fn published_key(&self, path: &str, name: &str) -> Option<String> {
        for a in chain(path).iter().rev() {
            if let Some(k) = self.published.get(a).and_then(|t| t.get(name)).filter(|k| !k.is_empty()) {
                return Some(k.clone());
            }
        }
        None
    }

    fn exact(&self, path: &str) -> bool {
        chain(path).iter().any(|a| self.entries.get(a).map(|v| !v.is_empty()).unwrap_or(false))
    }
}

// ---- the rules --------------------------------------------------------------------------------

#[derive(Clone, Debug)]
struct Finding {
    rel: String,
    line: usize,
    rule: &'static str,
    owner: String,
    proc: String,
    var: Option<String>,
    kind: Option<String>,
}

fn raw_allowed(tree: &Tree, sink: &mut Sink, rel: &str, line: usize) -> bool {
    match tree.get(rel) {
        Some(f) => sink.allowed(f, line, LINT),
        None => false,
    }
}

fn derive_value(name: &str) -> Option<&str> {
    name.strip_prefix("derive_").filter(|v| !v.is_empty())
}

fn analyze(model: &Model, tree: &Tree, sink: &mut Sink, generated_covers: bool, ui_hosts: &[String]) -> Vec<Finding> {
    let mut findings: Vec<Finding> = Vec::new();
    for proc in &model.procs {
        if proc.owner == "/" || starts_any(&proc.rel, SKIP_SITE_DIRS) || proc.owner.starts_with("/datum/capability") {
            continue;
        }
        let kind = proc_kind(&proc.name);
        let value = derive_value(&proc.name);
        if kind.is_none() && value.is_none() {
            continue;
        }
        let known = model.union(&model.vars, &proc.owner);
        if proc.name == "ui_data" {
            // A window host's ui_data(A) is an output: every var of the host it reads must publish its writes, or nothing
            // re-runs it. Enforced for the hosts lint_scopes.toml lists (`ui_hosts`, the converted ones); the list grows as hosts
            // convert and goes away, the rule global, when the last one has.
            if !ui_hosts.iter().any(|h| *h == proc.owner) {
                continue;
            }
            let tracked = model.union(&model.tracked, &proc.owner);
            let relations = model.union(&model.relations, &proc.owner);
            let derived: HashSet<String> = model.declared_derive(&proc.owner).into_keys().collect();
            for (name, line) in body_reads(proc, &known) {
                if EXEMPT_VARS.contains(&name.as_str()) || tracked.contains(&name) || relations.contains(&name) || derived.contains(&name) || raw_allowed(tree, sink, &proc.rel, line) {
                    continue;
                }
                findings.push(Finding {
                    rel: proc.rel.clone(),
                    line,
                    rule: "untracked_ui_read",
                    owner: proc.owner.clone(),
                    proc: proc.name.clone(),
                    var: Some(name),
                    kind: Some("ui".to_string()),
                });
            }
        }
        if generated_covers && !model.exact(&proc.owner) {
            continue;
        }
        let (allowed_reads, label, wanted_kind): (HashSet<String>, String, &str) = if let Some(value) = value {
            let Some(reads_of) = model.declared_derive(&proc.owner).remove(value) else { continue };
            (reads_of, format!("derive_{}", value), "derive")
        } else {
            let k = kind.unwrap();
            (model.declared(&proc.owner, k), proc.name.clone(), k)
        };
        for (name, line) in body_reads(proc, &known) {
            if allowed_reads.contains(&name) || raw_allowed(tree, sink, &proc.rel, line) {
                continue;
            }
            findings.push(Finding {
                rel: proc.rel.clone(),
                line,
                rule: "undeclared_read",
                owner: proc.owner.clone(),
                proc: label.clone(),
                var: Some(name),
                kind: Some(wanted_kind.to_string()),
            });
        }
    }
    for proc in &model.procs {
        if proc.name == "on_state_changed"
            && proc.owner != "/"
            && !starts_any(&proc.rel, SKIP_SITE_DIRS)
            && model.exact(&proc.owner)
            && !raw_allowed(tree, sink, &proc.rel, proc.start)
        {
            findings.push(Finding {
                rel: proc.rel.clone(),
                line: proc.start,
                rule: "exact_on_state_changed",
                owner: proc.owner.clone(),
                proc: proc.name.clone(),
                var: None,
                kind: None,
            });
        }
    }
    for owner in &model.entry_order {
        for e in &model.entries[owner] {
            if starts_any(&e.rel, SKIP_SITE_DIRS) || raw_allowed(tree, sink, &e.rel, e.line) {
                continue;
            }
            let derive_names: HashSet<String> = model.declared_derive(owner).into_keys().collect();
            let relations = model.union(&model.relations, owner);
            let tracked = model.union(&model.tracked, owner);
            let mk = |rule: &'static str, var: String| Finding {
                rel: e.rel.clone(),
                line: e.line,
                rule,
                owner: owner.clone(),
                proc: String::new(),
                var: Some(var),
                kind: Some(e.kind.to_string()),
            };
            for link in &e.hops {
                if !relations.contains(link) {
                    findings.push(mk("hop_not_relation", link.clone()));
                }
            }
            for name in &e.local {
                if EXEMPT_VARS.contains(&name.as_str()) || tracked.contains(name) || derive_names.contains(name) || relations.contains(name) {
                    continue;
                }
                findings.push(mk("declared_untracked", name.clone()));
            }
            for (far_type, name) in &e.remote {
                let Some(far_type) = far_type.as_ref().filter(|t| !t.is_empty()) else { continue };
                if EXEMPT_VARS.contains(&name.as_str()) {
                    continue;
                }
                let far_ok = model.union(&model.tracked, far_type).contains(name)
                    || model.declared_derive(far_type).contains_key(name)
                    || model.union(&model.relations, far_type).contains(name);
                if !far_ok {
                    findings.push(mk("declared_untracked", format!("{}::{}", far_type, name)));
                }
            }
        }
    }
    findings.extend(reaction_findings(model, tree, sink));
    findings.sort_by(|a, b| {
        (a.rel.as_str(), a.line, a.rule, a.var.as_deref().unwrap_or("")).cmp(&(b.rel.as_str(), b.line, b.rule, b.var.as_deref().unwrap_or("")))
    });
    findings
}

// ---- presentation reactions -------------------------------------------------------------------

struct ReactionRead {
    kind: &'static str,
    handler: &'static str,
    proc: usize,
    reads: Vec<(String, usize)>,
}

fn reaction_reads(model: &Model) -> Vec<ReactionRead> {
    let mut byname: HashMap<&str, Vec<usize>> = HashMap::new();
    for (i, proc) in model.procs.iter().enumerate() {
        if proc.owner.starts_with(REACTION_OWNER_ROOT) && !starts_any(&proc.rel, GENERATED_SKIP_DIRS) && proc.rel != GENERATED_REL {
            byname.entry(proc.name.as_str()).or_default().push(i);
        }
    }
    let mut out = Vec::new();
    for (kind, handler, roots, skip) in REACTION_OUTPUTS {
        let mut names: HashSet<String> = roots.iter().map(|s| s.to_string()).collect();
        let mut todo: Vec<String> = roots.iter().map(|s| s.to_string()).collect();
        while let Some(t) = todo.pop() {
            for &pi in byname.get(t.as_str()).map(|v| v.as_slice()).unwrap_or(&[]) {
                for (_n, text) in &model.procs[pi].body {
                    for m in pat!(r"(?<![\w.])(?:src\.)?([A-Za-z_]\w*)\s*\(").captures_iter(text) {
                        let name = m.s(1);
                        if !names.contains(name) && byname.contains_key(name) && helper_name(name) {
                            names.insert(name.to_string());
                            todo.push(name.to_string());
                        }
                    }
                }
            }
        }
        let mut sorted: Vec<&String> = names.iter().collect();
        sorted.sort();
        for name in sorted {
            for &pi in byname.get(name.as_str()).map(|v| v.as_slice()).unwrap_or(&[]) {
                let proc = &model.procs[pi];
                let known = model.union(&model.vars, &proc.owner);
                let reads: Vec<(String, usize)> = body_reads(proc, &known).into_iter().filter(|(v, _)| !skip.contains(&v.as_str())).collect();
                out.push(ReactionRead { kind, handler, proc: pi, reads });
            }
        }
    }
    out
}

fn reaction_findings(model: &Model, tree: &Tree, sink: &mut Sink) -> Vec<Finding> {
    let mut findings = Vec::new();
    for r in reaction_reads(model) {
        let proc = &model.procs[r.proc];
        let mut tracked = model.union(&model.tracked, &proc.owner);
        tracked.extend(model.union(&model.relations, &proc.owner));
        tracked.extend(model.union(&model.object_vars, &proc.owner));
        for (name, line) in &r.reads {
            if tracked.contains(name) || EXEMPT_VARS.contains(&name.as_str()) || model.published_key(&proc.owner, name).is_some() {
                continue;
            }
            if raw_allowed(tree, sink, &proc.rel, *line) {
                continue;
            }
            findings.push(Finding {
                rel: proc.rel.clone(),
                line: *line,
                rule: "reaction_read_untracked",
                owner: proc.owner.clone(),
                proc: proc.name.clone(),
                var: Some(name.clone()),
                kind: Some(r.kind.to_string()),
            });
        }
    }
    findings
}

// ---- generated reads --------------------------------------------------------------------------

fn reaction_declarations(model: &Model) -> (BTreeMap<String, BTreeSet<&'static str>>, Vec<String>) {
    let mut flags: BTreeMap<String, BTreeSet<&'static str>> = BTreeMap::new();
    let mut members: BTreeSet<String> = BTreeSet::new();
    for proc in &model.procs {
        if proc.name != "reactions" || proc.owner == "/" || starts_any(&proc.rel, GENERATED_SKIP_DIRS) || proc.rel == GENERATED_REL {
            continue;
        }
        let text = proc.body.iter().map(|(_, l)| l.as_str()).collect::<Vec<_>>().join("\n");
        let mut pos = 0usize;
        loop {
            let Some(m) = pat!(r"(?<![\w.])(every|on_cross|on_notice)\s*\(").captures_at(&text, pos) else { break };
            let (inner, end) = paren_args(&text, m.end(0) - 1);
            pos = end;
            flags.entry(proc.owner.clone()).or_default().insert(reaction_kind_flag(m.s(1)));
            if m.s(1) == "every" {
                if let Some(f) = pat!(r"\bmembers\s*=\s*(/[\w/]+)").captures(inner) {
                    members.insert(f.s(1).to_string());
                }
            }
        }
    }
    (flags, members.into_iter().collect())
}

fn boot_text(model: &Model) -> Vec<String> {
    let (flags, members) = reaction_declarations(model);
    let mut out: Vec<String> = Vec::new();
    let mut push = |s: &str| out.push(s.to_string());
    push("/// Types whose reactions() declare every() / on_cross() / on_notice(), with the RXB_* kinds (code/datums/reactions/work.dm).");
    push("/proc/rx_boot_types()");
    push("\tRETURN_TYPE(/list)");
    push("\t// Built on first call: a static or global initializer may not have run yet when the first atoms initialize.");
    push("\t// ALLOW(sys_static_getter): built on first call; a global list may not exist yet while the first atoms initialize");
    push("\tvar/static/list/table");
    push("\tif(!table)");
    if !flags.is_empty() {
        push("\t\ttable = list(");
        for (owner, fl) in &flags {
            let joined = fl.iter().cloned().collect::<Vec<_>>().join(" | ");
            push(&format!("\t\t\t{} = {},", owner, joined));
        }
        push("\t\t)");
    } else {
        push("\t\ttable = list()");
    }
    push("\treturn table");
    push("");
    push("/// Capabilities some every(members = ...) runs per member of: their holders join the membership store at init.");
    push("/proc/rx_boot_members()");
    push("\tRETURN_TYPE(/list)");
    push("\t// ALLOW(sys_static_getter): built on first call; a global list may not exist yet while the first atoms initialize");
    push("\tvar/static/list/table");
    push("\tif(!table)");
    if !members.is_empty() {
        push("\t\ttable = list(");
        for cap in &members {
            push(&format!("\t\t\t{},", cap));
        }
        push("\t\t)");
    } else {
        push("\t\ttable = list()");
    }
    push("\treturn table");
    push("");
    out
}

/// The text of `code/_generated/reads.dm` for these files (the `derived_reads` generator, `analyze gen derived_reads`, writes it).
pub(crate) fn generated_for(tree: &Tree, files: &[&SourceFile]) -> String {
    generated_text(&Model::get(tree, files))
}

fn generated_text(model: &Model) -> String {
    // owner -> (kind, derive name or "") -> vars
    let mut per_owner: BTreeMap<String, BTreeMap<(String, String), Vec<String>>> = BTreeMap::new();
    let mut order: Vec<&Proc> = model.procs.iter().collect();
    order.sort_by(|a, b| (a.owner.as_str(), a.rel.as_str(), a.start).cmp(&(b.owner.as_str(), b.rel.as_str(), b.start)));
    for proc in order {
        if proc.owner == "/"
            || starts_any(&proc.rel, GENERATED_SKIP_DIRS)
            || proc.rel == GENERATED_REL
            || proc.owner.starts_with("/datum/capability")
        {
            continue;
        }
        // A system's window (SSair's) reads the system's own vars: the system boundary lint owns that, not the generated reads.
        if proc.name == "ui_data" && proc.owner.starts_with("/datum/system") {
            continue;
        }
        let mut kind = proc_kind(&proc.name).map(|k| k.to_string());
        let value = derive_value(&proc.name);
        if kind.is_none() && value.is_none() {
            continue;
        }
        let known = model.union(&model.vars, &proc.owner);
        if let Some(v) = value {
            if !known.contains(v) {
                continue;
            }
            kind = Some("derive".to_string());
        }
        let slot = per_owner
            .entry(proc.owner.clone())
            .or_default()
            .entry((kind.unwrap(), value.unwrap_or("").to_string()))
            .or_default();
        for (name, _) in body_reads(proc, &known) {
            if !slot.contains(&name) {
                slot.push(name);
            }
        }
    }
    // owner -> handler -> reads
    let mut reaction_slots: BTreeMap<String, BTreeMap<&'static str, Vec<String>>> = BTreeMap::new();
    for r in reaction_reads(model) {
        let proc = &model.procs[r.proc];
        let slot = reaction_slots.entry(proc.owner.clone()).or_default().entry(r.handler).or_default();
        for (name, _) in &r.reads {
            let read = match model.published_key(&proc.owner, name) {
                Some(k) => k,
                None => format!("nameof({})", name),
            };
            if !slot.contains(&read) {
                slot.push(read);
            }
        }
    }
    let mut out: Vec<String> = vec![
        "// GENERATED by tools/ci/derived_reads_lint.py --fix-generated. Do not edit by hand.".to_string(),
        "// What each type's should_run / draw / hidden_verbs / tgui_data / push_to_rust / derive_<x> read, as implicit".to_string(),
        "// reads for READERS() (code/datums/reactions). Not committed: every build regenerates it.".to_string(),
        String::new(),
    ];
    let owners: BTreeSet<&String> = per_owner.keys().chain(reaction_slots.keys()).collect();
    for owner in owners {
        let mut lines: Vec<String> = Vec::new();
        if let Some(slots) = per_owner.get(owner) {
            for ((kind, value), names) in slots {
                if names.is_empty() {
                    continue;
                }
                let mut sorted = names.clone();
                sorted.sort();
                let args = sorted.iter().map(|n| format!("nameof({})", n)).collect::<Vec<_>>().join(", ");
                if kind == "derive" {
                    lines.push(format!("\t. += derive(nameof({}), {})", value, args));
                } else {
                    lines.push(format!("\t. += {}({})", kind_call(kind).unwrap_or(""), args));
                }
            }
        }
        if let Some(handlers) = reaction_slots.get(owner) {
            for (handler, reads) in handlers {
                if !reads.is_empty() {
                    let mut sorted = reads.clone();
                    sorted.sort();
                    lines.push(format!("\t. += reaction_reads(PROC_REF({}), {})", handler, sorted.join(", ")));
                }
            }
        }
        if !lines.is_empty() {
            out.push(format!("{}/generated_reads()", owner));
            out.push("\t. = ..()".to_string());
            out.extend(lines);
            out.push(String::new());
        }
    }
    out.extend(boot_text(model));
    out.join("\n")
}

// ---- --fix (ported for the self-test only) ----------------------------------------------------

enum Op {
    Merge(String),
    After(String),
    Before(Vec<String>),
}

fn fix_texts(model: &Model, tree: &Tree, findings: &[Finding]) -> BTreeMap<String, String> {
    type Key = (String, String, Option<String>);
    let mut wanted: Vec<(Key, Vec<String>)> = Vec::new();
    for f in findings {
        if f.rule != "undeclared_read" {
            continue;
        }
        let kind = f.kind.clone().unwrap_or_default();
        let derive_name = if kind == "derive" { Some(f.proc["derive_".len()..].to_string()) } else { None };
        let key: Key = (f.owner.clone(), kind, derive_name);
        let pos = match wanted.iter().position(|(k, _)| *k == key) {
            Some(p) => p,
            None => {
                wanted.push((key, Vec::new()));
                wanted.len() - 1
            }
        };
        let var = f.var.clone().unwrap_or_default();
        if !wanted[pos].1.contains(&var) {
            wanted[pos].1.push(var);
        }
    }
    let mut by_owner: Vec<(String, Vec<(String, Option<String>, Vec<String>)>)> = Vec::new();
    for ((owner, kind, derive_name), names) in wanted {
        match by_owner.iter_mut().find(|(o, _)| *o == owner) {
            Some((_, v)) => v.push((kind, derive_name, names)),
            None => by_owner.push((owner, vec![(kind, derive_name, names)])),
        }
    }
    let raw_lines_of = |rel: &str| -> Vec<String> { tree.get(rel).map(|f| f.text().split('\n').map(|s| s.to_string()).collect()).unwrap_or_default() };
    let mut edits: BTreeMap<String, Vec<(usize, Op)>> = BTreeMap::new();
    for (owner, wants) in &by_owner {
        if let Some(&bi) = model.derived_procs.get(owner) {
            let block = &model.procs[bi];
            let raw_lines = raw_lines_of(&block.rel);
            for (kind, derive_name, names) in wants {
                let call = if kind == "derive" { "derive" } else { kind_call(kind).unwrap_or("") };
                let head = Pat::new_match(&format!(r"(\s*\. \+= ({})\()(.*)\)\s*$", call));
                let mut target: Option<(usize, String, String)> = None;
                for (number, _) in &block.body {
                    let text = raw_lines.get(number - 1).map(|s| s.as_str()).unwrap_or("");
                    if let Some(m) = head.captures(text) {
                        let ok = kind != "derive"
                            || Pat::new_match(&format!(r"nameof\(\s*(?:/[\w/]+::)?{}\s*\)", derive_name.as_deref().unwrap_or(""))).is_match(m.s(3));
                        if ok {
                            target = Some((*number, m.s(1).to_string(), m.s(3).to_string()));
                            break;
                        }
                    }
                }
                let extra = names.iter().map(|n| format!("nameof({})", n)).collect::<Vec<_>>().join(", ");
                if let Some((number, g1, g3)) = target {
                    edits.entry(block.rel.clone()).or_default().push((number, Op::Merge(format!("{}{}, {})", g1, g3, extra))));
                } else {
                    let line = match kind_call(kind) {
                        Some(c) => format!("\t. += {}({})", c, extra),
                        None => format!("\t. += derive(nameof({}), {})", derive_name.as_deref().unwrap_or(""), extra),
                    };
                    edits.entry(block.rel.clone()).or_default().push((block.body.last().unwrap().0, Op::After(line)));
                }
            }
        } else {
            let first = model
                .procs
                .iter()
                .filter(|p| p.owner == *owner && (proc_kind(&p.name).is_some() || p.name.starts_with("derive_")))
                .min_by(|a, b| (a.rel.as_str(), a.start).cmp(&(b.rel.as_str(), b.start)));
            let Some(first) = first else { continue };
            let mut lines = vec![format!("{}/derived()", owner), "\t. = ..()".to_string()];
            for (kind, derive_name, names) in wants {
                let extra = names.iter().map(|n| format!("nameof({})", n)).collect::<Vec<_>>().join(", ");
                if kind == "derive" {
                    lines.push(format!("\t. += derive(nameof({}), {})", derive_name.as_deref().unwrap_or(""), extra));
                } else {
                    lines.push(format!("\t. += {}({})", kind_call(kind).unwrap_or(""), extra));
                }
            }
            lines.push(String::new());
            edits.entry(first.rel.clone()).or_default().push((first.start, Op::Before(lines)));
        }
    }
    let mut out = BTreeMap::new();
    for (rel, mut todo) in edits {
        let mut raw_lines = raw_lines_of(&rel);
        todo.sort_by_key(|(n, _)| std::cmp::Reverse(*n));
        for (number, op) in todo {
            match op {
                Op::Merge(p) => raw_lines[number - 1] = p,
                Op::After(p) => {
                    let at = number.min(raw_lines.len());
                    raw_lines.insert(at, p);
                }
                Op::Before(p) => {
                    let at = (number - 1).min(raw_lines.len());
                    raw_lines.splice(at..at, p);
                }
            }
        }
        out.insert(rel, raw_lines.join("\n"));
    }
    out
}

// ---- the lint ---------------------------------------------------------------------------------

struct DerivedReads;

impl Lint for DerivedReads {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files = cx.files();
        let model = Model::get(cx.tree, &files);
        let ui_hosts = cx.list("ui_hosts").to_vec();
        for f in analyze(&model, cx.tree, out, true, &ui_hosts) {
            out.site_in(f.rule, &f.rel, f.line);
        }
    }

    fn post_judge(&self, cx: &Cx, _run: &Run, text: &mut String) -> bool {
        let files = cx.files();
        let model = Model::get(cx.tree, &files);
        let want = generated_text(&model);
        let current = cx.tree.read_extra(GENERATED_REL);
        if current.as_deref().map(|s| s.as_str()) != Some(want.as_str()) {
            let _ = writeln!(
                text,
                "derived_reads: {} is stale; run `analyze gen derived_reads` and commit it",
                GENERATED_REL
            );
            return true;
        }
        false
    }

    fn selftest(&self) -> Result<String, String> {
        selftest()
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/derived_reads_lint.py"],
            old_raw: &[],
            blank: &["tools/ci/derived_reads_baseline.txt"],
            parse: ParseKind::Tagged,
            update: Some(&["tools/ci/derived_reads_lint.py", "--update"]),
            seed: Some(&["tools/ci/derived_reads_lint.py", "--seed"]),
            files: &["tools/ci/derived_reads_baseline.txt"],
            selftest: Some(&["tools/ci/derived_reads_lint.py", "--selftest"]),
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(DerivedReads);
}

// ---- self-test --------------------------------------------------------------------------------

const FIXTURE_BASE: &str = "
/obj/pointer
»var/energy = 8
»var/max_energy = 8
»var/pointing = FALSE
»var/spare = 0

TRACKED(/obj/pointer, energy)
TRACKED(/obj/pointer, pointing)

/obj/pointer/should_run()
»return energy < max_energy

/obj/pointer/draw(datum/look/look)
»..()
»if(pointing)
»»look.state(\"on\")
";

const FIXTURE_DECLARED_TAIL: &str = "
/obj/pointer/derived()
». = ..()
». += runs_while(nameof(energy), nameof(max_energy))
». += drawn_from(nameof(pointing))
";

const FIXTURE_SUBTYPE_TAIL: &str = "
/obj/pointer/big
»var/glow = FALSE

/obj/pointer/big/draw(datum/look/look)
»..()
»if(pointing && glow)
»»look.state(\"big\")

/obj/pointer/big/derived()
». = ..()
». += drawn_from(nameof(glow))
";

const FIXTURE_MISC: &str = "
/obj/thing
»var/level = 0
»var/extra = 0
»var/total = 0
»var/spare = 0
»var/obj/thing/parent
»var/list/kids

TRACKED(/obj/thing, level)
REL(/obj/thing, parent)

/obj/thing/derived()
». = ..()
». += derive(nameof(total), nameof(level))
». += drawn_from(nameof(total), nameof(spare), rel(nameof(parent), nameof(/obj/thing::level)), rel(nameof(kids), nameof(/obj/thing::mystery)))
». += ui_from(nameof(cap_state))

/obj/thing/derive_total()
»return level + extra

/obj/thing/on_state_changed(bits)
»return

/obj/thing/tgui_data(mob/user)
»var/level = 5
»// ALLOW(derived_reads): fixture keep
». = list(\"level\" = level, \"n\" = total)
». += total
";

fn tabs(s: &str) -> String {
    s.replace('»', "\t")
}

fn model_of(texts: &[(&str, String)]) -> (Tree, Model) {
    let tree = Tree::from_files(texts.iter().map(|(rel, t)| SourceFile::from_text(rel, t)).collect());
    let files: Vec<&SourceFile> = tree.files.iter().collect();
    let model = Model::build(&files);
    (tree, model)
}

fn run_analyze(texts: &[(&str, String)]) -> (Tree, Model, Vec<Finding>) {
    let (tree, model) = model_of(texts);
    let mut sink = Sink::new();
    let found = analyze(&model, &tree, &mut sink, false, &["/obj/panel".to_string()]);
    (tree, model, found)
}

fn undeclared(found: &[Finding]) -> Vec<&Finding> {
    found.iter().filter(|f| f.rule == "undeclared_read").collect()
}

fn selftest() -> Result<String, String> {
    let mut bad: Vec<String> = Vec::new();
    let mut check = |name: &str, ok: bool, detail: String| {
        if !ok {
            bad.push(format!("{} {}", name, detail));
        }
    };
    let base = tabs(FIXTURE_BASE);
    let declared = format!("{}{}", base, tabs(FIXTURE_DECLARED_TAIL));
    let subtype = format!("{}{}", declared, tabs(FIXTURE_SUBTYPE_TAIL));
    let tr = |f: &Finding| (f.rule, f.var.clone(), f.proc.clone());
    // 1
    let (_, _, found) = run_analyze(&[("code/a.dm", base.clone())]);
    let got: Vec<_> = found.iter().map(tr).collect();
    check(
        "missing declaration",
        got.contains(&("undeclared_read", Some("energy".into()), "should_run".into())) && got.contains(&("undeclared_read", Some("pointing".into()), "draw".into())),
        format!("{:?}", got),
    );
    check(
        "only the read vars",
        found.iter().all(|f| matches!(f.var.as_deref(), Some("energy" | "pointing" | "max_energy"))),
        format!("{:?}", got),
    );
    // 2
    let (_, _, found) = run_analyze(&[("code/a.dm", declared.clone())]);
    check("declared is clean", undeclared(&found).is_empty(), format!("{:?}", found));
    let (_, _, found) = run_analyze(&[("code/a.dm", subtype.clone())]);
    check("inherited declarations", undeclared(&found).is_empty(), format!("{:?}", found));
    // 3
    let text = subtype.replace("\t. += drawn_from(nameof(glow))\n", "");
    let (tree, model, found) = run_analyze(&[("code/a.dm", text.clone())]);
    let got: Vec<_> = found.iter().map(|f| (f.rule, f.var.clone())).collect();
    check("subtype missing", got.contains(&("undeclared_read", Some("glow".into()))), format!("{:?}", got));
    // 4
    let fixed = fix_texts(&model, &tree, &found);
    check("fix edits the derived block", fixed.get("code/a.dm").map(|t| t.contains("drawn_from(nameof(glow))")).unwrap_or(false), format!("{:?}", fixed));
    let fixed_in: Vec<(&str, String)> = fixed.iter().map(|(k, v)| (k.as_str(), v.clone())).collect();
    let (t2, m2, again) = run_analyze(&fixed_in);
    check("fixed text is clean", !fixed.is_empty() && undeclared(&again).is_empty(), format!("{:?}", again));
    check("fix is stable", fix_texts(&m2, &t2, &again).is_empty(), String::new());
    // 5
    let (tree, model, found) = run_analyze(&[("code/a.dm", base.clone())]);
    let fixed = fix_texts(&model, &tree, &found);
    check("fix creates the block", fixed.get("code/a.dm").map(|t| t.contains("/obj/pointer/derived()")).unwrap_or(false), format!("{:?}", fixed));
    let fixed_in: Vec<(&str, String)> = fixed.iter().map(|(k, v)| (k.as_str(), v.clone())).collect();
    let (_, _, again) = run_analyze(&fixed_in);
    check("created block is clean", undeclared(&again).is_empty(), format!("{:?}", again));
    // 6
    let (_, _, found) = run_analyze(&[("code/b.dm", tabs(FIXTURE_MISC))]);
    let rules: HashSet<(&str, Option<String>)> = found.iter().map(|f| (f.rule, f.var.clone())).collect();
    let has = |r: &str, v: Option<&str>| rules.iter().any(|(rr, vv)| *rr == r && vv.as_deref() == v);
    check("hop through a plain var", has("hop_not_relation", Some("kids")), format!("{:?}", rules));
    check("relation hop is fine", !has("hop_not_relation", Some("parent")), format!("{:?}", rules));
    check("untracked declared var", has("declared_untracked", Some("spare")), format!("{:?}", rules));
    check("untracked remote var", has("declared_untracked", Some("/obj/thing::mystery")), format!("{:?}", rules));
    check(
        "tracked, derived and exempt reads are fine",
        !has("declared_untracked", Some("total")) && !has("declared_untracked", Some("cap_state")) && !has("declared_untracked", Some("level")),
        format!("{:?}", rules),
    );
    check("exact type overriding on_state_changed", has("exact_on_state_changed", None), format!("{:?}", rules));
    check(
        "derive body read past its reads",
        has("undeclared_read", Some("extra")) && found.iter().any(|f| f.rule == "undeclared_read" && f.proc == "derive_total"),
        format!("{:?}", rules),
    );
    // 7
    check("locals and ALLOW", !found.iter().any(|f| f.rule == "undeclared_read" && f.proc == "tgui_data"), format!("{:?}", found));
    // 8
    let (_, _, found) = run_analyze(&[("code/a.dm", base.clone())]);
    check("legacy type reports", found.iter().any(|f| f.rule == "undeclared_read"), String::new());
    // 9
    let (_, model) = model_of(&[("code/a.dm", declared.clone())]);
    let text = generated_text(&model);
    check(
        "generated reads",
        text.contains("/obj/pointer/generated_reads()")
            && text.contains("runs_while(nameof(energy), nameof(max_energy))")
            && text.contains("drawn_from(nameof(pointing))"),
        text.clone(),
    );
    let (_, model2) = model_of(&[("code/a.dm", declared.clone())]);
    check("generated is stable", generated_text(&model2) == text, String::new());
    // 11: a window host's ui_data() reads must be tracked
    let ui_fixture = tabs("
/obj/panel
»var/screen = 1
»var/label = \"x\"
»var/obj/thing/target
»var/note = \"\"

TRACKED(/obj/panel, screen)
REL(/obj/panel, target)

/obj/panel/ui_data(datum/act/eval/A)
»var/note = 3
»return list(\"screen\" = screen, \"label\" = label, \"t\" = target, \"n\" = note)
");
    let (_, _, found) = run_analyze(&[("code/a.dm", ui_fixture)]);
    let ui_got: Vec<_> = found.iter().filter(|f| f.rule == "untracked_ui_read").map(|f| f.var.clone()).collect();
    check("ui_data untracked read is flagged", ui_got == vec![Some("label".to_string())], format!("{:?}", ui_got));
    // 10
    let fixture = "/obj/pump/reactions()\n\t. = ..()\n\t. += every(1 SECONDS, PROC_REF(step), members = /datum/capability/pumped)\n\t. += on_notice(/datum/notice/x, PROC_REF(h))\n".to_string();
    let (_, model) = model_of(&[("code/a.dm", fixture)]);
    let boot = generated_text(&model);
    check("boot types", boot.contains("/obj/pump = RXB_EVERY | RXB_NOTICE,") && boot.contains("/datum/capability/pumped,"), boot);
    if bad.is_empty() {
        Ok("derived_reads_lint selftest passed".to_string())
    } else {
        Err(bad.join("; "))
    }
}
