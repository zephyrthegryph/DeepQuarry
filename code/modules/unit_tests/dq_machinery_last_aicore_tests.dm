// Behaviour pins for all five AI-core use_tool construction paths.
// Old code is driven through its actual tool dispatcher: its native catch-all intercepts clicks.
// After conversion the same assertions use test_click, proving native click recovery.
// Recorded before replacing the legacy waits; these assertions survive conversion.
/datum/unit_test/dq_machinery_last_aicore
	parent_type = /datum/unit_test/dq_machinery_timed_material_pin
	abstract_type = /datum/unit_test/dq_machinery_last_aicore
	var/core_type = /obj/structure/AIcore
	var/initial_state = 0
	var/initial_anchor = FALSE
	var/final_state = 1
	var/final_anchor = TRUE
	var/duration = 2 SECONDS
	var/dismantling = FALSE
	var/interruption = null

/datum/unit_test/dq_machinery_last_aicore/proc/begin_core_pin(mob/H, obj/structure/AIcore/C, obj/item/T)
	// The old-handler pins passed before conversion. Native ops now recover the intercepted click.
	test_click(H, C, T)
	var/datum/work = running(H)
	TEST_ASSERT_NOTNULL(work, "The real tool click starts timed construction work")
	TEST_ASSERT(isnull(declared_duration(work)) || declared_duration(work) == duration, "The timed work preserves the pinned duration")
	return work
/datum/unit_test/dq_machinery_last_aicore/run_pin()
	var/mob/living/carbon/human/H = person()
	var/turf/floor = get_turf(H)
	var/obj/structure/AIcore/C = allocate(core_type, floor)
	C.set_state(initial_state)
	C.set_anchored(initial_anchor)
	var/obj/item/T
	var/initial_fuel = null
	if(dismantling)
		var/obj/item/weldingtool/W = lit_welder(H)
		T = W
		initial_fuel = W.reagents.get_reagent_amount(REAGENT_ID_FUEL)
	else
		T = allocate(/obj/item/tool/wrench, floor)
		equip(H, T)
	var/list/old_outputs = contents_of(floor, /obj/item/stack/material/plasteel)
	var/datum/work = begin_core_pin(H, C, T)
	TEST_ASSERT_EQUAL(C.state, initial_state, "The real click cannot advance the core immediately")
	TEST_ASSERT_EQUAL(C.anchored, initial_anchor, "The bolts remain unchanged until completion")
	TEST_ASSERT_EQUAL(T.loc, H, "The real tool remains in the operator's custody while waiting")
	if(interruption == "drop")
		TEST_ASSERT(H.drop_from_inventory(T), "The operator drops the exact tool used by the action")
	else if(interruption == "move")
		H.forceMove(get_step(H, EAST))
	test_time(duration - 0.1 SECONDS)
	TEST_ASSERT(!QDELETED(C), "The actual core survives until the complete delay")
	TEST_ASSERT_EQUAL(C.state, initial_state, "An incomplete wait has not advanced construction")
	TEST_ASSERT_EQUAL(C.anchored, initial_anchor, "An incomplete wait has not changed anchoring")
	test_time(0.2 SECONDS)
	var/refund = 0
	for(var/obj/item/stack/material/plasteel/S in contents_of(floor, /obj/item/stack/material/plasteel))
		if(!(S in old_outputs))
			own(S)
			refund += S.get_amount()
	if(interruption)
		TEST_ASSERT(!QDELETED(C), "Interrupted tool work never destroys the core")
		TEST_ASSERT_EQUAL(C.state, initial_state, "Interrupted tool work keeps the initial construction state")
		TEST_ASSERT_EQUAL(C.anchored, initial_anchor, "Interrupted tool work keeps the initial bolts")
		TEST_ASSERT(was_cancelled(work, H), "The interrupted action actually ended without completing")
		TEST_ASSERT_EQUAL(refund, 0, "An interrupted dismantle creates no material refund")
	else if(dismantling)
		TEST_ASSERT(QDELETED(C), "The welder actually destroys the completed dismantled core")
		TEST_ASSERT_EQUAL(refund, 4, "The completed core returns exactly four plasteel sheets")
	else
		TEST_ASSERT(!QDELETED(C), "Bolting preserves the original core identity")
		TEST_ASSERT_EQUAL(C.state, final_state, "The completed construction step advances the real state")
		TEST_ASSERT_EQUAL(C.anchored, final_anchor, "The completed construction step changes the real bolts")
		TEST_ASSERT_EQUAL(refund, 0, "Bolting never manufactures plasteel")
	TEST_ASSERT_NULL(running(H), "Completed or cancelled tool work releases the operator")
	TEST_ASSERT_EQUAL(H.get_active_hand(), interruption == "drop" ? null : T, "The operation preserves the actual surviving tool custody")
	if(dismantling)
		var/obj/item/weldingtool/W = T
		TEST_ASSERT_EQUAL(W.reagents.get_reagent_amount(REAGENT_ID_FUEL), initial_fuel, "The legacy zero-amount dismantle spends no fuel")

/datum/unit_test/dq_machinery_last_aicore/anchor
/datum/unit_test/dq_machinery_last_aicore/anchor/drop
	interruption = "drop"
/datum/unit_test/dq_machinery_last_aicore/anchor/move
	interruption = "move"

/datum/unit_test/dq_machinery_last_aicore/unanchor
	initial_state = 1
	initial_anchor = TRUE
	final_state = 0
	final_anchor = FALSE
/datum/unit_test/dq_machinery_last_aicore/unanchor/drop
	interruption = "drop"
/datum/unit_test/dq_machinery_last_aicore/unanchor/move
	interruption = "move"

/datum/unit_test/dq_machinery_last_aicore/dismantle
	final_state = 0
	final_anchor = FALSE
	dismantling = TRUE
/datum/unit_test/dq_machinery_last_aicore/dismantle/drop
	interruption = "drop"
/datum/unit_test/dq_machinery_last_aicore/dismantle/move
	interruption = "move"

/datum/unit_test/dq_machinery_last_aicore/deactivated_unbolt
	core_type = /obj/structure/AIcore/deactivated
	initial_state = 20
	final_state = 20
	initial_anchor = TRUE
	final_anchor = FALSE
	duration = 4 SECONDS
/datum/unit_test/dq_machinery_last_aicore/deactivated_unbolt/drop
	interruption = "drop"
/datum/unit_test/dq_machinery_last_aicore/deactivated_unbolt/move
	interruption = "move"

/datum/unit_test/dq_machinery_last_aicore/deactivated_bolt
	core_type = /obj/structure/AIcore/deactivated
	initial_state = 20
	final_state = 20
	duration = 4 SECONDS
/datum/unit_test/dq_machinery_last_aicore/deactivated_bolt/drop
	interruption = "drop"
/datum/unit_test/dq_machinery_last_aicore/deactivated_bolt/move
	interruption = "move"


