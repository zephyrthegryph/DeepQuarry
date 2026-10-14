// The structure capabilities of the library (doc/rewrite/final_api.html, section 11, Structures): buckle() and climb(), on the fixtures of
// code/tests/library/fixtures.dm. Every test drives the engine through the test driver (test_drag, test_click, test_menu, test_answer, test_time) and
// reads what the world did: who is buckled to what, where a climber stands, and the op's outcome and reason.

/datum/unit_test/dq_lib_structures
	abstract_type = /datum/unit_test/dq_lib_structures

/datum/unit_test/dq_lib_structures/Run()
	test_driver_begin()
	run_gate()
	test_driver_end()

/datum/unit_test/dq_lib_structures/proc/run_gate()
	return

/// A fixture actor with hands, standing on the test tile.
/datum/unit_test/dq_lib_structures/proc/actor(type = /mob/living/simple_mob/e0_fixture)
	return allocate(type)

/// The tile east of the test tile.
/datum/unit_test/dq_lib_structures/proc/east_tile()
	return get_step(run_loc_floor_bottom_left, EAST)

/// A tile too far from the test tile for anything to be adjacent.
/datum/unit_test/dq_lib_structures/proc/far_tile()
	return run_loc_floor_top_right

// ---------------------------------------------------------------------------------------------------------------------
// buckle
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_lib_structures/buckle_self_drag_sits_at_once

/datum/unit_test/dq_lib_structures/buckle_self_drag_sits_at_once/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/lib_fixture/chair/chair = allocate(/obj/lib_fixture/chair)
	var/datum/op_result/sat = test_drag(M, M, chair)
	TEST_ASSERT_NOTNULL(sat, "a mob dragged onto the chair by itself resolves")
	TEST_ASSERT_EQUAL(sat.key, "buckle.buckle_self", "to the self-buckle op")
	TEST_ASSERT_EQUAL(sat.outcome, ACT_COMMITTED, "which commits with no wait")
	TEST_ASSERT_EQUAL(M.buckled_to(), chair, "the mob is buckled to the chair (the relation's near end)")
	TEST_ASSERT(M in chair.buckled_mob_list(), "and the chair lists it (the far end)")
	TEST_ASSERT_EQUAL(length(chair.buckled_mob_list()), 1, "alone")

/datum/unit_test/dq_lib_structures/buckle_drag_waits_then_buckles

/datum/unit_test/dq_lib_structures/buckle_drag_waits_then_buckles/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/mob/living/simple_mob/e0_fixture/V = actor()
	var/obj/lib_fixture/chair/chair = allocate(/obj/lib_fixture/chair)
	var/datum/op_result/buckling = test_drag(M, V, chair)
	TEST_ASSERT_NOTNULL(buckling, "dragging someone else onto the chair resolves")
	TEST_ASSERT_EQUAL(buckling.key, "buckle.buckle_drag", "to the drag op, not the self-buckle")
	TEST_ASSERT_NULL(buckling.outcome, "which waits")
	TEST_ASSERT_NULL(V.buckled_to(), "nobody is buckled while it waits")
	test_time(1 SECONDS)
	TEST_ASSERT_NULL(buckling.outcome, "still waiting half a second before the end")
	test_time(0.5 SECONDS)
	TEST_ASSERT_EQUAL(buckling.outcome, ACT_COMMITTED, "the wait ends and the buckling commits")
	TEST_ASSERT_EQUAL(V.buckled_to(), chair, "the dragged mob is buckled")
	TEST_ASSERT_NULL(M.buckled_to(), "and the one who dragged it is not")

/datum/unit_test/dq_lib_structures/buckle_drag_rechecks_after_the_wait

/datum/unit_test/dq_lib_structures/buckle_drag_rechecks_after_the_wait/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/mob/living/simple_mob/e0_fixture/V = actor()
	var/obj/lib_fixture/chair/chair = allocate(/obj/lib_fixture/chair)
	var/datum/op_result/buckling = test_drag(M, V, chair)
	TEST_ASSERT_NULL(buckling?.outcome, "the drag waits")
	V.forceMove(far_tile())
	test_time(1.5 SECONDS)
	TEST_ASSERT_NOTNULL(buckling?.outcome, "it ends")
	TEST_ASSERT(buckling?.outcome != ACT_COMMITTED, "but not committed: the one to buckle walked away during the wait")
	TEST_ASSERT_NULL(V.buckled_to(), "so nobody is buckled")

