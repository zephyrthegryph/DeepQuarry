// Chunk interest (code/engine/change/interest.dm, doc/rewrite/proposals/demand_driven_refresh.md section 3): a mark of an atom nobody can see is deferred, the
// atom is drawn before a chunk it stands in is shown, and the observers (a view, a vis_contents holder) are set by events.

/// An object that draws a state of its own and watches nothing: the subject of the deferral tests. It can stand on any turf with others of its kind.
/obj/dq_interest_probe
	name = "interest probe"
	var/shown = 0

/// A probe in the utility band of the plating plane that hides under intact tiles the way a pipe does (hide_under_floor()): what a floor covers.
/obj/dq_interest_probe/underfloor
	plane = PLATING_PLANE
	layer = PIPES_LAYER

/obj/dq_interest_probe/underfloor/hides_under_flooring()
	return TRUE

/obj/dq_interest_probe/underfloor/hide(i)
	hide_under_floor(src, i)

/// A probe drawn in the same band that stays visible on intact tiles (an atmos device, a connector): nothing covers it.
/obj/dq_interest_probe/band_visible
	plane = PLATING_PLANE
	layer = PIPES_LAYER

/obj/dq_interest_probe/draw(datum/look/look)
	. = ..()
	look.state("probe")

/// The state every test of this file starts from: no observers, and the probe type a lazy one (its live outputs are its look).
/datum/unit_test/proc/interest_isolate()
	interest_private_queue()
	set_global(nameof(GLOB.interest_grid), list())
	set_global(nameof(GLOB.interest_holds), alist())
	set_global(nameof(GLOB.interest_visible), alist())
	set_global(nameof(GLOB.interest_sigs), alist())
	set_global(nameof(GLOB.interest_anchors), alist())
	set_global(nameof(GLOB.interest_owed), alist())
	set_global(nameof(GLOB.interest_scan_owed), GLOB.interest_scan_owed)
	set_global(nameof(GLOB.interest_scan_stale), GLOB.interest_scan_stale)
	set_global(nameof(GLOB.interest_scan_empty), GLOB.interest_scan_empty)
	set_global(nameof(GLOB.refresh_deferred), GLOB.refresh_deferred)
	set_global(nameof(GLOB.refresh_deferred_absorbed), GLOB.refresh_deferred_absorbed)
	set_global(nameof(GLOB.refresh_parked_near), GLOB.refresh_parked_near)
	set_global(nameof(GLOB.refresh_near_drawn), GLOB.refresh_near_drawn)
	set_global(nameof(GLOB.interest_chunks_entered), GLOB.interest_chunks_entered)
	set_global(nameof(GLOB.interest_drawn_now), GLOB.interest_drawn_now)
	set_global(nameof(GLOB.interest_covered), alist())
	set_global(nameof(GLOB.interest_prefetched), list())
	set_global(nameof(GLOB.interest_scan_pending), alist())
	set_global(nameof(GLOB.interest_scan_middle), alist())
	set_global(nameof(GLOB.interest_ring_scans), list())
	set_global(nameof(GLOB.interest_chunks_entered), GLOB.interest_chunks_entered)
	set_global(nameof(GLOB.interest_test_coverable), list())
	set_global(nameof(GLOB.interest_covers_raised), GLOB.interest_covers_raised)
	var/list/lazy = GLOB.type_look_lazy.Copy()
	lazy[/obj/dq_interest_probe] = TRUE
	lazy[/obj/dq_interest_probe/underfloor] = TRUE
	set_global(nameof(GLOB.interest_unperceivable_skipped), GLOB.interest_unperceivable_skipped)
	set_global(nameof(GLOB.type_look_lazy), lazy)

/// The test runs on a refresh queue of its own: the world's queue, the places recorded for it and its base (which boot or a budgeted drain may have left
/// partly drained) are put back as they were when the test ends, whatever it flushes.
/datum/unit_test/proc/interest_private_queue()
	set_global(nameof(GLOB.refresh_queue), list())
	set_global(nameof(GLOB.refresh_queue_at), alist())
	set_global(nameof(GLOB.refresh_queue_base), 0)

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
			interest_arrival_drain() // the drain's own timer: the ring is listed by the step and scanned here (interest_ring_scan())
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
	// The verdict of the table type is this test's own: a verdict read from the cache file (it is there from the second boot of a world on) judges a table's look
	// against its default, and a table smoothed to its neighbours does not fit it, so it would never park.
	var/list/from_file = GLOB.look_verdict_from_file.Copy()
	from_file -= /obj/structure/table
	set_global(nameof(GLOB.look_verdict_from_file), from_file)
	refresh_flush()
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	for(var/obj/structure/table/table as anything in tables)
		state_changed(table)
	for(var/obj/structure/table/table as anything in tables)
		TEST_ASSERT(table.refresh_queued & DEP_PARKED, "a table nobody sees stays parked however its neighbours are marked (queued [table.refresh_queued], lazy [GLOB.type_look_lazy[table.type]], covered [interest_covers(get_turf(table))], loc [table.loc], tguis [LAZYLEN(table.open_tguis)])")
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
	var/list/probes = interest_probes(away, 3)
	var/obj/dq_interest_probe/elsewhere = probes[1]
	var/obj/dq_interest_probe/loading = probes[2]
	var/obj/dq_interest_probe/dying = probes[3]
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
	// An atom deleted inside its own init frame leaves nothing behind: the open frame is a bit of the atom's own datum_flags, it holds nothing and needs
	// no slot, and its destroy clears it (a datum that takes its slot next is not taken for one still setting up).
	init_open_begin(dying)
	TEST_ASSERT(dying.datum_flags & DF_INIT_OPEN, "an open frame is recorded on the atom")
	var/dying_slot = dying.handle_slot
	qdel(dying)
	TEST_ASSERT(!(dying.datum_flags & DF_INIT_OPEN), "a deleted atom's open frame is gone with it")
	TEST_ASSERT(!dying_slot || isnull(init_open?[dying_slot]), "and nothing is left counted under its slot")
	init_open_end(dying) // the frame's own end finds nothing and does nothing
	probes -= dying
	TEST_ASSERT(!(loading.datum_flags & DF_INIT_OPEN), "no frame of the load's atom is left open")
	// A frame opened inside an open frame is counted: the atom stays held until the outer one ends.
	init_open_begin(loading)
	init_open_begin(loading)
	init_open_end(loading)
	TEST_ASSERT(loading.datum_flags & DF_INIT_OPEN, "a nested frame keeps the atom held when it ends")
	init_open_end(loading)
	TEST_ASSERT(!(loading.datum_flags & DF_INIT_OPEN), "and the outer frame's end lets it go")
	TEST_ASSERT(isnull(init_open?[loading.handle_slot]), "with nothing left counted")
	interest_clean(probes)

