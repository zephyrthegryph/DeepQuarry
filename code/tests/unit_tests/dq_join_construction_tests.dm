/**
 * The joins a load batch computes (adjacency_flush_batch()) run as a construction step: what they write is published once, at the step's end.
 * The look they settle on must be the one the write-by-write path drew. Each test builds the same row twice in a load batch, once with silent
 * construction and once without, and compares what each member ends up showing.
 */
/datum/unit_test/dq_join_construction
	abstract_type = /datum/unit_test/dq_join_construction

/// What a member shows: its icon_state, dir, connections and the overlays of its look.
/datum/unit_test/dq_join_construction/proc/look_of(atom/A)
	var/list/states = list()
	for(var/overlay_entry in A.overlays) // appearances, not images
		var/image/overlay_image = overlay_entry
		states += "[overlay_image.icon_state]/[overlay_image.dir]"
	var/joins = ""
	if(istype(A, /obj/structure))
		var/obj/structure/S = A
		joins = "[jointext(S.connections || list(), ",")]|[jointext(S.other_connections || list(), ",")]"
	else if(istype(A, /turf/simulated/wall))
		var/turf/simulated/wall/W = A
		joins = jointext(W.get_wall_connections(), ",")
	return "[A.icon_state]|[A.dir]|[joins]|[jointext(states, ";")]"

/// The three tiles east of the test floor.
/datum/unit_test/dq_join_construction/proc/row()
	. = list()
	var/turf/T = test_floor()
	for(var/i in 1 to 3)
		T = get_step(T, EAST)
		TEST_ASSERT(istype(T, /turf/simulated/floor), "the test map has three floors east of the test floor")
		. += T

/// Builds `type` on each tile of the row inside one load batch, settles the draws, and returns each member's look.
/datum/unit_test/dq_join_construction/proc/build_row(type, silent)
	set_global("silent_construction", silent)
	var/list/made = list()
	var/datum/materialize_batch/batch = SSatoms.batch_open("dq_join_construction")
	for(var/turf/T as anything in row())
		made += new type(T)
	SSatoms.batch_close(batch)
	set_global("silent_construction", TRUE)
	stat_drain_point()
	refresh_flush()
	. = list()
	for(var/atom/A as anything in made)
		. += look_of(A)
	for(var/atom/A as anything in made)
		qdel(A)
	refresh_flush()

/datum/unit_test/dq_join_construction/windows_look_the_same/Run()
	var/before = GLOB.adjacency_joins_constructed
	var/list/loud = build_row(/obj/structure/window/reinforced/full, FALSE)
	var/list/silent = build_row(/obj/structure/window/reinforced/full, TRUE)
	TEST_ASSERT(GLOB.adjacency_joins_constructed > before, "the silent row's joins ran as a construction step")
	TEST_ASSERT_EQUAL(jointext(silent, "\n"), jointext(loud, "\n"), "a window row looks the same either way")
	TEST_ASSERT(findtext(silent[2], "1") || findtext(silent[2], "2") || findtext(silent[2], "3"), "the middle window joins its neighbours: [silent[2]]")

/datum/unit_test/dq_join_construction/low_walls_look_the_same/Run()
	var/list/loud = build_row(/obj/structure/low_wall, FALSE)
	var/list/silent = build_row(/obj/structure/low_wall, TRUE)
	TEST_ASSERT_EQUAL(jointext(silent, "\n"), jointext(loud, "\n"), "a low wall row looks the same either way")
