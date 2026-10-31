//! Test-only original boolean functions; no shared candidate core.
use std::{collections::{BTreeSet,HashMap},sync::Arc};
use crate::{tree::Tree,sem::reads::ReadsEngine};
const LIST_CALL:&str="[]";
fn declared_reactive(eng: &ReadsEngine, owner: &str, var: &str) -> bool {
    let mut cur = Some(owner.to_string());
    let mut guard = 0;
    while let Some(t) = cur {
        if eng.decls.tracked_explicit.get(&t).map(|s| s.contains(var)).unwrap_or(false) {
            return true;
        }
        guard += 1;
        if guard > 64 {
            break;
        }
        cur = eng.sem.parent_of(&t).filter(|p| p != &t && p != "/");
    }
    eng.is_relation(owner, var) || eng.is_stat(owner, var) || eng.is_derived(owner, var)
}

pub fn named_candidate(eng: &ReadsEngine, owner: &str, var: &str) -> bool {
    !declared_reactive(eng, owner, var) && !eng.sem.var_decl(owner, var).map(|v| v.is_const).unwrap_or(false)
}

/// A read the inference tracks: no declaration makes it reactive, it is not constant, and something writes it.
pub fn candidate(eng: &ReadsEngine, written: &crate::sem::reads::WriteIndex, calls: &BTreeSet<String>, owner: &str, var: &str) -> bool {
    if declared_reactive(eng, owner, var) {
        return false;
    }
    if eng.sem.var_decl(owner, var).map(|v| v.is_const).unwrap_or(false) {
        return false;
    }
    if written.is_written_on(eng.sem, owner, var) || calls.contains(var) {
        return true;
    }
    // A list is written through its generated mutators once `analyze fix` has rewritten the raw edits.
    calls.contains(&format!("{}{}", var, LIST_CALL)) && eng.sem.var_decl(owner, var).map(|v| v.is_list()).unwrap_or(false)
}
fn setter_names(var: &str) -> [String; 9] {
    [format!("set_{var}"), format!("add_{var}"), format!("include_{var}"), format!("remove_{var}"), format!("set_{var}_at"), format!("clear_{var}"), format!("insert_{var}"), format!("swap_{var}"), format!("cut_{var}")]
}

fn typed_set_calls(_tree:&Tree,sem:&crate::sem::Sem)->Arc<HashMap<String,BTreeSet<String>>>{let mut out:HashMap<String,BTreeSet<String>>=HashMap::new();for(name,owner)in super::reference::collect(sem){out.entry(name).or_default().insert(owner);}Arc::new(out)}
pub fn called_here(tree: &Tree, sem: &crate::sem::Sem, defs: &HashMap<String, Vec<String>>, calls: &BTreeSet<String>, owner: &str, var: &str) -> bool {
    let plain = calls.contains(var);
    let list = calls.contains(&format!("{}{}", var, LIST_CALL));
    if !plain && !list {
        return false;
    }
    let names = setter_names(var);
    let related = |t: &String| sem.is_subtype(t, owner) || sem.is_subtype(owner, t);
    // A call whose receiver has a static type speaks for that type only: `locked` is declared on forty types, and a typed
    // `door.set_locked()` says nothing about the other thirty-nine.
    let typed = typed_set_calls(tree, sem);
    let typed_for: Vec<&BTreeSet<String>> = names.iter().filter_map(|n| typed.get(n)).collect();
    if !typed_for.is_empty() {
        return typed_for.iter().any(|types| types.iter().any(related));
    }
    // Only calls whose receiver could not be typed name it: the name is enough when no unrelated type owns a hand-written proc of it.
    names.iter().all(|n| defs.get(n).is_none_or(|types| types.iter().all(related)))
}


#[test]fn original_candidate_boolean_projection_is_byte_exact(){let frozen=include_str!("native_candidates_frozen_boolean.rs");let actual=include_str!("native_candidates_reference.rs").split_once("pub fn named_candidate(").unwrap().1.split_once("fn setter_names(").unwrap().0;assert_eq!(frozen.split_once("pub fn named_candidate(").unwrap().1.trim_end(),actual.trim_end());let typed=include_str!("typed_set_calls_frozen_original.rs");for(marker,end)in[("fn declared_reactive(","\n/// The var names some proc writes"),("pub fn called_here(","\npub use crate::auto_tracking_policy")]{let original=typed.split_once(marker).unwrap().1.split_once(end).unwrap().0;let projected=include_str!("native_candidates_reference.rs").split_once(marker).unwrap().1;assert!(projected.replace("typed_set_calls(tree, sem)","typed_set_calls(tree)").starts_with(original));}}
