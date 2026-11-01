//! Metadata moved from the actual sys_resolvers registration fields; no scanner.

pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(crate::sys_resolvers_policy::RULES,&[],names,control)?;
 control.checkpoint()
}
