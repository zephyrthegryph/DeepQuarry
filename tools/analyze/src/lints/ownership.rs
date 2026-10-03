//! Port of `tools/ci/ownership_lint.py` `main()` (doc/rewrite/ownership.md sec 7-8): the static half
//! of own / shared / proto / relation. The structure index (`Index`, `proc_scopes`, the write
//! regexes) is `dm::ownership_index`; this file builds the accessor-usage map and runs the checks:
//!
//! * `unknown_var`  an accessor naming a var the receiver's type does not have
//! * `string_name`  an accessor naming its var with a string literal (`nameof()` instead)
//! * `kinds`        one kind per var across the hierarchy
//! * `matrix`       OWN / REL of a registry type, SHARED of a non-registry type, a gas mixture written
//!                  as a relation, SPILL / CONTAINED on a non-movable var type
//! * `contradiction` one var written as owned and as a relation, or against its declaration
//! * `removed`      the deleted declaration forms
//! * `callback`     `CALLBACK(` outside the core
//! * `handle`       `om_handle()` / `om_resolve()` / a `*_handle` var outside the core
//! * `raw_write`    an entity var written outside the ownership accessors
//!
//! Every problem fails (`Policy::Hard`; the check name is the rule). Paths under the `[lint.ownership]`
//! exemptions of `lint_scopes.toml` (unit tests, benchmarks, vendored TGS: `allow_annotations.exempt_path`)
//! are skipped by `string_name`, `removed`, `callback`, `handle` and `raw_write` only: the index, the
//! usage map, `unknown_var`, `kinds`, `matrix` and `contradiction` read every file.
//!
//! Quirks kept (the Python is the oracle):
//! * `ACCESSOR` / `TRANSFER_DEST` and the string-name check read the RAW line at the CODE view's line
//!   number (a trailing comment on a proc-body line still counts; an unbalanced `'` in the code view
//!   drifts the numbers, exactly as in the Python);
//! * `unknown_var` has no ALLOW and no exemption;
//! * SUSPECTED BUGS in the Python, kept: the `string_name` confirmation regex and `OBJ_TOKEN` were committed
//!   with a literal backspace byte where `\b` was meant. The first makes `string_name` fire only on a line
//!   with a U+0008 before the call name (see `file_checks`); the second is harmless (`new\x08` never matches,
//!   the identifier alternative matches `new` instead, the same token the shared index gets from `new`);
//! * a receiver type that is `""` (an untyped member) is as good as None everywhere the Python tests
//!   its truthiness, so both are stored as `""`;
//! * the Python keeps the usage as hash-ordered sets, so which of several `rel_*` sites a `contradiction`
//!   is reported at (the first match, then `break`) is not stable between Python runs; here the sets are
//!   sorted by `(receiver type, file, line)`.

use std::collections::{BTreeSet, HashMap};
use std::sync::{Arc, RwLock};

use serde::{Deserialize, Serialize};

