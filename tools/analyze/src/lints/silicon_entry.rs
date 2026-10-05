//! `silicon_entry`: how the AI, cyborgs, drones and pAIs reach machines (doc/rewrite/final_api.html section 8, "Origin, reach, provider,
//! authority"; 16.2 the airlock's AI control; 16.8 a cyborg's providers).
//!
//! Silicon access is an authority on the op pipeline: a silicon's interface is a provider (`remote_interface()`, AFF_CONTROL under
//! AUTH_REMOTE_ACCESS), a machine's remote controls are ops with a `remote()` binding (pinned to a gesture for the shift-, ctrl-, alt- and
//! middle-click shortcuts), whose link a machine admits with `req(PROC_REF(remote_link_allowed))`, and a cyborg's gripper is a provider whose
//! carried item is the held item. Four rules:
//!
//! * `shortcut` (an outright ban): the shared per-machine hooks the AI and cyborg clicks used to call, and the gripper's per-type case:
//!   `silicon_inspect`, `silicon_pull`, `silicon_alternate`, `silicon_swap_hands`, `silicon_quick`, `is_ai_remote_interface`,
//!   `remote_interface_blocked`, `handle_afterattack_special`, `silicon_or_ghost`.
//! * `handler_actor_check`: `isAI(`, `issilicon(`, `isrobot(`, `ispAI(` inside a proc that takes a `/datum/act` (an op's effect, requirement
//!   or condition). The op knows how the input came (A.authority, A.provider); a borg-only or AI-only op says so with
//!   `when(req(/mob/living/silicon/ai, of = ON_ACTOR))`.
//! * `siliconaccess`: the shared "is this a silicon the machine lets in" shortcut; `remote_link_allowed(A)` replaces it where an act is at hand.
//! * `legacy_entry`: `INTERACT_SILICON(` and `silicon_use =`, the legacy interaction entries for a silicon's plain click; each becomes an op
//!   with a `remote()` binding.
//!
//! The last three are ratchets over `tools/ci/silicon_entry_baseline.txt` (`analyze baseline --update --lint silicon_entry` drops fixed
//! sites). Exempt paths are in `lint_scopes.toml` ([lint.silicon_entry]).

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::tree::{SourceFile, CODE_DM};

const H_SHORTCUT: &str = "a machine's silicon controls are ops with a remote() binding (pinned with gesture(GESTURE_CTRL) and so on); a gripper's target is reached through the target's own ops with the gripper as provider (doc/rewrite/final_api.html 16.2, 16.8)";
const H_HANDLER: &str = "ask how the input came, not who sent it: A.authority & AUTH_REMOTE_ACCESS, req(PROC_REF(remote_link_allowed)), or a when(req(/mob/living/silicon/ai, of = ON_ACTOR)) on the op";
const H_ACCESS: &str = "use req(PROC_REF(remote_link_allowed)) on the op (library/mob/silicon.dm): the link's own rules decide (an AI is trusted, a cyborg shows its ID)";
const H_LEGACY: &str = "declare an op with a remote() binding on the type (inputs(remote()), or extend(\"ui_open\", inputs(hand(), remote())))";

static META: Meta = Meta {
    name: "silicon_entry",
    group: "",
    label: "silicon_entry",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Sites {
        baseline: "tools/ci/silicon_entry_baseline.txt",
        header: &[
            "silicon_entry: the legacy ways silicons reach machines. rule<TAB>file<TAB>normalized line. `shortcut` is banned outright.",
            "Shrink-only: `analyze baseline --update --lint silicon_entry` drops fixed sites and never adds one.",
        ],
        banned: &["shortcut"],
    },
    rules: &[
        RuleMeta { name: "shortcut", hint: H_SHORTCUT },
        RuleMeta { name: "handler_actor_check", hint: H_HANDLER },
        RuleMeta { name: "siliconaccess", hint: H_ACCESS },
        RuleMeta { name: "legacy_entry", hint: H_LEGACY },
    ],
    allow: &["silicon_entry"],
    lists: &[],
};

struct SiliconEntry;

/// Does a top-level line start a proc whose parameters include a /datum/act (an op handler, a requirement, a condition)?
fn act_proc_header(line: &str) -> bool {
    if !line.starts_with('/') {
        return false;
    }
    let Some(open) = line.find('(') else { return false };
    let params = &line[open..];
    params.contains("datum/act")
}

impl Lint for SiliconEntry {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, cx: &Cx, f: &SourceFile, out: &mut Sink) {
        if cx.exempt(&f.rel) || f.rel.starts_with("code/engine/_generated/") {
            return;
        }
        let shortcut = crate::pat!(
            r"\b(?:silicon_(?:inspect|pull|alternate|swap_hands|quick)|is_ai_remote_interface|remote_interface_blocked|handle_afterattack_special|silicon_or_ghost)\b"
        );
        let actor_check = crate::pat!(r"(?<![\w.])(?:isAI|issilicon|isrobot|ispAI)\(");
        let access = crate::pat!(r"\bsiliconaccess\(");
        let legacy = crate::pat!(r"\bINTERACT_SILICON\(|(?<![\w.])silicon_use\s*=");
        let mut in_act_proc = false;
        for (number, line) in f.code().numbered() {
            if !line.starts_with('\t') && !line.starts_with(' ') && !line.trim().is_empty() {
                in_act_proc = act_proc_header(line);
            }
            if out.allowed(f, number, "silicon_entry") {
                continue;
            }
            if shortcut.is_match(line) {
                out.site("shortcut", number);
            }
            if in_act_proc && actor_check.is_match(line) {
                out.site("handler_actor_check", number);
            }
            if access.is_match(line) && !line.contains("proc/siliconaccess(") {
                out.site("siliconaccess", number);
            }
            if legacy.is_match(line) && !line.trim_start().starts_with("#define") {
                out.site("legacy_entry", number);
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(SiliconEntry);
}
