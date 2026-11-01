//! Metadata moved from the actual sys_topic registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "topic_override",
        hint: "declare TOPIC_ACTION(type, href_key, PROC_REF(handler), specs...) rows instead of overriding Topic() (doc/rewrite/systems.md section 20)",
    },
    RuleMeta {
        name: "topic_raw_dispatch",
        hint: "one TOPIC_ACTION row per href key (\"key=value\" rows for value switches) instead of if/switch on href_list[...]",
    },
    RuleMeta {
        name: "topic_raw_locate",
        hint: "declare TOPIC_REF(name, type[, source]) and read args[name]; never locate() a ref straight from href_list",
    },
    RuleMeta {
        name: "topic_raw_num",
        hint: "declare TOPIC_NUM(name) and read args[name] instead of text2num(href_list[...])",
    },
];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
