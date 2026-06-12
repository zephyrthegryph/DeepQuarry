// Tests for the phased player melee system (windup -> swing -> recovery).
// See code/modules/mob/living/melee_swing.dm and the divert hook in
// code/_onclick/item_attack.dm.

// The DQ test map doesn't place the unit_test landmarks, so run_loc_floor_*
// are null. Carve a small open floor arena on z=1 and return its centre — that
// guarantees passable, adjacent neighbours in every direction for the tests.
/datum/unit_test/proc/_swing_arena()
	var/turf/anchor
	for(var/turf/simulated/T in block(locate(1, 1, 1), locate(world.maxx, world.maxy, 1)))
		if(T.x >= 3 && T.y >= 3 && T.x <= world.maxx - 3 && T.y <= world.maxy - 3)
			anchor = T
			break
	if(!anchor)
		return null
	for(var/turf/T in block(locate(anchor.x - 2, anchor.y - 2, 1), locate(anchor.x + 2, anchor.y + 2, 1)))
		T.ChangeTurf(/turf/simulated/floor)
	return locate(anchor.x, anchor.y, 1)


// Windup/recovery scale up with size; sweep turns on for big weapons; overrides win.
/datum/unit_test/dq_melee_swing_getters_scale

/datum/unit_test/dq_melee_swing_getters_scale/Run()
	var/obj/item/small = allocate(/obj/item)
	small.w_class = ITEMSIZE_SMALL
	var/obj/item/huge = allocate(/obj/item)
	huge.w_class = ITEMSIZE_HUGE

	TEST_ASSERT(!small.melee_is_sweep(), "a small weapon should not sweep")
	TEST_ASSERT(huge.melee_is_sweep(), "a huge weapon should sweep")
	TEST_ASSERT(huge.get_melee_windup() > small.get_melee_windup(), "bigger weapons should wind up slower")
	TEST_ASSERT(huge.get_melee_recovery() > small.get_melee_recovery(), "bigger weapons should recover slower")

	small.melee_windup = 99
	TEST_ASSERT_EQUAL(small.get_melee_windup(), 99, "an explicit melee_windup should override the size default")
	small.melee_sweep = TRUE
	TEST_ASSERT(small.melee_is_sweep(), "an explicit melee_sweep should force sweeping")


// Single-tile weapons target one tile; sweeping weapons widen to a 3-tile frontal arc.
/datum/unit_test/dq_melee_swing_tiles_arc

/datum/unit_test/dq_melee_swing_tiles_arc/Run()
	var/turf/base = _swing_arena()
	TEST_ASSERT_NOTNULL(base, "no test turf available")
	var/turf/north = get_step(base, NORTH)
	TEST_ASSERT_NOTNULL(north, "no tile north of the test turf")

	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, base)
	var/obj/item/single = allocate(/obj/item)
	single.w_class = ITEMSIZE_SMALL
	var/obj/item/sweeper = allocate(/obj/item)
	sweeper.w_class = ITEMSIZE_HUGE

	var/list/turf/single_tiles = attacker.get_swing_tiles(north, single)
	TEST_ASSERT_EQUAL(length(single_tiles), 1, "a single-tile weapon should target exactly one tile")
	TEST_ASSERT(north in single_tiles, "the single tile should be the tile toward the target")

	var/list/turf/sweep_tiles = attacker.get_swing_tiles(north, sweeper)
	TEST_ASSERT_EQUAL(length(sweep_tiles), 3, "a sweeping weapon should target a 3-tile arc")
	TEST_ASSERT(north in sweep_tiles, "the sweep should include the front tile")


// A target standing in the swing tile takes damage — routed through the attackby hook
// to also cover the divert in item_attack.dm.
/datum/unit_test/dq_melee_swing_hits_occupied_tile

/datum/unit_test/dq_melee_swing_hits_occupied_tile/Run()
	var/turf/base = _swing_arena()
	var/turf/north = get_step(base, NORTH)
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, base)
	var/mob/living/simple_mob/animal/passive/mouse/victim = allocate(/mob/living/simple_mob/animal/passive/mouse, north)
	QDEL_NULL(victim.ai_brain) // no AI: keep it in the swing tile deterministically (anchored alone doesn't stop the brain)
	var/obj/item/weapon = allocate(/obj/item)
	weapon.force = 8
	weapon.w_class = ITEMSIZE_SMALL
	attacker.put_in_active_hand(weapon)
	attacker.a_intent = I_HURT
	TEST_ASSERT_EQUAL(attacker.get_active_hand(), weapon, "weapon should be in the attacker's active hand")
	TEST_ASSERT(attacker.Adjacent(victim), "attacker should be adjacent to the victim")

	var/before = victim.health
	victim.attackby(weapon, attacker) // harm-intent item attack -> divert -> windup -> swing
	TEST_ASSERT(victim.health < before, "a victim in the swing tile should take damage (before [before], after [victim.health])")


