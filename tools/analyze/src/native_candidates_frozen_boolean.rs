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
