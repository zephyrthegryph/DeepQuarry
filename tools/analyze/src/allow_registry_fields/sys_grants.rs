//! Metadata moved from the actual sys_grants registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[RuleMeta {
    name: "verb_write",
    hint: "om_grant(target, GRANT_VERB | GRANT_VERB_HIDE, verb, source) / om_revoke(), or DECLARE_VERB* on the type; the store is the only verbs writer (doc/rewrite/systems.md section 19)",
}];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