/// A deleted datum leaves the refresh queues: they hold datums by reference, and a deleted holder must not stay pinned by them.
/datum/unit_test/dq_refresh_queues_drop_deleted

/datum/unit_test/dq_refresh_queues_drop_deleted/Run()
	interest_private_queue()
	set_global(nameof(GLOB.refresh_push_queue), list())
	var/turf/T = test_floor()
	refresh_flush()
	var/obj/dq_interest_probe/probe = new(T)
	TEST_ASSERT(probe in GLOB.refresh_queue, "a new atom is queued for its first draw")
	GLOB.refresh_push_queue[probe] = TRUE
	qdel(probe)
	TEST_ASSERT(!(probe in GLOB.refresh_queue), "a deleted atom is not held by the refresh queue")
	TEST_ASSERT(!(probe in GLOB.refresh_push_queue), "nor by the push queue")
	refresh_forget(probe)
	TEST_ASSERT(!(probe in GLOB.refresh_queue), "forgetting it twice is harmless")
	refresh_flush()

/// A type with no push to run takes no place in the push queue for a selective push mark; one that has a push does.
/datum/unit_test/dq_refresh_push_queue_only_for_pushing_types

/datum/unit_test/dq_refresh_push_queue_only_for_pushing_types/Run()
	var/turf/T = test_floor()
	var/obj/dq_interest_probe/probe = allocate(/obj/dq_interest_probe, T)
	refresh_flush()
	TEST_ASSERT(!refresh_pushes(probe), "a probe has no push_to_rust()")
	var/before = length(GLOB.refresh_push_queue)
	refresh_mark(probe, DEP_PUSH)
	TEST_ASSERT_EQUAL(length(GLOB.refresh_push_queue), before, "so a selective push mark queues no push for it")
	refresh_flush()

/// Dropping a deleted datum from a long refresh queue takes one step, wherever its entry is: the front of a queue of hundreds is no worse than the end.
/datum/unit_test/dq_refresh_queue_forget_is_one_step

/datum/unit_test/dq_refresh_queue_forget_is_one_step/Run()
	interest_private_queue()
	var/turf/T = test_floor()
	refresh_flush()
	set_global(nameof(GLOB.refresh_forget_scans), GLOB.refresh_forget_scans)
	set_global(nameof(GLOB.refresh_forget_scan_steps), GLOB.refresh_forget_scan_steps)
	set_global(nameof(GLOB.refresh_forget_scan_max), 0)
	var/list/probes = list()
	for(var/i in 1 to 600)
		probes += new /obj/dq_interest_probe(T)
	TEST_ASSERT(length(GLOB.refresh_queue) >= 600, "the new atoms are queued for their first draw")
	var/obj/dq_interest_probe/first = probes[1]
	var/obj/dq_interest_probe/middle = probes[300]
	var/obj/dq_interest_probe/last = probes[600]
	for(var/obj/dq_interest_probe/doomed in list(first, middle, last))
		var/doomed_slot = slot_known(doomed)
		TEST_ASSERT(doomed_slot && !isnull(GLOB.refresh_queue_at[doomed_slot]), "a queued atom's place is recorded under its slot")
		qdel(doomed)
		TEST_ASSERT(!(doomed in GLOB.refresh_queue), "a deleted atom's entry is gone from the queue, wherever it was")
		TEST_ASSERT(isnull(GLOB.refresh_queue_at[doomed_slot]), "and its place is forgotten")
	TEST_ASSERT_EQUAL(GLOB.refresh_forget_scan_max, 1, "each drop took one step")
	refresh_flush()
	TEST_ASSERT(!length(GLOB.refresh_queue_at), "the drain gave back every place it consumed")
	for(var/obj/dq_interest_probe/probe in probes)
		qdel(probe)
	refresh_flush()

/// The debug audit samples turfs of the chunks observers see, and a draw still owed in one of them is reported and repaired (the falsifier of the
/// never-see-undrawn rule). Nothing is sampled when nobody sees anything.
/datum/unit_test/dq_interest_audit_samples_seen_chunks

/datum/unit_test/dq_interest_audit_samples_seen_chunks/Run()
	interest_isolate()
	set_global(nameof(GLOB.interest_audit_parked_in_view), GLOB.interest_audit_parked_in_view)
	set_global(nameof(GLOB.interest_audit_looked), GLOB.interest_audit_looked)
	set_global(nameof(GLOB.refresh_drift), GLOB.refresh_drift.Copy())
	var/turf/T = test_floor()
	TEST_ASSERT(!length(interest_sample_turfs(20)), "nobody sees anything: no turf is sampled")
	interest_view_set("dq-test-viewer", T, null, world.view)
	var/list/sampled = interest_sample_turfs(40)
	TEST_ASSERT(length(sampled) > 0, "a viewer's chunks are sampled")
	for(var/turf/S as anything in sampled)
		TEST_ASSERT(interest_sees(S), "and only the ones it sees")
	var/list/probes = interest_probes(T, 1)
	var/obj/dq_interest_probe/probe = probes[1]
	interest_test_park(probe) // a draw owed where a viewer looks: the state the rule forbids
	interest_audit_turf(T)
	TEST_ASSERT_EQUAL(probe.refresh_queued, 0, "the audit repaired it")
	TEST_ASSERT_EQUAL(GLOB.interest_audit_parked_in_view, 1, "and counted it")
	TEST_ASSERT(findtext(GLOB.refresh_drift[length(GLOB.refresh_drift)], "REFRESH PARKED IN VIEW"), "and reported it")
	interest_clean(probes)

/// A view jump owing more than one pass draws: the viewer is covered while its draws run nearest first over the passes, and the cover lifts with nothing
/// left owing in view. Nothing in a viewer's view owes a draw while it can see (interest_view_owing()).
/datum/unit_test/dq_interest_arrival_covers_until_drawn

