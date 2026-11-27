//! `analyze sem model-parity`: the view ([`super::Model`]) against the converted dreammaker tree it replaces, on the declarations every
//! lint reads: the type set and parents, each type's own vars (declared or overridden, declared type, static/const/tmp, the declaration's
//! file and line, the last assignment's line) and procs (how many definitions, each one's file and line, parameter names). Prints a
//! count per category and the first differences of each; exit 0 only when nothing differs.

use std::collections::{BTreeMap, BTreeSet};

use dm_tree::MemberKind;

use super::{Member, Model};
use crate::sem::Sem;

/// The converted tree's file and line of `loc` (none for a builtin).
fn at(sem: &Sem, loc: dreammaker::Location) -> Option<(String, u32)> {
    (!loc.is_builtins()).then(|| (sem.rel(loc).to_string(), loc.line))
}

#[derive(Default)]
struct Tally {
    compared: usize,
    differ: usize,
    examples: Vec<String>,
}

impl Tally {
    fn check(&mut self, same: bool, example: impl FnOnce() -> String) {
        self.compared += 1;
        if !same {
            self.differ += 1;
            if self.examples.len() < examples_per() {
                self.examples.push(example());
            }
        }
    }
}

fn examples_per() -> usize {
    dq_hostio::var("DQ_PARITY_EXAMPLES").ok().and_then(|v| v.parse().ok()).unwrap_or(5)
}

fn declared_text(type_path: &[String]) -> String {
    if type_path.is_empty() {
        String::new()
    } else {
        format!("/{}", type_path.join("/"))
    }
}