use crate::dm::ownership_index::{self as oi,
    creates_entity, proc_scopes, puts_object, receiver_type, related, Index, OrdMap, ACCESSOR, CALLBACK, CALLBACK_OK, CORE_DIRS, ENTITY_ROOTS, HANDLE_CALL,
    HANDLE_OK, HANDLE_VAR, OBJLIST_WRITES, OWN_FUNCS, PROTO_FUNCS, REL_FUNCS, REL_WRITERS, REMOVED, STRING_NAME, TRANSFER_DEST, WRITE_ASSIGN, WRITE_INDEX,
    WRITE_MACRO, WRITE_METHOD,
};
use crate::incr;
use crate::lint::{AllowUse, Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat;
use crate::tree::{SourceFile, CODE_DM};
use crate::util::{before_slashes, py_lstrip, py_rstrip, py_strip, starts_with_any, under};

const LINT: &str = "ownership";

const H_RAW_WRITE: &str = "write it through own_* / rel_* / proto_* (doc/rewrite/ownership.md), or keep with // ALLOW(ownership): <reason>";
const H_CONTRADICTION: &str = "one var is one kind: write it through one accessor family that matches its declaration";
const H_KINDS: &str = "related types must declare the same kind for a var";
const H_MATRIX: &str = "a registry type is SHARED, a per-holder copy is PROTO, and a holder owns its gas mixture";
const H_CALLBACK: &str = "defer with om_after(), which holds arguments as handles";
const H_HANDLE: &str = "a content var naming an entity is a relation view: use rel_set()";
const H_UNKNOWN_VAR: &str = "name a var the receiver's type declares, with nameof()";
const H_STRING_NAME: &str = "name the var with nameof(var), nameof(x.var) or nameof(/type::var)";
const H_REMOVED: &str = "use the ownership() / relations() declarations (doc/rewrite/ownership.md)";

static META: Meta = Meta {
    name: "ownership",
    group: "",
    label: "ownership",
    legacy: "tools/ci/ownership_lint.py",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "raw_write", hint: H_RAW_WRITE },
        RuleMeta { name: "contradiction", hint: H_CONTRADICTION },
        RuleMeta { name: "kinds", hint: H_KINDS },
        RuleMeta { name: "matrix", hint: H_MATRIX },
        RuleMeta { name: "callback", hint: H_CALLBACK },
        RuleMeta { name: "handle", hint: H_HANDLE },
        RuleMeta { name: "unknown_var", hint: H_UNKNOWN_VAR },
        RuleMeta { name: "string_name", hint: H_STRING_NAME },
        RuleMeta { name: "removed", hint: H_REMOVED },
    ],
    allow: &["ownership"],
    lists: &[],
};

/// `decl_kind_of`: an old declaration macro name -> the kind it declares (ANNOTATE and the rest: none).
fn decl_kind_of(macro_name: &str) -> Option<&'static str> {
    match macro_name {
        "OWN" | "OWN_POLICY" | "OWN_IF" => Some("OWN"),
        "SHARED" => Some("SHARED"),
        "PROTO" => Some("PROTO"),
        "REL" | "REL_LIST" | "REL_PAIR" | "REL_PAIR_LIST" | "REL_SET" | "REL_KEYED" | "REL_KEYED_LIST" => Some("REL"),
        _ => None,
    }
}

/// `"entity"` (a single entity var) or `"list"` (an entity list).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Vk {
    Entity,
    List,
}

/// `(receiver type or "", file, line)`: one accessor write. An unknown receiver type is `""`.
type Loc = (String, String, usize);

#[derive(Default)]
struct UsageKinds {
    own: BTreeSet<Loc>,
    /// `rel_link` / `rel_unlink`: a true relation write.
    rel: BTreeSet<Loc>,
    /// `rel_set` / `rel_add` / `rel_remove` / `rel_clear`: the writers that replace `own_*`. They count as
    /// an owner's write (no contradiction with `own_*`, no gas-mixture matrix hit) and are also accepted on a REL var.
    relw: BTreeSet<Loc>,
    proto: BTreeSet<Loc>,
    shared: BTreeSet<Loc>,
}

struct Problem {
    check: &'static str,
    rel: String,
    line: usize,
    msg: String,
}

/// Check names a cached per-line result stores by index.
const LINE_CHECKS: [&str; 3] = ["removed", "callback", "handle"];

/// What the accessor-usage pass finds in one file (kinds: 0 OWN, 1 REL link, 2 PROTO, 3 SHARED, 4 REL writer).
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct UsageScan {
    /// `(var name, kind index, receiver type or "", line)` in discovery order
    events: Vec<(String, u8, String, u32)>,
    /// `unknown_var` reports `(line, message)`
    unknown: Vec<(u32, String)>,
}

/// One file's index-independent per-line results (`string_name`, `removed`, `callback`, `handle`).
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Content {
    string_name: Vec<(u32, String)>,
    /// `(LINE_CHECKS index, line, message)`
    lines: Vec<(u8, u32, String)>,
    uses: Vec<AllowUse>,
}

/// One file's `raw_write` results.
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct RawOut {
    lines: Vec<(u32, String)>,
    uses: Vec<AllowUse>,
}

