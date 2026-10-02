//! Port of `tools/ci/system_boundary_lint.py` (doc/rewrite/kernel.md sec 2.5).
//!
//! A subsystem, a world service or a /datum/system is a module; its folder is the boundary.
//! Counts are ratcheted per `(rule, file, owner)` in `tools/ci/system_boundary_baseline.txt`
//! (`name count` lines) and only shrink.
//!
//!   B1  no `SSx.<var>` / `GLOB.<x>_service.<var>` / `system(/datum/system/X).<var>` outside the owner
//!   B2  `system(/datum/system/X).proc()` outside X's folder must name a proc in X's api.dm
//!   B3  no proc definitions of a subsystem / service / system outside the owner's folder
//!   B4  X calls Y's API only if Y is in X's `uses`
//!   B5  no cycle in `needs`, and every `needs` entry names a declared type
//!   B6  OM_EMIT* event types under X's folder are in X's `emits`
//!   B7  a /datum/system folder has an api.dm iff another folder calls the system
//!
//! Shape notes (kept from the Python): a site's `key` is the baseline name (spaces as `%20`); its
//! `msg` is the whole text the old `--report` printed. A B5 or B7 site has no file or line, so the
//! text rides in `rel` (line 0), which is also how the parity parser compares it.
//! Python iterates `glob.glob` order and this engine path-sorted order; they only differ for a
//! duplicate definition, where "first one wins" could pick a different file.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::fmt::Write as _;

use crate::baseline::{self, Mode};
use crate::lint::{Cx, Lint, Meta, Policy, Registry, Run, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_MAPS_DM};
use crate::util::py_strip;

const LINT: &str = "system_boundary";
const BASELINE: &str = "tools/ci/system_boundary_baseline.txt";
const HEADER: &[&str] = &[
    "System boundary ratchet (tools/ci/system_boundary_lint.py). `<rule>:<file>:<owner> <count>`; only shrinks.",
    "Regenerate the file with --generate only when the rules change; otherwise --update lowers ceilings.",
];

const HINT: &str = "see tools/ci/system_boundary_lint.py and doc/rewrite/kernel.md sec 2.5";

static META: Meta = Meta {
    name: "system_boundary",
    group: "",
    label: "system_boundary",
    legacy: "tools/ci/system_boundary_lint.py",
    select: CODE_MAPS_DM,
    scan: ScanKind::Tree,
    policy: Policy::Custom,
    rules: &[
        RuleMeta { name: "B1", hint: HINT },
        RuleMeta { name: "B2", hint: HINT },
        RuleMeta { name: "B3", hint: HINT },
        RuleMeta { name: "B4", hint: HINT },
        RuleMeta { name: "B5", hint: HINT },
        RuleMeta { name: "B6", hint: HINT },
        RuleMeta { name: "B7", hint: HINT },
    ],
    allow: &["system_boundary"],
    lists: &[],
};

struct SystemBoundary;

fn folder_of(rel: &str) -> &str {
    match rel.rfind('/') {
        Some(i) => &rel[..i],
        None => "",
    }
}

fn inside(rel: &str, owner_dir: &str) -> bool {
    rel == owner_dir || (rel.starts_with(owner_dir) && rel.as_bytes().get(owner_dir.len()) == Some(&b'/'))
}

/// An insertion-ordered map with `setdefault` semantics (a Python dict).
struct OrderedMap<V> {
    order: Vec<String>,
    map: HashMap<String, V>,
}

impl<V> OrderedMap<V> {
    fn new() -> Self {
        OrderedMap { order: Vec::new(), map: HashMap::new() }
    }
    fn setdefault(&mut self, k: &str, v: V) {
        if !self.map.contains_key(k) {
            self.order.push(k.to_string());
            self.map.insert(k.to_string(), v);
        }
    }
    fn get(&self, k: &str) -> Option<&V> {
        self.map.get(k)
    }
    fn iter(&self) -> impl Iterator<Item = (&String, &V)> {
        self.order.iter().map(move |k| (k, &self.map[k]))
    }
}

