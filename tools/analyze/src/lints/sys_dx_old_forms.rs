//! Port of `tools/ci/sys_rules/dx_old_forms.py`: the forms the DX framework replaces
//! (doc/rewrite/dx_conventions.md). Each rule counts one family of old forms; the baseline only
//! shrinks.

use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::pat::Pat;
use crate::tree::SourceFile;
use crate::util::{before_slashes, py_strip};

const RULES: &[RuleMeta] = &[
    RuleMeta { name: "old_interaction_decl", hint: "capabilities() with hand()/tool()/use_on()/insert() or a library capability (dx_conventions.md §2)" },
    RuleMeta { name: "old_tool_act", hint: "a tool() entry or a library capability instead of a *_act tool proc (§2)" },
    RuleMeta { name: "old_emag", hint: "the emag(say =, effect =) capability (§2)" },
    RuleMeta { name: "old_requirement", hint: "needs = PROC_REF(x), else_say = \"...\" (§2)" },
    RuleMeta { name: "old_appearance", hint: "draw(datum/look/look) (§3)" },
    RuleMeta { name: "old_manual_refresh", hint: "nothing: changed() / dispatchers refresh automatically (§1, §3)" },
    RuleMeta { name: "old_ui", hint: "tgui_data() plus ui_<action>(mob/user, named args) procs (§5)" },
    RuleMeta { name: "old_prompt", hint: "ask_text/ask_number/ask_list/ask_yes_no/ask_color/ask_mob (§6)" },
    RuleMeta { name: "old_expiry", hint: "timed_set(src, nameof(var), value, for_time =) (§7)" },
    RuleMeta { name: "old_field", hint: "a plain var, or TRACKED(type, var) (§1)" },
    RuleMeta { name: "old_verb_decl", hint: "a native verb plus hidden_verbs() (§4)" },
    RuleMeta { name: "old_periodic", hint: "periodic_cadence plus should_run()/periodic_step(dt) (§4)" },
    RuleMeta { name: "manual_fingerprint", hint: "nothing: the dispatcher fingerprints (§2, §8)" },
];

/// The framework's own files define or bridge the old forms until they are deleted.
const EXEMPT_PREFIXES: &[&str] = &[
    "code/__defines/",
    "code/datums/capabilities/",
    "code/datums/sys/",
    "code/datums/interactions/",
    "code/datums/om/",
    "code/modules/detectivework/",
];

fn patterns() -> &'static [(&'static str, &'static Pat)] {
    static P: std::sync::LazyLock<Vec<(&'static str, &'static Pat)>> = std::sync::LazyLock::new(|| {
        vec![
            ("old_interaction_decl", pat!(r"\b(DECLARE_INTERACTIONS|EXTEND_INTERACTIONS|INTERACT_[A-Z_]+|dq_interaction_from_spec)\s*\(|/declare_interactions\(|^/datum/interaction/(machine_hand|machine_item|machine_alt)/")),
            ("old_tool_act", pat!(r"^/[\w/]+/(crowbar|screwdriver|wirecutter|wrench|welder|multitool|analyzer)_act\s*\(")),
            ("old_emag", pat!(r"\b(DECLARE_EMAG\w*)\s*\(|/emag_act\s*\(")),
            ("old_requirement", pat!(r"\bREQ_[A-Z_]+\b")),
            ("old_appearance", pat!(r"\b(APPEARANCE_(TEMPLATE|LEVEL|EMISSIVE|SLOT|WATCH|NONE)|DECLARE_APPEARANCE\w*)\s*\(|^/[\w/]+/update_icon\s*\(")),
            ("old_manual_refresh", pat!(r"(^|[^\w/])(update_icon|queue_icon_update)\s*\(\s*\)")),
            ("old_ui", pat!(r"\b(DECLARE_UI\w*|UI_ACT\w*|UI_DATA\w*|UI_ARG_\w+|UI_SUBACT\w*)\s*\(")),
            ("old_prompt", pat!(r"\b(act_ask|topic_ask|rerun_ask|rerun_ask_on|verb_ask|client_ask|flow_ask|om_ask|om_ask_sequence)\s*\(")),
            ("old_expiry", pat!(r"\bEXPIRY_\w+\s*\(")),
            ("old_field", pat!(r"\b(OM_FIELD|OM_FLAG_FIELD\w*|OM_DERIVE_FIELD|OM_FIELD_SETTER)\s*\(")),
            ("old_verb_decl", pat!(r"\bDECLARE_VERB\w*\s*\(")),
            ("old_periodic", pat!(r"\b(DECLARE_PERIODIC\w*|DECLARE_REPEAT)\s*\(|/machine_step\s*\(")),
            ("manual_fingerprint", pat!(r"\badd_fingerprint\s*\(")),
        ]
    });
    &P
}

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    if EXEMPT_PREFIXES.iter().any(|p| f.rel.starts_with(p)) {
        return;
    }
    for (number, line) in f.raw().numbered() {
        let code = before_slashes(line);
        if py_strip(code).is_empty() {
            continue;
        }
        for (rule, pattern) in patterns() {
            if pattern.is_match(code) {
                out.push((rule, number));
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "dx_old_forms", rules: RULES, file_scan: Some(scan_file), ..SysModule::DEFAULT });
}
