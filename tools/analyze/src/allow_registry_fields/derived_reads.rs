//! Metadata moved from the actual derived_reads registration fields; no scanner.
pub const ALLOW_0:&[&str]=&["derived_reads"];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[ALLOW_0],names,control)?;
 control.checkpoint()
}
