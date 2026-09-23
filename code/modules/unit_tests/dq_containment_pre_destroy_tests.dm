// The pre-destroy phase (J1, doc/rewrite/containment.md §2.4): qdel() releases
// a holder's contents through the normal transaction API while it is still
// fully valid, before Destroy() tears anything down. code/controllers/subsystems/garbage.dm,
// code/datums/containment/{api,ledger,latent}.dm, code/game/atoms_movable.dm.

// ---- Fixtures ----

/// A holder whose pre_destroy() we can observe from outside.
/obj/structure/closet/dq_pre_destroy_probe

/// Something that qdels itself from inside its own pre-destroy phase, to
/// prove a re-entrant qdel(src) during the phase completes cleanly.
/// has_pre_destroy_override opts it in: it declares no slots of its own.
/obj/item/dq_pre_destroy_requeler
	name = "requeler"
	has_pre_destroy_override = TRUE

/obj/item/dq_pre_destroy_requeler/pre_destroy(force)
	. = ..()
	qdel(src)

/// A type that opts into the pre-destroy phase without declaring any slots,
/// to prove has_pre_destroy_override works on its own.
/datum/dq_pre_destroy_override_only
	has_pre_destroy_override = TRUE
	var/ran = FALSE

/datum/dq_pre_destroy_override_only/pre_destroy(force)
	ran = TRUE

/// A plain datum that never opts in: its qdel() must never call pre_destroy().
/datum/dq_pre_destroy_plain
	var/ran = FALSE

/datum/dq_pre_destroy_plain/pre_destroy(force)
	ran = TRUE // if this ever runs, the type-gating in qdel() is broken

// ---- Tests ----

/datum/unit_test/dq_pre_destroy_releases_while_valid

/datum/unit_test/dq_pre_destroy_releases_while_valid/Run()
	var/turf/T = dq_containment_floor()
	var/obj/structure/closet/dq_pre_destroy_probe/closet = allocate(/obj/structure/closet/dq_pre_destroy_probe, T)
	var/obj/item/dq_containment_test/steel = allocate(/obj/item/dq_containment_test, T)
	closet.open()
	TEST_ASSERT(steel.move_into(closet), "steel in")
	closet.close()

	var/datum/dq_containment_listener/listener = allocate(/datum/dq_containment_listener)
	listener.watch(closet)

	GLOB.dq_pre_destroy_watch_item = steel
	GLOB.dq_pre_destroy_watch_result_valid = FALSE
	GLOB.dq_pre_destroy_watch_result_contents = FALSE
	RegisterSignal(closet, COMSIG_PRE_QDELETING, PROC_REF(dq_pre_destroy_watch_signal))

	qdel(closet)

	TEST_ASSERT(GLOB.dq_pre_destroy_watch_result_valid, "the holder was not QDELETED yet when COMSIG_PRE_QDELETING fired")
	TEST_ASSERT(GLOB.dq_pre_destroy_watch_result_contents, "steel was still inside when the pre-destroy signal fired")
	TEST_ASSERT_EQUAL(steel.loc, T, "steel was released to the drop location")
	TEST_ASSERT_EQUAL(jointext(listener.events, ","), "out:[CONTAINER_SLOT_INTERIOR]", "the release went through the normal commit bookkeeping")
	GLOB.dq_pre_destroy_watch_item = null

/// Globals used by the signal handler procs below -- a signal handler can't
/// close over unit-test locals, so they read/write these instead.
GLOBAL_VAR(dq_pre_destroy_watch_item)
GLOBAL_VAR(dq_pre_destroy_watch_result_valid)
GLOBAL_VAR(dq_pre_destroy_watch_result_contents)
GLOBAL_VAR(dq_pre_destroy_insert_result)

/datum/unit_test/proc/dq_pre_destroy_watch_signal(atom/source, force)
	SIGNAL_HANDLER
	GLOB.dq_pre_destroy_watch_result_valid = !QDELETED(source)
	GLOB.dq_pre_destroy_watch_result_contents = (GLOB.dq_pre_destroy_watch_item in source)

/datum/unit_test/dq_pre_destroy_reentrant_qdel

