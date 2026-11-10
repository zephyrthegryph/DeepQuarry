// The round-start draw backlog (doc/rewrite/proposals/change_graph.md section 7, step 5).
//
// A map load creates every atom before any drain runs, so each one's first refresh was queued at creation; on the station map that left
// all 310 k space turfs in the draw queue until a client connected (a clientless world does not advance time). The default-look stamp
// samples one fresh instance per type at boot (refresh_settle_created()) and drops the fresh atoms of types whose default look is empty;
// after the verdict, a fresh atom of such a type is not queued at all.

/// A type like a space turf: it has capabilities (an op), so it may derive something, and its draw shows nothing.
/obj/dq_stamp_plain
	name = "stamp plain"
	icon = 'icons/turf/space.dmi'
	icon_state = "default"

CAPABILITIES(/obj/dq_stamp_plain)
	op("dq_stamp_poke", item(/obj/item), label("Poke"), then(PROC_REF(poke)))

/obj/dq_stamp_plain/proc/poke(datum/act/op/act)
	return OP_PASS

/datum/unit_test/dq_draw_queue_default_look

/datum/unit_test/dq_draw_queue_default_look/Run()
	var/turf/T = test_floor()
	var/type = /obj/dq_stamp_plain
	refresh_flush()
	GLOB.type_look_stamp -= type
	GLOB.type_derives_cache -= type

	// A map load: three fresh instances before any drain, each queued once with the creation mark.
	var/obj/A = new type(T)
	var/obj/B = new type(T)
	var/obj/C = new type(T)
	TEST_ASSERT(A.refresh_queued & DEP_CREATED, "a fresh atom's first refresh carries the creation mark")
	TEST_ASSERT(B.refresh_queued & DEP_CREATED, "a second fresh atom carries it too (the verdict is not in yet)")
	var/skipped_before = GLOB.type_look_stamp_skipped
	refresh_settle_created()
	TEST_ASSERT_EQUAL(GLOB.type_look_stamp[type], TRUE, "the sampled fresh instance records an empty default look")
	TEST_ASSERT(!B.refresh_queued && !C.refresh_queued, "the other fresh atoms leave the queue")
	TEST_ASSERT(!(B in GLOB.refresh_queue) && !(C in GLOB.refresh_queue), "the queue no longer holds them")
	TEST_ASSERT(GLOB.type_look_stamp_skipped - skipped_before >= 2, "the dropped atoms are counted")

	// After the verdict: a fresh atom is not queued at all.
	var/obj/D = new type(T)
	TEST_ASSERT(!D.refresh_queued, "a fresh atom of a stamped type queues no first refresh")
	TEST_ASSERT(!(D in GLOB.refresh_queue), "and is not in the queue")
	TEST_ASSERT_NULL(refresh_look(D, FALSE), "a dry draw of the stamped atom is empty, as the stamp says")

	// A real write still queues it, without the creation mark.
	refresh_mark(D, DEP_ALL) // a real mark (a type that derives nothing is not queued by state_changed() at all)
	TEST_ASSERT(D.refresh_queued & DEP_DRAW, "a write after creation queues the redraw")
	TEST_ASSERT(!(D.refresh_queued & DEP_CREATED), "a real mark clears the creation mark")

	// A fresh atom written before the drain is not dropped by the stamp: the write is a real mark.
	var/obj/E = new type(T)
	refresh_mark(E, DEP_ALL)
	refresh_settle_created()
	TEST_ASSERT(E.refresh_queued, "a fresh atom written since creation keeps its refresh")

	// What the boot left: no space turf still in the queue on its creation mark alone.
	var/stale = 0
	for(var/datum/Q as anything in GLOB.refresh_queue)
		if(istype(Q, /turf/space) && (Q.refresh_queued & DEP_CREATED) && type_look_stamped(Q))
			stale++
	TEST_ASSERT_EQUAL(stale, 0, "space turfs queued only by their creation mark")

	for(var/obj/O as anything in list(A, B, C, D, E))
		qdel(O)
	refresh_flush()

/// The re-queue census: what marks space turfs once the world runs (meaningful with --full-map). It logs the sources and fails only when a
/// space turf is still queued on its creation mark alone.
/datum/unit_test/dq_draw_queue_space_requeue

