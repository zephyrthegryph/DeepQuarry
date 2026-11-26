// hop_moved() keeps, on a mover, which of the things it carries read the turf and area hops (code/engine/refs/hops.dm). The kept answers must be the
// full walk's on every step: checked here with GLOB.hop_cache_verify, through what changes them (a reader coming and going, a thing put in, taken
// out, deleted).

/// A human steps about while its carried things change and an observer of the turf hop comes and goes: every step's kept answers equal the full walk,
/// the cache is used (hits), and a new reader is published on the next step.
/datum/unit_test/dq_hop_cache_parity

/datum/unit_test/dq_hop_cache_parity/Run()
	set_global(nameof(GLOB.hop_cache_verify), TRUE)
	var/mismatches = GLOB.hop_cache_mismatches
	var/hits = GLOB.hop_cache_hits
	var/turf/start = run_loc_floor_bottom_left
	var/turf/east = get_step(start, EAST)
	TEST_ASSERT(istype(east, /turf/simulated/floor), "the test room has a floor east of the corner")
	var/mob/living/carbon/human/walker = allocate(/mob/living/carbon/human, start)
	var/obj/item/carried = allocate(/obj/item, walker)
	walk_between(walker, start, east, 3)
	// A reader of the turf hop on a carried thing comes: the next step publishes it there.
	rx_watch_adjust(carried, HOP_TURF, 1)
	walk_between(walker, start, east, 1)
	var/datum/rx_state/S = walker.rx
	var/list/moved = list(walker) + hop_nested_contents(walker)
	TEST_ASSERT(moved.Find(carried) in S.hop_cache_turf, "the carried thing that gained a turf reader is published the turf hop")
	walk_between(walker, start, east, 2)
	rx_watch_adjust(carried, HOP_TURF, -1)
	walk_between(walker, start, east, 2)
	// What it carries changes: a thing put in, one taken out, one deleted.
	var/obj/item/more = allocate(/obj/item, walker)
	walk_between(walker, start, east, 2)
	more.forceMove(start)
	walk_between(walker, start, east, 2)
	qdel(carried)
	walk_between(walker, start, east, 2)
	TEST_ASSERT_EQUAL(GLOB.hop_cache_mismatches, mismatches, "every step's kept answers equal the full walk")
	TEST_ASSERT(GLOB.hop_cache_hits > hits, "and steps used them")

/datum/unit_test/dq_hop_cache_parity/proc/walk_between(mob/M, turf/a, turf/b, steps)
	for(var/i in 1 to steps)
		M.forceMove(M.loc == a ? b : a)
