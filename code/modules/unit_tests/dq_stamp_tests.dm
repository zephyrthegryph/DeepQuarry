// STAMP: "how long since" on a base type, stored in the instance's lazy table (code/__defines/engine/sparse_slots.dm).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_stamp_roundtrip

/datum/unit_test/dq_stamp_roundtrip/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT(isnull(pen.cooldown_table), "an instance that never stamped holds no table")
	TEST_ASSERT(!STAMPED(pen, last_bumped), "a never-stamped name is not stamped")
	TEST_ASSERT_EQUAL(STAMP_ELAPSED(pen, last_bumped, CLOCK_WORLD), world.time, "a never-stamped name reads as a stamp at 0")
	STAMP(pen, last_bumped, CLOCK_WORLD)
	TEST_ASSERT(STAMPED(pen, last_bumped), "stamping records the name")
	TEST_ASSERT_EQUAL(STAMP_POINT(pen, last_bumped), world.time, "the stamp is now")
	TEST_ASSERT_EQUAL(STAMP_ELAPSED(pen, last_bumped, CLOCK_WORLD), 0, "nothing has elapsed yet")
	STAMP_AT(pen, last_bumped, world.time - 5 SECONDS)
	TEST_ASSERT_EQUAL(STAMP_ELAPSED(pen, last_bumped, CLOCK_WORLD), 5 SECONDS, "elapsed counts from the recorded point")
	STAMP_AT(pen, other_stamp, 0)
	TEST_ASSERT(STAMPED(pen, other_stamp), "a stamp at point 0 is still a stamp")
	STAMP_CLEAR(pen, last_bumped)
	TEST_ASSERT(!STAMPED(pen, last_bumped) && STAMPED(pen, other_stamp), "clearing one leaves the other")
	STAMP_CLEAR(pen, other_stamp)
	TEST_ASSERT(isnull(pen.cooldown_table), "the table goes with its last entry")

/// A stamp and a cooldown share the table without touching each other.
/datum/unit_test/dq_stamp_with_cooldown

/datum/unit_test/dq_stamp_with_cooldown/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	cooldown_start(H, next_click, 10 SECONDS)
	STAMP(H, last_move_time, CLOCK_WORLD)
	TEST_ASSERT(!cooldown_ready(H, next_click), "the cooldown survives a stamp")
	cooldown_reset(H, next_click)
	TEST_ASSERT(STAMPED(H, last_move_time), "the stamp survives a cooldown reset")

/// The stamps that left base-type vars: gone as vars, readable and rate-limiting as before.
/datum/unit_test/dq_stamp_converted_vars

/datum/unit_test/dq_stamp_converted_vars/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	for(var/name in list("last_bumped", "latent_touched_at", "last_move_time", "lifecycle_lifetime_timer"))
		TEST_ASSERT(!(name in H.vars), "[name] is no longer a var of a mob")
		TEST_ASSERT(!(name in pen.vars), "[name] is no longer a var of an item")
	dq_latent_touch(pen)
	TEST_ASSERT(STAMP_ELAPSED(pen, latent_touched_at, CLOCK_WORLD) < 1 SECOND, "a latency touch stamps the atom")

#endif