/datum/unit_test/dq_pre_destroy_reentrant_qdel/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_pre_destroy_requeler/thing = allocate(/obj/item/dq_pre_destroy_requeler, T)
	qdel(thing)
	TEST_ASSERT(QDELETED(thing), "qdel(src) called from inside pre_destroy() completed the deletion")

/datum/unit_test/dq_pre_destroy_latent_entries_drop

/datum/unit_test/dq_pre_destroy_latent_entries_drop/Run()
	var/turf/T = dq_containment_floor()
	var/obj/structure/closet/dq_pre_destroy_probe/closet = allocate(/obj/structure/closet/dq_pre_destroy_probe, T)
	closet.open()
	closet.close()
	var/datum/ledger/L = dq_ledger(closet)
	var/datum/latent_entry/entry = L.latent_add(/obj/item/dq_containment_test, 3)
	TEST_ASSERT_NOTNULL(entry, "a latent entry was declared")
	TEST_ASSERT_EQUAL(L.latent_count(), 3, "three latent things")

	qdel(closet)

	var/found = 0
	for(var/obj/item/dq_containment_test/I in T)
		found++
	TEST_ASSERT_EQUAL(found, 3, "the latent entries materialized onto the drop location when the holder was destroyed")

/datum/unit_test/dq_pre_destroy_refuses_inserts

/datum/unit_test/dq_pre_destroy_refuses_inserts/Run()
	var/turf/T = dq_containment_floor()
	var/obj/structure/closet/dq_pre_destroy_probe/closet = allocate(/obj/structure/closet/dq_pre_destroy_probe, T)
	closet.open()
	closet.close()
	var/obj/item/dq_containment_test/steel = allocate(/obj/item/dq_containment_test, T)

	GLOB.dq_pre_destroy_watch_item = steel
	GLOB.dq_pre_destroy_insert_result = null
	RegisterSignal(closet, COMSIG_PRE_QDELETING, PROC_REF(dq_pre_destroy_try_insert_signal))

	qdel(closet)

	TEST_ASSERT_EQUAL(GLOB.dq_pre_destroy_insert_result, FALSE, "a move into a pre-destroying holder is refused")
	TEST_ASSERT_EQUAL(steel.loc, T, "and the item never moved")
	GLOB.dq_pre_destroy_watch_item = null

/datum/unit_test/proc/dq_pre_destroy_try_insert_signal(atom/source, force)
	SIGNAL_HANDLER
	GLOB.dq_pre_destroy_insert_result = GLOB.dq_pre_destroy_watch_item.move_into(source)

/datum/unit_test/dq_pre_destroy_type_gating

/datum/unit_test/dq_pre_destroy_type_gating/Run()
	var/datum/dq_pre_destroy_override_only/opted_in = allocate(/datum/dq_pre_destroy_override_only)
	qdel(opted_in)
	TEST_ASSERT(opted_in.ran, "has_pre_destroy_override alone opts a non-holder type into the phase")

	var/datum/dq_pre_destroy_plain/plain = allocate(/datum/dq_pre_destroy_plain)
	qdel(plain)
	TEST_ASSERT(!plain.ran, "a type that never opts in never runs pre_destroy()")

/// Boot-check style coverage for "a slot holder must not return
/// QDEL_HINT_LETMELIVE from a forced Destroy()" (J1): force-qdel one
/// instance of each object-level holder type that is cheap and safe to spin
/// up outside its owning system, and check SSgarbage's own no_respect_force
/// counter didn't move. Mob/body and mecha holders are covered by their own
/// lifecycle tests instead of here.
/datum/unit_test/dq_pre_destroy_no_letmelive_holders

/datum/unit_test/dq_pre_destroy_no_letmelive_holders/Run()
	var/turf/T = dq_containment_floor()
	var/list/holder_types = list(
		/obj/structure/closet,
		/obj/structure/closet/crate,
		/obj/item/folder,
		/obj/item/storage/backpack,
	)
	for(var/path in holder_types)
		var/atom/movable/instance = allocate(path, T)
		var/datum/qdel_item/info = SSgarbage.items[path]
		var/before = info?.no_respect_force || 0
		qdel(instance, TRUE)
		info = SSgarbage.items[path]
		var/after = info?.no_respect_force || 0
		TEST_ASSERT_EQUAL(after, before, "[path] respects force in Destroy() (doesn't return QDEL_HINT_LETMELIVE)")
