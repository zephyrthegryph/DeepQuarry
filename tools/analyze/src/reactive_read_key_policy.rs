//! Canonical published read-key spelling shared by dependency/read emitters.
use std::collections::BTreeSet;
use crate::{reactive_read_facts::ReadKind,key_policy_control as kc};
pub fn canonical<C:kc::Control>(control:&mut C,kind:&ReadKind,name:&str,capability_keys:&BTreeSet<String>,defines:&BTreeSet<String>)->Result<String,C::Error>{
 if *kind==ReadKind::Accessor&&capability_keys.contains(name){kc::format(control,format_args!("capkey:[{name}]"))}
 else if *kind==ReadKind::Accessor&&defines.contains(name){kc::format(control,format_args!("[{name}]"))}
 else{kc::own(control,name)}
}
