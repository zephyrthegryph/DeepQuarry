// The requirement context (code/datums/operations/op_ctx.dm): requirement flyweights and the pooled op_ctx.

/obj/cap_fixture/ops
	name = "ops fixture"
	req_access = list(ACCESS_ENGINE)
	var/calls_allowed = FALSE

/obj/cap_fixture/ops/proc/fx_gate(mob/user, obj/item/held)
	return calls_allowed ? TRUE : "the gears are jammed"

// ---- requirements ----

/datum/unit_test/dx_op_reqs

/datum/unit_test/dx_op_reqs/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/ops/F = allocate(/obj/cap_fixture/ops, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/datum/op_ctx/ctx = op_ctx_take(H, F, null)

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

// ---- the pooled context ----

/datum/unit_test/dx_op_ctx

/datum/unit_test/dx_op_ctx/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/ops/F = allocate(/obj/cap_fixture/ops, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	var/live_before = op_ctx_live_count()
	var/datum/op_ctx/first = op_ctx_take(H, F, null)
	var/first_id = first.id
	TEST_ASSERT(first.id > 0 && op_ctx_live_count() == live_before + 1, "a taken context is live in the pool's accounting")
	first.release()
	TEST_ASSERT(first.released && isnull(first.actor) && isnull(first.target), "release() resets every field")
	TEST_ASSERT_EQUAL(op_ctx_live_count(), live_before, "and the pool counts it back")
	var/datum/op_ctx/second = op_ctx_take(H, F, null)
	TEST_ASSERT(second.id != first_id && !second.released, "the next take has a fresh id, live again")
	second.release()

	// A released context is poisoned in test builds: touching it is a bug.
	TEST_ASSERT_EQUAL(first.pool_state, POOL_STATE_POISONED, "a released context is poisoned, never handed out again")
	TEST_ASSERT_EQUAL(op_ctx_live_count(), live_before, "no context leaked by this test")
