// Tables that used to key by REF() text now key by ref_token(): a live entity is found, a deleted one resolves to nothing.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_ref_text_chunk_living_tokens

/datum/unit_test/dq_ref_text_chunk_living_tokens/Run()
	var/turf/T = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/id = mob_chunk_id(T)
	var/mob/living/L = allocate(/mob/living, T)
	var/datum/mob_chunk/C = mob_chunk(id)
	living_chunk_note(L, id, TRUE)
	TEST_ASSERT(L in living_in_chunk(id), "a noted living mob is listed by living_in_chunk()")
	TEST_ASSERT(C.living_refs[ref_token(L)], "the chunk keys the mob by its token")
	living_chunk_note(L, id, FALSE)
	TEST_ASSERT(!(L in living_in_chunk(id)), "a mob that left the chunk is no longer listed")
	living_chunk_note(L, id, TRUE)
	qdel(L)
	for(var/mob/living/other in living_in_chunk(id))
		TEST_ASSERT(!QDELETED(other), "a deleted mob never resolves from the chunk")

/datum/unit_test/dq_ref_text_chunk_watcher_removal

/datum/unit_test/dq_ref_text_chunk_watcher_removal/Run()
	var/turf/T = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/datum/om_wake_test_subscriber/watcher = new
	var/list/chunks = mob_chunks_around(T, 0)
	watch_mob_chunks(watcher, chunks, MOB_CHUNK_WATCH_ANY_MOB, TYPE_PROC_REF(/datum/om_wake_test_subscriber, chunk_woke))
	var/datum/mob_chunk/C = chunks[1]
	TEST_ASSERT(C.watchers[ref_token(watcher)], "the watch is filed under the watcher's token")
	unwatch_mob_chunks(watcher, chunks, MOB_CHUNK_WATCH_ANY_MOB)
	TEST_ASSERT(!LAZYLEN(C.watchers) || !C.watchers[ref_token(watcher)], "unwatch drops the watch")

/// A watcher that unwatches in its teardown (an AI pack does) loses its entry the moment it is qdel()ed, not on the next raise.
/datum/unit_test/dq_ref_text_chunk_deleted_pack_unwatches_at_once

/datum/unit_test/dq_ref_text_chunk_deleted_pack_unwatches_at_once/Run()
	var/turf/T = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/list/chunks = mob_chunks_around(T, 0)
	var/datum/mob_chunk/C = chunks[1]
	var/datum/ai_pack/pack = new /datum/ai_pack("test")
	pack.cover_chunks(chunks)
	var/token = ref_token(pack)
	TEST_ASSERT(C.watchers[token], "the pack's watch is filed under its token")
	qdel(pack)
	TEST_ASSERT(!LAZYLEN(C.watchers) || !C.watchers[token], "qdel() removed the pack's watch at once")


/datum/unit_test/dq_ref_text_ore_silo_logs_by_token

/datum/unit_test/dq_ref_text_ore_silo_logs_by_token/Run()
	var/turf/T = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/obj/machinery/ore_silo/silo = allocate(/obj/machinery/ore_silo, T)
	silo.silo_log(silo, "inserted", 1, "sheet", list("iron" = 1))
	TEST_ASSERT(length(GLOB.silo_access_logs[ref_token(silo)]), "the silo's log is filed under its token")
	GLOB.silo_access_logs -= ref_token(silo)

#endif