/datum/unit_test/dq_interest_arrival_covers_until_drawn/Run()
	interest_isolate()
	var/turf/centre = test_floor()
	var/list/probes = list()
	for(var/step in 0 to 5)
		var/turf/T = locate(centre.x + step, centre.y, centre.z)
		if(T)
			probes += interest_probes(T, 8)
	TEST_ASSERT(length(probes) > INTEREST_ARRIVAL_MIN_STEP, "more probes than one pass always draws")
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	for(var/obj/dq_interest_probe/probe as anything in probes)
		refresh_mark(probe, DEP_ALL)
	GLOB.interest_test_coverable += "dq-test-viewer"
	set_global(nameof(GLOB.interest_arrival_step_max), 10)
	interest_view_set("dq-test-viewer", centre, null, world.view)
	TEST_ASSERT(!isnull(GLOB.interest_covered["dq-test-viewer"]), "the view jump covers the viewer while its draws are owed")
	var/drawn = 0
	var/nearest_owed = 1000
	var/farthest_drawn = -1
	for(var/obj/dq_interest_probe/probe as anything in probes)
		var/d = get_dist(probe, centre)
		if(probe.refresh_queued)
			nearest_owed = min(nearest_owed, d)
		else
			drawn++
			farthest_drawn = max(farthest_drawn, d)
	TEST_ASSERT_EQUAL(drawn, 10, "the first pass draws one pass's worth")
	TEST_ASSERT(farthest_drawn <= nearest_owed, "nearest the eye first")
	for(var/pass in 1 to length(probes))
		if(isnull(GLOB.interest_covered["dq-test-viewer"]))
			break
		interest_arrival_drain()
	TEST_ASSERT(isnull(GLOB.interest_covered["dq-test-viewer"]), "the cover lifts once nothing is owed")
	TEST_ASSERT(!length(interest_view_owing("dq-test-viewer")), "and nothing in view owes a draw while the viewer can see")
	interest_clean(probes)

/// A login (a view jump) does only what its first frame needs in the tick it happens: it scans the nearest chunks until the cover is needed and draws one pass's worth,
/// and leaves the rest of the visible chunks and the whole ring to the drain. The cover stays up until everything in view is drawn, and everything is drawn in the end.
/datum/unit_test/dq_interest_login_work_is_bounded_and_complete

/datum/unit_test/dq_interest_login_work_is_bounded_and_complete/Run()
	interest_isolate()
	var/turf/floor = test_floor()
	var/turf/centre = locate(round((floor.x - 1) / INTEREST_CHUNK) * INTEREST_CHUNK + INTEREST_CHUNK, floor.y, floor.z) // a chunk's last column: its window spans two chunks
	TEST_ASSERT_NOTNULL(centre, "the map has that turf")
	var/list/visible = list()
	var/list/held = interest_view_keys(centre, world.view, visible)
	var/centre_chunk = INTEREST_KEY(centre.z, INTEREST_CHUNK_OF(centre.x), INTEREST_CHUNK_OF(centre.y))
	var/other_key = 0
	var/ring_key = 0
	for(var/key in visible)
		if(key != centre_chunk)
			other_key = key
			break
	for(var/key in held)
		if(!(key in visible))
			ring_key = key
			break
	TEST_ASSERT(other_key && ring_key, "the view spans two chunks and has a ring beyond them")
	var/turf/second = locate(round((other_key % 1048576) / 1024) * INTEREST_CHUNK + 8, (other_key % 1024) * INTEREST_CHUNK + 8, centre.z)
	var/turf/ring = locate(round((ring_key % 1048576) / 1024) * INTEREST_CHUNK + 8, (ring_key % 1024) * INTEREST_CHUNK + 8, centre.z)
	TEST_ASSERT(second && ring, "the map has those turfs")
	var/list/near = interest_probes(centre, 40) + interest_probes(second, 40)
	var/list/ring_probes = interest_probes(ring, 10)
	var/list/probes = near + ring_probes
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	for(var/obj/dq_interest_probe/probe as anything in probes)
		refresh_mark(probe, DEP_ALL)
	GLOB.interest_test_coverable += "dq-test-viewer"
	var/scanned_before = GLOB.interest_chunks_entered
	interest_view_set("dq-test-viewer", centre, null, world.view)
	TEST_ASSERT(!isnull(GLOB.interest_covered["dq-test-viewer"]), "the login is covered")
	TEST_ASSERT(GLOB.interest_chunks_entered - scanned_before <= 2, "the login tick scanned only the nearest chunk(s), not the whole view and ring ([GLOB.interest_chunks_entered - scanned_before])")
	TEST_ASSERT(length(GLOB.interest_scan_pending["dq-test-viewer"]) > 0, "the rest of the visible chunks wait for the drain")
	TEST_ASSERT(length(GLOB.interest_ring_scans) > 0, "and so does the ring")
	var/drawn_now = 0
	for(var/obj/dq_interest_probe/probe as anything in near)
		if(!probe.refresh_queued)
			drawn_now++
	TEST_ASSERT(drawn_now <= INTEREST_ARRIVAL_MIN_STEP, "the login tick drew no more than one pass ([drawn_now])")
	for(var/obj/dq_interest_probe/probe as anything in ring_probes)
		TEST_ASSERT(probe.refresh_queued, "nothing in the ring was touched in the login tick")
	for(var/pass in 1 to 300)
		interest_arrival_drain()
		var/near_owing = 0
		for(var/obj/dq_interest_probe/probe as anything in near)
			if(probe.refresh_queued)
				near_owing++
		if(isnull(GLOB.interest_covered["dq-test-viewer"]))
			TEST_ASSERT_EQUAL(near_owing, 0, "the cover lifted with part of the view still undrawn")
			TEST_ASSERT(!length(interest_view_owing("dq-test-viewer")), "and nothing in view owes a draw once it lifted")
			break
		else if(!near_owing && !length(GLOB.interest_scan_pending["dq-test-viewer"]))
			TEST_ASSERT(FALSE, "the view is drawn and nothing is left to scan, but the cover stayed")
	TEST_ASSERT(isnull(GLOB.interest_covered["dq-test-viewer"]), "the cover lifts")
	for(var/pass in 1 to 300)
		if(!length(GLOB.interest_prefetched) && !length(GLOB.interest_ring_scans))
			break
		interest_arrival_drain()
	TEST_ASSERT(!length(GLOB.interest_ring_scans) && !length(GLOB.interest_prefetched), "the drain finished the ring")
	for(var/obj/dq_interest_probe/probe as anything in probes)
		TEST_ASSERT_EQUAL(probe.refresh_queued, 0, "everything was drawn in the end")
	interest_clean(probes)

/// A walker crossing a chunk edge keeps most of its old view: what the new chunks still owe is drawn at once and the screen is never covered (the black flash
/// a running player saw every chunk edge). Only a view that kept nothing of the old one is a jump.
/datum/unit_test/dq_interest_walker_is_not_covered

