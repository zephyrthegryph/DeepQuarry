// Chunk interest (code/engine/change/interest.dm, doc/rewrite/proposals/demand_driven_refresh.md section 3): a mark of an atom nobody can see is deferred, the
// atom is drawn before a chunk it stands in is shown, and the observers (a view, a vis_contents holder) are set by events.

/// An object that draws a state of its own and watches nothing: the subject of the deferral tests. It can stand on any turf with others of its kind.
/obj/dq_interest_probe
	name = "interest probe"
	var/shown = 0

/obj/dq_interest_probe/draw(datum/look/look)
	. = ..()
	look.state("probe")

/// The state every test of this file starts from: no observers, and the probe type a lazy one (its live outputs are its look).
/datum/unit_test/proc/interest_isolate()
	set_global(nameof(GLOB.interest_grid), list())
	set_global(nameof(GLOB.interest_holds), list())
	set_global(nameof(GLOB.interest_visible), list())
	set_global(nameof(GLOB.interest_sigs), list())
	set_global(nameof(GLOB.interest_anchors), list())
	set_global(nameof(GLOB.refresh_deferred), GLOB.refresh_deferred)
	set_global(nameof(GLOB.refresh_deferred_absorbed), GLOB.refresh_deferred_absorbed)
	set_global(nameof(GLOB.refresh_parked_near), GLOB.refresh_parked_near)
	set_global(nameof(GLOB.refresh_near_drawn), GLOB.refresh_near_drawn)
	set_global(nameof(GLOB.interest_chunks_entered), GLOB.interest_chunks_entered)
	set_global(nameof(GLOB.interest_drawn_now), GLOB.interest_drawn_now)
	var/list/lazy = GLOB.type_look_lazy.Copy()
	lazy[/obj/dq_interest_probe] = TRUE
	set_global(nameof(GLOB.type_look_lazy), lazy)

/// A turf four chunks away from `T` on its row, outside its view and the ring round it, or null when the map is too small.
/datum/unit_test/proc/interest_far_from(turf/T)
	var/dx = 4 * INTEREST_CHUNK
	if(T.x + dx <= world.maxx)
		return locate(T.x + dx, T.y, T.z)
	if(T.x - dx >= 1)
		return locate(T.x - dx, T.y, T.z)
	return null

/// Makes `count` probes on `T`, drawn and quiet.
/datum/unit_test/proc/interest_probes(turf/T, count)
	var/list/probes = list()
	for(var/i in 1 to count)
		probes += new /obj/dq_interest_probe(T)
	refresh_flush()
	return probes

/datum/unit_test/proc/interest_clean(list/probes)
	for(var/obj/dq_interest_probe/probe as anything in probes)
		qdel(probe)
	refresh_flush()

/// A mass mark of atoms nobody can see parks them all, queues nothing, and counts the marks; a mark of an atom already owing its draw is absorbed.
/datum/unit_test/dq_interest_mass_mark_off_screen_defers

/datum/unit_test/dq_interest_mass_mark_off_screen_defers/Run()
	interest_isolate()
	var/turf/T = test_floor()
	var/list/probes = interest_probes(T, 20)
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	var/queued_before = length(GLOB.refresh_queue)
	var/deferred_before = GLOB.refresh_deferred
	var/absorbed_before = GLOB.refresh_deferred_absorbed
	for(var/obj/dq_interest_probe/probe as anything in probes)
		refresh_mark(probe, DEP_ALL)
	TEST_ASSERT_EQUAL(GLOB.refresh_deferred - deferred_before, 20, "every mark of an unobserved lazy atom was deferred")
	TEST_ASSERT_EQUAL(length(GLOB.refresh_queue), queued_before, "and none of them reached the queue")
	for(var/obj/dq_interest_probe/probe as anything in probes)
		TEST_ASSERT_EQUAL(probe.refresh_queued, DEP_PARKED, "an unobserved atom owes its draw and is not queued")
	for(var/obj/dq_interest_probe/probe as anything in probes)
		refresh_mark(probe, DEP_DRAW)
	TEST_ASSERT_EQUAL(GLOB.refresh_deferred_absorbed - absorbed_before, 20, "a second mark of an atom already owing its draw is absorbed: the redraw never happens")
	TEST_ASSERT_EQUAL(length(GLOB.refresh_queue), queued_before, "and still queues nothing")
	// Nothing waits forever: a viewer arrives and every owed draw is run before it can see them.
	interest_view_set("dq-test-viewer", T, null, world.view)
	for(var/obj/dq_interest_probe/probe as anything in probes)
		TEST_ASSERT_EQUAL(probe.refresh_queued, 0, "the chunk became visible: the owed draw ran at once")
	interest_clean(probes)

