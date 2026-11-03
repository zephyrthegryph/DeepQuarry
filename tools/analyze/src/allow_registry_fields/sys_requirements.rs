//! Metadata moved from the actual sys_requirements registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[RuleMeta {
    name: "inline_refusal",
    hint: "declare the guard as a requirement clause (REQ_FIELD/REQ_FIELD_NOT/REQ_FIELD_EQ/REQ_ACCESS/REQ_NOT_EMAGGED/REQ_ANCHORED/REQ_PANEL/REQ_ON) on the interaction (systems.md section 6)",
}];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}

// SAME actual registered name/group/required-list fields, no policy/source role.
pub const SCOPE_MODULE_NAME:&str="requirements";
#[cfg(feature="native-policy")]
pub(crate) fn visit_scopes<C:crate::key_policy_control::Control>(control:&mut C,visit:&mut dyn FnMut(crate::required_scope_policy::Requirement<'_>,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{
crate::required_scope_registry::visit_sys(SCOPE_MODULE_NAME,control,visit)?;
control.checkpoint()
}
