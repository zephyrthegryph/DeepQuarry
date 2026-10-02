/// Keep the actual machinery shock guard while recording its supplied actor.
/obj/machinery/power/apc/dx_test/interim_wire_actor_probe
	var/shock_actor_ref
	var/shock_count = 0
	var/shock_chance

/obj/machinery/power/apc/dx_test/interim_wire_actor_probe/shock(mob/user, prb)
	shock_actor_ref = user ? REF(user) : null
	shock_count++
	shock_chance = prb
	return ..()

/datum/unit_test/interim_apc_wire_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/dx_test/interim_wire_actor_probe/apc = allocate(/obj/machinery/power/apc/dx_test/interim_wire_actor_probe, T)
	apc.stat_add(BROKEN)
	TEST_ASSERT(!apc.operable(), "the fixture's real machinery shock guard refuses electrical effects")
	var/datum/wires/apc/wires = wires_of(apc)
	TEST_ASSERT(istype(wires), "the real APC initializes its maintenance-panel wire controller")
	TEST_ASSERT(!apc.shorted, "the APC begins without a power short")
	wires.cut(WIRE_MAIN_POWER1, user)
	TEST_ASSERT(wires.is_cut(WIRE_MAIN_POWER1), "cutting marks the first power wire cut")
	TEST_ASSERT(apc.shorted, "cutting the first power wire shorts the actual APC")
	TEST_ASSERT_EQUAL(apc.shock_count, 1, "the first cut attempts one shock")
	TEST_ASSERT_EQUAL(apc.shock_actor_ref, REF(user), "the cut forwards its actual actor")
	TEST_ASSERT_EQUAL(apc.shock_chance, 50, "actor plumbing preserves the original shock probability")
	wires.cut(WIRE_MAIN_POWER2, user)
	TEST_ASSERT(wires.is_cut(WIRE_MAIN_POWER2), "cutting marks the second power wire cut")
	TEST_ASSERT_EQUAL(apc.shock_count, 2, "the second cut attempts another shock")
	wires.cut(WIRE_MAIN_POWER1, user)
	TEST_ASSERT(!wires.is_cut(WIRE_MAIN_POWER1), "the first wire can be mended")
	TEST_ASSERT(apc.shorted, "mending one wire leaves the other wire's short active")
	TEST_ASSERT_EQUAL(apc.shock_count, 2, "partial repair does not attempt the final-mend shock")
	wires.cut(WIRE_MAIN_POWER2, user)
	TEST_ASSERT(!wires.is_cut(WIRE_MAIN_POWER2), "the second wire can be mended")
	TEST_ASSERT(!apc.shorted, "mending the final wire clears the real power short")
	TEST_ASSERT_EQUAL(apc.shock_count, 3, "final repair attempts one shock")
	TEST_ASSERT_EQUAL(apc.shock_actor_ref, REF(user), "final repair forwards its actual actor")
	wires.cut(WIRE_MAIN_POWER1)
	TEST_ASSERT(apc.shorted, "actorless cutting still shorts the APC")
	TEST_ASSERT_EQUAL(apc.shock_count, 3, "actorless cutting has no living shock victim")
	wires.cut(WIRE_MAIN_POWER1, user)
	TEST_ASSERT(!apc.shorted, "an actor can repair the actorless cut")
	TEST_ASSERT_EQUAL(apc.shock_count, 4, "repairing that cut shocks the supplied living actor")