/// The same mark on atoms a viewer can see queues them at once, and nothing is deferred.
/datum/unit_test/dq_interest_mass_mark_on_screen_draws_at_once

/datum/unit_test/dq_interest_mass_mark_on_screen_draws_at_once/Run()
	interest_isolate()
	var/turf/T = test_floor()
	var/list/probes = interest_probes(T, 20)
	interest_view_set("dq-test-viewer", T, null, world.view)
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	var/deferred_before = GLOB.refresh_deferred
	for(var/obj/dq_interest_probe/probe as anything in probes)
		refresh_mark(probe, DEP_ALL)
	TEST_ASSERT_EQUAL(GLOB.refresh_deferred, deferred_before, "nothing was deferred")
	for(var/obj/dq_interest_probe/probe as anything in probes)
		TEST_ASSERT(probe in GLOB.refresh_queue, "an atom in view is queued by its mark")
		TEST_ASSERT(!(probe.refresh_queued & DEP_PARKED), "and is not parked")
	refresh_drain(null)
	for(var/obj/dq_interest_probe/probe as anything in probes)
		TEST_ASSERT_EQUAL(probe.refresh_queued, 0, "and drawn by the next drain")
	interest_clean(probes)

/// A viewer arriving at an area with owed draws (a teleport, a login): they have all run by the time its view is set, whatever the lane has done.
/datum/unit_test/dq_interest_arrival_draws_visible_chunks

/datum/unit_test/dq_interest_arrival_draws_visible_chunks/Run()
	interest_isolate()
	var/turf/home = test_floor()
	var/turf/away = interest_far_from(home)
	TEST_ASSERT_NOTNULL(away, "the map has room for a turf four chunks away")
	var/list/probes = interest_probes(away, 10)
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	interest_view_set("dq-test-viewer", home, null, world.view)
	for(var/obj/dq_interest_probe/probe as anything in probes)
		refresh_mark(probe, DEP_ALL)
		TEST_ASSERT_EQUAL(probe.refresh_queued, DEP_PARKED, "far from the viewer the change is deferred")
	TEST_ASSERT(!interest_covers(away), "the chunk is not held")
	var/entered_before = GLOB.interest_chunks_entered
	TEST_ASSERT(interest_view_set("dq-test-viewer", away, null, world.view), "the viewer's arrival changes its hold")
	TEST_ASSERT(GLOB.interest_chunks_entered > entered_before, "and walks the chunks it enters")
	TEST_ASSERT(interest_covers(away), "the chunk is held now")
	TEST_ASSERT(!interest_covers(home), "and the one the viewer left is not")
	for(var/obj/dq_interest_probe/probe as anything in probes)
		TEST_ASSERT_EQUAL(probe.refresh_queued, 0, "drawn by the event itself, before the chunk is shown")
	TEST_ASSERT(!interest_view_set("dq-test-viewer", away, null, world.view), "an unchanged view does nothing")
	interest_clean(probes)

/// A viewer walking one tile per tick toward undrawn atoms: each is drawn by the time it is inside the view window. Run twice: with the lane draining every
/// tick (the ring queues the draws and the lane runs them), and with the lane never running (the chunk becoming visible draws them outside the budget).
/datum/unit_test/dq_interest_walk_never_sees_undrawn

