// Draw on change (code/engine/change/draw_queue.dm, gaze.dm; doc/rewrite/draw_on_change.md): a look change marks its atom and files it in the bucket of
// its chunk; a budgeted drain draws the buckets nearest a client's eye first and every other one after. Nothing waits for a viewer.

/// An object that draws a state of its own and watches nothing: the subject of the queue tests. It can stand on any turf with others of its kind.
/obj/dq_draw_probe
	name = "draw probe"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"
	var/shown = 0

/obj/dq_draw_probe/draw(datum/look/look)
	. = ..()
	look.overlay("shown-[shown]")

/// A probe with an output besides its look: the refresh queue runs it.
/obj/dq_draw_probe/effect
	var/effects = 0

/obj/dq_draw_probe/effect/on_state_changed(bits)
	..()
	effects++

/// A scheduler that is out of budget after `cap` draws: the drain's budget, made countable.
/datum/time_scheduler/dq_draw_cap
	cap = 1
	limit = 1000 // the tick is not spent: only the draw count is the budget (dq_spent_tick is the other case)

/// The state every test of this file starts from: the draw queue, the refresh queue and the gaze registry are empty and private to the test (the world's
/// are put back when it ends).
/datum/unit_test/proc/draw_isolate()
	set_global(nameof(GLOB.refresh_queue), list())
	set_global(nameof(GLOB.refresh_queue_at), alist())
	set_global(nameof(GLOB.refresh_queue_base), 0)
	set_global(nameof(GLOB.draw_buckets), alist())
	set_global(nameof(GLOB.draw_filed), alist())
	set_global(nameof(GLOB.gaze_grid), list())
	set_global(nameof(GLOB.gaze_holds), alist())
	set_global(nameof(GLOB.gaze_sigs), alist())
	set_global(nameof(GLOB.gaze_at), alist())
	set_global(nameof(GLOB.gaze_anchors), alist())

/// A turf `chunks` chunks east of `T` (west when the map ends), or null when the map is too small.
/datum/unit_test/proc/draw_chunks_from(turf/T, chunks)
	var/dx = chunks * GAZE_CHUNK
	if(T.x + dx <= world.maxx)
		return locate(T.x + dx, T.y, T.z)
	if(T.x - dx >= 1)
		return locate(T.x - dx, T.y, T.z)
	return null

/// Makes `count` probes on `T`, drawn and quiet.
/datum/unit_test/proc/draw_probes(turf/T, count)
	var/list/probes = list()
	for(var/i in 1 to count)
		probes += new /obj/dq_draw_probe(T)
	refresh_flush()
	draw_flush()
	return probes

/datum/unit_test/proc/draw_clean(list/probes)
	for(var/obj/dq_draw_probe/probe as anything in probes)
		qdel(probe)
	refresh_flush()
	draw_flush()

/// Whether `A` shows what a fresh draw of it makes.
/datum/unit_test/proc/draw_is_current(atom/A)
	return refresh_look(A, FALSE) == A.rx?.look_key

/// A look change files the atom (not the refresh queue), nothing is drawn until the drain, and what the drain draws is current.
/datum/unit_test/dq_draw_change_is_drawn_by_the_drain

/datum/unit_test/dq_draw_change_is_drawn_by_the_drain/Run()
	draw_isolate()
	var/turf/T = test_floor()
	var/list/probes = draw_probes(T, 3)
	var/obj/dq_draw_probe/A = probes[1]
	var/dirtied = GLOB.draw_n["dirtied"]
	A.set_shown(2)
	TEST_ASSERT_EQUAL(GLOB.draw_n["dirtied"] - dirtied, 1, "a look change is one dirtied atom")
	TEST_ASSERT_EQUAL(draw_depth(), 1, "and one filed draw")
	TEST_ASSERT(!(A in GLOB.refresh_queue), "that the refresh queue does not hold")
	TEST_ASSERT(!("shown-2" in A.rx?.look_overlays), "nothing is drawn until the drain runs")
	A.set_shown(3)
	TEST_ASSERT_EQUAL(draw_depth(), 1, "a second change before the drain files nothing more")
	TEST_ASSERT(draw_drain(null), "the drain empties it")
	TEST_ASSERT_EQUAL(draw_depth(), 0, "nothing is filed after")
	TEST_ASSERT(("shown-3" in A.rx?.look_overlays), "and the atom shows its latest look: [json_encode(A.rx?.look_overlays)]")
	TEST_ASSERT(draw_is_current(A), "which is what a fresh draw makes")
	draw_clean(probes)

