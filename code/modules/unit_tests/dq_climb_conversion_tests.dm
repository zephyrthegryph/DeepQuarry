// What the climbing structures do, written against the legacy behaviour first and kept green on the library's climb() capability
// (code/library/structures/climb.dm): the default climb, a machine, a railing (vaulting, and breaking when it is not anchored), a cliff (climbing
// shoes, half the time for a double cliff), a flipped table, and shaking climbers off (a crate opening, a structure moving). Each test drags the
// climber onto the structure the way a player does, and reads where the climber stands.

/datum/unit_test/dq_climb
	abstract_type = /datum/unit_test/dq_climb

/datum/unit_test/dq_climb/Run()
	test_driver_begin()
	test_rng(1)
	run_gate()
	for(var/dx in 0 to 3)
		for(var/dy in 0 to 3)
			var/turf/T = floor_at(dx, dy)
			if(T)
				own_turf_contents(T)
	test_driver_end()

/datum/unit_test/dq_climb/proc/run_gate()
	return

/// The floor `dx` east and `dy` north of the block's bottom left corner.
/datum/unit_test/dq_climb/proc/floor_at(dx, dy)
	var/turf/origin = run_loc_floor_bottom_left
	return locate(origin.x + dx, origin.y + dy, origin.z)

/// A conscious person with hands, who cannot be knocked out by the test's passing time.
/datum/unit_test/dq_climb/proc/actor(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || floor_at(0, 0))
	H.enable_godmode()
	return H

/// The climber drags itself onto the structure, as a player does.
/datum/unit_test/dq_climb/proc/climb_it(mob/living/climber, atom/movable/S)
	climber.next_click = 0
	return test_drag(climber, climber, S)

// ---------------------------------------------------------------------------------------------------------------------
// The default climb
// ---------------------------------------------------------------------------------------------------------------------

/// A crate takes three and a half seconds and ends with the climber on its tile.
/datum/unit_test/dq_climb/a_crate_takes_three_and_a_half_seconds

/datum/unit_test/dq_climb/a_crate_takes_three_and_a_half_seconds/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/closet/crate/C = allocate(/obj/structure/closet/crate, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	climb_it(H, C)
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, floor_at(1, 0), "still at the foot of the crate after three seconds")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(H.loc, at, "on the crate after four")

/// A machine can be climbed too (a water tank is one the old code made climbable).
/datum/unit_test/dq_climb/a_tank_can_be_climbed

/datum/unit_test/dq_climb/a_tank_can_be_climbed/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/reagent_dispensers/watertank/W = allocate(/obj/structure/reagent_dispensers/watertank, at)
	TEST_ASSERT(has_trait(W, TRAIT_CLIMBABLE), "a water tank is climbable")
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	climb_it(H, W)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, at, "the climber is on the tank's tile")

/// What stands on the tile the climber would land on, and is solid and not climbable, stops the climb.
/datum/unit_test/dq_climb/a_solid_thing_on_the_tile_stops_the_climb

/datum/unit_test/dq_climb/a_solid_thing_on_the_tile_stops_the_climb/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/closet/crate/C = allocate(/obj/structure/closet/crate, at)
	var/obj/structure/grille/G = allocate(/obj/structure/grille, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	TEST_ASSERT(G.density, "the grille is solid")
	climb_it(H, C)
	test_time(6 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, floor_at(1, 0), "the climber did not get onto the crate")

/// A climber that walks off before the end does not arrive.
/datum/unit_test/dq_climb/a_climber_that_walks_off_does_not_arrive

/datum/unit_test/dq_climb/a_climber_that_walks_off_does_not_arrive/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/closet/crate/C = allocate(/obj/structure/closet/crate, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	climb_it(H, C)
	test_time(1 SECOND)
	H.forceMove(floor_at(2, 0))
	test_time(6 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, floor_at(2, 0), "the climber stays where it went")

// ---------------------------------------------------------------------------------------------------------------------
// Railings
// ---------------------------------------------------------------------------------------------------------------------

/// A railing climbed from the side lands on its tile; climbed again from its own tile it goes over to the tile it faces.
/datum/unit_test/dq_climb/a_railing_is_climbed_onto_then_over

/datum/unit_test/dq_climb/a_railing_is_climbed_onto_then_over/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/railing/R = allocate(/obj/structure/railing, at)
	R.dir = EAST
	var/mob/living/carbon/human/H = actor(floor_at(0, 1))
	climb_it(H, R)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, at, "onto the railing's tile")
	TEST_ASSERT(!QDELETED(R), "an anchored railing does not break")
	climb_it(H, R)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, floor_at(2, 1), "and over, to the tile it faces")
	TEST_ASSERT(!QDELETED(R), "the anchored railing still stands")

/// A railing that is not anchored breaks under the climber.
/datum/unit_test/dq_climb/an_unanchored_railing_breaks_under_the_climber

