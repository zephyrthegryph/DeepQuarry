// Operations (code/datums/operations/): requirement flyweights, the pooled op_ctx and its stage
// order, cap_op / cap_require / refine, compartments, actions and the timed wait.

/obj/cap_fixture/ops
	name = "ops fixture"
	req_access = list(ACCESS_ENGINE)

/obj/cap_fixture/ops/capabilities()
	. = ..()
	. += cap_op("Latch", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), action = ACT_LOCK, needs = req_clear(CAP_LOCKED), key = "latch")
	. += cap_op("Rip out", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), action = ACT_DISMANTLE, kind = OP_STRUCTURAL, key = "rip")
	. += cap_require(OP_STRUCTURAL, needs = req_set(CAP_PANEL_OPEN))
	. += cap_op("Slow", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), action = ACT_TOGGLE, delay = 3 SECONDS, needs = req_clear(CAP_LOCKED), key = "slow")
	. += cap_op("Press", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), action = ACT_USE, via = ROUTE_PHYSICAL | ROUTE_VERB, key = "press")
	. += cap_op("Panel", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), action = ACT_CLOSE, via = ROUTE_PHYSICAL | ROUTE_UI, key = "panel")
	. += cap_control("Console", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), action = ACT_OPEN, key = "console")
	. += cap_op("Remote", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), via = ROUTE_UI, needs = req_set(CAP_EMAGGED), action = ACT_PULL, key = "remote")
	. += cap_op("Impossible", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), by = (1<<12), via = ROUTE_UI, needs = req_set(CAP_EMAGGED), action = ACT_PRY, key = "impossible")
	. += cap_op("Bayed", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), at = BAY_INTERIOR, action = ACT_EJECT, key = "bayed")
	. += compartment(BAY_INTERIOR, door = CAP_PANEL_OPEN, heat = 0.25, gas = FALSE)

/obj/cap_fixture/ops/proc/fx_op(mob/user)
	LAZYADD(calls, "op")
	return TRUE

/obj/cap_fixture/ops/proc/fx_gate(mob/user, obj/item/held)
	return calls_allowed ? TRUE : "the gears are jammed"

/obj/cap_fixture/ops
	var/calls_allowed = FALSE

/// The same fixture with the slow op made slower and the press op rerouted by refine().
/obj/cap_fixture/ops/refined

/obj/cap_fixture/ops/refined/capabilities()
	. = ..()
	. += refine("slow", delay = 9 SECONDS, action = ACT_CLOSE)

/// The op capability of F with key `key`.
/proc/dx_op_of(atom/A, key)
	RETURN_TYPE(/datum/op_def)
	return cap_op_of(cap_of(A, "op:[key]"))

// ---- requirements ----

/datum/unit_test/dx_op_reqs

