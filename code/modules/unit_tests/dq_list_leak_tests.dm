// List leak probe: creating and deleting an instance must not leave lists behind. BYOND gives every list an id out of one
// pool (about 16M); a list a deleted thing's bookkeeping still holds is never freed, and a full-tree sweep (one instance of
// thousands of types) runs the pool dry ("bad list" everywhere).
//
// The measure: the id inside the ref of a list made now. Freed ids are reused, so a batch of lists held at once reaches as high as the
// pool's live count does; the highest id of such a batch after N create/delete cycles, against the one before, is the growth.

/// The highest list id among `count` lists held at once (the ids are the low 24 bits of a list's ref).
/proc/dq_list_id_high_water(count = 64)
	var/list/held = list()
	var/high = 0
	for(var/i in 1 to count)
		var/list/L = list()
		held += list(L)
		var/text = ref(L)
		var/id = text2num(copytext(text, 6), 16) // "[0x5xxxxxx]": drop "[0x5"
		if(isnum(id) && id > high)
			high = id
	return high

/// A create/delete cycle count and its growth for `type`: lists the pool holds more after than before. A warm-up pass first, so one-time
/// caches (a type's first instance) are not counted.
/datum/unit_test/proc/dq_list_growth(type, cycles = 300)
	var/turf/T = test_floor()
	for(var/i in 1 to 10)
		qdel(new type(T))
	list_leak_settle()
	var/before = dq_list_id_high_water()
	for(var/i in 1 to cycles)
		qdel(new type(T))
		if(!(i % 50))
			list_leak_settle()
	list_leak_settle()
	var/after = dq_list_id_high_water()
	var/growth = after - before
	log_test("LIST LEAK: [type] x[cycles]: id high water [before] -> [after] (growth [growth], [round(growth / cycles, 0.01)] per instance)")
	return growth

/datum/unit_test/proc/list_leak_settle()
	refresh_flush()
	wait_ticks(round((GC_FILTER_QUEUE + 2) / world.tick_lag) + 1)
	refresh_flush()
	for(var/i in 1 to 100)
		dq_test_gc_pass(GC_QUEUE_FILTER)
		wait_ticks(1)

/datum/unit_test/dq_list_leak_probe

/datum/unit_test/dq_list_leak_probe/Run()
	for(var/type in list(/mob/living/carbon/human, /mob/living/simple_mob/animal/passive/bird/azure_tit/iceman, /obj/item/storage/box, /obj/machinery/light, /obj/structure/closet))
		dq_list_growth(type)

/// The staleness sweep's clean-check snapshots (strict builds) are keyed by entity and leave with it: one list of lists per checked stat
/// and draw of every entity ever made is what ran the list pool dry in a full look sweep.
/datum/unit_test/dq_staleness_good_forgotten

/datum/unit_test/dq_staleness_good_forgotten/Run()
	var/turf/T = test_floor()
	var/before = length(GLOB.staleness_good)
	for(var/i in 1 to 40)
		var/mob/living/carbon/human/H = new(T)
		staleness_track(H)
		refresh_flush()
		staleness_check_entity(H, "list leak test")
		var/ref = REF(H)
		qdel(H)
		TEST_ASSERT(isnull(GLOB.staleness_good[ref]), "a destroyed entity left its clean-check snapshots in GLOB.staleness_good")
		TEST_ASSERT(isnull(GLOB.staleness_served[ref]), "a destroyed entity left GLOB.staleness_served rows")
		TEST_ASSERT(isnull(GLOB.derived_ignored[ref]), "a destroyed entity left GLOB.derived_ignored names")
	TEST_ASSERT_EQUAL(length(GLOB.staleness_good), before, "GLOB.staleness_good grew over create/delete cycles")
