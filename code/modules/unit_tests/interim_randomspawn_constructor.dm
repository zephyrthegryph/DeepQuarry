/// Data-only fixture configurations exercise the actual production constructor and movement, without overriding effects.
/obj/effect/step_trigger/teleporter/randomspawn/interim_always_removed
	destroyprob = 100

/obj/effect/step_trigger/teleporter/randomspawn/interim_retained
	destroyprob = 0
	teleprob = 100

/datum/unit_test/interim_randomspawn_constructor/Run()
	var/turf/T = test_floor()
	var/list/before = turf_contents_of_type(T, /obj/effect/step_trigger/teleporter/randomspawn)
	var/obj/effect/step_trigger/teleporter/randomspawn/removed = allocate(/obj/effect/step_trigger/teleporter/randomspawn/interim_always_removed, T)
	TEST_ASSERT(QDELETED(removed), "The configured certain-removal roll terminates the actual constructor")
	TEST_ASSERT_EQUAL(length(turf_contents_of_type(T, /obj/effect/step_trigger/teleporter/randomspawn)), length(before), "The actual removed constructor leaves no trigger on its original floor")
	var/obj/effect/step_trigger/teleporter/randomspawn/retained = allocate(/obj/effect/step_trigger/teleporter/randomspawn/interim_retained, T)
	TEST_ASSERT(retained && !QDELETED(retained), "The configured zero-removal constructor creates the real trigger")
	TEST_ASSERT(retained.flags & ATOM_INITIALIZED, "The actual surviving constructor preserves its initialized parent chain")
	TEST_ASSERT_EQUAL(retained.loc, T, "The actual surviving trigger remains on its original floor")
	TEST_ASSERT_EQUAL(length(turf_contents_of_type(T, /obj/effect/step_trigger/teleporter/randomspawn)), length(before) + 1, "Only the exact surviving trigger is added to the original floor")
	TEST_ASSERT_EQUAL(retained.destroyprob, 0, "The actual survivor preserves its original removal configuration")
	TEST_ASSERT_EQUAL(retained.teleprob, 100, "The actual survivor preserves its original teleport configuration")
	var/turf/destination = get_step(T, EAST)
	TEST_ASSERT(destination && !destination.density, "The configured real destination is an adjacent passable floor")
	retained.teleport_x = destination.x
	retained.teleport_y = destination.y
	retained.teleport_z = destination.z
	var/obj/item/pen/traveller = allocate(/obj/item/pen, T)
	retained.Trigger(traveller)
	TEST_ASSERT_EQUAL(traveller.loc, destination, "The actual surviving trigger teleports the original real item to its configured floor")
	TEST_ASSERT(!QDELETED(traveller) && !QDELETED(retained), "Actual teleporting preserves both the original traveller and survivor identities")
	TEST_ASSERT_EQUAL(retained.loc, T, "Actual teleporting preserves the original trigger floor")
