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
//! * `handler_actor_check`: `isAI(`, `issilicon(`, `isrobot(`, `ispAI(` in a proc that takes a `/datum/act` (an op's effect,
//!   requirement or condition; found on the typed tree, `sem::actor_tests`). The op knows how the input came (A.authority,
//!   A.provider); a borg-only or AI-only op says so with `when(req(/mob/living/silicon/ai, of = ON_ACTOR))`.
//! * `handler_actor_istype`: the same test written as `istype(<the actor>, /mob/living/silicon...)`, on the act's actor or a local
//!   holding it. Ratcheted (the text rule never saw these; the baseline holds the sites that existed when it moved to the tree).
//! * `helper_actor_check`: the same test in a proc a handler reaches with the actor (or the act) as an argument, at any depth up to
//!   8 calls (`sem::actor_tests`, on the typed tree). Ratcheted: the baseline holds the sites that existed when the rule moved to the
//!   tree.
//! * `siliconaccess`: the shared "is this a silicon the machine lets in" shortcut; `remote_link_allowed(A)` replaces it where an act is at hand.
//! * `legacy_entry`: `INTERACT_SILICON(` and `silicon_use =`, the legacy interaction entries for a silicon's plain click; each becomes an op
//!   with a `remote()` binding.
//!
//! `siliconaccess`, `handler_actor_istype` and `helper_actor_check` are ratchets over `tools/ci/silicon_entry_baseline.txt` (`analyze baseline --update --lint silicon_entry` drops fixed
//! sites). Exempt paths are in `lint_scopes.toml` ([lint.silicon_entry]).

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::tree::{SourceFile, CODE_DM};

const H_SHORTCUT: &str = "a machine's silicon controls are ops with a remote() binding (pinned with gesture(GESTURE_CTRL) and so on); a gripper's target is reached through the target's own ops with the gripper as provider (doc/rewrite/final_api.html 16.2, 16.8)";
const H_HELPER: &str = "the helper decides by who called it: pass it what the op already knows (A.authority & AUTH_REMOTE_ACCESS, the provider), or split the op per actor kind with when(req(/mob/living/silicon/ai, of = ON_ACTOR))";
const H_HANDLER: &str = "ask how the input came, not who sent it: A.authority & AUTH_REMOTE_ACCESS, req(PROC_REF(remote_link_allowed)), or a when(req(/mob/living/silicon/ai, of = ON_ACTOR)) on the op";
const H_ACCESS: &str = "use req(PROC_REF(remote_link_allowed)) on the op (library/mob/silicon.dm): the link's own rules decide (an AI is trusted, a cyborg shows its ID)";
const H_LEGACY: &str = "declare an op with a remote() binding on the type (inputs(remote()), or extend(\"ui_open\", inputs(hand(), remote())))";

static META: Meta = Meta {
    name: "silicon_entry",
    group: "",
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
    allow: &["silicon_entry"],
    lists: &[],
};

struct SiliconEntry;

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
        let access = crate::pat!(r"\bsiliconaccess\(");
        let legacy = crate::pat!(r"\bINTERACT_SILICON\(|(?<![\w.])silicon_use\s*=");
        for (number, line) in f.code().numbered() {
            if out.allowed(f, number, "silicon_entry") {
                continue;
            }
            if shortcut.is_match(line) {
                out.site("shortcut", number);
            }
            if access.is_match(line) && !line.contains("proc/siliconaccess(") {
                out.site("siliconaccess", number);
            }
            if legacy.is_match(line) && !line.trim_start().starts_with("#define") {
                out.site("legacy_entry", number);
            }
        }
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        SiliconEntry::actor_tests(cx, out);
    }
}

impl SiliconEntry {
    /// `handler_actor_check` and `helper_actor_check` on the typed tree (`sem::actor_tests`), cached while no `code/` file changed.
    fn actor_tests(cx: &Cx, out: &mut Sink) {
        let files = cx.files();
        let key = crate::incr::ctx_key(&files.iter().map(|f| (f.rel.as_str(), f.fkey)).collect::<Vec<_>>());
        let found: Vec<(String, String, u32, String)> = crate::incr::cached("silicon-entry-actor-tests", key, || {
            let Some(sem) = cx.sem() else { return Vec::new() };
            let lines = |rel: &str, line: u32| -> Option<String> {
                let f = cx.tree.get(rel)?;
                f.code().numbered().find(|(n, _)| *n == line as usize).map(|(_, l)| l.to_string())
            };
            crate::sem::actor_tests::actor_tests(&sem, &lines).into_iter().map(|t| (t.rule.to_string(), t.rel.clone(), t.line, describe(&t))).collect()
        });
        for (rule, rel, line, msg) in found {
            if rel.is_empty() || cx.exempt(&rel) || rel.starts_with("code/engine/_generated/") {
                continue;
            }
            let Some(f) = cx.tree.get(&rel) else { continue };
            if out.allowed(f, line as usize, "silicon_entry") {
                continue;
            }
            let rule: &'static str = match rule.as_str() {
                "handler_actor_check" => "handler_actor_check",
                "handler_actor_istype" => "handler_actor_istype",
                _ => "helper_actor_check",
            };
            out.site_in_msg(rule, &rel, line as usize, msg);
        }
    }
}

