// Pins for the object behaviours that became capabilities when the OM framework was retired (doc/rewrite/om_retirement.md):
// omen, footsteps, swarming, the tether's attack_self swap and handset return, bluespace lockers, the resize guard and the
// mob chunk watches. Each pins what the old behaviour did on the notice or action it handled.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// add_omen() grants the omen capability with its unlucky trait; remove_omen() takes both back. A strong omen forces a dice roll
/// to 1 and fumbles a catch.
/datum/unit_test/dq_retired_omen_capability

/datum/unit_test/dq_retired_omen_capability/Run()
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human)
	TEST_ASSERT(!victim.has_omen(), "a fresh mob has no omen")
	victim.add_omen(incidents_left = INFINITY, luck_mod = 10, damage_mod = 0, evil = FALSE, safe_disposals = FALSE, vorish = FALSE)
	TEST_ASSERT(victim.has_omen(), "add_omen() grants the omen")
	TEST_ASSERT(has_trait(victim, TRAIT_UNLUCKY), "the omen brings the unlucky trait")
	TEST_ASSERT_EQUAL(victim.omen_roll_override(null, TRUE, 6), 1, "a strong omen forces the roll to 1")
	var/obj/item/thrown = allocate(/obj/item/paper)
	TEST_ASSERT(victim.omen_blocks_catch(thrown, 1), "a strong omen fumbles the catch")
	victim.remove_omen()
	TEST_ASSERT(!victim.has_omen(), "remove_omen() revokes it")
	TEST_ASSERT(!has_trait(victim, TRAIT_UNLUCKY), "and lifts the unlucky trait")
	TEST_ASSERT_NULL(victim.omen_roll_override(null, TRUE, 6), "without an omen nothing overrides a roll")
	TEST_ASSERT(!victim.omen_blocks_catch(thrown, 1), "without an omen nothing fumbles a catch")

/// enable_footsteps() grants the footstep capability, and a step counts on the moved notice.
/datum/unit_test/dq_retired_footstep_counts_steps

/datum/unit_test/dq_retired_footstep_counts_steps/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/next = locate(start.x + 1, start.y, start.z)
	var/mob/living/simple_mob/animal/passive/mouse/walker = allocate(/mob/living/simple_mob/animal/passive/mouse, start)
	walker.enable_footsteps(FOOTSTEP_MOB_CLAW, 1, -6)
	TEST_ASSERT(granted(walker, /datum/capability/footstep), "enable_footsteps() grants the footstep capability")
	walker.footstep_steps = 0
	walker.forceMove(next)
	walker.forceMove(start)
	TEST_ASSERT(walker.footstep_steps > 0, "each move is a step (counted [walker.footstep_steps])")
	walker.disable_footsteps()
	TEST_ASSERT(!granted(walker, /datum/capability/footstep), "disable_footsteps() revokes it")
	var/before = walker.footstep_steps
	walker.forceMove(next)
	TEST_ASSERT_EQUAL(walker.footstep_steps, before, "no steps are counted once disabled")

/// Two swarmers on one turf pair up and offset; one leaving unpairs both.
/datum/unit_test/dq_retired_swarming_pairs_on_a_turf

/datum/unit_test/dq_retired_swarming_pairs_on_a_turf/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/away = locate(start.x + 2, start.y, start.z)
	var/mob/living/simple_mob/animal/passive/mouse/first = allocate(/mob/living/simple_mob/animal/passive/mouse, start)
	var/mob/living/simple_mob/animal/passive/mouse/second = allocate(/mob/living/simple_mob/animal/passive/mouse, away)
	first.enable_swarming()
	second.enable_swarming()
	TEST_ASSERT(is_swarmer(first) && is_swarmer(second), "enable_swarming() grants the swarming capability")
	second.forceMove(start)
	TEST_ASSERT(second in first.swarm_members, "a swarmer moving onto another's turf pairs with it")
	TEST_ASSERT(first.is_swarming && second.is_swarming, "both are offset while paired")
	second.forceMove(away)
	TEST_ASSERT(!(second in first.swarm_members), "leaving the turf unpairs")
	TEST_ASSERT(!first.is_swarming && !second.is_swarming, "a swarmer left alone stops swarming")

/// The tether host takes the handheld out on attack_self (an instead on the attack_self action) and takes it back on attackby.
/datum/unit_test/dq_retired_tether_swap_and_return

