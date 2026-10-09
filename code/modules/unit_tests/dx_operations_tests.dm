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
	. += legacy_compartment(BAY_INTERIOR, door = CAP_PANEL_OPEN, heat = 0.25, gas = FALSE)

/obj/cap_fixture/ops/reactions()
	. = ..()
	. += before_op("latch", PROC_REF(fx_before))
	. += after_op("latch", PROC_REF(fx_after))
	. += before_op("slow", PROC_REF(fx_before))
	. += after_op("slow", PROC_REF(fx_after))

/// Records the hook order; refuses with `veto` (a reason) when it is set.
/obj/cap_fixture/ops/proc/fx_before(datum/op_ctx/ctx)
	LAZYADD(hook_log, "before|[ctx.op.key]|[ctx.actor == null ? "noactor" : "actor"]")
	return veto

/obj/cap_fixture/ops/proc/fx_after(datum/op_ctx/ctx)
	LAZYADD(hook_log, "after|[ctx.op.key]")

/obj/cap_fixture/ops/proc/fx_op(mob/user)
	LAZYADD(calls, "op")
	return !handler_refuses

/obj/cap_fixture/ops/proc/fx_gate(mob/user, obj/item/held)
	return calls_allowed ? TRUE : "the gears are jammed"

/obj/cap_fixture/ops
	var/calls_allowed = FALSE
	/// Set to make the op handlers refuse (a falsy return), to prove after_op waits for a commit.
	var/handler_refuses = FALSE
	/// What the before_op / after_op reactions saw, in order.
	var/list/hook_log
	/// A refusal reason (a /datum/msg type or text) the before_op reaction answers with.
	var/veto

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
	TEST_ASSERT(legacy_all_of(req_set(CAP_PANEL_OPEN), req_clear(CAP_LOCKED)) == legacy_all_of(req_set(CAP_PANEL_OPEN), req_clear(CAP_LOCKED)), "composites intern too")

	TEST_ASSERT_NULL(req_clear(CAP_LOCKED).test(ctx), "not locked: holds")
	TEST_ASSERT_EQUAL(req_set(CAP_LOCKED).test(ctx), /datum/msg/req_wrong_state, "not locked: req_set fails with the state reason")
	cap_set(F, CAP_LOCKED, TRUE)
	TEST_ASSERT_NULL(req_set(CAP_LOCKED).test(ctx), "locked: req_set holds")
	TEST_ASSERT_EQUAL(req_clear(CAP_LOCKED).test(ctx), /datum/msg/req_wrong_state, "locked: req_clear fails")
	var/list/reads = req_clear(CAP_LOCKED).reads(ctx)
	TEST_ASSERT_EQUAL(length(reads), 1, "req_clear reads one thing")
	TEST_ASSERT_EQUAL(reads[1][1], F, "it reads the target")
	TEST_ASSERT_EQUAL(reads[1][2], OP_KEY_CAP_STATE, "its cap_state")

	TEST_ASSERT_NULL(legacy_any_of(req_set(CAP_LOCKED), req_set(CAP_EMAGGED)).test(ctx), "any_of: one part holds")
	TEST_ASSERT_EQUAL(legacy_any_of(req_set(CAP_EMAGGED), req_set(CAP_BROKEN)).test(ctx), /datum/msg/req_wrong_state, "any_of: none holds, the first reason")
	TEST_ASSERT_EQUAL(legacy_all_of(req_set(CAP_LOCKED), req_set(CAP_EMAGGED)).test(ctx), /datum/msg/req_wrong_state, "all_of: one fails")
	TEST_ASSERT_EQUAL(none_of(req_set(CAP_LOCKED)).test(ctx), /datum/msg/req_forbidden, "none_of: a part holds")
	TEST_ASSERT_NULL(none_of(req_set(CAP_EMAGGED)).test(ctx), "none_of: no part holds")

	TEST_ASSERT_EQUAL(req_access().test(ctx), /datum/msg/req_no_access, "no access to an access-locked fixture")
	ctx.route = ROUTE_AUTHORITY
	TEST_ASSERT_NULL(req_access().test(ctx), "authority route passes the access requirement")
	ctx.route = ROUTE_PHYSICAL

	TEST_ASSERT_EQUAL(legacy_req(/obj/item/pen).test(ctx), /datum/msg/req_wrong_item, "no held item: not a pen")
	ctx.held = allocate(/obj/item/pen, T)
	TEST_ASSERT_NULL(legacy_req(/obj/item/pen).test(ctx), "holding a pen")
	TEST_ASSERT_NULL(legacy_req(list(/obj/item/paper, /obj/item/pen)).test(ctx), "a list of types")
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

	var/live_before = op_ctx_live_count()
	var/datum/op_ctx/first = op_ctx_take(H, F, null, dx_op_of(F, "latch"))
	var/first_id = first.id
	TEST_ASSERT(first.id > 0 && op_ctx_live_count() == live_before + 1, "a taken context is live in the pool's accounting")
	first.release()
	TEST_ASSERT(first.released && isnull(first.actor) && isnull(first.target), "release() resets every field")
	TEST_ASSERT_EQUAL(op_ctx_live_count(), live_before, "and the pool counts it back")
	var/datum/op_ctx/second = op_ctx_take(H, F, null, dx_op_of(F, "latch"))
	TEST_ASSERT(second.id != first_id && !second.released, "the next take has a fresh id, live again")
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
	H.set_stat(UNCONSCIOUS)
	ctx = op_ctx_take(H, F, null, dx_op_of(F, "press"))
	TEST_ASSERT_EQUAL(ctx.check(), /datum/msg/req_not_capable, "an unconscious actor can't")
	TEST_ASSERT_EQUAL(ctx.failed_stage, OP_STAGE_ACTOR, "at the actor stage")
	ctx.release()
	H.set_stat(CONSCIOUS)

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

	// A released context is poisoned in test builds: touching it is a bug.
	TEST_ASSERT_EQUAL(first.pool_state, POOL_STATE_POISONED, "a released context is poisoned, never handed out again")
	TEST_ASSERT_EQUAL(op_ctx_live_count(), live_before, "no context leaked by this test")

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
	var/datum/capability/compartment/keyed = legacy_compartment(BAY_CARGO, door = CAP_KEY, route_gate = req_clear(CAP_BROKEN))
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