/datum/unit_test/dq_lib_structures/buckle_refusals_are_requirements

/datum/unit_test/dq_lib_structures/buckle_refusals_are_requirements/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/mob/living/simple_mob/e0_fixture/first = actor()
	var/mob/living/simple_mob/e0_fixture/second = actor()
	var/obj/lib_fixture/chair/chair = allocate(/obj/lib_fixture/chair)
	var/obj/lib_fixture/chair/other_chair = allocate(/obj/lib_fixture/chair)
	test_drag(first, first, chair)
	TEST_ASSERT_EQUAL(first.buckled_to(), chair, "the first sits")
	// a full chair
	var/datum/op_result/full = test_drag(second, second, chair)
	TEST_ASSERT_EQUAL(full?.outcome, ACT_REFUSED, "a one-seat chair refuses a second sitter")
	TEST_ASSERT_EQUAL(full?.reason, MSG(buckle/full), "because it is full")
	TEST_ASSERT_NULL(second.buckled_to(), "and nobody moved")
	// already seated elsewhere
	var/datum/op_result/seated = test_drag(first, first, other_chair)
	TEST_ASSERT_EQUAL(seated?.outcome, ACT_REFUSED, "someone already buckled to one chair is refused by another")
	TEST_ASSERT_EQUAL(seated?.reason, MSG(buckle/seated), "because they are buckled to something")
	var/datum/op_result/again = test_drag(first, first, chair)
	TEST_ASSERT_EQUAL(again?.reason, MSG(buckle/seated_here), "and to the same chair, because they are already on it")
	// the chair is full: someone else is refused at once, without a wait
	var/datum/op_result/refused_drag = test_drag(M, second, chair)
	TEST_ASSERT_EQUAL(refused_drag?.outcome, ACT_REFUSED, "a refusal comes before the wait, not after it")
	TEST_ASSERT_EQUAL(refused_drag?.reason, MSG(buckle/full), "with the same reason")

/datum/unit_test/dq_lib_structures/buckle_restrained_takes_only_the_restrained

/datum/unit_test/dq_lib_structures/buckle_restrained_takes_only_the_restrained/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/mob/living/simple_mob/e0_fixture/free = actor()
	var/mob/living/simple_mob/e0_fixture/lib_cuffed/cuffed = actor(/mob/living/simple_mob/e0_fixture/lib_cuffed)
	var/obj/lib_fixture/clamp/clamp = allocate(/obj/lib_fixture/clamp)
	var/datum/op_result/refused = test_drag(M, free, clamp)
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "a clamp refuses someone who is not restrained")
	TEST_ASSERT_EQUAL(refused?.reason, MSG(buckle/restrained_only), "and says so")
	var/datum/op_result/taken = test_drag(M, cuffed, clamp)
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(taken?.outcome, ACT_COMMITTED, "it buckles a restrained one")
	TEST_ASSERT_EQUAL(cuffed.buckled_to(), clamp, "who is buckled")

/datum/unit_test/dq_lib_structures/buckle_slots_and_delay_are_the_settings

