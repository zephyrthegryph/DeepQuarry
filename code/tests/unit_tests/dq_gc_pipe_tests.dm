// The orphan pipes of a real boot. A pipe with no neighbour is spent by its own atmos_init() in the node setup, and a full-map boot leaves each one
// referenced (GC LEAK). What the boot trace established (10 full-map runs; refcount read through the ref text, a plain qdel'd effect reads 2):
//  - a map-loaded orphan pipe reads 5 or 6 when the node loop ends, 5 when setup_atmos_machinery() returns, 4 after the boot's refresh settle, and stays
//    4 (two over the control); a pipe made after the map load and ended the same way is freed. A map-loaded /obj/machinery/light ended by qdel() reads the same,
//    so it is the boot's map atoms, not pipes.
//  - the one transient reference is the atom's boot bucket (boot_created_hold()) until the settle; it is not the leak.
//  - ref_holders() (a search of every global, list, alist and non-atom datum var, 465 k containers, 50 k left at its budget) found only the garbage queue's
//    own entry for such a pipe, as the reference finder did. The other two references are in no DM container: a proc frame still running or a native table.
//  - the same flow on a small map (a template load, InitializeAtoms() with mapload, the boot hold and settle) leaves nothing over a fresh atom, so it does not reproduce.
// The sweeps below end pipes the same way in a small world.

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

// ref_holders() (code/content/admin/view_variables/ref_holders.dm), the whole-world holder search: it finds a holder in a global list, names the path, and
// reports when it stops short.

/datum/unit_test/dq_ref_holders_finds_a_holder/Run()
	var/obj/effect/abstract/info/target = new(test_floor())
	GLOB.refresh_push_queue += target
	var/list/hits = ref_holders(target, 2 MINUTES)
	GLOB.refresh_push_queue -= target
	var/summary = hits[length(hits)]
	hits.len--
	var/found = FALSE
	for(var/path in hits)
		if(findtext(path, "refresh_push_queue"))
			found = TRUE
	TEST_ASSERT(found, "the search names the global list that holds the datum (got: [jointext(hits, "; ")])")
	TEST_ASSERT(findtext(summary, " 0 left unvisited"), "and it finished within its budget ([summary])")
	var/list/after = ref_holders(target, 2 MINUTES)
	after.len--
	for(var/path in after)
		TEST_ASSERT(!findtext(path, "refresh_push_queue"), "with the holder gone the search no longer names it (got: [jointext(after, "; ")])")
	qdel(target)
