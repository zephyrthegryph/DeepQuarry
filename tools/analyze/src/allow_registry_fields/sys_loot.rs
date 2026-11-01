//! Metadata moved from the actual sys_loot registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[
    RuleMeta { name: "item_to_spawn", hint: "declare the table with loot(table = list(...)) in the type's CAPABILITIES block (systems.md section 8)" },
    RuleMeta {
        name: "loot_table_datum",
        hint: "searchable tiers are loot(uncommon = ..., rare = ...) on the /loot/... table + loot_search(table =) on the pile (systems.md section 8)",
    },
    RuleMeta {
        name: "random_spawn_list",
        hint: "spawn lists and roll logic belong in the type's loot(table =, hook =) entry, not procs or list vars (systems.md section 8)",
    },
];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
