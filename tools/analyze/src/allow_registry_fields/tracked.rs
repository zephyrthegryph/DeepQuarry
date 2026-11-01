//! Metadata moved from the actual tracked registration fields; no scanner.
pub const ALLOW_0:&[&str]=&["tracked"];
pub const ALLOW_1:&[&str]=&["tracked"];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[ALLOW_0,ALLOW_1],names,control)?;
 control.checkpoint()
}