/// Runs the comparison; returns the number of differences.
pub fn run(sem: &Sem, model: &Model) -> usize {
    let mut tallies: BTreeMap<&'static str, Tally> = BTreeMap::new();
    let tree = &sem.objtree;
    let mut converted: BTreeSet<String> = BTreeSet::new();
    for ty in tree.iter_types() {
        let t = ty.get();
        let path = if t.path.is_empty() { "/".to_string() } else { t.path.clone() };
        converted.insert(path.clone());
        let native = model.ty(&path);
        tallies.entry("type present").or_default().check(native.is_some(), || format!("{path}: no native type (builtin: {})", t.location.is_builtins()));
        let Some(native) = native else { continue };
        let parent = ty.parent_type().map(|p| if p.get().path.is_empty() { "/".to_string() } else { p.get().path.clone() });
        let nparent = native.parent().map(|p| p.path().to_string());
        tallies.entry("type parent").or_default().check(parent == nparent, || format!("{path}: parent {parent:?} vs {nparent:?}"));
        // The root's location is the `.dme`'s own file in dreammaker's tree; the view has none (nothing reads it).
        if !t.location.is_builtins() && path != "/" {
            let line = at(sem, t.location);
            let nline = native.site().and_then(|s| model.line(s));
            tallies.entry("type site").or_default().check(line == nline, || format!("{path}: {line:?} vs {nline:?}"));
        }

        // Vars: dreammaker keeps one entry per name (the declaration, if any, and the last assignment).
        let mut nvars: BTreeMap<&str, Vec<Member<'_>>> = BTreeMap::new();
        for m in native.vars() {
            nvars.entry(m.name()).or_default().push(m);
        }
        let builtins = super::builtins::get();
        let bvars = builtins.vars.get(path.as_str());
        let dnames: BTreeSet<&str> = t.vars.keys().map(|k| k.as_str()).collect();
        let mut nnames: BTreeSet<&str> = nvars.keys().copied().collect();
        nnames.extend(bvars.into_iter().flatten().map(|(n, _)| n.as_str()));
        // `parent_type = /x` is the type's explicit parent in the semantic tree, a var override in dreammaker's.
        let explicit = native.explicit_parent();
        if explicit.is_some_and(|(_, site)| site.is_some()) {
            nnames.insert("parent_type");
        }
        for name in dnames.symmetric_difference(&nnames) {
            let builtin = t.vars.get(*name).is_some_and(|v| v.value.location.is_builtins());
            tallies.entry("var names").or_default().check(false, || format!("{path}/{name}: only {} (builtin {builtin})", if dnames.contains(name) { "converted" } else { "native" }));
        }
        for (name, v) in &t.vars {
            let builtin = builtins.var(&path, name);
            if !nnames.contains(name.as_str()) {
                continue;
            }
            tallies.entry("var names").or_default().check(true, String::new);
            let empty = Vec::new();
            let members = nvars.get(name.as_str()).unwrap_or(&empty);
            let declaration = members.iter().find(|m| m.declares());
            let declares = declaration.is_some() || builtin.is_some_and(|b| b.declares);
            tallies.entry("var declared").or_default().check(v.declaration.is_some() == declares, || {
                format!("{path}/{name}: converted declares {} native {}", v.declaration.is_some(), declares)
            });
            if let (Some(d), None, Some(b)) = (&v.declaration, declaration, builtin) {
                let dt = declared_text(&d.var_type.type_path);
                tallies.entry("var builtin type").or_default().check(dt == b.declared, || format!("{path}/{name}: {dt:?} vs {:?}", b.declared));
            }
            if let (Some(d), Some(n)) = (&v.declaration, declaration) {
                let dt = declared_text(&d.var_type.type_path);
                tallies.entry("var declared type").or_default().check(dt == n.declared_type(), || format!("{path}/{name}: {dt:?} vs {:?}", n.declared_type()));
                let f = d.var_type.flags;
                let bits = n.flags();
                let same = f.is_static() == (bits & (1 | 8) != 0) && f.is_const() == (bits & 2 != 0) && f.is_tmp() == (bits & 4 != 0);
                tallies.entry("var flags").or_default().check(same, || format!("{path}/{name}: {f:?} vs {bits:#x}"));
                let line = at(sem, d.location);
                let nline = n.site().and_then(|s| model.line(s));
                tallies.entry("var declaration line").or_default().check(line == nline, || format!("{path}/{name}: {line:?} vs {nline:?}"));
            }
            if !v.value.location.is_builtins() {
                let line = at(sem, v.value.location);
                let nline = if name == "parent_type" {
                    explicit.and_then(|(_, site)| site).and_then(|s| model.line(s))
                } else {
                    members.last().and_then(|m| m.site()).and_then(|s| model.line(s))
                };
                tallies.entry("var value line").or_default().check(line == nline, || format!("{path}/{name}: {line:?} vs {nline:?}"));
            }
        }

        // Procs: one entry per name, a value per definition in order.
        let mut nprocs: BTreeMap<&str, Vec<Member<'_>>> = BTreeMap::new();
        for m in native.procs() {
            nprocs.entry(m.name()).or_default().push(m);
        }
        for (name, p) in &t.procs {
            if p.value.iter().any(|v| v.location.is_builtins()) {
                let b = builtins.proc(&path, name);
                let same = b.is_some_and(|b| {
                    let params: Vec<&str> = p.value.iter().find(|v| v.location.is_builtins()).map(|v| v.parameters.iter().map(|q| q.name.as_str()).collect()).unwrap_or_default();
                    params == b.parameters.iter().map(String::as_str).collect::<Vec<_>>()
                });
                tallies.entry("proc builtin").or_default().check(same, || format!("{path}/{name}: builtin missing or parameters differ"));
            }
            let values: Vec<_> = p.value.iter().filter(|v| !v.location.is_builtins()).collect();
            let members = nprocs.get(name.as_str()).cloned().unwrap_or_default();
            tallies.entry("proc definitions").or_default().check(values.len() == members.len(), || {
                format!("{path}/{name}: {} converted vs {} native", values.len(), members.len())
            });
            if values.len() != members.len() {
                continue;
            }
            if values.is_empty() {
                continue;
            }
            let verb = p.declaration.as_ref().map(|d| d.kind == dreammaker::ast::ProcDeclKind::Verb);
            let nverb = members.iter().find(|m| m.declares()).map(|m| m.kind() == MemberKind::Verb).or_else(|| builtins.proc(&path, name).filter(|b| b.declares).map(|b| b.verb));
            tallies.entry("proc kind").or_default().check(verb == nverb, || format!("{path}/{name}: verb {verb:?} vs {nverb:?}"));
            for (v, m) in values.iter().zip(&members) {
                let line = at(sem, v.location);
                let nline = m.site().and_then(|s| model.line(s));
                tallies.entry("proc line").or_default().check(line == nline, || format!("{path}/{name}: {line:?} vs {nline:?}"));
                let params: Vec<&str> = v.parameters.iter().map(|q| q.name.as_str()).collect();
                let nparams = m.parameter_names();
                tallies.entry("proc parameters").or_default().check(params == nparams, || format!("{path}/{name}: {params:?} vs {nparams:?}"));
            }
        }
        for name in nprocs.keys() {
            if !t.procs.contains_key(*name) {
                tallies.entry("proc definitions").or_default().check(false, || format!("{path}/{name}: only native"));
            }
        }
    }
    for ty in model.types() {
        if !converted.contains(ty.path()) {
            tallies.entry("type present").or_default().check(false, || format!("{}: only native (synthetic {})", ty.path(), ty.synthetic()));
        }
    }
    let mut total = super::body_parity::run(sem, model, examples_per()) + super::value_parity::run(sem, model, examples_per());
    for (name, t) in &tallies {
        total += t.differ;
        println!("{name:<22} {:>8} compared {:>7} differ", t.compared, t.differ);
        for e in &t.examples {
            println!("    {e}");
        }
    }
    println!("MODEL PARITY: {} difference(s)", total);
    total
}