fn usage_scan(idx: &Index, f: &SourceFile) -> UsageScan {
    let raw = f.raw();
    let mut sc = UsageScan::default();
    proc_scopes(f.code(), |no, _line, owner, _proc, local_types| {
        let rl = raw.line(no);
        for m in ACCESSOR.captures_iter(rl) {
            let (func, recv, name) = (m.s(1), m.s(2), m.s(3));
            let mut rtype: Option<String> =
                if recv == "src" { Some(owner.to_string()) } else { local_types.get(recv).and_then(|t| t.clone()) };
            if rtype.is_none() && recv != "src" {
                rtype = idx.member(owner, recv).map(|g| g.vtype);
            }
            let rtype = rtype.unwrap_or_default();
            let kind: u8 = if OWN_FUNCS.contains(&func) {
                0
            } else if REL_FUNCS.contains(&func) {
                if REL_WRITERS.contains(&func) {
                    4
                } else {
                    1
                }
            } else if PROTO_FUNCS.contains(&func) {
                2
            } else {
                3
            };
            sc.events.push((name.to_string(), kind, rtype.clone(), no as u32));
            // The var named by the string must exist: on the receiver's type when it is known, else
            // on some type (a string var name can't be checked by the compiler).
            if !rtype.is_empty() && under(&rtype, ENTITY_ROOTS) {
                let prefix = format!("{}/", rtype);
                let on_subtype = idx.name_decls.get(name).map(|v| v.iter().any(|(t, _, _)| t.starts_with(&prefix))).unwrap_or(false);
                if idx.member(&rtype, name).is_none() && !on_subtype {
                    sc.unknown.push((no as u32, format!("{}({}, \"{}\"): {} has no var {}", func, recv, name, rtype, name)));
                }
            } else if idx.name_decls.get(name).map(|v| v.is_empty()).unwrap_or(true) {
                sc.unknown.push((no as u32, format!("{}({}, \"{}\"): no type declares a var {}", func, recv, name, name)));
            }
        }
        for m in TRANSFER_DEST.captures_iter(rl) {
            let (recv, name) = (m.s(1), m.s(2));
            let rtype: String = if recv == "src" { owner.to_string() } else { local_types.get(recv).and_then(|t| t.clone()).unwrap_or_default() };
            sc.events.push((name.to_string(), 0, rtype, no as u32));
        }
    });
    sc
}

/// Everything the per-line checks need, shared across the file workers.
struct Ctx {
    idx: Arc<Index>,
    usage: OrdMap<UsageKinds>,
    vk_cache: RwLock<HashMap<(String, String), (Option<Vk>, Option<String>)>>,
    amb_cache: RwLock<HashMap<String, Option<Vk>>>,
}

impl Ctx {
    fn is_shared_decl(&self, rtype: &str, name: &str) -> bool {
        match self.idx.decl(rtype, name) {
            Some((_, d)) => decl_kind_of(&d.macro_name) == Some("SHARED"),
            None => false,
        }
    }

    /// `var_kind(owner_type, name)`: `Entity` for a single entity var, `List` for an entity list, None
    /// otherwise; plus the declaring type.
    fn var_kind(&self, owner_type: &str, name: &str) -> (Option<Vk>, Option<String>) {
        let key = (owner_type.to_string(), name.to_string());
        if let Some(v) = self.vk_cache.read().unwrap().get(&key) {
            return v.clone();
        }
        let v = self.var_kind_uncached(owner_type, name);
        self.vk_cache.write().unwrap().insert(key, v.clone());
        v
    }

