//! Metadata moved from the actual sys_messages registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[RuleMeta {
    name: "visible_pair",
    hint: "act_message(user, target, MSG_SELF(), MSG_OTHERS(), MSG_BLIND()) or act_message_t() (doc/rewrite/systems.md section 15)",
}];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