/datum/unit_test/dq_interest_walker_is_not_covered/Run()
	interest_isolate()
	var/turf/base = test_floor()
	var/start_x = round((base.x - 1) / INTEREST_CHUNK) * INTEREST_CHUNK + 1
	var/turf/home = locate(start_x, base.y, base.z)
	var/turf/stepped = locate(start_x + 9, base.y, base.z) // its window reaches the next chunk and keeps the one it held
	var/turf/edge = locate(start_x + INTEREST_CHUNK, base.y, base.z)
	TEST_ASSERT(home && stepped && edge, "the map has room for two neighbouring chunks")
	var/list/probes = interest_probes(edge, INTEREST_ARRIVAL_MIN_STEP + 8)
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	for(var/obj/dq_interest_probe/probe as anything in probes)
		refresh_mark(probe, DEP_ALL)
	GLOB.interest_test_coverable += "dq-test-walker"
	interest_view_set("dq-test-walker", home, null, world.view)
	GLOB.interest_covered -= "dq-test-walker" // the first view is a jump; this test is about the step after it
	var/raised = GLOB.interest_covers_raised
	interest_view_set("dq-test-walker", stepped, null, world.view)
	TEST_ASSERT(isnull(GLOB.interest_covered["dq-test-walker"]), "a step across a chunk edge does not cover the viewer")
	TEST_ASSERT_EQUAL(GLOB.interest_covers_raised, raised, "and raises no cover")
	TEST_ASSERT(!length(interest_view_owing("dq-test-walker")), "what the new chunk owed is drawn when it comes into view")
	interest_clean(probes)

/// A walker's edge owing more than one tick's batch (INTEREST_WALKER_NOW_MAX) draws the nearest of it now, queues the rest at the front of the prefetch queue and
/// raises no cover; the drain then works the rest down over its passes, nearest first, until nothing in view owes a draw. A small batch (the test above) is all drawn now.
/datum/unit_test/dq_interest_walker_edge_defers_past_budget

/datum/unit_test/dq_interest_walker_edge_defers_past_budget/Run()
	interest_isolate()
	set_global(nameof(GLOB.interest_walker_deferred), GLOB.interest_walker_deferred)
	var/turf/base = test_floor()
	var/start_x = round((base.x - 1) / INTEREST_CHUNK) * INTEREST_CHUNK + 1
	var/turf/home = locate(start_x, base.y, base.z)
	var/turf/stepped = locate(start_x + 9, base.y, base.z)
	var/turf/edge = locate(start_x + INTEREST_CHUNK, base.y, base.z)
	var/turf/far_corner = locate(start_x + 2 * INTEREST_CHUNK - 1, base.y, base.z) // the far end of the new chunk: the farthest from the eye
	TEST_ASSERT(home && stepped && edge && far_corner, "the map has room for two neighbouring chunks")
	var/list/near = interest_probes(edge, INTEREST_WALKER_NOW_MAX + 20)
	var/list/far = interest_probes(far_corner, 5)
	var/list/probes = near + far
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	for(var/obj/dq_interest_probe/probe as anything in probes)
		refresh_mark(probe, DEP_ALL)
	GLOB.interest_test_coverable += "dq-test-walker"
	interest_view_set("dq-test-walker", home, null, world.view)
	GLOB.interest_covered -= "dq-test-walker" // the first view is a jump; this test is about the step after it
	var/raised = GLOB.interest_covers_raised
	var/deferred_before = GLOB.interest_walker_deferred
	interest_view_set("dq-test-walker", stepped, null, world.view)
	TEST_ASSERT(isnull(GLOB.interest_covered["dq-test-walker"]), "a walker's edge is never covered, however much it owes")
	TEST_ASSERT_EQUAL(GLOB.interest_covers_raised, raised, "and raises no cover")
	var/owing = 0
	var/far_owing = 0
	for(var/obj/dq_interest_probe/probe as anything in probes)
		if(probe.refresh_queued)
			owing++
			if(probe in far)
				far_owing++
	TEST_ASSERT_EQUAL(owing, length(probes) - INTEREST_WALKER_NOW_MAX, "only one tick's batch was drawn now")
	TEST_ASSERT_EQUAL(far_owing, length(far), "nearest the eye first: the farthest ones are the ones left")
	TEST_ASSERT_EQUAL(GLOB.interest_walker_deferred - deferred_before, owing, "the deferred draws are counted")
	TEST_ASSERT(length(GLOB.interest_prefetched) >= owing, "and wait in the queue the drain works")
	set_global(nameof(GLOB.interest_arrival_step_max), 10)
	var/passes = 0
	for(var/pass in 1 to 100)
		if(!length(GLOB.interest_prefetched))
			break
		interest_arrival_drain()
		passes++
	TEST_ASSERT(passes >= 2, "the drain spread them over passes ([passes])")
	TEST_ASSERT_EQUAL(length(GLOB.interest_prefetched), 0, "nothing stays queued")
	for(var/obj/dq_interest_probe/probe as anything in probes)
		TEST_ASSERT_EQUAL(probe.refresh_queued, 0, "every deferred draw ran")
	TEST_ASSERT(!length(interest_view_owing("dq-test-walker")), "and nothing in view owes a draw")
	TEST_ASSERT(isnull(GLOB.interest_covered["dq-test-walker"]), "no cover came up while it drained")
	interest_clean(probes)

/// A walker's edge spends its draw budget on real draws only: owed items that need no draw (here, nothing can perceive them) sit nearest the eye and do not use it up,
/// so the full batch of real draws still runs now behind them, and the real ones past the batch are the ones deferred.
/datum/unit_test/dq_interest_walker_edge_budget_counts_real_draws