    fn var_kind_uncached(&self, owner_type: &str, name: &str) -> (Option<Vk>, Option<String>) {
        let idx = &self.idx;
        let Some(got) = idx.member(owner_type, name) else { return (None, None) };
        let (dtype, vtype, is_list) = (got.declared_on, got.vtype, got.is_list);
        let dkind = idx.decl(owner_type, name).and_then(|(_, d)| decl_kind_of(&d.macro_name));
        if dkind == Some("SHARED") {
            return (None, Some(dtype));
        }
        if matches!(dkind, Some("OWN") | Some("REL") | Some("PROTO")) {
            return (Some(if is_list || vtype.is_empty() { Vk::List } else { Vk::Entity }), Some(dtype));
        }
        if let Some(used) = self.usage.get(name) {
            for set in [&used.own, &used.rel, &used.relw, &used.proto] {
                for (t, _, _) in set {
                    // The usage must name this same var: its receiver resolves the member to the same
                    // declaring type (not merely a related type with a same-named var).
                    if !t.is_empty() && related(t, owner_type) {
                        if let Some(gt) = idx.member(t, name) {
                            if gt.declared_on == dtype {
                                return (Some(if is_list { Vk::List } else { Vk::Entity }), Some(dtype));
                            }
                        }
                    }
                }
            }
        }
        if is_list {
            return (if idx.is_entity(&vtype) { Some(Vk::List) } else { None }, Some(dtype));
        }
        (if idx.is_entity(&vtype) { Some(Vk::Entity) } else { None }, Some(dtype))
    }

    /// `unknown_receiver_kind(name)`: for an untyped receiver, the kind when every declaration of
    /// `name` agrees.
    fn unknown_receiver_kind(&self, name: &str) -> Option<Vk> {
        if let Some(v) = self.amb_cache.read().unwrap().get(name) {
            return *v;
        }
        let mut kinds: Vec<Option<Vk>> = Vec::new();
        if let Some(decls) = self.idx.name_decls.get(name) {
            for (t, _, _) in decls {
                let (k, _) = self.var_kind(t, name);
                if !kinds.contains(&k) {
                    kinds.push(k);
                }
            }
        }
        let v = if kinds.len() == 1 { kinds[0] } else { None };
        self.amb_cache.write().unwrap().insert(name.to_string(), v);
        v
    }
}

/// The index-independent checks of one file (`string_name`, `removed`, `callback`, `handle`).
fn content_checks(f: &SourceFile) -> Content {
    let mut sink = Sink::new();
    sink.cur = f.rel.clone();
    let mut res = Content::default();
    let raw = f.raw();
    let code = f.code();
    let rel = f.rel.as_str();

    // string_name: code_only() blanks string contents, so match the raw line where the code line has a call.
    for (no, line) in code.numbered() {
        if !line.contains('(') {
            continue;
        }
        let Some(hit) = STRING_NAME.captures(before_slashes(raw.line(no))) else { continue };
        let name = if hit.s(1).is_empty() { hit.s(2) } else { hit.s(1) };
        // The call itself must be code (a name inside a string or comment is blanked in `line`).
        // SUSPECTED BUG, kept: the Python's `re.search(r"\b%s\(" % name, line)` was committed with a literal
        // backspace byte (0x08) where `\b` belongs, so it needs a U+0008 right before the name and
        // string_name fires only on a line that carries one (never, in the real tree).
        if line.contains(&format!("\u{8}{}(", name)) && !sink.allowed(f, no, LINT) {
            res.string_name.push((no as u32, format!("{}(): name the var with nameof(), not a string", name)));
        }
    }

    // removed / callback / handle
    for no in 1..=raw.num_lines() {
        let c = code.line(no);
        if let Some(m) = REMOVED.find(c) {
            if !rel.starts_with("tools/") && !sink.allowed(f, no, LINT) {
                res.lines.push((0, no as u32, format!("{} was removed (doc/rewrite/ownership.md)", m.as_str())));
            }
        }
        if CALLBACK.is_match(c) && !starts_with_any(rel, CALLBACK_OK) && !sink.allowed(f, no, LINT) {
            res.lines.push((1, no as u32, "CALLBACK outside the core: use om_after() (arguments held as handles)".to_string()));
        }
        if !starts_with_any(rel, HANDLE_OK) {
            if let Some(m) = HANDLE_CALL.captures(c) {
                if !sink.allowed(f, no, LINT) {
                    res.lines.push((2, no as u32, format!("om_{}() in content: a var naming an entity is a relation view (rel_set)", m.s(1))));
                }
            }
            if let Some(hm) = HANDLE_VAR.captures(c) {
                if !sink.allowed(f, no, LINT) {
                    let var = if hm.s(1).is_empty() { hm.s(3) } else { hm.s(1) };
                    res.lines.push((2, no as u32, format!("var {}: a content var naming an entity is a relation view, not a handle", var)));
                }
            }
        }
    }
    res.uses = sink.allow_used;
    res
}

