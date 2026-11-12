/**
 * The space turf's build ops and the mineral turf's dig ops: one op per tool, refusals as requirements with their reasons, timed digs as waits.
 * Space tests use a space turf of the test map (the actor stands on it); mineral tests change the tile east of the test floor and put it back.
 */
/datum/unit_test/dq_turf_ops
	abstract_type = /datum/unit_test/dq_turf_ops
	var/list/tile_at
	var/tile_type

/datum/unit_test/dq_turf_ops/Run()
	set_global(nameof(GLOB.turf_change_calls), GLOB.turf_change_calls) // the builds change turfs: teardown restores the count
	test_driver_begin()
	run_ops()
	test_driver_end()

/datum/unit_test/dq_turf_ops/proc/run_ops()
	return

/// `held` in the active hand of `user`, and a click on `target` with it.
/datum/unit_test/dq_turf_ops/proc/click_with(mob/living/user, atom/target, obj/item/held)
	if(user.get_active_hand() != held)
		if(user.get_active_hand())
			user.drop_item()
		user.put_in_active_hand(held)
	STATE_SET(user, cooldowns, next_click, 0)
	return test_click(user, target, held)

/// A bare space turf of the test map: no lattice, nothing on it.
/datum/unit_test/dq_turf_ops/proc/bare_space()
	RETURN_TYPE(/turf/space)
	for(var/turf/space/S in world)
		if(S.x > 2 && S.y > 2 && S.x < world.maxx - 2 && S.y < world.maxy - 2 && !contents_count(S) && !S.edge)
			return S
	return null

/datum/unit_test/dq_turf_ops/proc/take_tile()
	var/turf/T = get_step(test_floor(), EAST)
	TEST_ASSERT(istype(T, /turf/simulated), "the test map has a simulated tile east of the test floor")
	tile_at = list(T.x, T.y, T.z)
	tile_type = T.type

/datum/unit_test/dq_turf_ops/proc/tile()
	RETURN_TYPE(/turf)
	return locate(tile_at[1], tile_at[2], tile_at[3])

/datum/unit_test/dq_turf_ops/proc/make_tile(type)
	RETURN_TYPE(/turf)
	var/turf/made = tile().ChangeTurf(type)
	stat_drain_point()
	return made

/datum/unit_test/dq_turf_ops/proc/put_tile_back()
	for(var/obj/O in tile())
		qdel(O)
	make_tile(tile_type)

// ---- space ----

/// Rods on bare space build a lattice and spend one rod; rods on that lattice upgrade it to a catwalk.
/datum/unit_test/dq_turf_ops/space_rods_build_lattice_then_catwalk/run_ops()
	var/turf/space/S = bare_space()
	TEST_ASSERT_NOTNULL(S, "the test map has bare space")
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, S)
	var/obj/item/stack/rods/R = allocate(/obj/item/stack/rods, S)
	R.set_amount(10)
	var/datum/op_result/built = click_with(user, S, R)
	TEST_ASSERT_EQUAL(built?.key, "space_build_lattice", "rods on bare space build a lattice")
	TEST_ASSERT_EQUAL(built?.outcome, ACT_COMMITTED, "and it commits")
	TEST_ASSERT_NOTNULL(locate_within(S, /obj/structure/lattice), "a lattice is on the space")
	TEST_ASSERT_EQUAL(R.get_amount(), 9, "one rod is spent")
	var/datum/op_result/upgraded = click_with(user, S, R)
	TEST_ASSERT_EQUAL(upgraded?.key, "space_upgrade_lattice", "rods on the lattice upgrade it")
	TEST_ASSERT_EQUAL(upgraded?.outcome, ACT_COMMITTED, "and it commits")
	TEST_ASSERT_NOTNULL(locate_within(S, /obj/structure/catwalk), "a catwalk replaced the lattice")
	TEST_ASSERT_EQUAL(R.get_amount(), 8, "one more rod is spent")
	for(var/obj/structure/O in S)
		qdel(O)

