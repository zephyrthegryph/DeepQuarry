//! Compatibility wrapper over the SAME unique raw handler policy.
use super::decls::Decls;
pub use crate::reactive_hooks_policy::{Ctx,Role,HookForm,HOOK_FORMS,HandlerRef};
fn markers(decls:&Decls)->Vec<crate::declare_policy::Marker<'_>>{
 decls.markers.iter().map(|m|crate::declare_policy::Marker{name:&m.name,rel:&m.rel,line:m.line,body:&m.body,args:&m.args,body_offset:m.body_offset,line_starts:&m.line_starts}).collect()
}
pub fn discover(decls:&Decls)->Vec<HandlerRef>{crate::reactive_hooks_policy::discover(&markers(decls))}
pub fn discover_in(decls:&Decls,names:&[&str])->Vec<HandlerRef>{crate::reactive_hooks_policy::discover_in(&markers(decls),names)}

#[cfg(test)]
mod context_tests {
    use super::*;
    use crate::tree::{SourceFile, Tree};

    fn handlers(source: &str) -> Vec<HandlerRef> {
        let file = SourceFile::from_text("code/content/probe.dm", source);
        let tree = Tree::from_files(vec![file]);
        let decls = Decls::get(&tree);
        let found = discover(&decls);
        assert!(!found.is_empty(), "the fixture must discover its declarations");
        found
    }

    #[test]
    fn runtime_observe_typed_requirements_are_read_roots() {
        let found = handlers("/datum/test/proc/register()\n\tvar/H = observe(box, /datum/act/insert, P, needs(req(TYPE_PROC_REF(/datum/probe, admission))))\n");
        assert_eq!(found.len(), 1);
        let handler = &found[0];
        assert_eq!(handler.owner, "/datum/probe");
        assert_eq!(handler.proc, "admission");
        assert_eq!(handler.ctx, Ctx::Op);
        assert_eq!(handler.role, Role::Requirement);
        assert!(handler.role.reads_covered());
        assert_eq!(handler.line, 2);
    }

    #[test]
    fn runtime_observe_preserves_typed_event_effects_and_op_requirements() {
        let found = handlers("/proc/install()\n\tobserve(host, /datum/notice/ended, listener, then(TYPE_PROC_REF(/datum/probe, heard)))\n\tobserve(host, /datum/act/strike, listener, instead(when(TYPE_PROC_REF(/datum/probe, blocks))), needs(req(TYPE_PROC_REF(/datum/probe, admission))))\n");
        let heard = found.iter().find(|h| h.proc == "heard").unwrap();
        assert_eq!(heard.ctx, Ctx::Notice);
        assert_eq!(heard.notice, "/datum/notice/ended");
        assert_eq!(heard.role, Role::Reaction);
        let blocks = found.iter().find(|h| h.proc == "blocks").unwrap();
        assert_eq!(blocks.ctx, Ctx::Action);
        assert_eq!(blocks.notice, "/datum/act/strike");
        let admission = found.iter().find(|h| h.proc == "admission").unwrap();
        assert_eq!(admission.ctx, Ctx::Op);
        assert_eq!(admission.role, Role::Requirement);
    }