/// The `raw_write` check of one file (outside the core directories).
fn raw_checks(cx: &Ctx, f: &SourceFile) -> RawOut {
    let mut res = RawOut::default();
    if starts_with_any(f.rel.as_str(), CORE_DIRS) {
        return res;
    }
    let mut sink = Sink::new();
    sink.cur = f.rel.clone();
    let mut problems: Vec<Problem> = Vec::new();
    raw_writes(cx, f, &mut sink, &mut problems);
    res.lines = problems.into_iter().map(|p| (p.line as u32, p.msg)).collect();
    res.uses = sink.allow_used;
    res
}

/// One candidate write found on a proc-body line: `(receiver chain, var, how, text after it)`.
struct Hit {
    chain: String,
    name: String,
    how: String,
    rhs: String,
}

fn raw_writes(cx: &Ctx, f: &SourceFile, sink: &mut Sink, problems: &mut Vec<Problem>) {
    let idx = &*cx.idx;
    let rel = f.rel.as_str();
    proc_scopes(f.code(), |no, line, owner, proc, local_types| {
        let mut hits: Vec<Hit> = Vec::new();
        for m in WRITE_ASSIGN.captures_iter(line) {
            let (chain, name, op) = (m.s(1), m.s(2), m.s(3));
            let (start, end) = (m.start(0), m.end(0));
            let before = py_rstrip(&line[..start]);
            if before.ends_with("var") || pat!(r"var/(?:[\w/]+/)?$").is_match(&line[..start]) {
                continue;
            }
            if chain.is_empty() && (before.ends_with('(') || before.ends_with(',')) {
                continue; // a named argument or an assoc key in list(...)
            }
            if chain.is_empty() && local_types.contains_key(name) {
                continue;
            }
            if op == "=" && py_lstrip(&line[end..]).starts_with('=') {
                continue;
            }
            hits.push(Hit { chain: chain.to_string(), name: name.to_string(), how: op.to_string(), rhs: line[end..].to_string() });
        }
        for m in WRITE_INDEX.captures_iter(line) {
            if m.s(1).is_empty() && local_types.contains_key(m.s(2)) {
                continue;
            }
            let whole = &line[m.start(0)..m.end(0)];
            let (a, b) = (whole.find('[').map(|i| i + 1).unwrap_or(0), whole.rfind(']').unwrap_or(whole.len()));
            let inner = if a <= b { &whole[a..b] } else { "" };
            hits.push(Hit {
                chain: m.s(1).to_string(),
                name: m.s(2).to_string(),
                how: "[]=".to_string(),
                rhs: format!("{} {}", inner, &line[m.end(0)..]),
            });
        }
        for m in WRITE_METHOD.captures_iter(line) {
            if m.s(1).is_empty() && local_types.contains_key(m.s(2)) {
                continue;
            }
            hits.push(Hit { chain: m.s(1).to_string(), name: m.s(2).to_string(), how: format!(".{}", m.s(3)), rhs: line[m.end(0)..].to_string() });
        }
        for m in WRITE_MACRO.captures_iter(line) {
            if m.s(2).is_empty() && local_types.contains_key(m.s(3)) {
                continue;
            }
            hits.push(Hit { chain: m.s(2).to_string(), name: m.s(3).to_string(), how: m.s(1).to_string(), rhs: line[m.end(0)..].to_string() });
        }
        for h in &hits {
            if matches!(
                h.name.as_str(),
                "src" | "usr" | "loc" | "contents" | "vars" | "overlays" | "underlays" | "vis_contents" | "verbs" | "screen" | "images"
            ) {
                continue;
            }
            let rtype = receiver_type(idx, &h.chain, owner, local_types).filter(|t| !t.is_empty());
            let mut kind = match &rtype {
                Some(rt) => cx.var_kind(rt, &h.name).0,
                None if !h.chain.is_empty() => cx.unknown_receiver_kind(&h.name),
                None => continue,
            };
            if kind.is_none() && h.how == "=" && creates_entity(&h.rhs) {
                if let Some(rt) = &rtype {
                    // A member var assigned a new entity: whatever its declared type, the holder made
                    // it, so it owns it (own_set), unless declared otherwise.
                    if idx.member(rt, &h.name).is_some() && !cx.is_shared_decl(rt, &h.name) {
                        kind = Some(Vk::Entity);
                    }
                }
            }
            if kind.is_none() && OBJLIST_WRITES.contains(&h.how.as_str()) && puts_object(&h.rhs, local_types, &idx.registry) {
                if let Some(rt) = &rtype {
                    // An untyped list var collecting entities (src, a new object, an entity-typed local):
                    // an object-keyed roster, which is an owned or relation list.
                    if let Some(g) = idx.member(rt, &h.name) {
                        if g.is_list && !cx.is_shared_decl(rt, &h.name) {
                            kind = Some(Vk::List);
                        }
                    }
                }
            }
            let Some(kind) = kind else { continue };
            if sink.allowed(f, no, LINT) {
                continue;
            }
            problems.push(Problem {
                check: "raw_write",
                rel: rel.to_string(),
                line: no,
                msg: format!(
                    "{}{} {} in {}/{}: {} var; use the ownership accessors (own_*/rel_*)",
                    h.chain,
                    h.name,
                    h.how,
                    owner,
                    proc,
                    if kind == Vk::Entity { "an entity" } else { "an entity list" }
                ),
            });
        }
    });
}