/datum/unit_test/dq_interest_walk_never_sees_undrawn/Run()
	TEST_ASSERT(walk_toward(TRUE), "with the lane draining every tick")
	TEST_ASSERT(walk_toward(FALSE), "with the lane starved")

/datum/unit_test/dq_interest_walk_never_sees_undrawn/proc/walk_toward(lane_drains)
	interest_isolate()
	var/turf/home = test_floor()
	var/turf/away = interest_far_from(home)
	if(isnull(away))
		return Fail("the map has no turf four chunks from the test floor", __FILE__, __LINE__)
	var/list/probes = interest_probes(away, 6)
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	var/half = world.view + 2
	var/step = away.x > home.x ? 1 : -1
	interest_view_set("dq-test-viewer", home, null, world.view)
	for(var/obj/dq_interest_probe/probe as anything in probes)
		refresh_mark(probe, DEP_ALL)
	var/seen_drawn_early = FALSE
	for(var/x = home.x, x != away.x, x += step)
		var/turf/at = locate(x, home.y, home.z)
		interest_view_set("dq-test-viewer", at, null, world.view)
		if(lane_drains)
			refresh_drain(null)
		for(var/obj/dq_interest_probe/probe as anything in probes)
			var/turf/where = probe.loc
			if(abs(where.x - at.x) <= half)
				if(probe.refresh_queued)
					return Fail("a probe at [where.x],[where.y] was inside the view window of a viewer at [at.x],[at.y] with its draw still owed ([probe.refresh_queued], lane [lane_drains ? "draining" : "starved"])", __FILE__, __LINE__)
			else if(!probe.refresh_queued)
				seen_drawn_early = TRUE
	if(lane_drains && !seen_drawn_early)
		return Fail("with the lane draining, the ring should have had the draws done before the window reached the chunk", __FILE__, __LINE__)
	interest_clean(probes)
	return TRUE

/// A parked atom that moves into a held chunk draws; one that moves between unheld chunks stays parked.
/datum/unit_test/dq_interest_parked_atom_moves_into_view

/datum/unit_test/dq_interest_parked_atom_moves_into_view/Run()
	interest_isolate()
	var/turf/home = test_floor()
	var/turf/away = interest_far_from(home)
	TEST_ASSERT_NOTNULL(away, "the map has room for a turf four chunks away")
	var/list/probes = interest_probes(away, 1)
	var/obj/dq_interest_probe/probe = probes[1]
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	interest_view_set("dq-test-viewer", home, null, world.view)
	refresh_mark(probe, DEP_ALL)
	TEST_ASSERT_EQUAL(probe.refresh_queued, DEP_PARKED, "deferred out of view")
	probe.forceMove(locate(away.x, away.y + 1, away.z))
	TEST_ASSERT_EQUAL(probe.refresh_queued, DEP_PARKED, "a move between unheld chunks keeps it parked")
	probe.forceMove(home)
	TEST_ASSERT_EQUAL(probe.refresh_queued, 0, "moved into the viewer's chunk it is drawn")
	interest_clean(probes)

/// A holder that shows turfs through vis_contents (a camera screen, a picture in picture, a portal) is an observer of them while it does, and not after
/// it stops or is deleted.
/datum/unit_test/dq_interest_vis_holder_observes