/datum/unit_test/dq_draw_queue_space_requeue/Run()
	var/queued = 0
	var/created_only = 0
	for(var/datum/Q as anything in GLOB.refresh_queue)
		if(istype(Q, /turf/space))
			queued++
			if(Q.refresh_queued & DEP_CREATED)
				created_only++
	log_test("space requeue: [queued] space turf(s) queued at test start, [created_only] on the creation mark alone; stamp [GLOB.type_look_stamp[/turf/space] ? "empty" : "kept"], [GLOB.type_look_stamp_skipped] fresh atom(s) dropped so far")
	GLOB.refresh_mark_probe_sources = list()
	set_global(nameof(GLOB.refresh_mark_probe_type), /turf/space)
	kernel_test_begin()
	for(var/pass in 1 to 20)
		kernel_phase_run(KERNEL_PHASE_D)
		kernel_drain_now()
	set_global(nameof(GLOB.refresh_mark_probe_type), null)
	kernel_test_end()
	var/total = 0
	for(var/chain in GLOB.refresh_mark_probe_sources)
		total += GLOB.refresh_mark_probe_sources[chain]
		log_test("space requeue: [GLOB.refresh_mark_probe_sources[chain]] x [chain]")
	log_test("space requeue: [total] mark(s) of space turfs over 20 deadline passes")
	TEST_ASSERT(!(GLOB.type_look_stamp[/turf/space] && created_only), "space turfs still queued on their creation mark alone after boot: [created_only]")

/// A datum that is not an atom and derives nothing (no derived() values, no push_to_rust()/on_state_changed() of its own) has no live output: its
/// type's verdict comes from declarations at first sight, so even its first tracked write queues nothing (rx_state, vending product rows and reagents
/// were 45 k queue entries at boot, each waiting for a probe refresh that ran after them all).
/datum/dq_refresh_plain_datum
	var/count = 0

/datum/dq_refresh_plain_datum/proc/bump()
	count++
	state_changed(src, CHANGE_EXPLICIT, nameof(count))

/// The same datum with a side effect of its own: every write refreshes it, the first one included.
/datum/dq_refresh_plain_datum/side
	var/sides = 0

/datum/dq_refresh_plain_datum/side/on_state_changed(bits)
	sides++

/datum/unit_test/dq_datum_refresh_skips_types_that_derive_nothing

/datum/unit_test/dq_datum_refresh_skips_types_that_derive_nothing/Run()
	refresh_flush()
	GLOB.type_derives_cache -= /datum/dq_refresh_plain_datum
	GLOB.type_derives_cache -= /datum/dq_refresh_plain_datum/side
	var/datum/dq_refresh_plain_datum/plain = new
	plain.bump()
	TEST_ASSERT(!plain.refresh_queued, "a datum type that derives nothing was queued for its first write")
	TEST_ASSERT_EQUAL(refresh_live_outputs(plain), 0, "a datum that derives nothing has no live output")
	var/datum/rx_state/rx = new
	TEST_ASSERT_EQUAL(refresh_live_outputs(rx), 0, "an rx_state has no live output: its writes are not queue entries")
	var/datum/dq_refresh_plain_datum/side/side = new
	side.bump()
	TEST_ASSERT(side.refresh_queued, "a datum type with an on_state_changed() of its own was not queued on its first write")
	TEST_ASSERT(refresh_live_outputs(side) & DEP_LEGACY, "its side effect is a live output")
	TEST_ASSERT(!(refresh_live_outputs(side) & (DEP_DRAW | DEP_VALUES)), "and it has no look and no values")
	refresh_flush()
	TEST_ASSERT_EQUAL(side.sides, 1, "its on_state_changed() ran")
	side.bump()
	TEST_ASSERT(side.refresh_queued, "a datum type with an on_state_changed() of its own was not queued")
	refresh_flush()
	TEST_ASSERT_EQUAL(side.sides, 2, "and its on_state_changed() ran again")
	qdel(plain)
	qdel(side)

/// What is pending is judged by kind: a lazy type's real mark (made while the map initializes) is presentation, so the atom still parks and still draws
/// when a client comes near; a type whose verdict is not lazy keeps its marked entry queued; a mark of an effect kind is never deferred.
/datum/unit_test/dq_refresh_park_look_only_marks