/datum/unit_test/dq_lib_structures/buckle_slots_and_delay_are_the_settings/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/mob/living/simple_mob/e0_fixture/one = actor()
	var/mob/living/simple_mob/e0_fixture/two = actor()
	var/mob/living/simple_mob/e0_fixture/three = actor()
	var/obj/lib_fixture/sofa/sofa = allocate(/obj/lib_fixture/sofa)
	test_drag(one, one, sofa)
	test_drag(two, two, sofa)
	TEST_ASSERT_EQUAL(length(sofa.buckled_mob_list()), 2, "a sofa seats two (slots = 2), whatever the old max_buckled_mobs var says")
	var/datum/op_result/third = test_drag(M, three, sofa)
	TEST_ASSERT_EQUAL(third?.reason, MSG(buckle/full), "and not a third")
	// the wait of a sofa is its own delay (3 seconds)
	var/obj/lib_fixture/sofa/empty = allocate(/obj/lib_fixture/sofa)
	var/datum/op_result/slow = test_drag(M, three, empty)
	test_time(2.5 SECONDS)
	TEST_ASSERT_NULL(slow?.outcome, "buckling someone onto a sofa is still waiting after 2.5 seconds")
	test_time(0.5 SECONDS)
	TEST_ASSERT_EQUAL(slow?.outcome, ACT_COMMITTED, "and done at 3")
	TEST_ASSERT_EQUAL(three.buckled_to(), empty, "with the mob buckled")

/datum/unit_test/dq_lib_structures/buckle_structure_carries_its_occupant

/datum/unit_test/dq_lib_structures/buckle_structure_carries_its_occupant/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/lib_fixture/chair/chair = allocate(/obj/lib_fixture/chair)
	test_drag(M, M, chair)
	var/turf/dest = east_tile()
	chair.Move(dest, EAST)
	TEST_ASSERT_EQUAL(chair.loc, dest, "the chair moved")
	TEST_ASSERT_EQUAL(M.loc, dest, "and its occupant went with it")
	TEST_ASSERT_EQUAL(M.buckled_to(), chair, "still buckled")

/datum/unit_test/dq_lib_structures/buckle_unbuckle_frees_the_occupant

/datum/unit_test/dq_lib_structures/buckle_unbuckle_frees_the_occupant/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/mob/living/simple_mob/e0_fixture/V = actor()
	var/obj/lib_fixture/chair/chair = allocate(/obj/lib_fixture/chair)
	var/datum/op_result/nobody = test_click(M, chair, null)
	TEST_ASSERT(!nobody || nobody.key != "buckle.unbuckle", "an empty hand on an empty chair does not mean unbuckle")
	test_drag(V, V, chair)
	var/datum/op_result/freed = test_click(M, chair, null)
	TEST_ASSERT_NOTNULL(freed, "an empty hand on a chair with someone on it resolves")
	TEST_ASSERT_EQUAL(freed.key, "buckle.unbuckle", "to unbuckle")
	TEST_ASSERT_EQUAL(freed.outcome, ACT_COMMITTED, "which commits")
	TEST_ASSERT_NULL(V.buckled_to(), "the occupant is free")
	TEST_ASSERT_EQUAL(length(chair.buckled_mob_list()), 0, "and the chair is empty")

/datum/unit_test/dq_lib_structures/buckle_unbuckle_asks_which_of_several

/datum/unit_test/dq_lib_structures/buckle_unbuckle_asks_which_of_several/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/mob/living/simple_mob/e0_fixture/one = actor()
	var/mob/living/simple_mob/e0_fixture/two = actor()
	var/obj/lib_fixture/sofa/sofa = allocate(/obj/lib_fixture/sofa)
	test_drag(one, one, sofa)
	test_drag(two, two, sofa)
	var/datum/op_result/asking = test_click(M, sofa, null)
	TEST_ASSERT_EQUAL(asking?.key, "buckle.unbuckle", "an empty hand on a sofa with two on it is the unbuckle op")
	TEST_ASSERT_NULL(asking?.outcome, "which asks who")
	TEST_ASSERT_EQUAL(length(sofa.buckled_mob_list()), 2, "and frees nobody yet")
	var/second_name = "[two] (2)" // both fixtures share a name: the second is told apart
	var/datum/op_result/answered = test_answer(M, second_name)
	TEST_ASSERT_EQUAL(answered?.outcome, ACT_COMMITTED, "the answer commits it")
	TEST_ASSERT_NULL(two.buckled_to(), "the one picked is free")
	TEST_ASSERT_EQUAL(one.buckled_to(), sofa, "and the other is still buckled")

/datum/unit_test/dq_lib_structures/buckle_destroying_the_structure_frees_its_occupant