/datum/unit_test/dq_interest_walker_edge_budget_counts_real_draws/Run()
	interest_isolate()
	set_global(nameof(GLOB.interest_walker_deferred), GLOB.interest_walker_deferred)
	var/turf/base = test_floor()
	var/start_x = round((base.x - 1) / INTEREST_CHUNK) * INTEREST_CHUNK + 1
	var/turf/home = locate(start_x, base.y, base.z)
	var/turf/stepped = locate(start_x + 9, base.y, base.z)
	var/turf/edge = locate(start_x + INTEREST_CHUNK, base.y, base.z)
	var/turf/far_corner = locate(start_x + 2 * INTEREST_CHUNK - 1, base.y, base.z)
	TEST_ASSERT(home && stepped && edge && far_corner, "the map has room for two neighbouring chunks")
	var/list/clean = interest_probes(edge, INTEREST_WALKER_NOW_MAX + 10) // nearest the eye, and none of them can be drawn
	var/list/real = interest_probes(far_corner, INTEREST_WALKER_NOW_MAX + 2)
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	for(var/obj/dq_interest_probe/probe as anything in clean)
		probe.set_invisibility(INVISIBILITY_ABSTRACT)
		rx_of(probe).look_key = null
		interest_test_park(probe)
	for(var/obj/dq_interest_probe/probe as anything in real)
		refresh_mark(probe, DEP_ALL)
	GLOB.interest_test_coverable += "dq-test-walker"
	interest_view_set("dq-test-walker", home, null, world.view)
	GLOB.interest_covered -= "dq-test-walker"
	var/raised = GLOB.interest_covers_raised
	var/deferred_before = GLOB.interest_walker_deferred
	interest_view_set("dq-test-walker", stepped, null, world.view)
	TEST_ASSERT_EQUAL(GLOB.interest_covers_raised, raised, "a walker's edge raises no cover")
	var/owing = 0
	for(var/obj/dq_interest_probe/probe as anything in real)
		if(probe.refresh_queued)
			owing++
	TEST_ASSERT_EQUAL(owing, length(real) - INTEREST_WALKER_NOW_MAX, "the full batch of real draws ran now, behind the items that needed none")
	TEST_ASSERT_EQUAL(GLOB.interest_walker_deferred - deferred_before, owing, "only the real draws past the batch were deferred")
	interest_clean(clean + real)

/// A viewer that cannot be covered (no client: a camera screen) gets everything in view drawn at once: it never sees an owed draw.
/datum/unit_test/dq_interest_uncoverable_view_draws_at_once

/datum/unit_test/dq_interest_uncoverable_view_draws_at_once/Run()
	interest_isolate()
	var/turf/centre = test_floor()
	var/list/probes = interest_probes(centre, 50)
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	for(var/obj/dq_interest_probe/probe as anything in probes)
		refresh_mark(probe, DEP_ALL)
	set_global(nameof(GLOB.interest_arrival_step_max), 10)
	interest_view_set("dq-test-camera", centre, null, world.view)
	TEST_ASSERT(isnull(GLOB.interest_covered["dq-test-camera"]), "no client: no cover")
	TEST_ASSERT(!length(interest_view_owing("dq-test-camera")), "and nothing in its view owes a draw")
	interest_clean(probes)

/// Nothing is drawn that no viewer could perceive, and a reveal draws it: three kinds of cover. A probe under an intact floor (the floor's cover hides
/// its layer band), one in a closed locker (contained), and one past every viewer's sight stay owing while the viewer looks; prying the tiles up, taking
/// the probe out, and dropping its invisibility each draw it.
/datum/unit_test/dq_interest_unperceivable_waits_for_reveal

/datum/unit_test/dq_interest_unperceivable_waits_for_reveal/Run()
	interest_isolate()
	var/turf/simulated/floor/floor = test_floor()
	TEST_ASSERT(istype(floor) && !floor.is_plating(), "the test floor has tiles on")
	var/obj/dq_interest_probe/underfloor/piped = allocate(/obj/dq_interest_probe/underfloor, floor)
	var/obj/structure/closet/locker = allocate(/obj/structure/closet, floor)
	var/obj/dq_interest_probe/boxed = allocate(/obj/dq_interest_probe, locker)
	var/obj/dq_interest_probe/unseen = allocate(/obj/dq_interest_probe, floor)
	floor.levelupdate() // the tiles hide the piped probe, as they hide a pipe laid under them
	refresh_flush()
	TEST_ASSERT(piped.invisibility >= INVISIBILITY_ABSTRACT, "the piped probe is hidden under the tiles")
	unseen.set_invisibility(INVISIBILITY_ABSTRACT)
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	for(var/obj/dq_interest_probe/probe as anything in list(piped, boxed, unseen))
		rx_of(probe).look_key = null
		interest_test_park(probe) // owes its first draw, parked as the boot leaves it
	var/skipped = GLOB.interest_unperceivable_skipped
	interest_view_set("dq-test-viewer", floor, null, world.view)
	refresh_flush()
	for(var/obj/dq_interest_probe/probe as anything in list(piped, boxed, unseen))
		TEST_ASSERT(probe.refresh_queued & DEP_PARKED, "[probe] ([probe.type]) nobody could perceive is not drawn when its chunk is seen")
	TEST_ASSERT(GLOB.interest_unperceivable_skipped > skipped, "and the skips are counted")
	TEST_ASSERT(!length(interest_view_owing("dq-test-viewer")), "nothing a viewer could perceive is left owing")
	// The reveals: the tiles come up, the probe leaves its locker, its invisibility drops.
	var/datum/decl/flooring/tiles = floor.flooring
	floor.make_plating()
	boxed.forceMove(floor)
	unseen.set_invisibility(0)
	refresh_flush()
	for(var/obj/dq_interest_probe/probe as anything in list(piped, boxed, unseen))
		TEST_ASSERT(!probe.refresh_queued, "[probe] ([probe.type]) draws when it is revealed")
		TEST_ASSERT(!isnull(probe.rx?.look_key), "and has a look")
	floor.install_flooring(tiles) // the shared test floor gets its tiles back

/// The floor covers only what it hides today: a thing drawn in the utility band that stays visible on intact tiles (an atmos device, a connector) is drawn
/// when its chunk is seen, like anything else in view.
/datum/unit_test/dq_interest_cover_spares_visible_band

/datum/unit_test/dq_interest_cover_spares_visible_band/Run()
	interest_isolate()
	var/turf/simulated/floor/floor = test_floor()
	TEST_ASSERT(istype(floor) && !floor.is_plating(), "the test floor has tiles on")
	var/obj/dq_interest_probe/band = allocate(/obj/dq_interest_probe/band_visible, floor)
	refresh_flush()
	TEST_ASSERT(!floor.cover_hides(band), "a visible thing in the band is not covered")
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	rx_of(band).look_key = null
	interest_test_park(band)
	interest_view_set("dq-test-viewer", floor, null, world.view)
	refresh_flush()
	TEST_ASSERT(!band.refresh_queued, "it draws when its chunk is seen")
	TEST_ASSERT(!isnull(band.rx?.look_key), "and has a look")

/// Over the whole map, no atom visible today (below abstract invisibility) is reported covered by its turf. Run with --full-map for the station.
/datum/unit_test/dq_interest_cover_hides_nothing_visible

