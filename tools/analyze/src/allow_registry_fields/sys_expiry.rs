//! Metadata moved from the actual sys_expiry registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "world_time_expiry",
        hint: "COOLDOWN_DECLARE/COOLDOWN_START/COOLDOWN_RUNNING/COOLDOWN_TIMELEFT for an end time, STAMP/ELAPSED for a start (code/__defines/cooldowns.dm, code/__defines/sys_expiry.dm)",
    },
    RuleMeta {
        name: "world_time_write",
        hint: "a stored time is written with COOLDOWN_START/COOLDOWN_EXTEND/STAMP (or TIME_NOW for list slots/records), never `x = world.time (+ N)`",
    },
    RuleMeta {
        name: "expiry_undeclared",
        hint: "a var read/written by COOLDOWN_EXTEND/RUNNING/LAPSED or an _OWN cooldown macro is declared with COOLDOWN_DECLARE (a base type uses a cooldowns() name and cooldown_*)",
    },
];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}

// SAME actual registered name/group/required-list fields, no policy/source role.
pub const SCOPE_MODULE_NAME:&str="expiry";
#[cfg(feature="native-policy")]
pub(crate) fn visit_scopes<C:crate::key_policy_control::Control>(control:&mut C,visit:&mut dyn FnMut(crate::required_scope_policy::Requirement<'_>,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{
crate::required_scope_registry::visit_sys(SCOPE_MODULE_NAME,control,visit)?;
control.checkpoint()
}