/datum/unit_test/dq_lib_structures/buckle_destroying_the_structure_frees_its_occupant/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/lib_fixture/chair/chair = new(run_loc_floor_bottom_left)
	test_drag(M, M, chair)
	TEST_ASSERT_EQUAL(M.buckled_to(), chair, "buckled")
	qdel(chair)
	TEST_ASSERT_NULL(M.buckled_to(), "deleting the chair frees its occupant: the relation is torn down with it")

/datum/unit_test/dq_lib_structures/buckle_a_held_mob_is_buckled_after_the_wait

/datum/unit_test/dq_lib_structures/buckle_a_held_mob_is_buckled_after_the_wait/run_gate()
	var/mob/living/carbon/human/holder_mob = allocate(/mob/living/carbon/human)
	var/mob/living/simple_mob/e0_fixture/V = actor()
	var/obj/lib_fixture/chair/chair = allocate(/obj/lib_fixture/chair)
	var/obj/item/grab/G = new(holder_mob, V)
	TEST_ASSERT(!QDELETED(G), "the grab holds the mob")
	holder_mob.put_in_active_hand(G)
	var/datum/op_result/buckling = test_click(holder_mob, chair, G)
	TEST_ASSERT_EQUAL(buckling?.key, "buckle.buckle_grab", "a held grab used on the chair is the grab op")
	TEST_ASSERT_NULL(buckling?.outcome, "which waits (refused: [buckling?.reason])")
	test_time(1.5 SECONDS)
	TEST_ASSERT_EQUAL(buckling?.outcome, ACT_COMMITTED, "and commits")
	TEST_ASSERT_EQUAL(V.buckled_to(), chair, "the held mob is buckled")

// ---------------------------------------------------------------------------------------------------------------------
// climb
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_lib_structures/climb_waits_then_moves_onto_the_tile

/datum/unit_test/dq_lib_structures/climb_waits_then_moves_onto_the_tile/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/lib_fixture/crate/crate = allocate(/obj/lib_fixture/crate)
	var/turf/crate_tile = get_turf(crate)
	M.forceMove(east_tile())
	TEST_ASSERT(has_trait(crate, TRAIT_CLIMBABLE), "a holder with climb() is climbable (the trait the old behaviour added)")
	var/datum/op_result/climbing = test_drag(M, M, crate)
	TEST_ASSERT_NOTNULL(climbing, "a mob dragged onto a crate by itself resolves")
	TEST_ASSERT_EQUAL(climbing.key, "climb.climb", "to the climb op")
	TEST_ASSERT_NULL(climbing.outcome, "which waits")
	test_time(3 SECONDS)
	TEST_ASSERT_NULL(climbing.outcome, "still waiting half a second before the end")
	TEST_ASSERT(get_turf(M) != crate_tile, "the climber has not moved yet")
	test_time(0.5 SECONDS)
	TEST_ASSERT_EQUAL(climbing.outcome, ACT_COMMITTED, "the wait ends and the climb commits")
	TEST_ASSERT_EQUAL(get_turf(M), crate_tile, "the climber stands on the crate's tile")

/datum/unit_test/dq_lib_structures/climb_menu_entry_is_the_same_climb

/datum/unit_test/dq_lib_structures/climb_menu_entry_is_the_same_climb/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/lib_fixture/crate/crate = allocate(/obj/lib_fixture/crate)
	M.forceMove(east_tile())
	var/datum/op_result/picked = test_menu(M, crate, "climb.climb_menu")
	TEST_ASSERT_EQUAL(picked?.origin, ORIGIN_MENU, "picked from the context menu it runs with that origin")
	test_time(3.5 SECONDS)
	TEST_ASSERT_EQUAL(picked?.outcome, ACT_COMMITTED, "and commits")
	TEST_ASSERT_EQUAL(get_turf(M), get_turf(crate), "with the climber on the tile")

/datum/unit_test/dq_lib_structures/climb_refuses_a_blocked_tile

