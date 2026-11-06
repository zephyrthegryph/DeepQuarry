//! `analyze gen actions` -> `code/engine/_generated/actions.dm` (E4, actions and hooks).
//!
//! `ACTION(name, typed fields..., FIXED, notice = /datum/notice/x)` expands to nothing in DM (code/__defines/engine/markers.dm). This reads each
//! one from source and writes what DM cannot (doc/rewrite/final_api.html section 8, "World actions"):
//!
//! * the act type `/datum/act/<name>` (parent `/datum/act/action`, or the parent action for a `hit/projectile` style name) with the typed fields,
//!   and `act_<name>(holder, fields...)`, which the `ACT_TRY(E, name, fields...)` macro calls: ACT_PASS when nothing hooks the action and nothing
//!   listens for its notice, null when it was refused or taken over, else the pooled act;
//! * the past-tense notice `/datum/notice/<past>` with the same fields, and `make_notice()` on the act, which copies the act's final fields into it;
//! * for a FIXED action (nothing can refuse it) no act type: `publish_<name>(holder, fields...)`, which `PUBLISH(E, name, field = v)` calls.
//!
//! The notice name is the action's name in the past tense (fall -> fell, insert -> inserted); a name that already reads as past tense (hit,
//! stumbled_into, round_started) is kept, and `notice =` overrides. A name with a slash inherits its parent's fields and its proc and ACT_TRY token
//! use an underscore. The `op` action's act type is the op context (code/host/acts/context.dm), so only its notice is generated.
//! A field named `origin` is declared `origin_turf` (every act has an ORIGIN_* `origin`); any other reserved name is a diagnostic.
//! Declarations in files under `code/tests/` go in an `#if defined(UNIT_TESTS)` block.

use crate::sem::gen::{GenCx, GenOut, Generator};
use std::collections::BTreeSet;
struct Actions;
impl Generator for Actions {
    fn name(&self) -> &'static str {
        "actions"
    }
    fn output(&self) -> &'static str {
        "actions.dm"
    }
    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        let mut builder = crate::actions_policy::Builder::default();
        for m in cx.markers("ACTION") {
            builder
                .push(&m.rel, m.line, &m.args)
                .expect("legacy row policy has no allocation ceiling");
        }
        let prepared = builder
            .prepare(|| Ok(()))
            .expect("legacy row policy has no allocation ceiling");
        let mut elsewhere = std::collections::BTreeMap::new();
        for notice in prepared.notices() {
            if !elsewhere.contains_key(notice) {
                elsewhere.insert(notice.to_owned(), declared_elsewhere(cx, notice));
            }
        }
        let generated = prepared
            .finish(
                |notice, name| {
                    elsewhere
                        .get(notice)
                        .is_some_and(|vars| vars.contains(name))
                },
                || Ok(()),
            )
            .expect("legacy row policy has no allocation ceiling");
        for d in generated.diags {
            out.diag(&d.rel, d.line, d.msg);
        }
        for line in generated.body.split_terminator('\n') {
            out.line(line);
        }
    }
}
/// The vars a notice type already has from a declaration outside the generated file.
fn declared_elsewhere(cx: &GenCx, notice: &str) -> BTreeSet<String> {
    // Which files mention a notice type: per-file facts (the runs of name characters after each `/datum/notice/`), read once per
    // content change. `contains(notice)` on the comment-stripped text is true exactly when some run starts with the notice's name.
    let mentions: std::sync::Arc<Vec<(String, Vec<String>)>> =
        cx.tree.memo("gen/notice_mentions", || {
            let all = cx.tree.select(&crate::tree::CODE_DM);
            let facts: Vec<Vec<String>> = crate::incr::facts("notice-mentions", &all, |f| {
                let text = &f.code().text;
                let mut out: Vec<String> = Vec::new();
                crate::actions_policy::visit_notice_mentions(text, |run| out.push(run.to_owned()));
                out.sort();
                out.dedup();
                out
            });
            all.iter()
                .zip(facts)
                .map(|(f, m)| (f.rel.clone(), m))
                .collect()
        });
    let files: Vec<&crate::tree::SourceFile> = match crate::actions_policy::notice_suffix(notice) {
        Some(rest) => mentions
            .iter()
            .filter(|(rel, m)| {
                rel != "code/engine/_generated/actions.dm"
                    && m.iter().any(|run| run.starts_with(rest))
            })
            .filter_map(|(rel, _)| cx.tree.get(rel))
            .collect(),
        _ => cx
            .tree
            .select(&crate::tree::CODE_DM)
            .into_iter()
            .filter(|f| {
                f.rel != "code/engine/_generated/actions.dm" && f.code().text.contains(notice)
            })
            .collect(),
    };
    let table = crate::dm::dx::type_vars_in(cx.tree, &files);
    table
        .get(notice)
        .map(|v| v.iter().cloned().collect())
        .unwrap_or_default()
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(Actions));
}
pub(crate) use crate::actions_policy::{past_tense, split_notice_opt};
#[cfg(test)]
mod tests {
    use super::*;

