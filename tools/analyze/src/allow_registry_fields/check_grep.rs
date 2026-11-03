//! Metadata moved from the actual check_grep registration fields; no scanner.
pub const ALLOW_0:&[&str]=&["check_grep"];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[ALLOW_0],names,control)?;
 control.checkpoint()
}

// SAME actual registered name/group/required-list fields, no policy/source role.
#[cfg(feature="native-policy")]
pub(crate) fn visit_scopes<C:crate::key_policy_control::Control>(control:&mut C,visit:&mut dyn FnMut(crate::required_scope_policy::Requirement<'_>,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{
let meta=crate::lints::check_grep::native::metadata();visit(crate::required_scope_policy::Requirement{name:meta.name,group:meta.group,lists:meta.lists},control)?;
control.checkpoint()
}