#[derive(Default, Clone)]
struct Decl {
    file: String,
    needs: Option<Vec<String>>,
    uses: Option<Vec<String>>,
    emits: Option<Vec<String>>,
}

/// `list_arg`: the typepaths of the `name = list(...)` whose first line is `start` (0-based).
fn list_arg(lines: &[&str], start: usize) -> Vec<String> {
    let mut text = String::new();
    let mut depth: i64 = 0;
    for line in &lines[start..] {
        text.push_str(line);
        text.push('\n');
        depth += line.matches('(').count() as i64 - line.matches(')').count() as i64;
        if depth <= 0 {
            break;
        }
    }
    let tail = text.split("list(").last().unwrap_or("");
    pat_paths().find_iter(tail).iter().map(|m| m.as_str().to_string()).collect()
}

fn pat_paths() -> &'static Pat {
    crate::pat!(r"/[\w/]+")
}

/// Tarjan's SCCs of size > 1 (or a self-loop), as sorted vectors, in discovery order.
struct Tarjan<'g> {
    graph: &'g HashMap<String, Vec<String>>,
    index: HashMap<String, usize>,
    low: HashMap<String, usize>,
    on: HashSet<String>,
    stack: Vec<String>,
    out: Vec<Vec<String>>,
    counter: usize,
}

impl<'g> Tarjan<'g> {
    fn visit(&mut self, v: &str) {
        self.index.insert(v.to_string(), self.counter);
        self.low.insert(v.to_string(), self.counter);
        self.counter += 1;
        self.stack.push(v.to_string());
        self.on.insert(v.to_string());
        let succ: Vec<String> = self.graph.get(v).cloned().unwrap_or_default();
        for w in &succ {
            if !self.index.contains_key(w) {
                self.visit(w);
                let lw = self.low[w];
                let lv = self.low[v];
                self.low.insert(v.to_string(), lv.min(lw));
            } else if self.on.contains(w) {
                let iw = self.index[w];
                let lv = self.low[v];
                self.low.insert(v.to_string(), lv.min(iw));
            }
        }
        if self.low[v] == self.index[v] {
            let mut comp = Vec::new();
            loop {
                let w = self.stack.pop().unwrap();
                self.on.remove(&w);
                let done = w == v;
                comp.push(w);
                if done {
                    break;
                }
            }
            let selfloop = self.graph.get(v).map(|s| s.iter().any(|x| x == v)).unwrap_or(false);
            if comp.len() > 1 || selfloop {
                comp.sort();
                self.out.push(comp);
            }
        }
    }
}

struct Doc<'a> {
    rel: &'a str,
    f: &'a SourceFile,
    code: Vec<&'a str>,
}

