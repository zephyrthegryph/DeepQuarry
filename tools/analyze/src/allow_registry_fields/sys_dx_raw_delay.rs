//! Metadata moved from the actual sys_dx_raw_delay registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[RuleMeta {
    name: "dx_raw_delay",
    hint: "write the delay with a time define (2 SECONDS, 5 MINUTES, 1 TICK), not raw deciseconds (AGENTS.md §3f)",
}];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
