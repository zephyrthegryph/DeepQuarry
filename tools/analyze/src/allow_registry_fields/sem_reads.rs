//! Metadata moved from the actual sem_reads registration fields; no scanner.
pub const ALLOW_0:&[&str]=&["reads"];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[ALLOW_0],names,control)?;
 control.checkpoint()
}

// SAME actual registered name/group/required-list fields, no policy/source role.
pub const SCOPE_META_0:crate::required_scope_policy::Requirement<'static>=crate::required_scope_policy::Requirement{name:"sem/reads",group:"sem",lists:&[]};
#[cfg(feature="native-policy")]
pub(crate) fn visit_scopes<C:crate::key_policy_control::Control>(control:&mut C,visit:&mut dyn FnMut(crate::required_scope_policy::Requirement<'_>,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{
visit(SCOPE_META_0,control)?;
control.checkpoint()
}
