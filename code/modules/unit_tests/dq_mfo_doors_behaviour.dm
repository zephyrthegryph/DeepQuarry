// Behaviour pins for rewrite/missing-forms: what walking into a door does (the bump action), what a simple mob's smash does to a door (the
// generic hit) and what a door looks like open and shut (draw()). Written against the legacy Bumped()/attack_generic()/update_icon() forms and
// pinned green on them before the conversion; every assertion that changes on purpose is a row of doc/rewrite/intended_changes.md
// ("Missing forms") and says so beside it.
//
// They reuse the dq_p2_door harness (dq_p2_door_behaviour.dm): its fixtures, adapters, kernel clock and settle(). The inputs are public: a mob
// walking into the door (its own Bump(), the movement path), a simple mob's attack (apply_attack(), the path its AI takes), and the look read
// after the refresh queue drains.

/// `mover` walks into `target`: the movement path's Bump(), as a blocked step calls it.
/proc/mfo_walk_into(atom/movable/mover, atom/target)
	mover.Bump(target)

/// A simple mob's attack on `target` for `damage`, as its AI lands one.
/proc/mfo_smash(mob/living/simple_mob/M, atom/target, damage)
	M.apply_attack(target, damage)

/// The icon state `A` shows once every pending redraw has run.
/proc/mfo_look(atom/A)
	A.update_icon()
	refresh_flush()
	return A.icon_state

// =====================================================================================================================
// Walking into a door
// =====================================================================================================================

/datum/unit_test/dq_p2_door/mfo_walk_into_airlock_opens_with_access

/datum/unit_test/dq_p2_door/mfo_walk_into_airlock_opens_with_access/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(list(ACCESS_ENGINE))
	mfo_walk_into(H, D)
	settle()
	TEST_ASSERT(!D.density, "walking into the door with its access opens it")

/datum/unit_test/dq_p2_door/mfo_walk_into_airlock_denied_without_access

/datum/unit_test/dq_p2_door/mfo_walk_into_airlock_denied_without_access/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/H = make_person(list(ACCESS_SECURITY))
	mfo_walk_into(H, D)
	settle()
	TEST_ASSERT(D.density, "walking into the door without its access leaves it shut")
	TEST_ASSERT(!D.operating, "and it does not move")

/// An electrified door whose shock finds no power to land (the test room has no APC) lets the walker through as an unelectrified one would.
/datum/unit_test/dq_p2_door/mfo_walk_into_live_airlock_without_a_grid_opens

/datum/unit_test/dq_p2_door/mfo_walk_into_live_airlock_without_a_grid_opens/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	D.electrify(-1)
	TEST_ASSERT(p2_door_electrified(D), "the door is live")
	var/mob/living/carbon/human/H = make_person(list(ACCESS_ENGINE))
	mfo_walk_into(H, D)
	settle()
	TEST_ASSERT(!D.density, "the shock found nothing to land with: the bump went on and opened it")

/datum/unit_test/dq_p2_door/mfo_walk_into_open_panel_airlock_does_nothing

/datum/unit_test/dq_p2_door/mfo_walk_into_open_panel_airlock_does_nothing/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock)
	var/mob/living/carbon/human/H = make_person(null)
	click(H, D, give_tool(H, /obj/item/tool/screwdriver))
	TEST_ASSERT(p2_door_panel_open(D), "the panel is open")
	mfo_walk_into(H, D)
	settle()
	TEST_ASSERT(D.density, "a door with its panel open ignores a walker")

/// A pest (a mouse nobody plays) never bumps a door open, even one anybody may use.
/datum/unit_test/dq_p2_door/mfo_walk_into_airlock_pest_does_nothing

/datum/unit_test/dq_p2_door/mfo_walk_into_airlock_pest_does_nothing/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, tile(3, 2))
	add_trait(M, TRAIT_AMBIENT_PEST_MOB, "mf_test")
	mfo_walk_into(M, D)
	settle()
	TEST_ASSERT(D.density, "a pest's bump does not open the door")

/// A drone (UAV) flying into a door opens a public one and is denied by one with access.
/datum/unit_test/dq_p2_door/mfo_uav_opens_a_public_door_only

/datum/unit_test/dq_p2_door/mfo_uav_opens_a_public_door_only/run_gate()
	var/obj/machinery/door/airlock/locked = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/obj/item/uav/U = allocate(/obj/item/uav, tile(3, 2))
	mfo_walk_into(U, locked)
	settle()
	TEST_ASSERT(locked.density, "a door with access is shut to a drone")
	locked.req_access = null
	mfo_walk_into(U, locked)
	settle()
	TEST_ASSERT(!locked.density, "a public door opens for one")

