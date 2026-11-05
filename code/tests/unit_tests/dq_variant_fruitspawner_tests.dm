// The fruit spawners are rows of one table (code/content/variants/fruitspawner.dm): a map that names an old path, and a spawner made with its
// variant, both resolve to a harvest of the row's seed.

/datum/unit_test/dq_variant_fruitspawner_rows

/datum/unit_test/dq_variant_fruitspawner_rows/Run()
	var/list/row = dq_variant_vars(/obj/fruitspawner, "cabbage")
	TEST_ASSERT(islist(row), "the table has a cabbage row")
	TEST_ASSERT_EQUAL(row["seedtype"], PLANT_CABBAGE, "the row names the seed")
	// A map that names the old path hands the resolver the row's seed as a var edit.
	var/list/alias = variant_alias_of("/obj/fruitspawner/cabbage")
	TEST_ASSERT(islist(alias), "the old path resolves")
	var/list/edits = variant_edits_of(alias)
	TEST_ASSERT_EQUAL(edits["seedtype"], PLANT_CABBAGE, "its edits carry the seed the resolver reads")
	// Made at runtime, the spawner resolves into a harvest on the tile and is gone.
	var/turf/T = dq_containment_floor()
	// A closet on the tile takes the harvest, as map_spawn_container() chooses; a bare turf as the harvester trips the crop contract event.
	allocate(/obj/structure/closet, T)
	var/before = length(contents_of(T, /obj/item))
	variant_new(VARIANT(/obj/fruitspawner, "cabbage"), T)
	TEST_ASSERT(length(contents_of(T, /obj/item)) > before, "a cabbage spawner left its harvest on the tile")
	for(var/obj/item/harvested in contents_of(T, /obj/item))
		qdel(harvested)
