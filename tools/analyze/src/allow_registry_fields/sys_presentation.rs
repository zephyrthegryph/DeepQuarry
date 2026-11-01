//! Metadata moved from the actual sys_presentation registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[RuleMeta {
    name: "presentation_call",
    hint: "write the input through its setter or PUBLISH_CHANGE the key that covers it (MOB_KEY_*); the HUD / sight reactions run by themselves (living_systems.dm)",
}];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
