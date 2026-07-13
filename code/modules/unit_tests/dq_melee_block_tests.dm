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
	// A successful parry drops the guard immediately and leaves the blocker free to riposte —
	// no whiff penalty, no commitment lock (the parry is the clean exit).
	TEST_ASSERT(!blocker.blocking, "a parry should drop the guard immediately")
	TEST_ASSERT_EQUAL(blocker.melee_locked_until, 0, "a parry should leave the blocker free to riposte (no lockout)")
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
	// A soft block catches the hit at half damage and KEEPS the guard up — a held block isn't
	// spent by soaking one hit; it keeps blocking until released/timed out.
	TEST_ASSERT(blocker.blocking, "a soft block should keep the guard up, not drop it")
	TEST_ASSERT_EQUAL(blocker.block_soft_at, world.time, "a soft block should flag the hit for 50% reduction")
	TEST_ASSERT(blocker.stamina < 100, "a soft block should cost the blocker stamina")
	TEST_ASSERT(blocker.block_used, "catching a hit should mark the guard as used (no whiff penalty)")
	// A second hit while the guard is still up soft-blocks again (it isn't a one-shot guard).
	var/stamina_after_first = blocker.stamina
	TEST_ASSERT(!blocker.check_shields(weapon.force, weapon, attacker, BP_TORSO, "the [weapon.name]"), "a held guard should soft-block a second hit too")
	TEST_ASSERT(blocker.stamina < stamina_after_first, "a second soft block should cost more stamina")
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


// --- Stagger / poise: builds, then breaks the target open ------------------
/datum/unit_test/dq_stagger_builds_and_breaks

/datum/unit_test/dq_stagger_builds_and_breaks/Run()
	var/mob/living/simple_mob/quarry_stalker/m = allocate(/mob/living/simple_mob/quarry_stalker, _swing_arena())
	m.max_stagger = 50
	m.add_stagger(30)
	TEST_ASSERT(!m.is_stagger_broken(), "30/50 poise should not break the target yet")
	m.add_stagger(30) // crosses the cap
	TEST_ASSERT(m.is_stagger_broken(), "reaching max poise should break the target open")
	TEST_ASSERT_EQUAL(m.stagger, 0, "a stagger break empties the meter")

// --- Stagger ceiling scales to fauna durability ----------------------------
// A simple_mob's poise ceiling is derived from its HP at spawn (not the flat PvP default), so a
// squishy critter staggers open before it's killed and the execution payoff is actually reachable.
/datum/unit_test/dq_stagger_scales_to_health

/datum/unit_test/dq_stagger_scales_to_health/Run()
	var/mob/living/simple_mob/vore/scrubble/m = allocate(/mob/living/simple_mob/vore/scrubble, _swing_arena())
	var/expected = max(round(m.maxHealth * DQ_STAGGER_FAUNA_FRAC), 1)
	TEST_ASSERT_EQUAL(m.max_stagger, expected, "a [m.maxHealth]-HP scrubble's poise ceiling should scale to [expected], got [m.max_stagger]")
	TEST_ASSERT(m.max_stagger < DQ_STAGGER_MAX, "a low-HP critter should break for far less than the flat PvP ceiling")
	// A single parry's worth of poise should now be enough to break a 50-HP scrubble open.
	m.add_stagger(DQ_STAGGER_PARRY)
	TEST_ASSERT(m.is_stagger_broken(), "one parry's poise should break an HP-scaled fauna open (it didn't — executions stay unreachable)")

// --- Wounding: a leg hit applies the slow modifier -------------------------
/datum/unit_test/dq_wound_leg_slows

/datum/unit_test/dq_wound_leg_slows/Run()
	var/turf/base = _swing_arena()
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, base)
	var/mob/living/simple_mob/quarry_stalker/victim = allocate(/mob/living/simple_mob/quarry_stalker, get_step(base, NORTH))
	var/obj/item/weapon = allocate(/obj/item)
	weapon.force = 15
	attacker.apply_wound_effect(victim, weapon, BP_L_LEG)
	TEST_ASSERT(locate(/datum/modifier/dq_wound_leg) in victim.modifiers, "a solid leg hit should apply the wounded-leg slow")
	// A light tap (below the force floor) should NOT wound.
	var/mob/living/simple_mob/quarry_stalker/fresh = allocate(/mob/living/simple_mob/quarry_stalker, get_step(base, SOUTH))
	weapon.force = 2
	attacker.apply_wound_effect(fresh, weapon, BP_L_LEG)
	TEST_ASSERT(!(locate(/datum/modifier/dq_wound_leg) in fresh.modifiers), "a light tap should not wound a limb")