/// Mass changes over several chunks, drained a few draws a tick: every atom is current when the queue is empty, and no pass draws more than its budget.
/datum/unit_test/dq_draw_nothing_is_stale_after_the_drain

/datum/unit_test/dq_draw_nothing_is_stale_after_the_drain/Run()
	draw_isolate()
	var/turf/T = test_floor()
	var/list/spots = list(T)
	for(var/chunks in 1 to 3)
		var/turf/far = draw_chunks_from(T, chunks)
		if(far)
			spots += far
	var/list/probes = list()
	for(var/turf/spot as anything in spots)
		probes += draw_probes(spot, 12)
	for(var/obj/dq_draw_probe/probe as anything in probes)
		probe.set_shown(rand(1, 9))
	TEST_ASSERT_EQUAL(draw_depth(), length(probes), "every change is filed")
	var/datum/time_scheduler/dq_draw_cap/sched = new
	sched.cap = 7
	var/passes = 0
	while(length(GLOB.draw_buckets) && passes < 100)
		passes++
		sched.calls = 0
		var/before = GLOB.draw_n["drawn"]
		draw_drain(sched)
		TEST_ASSERT(GLOB.draw_n["drawn"] - before <= 7, "a pass draws no more than its budget allows")
	TEST_ASSERT_EQUAL(draw_depth(), 0, "the queue ends empty")
	TEST_ASSERT(passes >= round(length(probes) / 7), "which took as many passes as the budget needed")
	for(var/obj/dq_draw_probe/probe as anything in probes)
		TEST_ASSERT(draw_is_current(probe), "an atom of the queue shows what a fresh draw makes")
	draw_clean(probes)

/// A client walking, with nothing changing, causes no draw work at all: no mark, no draw, no look built, no drain pass.
/datum/unit_test/dq_draw_walking_client_causes_no_draw_work

/datum/unit_test/dq_draw_walking_client_causes_no_draw_work/Run()
	draw_isolate()
	var/turf/T = test_floor()
	var/list/probes = draw_probes(T, 10)
	var/marks = GLOB.refresh_marks_raised
	var/dirtied = GLOB.draw_n["dirtied"]
	var/drawn = GLOB.draw_n["drawn"]
	var/builds = GLOB.look_builds
	var/passes = GLOB.draw_n["drain_calls"]
	var/steps = 0
	for(var/step in 1 to 40)
		var/turf/at = locate(clamp(T.x + step, 1, world.maxx), T.y, T.z)
		gaze_view_set("dq-draw-walker", at, at, world.view)
		GLOB.gaze_at["dq-draw-walker"] = at
		TEST_ASSERT(draw_drain(null), "the drain has nothing to do")
		steps++
	TEST_ASSERT_EQUAL(GLOB.refresh_marks_raised, marks, "walking marks nothing")
	TEST_ASSERT_EQUAL(GLOB.draw_n["dirtied"], dirtied, "dirties nothing")
	TEST_ASSERT_EQUAL(GLOB.draw_n["drawn"], drawn, "draws nothing")
	TEST_ASSERT_EQUAL(GLOB.look_builds, builds, "builds no look")
	TEST_ASSERT_EQUAL(GLOB.draw_n["drain_calls"], passes, "and runs no drain pass")
	TEST_ASSERT_EQUAL(draw_depth(), 0, "and the queue stays empty")
	gaze_hold_set("dq-draw-walker", null)
	draw_clean(probes)

/// A change next to a client's eye is drawn before a change far away that was made earlier, and the far one is drawn after.
/datum/unit_test/dq_draw_change_near_the_eye_draws_before_far

