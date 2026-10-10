// The powered capability (code/datums/capabilities/library/powered.dm).

/obj/cap_fixture/powered
	var/has_power = TRUE

/obj/cap_fixture/powered/cap_powered()
	return has_power

/obj/cap_fixture/powered/capabilities()
	. = ..()
	. += cap_power()
	. += cap_hand("Poke", TYPE_PROC_REF(/obj/cap_fixture/powered, poke))

/obj/cap_fixture/powered/proc/poke(mob/user, obj/item/held)
	return TRUE

/obj/machinery/cap_fixture_powered
	name = "powered capability fixture"
	use_power = USE_POWER_OFF

/obj/machinery/cap_fixture_powered/capabilities()
	. = ..()
	. += cap_power()

/// Dark and an examine line while unpowered; entries refuse unless works_unpowered.
/datum/unit_test/dx_cap_powered_dark/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/powered/A = allocate(/obj/cap_fixture/powered, T)
	var/datum/interaction/capability/poke
	for(var/datum/interaction/capability/E as anything in cap_interactions(A))
		if(E.name == "Poke")
			poke = E
	refresh_flush()
	TEST_ASSERT(!cap_test_has_layer(A, "dark"), "not dark while powered")
	TEST_ASSERT(!("It is unpowered." in caps_examine(A, H)), "no unpowered line while powered")
	TEST_ASSERT_NULL(poke.why_not(H, A, null), "entries work while powered")
	A.has_power = FALSE
	changed(A)
	refresh_flush()
	TEST_ASSERT(cap_test_has_layer(A, "dark"), "dark while unpowered")
	TEST_ASSERT("It is unpowered." in caps_examine(A, H), "the unpowered line shows")
	TEST_ASSERT_EQUAL(poke.why_not(H, A, null), "it has no power", "entries refuse while unpowered")

/// power_change() marks the machine changed, so its look follows the power. The machine's power is the area's channel read (a hold here forces it);
/// power_change() acts on the flip the machine has not seen yet.
/datum/unit_test/dx_cap_powered_power_change/Run()
	var/obj/machinery/cap_fixture_powered/M = allocate(/obj/machinery/cap_fixture_powered, run_loc_floor_bottom_left)
	refresh_flush()
	var/was_dark = cap_test_has_layer(M, "dark")
	// Put the machine in the opposite of its real power state.
	M.set_grid_power(M.power_lost())
	TEST_ASSERT(M.power_change(), "power_change() sees the power state flip")
	TEST_ASSERT(M.refresh_queued, "power_change() marks the machine changed")
	refresh_flush()
	TEST_ASSERT_NOTEQUAL(cap_test_has_layer(M, "dark"), was_dark, "the dark layer follows the power")