/datum/unit_test/dq_refresh_park_look_only_marks/Run()
	set_global(nameof(GLOB.refresh_parked_near), GLOB.refresh_parked_near)
	interest_isolate()
	set_global(nameof(GLOB.refresh_parked_marked), GLOB.refresh_parked_marked)
	set_global(nameof(GLOB.refresh_parked), GLOB.refresh_parked)
	set_global(nameof(GLOB.refresh_near_drawn), GLOB.refresh_near_drawn)
	set_global(nameof(GLOB.refresh_park_residual), GLOB.refresh_park_residual)
	var/turf/T = test_floor()
	refresh_flush()
	GLOB.type_look_stamp -= /obj/structure/table
	var/obj/structure/table/marked = new(T)
	refresh_mark(marked, DEP_ALL)
	refresh_mark(marked, DEP_DRAW) // a real mark: the creation mark is gone
	TEST_ASSERT(!(marked.refresh_queued & DEP_CREATED), "a real mark clears the creation mark")
	GLOB.type_look_lazy -= /obj/structure/table
	refresh_park_backlog()
	TEST_ASSERT(marked.refresh_queued != DEP_PARKED, "a type without a lazy verdict stays queued")
	GLOB.type_look_lazy[/obj/structure/table] = TRUE
	TEST_ASSERT(refresh_pending_look_only(marked), "a lazy table's pending work is look only")
	var/marked_before = GLOB.refresh_parked_marked
	refresh_park_backlog()
	TEST_ASSERT_EQUAL(marked.refresh_queued, DEP_PARKED, "a look-only mark during init no longer keeps a lazy atom in the queue")
	TEST_ASSERT(GLOB.refresh_parked_marked > marked_before, "and the park counts it as marked since creation")
	TEST_ASSERT(findtext(refresh_kind_census(list(marked)), "0 entries"), "a parked atom is no queued work in the census")
	// Nothing waits forever: a client near it draws what it owed.
	interest_hold_set("dq-test-near", interest_view_keys(T, world.view))
	TEST_ASSERT(marked.refresh_queued & DEP_DRAW, "a client near it queues the draw it owed")
	refresh_flush()
	TEST_ASSERT_EQUAL(marked.refresh_queued, 0, "and the drain draws it")
	// An effect bit is not presentation: a datum with a side effect pending is never look only.
	var/datum/dq_refresh_plain_datum/side/side = new
	side.bump()
	TEST_ASSERT(!refresh_pending_look_only(side), "a pending side effect is not look only")
	TEST_ASSERT(findtext(refresh_kind_census(list(side)), "effects 1"), "the census counts it as an effect")
	GLOB.type_look_lazy -= /obj/structure/table
	qdel(side)
	qdel(marked)
	for(var/obj/item/stack/material/scrap in T)
		qdel(scrap)
	refresh_flush()

/// A fixture whose setup() writes a var its draw reads: the writes an atom's own construction makes after Initialize() returned.
/obj/dq_setup_marks_probe
	name = "setup marks probe"
	var/shade = 0

CAPABILITIES(/obj/dq_setup_marks_probe)
	setup(PROC_REF(probe_setup))

/obj/dq_setup_marks_probe/draw(datum/look/look)
	. = ..()
	look.state("shade-[shade]")

/obj/dq_setup_marks_probe/proc/probe_setup()
	set_shade(2)

/// What an atom's setup() writes is its construction (the first draw queued at creation covers it): the creation mark survives, so the type is
/// still sampled at boot (refresh_settle_created()) instead of every instance waiting, unsampled, for the post-boot drain. A write after construction
/// is a real mark and clears it, as before.
/datum/unit_test/dq_refresh_setup_writes_are_construction

/datum/unit_test/dq_refresh_setup_writes_are_construction/Run()
	var/turf/T = test_floor()
	refresh_flush()
	GLOB.type_look_stamp -= /obj/dq_setup_marks_probe
	GLOB.type_look_lazy -= /obj/dq_setup_marks_probe
	var/obj/dq_setup_marks_probe/first = new(T)
	var/obj/dq_setup_marks_probe/second = new(T)
	TEST_ASSERT_EQUAL(first.shade, 2, "its setup() ran")
	TEST_ASSERT(first.refresh_queued & DEP_CREATED, "the setup() write did not clear the creation mark")
	TEST_ASSERT(first.refresh_queued & DEP_DRAW, "and its first draw is still owed")
	refresh_settle_created()
	TEST_ASSERT(!isnull(GLOB.type_look_stamp[/obj/dq_setup_marks_probe]), "the boot settle sampled the type: its instances were fresh")
	TEST_ASSERT(!GLOB.type_look_stamp[/obj/dq_setup_marks_probe], "and its default look is not empty (the setup write is drawn)")
	// A write after construction is a real mark.
	second.set_shade(5)
	TEST_ASSERT(!(second.refresh_queued & DEP_CREATED), "a write after construction clears the creation mark")
	refresh_flush()
	TEST_ASSERT_EQUAL(second.shade, 5, "and the write stands")
	TEST_ASSERT_EQUAL(second.refresh_queued, 0, "and the drain draws it")
	GLOB.type_look_stamp -= /obj/dq_setup_marks_probe
	GLOB.type_look_lazy -= /obj/dq_setup_marks_probe
	qdel(first)
	qdel(second)
	refresh_flush()