/datum/unit_test/dq_climb/an_unanchored_railing_breaks_under_the_climber/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/railing/R = allocate(/obj/structure/railing, at)
	R.dir = EAST
	R.set_anchored(FALSE)
	var/mob/living/carbon/human/H = actor(floor_at(0, 1))
	climb_it(H, R)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, at, "the climber got on the railing's tile")
	TEST_ASSERT(QDELETED(R) || R.get_integrity() <= 0, "and the railing broke")

/// A ledge is vaulted: from its own tile the climb goes over it.
/datum/unit_test/dq_climb/a_ledge_is_vaulted

/datum/unit_test/dq_climb/a_ledge_is_vaulted/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/ledge/L = allocate(/obj/structure/ledge, at)
	L.dir = EAST
	var/mob/living/carbon/human/H = actor(floor_at(0, 1))
	climb_it(H, L)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, at, "onto the ledge")
	climb_it(H, L)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, floor_at(2, 1), "and over it")

// ---------------------------------------------------------------------------------------------------------------------
// Cliffs
// ---------------------------------------------------------------------------------------------------------------------

/// Without climbing shoes a cliff is too steep: the climber never gets up.
/datum/unit_test/dq_climb/a_cliff_is_too_steep_without_climbing_shoes

/datum/unit_test/dq_climb/a_cliff_is_too_steep_without_climbing_shoes/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/cliff/C = allocate(/obj/structure/cliff, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	climb_it(H, C)
	test_time(15 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, floor_at(1, 0), "the climber stays at the bottom")

/// With climbing shoes it takes ten seconds.
/datum/unit_test/dq_climb/a_cliff_is_climbed_in_climbing_shoes

/datum/unit_test/dq_climb/a_cliff_is_climbed_in_climbing_shoes/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/cliff/C = allocate(/obj/structure/cliff, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/clothing/shoes/S = allocate(/obj/item/clothing/shoes/boots/winter/climbing)
	H.equip_to_slot_if_possible(S, SLOT_ID_SHOES)
	TEST_ASSERT_EQUAL(H.get_equipped_item(SLOT_ID_SHOES), S, "the climber wears the shoes")
	climb_it(H, C)
	test_time(9 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, floor_at(1, 0), "still at the bottom after nine seconds")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, at, "up after eleven")

/// A double cliff takes half the time.
/datum/unit_test/dq_climb/a_double_cliff_takes_half_the_time

/datum/unit_test/dq_climb/a_double_cliff_takes_half_the_time/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/cliff/C = allocate(/obj/structure/cliff, at)
	C.is_double_cliff = TRUE
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/obj/item/clothing/shoes/S = allocate(/obj/item/clothing/shoes/boots/winter/climbing)
	H.equip_to_slot_if_possible(S, SLOT_ID_SHOES)
	climb_it(H, C)
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, floor_at(1, 0), "still at the bottom after four seconds")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, at, "up after six")

// ---------------------------------------------------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------------------------------------------------

/// A table is climbed like any structure.
/datum/unit_test/dq_climb/a_table_is_climbed

/datum/unit_test/dq_climb/a_table_is_climbed/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	climb_it(H, T)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, at, "the climber is on the table's tile")

/// A climber standing on a flipped table climbs out the side the table faces (the old table's rule never moved them at all).
/datum/unit_test/dq_climb/a_flipped_table_is_climbed_out_the_side_it_faces

/datum/unit_test/dq_climb/a_flipped_table_is_climbed_out_the_side_it_faces/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/table/T = allocate(/obj/structure/table/steel, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	test_menu(H, T, "flip")
	TEST_ASSERT_EQUAL(T.flipped, 1, "the table is flipped")
	TEST_ASSERT_EQUAL(T.dir, NORTH, "facing north")
	climb_it(H, T)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, at, "the climber is on the table's tile")
	climb_it(H, T)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, floor_at(1, 2), "and climbing again from there goes out the side the table faces")

/// The menu offers Climb on a structure, and picking it is the same climb.
/datum/unit_test/dq_climb/the_menu_climb_is_the_same_climb

/datum/unit_test/dq_climb/the_menu_climb_is_the_same_climb/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/closet/crate/C = allocate(/obj/structure/closet/crate, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/datum/op_result/picked = test_menu(H, C, "climb.climb_menu")
	TEST_ASSERT_NOTNULL(picked, "the menu offers Climb")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, at, "the climber is on the crate's tile")

// ---------------------------------------------------------------------------------------------------------------------
// Fences
// ---------------------------------------------------------------------------------------------------------------------

/// An intact fence cannot be climbed; one cut to a medium hole can; one cut large is walked through, not climbed.
/datum/unit_test/dq_climb/a_fence_is_climbed_through_a_medium_hole

