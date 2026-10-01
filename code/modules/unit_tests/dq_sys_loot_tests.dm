// Declared loot (DECLARE_LOOT) and map-time resolvers (MAP_RESOLVER), doc/rewrite/systems.md §8-9.

DECLARE_LOOT(/loot/unit_test/pair, LOOT_ALL(/obj/item/tool/wrench, /obj/item/tool/crowbar))
DECLARE_LOOT(/loot/unit_test/never, LOOT_TABLE(/obj/item/tool/wrench), LOOT_CHANCE(0))
DECLARE_LOOT(/loot/unit_test/nested, LOOT_TABLE(LOOT_REF(/loot/unit_test/pair)), LOOT_COUNT(2))
DECLARE_LOOT(/loot/unit_test/parent, LOOT_TABLE(/obj/item/tool/wrench), LOOT_CHANCE(50), LOOT_COUNT(3))
DECLARE_LOOT(/loot/unit_test/parent/child, LOOT_ALL(/obj/item/tool/crowbar))

/// Deletes everything the loot tests spawned on `T` (not the turf's own mapped contents).
/datum/unit_test/proc/dq_loot_cleanup(list/made)
	for(var/atom/movable/AM as anything in made)
		if(!QDELETED(AM))
			qdel(AM)

/// Declarations build from the macro; a child merges over its parent, replacing what spawns as one unit.
/datum/unit_test/dq_sys_loot_declarations

/datum/unit_test/dq_sys_loot_declarations/Run()
	var/datum/loot_decl/toolbox = loot_decl_for(/obj/random/toolbox)
	TEST_ASSERT_NOTNULL(toolbox, "/obj/random/toolbox has a declaration")
	TEST_ASSERT(toolbox.main_table && toolbox.main_table.total > 0, "the toolbox table has weighted entries")
	TEST_ASSERT_EQUAL(loot_decl_for(/obj/random/toolbox), toolbox, "declarations are built once and shared")

	var/datum/loot_decl/child = loot_decl_for(LOOT_REF(/loot/unit_test/parent/child))
	TEST_ASSERT_NOTNULL(child, "the child declaration builds")
	TEST_ASSERT_NULL(child.main_table, "a child naming LOOT_ALL drops the parent's table")
	TEST_ASSERT_EQUAL(child.chance, 50, "the child inherits the parent's chance")
	TEST_ASSERT_EQUAL(child.count, 3, "the child inherits the parent's count")
	TEST_ASSERT_EQUAL(length(child.all), 1, "the child's own LOOT_ALL is kept")

	// An /obj/random subtype without its own line resolves to its nearest declared ancestor.
	var/datum/loot_decl/mob = loot_decl_for(/obj/random/mob)
	TEST_ASSERT_NOTNULL(mob, "/obj/random/mob is declared")
	TEST_ASSERT_EQUAL(mob.hook, GLOBAL_PROC_REF(loot_hook_random_mob), "the random mob hook is declared")
	var/datum/loot_decl/sif = loot_decl_for(/obj/random/mob/sif)
	TEST_ASSERT_EQUAL(sif.hook, GLOBAL_PROC_REF(loot_hook_random_mob), "a subtype's declaration inherits the hook")
	TEST_ASSERT_NULL(loot_decl_for(/obj/item/tool/wrench), "an ordinary item has no declaration")

/// The seeded rng is reproducible, and a map-time roll depends only on the seed, position and type.
/datum/unit_test/dq_sys_loot_seeded_rng

/datum/unit_test/dq_sys_loot_seeded_rng/Run()
	var/datum/loot_rng/a = new(12345)
	var/datum/loot_rng/b = new(12345)
	var/datum/loot_rng/c = new(54321)
	var/same = TRUE
	var/differs = FALSE
	for(var/i in 1 to 20)
		var/va = a.next()
		var/vb = b.next()
		var/vc = c.next()
		TEST_ASSERT(va >= 0 && va < 1, "rolls are in \[0, 1)")
		if(va != vb)
			same = FALSE
		if(va != vc)
			differs = TRUE
	TEST_ASSERT(same, "the same seed gives the same sequence")
	TEST_ASSERT(differs, "a different seed gives a different sequence")
	TEST_ASSERT_EQUAL(loot_type_hash(/obj/random/toolbox), loot_type_hash(/obj/random/toolbox), "type hashes are stable")
	TEST_ASSERT(loot_type_hash(/obj/random/toolbox) < LOOT_HASH_MOD, "type hashes stay exact")

/// loot_spawn: LOOT_ALL spawns everything, LOOT_CHANCE(0) nothing, nested tables roll through.
/datum/unit_test/dq_sys_loot_spawn