/// A wall or floor built while the round runs (ChangeTurf) takes its material and flooring in setup(), is drawn from them and still answers later changes.
/datum/unit_test/dq_refresh_runtime_built_turfs_draw

/datum/unit_test/dq_refresh_runtime_built_turfs_draw/Run()
	var/turf/T = test_floor()
	var/floor_type = T.type
	refresh_flush()
	var/turf/simulated/wall/W = T.ChangeTurf(/turf/simulated/wall)
	TEST_ASSERT(istype(W), "the floor became a wall")
	if(!istype(W))
		return
	TEST_ASSERT(istype(W.material, /datum/material), "the wall took its material in setup()")
	TEST_ASSERT(W.density, "the wall is solid")
	refresh_flush()
	TEST_ASSERT_EQUAL(W.refresh_queued, 0, "the wall's first draw ran")
	var/before = W.icon_state
	var/turf/back = W.ChangeTurf(floor_type)
	refresh_flush()
	TEST_ASSERT(!istype(back, /turf/simulated/wall), "the wall became a floor again ([back.type]; was drawn [before])")
	TEST_ASSERT(!back.density, "which can be walked on")
	TEST_ASSERT_EQUAL(back.refresh_queued, 0, "and the floor's draw ran")

/// Draw on first view at boot: while the boot map loads, a type with no look verdict queues one fresh instance as its sample and holds the rest out of
/// the queue by type; the settle drops the held atoms of an empty default look without walking the queue, and a real mark on a held atom queues it.
/datum/unit_test/dq_boot_created_held_by_type

/datum/unit_test/dq_boot_created_held_by_type/Run()
	var/turf/T = test_floor()
	var/type = /obj/dq_stamp_plain
	refresh_flush()
	GLOB.type_look_stamp -= type
	GLOB.type_derives_cache -= type
	set_global(nameof(GLOB.boot_created_settled), FALSE)
	var/datum/materialize_batch/batch = SSatoms.batch_open("dq_boot_created_held_by_type") // the boot map load's frame is open
	var/obj/sample = new type(T)
	var/obj/held = new type(T)
	var/obj/written = new type(T)
	SSatoms.batch_close(batch)
	TEST_ASSERT(sample.refresh_queued & DEP_CREATED, "the first fresh instance is queued as the type's sample")
	TEST_ASSERT_EQUAL(held.refresh_queued, DEP_PARKED, "a later one is held out of the queue, owing its first refresh")
	TEST_ASSERT(!(held in GLOB.refresh_queue), "and is not in the queue")
	refresh_mark(written, DEP_ALL)
	TEST_ASSERT(written in GLOB.refresh_queue, "a real mark on a held atom queues it at once")
	refresh_settle_created()
	TEST_ASSERT(GLOB.type_look_stamp[type], "the sample records an empty default look")
	TEST_ASSERT_EQUAL(held.refresh_queued, DEP_PARKED, "the held atom of an empty default look is released with its type, untouched")
	TEST_ASSERT(!(held in GLOB.refresh_queue), "and never enters the queue")
	TEST_ASSERT(written.refresh_queued, "the written one keeps its refresh")
	TEST_ASSERT(GLOB.boot_created_settled, "the boot settle closes the hold: a later map load queues as before")
	refresh_flush()
	qdel(sample)
	qdel(held)
	qdel(written)

/// The look verdicts written for the next boot of this world are the verdicts sampling found: every cached type's stamp and lazy verdict equal the tables
/// now, and a cache keyed by another world is not read.
/datum/unit_test/dq_look_verdict_cache_agrees

