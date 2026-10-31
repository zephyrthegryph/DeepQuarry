//! Test-only independent actual old visitor; no new shared receiver core calls.
use std::{collections::HashMap};
use dreammaker::ast::{Expression,Follow,Term};
use crate::sem::Sem;
const AUTO_REL:&str="code/engine/_generated/auto_tracked.dm";const TRACKED_LISTS_REL:&str="code/engine/_generated/tracked_lists.dm";const UNTYPED:&str="?";const SETTER_PREFIXES:&[&str]=&["set_","add_","include_","remove_","clear_","insert_","swap_","cut_"];
fn fact(sem:&Sem,p:dreammaker::objtree::ProcRef)->Vec<(String,String)>{
            let owner = if p.ty().get().path.is_empty() { "/".to_string() } else { p.ty().get().path.clone() };
            let owner = &owner;
            let mut hits: Vec<(String, String)> = Vec::new();
            let Some(code) = &*p.get().code else { return hits };
            let mut locals: HashMap<String, String> = HashMap::new();
            for prm in p.get().parameters.iter() {
                if !prm.var_type.type_path.is_empty() {
                    locals.insert(prm.name.clone(), format!("/{}", prm.var_type.type_path.join("/")));
                }
            }
            collect_local_types(code, &mut locals);
            let is_call = |n: &str| SETTER_PREFIXES.iter().any(|p| n.starts_with(p));
            crate::sem::ast::walk_block(code, &mut |e, _| {
                let Expression::Base { term, follow } = e else { return };
                let mut cur: Option<String> = match &term.elem {
                    Term::Ident(n) if n.as_str() == "src" => Some(owner.clone()),
                    Term::Ident(n) => locals.get(n).cloned().or_else(|| sem.var_decl(owner, n).map(|v| v.declared).filter(|d| !d.is_empty())),
                    Term::Call(n, _) => {
                        if is_call(n) {
                            hits.push((n.as_str().to_string(), owner.clone()));
                        }
                        None
                    }
                    _ => None,
                };
                for fo in follow.iter() {
                    match &fo.elem {
                        Follow::Field(_, n) => cur = cur.and_then(|c| sem.var_decl(&c, n.as_str())).map(|v| v.declared).filter(|d| !d.is_empty()),
                        Follow::Call(_, n, _) => {
                            if is_call(n.as_str()) {
                                hits.push((n.as_str().to_string(), cur.clone().unwrap_or_else(|| UNTYPED.to_string())));
                            }
                            cur = None;
                        }
                        _ => cur = None,
                    }
                }
            });
            hits
        }
fn collect_local_types(b: &dreammaker::ast::Block, out: &mut HashMap<String, String>) {
    use dreammaker::ast::Statement;
    for st in b.iter() {
        match &st.elem {
            Statement::Var(vs) if !vs.var_type.type_path.is_empty() => {
                out.insert(vs.name.clone(), format!("/{}", vs.var_type.type_path.join("/")));
            }
            Statement::Vars(list) => {
                for vs in list.iter().filter(|v| !v.var_type.type_path.is_empty()) {
                    out.insert(vs.name.clone(), format!("/{}", vs.var_type.type_path.join("/")));
                }
            }
            Statement::ForList(fl) => {
                if let Some(vt) = fl.var_type.as_ref().filter(|v| !v.type_path.is_empty()) {
                    out.insert(fl.name.as_str().to_string(), format!("/{}", vt.type_path.join("/")));
                }
            }
            _ => {}
        }
        for nb in crate::sem::ast::stmt_blocks(&st.elem) {
            collect_local_types(nb, out);
        }
    }
}
pub fn collect(sem:&Sem)->Vec<(String,String)>{let mut rows=Vec::new();for ty in sem.objtree.iter_types(){for procedure in ty.iter_self_procs(){if procedure.is_builtin()||matches!(sem.file_of(procedure.get().location),Some(AUTO_REL)|Some(TRACKED_LISTS_REL)){continue}rows.extend(fact(sem,procedure));}}rows.sort();rows.dedup();rows}
#[test]fn frozen_original_fact_and_typed_local_walk_are_exact(){let frozen=include_str!("typed_set_calls_frozen_original.rs");let marker="let fact = |p: dreammaker::objtree::ProcRef| -> Vec<(String, String)> {";let typed=frozen.find("pub fn typed_set_calls(").unwrap();let start=frozen[typed..].find(marker).unwrap()+typed+marker.len();let end=frozen[start..].find("\n        };\n        crate::sem::body_facts::indexed").unwrap()+start;assert_eq!(frozen[start..end].trim_end(),include_str!("typed_set_calls_reference.rs").split_once("fn fact(sem:&Sem,p:dreammaker::objtree::ProcRef)->Vec<(String,String)>{").unwrap().1.split_once("\nfn collect_local_types(").unwrap().0.strip_suffix('}').unwrap().trim_end());let old=frozen.split_once("fn collect_local_types(").unwrap().1.split_once("\n/// Whether a `set_v(").unwrap().0;let projected=include_str!("typed_set_calls_reference.rs").split_once("fn collect_local_types(").unwrap().1.split_once("\npub fn collect(").unwrap().0;assert_eq!(old.trim_end(),projected.trim_end());}

use crate::tree::Tree;
fn from_tracked_macro(tree: &Tree, sem: &crate::sem::Sem, loc: dreammaker::Location) -> bool {
    let Some(rel) = sem.file_of(loc) else { return false };
    let Some(f) = tree.get(rel) else { return false };
    f.raw().lines().nth((loc.line as usize).saturating_sub(1)).is_some_and(|l| {
        let t = l.trim_start();
        t.starts_with("TRACKED(") || t.starts_with("TRACKED_BRIDGED(")
    })
}

/// Every `set_*` proc defined outside the generated file, by name: the types that define it.
pub fn setter_defs(tree: &Tree, sem: &crate::sem::Sem) -> HashMap<String, Vec<String>> {
    let mut out: HashMap<String, Vec<String>> = HashMap::new();
    for t in sem.objtree.iter_types() {
        let path = if t.get().path.is_empty() { "/".to_string() } else { t.get().path.clone() };
        for (name, p) in &t.get().procs {
            if !["set_", "add_", "include_", "remove_", "clear_", "insert_", "swap_", "cut_"].iter().any(|p| name.starts_with(p)) {
                continue;
            }
            if p.declaration.is_some() && p.value.iter().any(|v| sem.file_of(v.location) != Some(AUTO_REL) && sem.file_of(v.location) != Some(TRACKED_LISTS_REL) && !from_tracked_macro(tree, sem, v.location)) {
                out.entry(name.clone()).or_default().push(path.clone());
            }
        }
    }
    out
}


pub fn own_variables(sem:&Sem)->std::collections::BTreeSet<(String,String)>{let mut out=std::collections::BTreeSet::new();for ty in sem.objtree.iter_types(){let owner=if ty.get().path.is_empty(){"/"}else{&ty.get().path};for(name,var)in &ty.get().vars{if var.declaration.is_some(){out.insert((owner.to_owned(),name.clone()));}}}out}
#[test]fn frozen_original_setter_definitions_projection_is_exact(){let frozen=include_str!("../examples/support/auto_decision_original/producer.rs");let original=frozen.split_once("fn from_tracked_macro(").unwrap().1.split_once("/// The vars of `candidates`").unwrap().0;let projected=include_str!("typed_set_calls_reference.rs").split_once("fn from_tracked_macro(").unwrap().1.split_once("pub fn own_variables(").unwrap().0;assert_eq!(original.trim_end(),projected.trim_end());}
