// Stamps and cooldowns of a base type: fields of the `cooldowns` lazy state (code/library/atom/states/cooldowns_state.dm). A field is an end time (a cooldown) or a
// start point on a clock (a stamp), 0 while never set.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_stamp_roundtrip

/datum/unit_test/dq_stamp_roundtrip/Run()
	set_global(nameof(GLOB.lazy_states_made), GLOB.lazy_states_made)
	set_global(nameof(GLOB.lazy_states_cleared), GLOB.lazy_states_cleared)
	var/turf/T = dq_containment_floor()
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT_NULL(cooldowns_peek(pen), "an instance that never stamped holds no state")
	TEST_ASSERT_EQUAL(TIME_NOW(CLOCK_WORLD, pen) - STATE_PEEK(pen, cooldowns, last_bumped), world.time, "a never-stamped name reads as a stamp at 0")
	STATE_SET(pen, cooldowns, last_bumped, TIME_NOW(CLOCK_WORLD, pen))
	TEST_ASSERT_EQUAL(STATE_PEEK(pen, cooldowns, last_bumped), world.time, "the stamp is now")
	TEST_ASSERT_EQUAL(TIME_NOW(CLOCK_WORLD, pen) - STATE_PEEK(pen, cooldowns, last_bumped), 0, "nothing has elapsed yet")
	STATE_SET(pen, cooldowns, last_bumped, world.time - 5 SECONDS)
	TEST_ASSERT_EQUAL(TIME_NOW(CLOCK_WORLD, pen) - STATE_PEEK(pen, cooldowns, last_bumped), 5 SECONDS, "elapsed counts from the recorded point")
	STATE_SET(pen, cooldowns, next_move, world.time + 5 SECONDS)
	STATE_SET(pen, cooldowns, last_bumped, 0)
	TEST_ASSERT_NOTNULL(cooldowns_peek(pen), "clearing one leaves the other")
	STATE_SET(pen, cooldowns, next_move, 0)
	TEST_ASSERT_NULL(cooldowns_peek(pen), "the state goes with its last non-default field")

/// A stamp and a cooldown share the state without touching each other.
/datum/unit_test/dq_stamp_with_cooldown

/datum/unit_test/dq_stamp_with_cooldown/Run()
	set_global(nameof(GLOB.lazy_states_made), GLOB.lazy_states_made)
	set_global(nameof(GLOB.lazy_states_cleared), GLOB.lazy_states_cleared)
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	STATE_SET(H, cooldowns, next_click, world.time + (10 SECONDS))
	STATE_SET(H, cooldowns, last_move_time, TIME_NOW(CLOCK_WORLD, H))
	TEST_ASSERT(!COOLDOWN_FINISHED(cooldowns_view(H), next_click), "the cooldown survives a stamp")
	STATE_SET(H, cooldowns, next_click, 0)
	TEST_ASSERT(STATE_PEEK(H, cooldowns, last_move_time) > 0, "the stamp survives a cooldown reset")

/// The stamps that left base-type vars: gone as vars, readable and rate-limiting as before.
/datum/unit_test/dq_stamp_converted_vars

/datum/unit_test/dq_stamp_converted_vars/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	for(var/name in list("last_bumped", "last_move_time", "lifecycle_lifetime_timer"))
		TEST_ASSERT(!(name in H.vars), "[name] is no longer a var of a mob")
		TEST_ASSERT(!(name in pen.vars), "[name] is no longer a var of an item")

#endif