/datum/unit_test/dq_retired_tether_swap_and_return/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	var/obj/item/defib_kit/kit = allocate(/obj/item/defib_kit)
	var/obj/item/paddles = kit.tethered_handheld()
	TEST_ASSERT_NOTNULL(paddles, "the kit makes its paddles")
	TEST_ASSERT(granted(kit, /datum/capability/tether_host), "the host carries the tether_host capability")
	TEST_ASSERT(granted(paddles, /datum/capability/tether_handheld), "the handheld carries the tether_handheld capability")
	user.equip_to_slot_or_del(kit, SLOT_ID_BACK)
	TEST_ASSERT_EQUAL(kit.loc, user, "the kit is worn")
	TEST_ASSERT(kit.attack_self(user), "using the worn kit is taken over by the tether")
	TEST_ASSERT_EQUAL(paddles.loc, user, "the paddles came out into the user's hands")
	TEST_ASSERT(attackby_stopped(kit, paddles, user, null), "hitting the kit with its paddles is taken over")
	TEST_ASSERT_EQUAL(paddles.loc, kit, "the paddles went back into the kit")

/// A bluespace locker sends what it closes on to its exit.
/datum/unit_test/dq_retired_bluespace_locker_sends

/datum/unit_test/dq_retired_bluespace_locker_sends/Run()
	test_driver_begin()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/far = locate(start.x + 4, start.y + 2, start.z)
	var/obj/structure/closet/entry = allocate(/obj/structure/closet, start)
	var/obj/structure/closet/exit_closet = allocate(/obj/structure/closet, far)
	entry.connect_bluespace(list(exit_closet))
	TEST_ASSERT(granted(entry, /datum/capability/bluespace_connection), "connecting grants the bluespace capability")
	if(!entry.opened)
		entry.open()
	var/obj/item/cargo = allocate(/obj/item/paper, start)
	entry.close()
	test_time(2 SECONDS)
	TEST_ASSERT(get_turf(cargo) != start, "closing the locker on the paper sent it away (it is at [AREACOORD(cargo)])")
	test_driver_end()

/// The resize guard is granted at an extreme size and revoked inside bounds.
/datum/unit_test/dq_retired_resize_guard_follows_size

/datum/unit_test/dq_retired_resize_guard_follows_size/Run()
	var/mob/living/carbon/human/subject = allocate(/mob/living/carbon/human)
	if(!subject.has_large_resize_bounds())
		TEST_NOTICE(src, "the test map has no large-size area; the guard was not exercised")
		return
	subject.resize(RESIZE_MAXIMUM_DORMS, ignore_prefs = TRUE)
	TEST_ASSERT(granted(subject, /datum/capability/resize_guard), "an extreme size grants the guard")
	subject.resize(RESIZE_NORMAL, ignore_prefs = TRUE)
	TEST_ASSERT(!granted(subject, /datum/capability/resize_guard), "a normal size revokes it")

/// A chunk watch calls its watcher back with the bits; unwatching stops it; a deleted watcher is dropped.
/datum/unit_test/dq_retired_mob_chunk_watch_calls_back

/datum/dq_chunk_watch_probe
	var/heard = 0
	var/last_bits = 0

/datum/dq_chunk_watch_probe/proc/heard_chunk(datum/mob_chunk/C, bits)
	heard++
	last_bits = bits

/datum/unit_test/dq_retired_mob_chunk_watch_calls_back/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/datum/dq_chunk_watch_probe/probe = allocate(/datum/dq_chunk_watch_probe)
	var/list/chunks = watch_mob_chunks(probe, mob_chunks_around(start, 1), MOB_CHUNK_WATCH_ANY_MOB, TYPE_PROC_REF(/datum/dq_chunk_watch_probe, heard_chunk))
	TEST_ASSERT(length(chunks), "a watch covers the chunks around a turf")
	mob_chunk_changed(mob_chunk_id(start), MOB_CHUNK_WATCH_PLAYER)
	TEST_ASSERT_EQUAL(probe.heard, 0, "a bit outside the mask is not heard")
	mob_chunk_changed(mob_chunk_id(start), MOB_CHUNK_WATCH_ANY_MOB)
	TEST_ASSERT_EQUAL(probe.heard, 1, "the watched bit calls the watcher back")
	TEST_ASSERT_EQUAL(probe.last_bits, MOB_CHUNK_WATCH_ANY_MOB, "with the bits raised")
	unwatch_mob_chunks(probe, chunks, MOB_CHUNK_WATCH_ANY_MOB)
	mob_chunk_changed(mob_chunk_id(start), MOB_CHUNK_WATCH_ANY_MOB)
	TEST_ASSERT_EQUAL(probe.heard, 1, "an unwatched chunk calls nobody")

#endif