struct Ownership;

impl Lint for Ownership {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let all = cx.all_files();
        let files = cx.files();
        let mut problems: Vec<Problem> = Vec::new();

        // ---- the index-independent per-line checks run beside the index and the usage scan
        let (contents, (idx, scans)) = rayon::join(
            || oi::sharded_facts("ownership-content", &files, content_checks),
            || {
                let idx = Index::get(cx.tree, &all);
                // ---- the assignment index: accessor usage per var name and receiver type. A file's
                // scan reads the members and name declarations only, so it is cached under their key.
                let scans: Vec<UsageScan> = oi::sharded_keyed("ownership-usage", idx.key_members, &all, |f| usage_scan(&idx, f));
                (idx, scans)
            },
        );
        let mut usage: OrdMap<UsageKinds> = OrdMap::new();
        let mut unknown: Vec<Problem> = Vec::new();
        for (f, sc) in all.iter().zip(scans) {
            for (name, kind, rtype, no) in sc.events {
                let u = usage.entry_or_insert_with(&name, UsageKinds::default);
                let set = match kind {
                    0 => &mut u.own,
                    1 => &mut u.rel,
                    2 => &mut u.proto,
                    4 => &mut u.relw,
                    _ => &mut u.shared,
                };
                set.insert((rtype, f.rel.clone(), no as usize));
            }
            for (no, msg) in sc.unknown {
                unknown.push(Problem { check: "unknown_var", rel: f.rel.clone(), line: no as usize, msg });
            }
        }
        problems.extend(unknown);
        // What a per-file raw_write judgement reads of the usage map: the receiver types only.
        fn types_of(set: &BTreeSet<Loc>) -> Vec<&str> {
            let mut v: Vec<&str> = set.iter().map(|(t, _, _)| t.as_str()).collect();
            v.dedup();
            v
        }
        let usage_types: Vec<(&str, [Vec<&str>; 4])> =
            usage.iter().map(|(name, u)| (name, [types_of(&u.own), types_of(&u.rel), types_of(&u.relw), types_of(&u.proto)])).collect();
        let judge_key = incr::mix(&[idx.key_struct, incr::ctx_key(&usage_types)]);
        let cxt = Ctx { idx: idx.clone(), usage, vk_cache: RwLock::new(HashMap::new()), amb_cache: RwLock::new(HashMap::new()) };

