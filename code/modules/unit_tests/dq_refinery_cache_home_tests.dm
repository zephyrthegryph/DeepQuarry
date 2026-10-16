/datum/unit_test/dq_refinery_cache_home
/datum/unit_test/dq_refinery_cache_home/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/turf/T = test_floor()
	var/obj/machinery/reagent_refinery/grinder/G = allocate(/obj/machinery/reagent_refinery/grinder, T)
	var/list/initial_items = G.vars["holdingitems"]
	TEST_ASSERT_NULL(initial_items, "an empty grinder has no intake cache allocation")
	TEST_ASSERT_NULL(G.has_room(null, null, null), "the real admission still permits an item in an empty cache")
	var/obj/item/stack/material/steel/S = allocate(/obj/item/stack/material/steel, T)
	TEST_ASSERT(G.conveyor_load(S), "the real conveyor intake accepts a grindable steel stack")
	TEST_ASSERT_EQUAL(S.loc, G, "intake uses actual containment")
	var/list/held = G.vars["holdingitems"]
	TEST_ASSERT_EQUAL(length(held), 1, "the native owned collection materializes on intake")
	TEST_ASSERT_EQUAL(held[1], S, "the collection retains the actual inserted stack")
	TEST_ASSERT(G.refinery_busy(), "the actual busy gate observes the nonempty intake")
	qdel(G)
	TEST_ASSERT(!QDELETED(S), "destroying the grinder spills rather than deletes its intake")
	TEST_ASSERT_EQUAL(S.loc, T, "the actual stack is released back to the floor")