// --- Execution: a broken/downed/grabbed mob can be finished -----------------
/datum/unit_test/dq_execution_on_broken_mob

/datum/unit_test/dq_execution_on_broken_mob/Run()
	var/turf/base = _swing_arena()
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, base)
	var/mob/living/simple_mob/quarry_stalker/victim = allocate(/mob/living/simple_mob/quarry_stalker, get_step(base, NORTH))
	victim.maxHealth = 100
	victim.health = 100
	TEST_ASSERT(!attacker.can_execute(victim), "a healthy, standing mob should not be executable")
	victim.stagger_broken_until = world.time + 50 // force the broken-open window
	TEST_ASSERT(attacker.can_execute(victim), "a staggered-open adjacent mob should be executable")
	attacker.perform_execution(victim, null)
	TEST_ASSERT(victim.health < 100, "an execution should deal heavy damage")

	// Players are never executable, even broken wide open and adjacent — only fauna are.
	var/mob/living/carbon/human/prey = allocate(/mob/living/carbon/human, get_step(base, EAST))
	prey.stagger_broken_until = world.time + 50
	prey.Weaken(5)
	TEST_ASSERT(!attacker.can_execute(prey), "a player-type (human) target must never be executable, even when broken and downed")

// --- Execution: a bare-handed Harm attack on a broken mob triggers a finisher ----------------
// The whole weapon-swing pipeline is weapon-only, so an empty-handed Harm attack has to route the
// execution itself. dq_try_held_attack (the LMB-press entry) must consume it as an unarmed
// execution rather than fall through to a normal punch.
/datum/unit_test/dq_execution_unarmed_triggers

/datum/unit_test/dq_execution_unarmed_triggers/Run()
	var/turf/base = _swing_arena()
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human, base)
	var/mob/living/simple_mob/quarry_stalker/victim = allocate(/mob/living/simple_mob/quarry_stalker, get_step(base, NORTH))
	victim.maxHealth = 100
	victim.health = 100
	victim.stagger_broken_until = world.time + 50 // broken wide open
	attacker.a_intent = I_HURT
	TEST_ASSERT_NULL(attacker.get_active_hand(), "test attacker should be bare-handed for the unarmed path")
	var/consumed = attacker.dq_try_held_attack(victim)
	TEST_ASSERT(consumed, "a bare-handed Harm attack on a broken mob must be consumed as an execution, not fall through")
	TEST_ASSERT(victim.health < 100, "the unarmed execution should have landed its finishing damage")

// --- Universal grab: a simple_mob can grab via dq_grab ---------------------
/datum/unit_test/dq_universal_grab

/datum/unit_test/dq_universal_grab/Run()
	var/turf/base = _swing_arena()
	var/mob/living/simple_mob/quarry_stalker/grabber = allocate(/mob/living/simple_mob/quarry_stalker, base)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, get_step(base, NORTH))
	var/obj/item/grab/G = grabber.dq_grab(victim)
	TEST_ASSERT_NOTNULL(G, "a simple_mob should be able to establish a grab through the universal grab system")
	TEST_ASSERT(G in victim.grabbed_by, "the grab should be tracked on the victim's grabbed_by list")
	TEST_ASSERT_EQUAL(G.assailant, grabber, "the simple_mob should be the grab's assailant")


// --- Stagger immunity: a break can't be chained into a stunlock -----------
/datum/unit_test/dq_stagger_immunity_after_break

/datum/unit_test/dq_stagger_immunity_after_break/Run()
	var/mob/living/simple_mob/quarry_stalker/m = allocate(/mob/living/simple_mob/quarry_stalker, _swing_arena())
	m.max_stagger = 30
	m.add_stagger(30) // breaks
	TEST_ASSERT(m.is_stagger_broken(), "max poise should break the target")
	// End the broken window but stay inside the post-break immunity grace.
	m.stagger_broken_until = world.time
	TEST_ASSERT(!m.is_stagger_broken(), "broken window should be over for this check")
	m.add_stagger(30) // would re-break if immunity weren't enforced
	TEST_ASSERT(!m.is_stagger_broken(), "a second break shouldn't be possible during the immunity grace (stunlock guard)")
	TEST_ASSERT_EQUAL(m.stagger, 0, "poise shouldn't accumulate during the immunity grace")
