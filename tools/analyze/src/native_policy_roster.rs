//! One parser-free roster shared by build module admission and policy dispatch.
//! The policies themselves remain their existing modules; no scanner is copied.
pub const MODULES: [(&str, &str); 27] = [
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
];
pub const LINT_NAMES: [&str; 27] = {
    let mut names = [""; 27];
    let mut index = 0;
    while index < MODULES.len() {
        names[index] = MODULES[index].1;
        index += 1;
    }
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
            27
        );
        assert_eq!(
            super::LINT_NAMES
                .iter()
                .copied()
                .collect::<BTreeSet<_>>()
                .len(),
            27
        );
        assert_eq!(super::LINT_NAMES[26], "sys/sync_sql");
    }
}