/datum/unit_test/dx_op_reqs/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/ops/F = allocate(/obj/cap_fixture/ops, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/datum/op_ctx/ctx = op_ctx_take(H, F, null, dx_op_of(F, "latch"))

	TEST_ASSERT(req_set(CAP_LOCKED) == req_set(CAP_LOCKED), "the same declaration is one shared flyweight")
	TEST_ASSERT(req_set(CAP_LOCKED) != req_clear(CAP_LOCKED), "set and clear are different flyweights")
	TEST_ASSERT(all_of(req_set(CAP_PANEL_OPEN), req_clear(CAP_LOCKED)) == all_of(req_set(CAP_PANEL_OPEN), req_clear(CAP_LOCKED)), "composites intern too")

	TEST_ASSERT_NULL(req_clear(CAP_LOCKED).test(ctx), "not locked: holds")
	TEST_ASSERT_EQUAL(req_set(CAP_LOCKED).test(ctx), /datum/msg/req_wrong_state, "not locked: req_set fails with the state reason")
	cap_set(F, CAP_LOCKED, TRUE)
	TEST_ASSERT_NULL(req_set(CAP_LOCKED).test(ctx), "locked: req_set holds")
	TEST_ASSERT_EQUAL(req_clear(CAP_LOCKED).test(ctx), /datum/msg/req_wrong_state, "locked: req_clear fails")
	var/list/reads = req_clear(CAP_LOCKED).reads(ctx)
	TEST_ASSERT_EQUAL(length(reads), 1, "req_clear reads one thing")
	TEST_ASSERT_EQUAL(reads[1][1], F, "it reads the target")
	TEST_ASSERT_EQUAL(reads[1][2], OP_KEY_CAP_STATE, "its cap_state")

	TEST_ASSERT_NULL(any_of(req_set(CAP_LOCKED), req_set(CAP_EMAGGED)).test(ctx), "any_of: one part holds")
	TEST_ASSERT_EQUAL(any_of(req_set(CAP_EMAGGED), req_set(CAP_BROKEN)).test(ctx), /datum/msg/req_wrong_state, "any_of: none holds, the first reason")
	TEST_ASSERT_EQUAL(all_of(req_set(CAP_LOCKED), req_set(CAP_EMAGGED)).test(ctx), /datum/msg/req_wrong_state, "all_of: one fails")
	TEST_ASSERT_EQUAL(none_of(req_set(CAP_LOCKED)).test(ctx), /datum/msg/req_forbidden, "none_of: a part holds")
	TEST_ASSERT_NULL(none_of(req_set(CAP_EMAGGED)).test(ctx), "none_of: no part holds")

	TEST_ASSERT_EQUAL(req_access().test(ctx), /datum/msg/req_no_access, "no access to an access-locked fixture")
	ctx.route = ROUTE_AUTHORITY
	TEST_ASSERT_NULL(req_access().test(ctx), "authority route passes the access requirement")
	ctx.route = ROUTE_PHYSICAL

	TEST_ASSERT_EQUAL(req(/obj/item/pen).test(ctx), /datum/msg/req_wrong_item, "no held item: not a pen")
	ctx.held = allocate(/obj/item/pen, T)
	TEST_ASSERT_NULL(req(/obj/item/pen).test(ctx), "holding a pen")
	TEST_ASSERT_NULL(req(list(/obj/item/paper, /obj/item/pen)).test(ctx), "a list of types")
	TEST_ASSERT_EQUAL(req_part(/obj/item/cell).test(ctx), /datum/msg/req_no_part, "no cell inside")
	var/obj/item/cell/C = allocate(/obj/item/cell, F)
	TEST_ASSERT_NULL(req_part(/obj/item/cell).test(ctx), "a cell inside")
	TEST_ASSERT(C.loc == F, "the fixture holds the cell")

	var/datum/req/gate = req_proc(TYPE_PROC_REF(/obj/cap_fixture/ops, fx_gate))
	TEST_ASSERT_EQUAL(gate.test(ctx), /datum/msg/req_refused, "a proc's refusal is a refused reason")
	TEST_ASSERT_EQUAL(req_reason_text(/datum/msg/req_refused, ctx), "the gears are jammed", "with its text as the detail")
	F.calls_allowed = TRUE
	TEST_ASSERT_NULL(gate.test(ctx), "the proc allows")
	ctx.release()

// ---- the pooled context and the stage order ----

/datum/unit_test/dx_op_ctx

/datum/unit_test/dx_op_ctx/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/ops/F = allocate(/obj/cap_fixture/ops, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	var/datum/op_ctx/first = op_ctx_take(H, F, null, dx_op_of(F, "latch"))
	var/first_id = first.id
	TEST_ASSERT(first.id > 0 && GLOB.op_ctx_live["[first.id]"] == first, "a taken context is live")
	first.release()
	TEST_ASSERT(first.released && isnull(first.actor) && isnull(first.target), "release() resets every field")
	var/datum/op_ctx/second = op_ctx_take(H, F, null, dx_op_of(F, "latch"))
	TEST_ASSERT(second == first, "the pool hands the same datum out again")
	TEST_ASSERT(second.id != first_id && !second.released, "with a fresh id, live again")
	second.release()

	// Provider first: no slot gives the affordance, so the route and the needs are never asked.
	var/datum/op_ctx/ctx = op_ctx_take(H, F, null, dx_op_of(F, "impossible"))
	TEST_ASSERT_EQUAL(ctx.check(), /datum/msg/req_no_provider, "provider is the first stage")
	TEST_ASSERT_EQUAL(ctx.failed_stage, OP_STAGE_PROVIDER, "failed at the provider stage")
	ctx.release()

	// Route second: a UI-only op over the physical route, with its needs also unmet.
	ctx = op_ctx_take(H, F, null, dx_op_of(F, "remote"))
	TEST_ASSERT_EQUAL(ctx.check(), /datum/msg/req_no_route, "route comes before the op's needs")
	TEST_ASSERT_EQUAL(ctx.failed_stage, OP_STAGE_ROUTE, "failed at the route stage")
	ctx.release()

	// Over the UI route the needs stage is reached (last).
	ctx = op_ctx_take(H, F, null, dx_op_of(F, "remote"), ROUTE_UI)
	TEST_ASSERT_EQUAL(ctx.check(), /datum/msg/req_wrong_state, "needs answer last")
	TEST_ASSERT_EQUAL(ctx.failed_stage, OP_STAGE_NEEDS, "failed at the needs stage")
	TEST_ASSERT_NOTNULL(ctx.provider, "the provider was resolved on the way")
	TEST_ASSERT_EQUAL(ctx.provider.slot_id, SLOT_ID_HAND_R, "the active hand provides")
	H.hand = 1
	ctx.check()
	TEST_ASSERT_EQUAL(ctx.provider.slot_id, SLOT_ID_HAND_L, "and the active hand is asked first")
	H.hand = null
	ctx.release()

	// Actor state third: an unconscious actor is refused by an ordinary op, allowed an emergency one.
	H.stat = UNCONSCIOUS
	ctx = op_ctx_take(H, F, null, dx_op_of(F, "press"))
	TEST_ASSERT_EQUAL(ctx.check(), /datum/msg/req_not_capable, "an unconscious actor can't")
	TEST_ASSERT_EQUAL(ctx.failed_stage, OP_STAGE_ACTOR, "at the actor stage")
	ctx.release()
	H.stat = CONSCIOUS

	// Capability contract fifth: cap_require(OP_STRUCTURAL) covers the structural op only.
	ctx = op_ctx_take(H, F, null, dx_op_of(F, "rip"))
	ctx.entry = dx_cap_entry(F, "Rip out")
	TEST_ASSERT_EQUAL(ctx.check(), /datum/msg/req_wrong_state, "the structural contract applies")
	TEST_ASSERT_EQUAL(ctx.failed_stage, OP_STAGE_CAPS, "at the capability stage")
	cap_set(F, CAP_PANEL_OPEN, TRUE)
	TEST_ASSERT_NULL(ctx.check(), "with the panel open it passes")
	ctx.release()
	ctx = op_ctx_take(H, F, null, dx_op_of(F, "press"))
	cap_set(F, CAP_PANEL_OPEN, FALSE)
	TEST_ASSERT_NULL(ctx.check(), "the contract does not touch other kinds")
	ctx.release()

	// A released context is poisoned: a second release is a bug.
	TEST_ASSERT(GLOB.op_ctx_live["[first_id]"] != first, "the released context is no longer live under its old id")

// ---- cap_op, presets, refine ----

/datum/unit_test/dx_op_cap_op

/datum/unit_test/dx_op_cap_op/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/ops/F = allocate(/obj/cap_fixture/ops, T)
	var/obj/cap_fixture/ops/refined/R = allocate(/obj/cap_fixture/ops/refined, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	var/datum/op_def/latch = dx_op_of(F, "latch")
	TEST_ASSERT_NOTNULL(latch, "cap_op declares an op under its key")
	TEST_ASSERT_EQUAL(latch.by, AFF_MANIPULATE, "a plain op needs a manipulating provider")
	TEST_ASSERT_EQUAL(latch.via, ROUTE_PHYSICAL, "over the physical route")
	TEST_ASSERT_EQUAL(latch.action, ACT_LOCK, "answering ACT_LOCK")
	var/datum/op_def/console = dx_op_of(F, "console")
	TEST_ASSERT_EQUAL(console.by, AFF_CONTROL, "cap_control needs AFF_CONTROL")
	TEST_ASSERT_EQUAL(console.via, ROUTE_PHYSICAL | ROUTE_INTERFACE, "over the physical or interface route")

	// The old constructors are presets: no provider, lenient, and unchanged gating.
	var/datum/capability/entry/hand_cap = cap_hand("Old", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), behind = PANEL, locked_by = LOCK)
	var/datum/op_def/old = cap_op_of(hand_cap)
	TEST_ASSERT(old.legacy, "cap_hand is a legacy preset")
	TEST_ASSERT_EQUAL(old.by, NONE, "with no provider requirement")
	TEST_ASSERT_EQUAL(length(old.gating), 2, "the old gating args are mapped onto requirements")
	TEST_ASSERT(req_set(PANEL) in old.gating, "behind became req_set")
	TEST_ASSERT(req_clear(LOCK) in old.gating, "locked_by became req_clear")
	TEST_ASSERT_EQUAL(hand_cap.key, hand_cap.entry.id, "a preset keeps its old key")
	var/datum/op_def/tool_op = cap_op_of(cap_tool("Wrench it", TOOL_WRENCH, TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), delay = 2 SECONDS))
	TEST_ASSERT_EQUAL(tool_op.using, TOOL_WRENCH, "cap_tool uses a tool quality")
	TEST_ASSERT_EQUAL(tool_op.delay, 2 SECONDS, "with its delay")
	var/datum/op_def/use_op = cap_op_of(cap_use_on("Write", /obj/item/pen, TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op)))
	TEST_ASSERT_EQUAL(use_op.using, /obj/item/pen, "cap_use_on uses an item type")

	// The presets still run through the old entry machinery: gating reasons are the old words.
	var/datum/interaction/capability/E = dx_cap_entry(F, "Latch")
	TEST_ASSERT_NOTNULL(E, "the op builds an interaction entry")
	TEST_ASSERT_EQUAL(E.op, latch, "linked to its op")
	TEST_ASSERT_NULL(E.why_not(H, F, null), "runnable when its requirements hold")
	cap_set(F, CAP_LOCKED, TRUE)
	TEST_ASSERT_EQUAL(E.why_not(H, F, null), "it isn't in the right state for that", "refused with the requirement's reason")
	cap_set(F, CAP_LOCKED, FALSE)

	// The same key twice is the init error; replace = TRUE and refine() are not.
	var/datum/capability/first = cap_op("A", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), key = "dup")
	var/datum/capability/again = cap_op("B", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), key = "dup")
	var/datum/capability/replacing = cap_op("C", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), key = "dup", replace = TRUE)
	TEST_ASSERT(cap_op_key_conflict(again, first), "the same op key declared twice conflicts")
	TEST_ASSERT(!cap_op_key_conflict(replacing, first), "replace = TRUE is allowed")
	TEST_ASSERT(!cap_op_key_conflict(cap_hand("A", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op)), cap_hand("A", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op))), "presets keep the old silent replace")
	var/list/into = caps_intern_list(list(first, replacing))
	TEST_ASSERT_EQUAL(length(into), 1, "the replacing op takes the place of the first")
	TEST_ASSERT_EQUAL(cap_op_of(into[1]).name, "C", "it is the replacement")

	// refine() edits the op in place: same position, same key, new delay and action.
	var/datum/op_def/slow = dx_op_of(F, "slow")
	var/datum/op_def/slower = dx_op_of(R, "slow")
	TEST_ASSERT_EQUAL(slow.delay, 3 SECONDS, "the base op waits 3s")
	TEST_ASSERT_EQUAL(slower.delay, 9 SECONDS, "the refined one 9s")
	TEST_ASSERT_EQUAL(slower.action, ACT_CLOSE, "and answers another action")
	TEST_ASSERT_EQUAL(slower.handler, slow.handler, "the handler it did not refine is kept")
	TEST_ASSERT_EQUAL(length(caps_of(R)), length(caps_of(F)), "refining adds no capability")