/datum/unit_test/dq_draw_change_near_the_eye_draws_before_far/Run()
	draw_isolate()
	var/turf/T = test_floor()
	var/turf/far_turf = draw_chunks_from(T, 4)
	if(!far_turf)
		return // a map too small to have a chunk four away
	var/list/near_probes = draw_probes(T, 2)
	var/list/far_probes = draw_probes(far_turf, 2)
	var/obj/dq_draw_probe/near = near_probes[1]
	var/obj/dq_draw_probe/far = far_probes[1]
	GLOB.gaze_at["dq-draw-eye"] = T
	far.set_shown(5) // the far change is made first
	near.set_shown(6)
	TEST_ASSERT_EQUAL(draw_depth(), 2, "both are filed")
	var/datum/time_scheduler/dq_draw_cap/sched = new // out of budget after one draw
	draw_drain(sched)
	TEST_ASSERT(("shown-6" in near.rx?.look_overlays), "the change near the eye is drawn first: [json_encode(near.rx?.look_overlays)]")
	TEST_ASSERT(!("shown-5" in far.rx?.look_overlays), "the far one waits")
	TEST_ASSERT_EQUAL(draw_depth(), 1, "and is still filed")
	draw_drain(null)
	TEST_ASSERT(("shown-5" in far.rx?.look_overlays), "and is drawn when the near work is done, with no viewer there")
	TEST_ASSERT(draw_is_current(far) && draw_is_current(near), "both are current")
	GLOB.gaze_at -= "dq-draw-eye"
	draw_clean(near_probes + far_probes)

/// The order is rings around the eyes: the nearest of several eyes counts, and a level with no client drains after one with a client.
/datum/unit_test/dq_draw_order_is_rings_around_the_eyes

/datum/unit_test/dq_draw_order_is_rings_around_the_eyes/Run()
	draw_isolate()
	var/turf/T = test_floor()
	var/turf/two = draw_chunks_from(T, 2)
	var/turf/five = draw_chunks_from(T, 5)
	if(!two || !five)
		return
	var/list/probes = list()
	for(var/turf/spot in list(five, two, T))
		probes += draw_probes(spot, 1)
	for(var/obj/dq_draw_probe/probe as anything in probes)
		probe.set_shown(7)
	GLOB.gaze_at["dq-draw-eye-a"] = T
	var/list/order = draw_order()
	var/list/here = list(GAZE_KEY(T.z, GAZE_CHUNK_OF(T.x), GAZE_CHUNK_OF(T.y)), GAZE_KEY(two.z, GAZE_CHUNK_OF(two.x), GAZE_CHUNK_OF(two.y)), GAZE_KEY(five.z, GAZE_CHUNK_OF(five.x), GAZE_CHUNK_OF(five.y)))
	TEST_ASSERT_EQUAL(jointext(order, ","), jointext(here, ","), "buckets drain in rings out from the eye: [jointext(order, ",")]")
	GLOB.gaze_at["dq-draw-eye-b"] = five // a second eye: the far bucket is now near an eye
	order = draw_order()
	TEST_ASSERT(order.Find(here[3]) < order.Find(here[2]), "the nearest of several eyes decides: [jointext(order, ",")]")
	GLOB.gaze_at = alist()
	draw_drain(null)
	draw_clean(probes)

/// A deleted atom leaves its bucket (nothing pins it), wherever it is in it, and the drain meets no null it cannot skip.
/datum/unit_test/dq_draw_queue_drops_deleted

/datum/unit_test/dq_draw_queue_drops_deleted/Run()
	draw_isolate()
	var/turf/T = test_floor()
	var/list/probes = draw_probes(T, 600)
	for(var/obj/dq_draw_probe/probe as anything in probes)
		probe.set_shown(4)
	TEST_ASSERT_EQUAL(draw_depth(), 600, "the changes are filed")
	var/obj/dq_draw_probe/first = probes[1]
	var/obj/dq_draw_probe/middle = probes[300]
	var/obj/dq_draw_probe/last = probes[600]
	for(var/obj/dq_draw_probe/doomed in list(first, middle, last))
		qdel(doomed)
		TEST_ASSERT(!(doomed in GLOB.draw_buckets[GAZE_KEY(T.z, GAZE_CHUNK_OF(T.x), GAZE_CHUNK_OF(T.y))]), "a deleted atom is not in its bucket")
		TEST_ASSERT(isnull(GLOB.draw_filed[slot_known(doomed)]), "and its filing is forgotten")
	TEST_ASSERT_EQUAL(draw_depth(), 597, "the others stay filed")
	draw_drain(null)
	TEST_ASSERT_EQUAL(draw_depth(), 0, "and drain")
	draw_clean(probes)

/// An atom with an output besides its look is run by the refresh queue, look included, and its bucket entry is skipped, not drawn twice.
/datum/unit_test/dq_draw_eager_atom_runs_in_the_refresh_queue

