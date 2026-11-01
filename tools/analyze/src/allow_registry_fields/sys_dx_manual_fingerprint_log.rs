//! Metadata moved from the actual sys_dx_manual_fingerprint_log registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[RuleMeta {
    name: "dx_manual_fingerprint_log",
    hint: "drop it: dispatch_call() fingerprints and logs a successful dispatched call (set `log =` / ui_logged() for the level) (dx_conventions.md section 2, 8)",
}];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
