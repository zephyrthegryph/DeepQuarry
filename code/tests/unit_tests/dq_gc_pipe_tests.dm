// OPEN: a real boot still leaks about 36 orphan pipes (pipes atmos_init() ends during the map's node setup stay referenced after qdel()), and the
// tests below, which end pipes the same way in a small world, do not reproduce it. Next diagnostic: log refcount(P) at each phase of the destroy
// transaction when atmos_init() ends an orphan pipe in a real boot, and see which phase first leaves a holder behind.

// The GC sweep, for pipes the map load ends: a pipe with no neighbour to connect to is spent by its own atmos_init() while SSair's batched
// node setup runs, and every one of them was still referenced five minutes later (the live log's "GC LEAK ... pipe/simple/hidden/..." lines).

/datum/unit_test/dq_gc_sweep/orphan_pipes
	/// ref text -> label of the pipes atmos_init() ended.
	var/list/ended = list()

/// The pipes are ended by the node setup itself (the way setup_atmos_machinery() runs it), not by the sweep.
/datum/unit_test/dq_gc_sweep/orphan_pipes/dq_gc_sweep_build(turf/T)
	var/list/made = list()
	for(var/path in list(/obj/machinery/atmospherics/pipe/simple/hidden/supply, /obj/machinery/atmospherics/pipe/simple/hidden/scrubbers, /obj/machinery/atmospherics/pipe/simple/hidden, /obj/machinery/atmospherics/pipe/simple/hidden/yellow))
		for(var/i in 1 to 3)
			var/obj/machinery/atmospherics/pipe/simple/P = new path(T)
			made += P
			ended[ref(P)] = "orphan [path] [i]"
	refresh_flush() // the map load's draw of each pipe has run by the time the node setup ends it
	rel_write_batch_begin()
	for(var/obj/machinery/atmospherics/pipe/simple/P as anything in made)
		P.atmos_init()
	rel_write_batch_commit()
	for(var/obj/machinery/atmospherics/pipe/simple/P as anything in made)
		TEST_ASSERT(QDELETED(P), "an orphan pipe was not spent by atmos_init()")
	made.Cut()
	return list("labels" = list())

/datum/unit_test/dq_gc_sweep/orphan_pipes/dq_gc_sweep_delete(list/subjects)
	return ended

// The same sweep, for the glows a viewer holds copies of (client_glow_holder.dm): the live log showed /obj/effect/overlay/client_glow
// still referenced five minutes after qdel().

/datum/unit_test/dq_gc_sweep/held_glows
	/// ref text -> label of what the sweep deleted.
	var/list/ended = list()
	var/datum/client_glow_holder/viewer
	var/list/fixtures_made = list()

/datum/unit_test/dq_gc_sweep/held_glows/dq_gc_sweep_build(turf/T)
	set_global(nameof(GLOB.client_lighting), FALSE)
	set_global(nameof(GLOB.client_glow_holder_recomputes), GLOB.client_glow_holder_recomputes)
	client_lighting_set(TRUE)
	var/list/fixtures = list()
	for(var/i in 1 to 12)
		fixtures += new /obj/machinery/light(T)
	SSlighting.light_step(0, TRUE)
	viewer = new
	viewer.view_at(client_glow_test_eye(T), 7, 7)
	var/n = 0
	for(var/obj/machinery/light/F as anything in fixtures)
		var/datum/light_source/S = F.light
		TEST_ASSERT_NOTNULL(S?.glow, "a fixture glows")
		TEST_ASSERT_NOTNULL(viewer.entry_of(S), "the viewer holds the fixture's glow")
		var/obj/effect/overlay/client_glow/G = S.glow
		ended[ref(G)] = "a held glow"
		// Half the glows end with their light, half are deleted on their own (a glow goes with the turf contents it stands among).
		if(++n % 2)
			qdel(G)
		else
			qdel(F)
	fixtures_made = fixtures
	return list("labels" = list())

/datum/unit_test/dq_gc_sweep/held_glows/dq_gc_sweep_delete(list/subjects)
	return ended

/datum/unit_test/dq_gc_sweep/held_glows/Run()
	. = ..()
	spent(viewer)
	for(var/obj/machinery/light/F as anything in fixtures_made)
		if(!QDELETED(F))
			qdel(F)
	fixtures_made.Cut()
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// An entry the boot settle leaves behind (it clears the sampled atom's pending bits and keeps its queue entry) and a later mark: the queue holds the
/// atom once, so refresh_forget() takes out its only entry and nothing pins it after qdel().
/datum/unit_test/dq_refresh_queue_one_entry_per_datum

/datum/unit_test/dq_refresh_queue_one_entry_per_datum/Run()
	var/turf/T = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(5, 5, 1)
	var/obj/machinery/atmospherics/pipe/simple/hidden/yellow/P = new(T)
	refresh_flush()
	refresh_mark(P, DEP_ALL)
	P.refresh_queued = 0 // the settle's sample: drawn at once, its entry stays in the queue
	refresh_mark(P, DEP_ALL) // marked again before the queue was replaced
	var/entries = 0
	for(var/datum/D as anything in GLOB.refresh_queue)
		if(D == P)
			entries++
	TEST_ASSERT_EQUAL(entries, 1, "a marked datum has one queue entry however often it is marked")
	qdel(P)
	for(var/datum/D as anything in GLOB.refresh_queue)
		TEST_ASSERT(D != P, "a destroyed datum left an entry in the refresh queue")
