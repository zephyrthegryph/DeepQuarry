//! Metadata moved from the actual sys_dx_ownership_forms registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "old_ownership_macro",
        hint: "ownership() with owns()/shares()/proto() and relations() with rel_one()/rel_many()/rel_key() (ownership.md §1.2, §4.1)",
    },
    RuleMeta { name: "old_destroy_macro", hint: "an override of the well-known teardown proc (destroy_step/destroy_capture/destroy_after) (ownership.md §6)" },
    RuleMeta { name: "string_accessor_var", hint: "nameof(var) / nameof(/type::var) for the var name of an own_*/rel_*/proto_* accessor (ownership.md §1.2)" },
    RuleMeta {
        name: "owned_twice",
        hint: "drop the ownership() line: the capability (cap_slot) already owns this var through its owned() entries (ownership.md §1.2)",
    },
];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
