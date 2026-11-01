//! Metadata moved from the actual sys_contents registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[RuleMeta {
    name: "materializing_walk",
    hint: "FOR_REAL_CONTENTS() + latent_names()/latent_count() in tgui_data()/examine() (doc/rewrite/systems.md section 18)",
}];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