/datum/unit_test/dq_sys_loot_spawn/Run()
	var/turf/T = test_floor()
	var/list/made = loot_spawn(LOOT_REF(/loot/unit_test/pair), T)
	TEST_ASSERT_EQUAL(length(made), 2, "LOOT_ALL spawns both entries")
	var/wrenches = 0
	var/crowbars = 0
	for(var/obj/item/I in made)
		if(I.has_tool_quality(TOOL_WRENCH))
			wrenches++
		else if(I.has_tool_quality(TOOL_CROWBAR))
			crowbars++
	TEST_ASSERT_EQUAL(wrenches, 1, "the wrench spawned")
	TEST_ASSERT_EQUAL(crowbars, 1, "the crowbar spawned")
	dq_loot_cleanup(made)

	TEST_ASSERT_NULL(loot_spawn(LOOT_REF(/loot/unit_test/never), T), "a 0% declaration spawns nothing")

	var/list/direct = list()
	made = loot_spawn(LOOT_REF(/loot/unit_test/nested), T, null, null, direct)
	TEST_ASSERT_EQUAL(length(made), 4, "a nested table rolled twice spawns its pair twice")
	TEST_ASSERT_EQUAL(length(direct), 0, "what a nested table spawns is not the outer declaration's own")
	dq_loot_cleanup(made)

/// An /obj/random made at runtime never becomes a live atom: it resolves in InitAtom and leaves its roll.
/datum/unit_test/dq_sys_loot_random_never_lives

/datum/unit_test/dq_sys_loot_random_never_lives/Run()
	var/turf/T = test_floor()
	var/list/before = T.contents.Copy()
	var/obj/random/tool/R = new(T)
	TEST_ASSERT(!R || R.loc == null, "the spawner is detached, not placed")
	var/list/made = T.contents - before
	TEST_ASSERT_EQUAL(length(made), 1, "the spawner left exactly one roll")
	var/atom/movable/result = made[1]
	TEST_ASSERT(!istype(result, /obj/random), "the roll is an item, not another spawner")
	TEST_ASSERT_NULL(locate_on(T, /obj/random), "no /obj/random remains on the turf")
	dq_loot_cleanup(made)

/// Floor decals resolve onto the turf with the map's var edits, and never become atoms.
/datum/unit_test/dq_sys_resolver_floor_decal

/datum/unit_test/dq_sys_resolver_floor_decal/Run()
	var/turf/simulated/floor/T = test_floor()
	TEST_ASSERT(istype(T), "the test floor is a floor")
	var/list/old_decals = T.decals?.Copy()
	TEST_ASSERT(map_resolve_path(/obj/effect/floor_decal/corner/white, T, list("dir" = NORTH, "color" = "#123456")), "the decal resolves")
	TEST_ASSERT_NULL(locate_on(T, /obj/effect/floor_decal), "no decal atom was made")
	var/image/I = LAZYACCESS(T.decals, LAZYLEN(T.decals))
	TEST_ASSERT_NOTNULL(I, "the decal image is remembered on the turf")
	TEST_ASSERT_EQUAL(I.dir, NORTH, "the mapped dir is honoured")
	TEST_ASSERT_EQUAL(I.color, "#123456", "the mapped colour is honoured")
	T.cut_overlay(I)
	T.decals = old_decals

/// A coordinate-only landmark becomes a registry row; one that stays is left to be made normally.
/datum/unit_test/dq_sys_resolver_landmark

/datum/unit_test/dq_sys_resolver_landmark/Run()
	var/turf/T = test_floor()
	defer_cleanup(null, GLOBAL_PROC_REF(dq_test_drop_blobstart), T)
	TEST_ASSERT(map_resolve_path(/obj/effect/landmark, T, list("name" = "blobstart")), "a blobstart landmark resolves")
	TEST_ASSERT(T in GLOB.blobstart, "its turf is a blobstart registry row")
	dq_test_drop_blobstart(T)
	TEST_ASSERT(!map_resolve_path(/obj/effect/landmark, T, list("name" = "JoinLate")), "a JoinLate landmark stays an atom")
	TEST_ASSERT(!map_resolve_path(/obj/effect/landmark/event_trigger, T, list("name" = "blobstart")), "a landmark subtype with its own work stays an atom")

/// Deferred resolvers run immediately outside a load, and map_varedits_of() reads an instance's edits.
/datum/unit_test/dq_sys_resolver_varedits

/datum/unit_test/dq_sys_resolver_varedits/Run()
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench)
	W.name = "edited wrench"
	W.pixel_y = 7
	var/list/edits = map_varedits_of(W)
	TEST_ASSERT_EQUAL(edits?["name"], "edited wrench", "a changed name is an edit")
	TEST_ASSERT_EQUAL(edits?["pixel_y"], 7, "a changed offset is an edit")
	TEST_ASSERT(!("desc" in edits), "an unchanged var is not an edit")
	TEST_ASSERT(!map_loading(), "no load is running during a unit test")

/// Takes a test turf back out of the blobstart registry.
/proc/dq_test_drop_blobstart(turf/T)
	GLOB.blobstart -= T