    use crate::sem::gen::render;
    use crate::tree::{SourceFile, Tree};
    use std::path::Path;

    fn gen(src: &str) -> (String, Vec<String>) {
        let tree = Tree::from_files(vec![SourceFile::from_text("code/a.dm", src)]);
        let cx = GenCx::new(&tree, Path::new("."));
        let (text, diags) = render(&Actions, &cx);
        (text, diags.into_iter().map(|d| d.msg).collect())
    }

    const SRC: &str = "ACTION(fall, turf/landing, mob/living/landed_on)
ACTION(move, turf/origin, turf/destination)
ACTION(hit, datum/damage_packet/packet)
ACTION(hit/projectile)
ACTION(slash, mob/living/slasher, FIXED)
ACTION(body_status, notice = /datum/notice/body_status_changed)
";

    #[test]
    fn an_action_gets_a_type_a_proc_and_a_notice() {
        let (text, diags) = gen(SRC);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(
            text.contains(
                "/datum/act/fall
	parent_type = /datum/act/action
	var/turf/landing
	var/mob/living/landed_on"
            ),
            "{}",
            text
        );
        assert!(
            text.contains(
                "/datum/notice/fell
	var/turf/landing"
            ),
            "the notice is the past tense: {}",
            text
        );
        assert!(text.contains("/proc/act_fall(datum/holder, turf/landing, mob/living/landed_on, act_answer = FALSE)"), "{}", text);
        assert!(
            text.contains("	return act_resolve(A, act_answer)"),
            "{}",
            text
        );
        assert!(
            text.contains(
                "/datum/act/move
	parent_type = /datum/act/action
	var/turf/origin_turf"
            ),
            "origin is the act's ORIGIN_*: {}",
            text
        );
    }

    #[test]
    fn a_slash_name_inherits_and_a_fixed_action_has_no_act() {
        let (text, _) = gen(SRC);
        assert!(text.contains("/proc/act_hit_projectile(datum/holder, datum/damage_packet/packet, act_answer = FALSE)"), "{}", text);
        assert!(text.contains("/datum/notice/hit/projectile"), "{}", text);
        assert!(
            !text.contains("/datum/act/slash"),
            "a FIXED action has no act type: {}",
            text
        );
        assert!(
            text.contains("/proc/publish_slash(datum/holder, mob/living/slasher)"),
            "{}",
            text
        );
        assert!(text.contains("/datum/notice/slashed"), "{}", text);
        assert!(
            text.contains("/datum/notice/body_status_changed"),
            "notice = overrides the name: {}",
            text
        );
    }

