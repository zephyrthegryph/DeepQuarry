// Loot behaviour, asserted directly: a roll yields what its table declares, a search yields once per searcher, a resolver is found by inheritance.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A roll of a spawner makes something, and only things its table names.
/datum/unit_test/dq_loot_roll_yields_table_item

/datum/unit_test/dq_loot_roll_yields_table_item/Run()
	var/turf/T = test_floor()
	var/saved_seed = GLOB.loot_seed
	var/saved_serial = GLOB.loot_roll_serial
	GLOB.loot_seed = 26118
	GLOB.loot_roll_serial = 0
	var/made_total = 0
	for(var/roll in 1 to 30)
		var/list/made = loot_spawn(/obj/random/toolbox, T)
		for(var/atom/A as anything in made)
			made_total++
			TEST_ASSERT(istype(A, /obj/item/storage/toolbox), "a toolbox spawner made [A.type], which its table does not name")
			if(!QDELETED(A))
				qdel(A)
	GLOB.loot_seed = saved_seed
	GLOB.loot_roll_serial = saved_serial
	own_turf_contents(T)
	TEST_ASSERT(made_total > 0, "thirty rolls of a table that always spawns made nothing")

/// A pile that always yields gives its loot to a searcher once, then refuses the same searcher.
/datum/unit_test/dq_loot_search_yields_once_per_searcher

/datum/unit_test/dq_loot_search_yields_once_per_searcher/Run()
	var/pile_type
	for(var/type in typesof(/obj/structure/loot_pile) | typesof(/obj/structure/trash_pile))
		var/datum/loot_decl/decl = loot_decl_for(loot_search_table(type))
		if(decl && decl.chance >= 100 && !decl.repeat_search && !decl.loot_left && !decl.gamma_chance)
			pile_type = type
			break
	TEST_ASSERT(pile_type, "some pile always yields to a first search")
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/searcher = allocate(/mob/living/carbon/human, T)
	var/obj/structure/pile = allocate(pile_type, T)
	bind_player(searcher, "lootsearcher", as_ckey = TRUE)
	TEST_ASSERT_NULL(loot_search_refusal(pile, searcher), "a fresh pile can be searched")
	var/list/before = contents_of(T).Copy()
	loot_search_roll(pile, searcher)
	var/gained = 0
	for(var/atom/movable/AM as anything in contents_of(T))
		if(!(AM in before) && !QDELETED(AM))
			gained++
			qdel(AM)
	TEST_ASSERT(gained > 0, "the first search of [pile_type] gave the searcher nothing")
	TEST_ASSERT_EQUAL(loot_search_refusal(pile, searcher), /datum/msg/loot_search/nothing_more, "the same searcher is refused a second search")
	bind_player(searcher, null, as_ckey = TRUE)
	own_turf_contents(T)
	test_driver_end()

/// A map resolver is found for its type and for the types under it, and not for a plain item.
/datum/unit_test/dq_map_resolver_inherited

/datum/unit_test/dq_map_resolver_inherited/Run()
	var/resolver = map_resolver_proc(/obj/effect/falling_effect)
	TEST_ASSERT(resolver, "the falling effect declares a map resolver")
	TEST_ASSERT_NULL(map_resolver_proc(/obj/item/pen), "a pen has no map resolver")
	TEST_ASSERT("falling_type" in map_resolver_vars_of(/obj/effect/falling_effect), "the resolver reads the falling type")
	for(var/type in subtypesof(/obj/effect/falling_effect))
		if(findtext("[type]", "/dq_"))
			continue
		TEST_ASSERT_EQUAL(map_resolver_proc(type), resolver, "[type] inherits its parent's resolver")

#endif
