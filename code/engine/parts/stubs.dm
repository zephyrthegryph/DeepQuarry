// E0 stubs for E2's public surface (doc/rewrite/final_api.html, sections 8 and 9; section 19 "E2, parts"): performing an op by
// key, reading menus, spending a resource, and the explain tools. Signatures are the final ones; a body reports what it needs
// through ENGINE_STUB and returns null until E2 lands. No runtime behaviour here.
//
// Name clash. The final name of three of these is taken on master by the live legacy op layer (code/datums/operations/actions.dm:
// perform_op, action_options, screentip_for), and the legacy callers outnumber what E0 may touch. The stubs carry an e0_ prefix;
// the proofs reach them through the test-only aliases in code/modules/unit_tests/dq_e0_aliases.dm, which spell the final name,
// so a proof reads as section 19 writes it. E2 deletes the legacy procs, renames these to the final names and deletes the aliases.

/// The final perform_op(): runs the op named `key` on `target` through whichever binding accepts `origin` (default ORIGIN_AI) and
/// returns a /datum/op_result. An op that still waits comes back with a null outcome and the same record is filled in later.
/// `authority` is an AUTH_* with its datum for an admin call; `trace` prints the resolution.
/proc/e0_perform_op(mob/actor, atom/target, key, obj/item/held, origin = ORIGIN_AI, authority, trace = FALSE)
	RETURN_TYPE(/datum/op_result)
	ENGINE_STUB(ENGINE_E2, "op engine: perform_op (an op by key, returning a /datum/op_result)")
	return null

/// The final action_options(): every candidate op on `target` for `actor` holding `held`, as a list of assoc lists with "key",
/// "label", "enabled" and "reason". Evaluated lazily and cached on (actor, target, held, their generations, the actor provider set generation).
/proc/e0_action_options(mob/actor, atom/target, obj/item/held)
	ENGINE_STUB(ENGINE_E2, "resolver: action_options (the menu candidates and their reasons)")
	return null

/// The final screentip_for(): the text of the op a `gesture` would run, or null.
/proc/e0_screentip_for(mob/actor, atom/target, obj/item/held, gesture)
	ENGINE_STUB(ENGINE_E2, "resolver: screentip_for (the text of the op a click would run)")
	return null

/// perform_intent(actor, target, INTENT_X, held): the same path through the ops with a physical binding; returns the key of the op that ran, or null.
/proc/perform_intent(mob/actor, atom/target, intent, obj/item/held)
	ENGINE_STUB(ENGINE_E2, "op engine: perform_intent")
	return null

/// explain_click(): every candidate for a click, the filter that dropped it (entry file:line), the winner and its tier.
/proc/explain_click(mob/actor, atom/target, obj/item/held, gesture)
	ENGINE_STUB(ENGINE_E2, "explain tooling: explain_click")
	return null

/// Asserts in a unit test that a click resolves to `key`.
/proc/assert_resolves(mob/actor, atom/target, obj/item/held, gesture, key)
	ENGINE_STUB(ENGINE_E2, "explain tooling: assert_resolves")
	return FALSE

/// res_spend(): code outside an op reserves and commits `n` of `resource` in one call with an explicit context; returns `n`, or 0 when it could not be spent.
/proc/res_spend(datum/holder, resource, n, mob/actor, obj/item/held, atom/target)
	ENGINE_STUB(ENGINE_E2, "resource transactions: res_spend (reserve and commit in one call)")
	return 0