/// A holder whose one internal slot sits in a bay with a leaky boundary, and the same holder with no bay.
/obj/item/dx_bay_holder
	name = "bay holder"
	w_class = ITEMSIZE_NORMAL
	max_integrity = 10000

/obj/item/dx_bay_holder/capabilities()
	. = ..()
	. += legacy_compartment(BAY_INTERIOR, heat = 0.25, radiation = 0.5, gas = FALSE)

/datum/om/relation/slot/dx_bay_holder_slot
	holder = /obj/item/dx_bay_holder
	slot_id = "bay"
	exposure = SLOT_EXPOSURE_INTERNAL
	at = BAY_INTERIOR

/obj/item/dx_plain_holder
	name = "plain holder"
	w_class = ITEMSIZE_NORMAL
	max_integrity = 10000

/datum/om/relation/slot/dx_bay_holder_plain_slot
	holder = /obj/item/dx_plain_holder
	slot_id = "bay"
	exposure = SLOT_EXPOSURE_INTERNAL

/// A compartment's transmission() scales the path share of a slot that names its bay (containment/paths.dm).
/datum/unit_test/dx_op_bay_paths

/datum/unit_test/dx_op_bay_paths/Run()
	var/turf/T = test_floor()
	var/obj/item/dx_bay_holder/bayed = allocate(/obj/item/dx_bay_holder, T)
	var/obj/item/dx_plain_holder/plain = allocate(/obj/item/dx_plain_holder, T)
	var/obj/item/dq_path_probe/in_bay = allocate(/obj/item/dq_path_probe, T)
	var/obj/item/dq_path_probe/in_plain = allocate(/obj/item/dq_path_probe, T)
	TEST_ASSERT(move_into(bayed, null, in_bay), "the probe goes into the bayed holder")
	TEST_ASSERT(move_into(plain, null, in_plain), "and the other into the plain one")
	var/heat_plain = dq_path_step(plain, in_plain, PATH_EFFECT_HEAT)
	var/rad_plain = dq_path_step(plain, in_plain, PATH_EFFECT_RADIATION)
	TEST_ASSERT(heat_plain > 0 && rad_plain > 0, "the plain slot lets heat and radiation through")
	TEST_ASSERT(abs(dq_path_step(bayed, in_bay, PATH_EFFECT_HEAT) - heat_plain * 0.25) < 0.001, "heat crosses the bay at its declared 0.25 of the slot's share")
	TEST_ASSERT(abs(dq_path_step(bayed, in_bay, PATH_EFFECT_RADIATION) - rad_plain * 0.5) < 0.001, "radiation at 0.5")
	TEST_ASSERT_EQUAL(dq_path_step(plain, in_plain, PATH_EFFECT_GAS), 1, "gas reaches the plain slot")
	TEST_ASSERT_EQUAL(dq_path_step(bayed, in_bay, PATH_EFFECT_GAS), 0, "the bay's boundary stops gas")

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
	var/datum/op_def/answered = resolved[2]
	TEST_ASSERT_EQUAL(answered.name, "Press", "and the op that answers it")
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

	// The radial names ops by key (two ops of one action are two rows), with the action each answers.
	var/list/rows = action_options(H, F)
	var/list/by_id = list()
	for(var/list/row as anything in rows)
		by_id[row["id"]] = row
	TEST_ASSERT(by_id["latch"] && by_id["latch"]["enabled"], "the radial lists the latch op, enabled")
	TEST_ASSERT_EQUAL(by_id["latch"]?["action"], ACT_LOCK, "with the action it answers")
	TEST_ASSERT(by_id["bayed"] && !by_id["bayed"]["enabled"], "the bayed op is listed but disabled (the bay is closed)")
	TEST_ASSERT(by_id["bayed"]["reason"], "with its reason")
	TEST_ASSERT(!by_id[ACT_REPAIR], "rows are ops, not actions")
	// The target's old operation declarations remain visible beside a modern actor's ops;
	// legacy hand/tool presets must not duplicate a converted target's actual engine entries.
	var/obj/machinery/door/airlock/converted = allocate(/obj/machinery/door/airlock, T)
	var/list/old_shapes = list()
	for(var/list/row as anything in input_compatibility().compatibility_menu(H, converted, ROUTE_PHYSICAL))
		old_shapes[row["id"]] = TRUE
	var/list/named_operations = list()
	for(var/list/row as anything in input_compatibility().compatibility_menu(H, converted, ROUTE_PHYSICAL, operations_only = TRUE))
		named_operations[row["id"]] = TRUE
	TEST_ASSERT_EQUAL(length(named_operations), 0, "The fully converted airlock exposes no legacy named operations")
	for(var/list/row as anything in op_menu(H, converted, null))
		TEST_ASSERT(!(old_shapes[row["id"]] && !named_operations[row["id"]] && !op_index_of_table(table_of(converted)).by_key[row["id"]] && !op_index_of_table(table_of(H)).by_key[row["id"]]), "A converted target's legacy-shaped [row["id"]] row was reintroduced beside its native operations")


	F.hook_log = null
	TEST_ASSERT(perform_action(H, F, ACT_LOCK), "perform_action runs the op")
	TEST_ASSERT_EQUAL(length(F.calls), 1, "the handler ran once")
	TEST_ASSERT_EQUAL(jointext(F.hook_log, ","), "before|latch|actor,after|latch", "the before_op and after_op reactions fired around the commit")
	// A before_op reaction that answers with a reason stops the commit and the actor is told.
	F.calls = null
	F.hook_log = null
	var/live_then = op_ctx_live_count()
	F.veto = "the latch is jammed by a reaction"
	perform_action(H, F, ACT_LOCK)
	TEST_ASSERT_NULL(F.calls, "the handler never ran")
	TEST_ASSERT_EQUAL(jointext(F.hook_log, ","), "before|latch|actor", "after_op did not fire for a stopped op")
	TEST_ASSERT_EQUAL(op_ctx_live_count(), live_then, "the context was released")
	F.veto = /datum/msg/req_sealed
	perform_action(H, F, ACT_LOCK)
	TEST_ASSERT_NULL(F.calls, "a /datum/msg reason vetoes too")
	F.veto = null
	F.calls = null
	F.hook_log = null
	TEST_ASSERT(perform_action(H, F, ACT_LOCK), "and it runs again once the reaction lets go")
	// after_op fires only for a commit: a handler that refuses does not count.
	F.calls = null
	F.hook_log = null
	F.handler_refuses = TRUE
	perform_action(H, F, ACT_LOCK)
	TEST_ASSERT_EQUAL(length(F.calls), 1, "the handler ran")
	TEST_ASSERT_EQUAL(jointext(F.hook_log, ","), "before|latch|actor", "but a refused handler is not a commit: no after_op")
	F.handler_refuses = FALSE
	TEST_ASSERT_EQUAL(GLOB.op_route_now, ROUTE_PHYSICAL, "the route override is restored")

	// The UI route: act("action", {id}) is a UI action of the capability layer, reached through tgui_act.
	F.calls = null
	var/datum/tgui/ui = ui_test_window(F)
	ui.user = H
	TEST_ASSERT(F.tgui_act("action", list("id" = ACT_CLOSE), ui), "the UI route reaches an op that accepts it")
	TEST_ASSERT_EQUAL(length(F.calls), 1, "and ran its handler")
	TEST_ASSERT(!F.tgui_act("action", list("id" = "nonsense"), ui), "an unknown id is refused")
	TEST_ASSERT(!F.tgui_act("action", list("id" = ACT_PRY), ui), "an action whose op refuses the UI route is refused")
	TEST_ASSERT(!hascall(F, "act_action"), "no atom carries act_action: it lives on the capability")
	TEST_ASSERT(!hascall(H, "act_action"), "not even a mob")

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
	TEST_ASSERT(after_pending(H, "op_wait"), "and waits")
	TEST_ASSERT_EQUAL(length(GLOB.op_pending), 1, "one pending context")
	TEST_ASSERT_NULL(F.calls, "nothing ran yet")
	cap_set(F, CAP_LOCKED, TRUE)
	TEST_ASSERT(!after_pending(H, "op_wait"), "the wait is cancelled at once")
	TEST_ASSERT_EQUAL(length(GLOB.op_pending), 0, "the pending set is empty")
	TEST_ASSERT_EQUAL(length(GLOB.op_watchers), 0, "and the watch index too")
	TEST_ASSERT_EQUAL(GLOB.op_cancelled_log[length(GLOB.op_cancelled_log)], "slow|[/datum/msg/req_wrong_state]", "the early cancel is recorded with its reason")
	TEST_ASSERT_NULL(F.calls, "the handler never ran")
	cap_set(F, CAP_LOCKED, FALSE)

	// A change nobody published is still caught by the re-check when the wait ends.
	TEST_ASSERT(perform_action(H, F, ACT_TOGGLE), "starts again")
	var/pending_id = GLOB.op_pending[1]
	capability_runtime(F).bits |= CAP_LOCKED
	cancel_after(H, "op_wait")
	op_wait_done(pending_id)
	TEST_ASSERT_NULL(F.calls, "the after-wait re-check refuses a stale go-ahead")
	TEST_ASSERT_EQUAL(length(GLOB.op_pending), 0, "the context was released")
	capability_runtime(F).bits &= ~CAP_LOCKED

	// And a wait that ends with everything holding commits, through op_before / op_after.
	TEST_ASSERT(perform_action(H, F, ACT_TOGGLE), "starts a third time")
	pending_id = GLOB.op_pending[1]
	cancel_after(H, "op_wait")
	F.hook_log = null
	op_wait_done(pending_id)
	TEST_ASSERT_EQUAL(length(F.calls), 1, "the handler ran after the wait")
	TEST_ASSERT_EQUAL(jointext(F.hook_log, ","), "before|slow|actor,after|slow", "with the hooks around it")

