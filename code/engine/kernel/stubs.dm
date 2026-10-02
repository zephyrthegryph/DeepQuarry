// E0 stubs for E6's kernel and input surface (doc/rewrite/final_api.html, sections 2 and 15; section 19 "E6, kernel completion").
//
// Each proc is the entry point the test driver's kernel and input forms call. It reports what it needs through ENGINE_STUB, so
// a proof that reaches it fails with "E1-E6 not implemented: <what>", and returns null. E6 (with E2 for the resolver behind
// the inbox) replaces the body and keeps the signature. No runtime behaviour here.

/// Resolves a click through the input inbox as origin `origin` would, and returns the op's /datum/op_result (null outcome
/// while it waits), or null when nothing resolved. E6 owns the inbox; E2 owns the resolver it hands the event to.
/proc/inbox_click(mob/actor, atom/target, obj/item/held, gesture, origin)
	RETURN_TYPE(/datum/op_result)
	ENGINE_STUB(ENGINE_E6, "input inbox: inbox_click (a click resolved through the inbox, then the E2 resolver)")
	return null

/// Presses a window button: the args cross the schema boundary, the op's ui_act() binding matches. Returns the op's /datum/op_result.
/proc/inbox_ui(mob/actor, window, action, list/args)
	RETURN_TYPE(/datum/op_result)
	ENGINE_STUB(ENGINE_E6, "input inbox: inbox_ui (a window action through the inbox, then the E2 ui_act() binding)")
	return null

/// Picks an op by key from a target's menu (origin ORIGIN_MENU), with `held` as the held item. Returns the op's /datum/op_result.
/proc/inbox_menu(mob/actor, atom/target, op_key, obj/item/held)
	RETURN_TYPE(/datum/op_result)
	ENGINE_STUB(ENGINE_E6, "input inbox: inbox_menu (a menu pick through the inbox, then the E2 resolver)")
	return null

/// Answers the actor's open request with `value`, or ends it with a REQ_* `outcome`. Returns the /datum/op_result of the op that
/// was waiting (the same record the earlier call gave back), now advanced.
/proc/request_answer(mob/actor, value, outcome)
	RETURN_TYPE(/datum/op_result)
	ENGINE_STUB(ENGINE_E6, "request layer: request_answer (the workflow step answer and its resume)")
	return null

/// Runs one marked drain now.
/proc/kernel_drain_now()
	ENGINE_STUB(ENGINE_E6, "kernel: kernel_drain_now (a marked drain under each lane budget)")

/// Runs one kernel phase once, at the current time, moving no clock.
/proc/kernel_phase_run(phase)
	ENGINE_STUB(ENGINE_E6, "kernel: kernel_phase_run (one phase K, S, N, U, D, P, R or G)")

/// Advances the kernel clock by `t` deciseconds, running every phase and every drain that falls due, in order.
/proc/kernel_time_advance(t)
	ENGINE_STUB(ENGINE_E6, "kernel: kernel_time_advance (the clock moves, every due phase and drain runs)")
