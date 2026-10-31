//! SAME original cross-file boundary policy. Source acquisition and baseline I/O stay with callers.
use std::collections::{BTreeMap,BTreeSet,HashMap,HashSet};
use serde::{Deserialize,Serialize};
use crate::{lint::Sink,pat::Pat,tree::SourceFile,util::py_strip};
use crate::system_boundary_report::LINT;
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
    fn iter(&self) -> impl Iterator<Item = (&String, &V)> {
        self.order.iter().map(move |k| (k, &self.map[k]))
    }
}

#[derive(Default, Clone)]
struct Decl {
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

/// One file's contribution to the cross-file index.
#[derive(Serialize, Deserialize, Default, PartialEq)]
pub(crate) struct Facts {
    /// `SUBSYSTEM_DEF(x)` / `SYSTEM_DEF(x)` names declared in the file, in order.
    ss_defs: Vec<String>,
    /// `GLOBAL_DATUM_INIT(x_service, /datum/world_service...)`: `(name, type)`.
    service_defs: Vec<(String, String)>,
    /// `/datum/system/x` type blocks (the whole path).
    system_types: Vec<String>,
    /// Every type block in the file (sorted, unique): the `known` set.
    types: Vec<String>,
    /// `needs` / `uses` / `emits` lists: `(type, kind 0/1/2, typepaths)`, in order.
    entries: Vec<(String, u8, Vec<String>)>,
    /// The proc names an `api.dm` defines (sorted, unique); empty for any other file.
    api_procs: Vec<String>,
}

pub(crate) fn facts_of(f: &SourceFile) -> Facts {
    let mut fa = Facts::default();
    let ss_def = crate::pat!(r"(?m)^\s*(?:VERB_MANAGER_)?(?:SUBSYSTEM|SYSTEM)_DEF\((\w+)\)");
    let service_def = crate::pat!(r"(?m)^\s*GLOBAL_DATUM_INIT\((\w+_service),\s*(/datum/world_service[\w/]*)");
    let system_type = crate::pat!(r"(?m)^/datum/system/(\w+)\s*$");
    let raw = f.text();
    for c in ss_def.captures_iter(raw) {
        fa.ss_defs.push(c.s(1).to_string());
    }
    for c in service_def.captures_iter(raw) {
        fa.service_defs.push((c.s(1).to_string(), c.s(2).to_string()));
    }
    for c in system_type.captures_iter(raw) {
        fa.system_types.push(format!("/datum/system/{}", c.s(1)));
    }

    let typedef = crate::pat_match!(r"(/[\w/]+)\s*$");
    let var_needs = crate::pat_match!(r"\s+(?:var/list/)?needs\s*=\s*list\(");
    let var_uses = crate::pat_match!(r"\s+(?:var/list/)?uses\s*=\s*list\(");
    let var_emits = crate::pat_match!(r"\s+(?:var/list/)?emits\s*=\s*list\(");
    let code = f.code().lines_vec();
    let mut types: BTreeSet<String> = BTreeSet::new();
    let mut current: Option<String> = None;
    for (number, line) in code.iter().enumerate() {
        if let Some(m) = typedef.captures(line) {
            let t = m.s(1).to_string();
            types.insert(t.clone());
            current = Some(t);
            continue;
        }
        let Some(cur) = &current else { continue };
        for (kind, pat) in [(0u8, var_needs), (1u8, var_uses), (2u8, var_emits)] {
            if pat.is_match(line) {
                fa.entries.push((cur.clone(), kind, list_arg(&code, number)));
            }
        }
    }
    fa.types = types.into_iter().collect();

    if f.rel.ends_with("/api.dm") {
        let api_proc = crate::pat!(r"(?m)^/[\w/]+/(?:proc/)?(\w+)\s*\(");
        let procs: BTreeSet<String> = api_proc.captures_iter(&f.code().text).iter().map(|c| c.s(1).to_string()).collect();
        fa.api_procs = procs.into_iter().collect();
    }
    fa
}

/// What the per-file judgement reads: the owners, the api procs, the `uses` / `emits` of systems.
#[derive(Serialize)]
struct Ctx {
    ss_owner: Vec<(String, String)>,
    service_owner: Vec<(String, String, String)>,
    system_owner: Vec<(String, String)>,
    api_procs: BTreeMap<String, Vec<String>>,
    uses: BTreeMap<String, Option<Vec<String>>>,
    emits: BTreeMap<String, Option<Vec<String>>>,
}

/// One file's findings: B1..B4 hits in line order, the systems it calls from outside, and its
/// would-be B6 emits `(system index, line, event type)`.
#[derive(Serialize, Deserialize, Default, PartialEq)]
pub(crate) struct FileOut {
    /// `(rule 0..=3 for B1..B4, line, key, text)`.
    pub(crate) hits: Vec<(u8, u32, String, String)>,
    called: Vec<String>,
    pub(crate) b6: Vec<(u32, u32, String)>,
}

/// Lookup tables over [`Ctx`] (the judge's hot paths).
struct Look<'a> {
    ss: HashMap<&'a str, &'a str>,
    services: HashMap<&'a str, (&'a str, &'a str)>,
    systems: HashMap<&'a str, &'a str>,
}