/datum/unit_test/dq_climb/a_fence_is_climbed_through_a_medium_hole/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/fence/intact = allocate(/obj/structure/fence, at)
	var/mob/living/carbon/human/H = actor(floor_at(1, 0))
	var/datum/op_result/refused = climb_it(H, intact)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(H.loc, floor_at(1, 0), "an intact fence is not climbed (refused: [refused?.reason])")
	var/obj/structure/fence/medium = allocate(/obj/structure/fence/cut/medium, floor_at(2, 1))
	var/mob/living/carbon/human/H2 = actor(floor_at(2, 0))
	climb_it(H2, medium)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(H2.loc, get_turf(medium), "a medium hole is climbed through")
	var/obj/structure/fence/large = allocate(/obj/structure/fence/cut/large, floor_at(3, 1))
	var/mob/living/carbon/human/H3 = actor(floor_at(3, 0))
	climb_it(H3, large)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(H3.loc, floor_at(3, 0), "a large hole is walked through, not climbed")

/// What is not climbable is not offered a climb.
/datum/unit_test/dq_climb/a_huge_scrubber_is_not_climbable

/datum/unit_test/dq_climb/a_huge_scrubber_is_not_climbable/run_gate()
	var/obj/machinery/portable_atmospherics/powered/scrubber/S = allocate(/obj/machinery/portable_atmospherics/powered/scrubber, floor_at(1, 1))
	var/obj/machinery/portable_atmospherics/powered/scrubber/huge/H = allocate(/obj/machinery/portable_atmospherics/powered/scrubber/huge, floor_at(2, 1))
	TEST_ASSERT(has_trait(S, TRAIT_CLIMBABLE), "a portable scrubber is climbable")
	TEST_ASSERT(!has_trait(H, TRAIT_CLIMBABLE), "a huge one is not")

// ---------------------------------------------------------------------------------------------------------------------
// Shaking climbers off
// ---------------------------------------------------------------------------------------------------------------------

/// Opening a crate shakes off whoever is climbing it.
/datum/unit_test/dq_climb/opening_a_crate_shakes_off_its_climber

/datum/unit_test/dq_climb/opening_a_crate_shakes_off_its_climber/run_gate()
	var/turf/at = floor_at(1, 1)
	var/obj/structure/closet/crate/C = allocate(/obj/structure/closet/crate, at)
	var/mob/living/carbon/human/climber = allocate(/mob/living/carbon/human, floor_at(1, 0)) // no godmode: it can be knocked down
	climb_it(climber, C)
	test_time(1 SECOND)
	C.open()
	TEST_ASSERT(climber.status_units(STAT_WEAKENED) > 0, "the climber was knocked down")
	test_time(8 SECONDS)
	TEST_ASSERT_EQUAL(climber.loc, floor_at(1, 0), "and never made it up")

/// A structure that is moved by something unforced shakes its climbers off.
/datum/unit_test/dq_climb/moving_a_structure_shakes_off_its_climber

/datum/unit_test/dq_climb/moving_a_structure_shakes_off_its_climber/run_gate()
	var/obj/structure/closet/crate/C = allocate(/obj/structure/closet/crate, floor_at(1, 1))
	var/mob/living/carbon/human/climber = allocate(/mob/living/carbon/human, floor_at(1, 0))
	climb_it(climber, C)
	test_time(1 SECOND)
	C.Move(floor_at(2, 1))
	TEST_ASSERT_EQUAL(C.loc, floor_at(2, 1), "the crate moved")
	TEST_ASSERT(climber.status_units(STAT_WEAKENED) > 0, "the climber was knocked down")
	test_time(8 SECONDS)
	TEST_ASSERT_EQUAL(climber.loc, floor_at(1, 0), "and never made it up")

/// Someone who shakes a structure with no climbers on it shakes nobody.
/datum/unit_test/dq_climb/shaking_an_empty_structure_does_nothing

/datum/unit_test/dq_climb/shaking_an_empty_structure_does_nothing/run_gate()
	var/obj/structure/closet/crate/C = allocate(/obj/structure/closet/crate, floor_at(1, 1))
	var/mob/living/carbon/human/bystander = actor(floor_at(1, 0))
	climb_shake_off(C, bystander)
	TEST_ASSERT_EQUAL(bystander.status_units(STAT_WEAKENED), 0, "nobody was knocked down")

/// A climber cannot shake itself off.
/datum/unit_test/dq_climb/a_climber_cannot_shake_itself_off

/datum/unit_test/dq_climb/a_climber_cannot_shake_itself_off/run_gate()
	var/obj/structure/closet/crate/C = allocate(/obj/structure/closet/crate, floor_at(1, 1))
	var/mob/living/carbon/human/climber = allocate(/mob/living/carbon/human, floor_at(1, 0))
	climb_it(climber, C)
	test_time(1 SECOND)
	climb_shake_off(C, climber)
	TEST_ASSERT_EQUAL(climber.status_units(STAT_WEAKENED), 0, "the climber is not knocked down by its own shake")
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(climber.loc, C.loc, "and gets up")
