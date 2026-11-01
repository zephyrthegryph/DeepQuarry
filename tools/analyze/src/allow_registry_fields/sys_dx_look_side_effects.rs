//! Metadata moved from the actual sys_dx_look_side_effects registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[RuleMeta {
    name: "dx_appearance_side_effect",
    hint: "appearance procs (appearance_overlays, DECLARE_APPEARANCE_PROC rows; draw() is dx_reactive_write's) write no state and play no sound: move it to the handler or setter that changes the state (G12)",
}];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
