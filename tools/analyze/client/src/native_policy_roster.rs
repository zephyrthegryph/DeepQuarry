//! One parser-free roster shared by build module admission and policy dispatch.
//! The policies themselves remain their existing modules; no scanner is copied.
pub const RAW_FILE_COUNT: usize = 43;
const RAW_FILE_PREFIX_COUNT: usize = 42;
pub const MODULES: [(&str, &str); 51] = [
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
    ("engine_internal", "engine_internal"),
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
    ("lifeform_allows", "lifeform_allows"),
    ("escape_hatches", "escape_hatches"),
    ("sys_contents", "sys/contents"),
    ("sys_damage_reactions", "sys/damage_reactions"),
    ("sys_dx_manual_transfer", "sys/dx_manual_transfer"),
    ("sys_dx_raw_delay", "sys/dx_raw_delay"),
    ("sys_dx_raw_overlays", "sys/dx_raw_overlays"),
    ("sys_dx_review", "sys/dx_review"),
    ("sys_emag", "sys/emag"),
    ("sys_grants", "sys/grants"),
    ("sys_messages", "sys/messages"),
    ("sys_presentation", "sys/presentation"),
    ("sys_topic", "sys/topic"),
    ("sys_usr_use", "sys/usr_use"),
    ("deadline_polling", "deadline_polling"),
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
pub const LINT_NAMES: [&str; 51] = {
    let mut names = [""; 51];
    let mut index = 0;
    while index < MODULES.len() {
        names[index] = MODULES[index].1;
        index += 1;
    }
    names
};
/// Per-file/workspace admission remains the audited per-file policies.
pub const RAW_FILE_LINT_NAMES: [&str; RAW_FILE_COUNT] = {
    let mut names = [""; RAW_FILE_COUNT];
    let mut source = 0;
    let mut target = 0;
    while source < MODULES.len() {
        // MODULES[45] is the unchanged entry_slots File-only policy.
        if source < RAW_FILE_PREFIX_COUNT || source == 45 {
            names[target] = MODULES[source].1;
            target += 1;
        }
        source += 1;
    }
    assert!(target == RAW_FILE_COUNT);
    names
};
// EntrySlots retains its separately bounded existing Kind10 fixture role.
/// Whole-cohort Kind10 policies; these never acquire File/RAW27 semantics.
pub const RAW_COHORT_LINT_NAMES: [&str; 9] = {
    let mut names = [""; 9];
    let mut index = 0;
    while index < names.len() { names[index] = MODULES[RAW_FILE_PREFIX_COUNT + index].1; index += 1; }
    names
};
/// The closed, check-only selection that shares one Original workspace preparation.
pub const SEMANTIC_READ_REPORT_COHORT: [&str; 3] = ["sem/reads", "untracked_inputs", "setter_publishes"];

pub fn is_semantic_read_report_cohort(names: &[String]) -> bool {
    names.len() == SEMANTIC_READ_REPORT_COHORT.len()
        && SEMANTIC_READ_REPORT_COHORT.iter().all(|expected| names.iter().any(|name| name.as_str() == *expected))
}

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
            51
        );
        assert_eq!(
            super::LINT_NAMES
                .iter()
                .copied()
                .collect::<BTreeSet<_>>()
                .len(),
            super::MODULES.len()
        );
        assert_eq!(super::LINT_NAMES[26], "sys/sync_sql");
        assert_eq!(&super::RAW_FILE_LINT_NAMES[..42], &super::LINT_NAMES[..42]);
        assert_eq!(super::RAW_FILE_LINT_NAMES[42], "entry_slots");
        assert_eq!(super::RAW_COHORT_LINT_NAMES.as_slice(), &super::LINT_NAMES[42..]);
        assert_eq!(super::RAW_COHORT_LINT_NAMES[0], "cooldown");
        assert_eq!(super::RAW_COHORT_LINT_NAMES[8], "cap_bits");
    }
}