/// A bot whose card has the access opens the door it runs into.
/datum/unit_test/dq_p2_door/mfo_bot_opens_with_its_card

/datum/unit_test/dq_p2_door/mfo_bot_opens_with_its_card/run_gate()
	var/obj/machinery/door/airlock/D = make_door(/obj/machinery/door/airlock, list(ACCESS_ENGINE))
	var/mob/living/bot/cleanbot/B = allocate(/mob/living/bot/cleanbot, tile(3, 2))
	B.botcard.access = list(ACCESS_ENGINE)
	mfo_walk_into(B, D)
	settle()
	TEST_ASSERT(!D.density, "the bot's card opened it")

/// A windoor opens for a walker with its access and stays shut to one without.
/datum/unit_test/dq_p2_door/mfo_walk_into_windoor

/datum/unit_test/dq_p2_door/mfo_walk_into_windoor/run_gate()
	var/obj/machinery/door/window/D = make_door(/obj/machinery/door/window, list(ACCESS_ENGINE))
	var/mob/living/carbon/human/stranger = make_person(list(ACCESS_SECURITY))
	mfo_walk_into(stranger, D)
	settle()
	TEST_ASSERT(D.density, "no access: the windoor stays shut")
	var/mob/living/carbon/human/H = make_person(list(ACCESS_ENGINE), tile(3, 3))
	mfo_walk_into(H, D)
	test_time(1 SECONDS)
	TEST_ASSERT(!D.density, "with access it opens")

/// A shut blast door ignores whoever walks into it, access or not.
/datum/unit_test/dq_p2_door/mfo_walk_into_blast_door_does_nothing

/datum/unit_test/dq_p2_door/mfo_walk_into_blast_door_does_nothing/run_gate()
	var/obj/machinery/door/blast/regular/D = make_door(/obj/machinery/door/blast/regular)
	var/mob/living/carbon/human/H = make_person(list(ACCESS_ENGINE))
	mfo_walk_into(H, D)
	settle()
	TEST_ASSERT(D.density, "a blast door answers only its button")

/// Walking into the transport pod gets you in.
/datum/unit_test/dq_p2_door/mfo_walk_into_transport_pod

/datum/unit_test/dq_p2_door/mfo_walk_into_transport_pod/run_gate()
	var/obj/machinery/transportpod/P = allocate(/obj/machinery/transportpod, tile(2, 2))
	var/mob/living/carbon/human/H = make_person(null, tile(3, 3))
	mfo_walk_into(H, P)
	settle()
	TEST_ASSERT_EQUAL(occupant_of(P), H, "walking into the pod puts you inside")
	p2_door_answer(H, FALSE)
	settle()

// =====================================================================================================================
// A simple mob's smash
// =====================================================================================================================

/// A powered airlock takes a strong smash as damage and stays shut; a weak one does nothing.
/datum/unit_test/dq_p2_door/mfo_smash_powered_airlock_takes_damage

/datum/unit_test/dq_p2_door/mfo_smash_powered_airlock_takes_damage/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, tile(3, 2))
	var/whole = D.get_integrity()
	mfo_smash(M, D, 1)
	settle()
	TEST_ASSERT_EQUAL(D.get_integrity(), whole, "a bonk does nothing")
	mfo_smash(M, D, 50)
	settle()
	TEST_ASSERT(D.get_integrity() < whole, "a strong smash damages it")
	TEST_ASSERT(D.density, "and it stays shut")
	tidy(tile(2, 2))

/// A dead airlock: a weak smash strains for nothing; a strong one forces it open, then shut.
/datum/unit_test/dq_p2_door/mfo_smash_dead_airlock_forces_it

/datum/unit_test/dq_p2_door/mfo_smash_dead_airlock_forces_it/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	p2_door_set_power(D, FALSE)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, tile(3, 2))
	mfo_smash(M, D, 1)
	settle()
	TEST_ASSERT(D.density, "a weak animal strains for nothing")
	mfo_smash(M, D, 50)
	settle()
	TEST_ASSERT(!D.density, "a strong one forces it open")
	mfo_smash(M, D, 50)
	settle()
	TEST_ASSERT(D.density, "and shut again")
	tidy(tile(2, 2))