/datum/unit_test/dq_look_verdict_cache_agrees/Run()
	look_verdicts_save()
	var/list/data = json_decode(file2text(LOOK_VERDICTS_FILE))
	TEST_ASSERT_EQUAL(data["key"], look_verdicts_key(), "the cache is keyed by this world")
	var/list/stamp = data["stamp"]
	var/list/lazy = data["lazy"]
	TEST_ASSERT(length(stamp) > 50, "the boot's verdicts were written ([length(stamp)])")
	var/mismatches = 0
	for(var/name in stamp)
		var/path = text2path(name)
		if(!path || !!stamp[name] != !!GLOB.type_look_stamp[path])
			mismatches++
	for(var/name in lazy)
		var/path = text2path(name)
		if(!path || !!lazy[name] != !!GLOB.type_look_lazy[path])
			mismatches++
	TEST_ASSERT_EQUAL(mismatches, 0, "every cached verdict equals the sampled one")

/// A verdict cache written by another world (another build or map) is never read: its verdicts would draw this world's atoms wrong. The same
/// document keyed by this world is read.
/datum/unit_test/dq_look_verdict_cache_ignores_another_world

/datum/unit_test/dq_look_verdict_cache_ignores_another_world/Run()
	var/type = /obj/dq_stamp_plain
	var/was_stamp = GLOB.type_look_stamp[type]
	var/was_lazy = GLOB.type_look_lazy[type]
	GLOB.type_look_stamp -= type
	GLOB.type_look_lazy -= type
	var/list/doc = list("key" = "another world|[look_verdicts_key()]", "stamp" = list("[type]" = 1), "lazy" = list("[type]" = 1))
	TEST_ASSERT(!look_verdicts_apply(doc), "a document of another world is refused")
	TEST_ASSERT(isnull(GLOB.type_look_stamp[type]) && isnull(GLOB.type_look_lazy[type]), "and none of its verdicts are read")
	doc["key"] = look_verdicts_key()
	doc["version"] = LOOK_VERDICTS_VERSION
	TEST_ASSERT(look_verdicts_apply(doc), "the same document keyed by this world is read")
	TEST_ASSERT(GLOB.type_look_stamp[type] && GLOB.type_look_lazy[type], "with its verdicts")
	GLOB.look_verdict_from_file -= type
	GLOB.type_look_stamp[type] = was_stamp
	GLOB.type_look_lazy[type] = was_lazy
	if(isnull(was_stamp))
		GLOB.type_look_stamp -= type
	if(isnull(was_lazy))
		GLOB.type_look_lazy -= type

/// Draw on first view holds only atoms on the map: a client's HUD (screen objects in nullspace: plane masters, fullscreen overlays) made during
/// boot is drawn at once, so a player who connects while the server boots never keeps an undrawn screen. A map atom of the same kind is still held.
/datum/unit_test/dq_boot_hold_spares_screens_and_non_map_atoms

/datum/unit_test/dq_boot_hold_spares_screens_and_non_map_atoms/Run()
	var/type = /obj/dq_stamp_plain
	refresh_flush()
	GLOB.type_look_stamp -= type
	GLOB.type_derives_cache -= type
	set_global(nameof(GLOB.boot_created_settled), FALSE)
	var/datum/materialize_batch/batch = SSatoms.batch_open("dq_boot_hold_spares_screens") // the boot map load's frame is open
	var/obj/sample = new type(test_floor())
	var/obj/on_map = new type(test_floor())
	var/obj/in_nullspace = new type(null) // where a HUD's screen objects live
	var/atom/movable/screen/hud_piece = new
	SSatoms.batch_close(batch)
	TEST_ASSERT(sample.refresh_queued & DEP_CREATED, "the first map instance is the type's sample")
	TEST_ASSERT_EQUAL(on_map.refresh_queued, DEP_PARKED, "a later map instance is still held for the verdict")
	TEST_ASSERT(in_nullspace.refresh_queued != DEP_PARKED, "an atom with no turf under it (a HUD's) is never held")
	TEST_ASSERT(hud_piece.refresh_queued != DEP_PARKED, "and neither is a screen object")
	refresh_settle_created()
	refresh_flush()
	qdel(sample)
	qdel(on_map)
	qdel(in_nullspace)
	qdel(hud_piece)