// Committed-but-dodgeable: a target that steps out of the telegraphed tiles during the
// windup takes no damage (the swing hits tiles, not a locked-on target).
/datum/unit_test/dq_melee_swing_dodge_by_moving

/datum/unit_test/dq_melee_swing_dodge_by_moving/Run()
	var/turf/base = _swing_arena()
	var/turf/north = get_step(base, NORTH)
	var/turf/far = get_step(north, NORTH)
	TEST_ASSERT_NOTNULL(far, "no tile two north of the test turf")

	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, base)
	var/mob/living/simple_mob/animal/passive/mouse/victim = allocate(/mob/living/simple_mob/animal/passive/mouse, north)
	QDEL_NULL(victim.ai_brain) // only the deliberate forceMove below should move it (no AI wandering)
	var/obj/item/weapon = allocate(/obj/item)
	weapon.force = 8
	weapon.w_class = ITEMSIZE_HUGE // long windup for timing headroom
	attacker.put_in_active_hand(weapon)
	attacker.a_intent = I_HURT

	var/before = victim.health
	INVOKE_ASYNC(attacker, TYPE_PROC_REF(/mob/living, begin_melee_swing), victim, weapon)
	sleep(2)                                  // windup is in progress (9 ds total)
	victim.forceMove(far)                     // dodge out of the swing tiles
	sleep(weapon.get_melee_windup() + 4)      // wait past the swing resolution
	TEST_ASSERT_EQUAL(victim.health, before, "a victim that left the tiles during windup should take no damage")


// After a swing, a recovery cooldown is set and the swinging flag is cleared.
/datum/unit_test/dq_melee_swing_sets_recovery_cooldown

/datum/unit_test/dq_melee_swing_sets_recovery_cooldown/Run()
	var/turf/base = _swing_arena()
	var/turf/north = get_step(base, NORTH)
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, base)
	var/mob/living/simple_mob/animal/passive/mouse/victim = allocate(/mob/living/simple_mob/animal/passive/mouse, north)
	var/obj/item/weapon = allocate(/obj/item)
	weapon.force = 5
	weapon.w_class = ITEMSIZE_NORMAL
	attacker.put_in_active_hand(weapon)
	attacker.a_intent = I_HURT

	attacker.begin_melee_swing(victim, weapon)
	TEST_ASSERT(attacker.next_click > world.time, "a recovery cooldown should be active immediately after the swing")
	TEST_ASSERT(!attacker.is_swinging, "is_swinging should be cleared after the swing resolves")


// A landed, unparried hit opens the combo window; a whiff breaks it.
/datum/unit_test/dq_melee_combo_window

/datum/unit_test/dq_melee_combo_window/Run()
	var/turf/base = _swing_arena()
	var/turf/north = get_step(base, NORTH)
	var/turf/east = get_step(base, EAST)
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, base)
	var/mob/living/simple_mob/animal/passive/mouse/victim = allocate(/mob/living/simple_mob/animal/passive/mouse, north)
	QDEL_NULL(victim.ai_brain) // no AI: keep it in the swing tile deterministically (anchored alone doesn't stop the brain)
	var/obj/item/weapon = allocate(/obj/item)
	weapon.force = 8
	weapon.w_class = ITEMSIZE_NORMAL
	attacker.put_in_active_hand(weapon)
	attacker.a_intent = I_HURT

	// Landing on the mouse opens the combo window and still sets a (reduced) recovery cooldown.
	attacker.begin_melee_swing(victim, weapon)
	TEST_ASSERT(attacker.combo_until > world.time, "a landed hit should open the combo window")
	TEST_ASSERT(attacker.next_click > world.time, "a landed hit should still set a recovery cooldown (no spam)")

	// A swing that connects with nothing (empty tile) breaks the combo.
	attacker.combo_until = world.time + COMBO_WINDOW
	attacker.begin_melee_swing(east, weapon) // nobody on the east tile
	TEST_ASSERT(attacker.combo_until <= world.time, "a whiffed swing should break the combo window")
