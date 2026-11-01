//! Metadata moved from the actual sys_fields registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[
    RuleMeta { name: "stat_bits", hint: "operable() / has_stat(BITS) to read, stat_add()/stat_remove()/set_stat() to write (systems.md section 2)" },
    RuleMeta { name: "stat_owned", hint: "set_powered() for NOPOWER, atom_break() / atom_fix() for BROKEN (G8: they publish the state)" },
    RuleMeta { name: "stat_helper", hint: "operable() is the one reader; inoperable()/is_operational() are gone (systems.md section 2)" },
    RuleMeta { name: "field_write", hint: "set_<field>() (stat_add()/stat_remove() for bits); no direct writes to a core field (systems.md section 2)" },
];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