/datum/unit_test/dq_interest_cover_hides_nothing_visible/Run()
	var/checked = 0
	var/list/wrong = list()
	for(var/turf/T in world)
		for(var/atom/movable/A as anything in T.contents)
			if(A.invisibility >= INVISIBILITY_ABSTRACT)
				continue
			checked++
			if(T.cover_hides(A) && length(wrong) < 20)
				wrong += "[A.type] at [T.x],[T.y],[T.z]"
	log_world("dq_interest_cover_hides_nothing_visible: [checked] visible atoms checked, [length(wrong)] covered")
	TEST_ASSERT(!length(wrong), "visible atoms reported covered: [jointext(wrong, "; ")]")

/// Leaves `A` parked, owing its first draw, as the boot leaves a held atom (the owed index lists it, as every parking does).
/datum/unit_test/proc/interest_test_park(atom/A)
	A.refresh_queued = DEP_PARKED
	interest_owed_note(A)

/// What a chunk owes by walking its turfs and contents, the way the scan did before the owed index: the atoms with refresh_queued set. The check of the index.
/datum/unit_test/proc/interest_owed_walk(z, cx, cy)
	. = list()
	var/x0 = cx * INTEREST_CHUNK + 1
	var/y0 = cy * INTEREST_CHUNK + 1
	for(var/turf/T as anything in block(locate(x0, y0, z), locate(min(world.maxx, x0 + INTEREST_CHUNK - 1), min(world.maxy, y0 + INTEREST_CHUNK - 1), z)))
		if(interest_owed_real(T))
			. += T
		for(var/atom/movable/A as anything in T.contents)
			if(interest_owed_real(A))
				. += A

/// A chunk scan reads the owed set only: it finds exactly the atoms a walk of the chunk finds, visits no other atom (the counter says how many).
/datum/unit_test/dq_interest_scan_visits_only_owed

/datum/unit_test/dq_interest_scan_visits_only_owed/Run()
	interest_isolate()
	var/turf/home = test_floor()
	var/z = home.z
	var/cx = INTEREST_CHUNK_OF(home.x)
	var/cy = INTEREST_CHUNK_OF(home.y)
	var/list/probes = interest_probes(home, 6)
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	for(var/obj/dq_interest_probe/probe as anything in probes)
		refresh_mark(probe, DEP_ALL)
	var/list/walked = interest_owed_walk(z, cx, cy)
	var/owed_before = GLOB.interest_scan_owed
	var/stale_before = GLOB.interest_scan_stale
	var/list/found = list()
	var/count = interest_collect_owed(found, z, cx, cy, cx, cy)
	TEST_ASSERT_EQUAL(count, length(walked), "the scan finds what a walk of the chunk finds")
	TEST_ASSERT_EQUAL(GLOB.interest_scan_owed - owed_before, count, "and the counter says it visited only those")
	TEST_ASSERT_EQUAL(GLOB.interest_scan_stale - stale_before, 0, "with no stale entry in the index")
	for(var/obj/dq_interest_probe/probe as anything in probes)
		TEST_ASSERT(handle_of(probe) in found, "every parked probe is found")
	// A chunk nobody owes anything in is not walked at all.
	var/turf/away = interest_far_from(home)
	if(away)
		var/empty_before = GLOB.interest_scan_empty
		var/list/none = list()
		TEST_ASSERT_EQUAL(interest_collect_owed(none, away.z, INTEREST_CHUNK_OF(away.x), INTEREST_CHUNK_OF(away.y), cx, cy), 0, "a chunk that owes nothing yields nothing")
		TEST_ASSERT_EQUAL(GLOB.interest_scan_empty - empty_before, 1, "and is counted empty, never walked")
	log_world("dq_interest_scan_visits_only_owed: [count] owed found in a chunk of [INTEREST_CHUNK * INTEREST_CHUNK] turfs")
	interest_clean(probes)

/// A parked atom that moves to another chunk leaves the old chunk's set and is found by the new chunk's scan.
/datum/unit_test/dq_interest_owed_follows_moves

/datum/unit_test/dq_interest_owed_follows_moves/Run()
	interest_isolate()
	var/turf/home = test_floor()
	var/turf/away = interest_far_from(home)
	TEST_ASSERT_NOTNULL(away, "the map has room for a turf four chunks away")
	var/list/probes = interest_probes(home, 1)
	var/obj/dq_interest_probe/probe = probes[1]
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	refresh_mark(probe, DEP_ALL)
	var/list/old_found = list()
	TEST_ASSERT_EQUAL(interest_collect_owed(old_found, home.z, INTEREST_CHUNK_OF(home.x), INTEREST_CHUNK_OF(home.y), 0, 0), 1, "found where it parked")
	probe.forceMove(away)
	TEST_ASSERT_EQUAL(probe.refresh_queued, DEP_PARKED, "still parked after the move")
	var/list/gone = list()
	TEST_ASSERT_EQUAL(interest_collect_owed(gone, home.z, INTEREST_CHUNK_OF(home.x), INTEREST_CHUNK_OF(home.y), 0, 0), 0, "the old chunk no longer lists it")
	var/list/arrived = list()
	TEST_ASSERT_EQUAL(interest_collect_owed(arrived, away.z, INTEREST_CHUNK_OF(away.x), INTEREST_CHUNK_OF(away.y), 0, 0), 1, "the new chunk's scan finds it")
	TEST_ASSERT(handle_of(probe) in arrived, "and it is the probe")
	// Into a container it stands in no chunk; out again it is listed again.
	var/obj/structure/closet/box = allocate(/obj/structure/closet, away)
	probe.forceMove(box)
	var/list/boxed = list()
	interest_collect_owed(boxed, away.z, INTEREST_CHUNK_OF(away.x), INTEREST_CHUNK_OF(away.y), 0, 0)
	TEST_ASSERT(!(handle_of(probe) in boxed), "inside a container it stands in no chunk")
	probe.forceMove(away)
	var/list/out = list()
	interest_collect_owed(out, away.z, INTEREST_CHUNK_OF(away.x), INTEREST_CHUNK_OF(away.y), 0, 0)
	TEST_ASSERT(handle_of(probe) in out, "back on the turf it is listed again")
	// The view arriving where it moved draws it, and nothing in view owes.
	interest_view_set("dq-test-viewer", away, null, world.view)
	TEST_ASSERT_EQUAL(probe.refresh_queued, 0, "the chunk became visible: drawn")
	TEST_ASSERT(!length(interest_view_owing("dq-test-viewer")), "nothing in view owes a draw")
	interest_clean(probes)

/// A mark on a parked atom keeps it parked and owed (the redraw is absorbed, nothing is woken); a qdel takes it out of the index.
/datum/unit_test/dq_interest_owed_marks_and_qdel

