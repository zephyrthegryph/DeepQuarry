//! Metadata moved from the actual sys_emag registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[RuleMeta {
    name: "emag_act",
    hint: "DECLARE_EMAG(type, PROC_REF(on_emag), msg) + emag_target() (code/__defines/sys_emag.dm, doc/rewrite/systems.md section 13)",
}];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
