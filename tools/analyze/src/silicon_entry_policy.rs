//! Unique original silicon raw rules and metadata, shared by both frontends.
use crate::lint::{Meta,Policy,RuleMeta,ScanKind,Sink};
use crate::tree::{SourceFile,CODE_DM};
const H_SHORTCUT: &str = "a machine's silicon controls are ops with a remote() binding (pinned with gesture(GESTURE_CTRL) and so on); a gripper's target is reached through the target's own ops with the gripper as provider (doc/rewrite/final_api.html 16.2, 16.8)";
const H_HELPER: &str = "the helper decides by who called it: pass it what the op already knows (A.authority & AUTH_REMOTE_ACCESS, the provider), or split the op per actor kind with when(req(/mob/living/silicon/ai, of = ON_ACTOR))";
const H_HANDLER: &str = "ask how the input came, not who sent it: A.authority & AUTH_REMOTE_ACCESS, req(PROC_REF(remote_link_allowed)), or a when(req(/mob/living/silicon/ai, of = ON_ACTOR)) on the op";
const H_ACCESS: &str = "use req(PROC_REF(remote_link_allowed)) on the op (library/mob/silicon.dm): the link's own rules decide (an AI is trusted, a cyborg shows its ID)";
const H_LEGACY: &str = "declare an op with a remote() binding on the type (inputs(remote()), or extend(\"ui_open\", inputs(hand(), remote())))";

pub static META: Meta = Meta {
    name: crate::allow_registry_fields::silicon_entry::SCOPE_META_0.name,
    group: crate::allow_registry_fields::silicon_entry::SCOPE_META_0.group,
    label: "silicon_entry",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Both,
    policy: Policy::Sites {
        baseline: "tools/ci/silicon_entry_baseline.txt",
        header: &[
            "silicon_entry: the legacy ways silicons reach machines. rule<TAB>file<TAB>normalized line. `shortcut` is banned outright.",
            "Shrink-only: `analyze baseline --update --lint silicon_entry` drops fixed sites and never adds one.",
        ],
        banned: &["shortcut", "handler_actor_check", "legacy_entry", "siliconaccess"],
    },
    rules: &[
        RuleMeta { name: "shortcut", hint: H_SHORTCUT },
        RuleMeta { name: "handler_actor_check", hint: H_HANDLER },
        RuleMeta { name: "handler_actor_istype", hint: H_HANDLER },
        RuleMeta { name: "helper_actor_check", hint: H_HELPER },
        RuleMeta { name: "siliconaccess", hint: H_ACCESS },
        RuleMeta { name: "legacy_entry", hint: H_LEGACY },
    ],
    allow: crate::allow_registry_fields::silicon_entry::ALLOW_0,
    lists: crate::allow_registry_fields::silicon_entry::SCOPE_META_0.lists,
};


pub fn scan_file_using(f:&SourceFile,out:&mut Sink,gate:&dyn crate::key_policy_control::Gate){
 let shortcut=crate::pat!(r"\b(?:silicon_(?:inspect|pull|alternate|swap_hands|quick)|is_ai_remote_interface|remote_interface_blocked|handle_afterattack_special|silicon_or_ghost)\b");
 let access=crate::pat!(r"\bsiliconaccess\(");let legacy=crate::pat!(r"\bINTERACT_SILICON\(|(?<![\w.])silicon_use\s*=");
 for(number,line)in f.code().numbered(){if !gate.checkpoint(){return}if out.allowed(f,number,"silicon_entry"){continue}if shortcut.is_match(line){out.site("shortcut",number)}if access.is_match(line)&&!line.contains("proc/siliconaccess("){out.site("siliconaccess",number)}if legacy.is_match(line)&&!line.trim_start().starts_with("#define"){out.site("legacy_entry",number)}}
}
pub fn macro_line(text:&str)->bool{crate::pat!(r"(?<![\w.])(?:isAI|issilicon|isrobot|ispAI)\(").is_match(text)}