/datum/unit_test/dq_draw_eager_atom_runs_in_the_refresh_queue/Run()
	draw_isolate()
	var/turf/T = test_floor()
	var/obj/dq_draw_probe/effect/A = allocate(/obj/dq_draw_probe/effect, T)
	var/list/probes = list(A)
	refresh_flush()
	A.set_shown(8)
	TEST_ASSERT(A in GLOB.refresh_queue, "a change of an atom with an output besides its look is queued in the refresh queue, not filed")
	refresh_flush()
	A.refresh_queued = DEP_DRAW // filed by hand: a look-only entry the atom then outgrows
	draw_file(A)
	TEST_ASSERT_EQUAL(draw_depth(), 1, "a look-only atom is filed")
	var/stale = GLOB.draw_n["stale"]
	var/builds = GLOB.look_builds
	refresh_mark(A, DEP_LEGACY, CHANGE_EXPLICIT) // an output besides the look: the refresh queue takes it
	TEST_ASSERT(A in GLOB.refresh_queue, "it is queued for the refresh queue as well")
	refresh_drain(null)
	TEST_ASSERT(("shown-8" in A.rx?.look_overlays), "the refresh queue drew it")
	draw_drain(null)
	TEST_ASSERT_EQUAL(GLOB.draw_n["stale"] - stale, 1, "its bucket entry was skipped")
	TEST_ASSERT(GLOB.look_builds - builds <= 1, "and it was not drawn twice")
	draw_clean(probes)

/// The hold of a fresh map-load atom (boot_created_hold()): a write marks nothing, and the settle draws it once, with what it was written.
/datum/unit_test/dq_draw_boot_hold_draws_once

/datum/unit_test/dq_draw_boot_hold_draws_once/Run()
	draw_isolate()
	var/turf/T = test_floor()
	var/list/probes = draw_probes(T, 3)
	var/type = /obj/dq_draw_probe
	set_global(nameof(GLOB.boot_created_buckets), list())
	set_global(nameof(GLOB.boot_created_sampled), list())
	set_global(nameof(GLOB.type_look_stamp), GLOB.type_look_stamp.Copy())
	GLOB.type_look_stamp[type] = FALSE
	GLOB.boot_created_buckets[type] = probes.Copy()
	for(var/obj/dq_draw_probe/probe as anything in probes)
		probe.datum_flags |= DF_BOOT_HELD
		probe.rx?.look_key = null
	var/obj/dq_draw_probe/A = probes[1]
	A.set_shown(6)
	TEST_ASSERT(!A.refresh_queued && !draw_depth(), "a write to a held atom marks nothing")
	var/builds = GLOB.look_builds
	boot_created_release()
	TEST_ASSERT(!(A.datum_flags & DF_BOOT_HELD), "the release lets it go")
	TEST_ASSERT_EQUAL(draw_depth() + length(GLOB.refresh_queue), 3, "and every held atom owes its first draw")
	refresh_flush()
	draw_flush()
	TEST_ASSERT(GLOB.look_builds - builds <= 3, "which is drawn once")
	TEST_ASSERT(("shown-6" in A.rx?.look_overlays), "with what the write made: [json_encode(A.rx?.look_overlays)]")
	draw_clean(probes)

/// Boot left nothing owed: no atom is held, none owes a refresh, and the draw queue is empty (a test world draws everything at boot).
/datum/unit_test/dq_draw_boot_leaves_no_undrawn_object

/datum/unit_test/dq_draw_boot_leaves_no_undrawn_object/Run()
	refresh_flush()
	draw_flush()
	TEST_ASSERT(GLOB.boot_created_settled, "the boot settled")
	TEST_ASSERT_EQUAL(length(GLOB.boot_created_buckets), 0, "no type still waits for its verdict")
	TEST_ASSERT_EQUAL(draw_depth(), 0, "the draw queue is empty")
	var/held = 0
	var/owing = 0
	var/list/examples = list()
	for(var/atom/A in world)
		if(A.datum_flags & DF_BOOT_HELD)
			held++
		if(A.refresh_queued)
			owing++
			if(length(examples) < 5)
				examples += "[A.type]"
	TEST_ASSERT_EQUAL(held, 0, "no atom is held for its verdict")
	TEST_ASSERT_EQUAL(owing, 0, "no atom owes a draw: [jointext(examples, ", ")]")