/datum/unit_test/dq_interest_owed_marks_and_qdel/Run()
	interest_isolate()
	var/turf/home = test_floor()
	var/z = home.z
	var/cx = INTEREST_CHUNK_OF(home.x)
	var/cy = INTEREST_CHUNK_OF(home.y)
	var/list/probes = interest_probes(home, 3)
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	for(var/obj/dq_interest_probe/probe as anything in probes)
		refresh_mark(probe, DEP_ALL)
	var/woken_before = GLOB.refresh_parked_woken
	for(var/n in 1 to 5)
		for(var/obj/dq_interest_probe/probe as anything in probes)
			refresh_mark(probe, DEP_DRAW)
	TEST_ASSERT_EQUAL(GLOB.refresh_parked_woken, woken_before, "marks on parked atoms woke none")
	for(var/obj/dq_interest_probe/probe as anything in probes)
		TEST_ASSERT_EQUAL(probe.refresh_queued, DEP_PARKED, "a mark of a parked atom leaves it parked")
	var/list/found = list()
	TEST_ASSERT_EQUAL(interest_collect_owed(found, z, cx, cy, cx, cy), 3, "and still owed: the scan lists all three")
	var/obj/dq_interest_probe/gone = probes[1]
	var/gone_handle = handle_of(gone)
	qdel(gone)
	refresh_flush()
	var/list/after = list()
	TEST_ASSERT_EQUAL(interest_collect_owed(after, z, cx, cy, cx, cy), 2, "a qdeleted atom is out of the scan")
	TEST_ASSERT(!(gone_handle in after), "and it is not the one listed")
	var/alist/set = GLOB.interest_owed[INTEREST_KEY(z, cx, cy)]
	TEST_ASSERT(!(set && set[gone_handle]), "the index no longer holds its handle")
	probes -= gone
	interest_clean(probes)

/// The index is checked against the walk over every chunk of the test map: nothing that owes a draw is missing from its chunk's set. Run with --full-map for the station.
/datum/unit_test/dq_interest_owed_index_matches_walk

/datum/unit_test/dq_interest_owed_index_matches_walk/Run()
	var/checked = 0
	var/missing = 0
	var/list/examples = list()
	for(var/z in 1 to world.maxz)
		for(var/cx in 0 to INTEREST_CHUNK_OF(world.maxx))
			for(var/cy in 0 to INTEREST_CHUNK_OF(world.maxy))
				var/list/walked = interest_owed_walk(z, cx, cy)
				if(!length(walked))
					continue
				var/alist/set = GLOB.interest_owed[INTEREST_KEY(z, cx, cy)]
				for(var/atom/A as anything in walked)
					checked++
					var/handle = isturf(A) ? slot_of_turf(A) : handle_of(A)
					if(!(set && set[handle]))
						missing++
						if(length(examples) < 10)
							examples += "[A.type] at [A.x],[A.y],[A.z] queued [A.refresh_queued]"
	log_world("dq_interest_owed_index_matches_walk: [checked] owing atoms checked, [missing] missing from the index [jointext(examples, "; ")]")
	TEST_ASSERT_EQUAL(missing, 0, "every atom that owes a draw is in its chunk's owed set: [jointext(examples, "; ")]")

/// Does `A` owe a draw that matters? Not one that is only the creation mark of an atom nothing derives for, nor a boot-held atom of an empty default look (it owes
/// nothing: interest_audit_atom(), interest_draw_now()); the owed index lists neither.
/datum/unit_test/proc/interest_owed_real(atom/A)
	if(!(A.refresh_queued & ~DEP_CREATED))
		return FALSE
	if(A.refresh_queued == DEP_PARKED && GLOB.type_look_stamp[A.type] && look_verdict_fits(A))
		return FALSE
	return TRUE

/// A parked atom of a lazy type stays parked under marks whatever its look became since (a verdict read from a file judged its look at creation only), and so does one
/// written under construction: neither wakes into the queue. One in a held chunk is still queued by a mark.
/datum/unit_test/dq_interest_parked_marks_do_not_wake

/datum/unit_test/dq_interest_parked_marks_do_not_wake/Run()
	interest_isolate()
	var/turf/home = test_floor()
	var/list/probes = interest_probes(home, 2)
	var/obj/dq_interest_probe/changed = probes[1]
	var/obj/dq_interest_probe/building = probes[2]
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	refresh_mark(changed, DEP_ALL)
	refresh_mark(building, DEP_ALL)
	TEST_ASSERT_EQUAL(changed.refresh_queued, DEP_PARKED, "parked while it looked as its type does")
	var/list/from_file = GLOB.look_verdict_from_file.Copy()
	from_file[/obj/dq_interest_probe] = TRUE
	set_global(nameof(GLOB.look_verdict_from_file), from_file)
	changed.set_icon_state("changed-since")
	TEST_ASSERT(!look_verdict_fits(changed), "its look no longer fits the verdict a file gave its type")
	var/woken_before = GLOB.refresh_parked_woken
	var/queued_before = length(GLOB.refresh_queue)
	refresh_mark(changed, DEP_DRAW)
	TEST_ASSERT_EQUAL(changed.refresh_queued, DEP_PARKED, "a mark of a parked atom whose look changed leaves it parked")
	building.datum_flags |= DF_CONSTRUCTING
	set_global(nameof(GLOB.construction_parked_absorbed), GLOB.construction_parked_absorbed)
	var/absorbed_before = GLOB.construction_parked_absorbed
	construction_note(building, null)
	building.datum_flags &= ~DF_CONSTRUCTING
	TEST_ASSERT_EQUAL(building.refresh_queued, DEP_PARKED, "a write under construction leaves a parked atom parked")
	TEST_ASSERT_EQUAL(GLOB.construction_parked_absorbed - absorbed_before, 1, "and is counted")
	TEST_ASSERT_EQUAL(GLOB.refresh_parked_woken, woken_before, "nothing was woken")
	TEST_ASSERT_EQUAL(length(GLOB.refresh_queue), queued_before, "and nothing queued")
	var/list/found = list()
	interest_collect_owed(found, home.z, INTEREST_CHUNK_OF(home.x), INTEREST_CHUNK_OF(home.y), 0, 0)
	TEST_ASSERT(handle_of(changed) in found, "both still owe, in the chunk's set")
	TEST_ASSERT(handle_of(building) in found, "(the second too)")
	// A viewer arriving draws them: nothing in view is left undrawn.
	interest_view_set("dq-test-viewer", home, null, world.view)
	TEST_ASSERT_EQUAL(changed.refresh_queued, 0, "the chunk became visible: the changed one is drawn")
	TEST_ASSERT_EQUAL(building.refresh_queued, 0, "and the one built under construction")
	TEST_ASSERT(!length(interest_view_owing("dq-test-viewer")), "nothing in view owes a draw")
	// Under a viewer's eye a mark still queues.
	refresh_mark(changed, DEP_DRAW)
	TEST_ASSERT(changed.refresh_queued && !(changed.refresh_queued & DEP_PARKED), "in a held chunk a mark queues the atom")
	interest_clean(probes)

