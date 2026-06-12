// Tests for the melee block / parry / feint system and intent stances.
// See code/modules/mob/living/melee_block.dm, the parry hook in
// code/modules/mob/living/carbon/human/human_defense.dm (check_shields), and the
// feint hook in code/modules/mob/living/melee_swing.dm. Reuses _swing_arena() from
// dq_melee_swing_tests.dm for a guaranteed open floor on z=1.


// The intent table returns distinct, well-shaped rows: aggressive intents hit harder and
// wind up slower than support intents, and Grab is the unmodified baseline.
/datum/unit_test/dq_intent_combat_mods_table

/datum/unit_test/dq_intent_combat_mods_table/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)

	H.a_intent = I_HURT
	var/list/harm = H.get_intent_combat_mods()
	H.a_intent = I_HELP
	var/list/help = H.get_intent_combat_mods()
	H.a_intent = I_GRAB
	var/list/grab = H.get_intent_combat_mods()

	TEST_ASSERT(harm[INTENT_MOD_DAMAGE] > help[INTENT_MOD_DAMAGE], "harm should hit harder than help")
	TEST_ASSERT(harm[INTENT_MOD_WINDUP] > help[INTENT_MOD_WINDUP], "harm should wind up slower than help")
	TEST_ASSERT_EQUAL(grab[INTENT_MOD_DAMAGE], 1.0, "grab should be the unmodified damage baseline")
	TEST_ASSERT_EQUAL(grab[INTENT_MOD_MOVE], 0, "grab should impose no move slowdown")


// A right-click during a windup sets feint_requested, the do_after extra-check cancels the
// swing, and the telegraphed victim takes no damage.
/datum/unit_test/dq_melee_feint_cancels_swing

/datum/unit_test/dq_melee_feint_cancels_swing/Run()
	var/turf/base = _swing_arena()
	TEST_ASSERT_NOTNULL(base, "no test turf available")
	var/turf/north = get_step(base, NORTH)
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, base)
	var/mob/living/simple_mob/animal/passive/mouse/victim = allocate(/mob/living/simple_mob/animal/passive/mouse, north)
	var/obj/item/weapon = allocate(/obj/item)
	weapon.force = 8
	weapon.w_class = ITEMSIZE_HUGE // long windup for timing headroom
	attacker.put_in_active_hand(weapon)
	attacker.a_intent = I_HURT

	var/before = victim.health
	INVOKE_ASYNC(attacker, TYPE_PROC_REF(/mob/living, begin_melee_swing), victim, weapon)
	sleep(2)                               // windup in progress
	attacker.melee_rightclick(victim)      // feint mid-windup
	TEST_ASSERT(attacker.feint_requested, "a right-click during the windup should request a feint")
	sleep(weapon.get_melee_windup() + 4)   // wait past where the swing would have resolved
	TEST_ASSERT_EQUAL(victim.health, before, "a feinted swing should deal no damage")
	TEST_ASSERT(!attacker.is_swinging, "is_swinging should clear after a feint")


// A raised block parries an incoming melee attack: check_shields negates it and the attacker
// is staggered (melee_locked_until pushed into the future).
/datum/unit_test/dq_melee_block_parries_and_staggers

/datum/unit_test/dq_melee_block_parries_and_staggers/Run()
	var/turf/base = _swing_arena()
	var/turf/north = get_step(base, NORTH)
	var/mob/living/carbon/human/blocker = allocate(/mob/living/carbon/human, base)
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, north)
	var/obj/item/weapon = allocate(/obj/item)
	weapon.force = 10
	weapon.w_class = ITEMSIZE_NORMAL
	blocker.put_in_active_hand(weapon)
	blocker.face_atom(attacker) // guard toward the threat

	blocker.start_block(weapon)
	TEST_ASSERT(blocker.blocking, "the blocker should be blocking after start_block")

	var/parried = blocker.check_shields(weapon.force, weapon, attacker, BP_TORSO, "the [weapon.name]")
	TEST_ASSERT(parried, "a raised guard should intercept an incoming adjacent melee attack")
	TEST_ASSERT(blocker.block_used, "a successful intercept should mark block_used")
	TEST_ASSERT(attacker.melee_locked_until > world.time, "a parry should stagger the attacker's attacks")


// An attack caught after the tight parry phase is a SOFT block: it is not fully negated (the hit
// proceeds at half), it costs the blocker stamina, flags the hit for 50% reduction, and does NOT
// stagger the attacker.
/datum/unit_test/dq_melee_soft_block

/datum/unit_test/dq_melee_soft_block/Run()
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

	blocker.start_block(weapon)
	sleep(DQ_PARRY_WINDOW + 1) // past the parry phase, still within the block tail
	TEST_ASSERT(blocker.blocking, "the guard should still be up in its block tail")
	var/fully_negated = blocker.check_shields(weapon.force, weapon, attacker, BP_TORSO, "the [weapon.name]")
	TEST_ASSERT(!fully_negated, "a soft block should let the halved hit through, not fully negate it")
	TEST_ASSERT(blocker.block_used, "a soft block should mark block_used (no whiff penalty)")
	TEST_ASSERT_EQUAL(blocker.block_soft_at, world.time, "a soft block should flag the hit for 50% reduction")
	TEST_ASSERT(blocker.stamina < 100, "a soft block should cost the blocker stamina")
	TEST_ASSERT_EQUAL(attacker.melee_locked_until, 0, "a soft block should NOT stagger the attacker")


