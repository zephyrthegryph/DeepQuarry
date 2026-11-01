//! Metadata moved from the actual sys_damage_reactions registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[RuleMeta {
    name: "entry_override",
    hint: "declare it next to the type: DAMAGE_REACTION(type, trigger, PROC_REF(x)) / REFLECTS(type, kinds, chance) / EMP_DISABLE(type, duration, field), or a protection flag (doc/rewrite/systems.md section 12)",
}];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