/// A dead, bolted airlock is broken into (an op that takes ten seconds), bolts and all.
/datum/unit_test/dq_p2_door/mfo_smash_dead_bolted_airlock_breaks_in

/datum/unit_test/dq_p2_door/mfo_smash_dead_bolted_airlock_breaks_in/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	p2_door_set_power(D, FALSE)
	p2_door_set_bolts(D, TRUE)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, tile(3, 2))
	mfo_smash(M, D, 50)
	test_time(5 SECONDS)
	TEST_ASSERT(D.density, "not yet")
	test_time(6 SECONDS)
	TEST_ASSERT(!D.density, "it breaks in")
	TEST_ASSERT(!p2_door_bolted(D), "through the bolts")
	tidy(tile(2, 2))

/// A dead blast door is forced open by a strong animal, slowly.
/datum/unit_test/dq_p2_door/mfo_smash_dead_blast_door_is_forced

/datum/unit_test/dq_p2_door/mfo_smash_dead_blast_door_is_forced/run_gate()
	var/obj/machinery/door/blast/regular/D = make_door(/obj/machinery/door/blast/regular)
	p2_door_set_power(D, FALSE)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, tile(3, 2))
	mfo_smash(M, D, 1)
	test_time(6 SECONDS)
	TEST_ASSERT(D.density, "a weak animal strains for nothing")
	mfo_smash(M, D, 50)
	test_time(6 SECONDS)
	TEST_ASSERT(!D.density, "a strong one forces it open")
	tidy(tile(2, 2))

/// A door with no smash of its own (a windoor) takes a strong smash as damage, and a bonk as nothing.
/datum/unit_test/dq_p2_door/mfo_smash_windoor_takes_damage

/datum/unit_test/dq_p2_door/mfo_smash_windoor_takes_damage/run_gate()
	var/obj/machinery/door/window/D = make_door(/obj/machinery/door/window)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, tile(3, 2))
	var/whole = D.get_integrity()
	mfo_smash(M, D, 1)
	settle()
	TEST_ASSERT_EQUAL(D.get_integrity(), whole, "a bonk does nothing")
	mfo_smash(M, D, 20)
	settle()
	TEST_ASSERT(D.get_integrity() < whole, "a strong smash damages it")
	tidy(tile(2, 2))

// =====================================================================================================================
// How a door looks
// =====================================================================================================================

/datum/unit_test/dq_p2_door/mfo_look_blast_door

/datum/unit_test/dq_p2_door/mfo_look_blast_door/run_gate()
	var/obj/machinery/door/blast/regular/D = make_door(/obj/machinery/door/blast/regular)
	TEST_ASSERT_EQUAL(mfo_look(D), "pdoor1", "a shut blast door")
	D.force_open()
	settle()
	TEST_ASSERT_EQUAL(mfo_look(D), "pdoor0", "an open one")
	D.force_close()
	settle()
	TEST_ASSERT_EQUAL(mfo_look(D), "pdoor1", "shut again")

/datum/unit_test/dq_p2_door/mfo_look_windoor

/datum/unit_test/dq_p2_door/mfo_look_windoor/run_gate()
	var/obj/machinery/door/window/D = make_door(/obj/machinery/door/window)
	TEST_ASSERT_EQUAL(mfo_look(D), "left", "a shut windoor")
	D.open()
	settle()
	TEST_ASSERT_EQUAL(mfo_look(D), "leftopen", "an open one")

/datum/unit_test/dq_p2_door/mfo_look_plain_door

/datum/unit_test/dq_p2_door/mfo_look_plain_door/run_gate()
	var/obj/machinery/door/morgue/D = make_door(/obj/machinery/door/morgue)
	TEST_ASSERT_EQUAL(mfo_look(D), "door1", "a shut door")
	D.open()
	settle()
	TEST_ASSERT_EQUAL(mfo_look(D), "door0", "an open one")

/datum/unit_test/dq_p2_door/mfo_look_airlock

/datum/unit_test/dq_p2_door/mfo_look_airlock/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	TEST_ASSERT_EQUAL(mfo_look(D), "door_closed", "a shut airlock")
	D.open()
	settle()
	TEST_ASSERT_EQUAL(mfo_look(D), "door_open", "an open one")
	D.close()
	settle()
	p2_door_set_bolts(D, TRUE)
	settle()
	TEST_ASSERT_EQUAL(mfo_look(D), "door_locked", "a bolted one with its lights on")