    #[test]
    fn a_reserved_field_and_an_orphan_subtype_are_reported() {
        let (_, diags) = gen("ACTION(poke, mob/actor)
ACTION(nowhere/child)
ACTION(poke, atom/x)
");
        assert!(
            diags.iter().any(|d| d.contains("every act carries")),
            "{:?}",
            diags
        );
        assert!(
            diags.iter().any(|d| d.contains("parent action `nowhere`")),
            "{:?}",
            diags
        );
        assert!(
            diags.iter().any(|d| d.contains("declared twice")),
            "{:?}",
            diags
        );
    }

    #[test]
    fn past_tense_rules() {
        assert_eq!(past_tense("fall"), "fell");
        assert_eq!(past_tense("move"), "moved");
        assert_eq!(past_tense("z_change"), "z_changed");
        assert_eq!(past_tense("insert"), "inserted");
        assert_eq!(past_tense("stumbled_into"), "stumbled_into");
        assert_eq!(past_tense("thrown_hit"), "thrown_hit");
        assert_eq!(past_tense("hit/projectile"), "hit/projectile");
        assert_eq!(past_tense("round_started"), "round_started");
        assert_eq!(past_tense("speak"), "spoke");
        assert_eq!(past_tense("equip"), "equipped");
        assert_eq!(past_tense("unequip"), "unequipped");
    }
    #[test]
    fn query_is_pooled_binding_not_event_or_notice() {
        let (text, diags) = gen("ACTION(admission_query, mob/wearer, mob/mover, datum/destination, slot_id, requirement_channel, list/query_options, QUERY)\n");
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(text.contains("parent_type = /datum/act/op"));
        assert!(text.contains("query_admission_query("));
        assert!(text.contains("act_context(query_type, holder, target, actor)"));
        assert!(text.contains("A.wearer = wearer"));
        assert!(text.contains("op_query_input_copy(query_options)"));
        assert!(!text.contains("act_begin("));
        assert!(!text.contains("act_resolve("));
        assert!(!text.contains("make_notice()"));
        assert!(!text.contains("/datum/notice/"));
        assert!(!text.contains("ALLOW("));
    }

    const QUERY_SRC: &str = "ACTION(admission_query, mob/wearer, mob/mover, datum/destination, slot_id, requirement_channel, list/query_options, QUERY)\n";

    #[test]
    fn query_binding_validates_all_inputs_before_pool_checkout() {
        let (text, diags) = gen(QUERY_SRC);
        assert!(diags.is_empty(), "{:?}", diags);
        let checkout = text
            .find("act_context(query_type, holder, target, actor)")
            .expect("one pooled checkout");
        assert_eq!(
            text.matches("act_context(query_type, holder, target, actor)")
                .count(),
            1
        );
        for validation in [
            "!ispath(query_type",
            "!holder || !istype(holder, /datum)",
            "!istype(target, /atom/movable)",
            "!istype(actor, /mob)",
            "!istype(wearer, /mob)",
            "!istype(mover, /mob)",
            "!istype(destination, /datum)",
            "op_query_input_copy(query_options",
            "istype(holder, /datum/pooled)",
            "istype(target, /datum/pooled)",
            "istype(actor, /datum/pooled)",
            "istype(wearer, /datum/pooled)",
            "istype(mover, /datum/pooled)",
            "istype(destination, /datum/pooled)",
        ] {
            assert!(
                text.find(validation).expect(validation) < checkout,
                "{} must not leak a checkout on invalid input",
                validation
            );
        }
        assert!(
            !text.contains("var/mob/wearer"),
            "typed inherited field must not be redeclared"
        );
        for effect in [
            "act_begin(",
            "act_resolve(",
            "notice_publish(",
            "publish_change(",
            "PUBLISH(",
            "METRICS_EVENT(",
            "make_notice()",
            "ALLOW(",
        ] {
            assert!(
                !text.contains(effect),
                "query constructor cannot execute world effect {}",
                effect
            );
        }
    }

    #[test]
    fn query_is_absent_from_normal_event_notice_registry() {
        let (text, diags) = gen(&format!("{}ACTION(fall, turf/landing)\n", QUERY_SRC));
        assert!(diags.is_empty(), "{:?}", diags);
        let registry = text
            .split("GLOBAL_LIST_INIT(action_notice_types,")
            .nth(1)
            .expect("ordinary action registry")
            .split("))")
            .next()
            .unwrap();
        assert!(registry.contains("/datum/act/fall = /datum/notice/fell"));
        assert!(
            !registry.contains("admission_query"),
            "queries are not observable actions"
        );
        assert!(!text.contains("/datum/notice/admission_queried"));
        assert!(
            text.contains("act_fall("),
            "adding queries must preserve ordinary events"
        );
    }

    #[test]
    fn invalid_query_schema_never_emits_a_binder() {
        for (src, diagnostic) in [
            (
                "ACTION(bad, mob/actor, mob/wearer, QUERY)",
                "every act carries",
            ),
            (
                "ACTION(bad, 123, mob/wearer, QUERY)",
                "neither a typed field",
            ),
            (
                "ACTION(bad, datum/mystery, QUERY)",
                "typed synchronous op admission schema",
            ),
            (
                "ACTION(bad, mob/destination, QUERY)",
                "typed synchronous op admission schema",
            ),
            (
                "ACTION(bad, mob/wearer, mob/wearer, QUERY)",
                "typed synchronous op admission schema",
            ),
            ("ACTION(bad, mob/wearer, QUERY, FIXED)", "QUERY cannot"),
            (
                "ACTION(bad, mob/wearer, QUERY, notice = /datum/notice/custom)",
                "QUERY cannot",
            ),
            ("ACTION(bad/child, mob/wearer, QUERY)", "QUERY cannot"),
        ] {
            let (text, diags) = gen(src);
            assert!(
                diags.iter().any(|d| d.contains(diagnostic)),
                "{}: {:?}",
                src,
                diags
            );
            assert!(
                !text.contains("/proc/query_bad"),
                "invalid schema cannot enter runtime: {}",
                text
            );
            assert!(
                !text.contains("act_context(query_type, holder, target, actor)"),
                "invalid schema cannot acquire pooled inputs"
            );
        }
    }
}
