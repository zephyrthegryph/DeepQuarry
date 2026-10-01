// The breakable capability (code/datums/capabilities/library/breakable.dm).

/obj/cap_fixture/breakable/capabilities()
	. = ..()
	. += cap_breakable(repair_tool = TOOL_WRENCH, repair_delay = 0)
	. += cap_hand("Poke", TYPE_PROC_REF(/obj/cap_fixture/breakable, poke))

/obj/cap_fixture/breakable/proc/poke(mob/user, obj/item/held)
	return TRUE

/obj/cap_fixture/breakable_default/capabilities()
	. = ..()
	. += cap_breakable()

/// atom_break() sets CAP_BROKEN, which refuses other entries, examines and draws; the repair clears it.
/datum/unit_test/dx_cap_breakable_break_and_repair/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/breakable/A = allocate(/obj/cap_fixture/breakable, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	var/datum/interaction/capability/repair = cap_test_entry(A, "breakable:[TOOL_WRENCH]")
	var/datum/interaction/capability/poke
	for(var/datum/interaction/capability/E as anything in cap_interactions(A))
		if(E.name == "Poke")
			poke = E
	TEST_ASSERT_NOTNULL(repair, "a repair entry")
	TEST_ASSERT(H.put_in_active_hand(wrench), "the human holds a wrench")
	TEST_ASSERT_EQUAL(repair.why_not(H, A, wrench), "it isn't broken", "nothing to repair while whole")
	TEST_ASSERT_NULL(poke.why_not(H, A, null), "other entries work while whole")

	A.atom_break()
	TEST_ASSERT(is_broken(A), "atom_break() sets CAP_BROKEN")
	TEST_ASSERT_EQUAL(poke.why_not(H, A, null), "it's broken", "other entries refuse while broken")
	TEST_ASSERT("It is broken." in caps_examine(A, H), "examine says broken")
	refresh_flush()
	TEST_ASSERT(cap_test_has_layer(A, "broken"), "the broken layer is drawn")
	TEST_ASSERT_NULL(repair.why_not(H, A, wrench), "the repair works while broken")
	TEST_ASSERT(repair.perform(H, A, wrench), "the repair runs")
	TEST_ASSERT(!is_broken(A), "the repair clears CAP_BROKEN")
	refresh_flush()
	TEST_ASSERT(!cap_test_has_layer(A, "broken"), "the layer is gone")

	A.atom_break()
	A.atom_fix()
	TEST_ASSERT(!is_broken(A), "atom_fix() clears CAP_BROKEN too")

/// The defaults: a welder over three seconds.
/datum/unit_test/dx_cap_breakable_defaults/Run()
	var/obj/cap_fixture/breakable_default/A = allocate(/obj/cap_fixture/breakable_default, run_loc_floor_bottom_left)
	var/datum/interaction/capability/repair = cap_test_entry(A, "breakable:[TOOL_WELDER]")
	TEST_ASSERT_NOTNULL(repair, "a welder repair entry")
	TEST_ASSERT_EQUAL(repair.tool, TOOL_WELDER, "needs a welder")
	TEST_ASSERT_EQUAL(repair.duration, 3 SECONDS, "takes three seconds")
	TEST_ASSERT(repair.works_broken, "works while broken")
