// The operation context (code/datums/operations/op_ctx.dm): requirement flyweights and the pooled op_ctx with its stage order.

/obj/cap_fixture/ops
	name = "ops fixture"
	req_access = list(ACCESS_ENGINE)
	var/calls_allowed = FALSE

CAPABILITY(/obj/cap_fixture/ops, cap_require(OP_STRUCTURAL, needs = req_set(CAP_PANEL_OPEN)))

/obj/cap_fixture/ops/proc/fx_gate(mob/user, obj/item/held)
	return calls_allowed ? TRUE : "the gears are jammed"

/// An op definition for a context check: a plain op needs a manipulating provider over the physical route.
/proc/dx_op_def(key, by = AFF_MANIPULATE, via = ROUTE_PHYSICAL, needs, kind = OP_CONTROL)
	RETURN_TYPE(/datum/op_def)
	var/datum/op_def/op = new
	op.key = key
	op.name = key
	op.by = by
	op.via = via
	op.kind = kind
	op.needs = req_list(needs)
	return op

// ---- requirements ----

/datum/unit_test/dx_op_reqs

/datum/unit_test/dx_op_reqs/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/ops/F = allocate(/obj/cap_fixture/ops, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/datum/op_ctx/ctx = op_ctx_take(H, F, null, dx_op_def("latch", needs = req_clear(CAP_LOCKED)))

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
	var/datum/op_ctx/first = op_ctx_take(H, F, null, dx_op_def("latch", needs = req_clear(CAP_LOCKED)))
	var/first_id = first.id
	TEST_ASSERT(first.id > 0 && op_ctx_live_count() == live_before + 1, "a taken context is live in the pool's accounting")
	first.release()
	TEST_ASSERT(first.released && isnull(first.actor) && isnull(first.target), "release() resets every field")
	TEST_ASSERT_EQUAL(op_ctx_live_count(), live_before, "and the pool counts it back")
	var/datum/op_ctx/second = op_ctx_take(H, F, null, dx_op_def("latch", needs = req_clear(CAP_LOCKED)))
	TEST_ASSERT(second.id != first_id && !second.released, "the next take has a fresh id, live again")
	second.release()

	// Provider first: no slot gives the affordance, so the route and the needs are never asked.
	var/datum/op_ctx/ctx = op_ctx_take(H, F, null, dx_op_def("impossible", by = (1<<12), via = ROUTE_UI, needs = req_set(CAP_EMAGGED)))
	TEST_ASSERT_EQUAL(ctx.check(), /datum/msg/req_no_provider, "provider is the first stage")
	TEST_ASSERT_EQUAL(ctx.failed_stage, OP_STAGE_PROVIDER, "failed at the provider stage")
	ctx.release()

	// Route second: a UI-only op over the physical route, with its needs also unmet.
	ctx = op_ctx_take(H, F, null, dx_op_def("remote", via = ROUTE_UI, needs = req_set(CAP_EMAGGED)))
	TEST_ASSERT_EQUAL(ctx.check(), /datum/msg/req_no_route, "route comes before the op's needs")
	TEST_ASSERT_EQUAL(ctx.failed_stage, OP_STAGE_ROUTE, "failed at the route stage")
	ctx.release()

	// Over the UI route the needs stage is reached (last).
	ctx = op_ctx_take(H, F, null, dx_op_def("remote", via = ROUTE_UI, needs = req_set(CAP_EMAGGED)), ROUTE_UI)
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
	ctx = op_ctx_take(H, F, null, dx_op_def("press", via = ROUTE_PHYSICAL | ROUTE_VERB))
	TEST_ASSERT_EQUAL(ctx.check(), /datum/msg/req_not_capable, "an unconscious actor can't")
	TEST_ASSERT_EQUAL(ctx.failed_stage, OP_STAGE_ACTOR, "at the actor stage")
	ctx.release()
	H.set_stat(CONSCIOUS)

	// Capability contract fifth: cap_require(OP_STRUCTURAL) covers the structural op only.
	ctx = op_ctx_take(H, F, null, dx_op_def("rip", kind = OP_STRUCTURAL))
	TEST_ASSERT_EQUAL(ctx.check(), /datum/msg/req_wrong_state, "the structural contract applies")
	TEST_ASSERT_EQUAL(ctx.failed_stage, OP_STAGE_CAPS, "at the capability stage")
	cap_set(F, CAP_PANEL_OPEN, TRUE)
	TEST_ASSERT_NULL(ctx.check(), "with the panel open it passes")
	ctx.release()
	ctx = op_ctx_take(H, F, null, dx_op_def("press", via = ROUTE_PHYSICAL | ROUTE_VERB))
	cap_set(F, CAP_PANEL_OPEN, FALSE)
	TEST_ASSERT_NULL(ctx.check(), "the contract does not touch other kinds")
	ctx.release()

	// A released context is poisoned in test builds: touching it is a bug.
	TEST_ASSERT_EQUAL(first.pool_state, POOL_STATE_POISONED, "a released context is poisoned, never handed out again")
	TEST_ASSERT_EQUAL(op_ctx_live_count(), live_before, "no context leaked by this test")