/datum/unit_test/dq_interest_vis_holder_observes/Run()
	interest_isolate()
	var/turf/home = test_floor()
	var/turf/away = interest_far_from(home)
	TEST_ASSERT_NOTNULL(away, "the map has room for a turf four chunks away")
	var/list/probes = interest_probes(away, 5)
	var/obj/dq_interest_probe/holder = new(home)
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	for(var/obj/dq_interest_probe/probe as anything in probes)
		refresh_mark(probe, DEP_ALL)
		TEST_ASSERT_EQUAL(probe.refresh_queued, DEP_PARKED, "deferred while nothing shows the chunk")
	vis_add(holder, away)
	TEST_ASSERT(interest_covers(away), "a holder showing a turf holds its chunk")
	for(var/obj/dq_interest_probe/probe as anything in probes)
		TEST_ASSERT_EQUAL(probe.refresh_queued, 0, "and the draws the screen needs have run")
	vis_remove(holder, away)
	TEST_ASSERT(!interest_covers(away), "a holder that stopped showing it releases the chunk")
	vis_add(holder, away)
	TEST_ASSERT(interest_covers(away), "shown again")
	qdel(holder)
	TEST_ASSERT(!interest_covers(away), "a deleted holder releases it")
	interest_clean(probes)

/// What is not a standing, lazy, look-only atom is never deferred: a carried item shows wherever it is carried, a type with no lazy verdict derives more than
/// a look, and a mark of an effect kind is not presentation.
/datum/unit_test/dq_interest_defers_only_unobserved_look

/datum/unit_test/dq_interest_defers_only_unobserved_look/Run()
	interest_isolate()
	var/turf/T = test_floor()
	var/list/probes = interest_probes(T, 3)
	var/obj/dq_interest_probe/standing = probes[1]
	var/obj/dq_interest_probe/carried = probes[2]
	var/obj/dq_interest_probe/other = probes[3]
	var/obj/dq_interest_probe/box = new(T)
	probes += box
	carried.forceMove(box)
	refresh_flush()
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	refresh_mark(carried, DEP_ALL)
	TEST_ASSERT(carried.refresh_queued & DEP_DRAW, "an atom inside a container is queued: its look is shown wherever it is carried")
	TEST_ASSERT(!(carried.refresh_queued & DEP_PARKED), "and not parked")
	refresh_mark(standing, DEP_PUSH)
	TEST_ASSERT(!(standing.refresh_queued & DEP_PARKED), "a mark with no presentation in it is not deferred")
	refresh_flush()
	var/list/no_verdict = GLOB.type_look_lazy.Copy()
	no_verdict -= /obj/dq_interest_probe
	set_global(nameof(GLOB.type_look_lazy), no_verdict)
	refresh_mark(other, DEP_ALL)
	TEST_ASSERT(!(other.refresh_queued & DEP_PARKED), "a type with no lazy verdict is never deferred")
	refresh_flush()
	interest_clean(probes)

/// Two atoms that watch each other do not pass a mark back and forth for ever once both are parked.
/datum/unit_test/dq_interest_watchers_do_not_loop

/datum/unit_test/dq_interest_watchers_do_not_loop/Run()
	interest_isolate()
	var/turf/T = test_floor()
	var/list/tables = list()
	for(var/i in 0 to 2)
		tables += new /obj/structure/table(locate(T.x + i, T.y, T.z))
	var/list/lazy = GLOB.type_look_lazy.Copy()
	lazy[/obj/structure/table] = TRUE
	set_global(nameof(GLOB.type_look_lazy), lazy)
	refresh_flush()
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	for(var/obj/structure/table/table as anything in tables)
		state_changed(table)
	for(var/obj/structure/table/table as anything in tables)
		TEST_ASSERT(table.refresh_queued & DEP_PARKED, "a table nobody sees stays parked however its neighbours are marked")
	interest_view_set("dq-test-viewer", T, null, world.view)
	for(var/obj/structure/table/table as anything in tables)
		TEST_ASSERT_EQUAL(table.refresh_queued, 0, "and is drawn when it is seen")
	for(var/obj/structure/table/table as anything in tables)
		qdel(table)
	for(var/i in 0 to 2)
		for(var/obj/item/stack/material/scrap in locate(T.x + i, T.y, T.z)) // a table leaves its material behind
			qdel(scrap)
	refresh_flush()

/// The view of a client is a rectangle of chunks with a ring of one chunk round it; the same rectangle is no event.
/datum/unit_test/dq_interest_view_keys