fn judge(f: &SourceFile, ctx: &Ctx, look: &Look) -> FileOut {
    let ss_access = crate::pat!(r"(?<![\w.])SS(\w+)\.(\w+)(\s*\()?");
    let service_access = crate::pat!(r"(?<![\w.])GLOB\.(\w+_service)\.(\w+)(\s*\()?");
    let system_access = crate::pat!(r"(?<![\w.])system\(\s*(/datum/system/\w+)\s*\)\.(\w+)(\s*\()?");
    let proc_def = crate::pat_match!(r"/datum/(controller/subsystem|world_service|system)/(\w+)/(?:proc/)?(\w+)\s*\(");
    let emit = crate::pat!(r"OM_EMIT\w*\(\s*(/datum/om/event/[\w/]+)");
    let rel = f.rel.as_str();
    let code = f.code().lines_vec();
    let mut out = FileOut::default();
    let mut called: BTreeSet<String> = BTreeSet::new();
    for (i, line) in code.iter().enumerate() {
        let number = i + 1;
        if crate::dm::sys::kept_recorded(f, number, LINT) {
            continue;
        }
        let where_ = format!("{}:{}: {}", rel, number, py_strip(f.raw().line(number)));
        for m in ss_access.captures_iter(line) {
            let Some(owner) = look.ss.get(m.s(1)) else { continue };
            if inside(rel, owner) {
                continue;
            }
            if !m.matched(3) {
                out.hits.push((0, number as u32, format!("B1:{}:SS{}", rel, m.s(1)).replace(' ', "%20"), where_.clone()));
            }
        }
        for m in service_access.captures_iter(line) {
            let Some(own) = look.services.get(m.s(1)) else { continue };
            if inside(rel, own.0) {
                continue;
            }
            if !m.matched(3) {
                out.hits.push((0, number as u32, format!("B1:{}:GLOB.{}", rel, m.s(1)).replace(' ', "%20"), where_.clone()));
            }
        }
        for m in system_access.captures_iter(line) {
            let (typ, member, is_call) = (m.s(1), m.s(2), m.matched(3));
            let Some(owner) = look.systems.get(typ) else { continue };
            if inside(rel, owner) {
                continue;
            }
            called.insert(typ.to_string());
            if !is_call {
                out.hits.push((0, number as u32, format!("B1:{}:{}", rel, typ).replace(' ', "%20"), where_.clone()));
            } else if !ctx.api_procs.get(typ).map(|s| s.iter().any(|p| p == member)).unwrap_or(false) {
                out.hits.push((1, number as u32, format!("B2:{}:{}", rel, typ).replace(' ', "%20"), where_.clone()));
            } else {
                let caller = ctx.system_owner.iter().find(|(_, dir)| inside(rel, dir)).map(|(t, _)| t.clone());
                if let Some(caller) = caller {
                    let uses = ctx.uses.get(&caller).and_then(|u| u.as_ref());
                    if !uses.map(|u| u.iter().any(|x| x == typ)).unwrap_or(false) {
                        out.hits.push((3, number as u32, format!("B4:{}:{}", rel, typ).replace(' ', "%20"), where_.clone()));
                    }
                }
            }
        }
        if let Some(m) = proc_def.captures(line) {
            let (kind, name) = (m.s(1), m.s(2));
            let owner: Option<String> = if kind == "controller/subsystem" {
                look.ss.get(name).map(|s| s.to_string())
            } else if kind == "world_service" {
                let suffix = format!("/{}", name);
                ctx.service_owner.iter().find(|(_, _, ty)| ty.ends_with(&suffix)).map(|(_, dir, _)| dir.clone())
            } else {
                // SYSTEM_DEF(x) declares /datum/system/x through a macro, like SUBSYSTEM_DEF(x).
                // Python `a or b`: an empty-string owner folder falls through to b.
                match look.ss.get(name) {
                    Some(o) if !o.is_empty() => Some(o.to_string()),
                    _ => look.systems.get(format!("/datum/system/{}", name).as_str()).map(|s| s.to_string()),
                }
            };
            if let Some(owner) = owner {
                if !inside(rel, &owner) {
                    out.hits.push((2, number as u32, format!("B3:{}:{}", rel, name).replace(' ', "%20"), where_.clone()));
                }
            }
        }
    }
    out.called = called.into_iter().collect();

    // B6: emitted events are declared (once the system declares `emits`).
    for (ti, (typ, owner_dir)) in ctx.system_owner.iter().enumerate() {
        let Some(emits) = ctx.emits.get(typ).and_then(|e| e.as_ref()) else { continue };
        if !inside(rel, owner_dir) {
            continue;
        }
        for (i, line) in code.iter().enumerate() {
            let number = i + 1;
            for m in emit.captures_iter(line) {
                if !emits.iter().any(|e| e == m.s(1)) && !crate::dm::sys::kept_recorded(f, number, LINT) {
                    out.b6.push((ti as u32, number as u32, m.s(1).to_string()));
                }
            }
        }
    }
    out
}

