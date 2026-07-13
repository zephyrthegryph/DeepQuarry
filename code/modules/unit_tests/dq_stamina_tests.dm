// Tests for the stamina / tiredness system. See code/modules/mob/living/stamina.dm and the
// drain hooks in melee_swing.dm / melee_block.dm / human_movement.dm. Reuses _swing_arena()
// from dq_melee_swing_tests.dm for a guaranteed open floor on z=1.


// adjust_stamina clamps at zero and stamps the use time (the regen idle-gate).
/datum/unit_test/dq_stamina_adjust_clamps_and_stamps

/datum/unit_test/dq_stamina_adjust_clamps_and_stamps/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.stamina = 100
	H.max_stamina = 100

	H.adjust_stamina(-30)
	TEST_ASSERT_EQUAL(H.stamina, 70, "a 30-point drain should leave 70 stamina")
	TEST_ASSERT_EQUAL(H.stamina_use_time, world.time, "a drain should stamp stamina_use_time")

	H.adjust_stamina(999) // clamp at max, no overflow
	TEST_ASSERT_EQUAL(H.stamina, 100, "stamina should clamp to max_stamina")


// Draining to zero collapses the mob: weakened, refilled to the collapse floor, and flagged.
/datum/unit_test/dq_stamina_zero_collapses

/datum/unit_test/dq_stamina_zero_collapses/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.stamina = 10
	H.max_stamina = 100

	H.adjust_stamina(-50) // drives stamina to zero
	TEST_ASSERT(H.stamina_collapsed, "hitting zero stamina should set the collapsed flag")
	TEST_ASSERT_EQUAL(H.stamina, STAMINA_COLLAPSE_FLOOR, "a collapse should refill stamina to the floor")
	TEST_ASSERT(H.weakened > 0, "a collapse should knock the mob down (weakened)")


// Recovering past the threshold clears the collapse lock so a future drain can collapse again.
/datum/unit_test/dq_stamina_recovery_clears_collapse

/datum/unit_test/dq_stamina_recovery_clears_collapse/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.max_stamina = 100
	H.stamina = 1
	H.adjust_stamina(-5) // collapse
	TEST_ASSERT(H.stamina_collapsed, "should be collapsed after draining to zero")

	H.adjust_stamina(STAMINA_RECOVER_THRESHOLD) // climb back past the threshold
	TEST_ASSERT(!H.stamina_collapsed, "recovering past the threshold should clear the collapse lock")


// Regen is idle-gated: nothing within the delay, then it ticks up afterward.
/datum/unit_test/dq_stamina_regen_idle_gated

/datum/unit_test/dq_stamina_regen_idle_gated/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.max_stamina = 100
	H.stamina = 50
	H.adjust_stamina(-10) // stamps use time; stamina now 40

	var/before = H.stamina
	H.handle_stamina_regen() // still inside the regen delay
	TEST_ASSERT_EQUAL(H.stamina, before, "regen should not start within the idle delay")

	H.stamina_use_time = world.time - (STAMINA_REGEN_DELAY + 1) // pretend the delay has elapsed
	H.handle_stamina_regen()
	TEST_ASSERT(H.stamina > before, "regen should recover stamina once the idle delay has passed")


// A committed melee swing spends stamina (covers the melee_swing.dm drain hook).
/datum/unit_test/dq_stamina_swing_drains

/datum/unit_test/dq_stamina_swing_drains/Run()
	var/turf/base = _swing_arena()
	TEST_ASSERT_NOTNULL(base, "no test turf available")
	var/turf/north = get_step(base, NORTH)
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, base)
	var/mob/living/simple_mob/animal/passive/mouse/victim = allocate(/mob/living/simple_mob/animal/passive/mouse, north)
	var/obj/item/weapon = allocate(/obj/item)
	weapon.force = 8
	weapon.w_class = ITEMSIZE_NORMAL
	attacker.put_in_active_hand(weapon)
	attacker.a_intent = I_HURT
	attacker.stamina = 100
	attacker.max_stamina = 100

	attacker.begin_melee_swing(victim, weapon)
	TEST_ASSERT(attacker.stamina < 100, "a melee swing should spend stamina (now [attacker.stamina])")


// Blocking is stamina-free: raising a guard, parrying, and whiffing all leave stamina untouched.
// (Stamina is an offensive/mobility resource; defense is gated by timing, not stamina.)
/datum/unit_test/dq_stamina_block_is_free

/datum/unit_test/dq_stamina_block_is_free/Run()
	var/turf/base = _swing_arena()
	var/turf/north = get_step(base, NORTH)
	var/mob/living/carbon/human/blocker = allocate(/mob/living/carbon/human, base)
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, north)
	var/obj/item/weapon = allocate(/obj/item)
	weapon.force = 10
	weapon.w_class = ITEMSIZE_NORMAL
	blocker.put_in_active_hand(weapon)
	blocker.face_atom(attacker)
	blocker.max_stamina = 100
	blocker.stamina = 100

	// Raising a guard costs no stamina.
	blocker.start_block(weapon)
	TEST_ASSERT_EQUAL(blocker.stamina, 100, "raising a guard should not touch stamina")

	// Parrying costs no stamina (and refunds none).
	blocker.check_shields(weapon.force, weapon, attacker, BP_TORSO, "the [weapon.name]")
	TEST_ASSERT_EQUAL(blocker.stamina, 100, "a parry should not touch stamina")

	// A whiffed guard costs no stamina either.
	blocker.block_used = FALSE
	blocker.blocking = TRUE
	blocker.end_block()
	TEST_ASSERT_EQUAL(blocker.stamina, 100, "a whiffed guard should not touch stamina")
