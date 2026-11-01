//! Metadata moved from the actual sem_keys registration fields; no scanner.
pub const ALLOW_SHARED_0:&[&str]=&["keys"];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[ALLOW_SHARED_0],names,control)?;
 control.checkpoint()
}