/datum/unit_test/dq_interest_view_keys/Run()
	interest_isolate()
	var/turf/T = test_floor()
	var/list/visible = list()
	var/list/keys = interest_view_keys(T, world.view, visible)
	var/key = INTEREST_KEY(T.z, INTEREST_CHUNK_OF(T.x), INTEREST_CHUNK_OF(T.y))
	TEST_ASSERT(key in visible, "the view sees the chunk the eye stands in")
	TEST_ASSERT(key in keys, "and holds it")
	TEST_ASSERT(length(keys) >= length(visible), "the ring is held beyond what is seen")
	if(T.x + INTEREST_CHUNK <= world.maxx && INTEREST_CHUNK_OF(T.x) < INTEREST_CHUNK_OF(world.maxx))
		TEST_ASSERT(INTEREST_KEY(T.z, INTEREST_CHUNK_OF(T.x) + 1, INTEREST_CHUNK_OF(T.y)) in keys, "a chunk to the side is in the ring")
	TEST_ASSERT(length(interest_view_keys(T, 31)) >= length(keys), "a wider view holds at least as many")
	TEST_ASSERT(interest_view_set("dq-test-a", T, null, world.view), "a first view is a change")
	TEST_ASSERT(!interest_view_set("dq-test-a", T, null, world.view), "the same view is not")
	TEST_ASSERT_EQUAL(interest_count(T.z, INTEREST_CHUNK_OF(T.x), INTEREST_CHUNK_OF(T.y)), 1, "one observer holds the eye's chunk")
	interest_view_set("dq-test-b", T, null, world.view)
	TEST_ASSERT_EQUAL(interest_count(T.z, INTEREST_CHUNK_OF(T.x), INTEREST_CHUNK_OF(T.y)), 2, "two hold it together")
	interest_hold_set("dq-test-a", null)
	TEST_ASSERT_EQUAL(interest_count(T.z, INTEREST_CHUNK_OF(T.x), INTEREST_CHUNK_OF(T.y)), 1, "and one still does after the other leaves")
	interest_hold_set("dq-test-b", null)
	TEST_ASSERT(!interest_covers(T), "nobody, nothing held")

/// A map load running elsewhere (an expedition z-level takes seconds) holds back only the atoms it is still setting up. A parked atom a player walks up
/// to draws as ever; one whose own init frame is open waits, and draws when the frame ends.
/datum/unit_test/dq_interest_map_load_gates_only_its_own_atoms

/datum/unit_test/dq_interest_map_load_gates_only_its_own_atoms/Run()
	interest_isolate()
	var/turf/home = test_floor()
	var/turf/away = interest_far_from(home)
	TEST_ASSERT_NOTNULL(away, "the map has room for a turf four chunks away")
	var/list/probes = interest_probes(away, 2)
	var/obj/dq_interest_probe/elsewhere = probes[1]
	var/obj/dq_interest_probe/loading = probes[2]
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	interest_view_set("dq-test-viewer", home, null, world.view)
	refresh_mark(elsewhere, DEP_ALL)
	refresh_mark(loading, DEP_ALL)
	TEST_ASSERT_EQUAL(elsewhere.refresh_queued, DEP_PARKED, "deferred out of view")
	set_var(SSatoms, "initialize_depth", 1) // a map load is running
	init_open_begin(loading) // and it is still setting this atom up
	interest_view_set("dq-test-viewer", away, null, world.view)
	TEST_ASSERT_EQUAL(elsewhere.refresh_queued, 0, "a parked atom the load did not create draws when the player arrives, load or no load")
	TEST_ASSERT_EQUAL(loading.refresh_queued, DEP_PARKED, "an atom whose own init frame is open is left alone")
	init_open_end(loading)
	TEST_ASSERT_EQUAL(loading.refresh_queued, 0, "and draws when its frame ends")
	TEST_ASSERT(!init_open, "no frame is left open")
	interest_clean(probes)