fn hit(out: &mut Sink, rule: &str, name: String, rel: &str, line: usize, text: String) {
    let key = name.replace(' ', "%20");
    out.site_keyed(rule, rel, line, text, key);
}

pub(crate) struct Prepared{ctx:Ctx,decl_order:Vec<String>,decls:HashMap<String,Decl>,known:HashSet<String>,file_paths:HashSet<String>}
impl Prepared{#[cfg(feature="legacy-sem")]pub(crate) fn context_key(&self)->crate::tree::Hash{crate::incr::ctx_key(&self.ctx)}}
pub(crate) fn prepare(files:&[(&str,&Facts)])->Prepared{
 let by_rel:HashMap<&str,usize>=files.iter().enumerate().map(|(i,(rel,_))|(*rel,i)).collect();
        // scan_owners
        let mut ss_owner: OrderedMap<String> = OrderedMap::new();
        let mut service_owner: OrderedMap<(String, String)> = OrderedMap::new();
        let mut system_owner: OrderedMap<String> = OrderedMap::new();
        // declarations
        let mut decl_order: Vec<String> = Vec::new();
        let mut decls: HashMap<String, Decl> = HashMap::new();
        let mut known: HashSet<String> = HashSet::new();
        for (rel, fa) in files {
            let folder = folder_of(rel);
            for n in &fa.ss_defs {
                ss_owner.setdefault(n, folder.to_string());
            }
            for (n, t) in &fa.service_defs {
                service_owner.setdefault(n, (folder.to_string(), t.clone()));
            }
            for t in &fa.system_types {
                system_owner.setdefault(t, folder.to_string());
            }
            known.extend(fa.types.iter().cloned());
            for (cur, kind, arg) in &fa.entries {
                if !decls.contains_key(cur) {
                    decl_order.push(cur.clone());
                    decls.insert(cur.clone(), Decl::default());
                }
                let e = decls.get_mut(cur).unwrap();
                match kind {
                    0 => e.needs = Some(arg.clone()),
                    1 => e.uses = Some(arg.clone()),
                    _ => e.emits = Some(arg.clone()),
                }
            }
        }
        // SUBSYSTEM_DEF(x) declares /datum/controller/subsystem/x through a macro.
        for (name, _) in ss_owner.iter() {
            known.insert(format!("/datum/controller/subsystem/{}", name));
            known.insert(format!("/datum/system/{}", name));
        }

        // api procs per system
        let mut api_procs: BTreeMap<String, Vec<String>> = BTreeMap::new();
        for (typ, owner_dir) in system_owner.iter() {
            let procs = by_rel.get(format!("{}/api.dm", owner_dir).as_str()).map(|&i| files[i].1.api_procs.clone()).unwrap_or_default();
            api_procs.insert(typ.clone(), procs);
        }

        let ctx = Ctx {
            ss_owner: ss_owner.iter().map(|(k, v)| (k.clone(), v.clone())).collect(),
            service_owner: service_owner.iter().map(|(k, v)| (k.clone(), v.0.clone(), v.1.clone())).collect(),
            system_owner: system_owner.iter().map(|(k, v)| (k.clone(), v.clone())).collect(),
            api_procs,
            uses: system_owner.iter().map(|(k, _)| (k.clone(), decls.get(k).and_then(|d| d.uses.clone()))).collect(),
            emits: system_owner.iter().map(|(k, _)| (k.clone(), decls.get(k).and_then(|d| d.emits.clone()))).collect(),
        };
 Prepared{ctx,decl_order,decls,known,file_paths:files.iter().map(|(rel,_)|(*rel).to_owned()).collect()}
}
pub(crate) fn judge_file(file:&SourceFile,prepared:&Prepared)->FileOut{let ctx=&prepared.ctx;
        let look = Look {
            ss: ctx.ss_owner.iter().map(|(k, v)| (k.as_str(), v.as_str())).collect(),
            services: ctx.service_owner.iter().map(|(k, d, t)| (k.as_str(), (d.as_str(), t.as_str()))).collect(),
            systems: ctx.system_owner.iter().map(|(k, v)| (k.as_str(), v.as_str())).collect(),
        };
 judge(file,ctx,&look)
}
pub(crate) fn finish(prepared:&Prepared,results:&[(String,FileOut)],out:&mut Sink){
 let ctx=&prepared.ctx;let decl_order=&prepared.decl_order;let decls=&prepared.decls;let known=&prepared.known;
        let rule_names = ["B1", "B2", "B3", "B4"];
        let mut system_called_from: HashSet<&str> = HashSet::new();
        for (rel, fo) in results {
            for (rule, line, key, text) in &fo.hits {
                out.site_keyed(rule_names[*rule as usize], rel, *line as usize, text.clone(), key.clone());
            }
            system_called_from.extend(fo.called.iter().map(|s| s.as_str()));
        }

        // B5: cycles in needs, and needs that name nothing.
        let mut graph_order: Vec<String> = Vec::new();
        let mut graph: HashMap<String, Vec<String>> = HashMap::new();
        for t in decl_order {
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
        for typ in decl_order {
            for need in decls[typ].needs.iter().flatten() {
                if !known.contains(need) {
                    let text = format!("{} needs {}, which no file declares", typ, need);
                    hit(out, "B5", format!("B5:unknown:{}->{}", typ, need), &text, 0, text.clone());
                }
            }
        }

        // B6: emitted events are declared (once the system declares `emits`).
        let with_b6: Vec<(usize, &FileOut)> = results.iter().enumerate().filter_map(|(index,(_,result))| (!result.b6.is_empty()).then_some((index,result))).collect();
        for (ti, (typ, _)) in ctx.system_owner.iter().enumerate() {
            for (fi, fo) in &with_b6 {
                let rel = results[*fi].0.as_str();
                for (t, number, evt) in &fo.b6 {
                    if *t as usize == ti {
                        hit(out, "B6", format!("B6:{}:{}", rel, typ), rel, *number as usize, format!("{}:{} emits {}", rel, number, evt));
                    }
                }
            }
        }

        // B7: api.dm iff other folders call the system.
        for (typ, owner_dir) in ctx.system_owner.iter() {
            let has_api = prepared.file_paths.contains(format!("{}/api.dm", owner_dir).as_str());
            let called = system_called_from.contains(typ.as_str());
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

pub(crate) fn facts_bytes(facts:&Facts)->Option<usize>{
 let mut n=std::mem::size_of::<Facts>();
 macro_rules! add{($value:expr)=>{n=n.checked_add($value)?;}}
 macro_rules! strings{($values:expr)=>{{let values=$values;add!(values.capacity().checked_mul(std::mem::size_of::<String>())?);for value in values{add!(value.capacity());}}}}
 strings!(&facts.ss_defs);add!(facts.service_defs.capacity().checked_mul(std::mem::size_of::<(String,String)>())?);for(a,b)in &facts.service_defs{add!(a.capacity());add!(b.capacity());}
 strings!(&facts.system_types);strings!(&facts.types);strings!(&facts.api_procs);
 add!(facts.entries.capacity().checked_mul(std::mem::size_of::<(String,u8,Vec<String>)>())?);for(name,_,values)in &facts.entries{add!(name.capacity());strings!(values);}Some(n)
}
pub(crate) fn prepared_headroom(files:&[(&str,&Facts)])->Option<usize>{
 // The original preparation clones these metadata strings into tree/hash tables.
 // Reserve before construction, including conservative per-node/map capacity.
 let mut bytes=8192usize;let mut systems=0usize;let mut all_api=0usize;
 for(relative,facts)in files{systems=systems.checked_add(facts.system_types.len())?;for name in &facts.api_procs{all_api=all_api.checked_add(name.capacity().checked_add(4096)?)?;}let actual=facts_bytes(facts)?;let entries=facts.ss_defs.len().checked_add(facts.service_defs.len())?.checked_add(facts.system_types.len())?.checked_add(facts.types.len())?.checked_add(facts.entries.len())?.checked_add(facts.api_procs.len())?;
  bytes=bytes.checked_add(actual.checked_mul(8)?)?.checked_add(entries.checked_mul(4096)?)?.checked_add(relative.len().checked_mul(8)?)?.checked_add(4096)?;
 }bytes.checked_add(systems.checked_mul(all_api.checked_mul(4)?)?)
}
pub(crate) fn result_bytes(result:&FileOut)->Option<usize>{
 let mut n=std::mem::size_of::<FileOut>().checked_add(result.hits.capacity().checked_mul(std::mem::size_of::<(u8,u32,String,String)>())?)?.checked_add(result.called.capacity().checked_mul(std::mem::size_of::<String>())?)?.checked_add(result.b6.capacity().checked_mul(std::mem::size_of::<(u32,u32,String)>())?)?;
 for(_,_,key,text)in &result.hits{n=n.checked_add(key.capacity())?.checked_add(text.capacity())?;}for value in &result.called{n=n.checked_add(value.capacity())?;}for(_,_,value)in &result.b6{n=n.checked_add(value.capacity())?;}Some(n)
}