impl SystemBoundary {
    fn check(&self, cx: &Cx, out: &mut Sink) {
        let files = cx.files();
        let docs: Vec<Doc> = files.iter().map(|f| Doc { rel: &f.rel, f, code: f.code().lines_vec() }).collect();
        let by_rel: HashMap<&str, usize> = docs.iter().enumerate().map(|(i, d)| (d.rel, i)).collect();

        // scan_owners
        let ss_def = crate::pat!(r"(?m)^\s*(?:VERB_MANAGER_)?(?:SUBSYSTEM|SYSTEM)_DEF\((\w+)\)");
        let service_def = crate::pat!(r"(?m)^\s*GLOBAL_DATUM_INIT\((\w+_service),\s*(/datum/world_service[\w/]*)");
        let system_type = crate::pat!(r"(?m)^/datum/system/(\w+)\s*$");
        let mut ss_owner: OrderedMap<String> = OrderedMap::new();
        let mut service_owner: OrderedMap<(String, String)> = OrderedMap::new();
        let mut system_owner: OrderedMap<String> = OrderedMap::new();
        for d in &docs {
            let raw = d.f.text();
            for c in ss_def.captures_iter(raw) {
                ss_owner.setdefault(c.s(1), folder_of(d.rel).to_string());
            }
            for c in service_def.captures_iter(raw) {
                service_owner.setdefault(c.s(1), (folder_of(d.rel).to_string(), c.s(2).to_string()));
            }
            for c in system_type.captures_iter(raw) {
                system_owner.setdefault(&format!("/datum/system/{}", c.s(1)), folder_of(d.rel).to_string());
            }
        }

        // declarations
        let typedef = crate::pat_match!(r"(/[\w/]+)\s*$");
        let var_needs = crate::pat_match!(r"\s+(?:var/list/)?needs\s*=\s*list\(");
        let var_uses = crate::pat_match!(r"\s+(?:var/list/)?uses\s*=\s*list\(");
        let var_emits = crate::pat_match!(r"\s+(?:var/list/)?emits\s*=\s*list\(");
        let mut decl_order: Vec<String> = Vec::new();
        let mut decls: HashMap<String, Decl> = HashMap::new();
        let mut known: HashSet<String> = HashSet::new();
        for d in &docs {
            let mut current: Option<String> = None;
            for (number, line) in d.code.iter().enumerate() {
                if let Some(m) = typedef.captures(line) {
                    let t = m.s(1).to_string();
                    known.insert(t.clone());
                    current = Some(t);
                    continue;
                }
                let Some(cur) = &current else { continue };
                for (var, pat) in [("needs", var_needs), ("uses", var_uses), ("emits", var_emits)] {
                    if pat.is_match(line) {
                        if !decls.contains_key(cur) {
                            decl_order.push(cur.clone());
                            decls.insert(cur.clone(), Decl { file: d.rel.to_string(), ..Decl::default() });
                        }
                        let arg = list_arg(&d.code, number);
                        let e = decls.get_mut(cur).unwrap();
                        match var {
                            "needs" => e.needs = Some(arg),
                            "uses" => e.uses = Some(arg),
                            _ => e.emits = Some(arg),
                        }
                    }
                }
            }
        }
        // SUBSYSTEM_DEF(x) declares /datum/controller/subsystem/x through a macro.
        for (name, _) in ss_owner.iter() {
            known.insert(format!("/datum/controller/subsystem/{}", name));
            known.insert(format!("/datum/system/{}", name));
        }

        // api procs per system
        let api_proc = crate::pat!(r"(?m)^/[\w/]+/(?:proc/)?(\w+)\s*\(");
        let mut api_procs: HashMap<String, HashSet<String>> = HashMap::new();
        for (typ, owner_dir) in system_owner.iter() {
            let mut procs = HashSet::new();
            if let Some(&i) = by_rel.get(format!("{}/api.dm", owner_dir).as_str()) {
                let text = docs[i].code.join("\n");
                for c in api_proc.captures_iter(&text) {
                    procs.insert(c.s(1).to_string());
                }
            }
            api_procs.insert(typ.clone(), procs);
        }

        let mut system_called_from: HashMap<String, HashSet<String>> = HashMap::new();
        let ss_access = crate::pat!(r"(?<![\w.])SS(\w+)\.(\w+)(\s*\()?");
        let service_access = crate::pat!(r"(?<![\w.])GLOB\.(\w+_service)\.(\w+)(\s*\()?");
        let system_access = crate::pat!(r"(?<![\w.])system\(\s*(/datum/system/\w+)\s*\)\.(\w+)(\s*\()?");
        let proc_def = crate::pat_match!(r"/datum/(controller/subsystem|world_service|system)/(\w+)/(?:proc/)?(\w+)\s*\(");

        let hit = |out: &mut Sink, rule: &str, name: String, rel: &str, line: usize, text: String| {
            let key = name.replace(' ', "%20");
            out.site_keyed(rule, rel, line, text, key);
        };

        for d in &docs {
            let rel = d.rel;
            for (i, line) in d.code.iter().enumerate() {
                let number = i + 1;
                if out.allowed(d.f, number, LINT) {
                    continue;
                }
                let where_ = format!("{}:{}: {}", rel, number, py_strip(d.f.raw().line(number)));
                for m in ss_access.captures_iter(line) {
                    let Some(owner) = ss_owner.get(m.s(1)) else { continue };
                    if inside(rel, owner) {
                        continue;
                    }
                    if !m.matched(3) {
                        hit(out, "B1", format!("B1:{}:SS{}", rel, m.s(1)), rel, number, where_.clone());
                    }
                }
                for m in service_access.captures_iter(line) {
                    let Some(own) = service_owner.get(m.s(1)) else { continue };
                    if inside(rel, &own.0) {
                        continue;
                    }
                    if !m.matched(3) {
                        hit(out, "B1", format!("B1:{}:GLOB.{}", rel, m.s(1)), rel, number, where_.clone());
                    }
                }
                for m in system_access.captures_iter(line) {
                    let (typ, member, is_call) = (m.s(1), m.s(2), m.matched(3));
                    let Some(owner) = system_owner.get(typ) else { continue };
                    if inside(rel, owner) {
                        continue;
                    }
                    system_called_from.entry(typ.to_string()).or_default().insert(rel.to_string());
                    if !is_call {
                        hit(out, "B1", format!("B1:{}:{}", rel, typ), rel, number, where_.clone());
                    } else if !api_procs.get(typ).map(|s| s.contains(member)).unwrap_or(false) {
                        hit(out, "B2", format!("B2:{}:{}", rel, typ), rel, number, where_.clone());
                    } else {
                        let caller = system_owner.iter().find(|(_, dir)| inside(rel, dir)).map(|(t, _)| t.clone());
                        if let Some(caller) = caller {
                            let uses = decls.get(&caller).and_then(|d| d.uses.as_ref());
                            if !uses.map(|u| u.iter().any(|x| x == typ)).unwrap_or(false) {
                                hit(out, "B4", format!("B4:{}:{}", rel, typ), rel, number, where_.clone());
                            }
                        }
                    }
                }
                if let Some(m) = proc_def.captures(line) {
                    let (kind, name) = (m.s(1), m.s(2));
                    let owner: Option<String> = if kind == "controller/subsystem" {
                        ss_owner.get(name).cloned()
                    } else if kind == "world_service" {
                        let suffix = format!("/{}", name);
                        service_owner.iter().find(|(_, o)| o.1.ends_with(&suffix)).map(|(_, o)| o.0.clone())
                    } else {
                        // SYSTEM_DEF(x) declares /datum/system/x through a macro, like SUBSYSTEM_DEF(x).
                        // Python `a or b`: an empty-string owner folder falls through to b.
                        match ss_owner.get(name) {
                            Some(o) if !o.is_empty() => Some(o.clone()),
                            _ => system_owner.get(&format!("/datum/system/{}", name)).cloned(),
                        }
                    };
                    if let Some(owner) = owner {
                        if !inside(rel, &owner) {
                            hit(out, "B3", format!("B3:{}:{}", rel, name), rel, number, where_.clone());
                        }
                    }
                }
            }
        }

        // B5: cycles in needs, and needs that name nothing.
        let mut graph_order: Vec<String> = Vec::new();
        let mut graph: HashMap<String, Vec<String>> = HashMap::new();
        for t in &decl_order {
            if let Some(n) = &decls[t].needs {
                if !n.is_empty() {
                    graph_order.push(t.clone());
                    graph.insert(t.clone(), n.clone());
                }
            }
        }
        let mut tj = Tarjan {
            graph: &graph,
            index: HashMap::new(),
            low: HashMap::new(),
            on: HashSet::new(),
            stack: Vec::new(),
            out: Vec::new(),
            counter: 0,
        };
        for v in &graph_order {
            if !tj.index.contains_key(v) {
                tj.visit(v);
            }
        }
        for comp in &tj.out {
            let text = format!("needs cycle: {}", comp.join(" -> "));
            let name = format!("B5:cycle:{}", comp.join("+").replace(' ', ""));
            hit(out, "B5", name, &text, 0, text.clone());
        }
        for typ in &decl_order {
            for need in decls[typ].needs.iter().flatten() {
                if !known.contains(need) {
                    let text = format!("{} needs {}, which no file declares", typ, need);
                    hit(out, "B5", format!("B5:unknown:{}->{}", typ, need), &text, 0, text.clone());
                }
            }
        }

        // B6: emitted events are declared (once the system declares `emits`).
        let emit = crate::pat!(r"OM_EMIT\w*\(\s*(/datum/om/event/[\w/]+)");
        for (typ, owner_dir) in system_owner.iter() {
            let Some(emits) = decls.get(typ).and_then(|d| d.emits.as_ref()) else { continue };
            for d in &docs {
                if !inside(d.rel, owner_dir) {
                    continue;
                }
                for (i, line) in d.code.iter().enumerate() {
                    let number = i + 1;
                    for m in emit.captures_iter(line) {
                        if !emits.iter().any(|e| e == m.s(1)) && !out.allowed(d.f, number, LINT) {
                            hit(out, "B6", format!("B6:{}:{}", d.rel, typ), d.rel, number, format!("{}:{} emits {}", d.rel, number, m.s(1)));
                        }
                    }
                }
            }
        }

        // B7: api.dm iff other folders call the system.
        for (typ, owner_dir) in system_owner.iter() {
            let has_api = by_rel.contains_key(format!("{}/api.dm", owner_dir).as_str());
            let called = system_called_from.get(typ).map(|s| !s.is_empty()).unwrap_or(false);
            if called != has_api {
                let text = format!(
                    "{}: api.dm {} but {}",
                    typ,
                    if has_api { "present" } else { "missing" },
                    if called { "called from outside" } else { "never called from outside" }
                );
                hit(out, "B7", format!("B7:{}", typ), &text, 0, text.clone());
            }
        }
    }
}

