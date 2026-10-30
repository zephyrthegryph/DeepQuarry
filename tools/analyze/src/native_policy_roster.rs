//! One parser-free roster shared by build module admission and policy dispatch.
//! The policies themselves remain their existing modules; no scanner is copied.
pub const RAW_FILE_COUNT: usize = 27;
pub const MODULES: [(&str, &str); 36] = [
    ("actor_forwarding", "actor_forwarding"),
    ("breakpoint", "breakpoint"),
    ("containment", "containment"),
    ("dcs", "dcs"),
    ("door_gates", "door_gates"),
    ("entity_ids", "entity_ids"),
    ("i7_handler", "i7_handler"),
    ("in_precedence", "in_precedence"),
    ("leftovers", "leftovers"),
    ("legacy_forms", "legacy_forms"),
    ("lifecycle_counts", "lifecycle_counts"),
    ("mouse_override", "mouse_override"),
    ("native_ref_write", "native_ref_write"),
    ("om_internal", "om_internal"),
    ("organ_slots", "organ_slots"),
    ("qdel_src", "qdel_src"),
    ("reactions_table_proc", "reactions_table_proc"),
    ("ref_text", "ref_text"),
    ("registry", "registry"),
    ("saved_handle", "saved_handle"),
    ("scheduler", "scheduler"),
    ("silent_catch", "silent_catch"),
    ("spatial", "spatial"),
    ("stance_examine", "stance_examine"),
    ("subsystem_fire", "subsystem_fire"),
    ("verb_category", "verb_category"),
    ("sys_sync_sql", "sys/sync_sql"),
    ("cooldown", "cooldown"),
    ("declaration_block", "declaration_block"),
    ("duplicate_input_key", "duplicate_input_key"),
    ("entry_slots", "entry_slots"),
    ("interactions", "interactions"),
    ("latent", "latent"),
    ("pollers", "pollers"),
    ("read_back", "read_back"),
    ("cap_bits", "cap_bits"),
];
pub const LINT_NAMES: [&str; 36] = {
    let mut names = [""; 36];
    let mut index = 0;
    while index < MODULES.len() {
        names[index] = MODULES[index].1;
        index += 1;
    }
    names
};
/// Per-file/workspace admission remains exactly the original 27 policies.
pub const RAW_FILE_LINT_NAMES: [&str; RAW_FILE_COUNT] = {
    let mut names = [""; RAW_FILE_COUNT];
    let mut index = 0;
    while index < RAW_FILE_COUNT { names[index] = MODULES[index].1; index += 1; }
    names
};
/// Whole-cohort Kind10 policies; these never acquire File/RAW27 semantics.
pub const RAW_COHORT_LINT_NAMES: [&str; 9] = {
    let mut names = [""; 9];
    let mut index = 0;
    while index < names.len() { names[index] = MODULES[RAW_FILE_COUNT + index].1; index += 1; }
    names
};
#[cfg(test)]
mod tests {
    #[test]
    fn roster_has_unique_module_and_lint_names() {
        use std::collections::BTreeSet;
        assert_eq!(
            super::MODULES
                .iter()
                .map(|(module, _)| *module)
                .collect::<BTreeSet<_>>()
                .len(),
            36
        );
        assert_eq!(
            super::LINT_NAMES
                .iter()
                .copied()
                .collect::<BTreeSet<_>>()
                .len(),
            36
        );
        assert_eq!(super::LINT_NAMES[26], "sys/sync_sql");
        assert_eq!(super::RAW_FILE_LINT_NAMES.as_slice(), &super::LINT_NAMES[..27]);
        assert_eq!(super::RAW_COHORT_LINT_NAMES.as_slice(), &super::LINT_NAMES[27..]);
        assert_eq!(super::RAW_COHORT_LINT_NAMES[0], "cooldown");
        assert_eq!(super::RAW_COHORT_LINT_NAMES[8], "cap_bits");
    }
}