fn describe(t: &crate::sem::actor_tests::ActorTest) -> String {
    let what = if t.tested == "macro" { "an isAI()/issilicon()/isrobot()/ispAI() test".to_string() } else { format!("istype(actor, {})", t.tested) };
    if t.rule != "helper_actor_check" {
        format!("{} in the op handler {}", what, t.handler)
    } else {
        format!("{} on the actor the op handler {} passes in", what, t.handler)
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(SiliconEntry);
}

#[cfg(test)]
mod tests {
    use crate::sem::actor_tests::actor_tests;
    use crate::sem::Sem;
    use crate::tree::{SourceFile, Tree};

    const DEFINES: &str = "#define issilicon(A) istype(A, /mob/living/silicon)
#define isAI(A) istype(A, /mob/living/silicon/ai)
";
    const TYPES: &str = "/datum/act
	var/actor
/datum/act/op
/datum/act/timer
/datum/prompt/choice
/mob/living/silicon/ai
/mob/living/silicon/robot
/obj/machinery
";

    fn found(source: &str) -> Vec<(String, u32)> {
        let root = tempfile::tempdir().unwrap();
        let sources = [("code/__defines/is.dm", DEFINES), ("code/types.dm", TYPES), ("code/probe.dm", source)];
        let mut files = Vec::new();
        for (rel, text) in sources {
            let abs = root.path().join(rel);
            std::fs::create_dir_all(abs.parent().unwrap()).unwrap();
            std::fs::write(abs, text).unwrap();
            files.push(SourceFile::from_text(rel, text));
        }
        let tree = Tree::from_files(files);
        let sem = Sem::build(root.path(), &tree).unwrap();
        let lines = |rel: &str, line: u32| -> Option<String> { tree.get(rel)?.code().numbered().find(|(n, _)| *n == line as usize).map(|(_, l)| l.to_string()) };
        actor_tests(&sem, &lines).into_iter().map(|t| (t.rule.to_string(), t.line)).collect()
    }

    #[test]
    fn a_handler_testing_the_actor_is_a_site() {
        let f = found("/obj/machinery/proc/use(datum/act/op/A)
	return isAI(A.actor)
");
        assert_eq!(f, vec![("handler_actor_check".to_string(), 2)]);
    }

    #[test]
    fn a_local_holding_the_actor_and_a_literal_istype_are_sites() {
        let f = found("/obj/machinery/proc/use(datum/act/op/A)
	var/mob/user = A.actor
	if(istype(user, /mob/living/silicon/robot))
		return 1
");
        assert_eq!(f, vec![("handler_actor_istype".to_string(), 3)]);
    }

    #[test]
    fn a_helper_reached_with_the_actor_is_a_helper_site() {
        let src = "/obj/machinery/proc/use(datum/act/op/A)
	return can_use(A.actor)
/obj/machinery/proc/can_use(mob/user)
	return deeper(user)
/obj/machinery/proc/deeper(mob/M)
	return issilicon(M)
";
        assert_eq!(found(src), vec![("helper_actor_check".to_string(), 6)]);
    }

    #[test]
    fn a_helper_given_the_act_tests_its_actor() {
        let src = "/obj/machinery/proc/use(datum/act/op/A)
	return check(A)
/obj/machinery/proc/check(datum/act/X)
	return 1
/obj/machinery/proc/other(X)
	return 1
/proc/global_check(act)
	return isAI(act.actor)
/obj/machinery/proc/use2(datum/act/op/A)
	return global_check(A)
";
        assert_eq!(found(src), vec![("helper_actor_check".to_string(), 8)]);
    }

    #[test]
    fn timers_prompts_and_other_mobs_are_not_sites() {
        let src = "/obj/machinery/proc/pull(datum/act/timer/A)
	return isAI(A.actor)
/datum/prompt/choice/prepare(datum/act/A)
	return isAI(A.actor)
/obj/machinery/proc/plain(mob/user)
	return isAI(user)
/obj/machinery/proc/use(datum/act/op/A, mob/other)
	return helper(other)
/obj/machinery/proc/helper(mob/M)
	return isAI(M)
";
        assert_eq!(found(src), Vec::<(String, u32)>::new());
    }
}