/// The chunk scan as it was before the owed index (kept here to time the two against each other): every turf of the chunk and everything standing on it is looked at.
/datum/unit_test/proc/interest_collect_owed_walked(list/into, z, cx, cy, mid_cx, mid_cy)
	. = 0
	var/x0 = cx * INTEREST_CHUNK + 1
	var/y0 = cy * INTEREST_CHUNK + 1
	if(x0 > world.maxx || y0 > world.maxy)
		return
	var/turf/low = locate(x0, y0, z)
	var/turf/high = locate(min(world.maxx, x0 + INTEREST_CHUNK - 1), min(world.maxy, y0 + INTEREST_CHUNK - 1), z)
	var/mid_x = mid_cx * INTEREST_CHUNK + INTEREST_CHUNK / 2
	var/mid_y = mid_cy * INTEREST_CHUNK + INTEREST_CHUNK / 2
	var/list/owed = list()
	for(var/turf/T as anything in block(low, high))
		var/owes = !!T.refresh_queued
		if(!owes)
			FOR_CONTENTS(var/atom/movable/A as anything, T)
				if(A.refresh_queued)
					owes = TRUE
					break
		if(owes)
			owed[T] = (T.x - mid_x) ** 2 + (T.y - mid_y) ** 2
	if(!length(owed))
		return
	owed = sortTim(owed, GLOBAL_PROC_REF(cmp_numeric_asc), associative = TRUE)
	for(var/turf/T as anything in owed)
		if(T.refresh_queued)
			into += handle_of(T)
			.++
		FOR_CONTENTS(var/atom/movable/A as anything, T)
			if(A.refresh_queued)
				into += handle_of(A)
				.++

/// Times the walking scan against the owed index over every chunk that owes a draw (run with --full-map for the station): the counts they find, and the milliseconds
/// each takes per chunk (median, 95th percentile and the sum; a chunk whose clock read crosses a tick is dropped, its reading would be meaningless).
/datum/unit_test/dq_interest_scan_cost_vs_walk

/datum/unit_test/dq_interest_scan_cost_vs_walk/Run()
	var/chunks = 0
	var/walked_found = 0
	var/index_found = 0
	var/list/walked_ms = list()
	var/list/index_ms = list()
	for(var/z in 1 to world.maxz)
		for(var/cx in 0 to INTEREST_CHUNK_OF(world.maxx))
			for(var/cy in 0 to INTEREST_CHUNK_OF(world.maxy))
				var/list/via_walk = list()
				var/started = TICK_USAGE_REAL
				var/found = interest_collect_owed_walked(via_walk, z, cx, cy, cx, cy)
				var/walk_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
				if(!found)
					continue
				chunks++
				walked_found += found
				var/list/via_index = list()
				started = TICK_USAGE_REAL
				var/indexed = interest_collect_owed(via_index, z, cx, cy, cx, cy)
				var/via_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
				index_found += indexed
				if(walk_ms > 0 && via_ms >= 0 && walk_ms < 500 && via_ms < 500)
					walked_ms += walk_ms
					index_ms += via_ms
	walked_ms = sortTim(walked_ms, GLOBAL_PROC_REF(cmp_numeric_asc))
	index_ms = sortTim(index_ms, GLOBAL_PROC_REF(cmp_numeric_asc))
	var/walk_sum = 0
	for(var/ms in walked_ms)
		walk_sum += ms
	var/index_sum = 0
	for(var/ms in index_ms)
		index_sum += ms
	var/n = length(walked_ms)
	if(n)
		log_world("dq_interest_scan_cost_vs_walk: [chunks] chunks owing ([n] timed); walking scan found [walked_found], median [round(walked_ms[round(n / 2) + 1], 0.01)] ms, p95 [round(walked_ms[min(n, round(n * 0.95) + 1)], 0.01)] ms, max [round(walked_ms[n], 0.01)] ms, sum [round(walk_sum, 0.1)] ms; owed index found [index_found], median [round(index_ms[round(n / 2) + 1], 0.01)] ms, p95 [round(index_ms[min(n, round(n * 0.95) + 1)], 0.01)] ms, max [round(index_ms[n], 0.01)] ms, sum [round(index_sum, 0.1)] ms")
	TEST_ASSERT(index_found <= walked_found, "the index never lists more than the walk finds")

/// A parked unseen atom's move publishes nothing (no loc or look-dir change reaches the reaction layer); it stays parked and owed, and one moved to a watched chunk draws.
/datum/unit_test/dq_interest_parked_move_is_quiet

/datum/unit_test/dq_interest_parked_move_is_quiet/Run()
	interest_isolate()
	var/turf/home = test_floor()
	var/turf/away = interest_far_from(home)
	TEST_ASSERT_NOTNULL(away, "the map has room for a turf four chunks away")
	var/list/probes = interest_probes(away, 1)
	var/obj/dq_interest_probe/probe = probes[1]
	set_global(nameof(GLOB.interest_defer_marks), TRUE)
	set_global(nameof(GLOB.interest_parked_move_spared), GLOB.interest_parked_move_spared)
	refresh_mark(probe, DEP_ALL)
	TEST_ASSERT_EQUAL(probe.refresh_queued, DEP_PARKED, "parked out of view")
	var/spared_before = GLOB.interest_parked_move_spared
	var/marks_before = GLOB.refresh_marks_raised
	for(var/n in 1 to 5)
		probe.forceMove(locate(away.x, away.y + (n % 2), away.z))
	TEST_ASSERT(GLOB.interest_parked_move_spared > spared_before, "its moves were spared their publish ([GLOB.interest_parked_move_spared - spared_before])")
	TEST_ASSERT_EQUAL(GLOB.refresh_marks_raised, marks_before, "and raised no mark")
	TEST_ASSERT_EQUAL(probe.refresh_queued, DEP_PARKED, "still parked and owed")
	interest_view_set("dq-test-viewer", home, null, world.view)
	probe.forceMove(home)
	TEST_ASSERT_EQUAL(probe.refresh_queued, 0, "moved where it is watched it draws")
	interest_clean(probes)