    #[test]
    fn runtime_observe_exact_act_root_uses_notice_delivery() {
        // observe() only uses action hooks for descendants of /datum/act/action;
        // the exact /datum/act root takes the notice-delivery branch.
        let found = handlers("/proc/test()\n\tobserve(source, /datum/act, listener, then(TYPE_PROC_REF(/datum/probe, heard)))\n");
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].ctx, Ctx::Notice);
        assert_eq!(found[0].notice, "/datum/act");
        assert_eq!(found[0].role, Role::Reaction);
    }

    #[test]
    fn runtime_legacy_key_subscription_is_not_an_act_callback() {
        let file = SourceFile::from_text("code/content/probe.dm", "/proc/test()\n\tobserve(source, on_change(list(key), TYPE_PROC_REF(/datum/probe, on_key)), listener, TYPE_PROC_REF(/datum/probe, on_key))\n");
        let tree = Tree::from_files(vec![file]);
        assert!(discover(&Decls::get(&tree)).is_empty());
    }

    #[test]
    fn runtime_observe_ignores_strings_comments_and_member_calls() {
        let file = SourceFile::from_text("code/content/probe.dm",
            "/proc/observe(a, b, c, d)\n\treturn\n/proc/test()\n\tvar/text = \"observe(a, b, c, needs(req(TYPE_PROC_REF(/datum/probe, string_fake))))\"\n\t// observe(a, b, c, needs(req(TYPE_PROC_REF(/datum/probe, comment_fake))))\n\tx.observe(a, b, c, needs(req(TYPE_PROC_REF(/datum/probe, member_fake))))\n");
        let tree = Tree::from_files(vec![file]);
        assert!(discover(&Decls::get(&tree)).is_empty());
    }

    #[test]
    fn change_value_getter_is_an_output_but_handler_is_a_reaction() {
        let found = handlers("CAPABILITIES(/datum/probe)\n\ton_change(all_of(PROC_REF(value), PROC_REF(other)), ANY, then(PROC_REF(deliver)))\n");
        let value = found.iter().find(|h| h.proc == "value").unwrap();
        assert_eq!(value.ctx, Ctx::Eval);
        assert_eq!(value.role, Role::Output);
        assert!(value.role.reads_covered());
        assert_eq!(found.iter().find(|h| h.proc == "other").unwrap().role, Role::Output);
        let deliver = found.iter().find(|h| h.proc == "deliver").unwrap();
        assert_eq!(deliver.ctx, Ctx::Notice);
        assert_eq!(deliver.role, Role::Reaction);
    }

    #[test]
    fn requirement_protocol_callbacks_keep_purity_reads_and_distinct_return_shapes() {
        let found = handlers("CAPABILITIES(/datum/probe)\n\top(\"use\", needs(req(PROC_REF(reason)), req_bool(PROC_REF(boolean))), then(PROC_REF(effect)))\n");
        let reason = found.iter().find(|handler| handler.proc == "reason").unwrap();
        let boolean = found.iter().find(|handler| handler.proc == "boolean").unwrap();
        assert_eq!(reason.ctx, Ctx::Op);
        assert_eq!(reason.role, Role::Requirement);
        assert!(!reason.role.boolean());
        assert_eq!(boolean.ctx, Ctx::Op);
        assert_eq!(boolean.role, Role::BooleanRequirement);
        assert!(boolean.role.boolean());
        for handler in [reason, boolean] {
            assert!(handler.role.pure());
            assert!(handler.role.reads_covered());
        }
    }

    #[test]
    fn requirement_protocol_window_remote_predicate_stays_boolean_with_its_own_reason() {
        let found = handlers("CAPABILITIES(/datum/probe)\n\top(\"use\", needs(req_window_usable(remote = PROC_REF(remote_allowed), remote_because = PROC_REF(remote_refusal)), req(PROC_REF(final_requirement))), then(PROC_REF(effect)))\n");
        let remote = found.iter().find(|handler| handler.proc == "remote_allowed").unwrap();
        assert_eq!(remote.ctx, Ctx::Op);
        assert_eq!(remote.role, Role::Condition);
        assert!(remote.role.boolean());
        assert!(remote.role.pure());
        assert!(remote.role.reads_covered());
        let refusal = found.iter().find(|handler| handler.proc == "remote_refusal").unwrap();
        assert_eq!(refusal.ctx, Ctx::Op);
        assert_eq!(refusal.role, Role::Reason);
        assert!(!refusal.role.boolean());
        assert_eq!(found.iter().find(|handler| handler.proc == "final_requirement").unwrap().role, Role::Requirement);
        assert_eq!(found.iter().find(|handler| handler.proc == "effect").unwrap().role, Role::Effect);
    }

    #[test]
    fn only_notice_carried_then_handlers_gain_reaction_role() {
        let found = handlers("CAPABILITIES(/datum/probe)
	on_notice(/datum/notice/probe, then(PROC_REF(noticed)))
	on_op(\"use\", then(PROC_REF(completed)))
	every(10, then(PROC_REF(tick)))
	op(\"ordinary\", then(PROC_REF(effect)))
");
        for name in ["noticed", "completed"] {
            let handler = found.iter().find(|h| h.proc == name).unwrap();
            assert_eq!(handler.role, Role::Reaction);
            assert_eq!(handler.ctx, Ctx::Notice);
        }
        assert_eq!(found.iter().find(|h| h.proc == "tick").unwrap().role, Role::Effect);
        assert_eq!(found.iter().find(|h| h.proc == "effect").unwrap().role, Role::Effect);
    }

    #[test]
    fn operation_when_receives_full_op_but_periodic_when_does_not() {
        let found = handlers("CAPABILITIES(/datum/probe)\n\top(\"use\", item(/obj), when(PROC_REF(offered)), then(PROC_REF(use)))\n\top(\"nested\", every(10, when = PROC_REF(ready), then(PROC_REF(tick))))\n\tevery(10, when = PROC_REF(standalone_ready), then(PROC_REF(standalone_tick)))\n");
        assert_eq!(found.iter().find(|h| h.proc == "offered").unwrap().ctx, Ctx::Op);
        assert_eq!(found.iter().find(|h| h.proc == "ready").unwrap().ctx, Ctx::Eval);
        assert_eq!(found.iter().find(|h| h.proc == "standalone_ready").unwrap().ctx, Ctx::Eval);
        assert_eq!(found.iter().find(|h| h.proc == "tick").unwrap().ctx, Ctx::Timer);
    }

    #[test]
    fn nested_every_members_effect_uses_timer_context() {
        let found = handlers("CAPABILITIES(/datum/system/probe)\n\tevery(10, then(PROC_REF(visit)), members = /datum/member, when = PROC_REF(ready))\n\top(\"ordinary\", then(PROC_REF(ordinary)))\n");
        let visit = found.iter().find(|h| h.proc == "visit").unwrap();
        assert_eq!(visit.ctx, Ctx::Timer);
        assert_eq!(visit.form, "then");
        assert_eq!(found.iter().find(|h| h.proc == "ready").unwrap().ctx, Ctx::Eval, "every admission conditions remain evaluation contexts");
        assert_eq!(found.iter().find(|h| h.proc == "ordinary").unwrap().ctx, Ctx::Op, "ordinary effects retain operation contexts");
    }

    #[test]
    fn nearest_timer_carrier_wins_and_does_not_take_ui_args() {
        let found = handlers("CAPABILITIES(/datum/probe)\n\top(\"press\", ui_act(\"press\", arg(\"value\")), on_notice(/datum/notice/probe, delayed(10, then(PROC_REF(later)))))\n");
        let later = found.iter().find(|h| h.proc == "later").unwrap();
        assert_eq!(later.ctx, Ctx::Timer, "a delayed effect receives a timer rather than its enclosing notice");
        assert!(later.ui_args.is_none(), "timer callbacks do not inherit UI invocation parameters");
    }
    #[test]
    fn registry_when_is_pure_but_init_only_while_live_conditions_remain_reactive() {
        let found = handlers("CAPABILITIES(/obj/probe)\n\tregistry(\"joins\", when = PROC_REF(initial_join))\n\top(\"use\", when(PROC_REF(live_gate)), then(PROC_REF(effect)))\n\tevery(1, then(PROC_REF(step)), when = PROC_REF(periodic_gate))\n");
        let initial = found.iter().find(|h| h.proc == "initial_join").unwrap();
        assert_eq!(initial.role, Role::InitCondition);
        assert!(initial.role.pure() && initial.role.boolean());
        assert!(!initial.role.reads_covered());
        for name in ["live_gate", "periodic_gate"] {
            let live = found.iter().find(|h| h.proc == name).unwrap();
            assert_eq!(live.role, Role::Condition);
            assert!(live.role.reads_covered());
        }
    }

    #[test]
    fn quoted_registry_text_does_not_hide_a_live_condition() {
        let found = handlers("CAPABILITIES(/obj/probe)\n\top(\"registry(fake(\", when(PROC_REF(live_gate)), then(PROC_REF(effect)))\n");
        assert_eq!(found.iter().find(|h| h.proc == "live_gate").unwrap().role, Role::Condition);
    }

}
