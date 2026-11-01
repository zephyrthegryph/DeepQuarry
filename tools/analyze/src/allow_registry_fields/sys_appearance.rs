//! Metadata moved from the actual sys_appearance registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "update_icon_call",
        hint: "delete it: a declared field's setter refreshes the appearance (APPEARANCE_WATCH the field for a procedural update_icon(); systems.md section 1)",
    },
    RuleMeta {
        name: "appearance_proc_overlays",
        hint: "return the overlays from appearance_overlays(); the runtime owns cut/add (systems.md section 1)",
    },
    RuleMeta {
        name: "appearance_proc_state",
        hint: "a provider draws, it changes no state: move the setter to where the state changes (systems.md section 1)",
    },
    RuleMeta {
        name: "update_icon_override",
        hint: "declare the appearance (APPEARANCE_TEMPLATE/LEVEL/EMISSIVE/SLOT, DECLARE_APPEARANCE); genuinely procedural drawing keeps `// ALLOW(sys_update_icon): <reason>` (systems.md section 1)",
    },
];
pub const ALLOW_EXTRA:&[&str]=&["update_icon"];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,ALLOW_EXTRA,names,control)?;
 control.checkpoint()
}