/// A cached verdict is the type's default look: an instance whose look vars were edited (a map var edit, a runtime-loaded map, a varedit) is never spared by it.
/datum/unit_test/dq_look_verdict_cache_spares_only_default_instances

/datum/unit_test/dq_look_verdict_cache_spares_only_default_instances/Run()
	var/type = /obj/dq_stamp_plain
	set_global(nameof(GLOB.look_verdict_unfit), GLOB.look_verdict_unfit)
	var/was_lazy = GLOB.type_look_lazy[type]
	var/was_cached = GLOB.look_verdict_from_file[type]
	GLOB.type_look_lazy[type] = TRUE
	GLOB.look_verdict_from_file[type] = TRUE // as if the verdict were read from the cache
	var/obj/plain = allocate(type, test_floor())
	var/obj/edited = allocate(type, test_floor())
	TEST_ASSERT(look_verdict_fits(plain), "an instance at its type's default is spared by the cached verdict")
	TEST_ASSERT(look_lazy_ok(plain), "and may be parked by a cached lazy verdict")
	edited.set_icon_state("dq_edited_state_that_is_not_the_default")
	TEST_ASSERT(!look_verdict_fits(edited), "an instance with an edited icon_state is not spared")
	TEST_ASSERT(!look_lazy_ok(edited), "and is never parked by a cached lazy verdict")
	TEST_ASSERT(GLOB.look_verdict_unfit > 0, "and the refusal is counted for the boot log")
	edited.set_icon_state(initial(edited.icon_state))
	edited.set_color("#ff0000")
	TEST_ASSERT(!look_verdict_fits(edited), "a colour edit is refused too")
	GLOB.look_verdict_from_file -= type
	TEST_ASSERT(look_verdict_fits(edited), "a verdict this boot sampled (not cached) is not judged per instance")
	GLOB.type_look_lazy[type] = was_lazy
	if(isnull(was_lazy))
		GLOB.type_look_lazy -= type
	if(was_cached)
		GLOB.look_verdict_from_file[type] = TRUE

/// A cache file that is not valid JSON (a write cut short, a hand edit) is ignored with a log and replaced by the next save; the replacement is whole.
/datum/unit_test/dq_look_verdict_cache_corrupt_file_ignored

/datum/unit_test/dq_look_verdict_cache_corrupt_file_ignored/Run()
	var/file = "data/look_verdicts_test_corrupt.json"
	set_global(nameof(GLOB.look_verdicts_saved), GLOB.look_verdicts_saved)
	fdel(file)
	text2file("{\"version\": 2, \"key\": \"cut sho", file)
	TEST_ASSERT(isnull(look_verdicts_read(file)), "a truncated document reads as nothing")
	fdel(file)
	text2file("\[1, 2]", file)
	TEST_ASSERT(isnull(look_verdicts_read(file)) || !look_verdicts_apply(look_verdicts_read(file)), "a document that is not an object applies nothing")
	TEST_ASSERT(look_verdicts_save(file), "the next save replaces the corrupt file")
	var/list/doc = look_verdicts_read(file)
	TEST_ASSERT(islist(doc) && doc["key"] == look_verdicts_key(), "with a whole document of this world")
	TEST_ASSERT(!fexists("[file].tmp"), "and leaves no temporary file")
	fdel(file)

/// A cache of another format version is refused, whatever else it says: the version is in the document and in the key.
/datum/unit_test/dq_look_verdict_cache_version_mismatch_rejected

/datum/unit_test/dq_look_verdict_cache_version_mismatch_rejected/Run()
	var/type = /obj/dq_stamp_plain
	var/was_stamp = GLOB.type_look_stamp[type]
	GLOB.type_look_stamp -= type
	TEST_ASSERT(findtext(look_verdicts_key(), "v[LOOK_VERDICTS_VERSION]|") == 1, "the key starts with the format version")
	var/list/doc = list("version" = LOOK_VERDICTS_VERSION - 1, "key" = look_verdicts_key(), "stamp" = list("[type]" = 1), "lazy" = list())
	TEST_ASSERT(!look_verdicts_apply(doc), "an older version is refused")
	doc -= "version"
	TEST_ASSERT(!look_verdicts_apply(doc), "a document with no version is refused")
	TEST_ASSERT(isnull(GLOB.type_look_stamp[type]), "and none of its verdicts are read")
	if(!isnull(was_stamp))
		GLOB.type_look_stamp[type] = was_stamp
