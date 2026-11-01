//! Metadata moved from the actual sys_dx_manual_transfer registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "manual_transfer",
        hint: "own_set/own_add/own_put(holder, nameof(holder.var), item, user = user): one call takes it out of the hand, slot or storage (ownership.md §1.3a)",
    },
    RuleMeta {
        name: "manual_move_adopt",
        hint: "own_set/own_add/own_put(holder, nameof(holder.var), item, into = TRUE) moves it in itself (ownership.md §1.3a)",
    },
];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