// A guard that catches no attack applies the whiff penalty when its window expires: the blocker's
// own attacks are locked out.
/datum/unit_test/dq_melee_block_whiff_locks_out

/datum/unit_test/dq_melee_block_whiff_locks_out/Run()
	var/mob/living/carbon/human/blocker = allocate(/mob/living/carbon/human)
	var/obj/item/weapon = allocate(/obj/item)
	weapon.force = 10
	blocker.put_in_active_hand(weapon)

	blocker.start_block(weapon)
	sleep(DQ_BLOCK_WINDOW + 1) // let the guard expire with no incoming attack
	TEST_ASSERT(!blocker.blocking, "the guard should have ended after its window")
	TEST_ASSERT(blocker.melee_locked_until > world.time, "a whiffed guard should lock out the blocker's attacks")


// A recent step locks out a melee swing: begin_melee_swing bails while within the move window.
/datum/unit_test/dq_melee_move_locks_attacks

/datum/unit_test/dq_melee_move_locks_attacks/Run()
	var/turf/base = _swing_arena()
	var/turf/north = get_step(base, NORTH)
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, base)
	var/mob/living/simple_mob/animal/passive/mouse/victim = allocate(/mob/living/simple_mob/animal/passive/mouse, north)
	var/obj/item/weapon = allocate(/obj/item)
	weapon.force = 8
	weapon.w_class = ITEMSIZE_SMALL
	attacker.put_in_active_hand(weapon)
	attacker.a_intent = I_HURT

	attacker.l_move_time = world.time // simulate having just stepped
	var/before = victim.health
	var/committed = attacker.begin_melee_swing(victim, weapon)
	TEST_ASSERT(!committed, "a swing should be locked out right after moving")
	TEST_ASSERT_EQUAL(victim.health, before, "a move-locked swing should deal no damage")


// A Disarm-intent shove knocks the target back a tile into open space and locks it out.
/datum/unit_test/dq_melee_shove_knockback

/datum/unit_test/dq_melee_shove_knockback/Run()
	var/turf/base = _swing_arena()
	var/turf/north = get_step(base, NORTH)
	var/turf/far = get_step(north, NORTH)
	TEST_ASSERT_NOTNULL(far, "no open tile behind the victim")
	var/mob/living/carbon/human/shover = allocate(/mob/living/carbon/human, base)
	var/mob/living/simple_mob/animal/passive/mouse/victim = allocate(/mob/living/simple_mob/animal/passive/mouse, north)
	QDEL_NULL(victim.ai_brain)
	var/obj/item/weapon = allocate(/obj/item)
	weapon.force = 8
	weapon.w_class = ITEMSIZE_NORMAL
	shover.put_in_active_hand(weapon)
	shover.a_intent = I_DISARM

	shover.begin_melee_shove(victim, weapon)
	TEST_ASSERT_EQUAL(get_turf(victim), far, "a shoved victim should be knocked back a tile")
	TEST_ASSERT(victim.melee_locked_until > world.time, "a shoved victim should be locked out")


// A shove into a blocked tile (a dense wall) knocks the target down without moving it.
/datum/unit_test/dq_melee_shove_knockdown

/datum/unit_test/dq_melee_shove_knockdown/Run()
	var/turf/base = _swing_arena()
	var/turf/north = get_step(base, NORTH)
	get_step(north, NORTH).ChangeTurf(/turf/simulated/wall) // dense wall behind the victim
	var/mob/living/carbon/human/shover = allocate(/mob/living/carbon/human, base)
	var/mob/living/simple_mob/animal/passive/mouse/victim = allocate(/mob/living/simple_mob/animal/passive/mouse, north)
	QDEL_NULL(victim.ai_brain)
	var/obj/item/weapon = allocate(/obj/item)
	weapon.force = 8
	weapon.w_class = ITEMSIZE_NORMAL
	shover.put_in_active_hand(weapon)
	shover.a_intent = I_DISARM

	shover.begin_melee_shove(victim, weapon)
	TEST_ASSERT_EQUAL(get_turf(victim), north, "a blocked shove should not move the victim")
	TEST_ASSERT(victim.weakened > 0, "a victim shoved into a wall should be knocked down")


// After a parry, the parrier's next attack is unblockable: it bypasses the target's raised guard.
/datum/unit_test/dq_melee_riposte_unblockable

/datum/unit_test/dq_melee_riposte_unblockable/Run()
	var/turf/base = _swing_arena()
	var/turf/north = get_step(base, NORTH)
	var/mob/living/carbon/human/parrier = allocate(/mob/living/carbon/human, base)
	var/mob/living/carbon/human/foe = allocate(/mob/living/carbon/human, north)
	var/obj/item/weapon = allocate(/obj/item)
	weapon.force = 10
	weapon.w_class = ITEMSIZE_NORMAL
	parrier.put_in_active_hand(weapon)
	parrier.riposte_until = world.time + DQ_RIPOSTE_WINDOW // simulate having just landed a parry

	// The foe raises a guard facing the parrier.
	var/obj/item/foe_weapon = allocate(/obj/item)
	foe_weapon.force = 10
	foe.put_in_active_hand(foe_weapon)
	foe.face_atom(parrier)
	foe.start_block(foe_weapon)

	var/blocked = foe.check_shields(weapon.force, weapon, parrier, BP_TORSO, "the [weapon.name]")
	TEST_ASSERT(!blocked, "a riposte attack should bypass the target's guard")
	TEST_ASSERT_EQUAL(parrier.riposte_until, 0, "the riposte should be consumed by the bypass")
