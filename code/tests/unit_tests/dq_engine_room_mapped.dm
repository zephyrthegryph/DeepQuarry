// The map's engine room holds an engine after init: the engine_loader landmark the map places is the one the mapping system
// loaded an engine template at (a supermatter or a tesla). Southern Cross places the landmark (run with --full-map); a map
// without one has nothing to check.

/datum/unit_test/dq_engine_room_has_engine

/datum/unit_test/dq_engine_room_has_engine/Run()
	var/obj/effect/landmark/engine_loader/loader = locate() in world
	if(!loader)
		log_test("this map places no engine loader")
		return
	TEST_ASSERT_EQUAL(mapping_engine_loader(), loader, "the mapping system knows the map's engine loader")
	var/list/cores = list()
	for(var/obj/machinery/power/supermatter/S in range(30, loader))
		cores += S
	for(var/obj/machinery/the_singularitygen/tesla/T in range(30, loader))
		cores += T
	log_test("engine loader at [loader.x],[loader.y],[loader.z]: [length(cores)] engine core(s) near it ([english_list(cores)])")
	TEST_ASSERT(length(cores) == 1, "the engine room holds exactly one engine core near the loader, found [length(cores)]")
