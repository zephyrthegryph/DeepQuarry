// A loot table whose roll can come round to itself (it lists its own spawner type, or a type that shares its table, or a chain of tables that leads back)
// rolls again at the spawn, without end. The declarations are checked when they are built (loot_self_spawners(), one WARNING per type) and loot_spawn()
// spawns nothing for a type found so. A spawner that rolls another spawner's different table (a parent type with its own rows) is fine.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A declaration whose table holds `rows`.
/proc/dq_loot_test_decl(list/rows)
	var/datum/loot_decl/decl = new
	decl.build_entry(loot(table = rows))
	return decl

/datum/unit_test/dq_loot_finds_self_spawning_tables

/datum/unit_test/dq_loot_finds_self_spawning_tables/Run()
	var/own = /obj/effect/landmark/costume/marisawizard
	var/chicken = /obj/effect/landmark/costume/chicken
	var/maid = /obj/effect/landmark/costume/maid
	var/butler = /obj/effect/landmark/costume/butler
	var/gladiator = /obj/effect/landmark/costume/gladiator
	var/list/decls = list()
	// a type that lists its own type (the bug: a type inheriting the base's random table, listed under it)
	decls[own] = dq_loot_test_decl(list(loot_types(1, list(own, chicken))))
	// two types that roll each other
	decls[maid] = dq_loot_test_decl(list(butler))
	decls[butler] = dq_loot_test_decl(list(maid, /obj/item/pen))
	// a type that rolls a parent spawner with a different table of its own: no fault
	decls[chicken] = dq_loot_test_decl(list(/obj/item/pen))
	decls[gladiator] = dq_loot_test_decl(list(chicken, /obj/item/pen))
	// a type that shares its parent's table, which lists it
	var/datum/loot_decl/shared = dq_loot_test_decl(list(/obj/effect/landmark/costume/madscientist))
	decls[/obj/effect/landmark/costume/madscientist] = shared
	decls[/obj/effect/landmark/costume/elpresidente] = shared
	var/list/found = loot_self_spawners(decls)
	TEST_ASSERT(found[own], "a table that lists its own spawner type was not found")
	TEST_ASSERT(found[maid] && found[butler], "two tables that roll each other were not found")
	TEST_ASSERT(!found[chicken], "a table of items was refused")
	TEST_ASSERT(!found[gladiator], "a table that rolls another spawner's own table was refused")
	TEST_ASSERT(found[/obj/effect/landmark/costume/madscientist] && found[/obj/effect/landmark/costume/elpresidente], "a table shared with a type it lists was not found")
	TEST_ASSERT_EQUAL(length(found), 5, "unexpected refusals: [json_encode(found)]")

/datum/unit_test/dq_loot_refuses_self_spawning_roll

/datum/unit_test/dq_loot_refuses_self_spawning_roll/Run()
	var/turf/T = test_floor()
	var/before = length(T.contents)
	GLOB.loot_refused[/obj/effect/landmark/costume/chicken] = TRUE
	var/list/made = loot_spawn(/obj/effect/landmark/costume/chicken, T)
	GLOB.loot_refused -= /obj/effect/landmark/costume/chicken
	TEST_ASSERT(isnull(made), "a refused roll made something")
	TEST_ASSERT_EQUAL(length(T.contents), before, "a refused roll left something on the tile")
	var/list/other = loot_spawn(/obj/effect/landmark/costume/chicken, T)
	TEST_ASSERT(length(other), "the same roll, no longer refused, made nothing")
	for(var/atom/movable/made_item as anything in other)
		qdel(made_item)

/// The shipped declarations hold no table that comes round to itself.
/datum/unit_test/dq_loot_shipped_tables_do_not_loop

/datum/unit_test/dq_loot_shipped_tables_do_not_loop/Run()
	TEST_ASSERT_EQUAL(length(GLOB.loot_refused), 0, "the shipped loot tables roll themselves: [json_encode(GLOB.loot_refused)]")

#endif
