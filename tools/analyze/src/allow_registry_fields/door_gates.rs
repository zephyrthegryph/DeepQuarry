//! Metadata moved from the actual door_gates registration fields; no scanner.
pub const ALLOW_0:&[&str]=&["door_gates"];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[ALLOW_0],names,control)?;
 control.checkpoint()
}
