// blocks() (code/datums/capabilities/library/block.dm).

/obj/item/cap_fixture/blocker/capabilities()
	. = ..()
	. += blocks(chance = 100, verb = "parries")

/obj/item/cap_fixture/blocker/never/capabilities()
	. = ..()
	. = without(., /datum/capability/block)
	. += blocks(chance = 0)

/obj/item/cap_fixture/blocker/wielded/capabilities()
	. = ..()
	. = without(., /datum/capability/block)
	. += two_handed()
	. += blocks(chance = 100, needs_wielded = TRUE, projectiles = TRUE)

/datum/unit_test/dx_cap_block

/datum/unit_test/dx_cap_block/Run()
	var/turf/floor = test_floor()
	var/turf/front = get_step(floor, NORTH)
	var/turf/behind = get_step(floor, SOUTH)
	TEST_ASSERT(front && behind, "the test floor needs neighbours")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, floor)
	var/mob/living/carbon/human/ahead = allocate(/mob/living/carbon/human, front)
	var/mob/living/carbon/human/sneak = allocate(/mob/living/carbon/human, behind)
	H.set_dir(NORTH)

	var/obj/item/cap_fixture/blocker/B = allocate(/obj/item/cap_fixture/blocker, floor)
	TEST_ASSERT("It can turn aside blows." in B.caps_examine(H), "examine describes the block")
	TEST_ASSERT(H.put_in_r_hand(B), "held")
	TEST_ASSERT(H.check_shields(10, null, ahead, BP_TORSO, "the test") > 0, "a held blocker stops a hit from the front")
	TEST_ASSERT_EQUAL(H.check_shields(10, null, sneak, BP_TORSO, "the test"), 0, "but not from behind")
	var/obj/item/projectile/shot = allocate(/obj/item/projectile, front)
	TEST_ASSERT_EQUAL(H.check_shields(10, shot, null, BP_TORSO, "the shot"), 0, "a parry doesn't stop projectiles")
	H.drop_from_inventory(B, floor)

	var/obj/item/cap_fixture/blocker/never/N = allocate(/obj/item/cap_fixture/blocker/never, floor)
	TEST_ASSERT(H.put_in_r_hand(N), "held")
	TEST_ASSERT_EQUAL(H.check_shields(10, null, ahead, BP_TORSO, "the test"), 0, "chance 0 never blocks")
	H.drop_from_inventory(N, floor)

	var/obj/item/cap_fixture/blocker/wielded/W = allocate(/obj/item/cap_fixture/blocker/wielded, floor)
	TEST_ASSERT("Held in both hands, it can turn aside blows and shots." in W.caps_examine(H), "examine names the wielding")
	TEST_ASSERT(H.put_in_r_hand(W), "held")
	TEST_ASSERT_EQUAL(H.check_shields(10, null, ahead, BP_TORSO, "the test"), 0, "needs_wielded: one hand doesn't block")
	TEST_ASSERT(W.attack_self(H), "wield it")
	TEST_ASSERT(H.check_shields(10, null, ahead, BP_TORSO, "the test") > 0, "wielded, it blocks")
	shot.forceMove(front)
	shot.starting = front
	TEST_ASSERT(H.check_shields(10, shot, null, BP_TORSO, "the shot") > 0, "projectiles = TRUE stops a shot from the front")
	H.drop_from_inventory(W, floor)