        // ---- raw_write per file, beside the whole-tree checks (kinds, matrix, contradictions)
        let (raws, global) = rayon::join(
            || -> Vec<RawOut> { oi::sharded_keyed("ownership-raw", judge_key, &files, |f| raw_checks(&cxt, f)) },
            || -> Vec<Problem> {
                let mut problems: Vec<Problem> = Vec::new();
            // ---- kinds: one kind per var across the hierarchy
            struct Entry {
                t: String,
                kind: &'static str,
                rel: String,
                line: usize,
            }
            let mut by_name: OrdMap<Vec<Entry>> = OrdMap::new();
            for (t, vs) in idx.decls.iter() {
                for (v, d) in vs.iter() {
                    if let Some(kind) = decl_kind_of(&d.macro_name) {
                        by_name.entry_or_insert_with(v, Vec::new).push(Entry { t: t.to_string(), kind, rel: d.rel.clone(), line: d.line });
                    }
                }
            }
            for (v, entries) in by_name.iter() {
                for (i, e1) in entries.iter().enumerate() {
                    for e2 in &entries[i + 1..] {
                        if e1.kind != e2.kind && related(&e1.t, &e2.t) {
                            problems.push(Problem {
                                check: "kinds",
                                rel: e2.rel.clone(),
                                line: e2.line,
                                msg: format!("{}.{} is {} here but {} on {} ({}:{}): one kind per var", e2.t, v, e2.kind, e1.kind, e1.t, e1.rel, e1.line),
                            });
                        }
                    }
                }
            }

            // ---- matrix
            for (t, vs) in idx.decls.iter() {
                for (v, d) in vs.iter() {
                    let Some(got) = idx.member(t, v) else { continue };
                    let vtype = got.vtype.as_str();
                    let kind = decl_kind_of(&d.macro_name);
                    let a = d.opts.as_str();
                    if matches!(kind, Some("OWN") | Some("REL")) && idx.is_registry(vtype) {
                        problems.push(Problem {
                            check: "matrix",
                            rel: d.rel.clone(),
                            line: d.line,
                            msg: format!("{}.{} is typed {}, a registry type: it is SHARED (a per-holder copy is PROTO)", t, v, vtype),
                        });
                    }
                    if kind == Some("SHARED") && !vtype.is_empty() && under(vtype, ENTITY_ROOTS) && !idx.is_registry(vtype) {
                        problems.push(Problem {
                            check: "matrix",
                            rel: d.rel.clone(),
                            line: d.line,
                            msg: format!("{}.{} is SHARED but typed {}, which is not a REGISTRY_TYPE", t, v, vtype),
                        });
                    }
                    if d.macro_name == "OWN"
                        && (a.contains("OWN_SPILL") || a.contains("OWN_CONTAINED"))
                        && !vtype.is_empty()
                        && !under(vtype, &["/atom/movable", "/obj", "/mob"])
                    {
                        problems.push(Problem {
                            check: "matrix",
                            rel: d.rel.clone(),
                            line: d.line,
                            msg: format!("{}.{}: {} needs a movable var type (got {})", t, v, py_strip(a), vtype),
                        });
                    }
                }
            }

            // ---- contradictions (usage vs usage, usage vs declaration, resources)
            for (name, kinds) in cxt.usage.iter() {
                for (t1, r1, n1) in &kinds.own {
                    for (t2, r2, n2) in &kinds.rel {
                        if !t1.is_empty() && !t2.is_empty() && related(t1, t2) {
                            let m1 = idx.member(t1, name);
                            if m1.is_some() && m1 == idx.member(t2, name) {
                                problems.push(Problem {
                                    check: "contradiction",
                                    rel: r2.clone(),
                                    line: *n2,
                                    msg: format!("{}.{} is written as a relation here and as owned at {}:{}", t2, name, r1, n1),
                                });
                                break;
                            }
                        }
                    }
                }
                for (t, r, n) in &kinds.rel {
                    if t.is_empty() {
                        continue;
                    }
                    if let Some(got) = idx.member(t, name) {
                        if got.vtype == "/datum/gas_mixture" {
                            problems.push(Problem {
                                check: "matrix",
                                rel: r.clone(),
                                line: *n,
                                msg: format!("{}.{} holds a gas mixture: a holder owns its mixture (own_set), a network's is PROTO", t, name),
                            });
                        }
                    }
                    if let Some((_, d)) = idx.decl(t, name) {
                        if !matches!(decl_kind_of(&d.macro_name), None | Some("REL")) {
                            problems.push(Problem {
                                check: "contradiction",
                                rel: r.clone(),
                                line: *n,
                                msg: format!("{}.{} is declared {} but written with rel_*", t, name, d.macro_name),
                            });
                        }
                    }
                }
                for (t, r, n) in kinds.own.iter().chain(kinds.relw.iter()) {
                    if t.is_empty() {
                        continue;
                    }
                    let is_relw = kinds.relw.contains(&(t.clone(), r.clone(), *n));
                    let d = idx.decl(t, name);
                    if let Some((_, dd)) = &d {
                        let ok = matches!(decl_kind_of(&dd.macro_name), None | Some("OWN")) || (is_relw && decl_kind_of(&dd.macro_name) == Some("REL"));
                        if !ok {
                            problems.push(Problem {
                                check: "contradiction",
                                rel: r.clone(),
                                line: *n,
                                msg: format!("{}.{} is declared {} but written with {}", t, name, dd.macro_name, if is_relw { "rel_*" } else { "own_*" }),
                            });
                        }
                    }
                    if let Some(got) = idx.member(t, name) {
                        let proto = matches!(&d, Some((_, dd)) if dd.macro_name == "PROTO");
                        // A rel_* writer of a registry-typed var is a view of the shared entry, not an owner (as before).
                        if idx.is_registry(&got.vtype) && !proto && !is_relw {
                            problems.push(Problem {
                                check: "matrix",
                                rel: r.clone(),
                                line: *n,
                                msg: format!("{}.{} is typed {}, a registry type: it is SHARED, not owned", t, name, got.vtype),
                            });
                        }
                    }
                }
            }

                problems
            },
        );

