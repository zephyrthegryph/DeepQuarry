// The orphan pipes of a real boot. A pipe with no neighbour is spent by its own atmos_init() in the node setup, and a full-map boot leaves each one
// referenced (GC LEAK). What the boot trace established (10 full-map runs; refcount read through the ref text, a plain qdel'd effect reads 2):
//  - a map-loaded orphan pipe reads 5 or 6 when the node loop ends, 5 when setup_atmos_machinery() returns, 4 after the boot's refresh settle, and stays
//    4 (two over the control); a pipe made after the map load and ended the same way is freed. A map-loaded /obj/machinery/light ended by qdel() reads the same,
//    so it is the boot's map atoms, not pipes.
//  - the one transient reference is the atom's boot bucket (boot_created_hold()) until the settle; it is not the leak.
//  - ref_holders() (a search of every global, list, alist and non-atom datum var, 465 k containers, 50 k left at its budget) found only the garbage queue's
//    own entry for such a pipe, as the reference finder did. The other two references are in no DM container: a proc frame still running or a native table.
//  - 11-11, small unit-test map: a map-placed /obj/machinery/light or lattice qdel'd keeps one reference a `new` one does not, once a test frame's loop variable
//    over the world is not counted (a loop that breaks on the atom keeps it). ref_holders(atoms = TRUE) found nothing: not in the atom's own object graph after
//    qdel(), not in any var or short list of 154 k atoms (the atom vars' first level). The boot probe: the count rises by 2 in CreateAtoms (one of them the live
//    atom's own area/loc entries) and by 1 more in the Atmospherics system's init for a lattice. Still open: a native holder, or a datum two levels below an atom.
//  - CAUSE (11-11): boot_turf() in verdigris/ffi/src/gas/mod.rs read each turf's contents through the Byondapi; since 516.1674 every such read is a persistent
//    reference and byondapi-rs does not release a ByondValue on drop, so every atom on a turf kept one. It releases them now (dq_map_atom_ends_like_new).
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
	P.refresh_queued = 0 // drawn at once, its entry stays in the queue
	refresh_mark(P, DEP_ALL) // marked again before the queue was replaced
	var/entries = 0
	for(var/datum/D as anything in GLOB.refresh_queue)
		if(D == P)
			entries++
	var/pipe_slot = slot_known(P)
	if(pipe_slot && !isnull(GLOB.draw_filed[pipe_slot]))
		entries++ // a look-only atom waits in the draw queue
	TEST_ASSERT_EQUAL(entries, 1, "a marked datum has one queue entry however often it is marked")
	qdel(P)
	for(var/datum/D as anything in GLOB.refresh_queue)
		TEST_ASSERT(D != P, "a destroyed datum left an entry in the refresh queue")
	for(var/key in GLOB.draw_buckets)
		TEST_ASSERT(!(P in GLOB.draw_buckets[key]), "a destroyed datum left an entry in the draw queue")

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

// ref_holders() with `atoms`: it also opens atoms (an atom's contents, its vars) and finds an /image whose loc is the target, which no list element shows.

/datum/unit_test/dq_ref_holders_opens_atoms/Run()
	var/obj/effect/abstract/info/box = new(test_floor())
	var/obj/effect/abstract/info/target = new(test_floor())
	target.forceMove(box)
	var/list/hits = ref_holders(target, 20 SECONDS, TRUE, box)
	hits.len--
	var/found = FALSE
	for(var/path in hits)
		if(findtext(path, "contents"))
			found = TRUE
	TEST_ASSERT(found, "with atoms the search names the container's contents as a holder (got: [jointext(hits, "; ")])")

	var/image/picture = new /image(null, target)
	GLOB.refresh_push_queue += picture
	var/list/image_hits = ref_holders(target, 20 SECONDS, TRUE)
	GLOB.refresh_push_queue -= picture
	image_hits.len--
	found = FALSE
	for(var/path in image_hits)
		if(findtext(path, "/image"))
			found = TRUE
	TEST_ASSERT(found, "an /image whose loc is the target is reported (got: [jointext(image_hits, "; ")])")
	qdel(target)
	qdel(box)

// A map-placed atom ends like a new one: after qdel() it holds no reference a `new` atom of its type does not.

/datum/unit_test/dq_map_atom_ends_like_new

/// The ref text of the first map-placed lattice (the loop variable is gone when this returns, so no caller local holds it).
/datum/unit_test/dq_map_atom_ends_like_new/proc/map_lattice_key()
	for(var/obj/structure/lattice/L in world)
		return ref(L)
	return null

/// The references the datum named by `key` holds besides the one this proc and refcount() hold.
/datum/unit_test/dq_map_atom_ends_like_new/proc/refs_of(key)
	var/datum/D = locate(key)
	if(!D)
		return -1
	return refcount(D) - 2