// ---- compartments ----

/datum/unit_test/dx_op_compartment

/datum/unit_test/dx_op_compartment/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/ops/F = allocate(/obj/cap_fixture/ops, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	var/datum/capability/compartment/bay = compartment_of(F, BAY_INTERIOR)
	TEST_ASSERT_NOTNULL(bay, "the fixture declares a bay")
	TEST_ASSERT_NULL(compartment_of(F, BAY_CARGO), "and no other")
	TEST_ASSERT_EQUAL(bay.transmission(PATH_EFFECT_HEAT), 0.25, "heat crosses at the declared share")
	TEST_ASSERT_EQUAL(bay.transmission(PATH_EFFECT_GAS), 0, "gas is stopped")
	TEST_ASSERT_EQUAL(bay.transmission(PATH_EFFECT_RADIATION), 1, "radiation is unchanged")

	var/datum/op_ctx/ctx = op_ctx_take(H, F, null, dx_op_of(F, "bayed"))
	ctx.entry = dx_cap_entry(F, "Bayed")
	TEST_ASSERT_EQUAL(ctx.check(), /datum/msg/req_sealed, "the closed door keeps the physical route out")
	TEST_ASSERT_EQUAL(ctx.failed_stage, OP_STAGE_ROUTE, "at the route stage")
	cap_set(F, CAP_PANEL_OPEN, TRUE)
	TEST_ASSERT_NULL(ctx.check(), "an open door lets it through")
	ctx.release()

	// A bay the type never declared refuses the op (fail closed).
	var/datum/op_def/lost = cap_op_of(cap_op("Lost", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), at = BAY_CARGO, key = "lost"))
	ctx = op_ctx_take(H, F, null, lost)
	TEST_ASSERT_EQUAL(ctx.check(), /datum/msg/req_sealed, "no such bay: refused")
	ctx.release()

	// door = CAP_KEY and route_gate, on a boundary of their own.
	var/datum/capability/compartment/keyed = compartment(BAY_CARGO, door = CAP_KEY, route_gate = req_clear(CAP_BROKEN))
	ctx = op_ctx_take(H, F, null, dx_op_of(F, "bayed"))
	TEST_ASSERT(!keyed.passes(ROUTE_PHYSICAL, ctx), "CAP_KEY: no access, no physical route")
	TEST_ASSERT_EQUAL(ctx.reason, /datum/msg/req_no_access, "for want of access")
	ctx.reason = null
	TEST_ASSERT(keyed.passes(ROUTE_UI, ctx), "other routes are not held by the key")
	TEST_ASSERT(keyed.passes(ROUTE_AUTHORITY, ctx), "authority passes every boundary")
	cap_set(F, CAP_BROKEN, TRUE)
	TEST_ASSERT(!keyed.passes(ROUTE_UI, ctx), "the route gate applies to every route")
	cap_set(F, CAP_BROKEN, FALSE)
	ctx.release()