impl Lint for SystemBoundary {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        self.check(cx, out);
    }

    fn finish(&self, cx: &Cx, run: &Run, text: &mut String) -> bool {
        let base = baseline::read_ceilings(&cx.tree.root.join(BASELINE));
        let mut by_key: BTreeMap<&str, Vec<&crate::lint::Site>> = BTreeMap::new();
        for s in &run.sites {
            by_key.entry(s.key.as_str()).or_default().push(s);
        }
        let mut failed = false;
        for (name, sites) in &by_key {
            let ceiling = base.get(*name).copied();
            let count = sites.len() as i64;
            if ceiling.is_none() || count > ceiling.unwrap() {
                let c = ceiling.map(|c| c.to_string()).unwrap_or_else(|| "none".to_string());
                let _ = writeln!(text, "system_boundary: FAIL {}: {} (ceiling {})", name, count, c);
                for s in sites.iter().take(5) {
                    let _ = writeln!(text, "    {}", s.msg);
                }
                failed = true;
            }
        }
        let lowered = base.iter().filter(|(k, v)| (by_key.get(k.as_str()).map(|s| s.len()).unwrap_or(0) as i64) < **v).count();
        let mut totals: Vec<String> = Vec::new();
        for r in ["B1", "B2", "B3", "B4", "B5", "B6", "B7"] {
            totals.push(format!("{}={}", r, run.sites.iter().filter(|s| s.rule == r).count()));
        }
        let _ = writeln!(
            text,
            "system_boundary: {}; {}; {} entries below their ceiling (--update lowers them)",
            totals.join(", "),
            if failed { "FAILED" } else { "ok" },
            lowered
        );
        failed
    }

    fn update_baseline(&self, cx: &Cx, run: &Run, mode: Mode) -> std::io::Result<String> {
        let path = cx.tree.root.join(BASELINE);
        match mode {
            Mode::Update => {
                let n = baseline::update_ceilings(&path, HEADER, &run.sites)?;
                Ok(format!("system_boundary: baseline lowered to {} entries", n))
            }
            Mode::Seed => {
                let counts = baseline::key_counts(&run.sites);
                baseline::write_ceilings(&path, HEADER, &counts)?;
                Ok(format!("system_boundary: wrote {} entries", counts.len()))
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/system_boundary_lint.py"],
            old_raw: &[&["tools/ci/system_boundary_lint.py", "--report"]],
            blank: &[],
            parse: ParseKind::RulePrefixed,
            update: Some(&["tools/ci/system_boundary_lint.py", "--update"]),
            seed: Some(&["tools/ci/system_boundary_lint.py", "--generate"]),
            files: &[BASELINE],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(SystemBoundary);
}
