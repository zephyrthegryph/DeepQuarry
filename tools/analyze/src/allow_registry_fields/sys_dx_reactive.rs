//! Metadata moved from the actual sys_dx_reactive registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "dx_untracked_read",
        hint: "declare the var TRACKED(type, var) (or give it a set_<var>()), or read it through a watched relation (design review H4)",
    },
    RuleMeta {
        name: "dx_reactive_write",
        hint: "reactive procs (draw, should_run, hidden_verbs, tgui_data, a capability's draw/gate/ui_data/examine, needs procs) write nothing: move the write to the handler or setter that changes the state (design review H5)",
    },
    RuleMeta {
        name: "dx_caps_instance_read",
        hint: "capabilities() is per type: read the instance var inside the capability at run time instead (design review M3, H1)",
    },
    RuleMeta {
        name: "dx_timed_write",
        hint: "write this var only through timed_set() or its set_<var>() proc (design review M5)",
    },
];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