/// Floor tiles on bare space are refused with the support reason; on a lattice they plate the turf and spend one tile.
/datum/unit_test/dq_turf_ops/space_tiles_need_a_lattice/run_ops()
	var/turf/space/S = bare_space()
	TEST_ASSERT_NOTNULL(S, "the test map has bare space")
	var/list/at = list(S.x, S.y, S.z)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, S)
	var/obj/item/stack/tile/floor/F = allocate(/obj/item/stack/tile/floor, S)
	F.set_amount(5)
	var/datum/op_result/refused = click_with(user, S, F)
	TEST_ASSERT_EQUAL(refused?.key, "space_plate", "tiles on space pick the plating op")
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "with no lattice it is refused")
	TEST_ASSERT_EQUAL(refused?.reason, /datum/msg/space/needs_support, "for want of support")
	TEST_ASSERT_EQUAL(F.get_amount(), 5, "and no tile is spent")
	S.ReplaceWithLattice()
	var/datum/op_result/plated = click_with(user, S, F)
	TEST_ASSERT_EQUAL(plated?.outcome, ACT_COMMITTED, "on a lattice the plating commits")
	var/turf/now = locate(at[1], at[2], at[3])
	TEST_ASSERT(istype(now, /turf/simulated/floor/airless), "the space is plated: [now.type]")
	TEST_ASSERT_EQUAL(F.get_amount(), 4, "one tile is spent")
	TEST_ASSERT_NULL(locate_within(now, /obj/structure/lattice), "the lattice is used up")
	qdel(user)
	qdel(F)
	now.ChangeTurf(/turf/space)

// ---- mineral ----

/// A pickaxe on rock waits its dig speed, then mines the rock out to sand.
/datum/unit_test/dq_turf_ops/mineral_pickaxe_digs_rock/run_ops()
	take_tile()
	var/turf/simulated/mineral/M = make_tile(/turf/simulated/mineral)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/pickaxe/P = allocate(/obj/item/pickaxe, test_floor())
	var/datum/op_result/digging = click_with(user, M, P)
	TEST_ASSERT_EQUAL(digging?.key, "mineral_pick", "a pickaxe on rock picks the dig op")
	TEST_ASSERT_NULL(digging?.outcome, "and waits")
	TEST_ASSERT(M.density, "the rock stands while the pick works")
	test_time(P.digspeed + 1)
	TEST_ASSERT_EQUAL(digging?.outcome, ACT_COMMITTED, "the dig commits after its wait")
	TEST_ASSERT(!tile().density, "the rock is mined out")
	put_tile_back()

/// A drill digs a hole in sand: the wait, then the sand is dug; a second dig is refused with the already-dug reason.
/datum/unit_test/dq_turf_ops/mineral_drill_digs_sand_once/run_ops()
	take_tile()
	var/turf/simulated/mineral/M = make_tile(/turf/simulated/mineral/floor)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/pickaxe/drill/D = allocate(/obj/item/pickaxe/drill, test_floor())
	var/datum/op_result/digging = click_with(user, M, D)
	TEST_ASSERT_EQUAL(digging?.key, "mineral_dig_hole", "a drill on sand digs a hole")
	TEST_ASSERT_NULL(digging?.outcome, "and waits")
	test_time(D.digspeed + 1)
	TEST_ASSERT_EQUAL(digging?.outcome, ACT_COMMITTED, "the hole commits after its wait")
	TEST_ASSERT(M.sand_dug, "the sand is dug")
	var/datum/op_result/again = click_with(user, M, D)
	TEST_ASSERT_EQUAL(again?.outcome, ACT_REFUSED, "a second dig is refused")
	TEST_ASSERT_EQUAL(again?.reason, /datum/msg/mineral/already_dug, "because the sand is already dug")
	put_tile_back()

/// A shock maul held in one hand is refused with the wield reason and leaves the rock as it was.
/datum/unit_test/dq_turf_ops/mineral_maul_needs_both_hands/run_ops()
	take_tile()
	var/turf/simulated/mineral/M = make_tile(/turf/simulated/mineral)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/melee/shock_maul/S = allocate(/obj/item/melee/shock_maul, test_floor())
	var/depth = M.excavation_level
	user.put_in_active_hand(S)
	user.put_in_inactive_hand(allocate(/obj/item/pickaxe, test_floor())) // the other hand is full: the maul is held in one hand
	S.update_held_icon()
	TEST_ASSERT(!S.wielded, "test precondition: the maul is held in one hand")
	var/datum/op_result/refused = click_with(user, M, S)
	TEST_ASSERT_EQUAL(refused?.key, "mineral_maul", "a maul on rock picks the smash op")
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "unwielded it is refused")
	TEST_ASSERT_EQUAL(refused?.reason, /datum/msg/mineral/maul_unwielded, "for want of both hands")
	TEST_ASSERT(M.density && M.excavation_level == depth, "the rock is untouched")
	put_tile_back()