        // ---- string_name (first, as the Python's second loop), per-line checks collected for later
        let mut line_problems: Vec<Problem> = Vec::new();
        let mut uses: Vec<AllowUse> = Vec::new();
        for ((f, c), r) in files.iter().zip(contents).zip(raws) {
            for (no, msg) in c.string_name {
                problems.push(Problem { check: "string_name", rel: f.rel.clone(), line: no as usize, msg });
            }
            for (check, no, msg) in c.lines {
                line_problems.push(Problem { check: LINE_CHECKS[check as usize], rel: f.rel.clone(), line: no as usize, msg });
            }
            for (no, msg) in r.lines {
                line_problems.push(Problem { check: "raw_write", rel: f.rel.clone(), line: no as usize, msg });
            }
            uses.extend(c.uses);
            uses.extend(r.uses);
        }
        problems.extend(global);
        // ---- per-line checks (removed, callback, handle, raw_write), then the ALLOW usage
        problems.extend(line_problems);
        for u in uses {
            if !out.allow_used.contains(&u) {
                out.allow_used.push(u);
            }
        }

        // The summary line counts in discovery order (Counter.most_common is stable); the report is
        // sorted by (file, line) like the Python's print loop.
        let mut counts: Vec<(&'static str, usize)> = Vec::new();
        for p in &problems {
            match counts.iter_mut().find(|(c, _)| *c == p.check) {
                Some((_, n)) => *n += 1,
                None => counts.push((p.check, 1)),
            }
        }
        counts.sort_by(|a, b| b.1.cmp(&a.1));
        let summary: Vec<String> = counts.iter().map(|(c, n)| format!("{} {}", c, n)).collect();
        out.note(format!(
            "ownership lint: {} problem{} ({})",
            problems.len(),
            if problems.len() == 1 { "" } else { "s" },
            if summary.is_empty() { "clean".to_string() } else { summary.join(", ") }
        ));
        problems.sort_by(|a, b| (&a.rel, a.line).cmp(&(&b.rel, b.line)));
        for p in problems {
            out.site_in_msg(p.check, &p.rel, p.line, p.msg);
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/ownership_lint.py"],
            old_raw: &[],
            blank: &[],
            parse: ParseKind::Bracketed,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Ownership);
}
