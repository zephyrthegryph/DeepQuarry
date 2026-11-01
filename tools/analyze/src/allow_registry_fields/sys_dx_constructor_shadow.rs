//! Metadata moved from the actual sys_dx_constructor_shadow registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "dx_constructor_shadow",
        hint: "rename the type proc: it shadows a global capability constructor or bundle inside capabilities() (framework review 2, H7)",
    },
    RuleMeta {
        name: "part_constructor_shadow",
        hint: "rename the proc: a capability datum's entries() calls the part constructors (cooldown(), flash(), put_in(), menu(), ...) bare, and its own proc of that name would answer instead of the engine's. A CAPABILITIES list is generated as `global.name(...)` and cannot clash; a hand-written entries() cannot be qualified for you",
    },
];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