// ---- pending operations: early cancel through publish_change, and teardown ----

/// The ops fixture plus a timed op that refuses while `gauge` is at 10 or more; `gauge` is a TRACKED var.
/obj/cap_fixture/ops/gauged
	name = "gauged fixture"
	var/gauge = 0
	var/unwatched = 0

TRACKED(/obj/cap_fixture/ops/gauged, gauge)
TRACKED(/obj/cap_fixture/ops/gauged, unwatched)

/obj/cap_fixture/ops/gauged/capabilities()
	. = ..()
	. += cap_op("Gauged", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), action = ACT_UNLOCK, delay = 3 SECONDS, needs = req_proc(TYPE_PROC_REF(/obj/cap_fixture/ops/gauged, fx_gauge_ok), list(nameof(/obj/cap_fixture/ops/gauged::gauge))), key = "gauged")

/obj/cap_fixture/ops/gauged/proc/fx_gauge_ok(mob/user, obj/item/held)
	return gauge < 10 ? TRUE : "the gauge reads too high"

/datum/unit_test/dx_op_publish_cancel

/datum/unit_test/dx_op_publish_cancel/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/ops/gauged/G = allocate(/obj/cap_fixture/ops/gauged, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/key = nameof(/obj/cap_fixture/ops/gauged::gauge)
	GLOB.op_cancelled_log.Cut()

	TEST_ASSERT(!READERS(G, key), "nothing reads the gauge before an operation waits on it")
	G.set_gauge(3)
	TEST_ASSERT(!G.rx?.observed, "an unread write registers nothing")
	TEST_ASSERT_EQUAL(length(GLOB.op_cancelled_log), 0, "and cancels nothing")

	TEST_ASSERT(perform_action(H, G, ACT_UNLOCK), "the gauged op starts")
	TEST_ASSERT(after_pending(H, "op_wait"), "and waits")
	TEST_ASSERT(READERS(G, key), "a pending op watching a TRACKED var counts as a reader of it")
	TEST_ASSERT_EQUAL(length(GLOB.op_watchers), 1, "and is in the watch index")
	G.set_unwatched(7)
	TEST_ASSERT(after_pending(H, "op_wait"), "a var it does not read leaves the wait alone")
	G.set_gauge(4)
	TEST_ASSERT(after_pending(H, "op_wait"), "a read that changed but still holds leaves the wait alone")
	G.set_gauge(50)
	TEST_ASSERT(!after_pending(H, "op_wait"), "a watched var that breaks the requirement cancels the wait at once")
	TEST_ASSERT_EQUAL(GLOB.op_cancelled_log[length(GLOB.op_cancelled_log)], "gauged|[/datum/msg/req_refused]", "recorded with its reason")
	TEST_ASSERT(!READERS(G, key), "the reader count went back to zero with the wait")
	TEST_ASSERT_EQUAL(length(GLOB.op_pending) + length(GLOB.op_watchers), 0, "nothing pending or watched is left")
	TEST_ASSERT_NULL(G.calls, "the handler never ran")
	G.set_gauge(0)
	TEST_ASSERT_EQUAL(length(GLOB.op_cancelled_log), 1, "and with nothing watching, a write cancels nothing")

/datum/unit_test/dx_op_teardown

/datum/unit_test/dx_op_teardown/Run()
	var/turf/T = test_floor()
	var/live0 = op_ctx_live_count()

	// The target is deleted while the op waits.
	var/obj/cap_fixture/ops/gauged/G = allocate(/obj/cap_fixture/ops/gauged, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(perform_action(H, G, ACT_UNLOCK), "the op starts")
	TEST_ASSERT_EQUAL(length(GLOB.op_pending), 1, "one waits")
	qdel(G)
	TEST_ASSERT_EQUAL(length(GLOB.op_pending), 0, "deleting the target cancels it")
	TEST_ASSERT_EQUAL(length(GLOB.op_watchers), 0, "and clears the watch index")
	TEST_ASSERT(!after_pending(H, "op_wait"), "and the actor's wait timer")
	TEST_ASSERT_EQUAL(op_ctx_live_count(), live0, "and the context went back to the pool")
	TEST_ASSERT_NULL(H.rx?.pending_ops, "the actor forgot it")

	// The actor is deleted while the op waits.
	var/obj/cap_fixture/ops/gauged/G2 = allocate(/obj/cap_fixture/ops/gauged, T)
	var/mob/living/carbon/human/H2 = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(perform_action(H2, G2, ACT_UNLOCK), "an op starts for another actor")
	TEST_ASSERT_EQUAL(length(GLOB.op_pending), 1, "one waits")
	qdel(H2)
	TEST_ASSERT_EQUAL(length(GLOB.op_pending), 0, "deleting the actor cancels it")
	TEST_ASSERT_EQUAL(length(GLOB.op_watchers), 0, "and clears the watch index")
	TEST_ASSERT_EQUAL(op_ctx_live_count(), live0, "the context went back to the pool")
	TEST_ASSERT_NULL(G2.rx?.pending_ops, "and the target forgot it")
	TEST_ASSERT_NULL(G2.calls, "the handler never ran")

// ---- the input router: gesture -> actions -> op, the resolver only for what no op answers ----

/// A probe with cap_op()s for the click, alt and drag gestures.
/obj/dq_interaction_probe/routed
	name = "routed probe"
	var/list/routed

/obj/dq_interaction_probe/routed/capabilities()
	. = ..()
	. += cap_op("Route press", TYPE_PROC_REF(/obj/dq_interaction_probe/routed, route_press), action = ACT_USE, needs = req_clear(CAP_LOCKED), key = "route_press")
	. += cap_op("Route toggle", TYPE_PROC_REF(/obj/dq_interaction_probe/routed, route_press), action = ACT_TOGGLE, key = "route_toggle")
	. += cap_op("Route put", TYPE_PROC_REF(/obj/dq_interaction_probe/routed, route_put), using = /obj/item/pen, action = ACT_DROP_ONTO, key = "route_put")

/obj/dq_interaction_probe/routed/proc/route_press(mob/user)
	LAZYADD(routed, "press")
	return TRUE

/obj/dq_interaction_probe/routed/proc/route_put(mob/user, obj/item/held)
	LAZYADD(routed, "put:[held.type]")
	return TRUE

/datum/unit_test/dx_op_input_router

/datum/unit_test/dx_op_input_router/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/dq_interaction_probe/routed/R = allocate(/obj/dq_interaction_probe/routed, T)

	// A plain click on a target with a cap_op runs the op.
	TEST_ASSERT_NOTNULL(gesture_entry_for(H, R, null, GESTURE_CLICK), "a click reaches the op")
	TEST_ASSERT_EQUAL(try_interaction(H, R, null, INPUT_ACTION_USE, null, TRUE), INTERACTION_TRY_RAN, "the click ran")
	TEST_ASSERT_EQUAL(jointext(R.routed, ","), "press", "through the op")

	// Alt-click is ACT_TOGGLE in the default profile.
	R.routed = null
	TEST_ASSERT_EQUAL(try_interaction(H, R, null, INPUT_ACTION_ALTERNATE), INTERACTION_TRY_RAN, "alt-click ran an op")
	TEST_ASSERT_EQUAL(jointext(R.routed, ","), "press", "the toggle op")

	// An op that would be refused now still takes the click: its refusal is what the player sees.
	R.routed = null
	cap_set(R, CAP_LOCKED, TRUE)
	TEST_ASSERT_NOTNULL(gesture_entry_for(H, R, null, GESTURE_CLICK), "a locked press op still takes the click")
	TEST_ASSERT_EQUAL(try_interaction(H, R, null, INPUT_ACTION_USE, null, TRUE), INTERACTION_TRY_BLOCKED, "the op's refusal answers")
	TEST_ASSERT(!length(R.routed), "the op did not run")
	cap_set(R, CAP_LOCKED, FALSE)

	// The tool-quality narrowing of the tool_act path applies: a crowbar click is not the pen-using drag op's.
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT_NULL(gesture_entry_for(H, R, pen, GESTURE_DRAG, TOOL_CROWBAR), "another tool quality refuses the op")
	// A drag onto the target reaches ACT_DROP_ONTO with the dragged item as what is put there.
	R.routed = null
	var/datum/input_adapter/adapter = H.input_adapter()
	adapter.drag(H, pen, R, null, null, null, null, "")
	TEST_ASSERT_EQUAL(jointext(R.routed, ","), "put:/obj/item/pen", "a drag ran the drop-onto op with the dragged item")

	// A fixture with no op is untouched by the router.
	var/obj/dq_interaction_probe/bare = allocate(/obj/dq_interaction_probe, T)
	TEST_ASSERT_NULL(gesture_entry_for(H, bare, null, GESTURE_CLICK), "no op on it: the router has nothing")

// ---- offered, EMPTY_HAND and the structural defaults ----

/// An op meant only with an empty hand while the fixture says so, and two structural ops.
/obj/cap_fixture/ops/offered
	name = "offered fixture"
	/// What the op's offered req_proc answers.
	var/offer = TRUE

/obj/cap_fixture/ops/offered/capabilities()
	. = ..()
	. += cap_op("Hands only", TYPE_PROC_REF(/obj/cap_fixture/ops, fx_op), using = EMPTY_HAND, offered = req_proc(PROC_REF(fx_offer)), action = ACT_USE, key = "hands")

/obj/cap_fixture/ops/offered/proc/fx_offer(mob/user, obj/item/held)
	return offer

/// `using = EMPTY_HAND` and `offered =` decide whether an op is meant at all: the input falls through, no refusal.
/datum/unit_test/dx_op_offered

/datum/unit_test/dx_op_offered/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/ops/offered/F = allocate(/obj/cap_fixture/ops/offered, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	var/datum/capability/entry/C = cap_of(F, "op:hands")
	var/datum/op_def/op = cap_op_of(C)
	TEST_ASSERT_EQUAL(length(op.offered), 2, "the empty hand and the proc")
	TEST_ASSERT(EMPTY_HAND == req_empty_hand(), "the empty hand is one flyweight")
	TEST_ASSERT(C.entry.is_meant(H, F, null), "an empty hand, and the holder offers it: meant")
	TEST_ASSERT(!C.entry.is_meant(H, F, pen), "a held item is not the empty hand: not meant")
	F.offer = FALSE
	TEST_ASSERT(!C.entry.is_meant(H, F, null), "the holder does not offer it: not meant")
	var/datum/op_ctx/ctx = op_ctx_take(H, F, pen, op)
	TEST_ASSERT_EQUAL(req_empty_hand().test(ctx), /datum/msg/req_hand_full, "a held item fails the requirement at commit")
	ctx.release()
	TEST_ASSERT_NOTNULL(C.entry.offered_reason(H, F, null), "offered_reason() names why it is not meant: no refusal, the input falls through")

/// A structural op works broken and unpowered without saying so; a control does not.
/datum/unit_test/dx_op_structural_defaults

/datum/unit_test/dx_op_structural_defaults/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/ops/F = allocate(/obj/cap_fixture/ops, T)
	var/datum/capability/entry/structural = cap_of(F, "op:rip")
	var/datum/capability/entry/control = cap_of(F, "op:press")
	TEST_ASSERT(structural.entry.works_unpowered && structural.entry.works_broken, "a structural op needs neither power nor a whole holder")
	TEST_ASSERT(!control.entry.works_unpowered && !control.entry.works_broken, "a control op needs both")
