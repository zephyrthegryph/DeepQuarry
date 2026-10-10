// Behaviour pins for the /mob/living timed abilities of group I in round 3 of the timed-action lane (rewrite/timed3-I), on the harness of
// dq_timed_pin_w8_behaviour.dm. The ops live in living_abilities() (code/library/mob/living_abilities.dm). Only what a test can reach without a
// prompt or a belly is pinned: the butchering of a carcass and the cuts of meat, laying and making eggs, and writing on a body. The beast form revert,
// melee swing (dq_melee_swing_tests.dm), vore ops (absorb devour, vertical nom, holo nom, beacon insert, eat minerals), the predator / prey control
// transfers and the wall climb need a belly, a second mind, a holopad or a prompt answer the driver does not reach.

/datum/unit_test/dq_timed_pin_w11I
	abstract_type = /datum/unit_test/dq_timed_pin_w11I
	parent_type = /datum/unit_test/dq_timed_pin_w8

// ---- Butchering a carcass: the time scales with the animal's size and the loot lands on its tile ----

/datum/unit_test/dq_timed_pin_w11I/butcher_carcass
	loss_cancels = TRUE
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w11I/butcher_carcass/setup_scene()
	user = person()
	var/mob/living/simple_mob/carcass = allocate(/mob/living/simple_mob/animal/passive/crab, run_loc_floor_bottom_left)
	carcass.meat_amount = 0
	carcass.butchery_loot = list(/obj/item/reagent_containers/food/snacks/meat = 1)
	carcass.butchery_drops_organs = FALSE
	carcass.set_stat(DEAD)
	target = carcass
	held = hold(/obj/item/material/knife)
	duration = max(1 TICK, 2 SECONDS * carcass.mob_size / 10)

/datum/unit_test/dq_timed_pin_w11I/butcher_carcass/start_click()
	test_chat_clear()
	var/mob/living/carcass = target
	carcass.harvest(user, held)

/datum/unit_test/dq_timed_pin_w11I/butcher_carcass/is_done()
	var/mob/living/carcass = target
	return QDELETED(carcass) || !LAZYLEN(carcass.butchery_loot)

/datum/unit_test/dq_timed_pin_w11I/butcher_carcass/extra_pin()
	// a second butcher is refused while the first one works on the carcass
	setup_scene()
	start_click()
	TEST_ASSERT(!isnull(running(user)), "the first butcher is working")
	var/mob/living/carbon/human/second = other()
	var/mob/living/carcass = target
	TEST_ASSERT(op_claimed(carcass), "the carcass is claimed while it is butchered")
	carcass.harvest(second, held)
	TEST_ASSERT(isnull(running(second)), "a second butcher does not start on a claimed carcass")
	clear_scene()

// ---- Cutting meat: one cut per lap, then the carcass ----

/datum/unit_test/dq_timed_pin_w11I/harvest_cuts

/datum/unit_test/dq_timed_pin_w11I/harvest_cuts/run_pin()
	var/mob/living/carbon/human/cutter = person()
	var/mob/living/simple_mob/carcass = allocate(/mob/living/simple_mob/animal/passive/crab, run_loc_floor_bottom_left)
	carcass.meat_type = /obj/item/reagent_containers/food/snacks/meat // a plain meat so the count below is not the crab's
	carcass.meat_amount = 3
	carcass.butchery_drops_organs = FALSE
	carcass.set_stat(DEAD)
	var/obj/item/knife = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	cutter.put_in_active_hand(knife)
	var/lap = max(1 TICK, 0.5 SECONDS * (carcass.mob_size / 10))
	carcass.harvest(cutter, knife)
	TEST_ASSERT(!isnull(running(cutter)), "harvesting starts a timed series")
	TEST_ASSERT_EQUAL(carcass.meat_amount, 3, "no cut is made at the start")
	test_time(lap + 1 TICK)
	TEST_ASSERT_EQUAL(carcass.meat_amount, 2, "one cut per lap")
	test_time(lap)
	TEST_ASSERT_EQUAL(carcass.meat_amount, 1, "the second lap makes the second cut")
	// walking away ends the series with the cuts made so far
	cutter.forceMove(get_step(cutter, EAST))
	test_time(5 * lap)
	TEST_ASSERT_EQUAL(carcass.meat_amount, 1, "moving off stops the cutting")
	TEST_ASSERT(isnull(running(cutter)), "nothing is left running")
	var/cuts = 0
	for(var/obj/item/reagent_containers/food/snacks/meat/M in contents_of(get_turf(carcass)))
		cuts++
	TEST_ASSERT_EQUAL(cuts, 2, "two pieces of meat lie on the carcass's tile")

// ---- Egg laying: thirty seconds, then an egg is made ----

/datum/unit_test/dq_timed_pin_w11I/make_egg
	loss_cancels = FALSE
	drop_cancels = FALSE

/datum/unit_test/dq_timed_pin_w11I/make_egg/setup_scene()
	user = person()
	user.eggs = 0
	target = allocate(/obj/item/paper, run_loc_floor_bottom_left) // stands in for the actor (the op's target is the actor itself)
	held = null
	duration = 30 SECONDS

/datum/unit_test/dq_timed_pin_w11I/make_egg/start_click()
	test_chat_clear()
	perform_op(user, user, "mobegglaying", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("choice" = "Make a Egg"))

/datum/unit_test/dq_timed_pin_w11I/make_egg/is_done()
	return user.eggs == 1

// ---- Body writing: three seconds next to the canvas, then the limb carries the message ----

/datum/unit_test/dq_timed_pin_w11I/body_writing
	loss_cancels = TRUE
	drop_cancels = FALSE
	duration = 3 SECONDS
	finished = "You finish writing"

/datum/unit_test/dq_timed_pin_w11I/body_writing/setup_scene()
	user = person()
	target = other()
	held = null

/datum/unit_test/dq_timed_pin_w11I/body_writing/start_click()
	test_chat_clear()
	var/mob/living/carbon/human/canvas = target
	var/obj/item/organ/external/limb = canvas.get_organ(BP_TORSO)
	perform_op(user, canvas, "body_writing", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("limb" = limb, "message" = "hello"))

/datum/unit_test/dq_timed_pin_w11I/body_writing/is_done()
	var/mob/living/carbon/human/canvas = target
	return !QDELETED(canvas) && LAZYACCESS(canvas.body_writing, BP_TORSO) == "hello"
