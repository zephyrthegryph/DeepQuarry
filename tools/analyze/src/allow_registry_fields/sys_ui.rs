//! Metadata moved from the actual sys_ui registration fields; no scanner.
use crate::lint::RuleMeta;
pub const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "tgui_interact_boilerplate",
        hint: "declare the window with DECLARE_UI(type, interface, opts...) and the ui_prepare/ui_redirect/ui_opening/ui_title/ui_interface hooks instead of a tgui_interact() override or a hand-opened /datum/tgui (doc/rewrite/systems.md section 3)",
    },
    RuleMeta {
        name: "ui_act_dispatch",
        hint: "one UI_ACT(type, action, handler, args...) row per action (UI_ACT_FORWARD to hand unknown actions to another datum, UI_ACT_NESTED / UI_SUBACT for nested ones) instead of a tgui_act() override",
    },
    RuleMeta {
        name: "tgui_data_override",
        hint: "declare the window's data with UI_DATA(type, \"var\", \"key=var\", \"proc:getter\", \"merge:getter{key:type,...}\") instead of a tgui_data() override",
    },
    RuleMeta {
        name: "tgui_state_override",
        hint: "declare a state every instance shares with DECLARE_UI_STATE(type, state) instead of a tgui_state() override that returns it",
    },
    RuleMeta {
        name: "text2num_params",
        hint: "declare the arg on the UI_ACT row (UI_ARG_NUM/INT/TEXT/BOOL/CHOICE/REF/PATH/LIST/VALUE) and read the typed params[name] in the handler; never parse raw params",
    },
];
pub(crate) fn collect<C:crate::key_policy_control::Control>(names:&mut std::collections::BTreeSet<String>,control:&mut C)->Result<(),C::Error>{
 crate::allow_registry_fields::plain(&[],names,control)?;
 crate::allow_registry_fields::sys(RULES,&[],names,control)?;
 control.checkpoint()
}