/datum/unit_test/dq_map_atom_ends_like_new/Run()
	var/map_key = map_lattice_key()
	TEST_ASSERT_NOTNULL(map_key, "the test map has a lattice")
	var/obj/structure/lattice/fresh = new(test_floor())
	var/fresh_key = ref(fresh)
	fresh = null
	qdel(locate(map_key))
	qdel(locate(fresh_key))
	TEST_ASSERT_EQUAL(refs_of(map_key), refs_of(fresh_key), "a map-placed lattice keeps no reference a new one does not")

// The same sweep, for the area air devices and injectors: the server bench logged outlet injectors and engine vent pumps still referenced
// after qdel() ("unable to be GC'd"). Each is made on its own, on a pipe, on a radio frequency and after a radio command, then deleted.
/datum/unit_test/dq_gc_sweep/atmos_air_devices

/datum/unit_test/dq_gc_sweep/atmos_air_devices/dq_gc_sweep_build(turf/T)
	var/list/subjects = list("labels" = list())
	for(var/path in list(/obj/machinery/atmospherics/unary/outlet_injector, /obj/machinery/atmospherics/unary/vent_pump/engine, /obj/machinery/atmospherics/unary/vent_pump/on, /obj/machinery/atmospherics/unary/vent_scrubber/on))
		for(var/i in 1 to 3)
			var/obj/machinery/atmospherics/unary/U = new path(T)
			if(i >= 2 && istype(U, /obj/machinery/atmospherics/unary/outlet_injector))
				var/obj/machinery/atmospherics/unary/outlet_injector/I = U
				I.set_frequency(ENGINE_FREQ)
				I.broadcast_status()
			dq_gc_sweep_add(subjects, U, "[path] [i]")
	refresh_flush()
	wait_ticks(round(1 SECONDS / world.tick_lag)) // the status reports (after()) and radio posts have run
	refresh_flush()
	return subjects

// The bench's case: the devices sit on a pipe and an explosion ends them (the supermatter bench's engine room), not a qdel().
/datum/unit_test/dq_gc_sweep/atmos_air_devices_blasted

/datum/unit_test/dq_gc_sweep/atmos_air_devices_blasted/dq_gc_sweep_build(turf/T)
	var/list/subjects = list("labels" = list())
	var/turf/pipe_turf = get_step(T, NORTH)
	TEST_ASSERT(pipe_turf, "the test floor has a tile north of it")
	for(var/path in list(/obj/machinery/atmospherics/unary/outlet_injector, /obj/machinery/atmospherics/unary/vent_pump/engine, /obj/machinery/atmospherics/unary/vent_pump/on, /obj/machinery/atmospherics/unary/vent_scrubber/on))
		for(var/i in 1 to 3)
			var/obj/machinery/atmospherics/unary/U = new path(T)
			U.set_dir(NORTH)
			dq_gc_sweep_add(subjects, U, "blasted [path] [i]")
	var/obj/machinery/atmospherics/pipe/simple/P = new /obj/machinery/atmospherics/pipe/simple(pipe_turf)
	P.set_dir(SOUTH)
	for(var/obj/machinery/atmospherics/unary/U in T)
		U.atmos_init()
	P.atmos_init()
	refresh_flush()
	wait_ticks(round(1 SECONDS / world.tick_lag))
	refresh_flush()
	dq_gc_sweep_add(subjects, P, "the pipe they share")
	return subjects

/datum/unit_test/dq_gc_sweep/atmos_air_devices_blasted/dq_gc_sweep_delete(list/subjects)
	var/list/deleted = list()
	var/list/labels = subjects[subjects[1]]
	subjects.Cut(1, 2)
	for(var/i in 1 to length(subjects))
		var/datum/D = subjects[i]
		deleted[ref(D)] = labels[i]
		SSexplosions.queue_blast(D, 1)
		subjects[i] = null
	subjects.Cut()
	SSexplosions.deliver_blast_batches(INFINITY, FALSE)
	SSair.rust_commit_pending_pipenets()
	for(var/key in deleted.Copy())
		var/datum/D = locate(key)
		if(D && !QDELETED(D))
			deleted -= key // the blast did not end it (a sturdy one): not a leak
			qdel(D, TRUE)
	return deleted

/// The blast's sparks are litter too (the base only clears items).
/datum/unit_test/dq_gc_sweep/atmos_air_devices_blasted/dq_gc_sweep_clean_litter(turf/T, list/floor_before)
	..()
	for(var/turf/place as anything in block(locate(max(T.x - 2, 1), max(T.y - 2, 1), T.z), locate(min(T.x + 2, world.maxx), min(T.y + 2, world.maxy), T.z)))
		FOR_CONTENTS(var/obj/effect/effect/sparks/S, place)
			qdel(S, TRUE)
