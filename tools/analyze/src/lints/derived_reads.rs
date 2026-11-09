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


use crate::lint::{Cx, Lint, Meta, Registry, Run, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{SourceFile, Tree, CODE_DM};
use crate::util::{is_py_space, py_lstrip, py_rstrip, py_strip};
use crate::{pat, pat_match};
use crate::reactive_reaction_policy::{GENERATED_SKIP_DIRS,EXEMPT_VARS};
pub(crate) use crate::reactive_reaction_policy::GENERATED_REL;

const LINT: &str = "derived_reads";
const MODIFIERS: &[&str] = &["tmp", "static", "global", "const", "final"];
const OBJECT_ROOTS: &[&str] = &["datum", "obj", "mob", "atom", "turf", "area", "client", "image", "list"];


use crate::derived_reads_metadata::META;

// ---- small mappings ---------------------------------------------------------------------------

use crate::derived_reads_collect_policy::{proc_kind,derive_value,chain,paren_args};

use crate::derived_reads_policy::kind_call;

/// `(kind, handler, roots, output vars)` in `REACTION_OUTPUTS` order.

fn starts_any(rel: &str, dirs: &[&str]) -> bool {
    dirs.iter().any(|d| rel.starts_with(d))
}

// ---- types ------------------------------------------------------------------------------------

/// `state_schema_lint.ancestors`: every path prefix, shortest first.
// ---- parsing ----------------------------------------------------------------------------------

type VarTable = HashMap<String, HashSet<String>>;



fn note_typed(typed: &mut VarTable, owner: &str, segs: &[&str], name: &str) {
    let segs: Vec<&&str> = segs.iter().filter(|s| !s.is_empty() && !MODIFIERS.contains(*s)).collect();
    if segs.len() > 1 && OBJECT_ROOTS.contains(segs[0]) {
        typed.entry(owner.to_string()).or_default().insert(name.to_string());
    }
}

/// `parse_vars`: `{type: var names}` declared in one file's `code_only` lines; `typed` collects the
/// object-typed ones.
fn parse_vars(lines:&[&str],typed:&mut VarTable)->VarTable{
 let mut found=VarTable::new();let result=crate::reactive_reaction_policy::visit_variable_lines(lines.iter().enumerate().map(|(n,line)|(n+1,*line)),&mut crate::key_policy_control::Compatibility,|_,row|{
  let owner=format!("/{}",row.owner_without_leading_slash);let segs:Vec<&str>=row.qualified.split('/').collect();found.entry(owner.clone()).or_default().insert(row.name.to_owned());note_typed(typed,&owner,&segs,row.name);Ok(true)
 });match result{Ok(_)=>found,Err(never)=>match never{}}
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



/// Every proc keeps its body: a draw's reads include those of the procs it calls (`drawn_helper_reads`), so any proc may be a helper.
fn keeps_body(_name: &str) -> bool {
    true
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
            if let Some(header)=crate::reactive_reaction_policy::header(line){
                cur=Some(Proc{rel:rel.to_owned(),owner:header.owner.to_owned(),name:header.name.to_owned(),args:header.args.to_owned(),start:number,body:Vec::new()});
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

use crate::derived_entry_policy::Entry;
/// Same unique lexical entry policy on the legacy adapter's borrowed body.
fn parse_entries(proc:&Proc)->Vec<Entry>{
 let view=crate::reactive_reaction_policy::Procedure{owner:&proc.owner,name:&proc.name,relative:&proc.rel,args:&proc.args,lines:crate::reactive_reaction_policy::Lines::Owned(&proc.body)};
 match crate::derived_entry_policy::entries(view,proc.start,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}
}

/// `body_reads`: `(var, first line)` for each var in `known` the proc body reads, in read order.
fn body_reads(proc:&Proc,known:&HashSet<String>)->Vec<(String,usize)>{
 let view=crate::reactive_reaction_policy::Procedure{owner:&proc.owner,name:&proc.name,relative:&proc.rel,args:&proc.args,lines:crate::reactive_reaction_policy::Lines::Owned(&proc.body)};
 match crate::reactive_reaction_policy::body_reads(&view,known,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}
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
    let code=f.code();let mut schema=match crate::derived_schema_policy::file(code,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}};
    fn table(value:crate::derived_schema_policy::Table)->VarTable{value.into_iter().map(|(owner,names)|(owner,names.into_iter().collect())).collect()}
    let mut procs = Vec::new();
    let mut entries = Vec::new();
    for mut proc in parse_procs(&f.rel, code) {
        let trimmed = proc.owner.trim_end_matches('/');
        proc.owner = if trimmed.is_empty() { "/".to_string() } else { trimmed.to_string() };
        let borrowed=crate::reactive_reaction_policy::Procedure{owner:&proc.owner,name:&proc.name,relative:&proc.rel,args:&proc.args,lines:crate::reactive_reaction_policy::Lines::Owned(&proc.body)};
        match crate::derived_schema_policy::relations(&mut schema,borrowed,&mut crate::key_policy_control::Compatibility){Ok(())=>(),Err(never)=>match never{}}
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
    Parts{vars:table(schema.vars),typed:table(schema.typed),tracked:table(schema.tracked),relations:table(schema.relations),published:schema.published,procs,entries}
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
                            local: e.local,
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
                        .map(|e| {
                            let mut local = e.local;
                            local.sort_unstable();
                            local.dedup();
                            Entry {
                                rel: e.rel,
                                line: e.line,
                                kind: intern_kind(&e.kind),
                                name: e.name,
                                local,
                                remote: e.remote,
                                hops: e.hops,
                            }
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

use crate::derived_reads_judge::{self as judge,Finding,Table,Facts};
struct JudgeFacts<'a>{model:&'a Model,tree:&'a Tree,sink:std::cell::RefCell<&'a mut Sink>,never_written:&'a dyn Fn(&str,&str)->bool}
impl Facts for JudgeFacts<'_>{
 type Error=std::convert::Infallible;type Known<'a>=HashSet<String> where Self:'a;
 fn known<'a>(&'a self,owner:&'a str)->Result<Self::Known<'a>,Self::Error>{Ok(self.model.union(&self.model.vars,owner))}
 fn has(&self,t:Table,owner:&str,name:&str)->Result<bool,Self::Error>{Ok(match t{Table::Tracked=>self.model.union(&self.model.tracked,owner).contains(name),Table::Relation=>self.model.union(&self.model.relations,owner).contains(name),Table::Object=>self.model.union(&self.model.object_vars,owner).contains(name),Table::Derived=>self.model.declared_derive(owner).contains_key(name)})}
 fn exact(&self,owner:&str)->Result<bool,Self::Error>{Ok(self.model.exact(owner))}
 fn declared_value(&self,owner:&str,value:&str)->Result<bool,Self::Error>{Ok(self.model.declared_derive(owner).contains_key(value))}
 fn declared_read(&self,owner:&str,kind:&str,value:Option<&str>,name:&str)->Result<bool,Self::Error>{Ok(match value{Some(value)=>self.model.declared_derive(owner).get(value).is_some_and(|set|set.contains(name)),None=>self.model.declared(owner,kind).contains(name)})}
 fn published(&self,owner:&str,name:&str)->Result<bool,Self::Error>{Ok(self.model.published_key(owner,name).is_some())}
 fn never_written(&self,owner:&str,name:&str)->Result<bool,Self::Error>{Ok((self.never_written)(owner,name))}
 fn allowed(&self,rel:&str,line:usize)->Result<bool,Self::Error>{Ok(raw_allowed(self.tree,&mut self.sink.borrow_mut(),rel,line))}
}
fn raw_allowed(tree:&Tree,sink:&mut Sink,rel:&str,line:usize)->bool{match tree.get(rel){Some(f)=>sink.allowed(f,line,LINT),None=>false}}
fn procedure(proc:&Proc)->crate::reactive_reaction_policy::Procedure<'_>{crate::reactive_reaction_policy::Procedure{owner:&proc.owner,name:&proc.name,relative:&proc.rel,args:&proc.args,lines:crate::reactive_reaction_policy::Lines::Owned(&proc.body)}}
fn checked_legacy(result:Result<(),std::convert::Infallible>){match result{Ok(())=>(),Err(never)=>match never{}}}
fn analyze(model:&Model,tree:&Tree,sink:&mut Sink,generated_covers:bool)->Vec<Finding>{
 let writers:Option<(Arc<crate::sem::reads::WriteIndex>,Arc<BTreeSet<String>>)>=if generated_covers{crate::sem::sem_for(tree).map(|sem|(crate::gens::auto_tracked::writes_outside_setters_of(tree,&sem),crate::gens::auto_tracked::set_calls(tree)))}else{None};
 let sem_model=if generated_covers{crate::sem::sem_for(tree)}else{None};let never_written=|owner:&str,name:&str|{let constant=sem_model.as_ref().and_then(|s|s.var_decl(owner,name)).is_some_and(|v|v.is_static||v.is_const);constant||writers.as_ref().is_some_and(|(w,c)|!sem_model.as_ref().is_some_and(|s|w.is_written_on(s,owner,name))&&!c.contains(name)&&!c.contains(&format!("{}[]",name)))};
 let facts=JudgeFacts{model,tree,sink:std::cell::RefCell::new(sink),never_written:&never_written};let mut findings=Vec::new();let mut output=|f|{findings.push(f);Ok(())};let mut control=crate::key_policy_control::Compatibility;
 for p in &model.procs{checked_legacy(judge::reactive(&facts,procedure(p),generated_covers,&mut control,&mut output))}
 for p in &model.procs{checked_legacy(judge::exact(&facts,procedure(p),p.start,&mut control,&mut output))}
 for owner in &model.entry_order{for e in &model.entries[owner]{checked_legacy(judge::entry(&facts,owner,e,&mut control,&mut output))}}
 for r in reaction_reads(model){checked_legacy(judge::reaction(&facts,procedure(&model.procs[r.proc]),r.kind,&r.reads,&mut control,&mut output))}
 findings.sort_by(judge::compare);findings
}

// ---- presentation reactions -------------------------------------------------------------------

struct ReactionRead {
    kind: &'static str,
    handler: &'static str,
    proc: usize,
    reads: Vec<(String, usize)>,
}

fn reaction_reads(model:&Model)->Vec<ReactionRead>{
 struct Original<'model>(&'model Model);
 impl crate::reactive_reaction_policy::Source for Original<'_>{
  type Error=std::convert::Infallible;type Known<'a>=HashSet<String> where Self:'a;
  fn for_each_named(&self,name:&str,visit:&mut dyn FnMut(crate::reactive_reaction_policy::ProcedureKey<'_>,crate::reactive_reaction_policy::Procedure<'_>)->Result<bool,Self::Error>)->Result<(),Self::Error>{
   for(index,proc)in self.0.procs.iter().enumerate(){if proc.name==name&&!visit(crate::reactive_reaction_policy::ProcedureKey::Legacy(index),crate::reactive_reaction_policy::Procedure{owner:&proc.owner,name:&proc.name,relative:&proc.rel,args:&proc.args,lines:crate::reactive_reaction_policy::Lines::Owned(&proc.body)})?{break}}Ok(())
  }
  fn known<'a>(&'a self,owner:&'a str)->Result<Self::Known<'a>,Self::Error>{Ok(self.0.union(&self.0.vars,owner))}
 }
 let original=Original(model);let result=crate::reactive_reaction_policy::reaction_reads(&original,&mut crate::key_policy_control::Compatibility);let rows=match result{Ok(value)=>value,Err(never)=>match never{}};
 rows.into_iter().map(|row|ReactionRead{kind:row.kind,handler:row.handler,proc:match row.procedure{crate::reactive_reaction_policy::OwnedProcedureKey::Legacy(index)=>index,crate::reactive_reaction_policy::OwnedProcedureKey::Raw{..}=>unreachable!("legacy adapter issued a raw locator")},reads:row.reads}).collect()
}

fn reaction_findings(model:&Model,tree:&Tree,sink:&mut Sink)->Vec<Finding>{
 let never=|_:&str,_:&str|false;let facts=JudgeFacts{model,tree,sink:std::cell::RefCell::new(sink),never_written:&never};let mut out=Vec::new();for r in reaction_reads(model){checked_legacy(judge::reaction(&facts,procedure(&model.procs[r.proc]),r.kind,&r.reads,&mut crate::key_policy_control::Compatibility,&mut|f|{out.push(f);Ok(())}))}out
}

// ---- generated reads --------------------------------------------------------------------------

fn reaction_declarations(model:&Model)->(BTreeMap<String,BTreeSet<&'static str>>,Vec<String>){let mut flags=BTreeMap::new();let mut members=BTreeSet::new();for proc in &model.procs{if proc.name!="reactions"||proc.owner=="/"||starts_any(&proc.rel,GENERATED_SKIP_DIRS)||proc.rel==GENERATED_REL{continue}match crate::derived_reads_collect_policy::boot_declarations(&proc.owner,proc.body.iter().map(|(number,line)|(*number,line.as_str())),&mut flags,&mut members,&mut crate::key_policy_control::Compatibility){Ok(())=>{},Err(never)=>match never{}}}(flags,members.into_iter().collect())}


/// The `(type, var)` pairs the presentation reactions (Life steps, HUD, sight, canmove: `REACTION_OUTPUTS`) read off the holder, whatever declares the var.
/// A reaction is reactive code: read-driven tracking (`gens::auto_tracked`) tracks what it reads.
pub(crate) fn reaction_read_pairs(tree: &Tree, files: &[&SourceFile]) -> BTreeSet<(String, String)> {
    let model = Model::get(tree, files);
    let mut out = BTreeSet::new();
    for r in reaction_reads(&model) {
        let owner = &model.procs[r.proc].owner;
        for (name, _) in &r.reads {
            out.insert((owner.clone(), name.clone()));
        }
    }
    out
}

/// The text of `code/_generated/reads.dm` for these files (the `derived_reads` generator, `analyze gen derived_reads`, writes it).
pub(crate) fn generated_for(tree: &Tree, files: &[&SourceFile]) -> String {
    generated_text(&Model::get(tree, files), &crate::sem::gen::test_only_types(tree))
}

/// The names an unscoped call (`name(`, `src.name(`) in a proc body invokes. `..()` and `obj.name()` are not named.
fn called_names(proc:&Proc)->Vec<String>{match crate::derived_reads_collect_policy::called_names(proc.body.iter().map(|(number,line)|(*number,line.as_str())),&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}}

/// A draw (or hidden_verbs) reads what the procs it calls read, on its own type and its parents, transitively: the reads of a callee
/// belong to the drawn type; an override of a callee on a subtype is a read of that subtype (the call is virtual). The walk visits each
/// proc once, so a recursive helper ends. Names are matched by proc name, so a read is over-approximated, never missed.
fn drawn_helper_reads(model: &Model, per_owner: &mut BTreeMap<String, BTreeMap<(String, String), Vec<String>>>) {
    let mut by_name: HashMap<&str, Vec<&Proc>> = HashMap::new();
    for p in &model.procs {
        if p.owner == "/" || starts_any(&p.rel, GENERATED_SKIP_DIRS) || p.rel == GENERATED_REL || p.owner.starts_with("/datum/capability") {
            continue;
        }
        by_name.entry(p.name.as_str()).or_default().push(p);
    }
    for d in &model.procs {
        if proc_kind(&d.name) != Some("drawn")
            || d.owner == "/"
            || starts_any(&d.rel, GENERATED_SKIP_DIRS)
            || d.rel == GENERATED_REL
            || d.owner.starts_with("/datum/capability")
        {
            continue;
        }
        let holder_chain = chain(&d.owner);
        let mut seen: HashSet<(String, usize)> = HashSet::new();
        seen.insert((d.rel.clone(), d.start));
        let mut queue: Vec<&Proc> = vec![d];
        let mut reached: Vec<&Proc> = Vec::new();
        while let Some(p) = queue.pop() {
            for callee in called_names(p) {
                for q in by_name.get(callee.as_str()).map(|v| v.as_slice()).unwrap_or(&[]) {
                    let above = holder_chain.contains(&q.owner);
                    if !above && !chain(&q.owner).contains(&d.owner) {
                        continue;
                    }
                    if seen.insert((q.rel.clone(), q.start)) {
                        queue.push(q);
                        reached.push(q);
                    }
                }
            }
        }
        for q in reached {
            let holder = if holder_chain.contains(&q.owner) { d.owner.clone() } else { q.owner.clone() };
            let known = model.union(&model.vars, &holder);
            let slot = per_owner.entry(holder).or_default().entry(("drawn".to_string(), String::new())).or_default();
            for (name, _) in body_reads(q, &known) {
                if !slot.contains(&name) {
                    slot.push(name);
                }
            }
        }
    }
}

fn generated_text(model: &Model, test_types: &BTreeSet<String>) -> String {
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
    drawn_helper_reads(model, &mut per_owner);
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
    let(flags,members)=reaction_declarations(model);
    crate::derived_reads_policy::generate(&per_owner,&reaction_slots,&flags,&members,test_types)
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
        for f in analyze(&model, cx.tree, out, true) {
            out.site_in(f.rule, &f.rel, f.line);
        }
    }

    fn post_judge(&self, cx: &Cx, _run: &Run, text: &mut String) -> bool {
        let files = cx.files();
        let model = Model::get(cx.tree, &files);
        let want = generated_text(&model, &crate::sem::gen::test_only_types(cx.tree));
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
            blank: &[],
            parse: ParseKind::Tagged,
            update: Some(&["tools/ci/derived_reads_lint.py", "--update"]),
            seed: Some(&["tools/ci/derived_reads_lint.py", "--seed"]),
            files: &[],
            selftest: Some(&["tools/ci/derived_reads_lint.py", "--selftest"]),
        })
    }
}

pub(crate) fn captured_metadata()->&'static Meta{&META}

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
    let found = analyze(&model, &tree, &mut sink, false);
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
    let text = generated_text(&model, &BTreeSet::new());
    check(
        "generated reads",
        text.contains("/obj/pointer/generated_reads()")
            && text.contains("runs_while(nameof(energy), nameof(max_energy))")
            && text.contains("drawn_from(nameof(pointing))"),
        text.clone(),
    );
    let (_, model2) = model_of(&[("code/a.dm", declared.clone())]);
    check("generated is stable", generated_text(&model2, &BTreeSet::new()) == text, String::new());
    // 10: a draw reads what the procs it calls read, transitively; a subtype's override is a read of the subtype; recursion ends
    let helper_fixture = tabs("
/obj/lamp
	var/lit = FALSE
	var/spare = 0
/obj/lamp/draw(datum/look/look)
	..()
	draw_state(look)
/obj/lamp/proc/draw_state(datum/look/look)
	look.state(state_name())
	draw_state(look)
/obj/lamp/proc/state_name()
	return lit ? \"on\" : \"off\"
/obj/lamp/big
	var/extra = 0
/obj/lamp/big/state_name()
	return extra ? \"x\" : \"y\"
");
    let (_, hmodel) = model_of(&[("code/h.dm", helper_fixture)]);
    let htext = generated_text(&hmodel, &BTreeSet::new());
    let lamp = htext.split("/obj/lamp/big/generated_reads()").next().unwrap_or("");
    let big = htext.split("/obj/lamp/big/generated_reads()").nth(1).unwrap_or("");
    check(
        "a draw follows the procs it calls",
        lamp.contains("drawn_from(nameof(lit))") && !htext.contains("nameof(spare)"),
        htext.clone(),
    );
    check("an override on a subtype is that subtype's read", big.contains("drawn_from(nameof(extra))"), htext.clone());
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
    let boot = generated_text(&model, &BTreeSet::new());
    check("boot types", boot.contains("/obj/pump = RXB_EVERY | RXB_NOTICE,") && boot.contains("/datum/capability/pumped,"), boot);
    if bad.is_empty() {
        Ok("derived_reads_lint selftest passed".to_string())
    } else {
        Err(bad.join("; "))
    }
}