/datum/unit_test/dq_lib_structures/climb_refuses_a_blocked_tile/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/lib_fixture/crate/crate = allocate(/obj/lib_fixture/crate)
	var/obj/lib_fixture/boulder/boulder = allocate(/obj/lib_fixture/boulder)
	M.forceMove(east_tile())
	var/datum/op_result/refused = test_drag(M, M, crate)
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "a solid thing on the crate's tile stops the climb")
	TEST_ASSERT(findtext("[refused?.reason]", "in the way"), "and the reason names it")
	TEST_ASSERT(get_turf(M) != get_turf(crate), "the climber did not move")
	qdel(boulder)
	var/datum/op_result/clear = test_drag(M, M, crate)
	TEST_ASSERT_NULL(clear?.outcome, "with it gone the climb is allowed (it waits)")
	test_time(3.5 SECONDS)
	TEST_ASSERT_EQUAL(get_turf(M), get_turf(crate), "and done")

/datum/unit_test/dq_lib_structures/climb_is_cancelled_when_the_climber_walks_off

/datum/unit_test/dq_lib_structures/climb_is_cancelled_when_the_climber_walks_off/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/lib_fixture/crate/crate = allocate(/obj/lib_fixture/crate)
	M.forceMove(east_tile())
	var/datum/op_result/climbing = test_drag(M, M, crate)
	TEST_ASSERT_NULL(climbing?.outcome, "the climb waits")
	M.forceMove(far_tile())
	test_time(3.5 SECONDS)
	TEST_ASSERT(climbing?.outcome != ACT_COMMITTED, "walking off ends it uncommitted")
	TEST_ASSERT(get_turf(M) != get_turf(crate), "and the mob never arrives")

/datum/unit_test/dq_lib_structures/climb_needs_hands_and_legs_free

/datum/unit_test/dq_lib_structures/climb_needs_hands_and_legs_free/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/lib_fixture/crate/crate = allocate(/obj/lib_fixture/crate, east_tile())
	var/obj/lib_fixture/chair/chair = allocate(/obj/lib_fixture/chair)
	test_drag(M, M, chair)
	TEST_ASSERT_EQUAL(M.buckled_to(), chair, "buckled")
	var/datum/op_result/refused = test_drag(M, M, crate)
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "a buckled mob cannot climb")
	TEST_ASSERT_EQUAL(refused?.reason, MSG(climb/hands_needed), "it needs its hands and legs free")
	var/mob/living/simple_mob/e0_fixture/lib_cuffed/cuffed = actor(/mob/living/simple_mob/e0_fixture/lib_cuffed)
	var/datum/op_result/cuffed_refusal = test_drag(cuffed, cuffed, crate)
	TEST_ASSERT_EQUAL(cuffed_refusal?.reason, MSG(climb/hands_needed), "and a restrained one cannot either")

/datum/unit_test/dq_lib_structures/climb_vaulting_goes_over_a_railing

/datum/unit_test/dq_lib_structures/climb_vaulting_goes_over_a_railing/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/lib_fixture/railing/railing = allocate(/obj/lib_fixture/railing, east_tile())
	var/turf/railing_tile = get_turf(railing)
	var/turf/facing = get_step(railing, railing.dir)
	// from the back (the railing faces east, the mob stands west of it) the climb lands on the railing's own tile
	var/datum/op_result/onto = test_drag(M, M, railing)
	TEST_ASSERT_EQUAL(onto?.key, "climb.climb", "a mob next to the railing climbs it")
	test_time(1.5 SECONDS)
	TEST_ASSERT_NULL(onto?.outcome, "the railing's delay is 2 seconds")
	test_time(0.5 SECONDS)
	TEST_ASSERT_EQUAL(onto?.outcome, ACT_COMMITTED, "and the climb commits")
	TEST_ASSERT_EQUAL(get_turf(M), railing_tile, "the climber is on the railing's own tile")
	// from the railing's own tile, the climb goes over it to the tile it faces
	var/datum/op_result/over = test_drag(M, M, railing)
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(over?.outcome, ACT_COMMITTED, "climbing again from its tile commits")
	TEST_ASSERT_EQUAL(get_turf(M), facing, "and goes over the railing to the facing tile")
