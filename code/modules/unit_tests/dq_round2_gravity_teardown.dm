// Real damage and ownership teardown exercise the production gravity generator.
// Normal damage breaks the generator. Destroying an owned part destroys the main,
// per the existing destroyed(main_part) behavior; this is separate from damage.
/datum/unit_test/round2_gravity_teardown
	abstract_type = /datum/unit_test/round2_gravity_teardown
	var/list/gravity_before
	var/obj/machinery/gravity_generator/main/fixture_generator

/datum/unit_test/round2_gravity_teardown/proc/generator_with_parts()
	var/turf/bottom_left = test_floor()
	var/turf/T = locate(bottom_left.x + 2, bottom_left.y + 1, bottom_left.z)
	TEST_ASSERT(T, "the main fits within the actual five-by-five fixture block")
	gravity_before = unit_test_gravity_snapshot()
	var/obj/machinery/gravity_generator/main/G = allocate(/obj/machinery/gravity_generator/main, T)
	fixture_generator = G
	defer_cleanup(src, PROC_REF(cleanup_generator))
	G.setup_parts()
	TEST_ASSERT_EQUAL(length(G.parts), 8, "the real main constructs all eight owned parts")
	// Production gravity discovers every relevant area. The test stores its snapshot
	// locally; deferred arguments may not use area datums as associative keys.
	G.update_list()
	G.update_areas()
	TEST_ASSERT(T.z in G.levels, "production level discovery includes the generator floor")
	TEST_ASSERT(get_area(T) in G.areas, "production area discovery includes the test area")
	G.set_gravity_state(TRUE)
	TEST_ASSERT(get_area(T).has_gravity, "the real generator initially supplies gravity")
	return G

/datum/unit_test/round2_gravity_teardown/proc/cleanup_generator()
	// No captured datum args: cleanup must run even when the test destroyed its generator.
	var/obj/machinery/gravity_generator/main/G = fixture_generator
	fixture_generator = null
	if(!QDELETED(G))
		destroyed(G)
	for(var/area/room as anything in gravity_before)
		if(!QDELETED(room))
			room.gravitychange(gravity_before[room])
	gravity_before = null

/datum/unit_test/round2_gravity_teardown/damage
/datum/unit_test/round2_gravity_teardown/damage/Run()
	var/obj/machinery/gravity_generator/main/G = generator_with_parts()
	var/obj/machinery/gravity_generator/part/P = G.parts[1]
	TEST_ASSERT(!G.broken_now() && !P.broken_now(), "the actual main and part begin intact")
	P.atom_break()
	TEST_ASSERT(!QDELETED(G) && G.broken_now(), "normal part damage breaks its live main without deleting it")
	TEST_ASSERT(!get_area(G).has_gravity, "normal part damage switches off gravity")

/datum/unit_test/round2_gravity_teardown/main_destroy
/datum/unit_test/round2_gravity_teardown/main_destroy/Run()
	var/obj/machinery/gravity_generator/main/G = generator_with_parts()
	var/list/owned_parts = G.parts.Copy()
	var/area/room = get_area(G)
	destroyed(G)
	TEST_ASSERT(QDELETED(G), "the actual main is destroyed")
	for(var/obj/machinery/gravity_generator/part/P as anything in owned_parts)
		TEST_ASSERT(QDELETED(P), "main destruction removes every original owned part")
	TEST_ASSERT(!room.has_gravity, "main destruction switches off gravity")

/datum/unit_test/round2_gravity_teardown/part_destroy
/datum/unit_test/round2_gravity_teardown/part_destroy/Run()
	var/obj/machinery/gravity_generator/main/G = generator_with_parts()
	var/list/owned_parts = G.parts.Copy()
	var/obj/machinery/gravity_generator/part/P = owned_parts[1]
	var/area/room = get_area(G)
	destroyed(P)
	TEST_ASSERT(QDELETED(G), "destroying an original part preserves the existing whole-generator destruction")
	for(var/obj/machinery/gravity_generator/part/part as anything in owned_parts)
		TEST_ASSERT(QDELETED(part), "part destruction removes every original owned part")
	TEST_ASSERT(!room.has_gravity, "part destruction switches off gravity")