// ---- actions ----

/datum/unit_test/dx_op_actions

/datum/unit_test/dx_op_actions/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/ops/F = allocate(/obj/cap_fixture/ops, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	TEST_ASSERT_EQUAL(bind_profile_of(H).type, /datum/bind_profile/default, "a human uses the default profile")
	TEST_ASSERT_EQUAL(action_def_of(ACT_LOCK).name, "Lock", "action definitions are registered by id")
	TEST_ASSERT(ACT_USE in bind_profile_of(H).actions_for(GESTURE_CLICK), "a click reaches ACT_USE")
	TEST_ASSERT(ACT_DROP_ONTO in bind_profile_of(H).actions_for(GESTURE_DRAG), "a drag reaches ACT_DROP_ONTO")
	TEST_ASSERT(ACT_EXAMINE in bind_profile_of(H).actions_for(GESTURE_SHIFT), "an action's own binds are appended")

	var/list/resolved = resolve_gesture(H, F, GESTURE_CLICK)
	TEST_ASSERT_NOTNULL(resolved, "a click resolves on the fixture")
	TEST_ASSERT_EQUAL(resolved[1], ACT_USE, "to ACT_USE")
	TEST_ASSERT_EQUAL(resolved[2].name, "Press", "and the op that answers it")
	resolved = resolve_gesture(H, F, GESTURE_ALT)
	TEST_ASSERT_EQUAL(resolved[1], ACT_TOGGLE, "alt-click takes the first action in the profile's priority list that has an op")
	TEST_ASSERT_EQUAL(screentip_for(H, F, GESTURE_ALT), "Alt-click: Slow", "the screentip names it")
	TEST_ASSERT_NULL(resolve_gesture(H, F, GESTURE_DRAG), "nothing on the fixture answers a drag")

	TEST_ASSERT_NULL(test_action(H, F, ACT_LOCK), "ACT_LOCK would run")
	cap_set(F, CAP_LOCKED, TRUE)
	TEST_ASSERT_EQUAL(test_action(H, F, ACT_LOCK), "it isn't in the right state for that", "test_action explains a refusal")
	cap_set(F, CAP_LOCKED, FALSE)
	TEST_ASSERT_EQUAL(test_action(H, F, ACT_EJECT, ROUTE_UI), "you can't do that that way", "the bayed op is not offered over the UI route")
	TEST_ASSERT_EQUAL(test_action(H, F, ACT_REPAIR), "there is nothing to repair there", "an action nothing answers")

	var/list/rows = action_options(H, F)
	var/list/by_id = list()
	for(var/list/row as anything in rows)
		by_id[row["id"]] = row
	TEST_ASSERT(by_id[ACT_LOCK] && by_id[ACT_LOCK]["enabled"], "the radial lists lock, enabled")
	TEST_ASSERT(by_id[ACT_EJECT] && !by_id[ACT_EJECT]["enabled"], "eject is listed but disabled (the bay is closed)")
	TEST_ASSERT(by_id[ACT_EJECT]["reason"], "with its reason")
	TEST_ASSERT(!by_id[ACT_REPAIR], "actions nothing answers are not listed")

	GLOB.op_hook_trace.Cut()
	TEST_ASSERT(perform_action(H, F, ACT_LOCK), "perform_action runs the op")
	TEST_ASSERT_EQUAL(length(F.calls), 1, "the handler ran once")
	TEST_ASSERT_EQUAL(jointext(GLOB.op_hook_trace, ","), "before|latch,after|latch", "op_before and op_after fired around the commit")
	TEST_ASSERT_EQUAL(GLOB.op_route_now, ROUTE_PHYSICAL, "the route override is restored")

	// The UI route: act("action", {id}).
	F.calls = null
	var/datum/dispatch_context/ctx = new(H, F)
	TEST_ASSERT(dispatch_succeeded(dispatch_call(ctx, F, "act_action", list("user" = H, "id" = ACT_CLOSE), "action")), "the UI route reaches an op that accepts it")
	TEST_ASSERT_EQUAL(length(F.calls), 1, "and ran its handler")
	TEST_ASSERT(!dispatch_succeeded(dispatch_call(ctx, F, "act_action", list("user" = H, "id" = "nonsense"), "action")), "an unknown id is refused")

	// The command bar.
	F.calls = null
	TEST_ASSERT(command_action(H, "Use", F), "the command bar normalises and runs it")
	TEST_ASSERT(!command_action(H, "no-such-thing", F), "an unknown action is refused")

// ---- the timed wait ----

/datum/unit_test/dx_op_wait

/datum/unit_test/dx_op_wait/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/ops/F = allocate(/obj/cap_fixture/ops, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	GLOB.op_cancelled_log.Cut()

	// A pending op cancels early when a requirement's read is published.
	TEST_ASSERT(perform_action(H, F, ACT_TOGGLE), "the timed op starts")
	TEST_ASSERT(om_timer_slot_pending(H, "op_wait"), "and waits")
	TEST_ASSERT_EQUAL(length(GLOB.op_pending), 1, "one pending context")
	TEST_ASSERT_NULL(F.calls, "nothing ran yet")
	cap_set(F, CAP_LOCKED, TRUE)
	TEST_ASSERT(!om_timer_slot_pending(H, "op_wait"), "the wait is cancelled at once")
	TEST_ASSERT_EQUAL(length(GLOB.op_pending), 0, "the pending set is empty")
	TEST_ASSERT_EQUAL(length(GLOB.op_watchers), 0, "and the watch index too")
	TEST_ASSERT_EQUAL(GLOB.op_cancelled_log[length(GLOB.op_cancelled_log)], "slow|[/datum/msg/req_wrong_state]", "the early cancel is recorded with its reason")
	TEST_ASSERT_NULL(F.calls, "the handler never ran")
	cap_set(F, CAP_LOCKED, FALSE)

	// A change nobody published is still caught by the re-check when the wait ends.
	TEST_ASSERT(perform_action(H, F, ACT_TOGGLE), "starts again")
	var/pending_id = GLOB.op_pending[1]
	F.cap_state |= CAP_LOCKED
	om_cancel_timer_slot(H, "op_wait")
	op_wait_done(pending_id)
	TEST_ASSERT_NULL(F.calls, "the after-wait re-check refuses a stale go-ahead")
	TEST_ASSERT_EQUAL(length(GLOB.op_pending), 0, "the context was released")
	F.cap_state &= ~CAP_LOCKED

	// And a wait that ends with everything holding commits, through op_before / op_after.
	TEST_ASSERT(perform_action(H, F, ACT_TOGGLE), "starts a third time")
	pending_id = GLOB.op_pending[1]
	om_cancel_timer_slot(H, "op_wait")
	GLOB.op_hook_trace.Cut()
	op_wait_done(pending_id)
	TEST_ASSERT_EQUAL(length(F.calls), 1, "the handler ran after the wait")
	TEST_ASSERT_EQUAL(jointext(GLOB.op_hook_trace, ","), "before|slow,after|slow", "with the hooks around it")
