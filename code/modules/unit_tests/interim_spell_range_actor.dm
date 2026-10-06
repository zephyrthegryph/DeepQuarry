/// Exercise the real casting boundary and range wrapper with an explicit caster.
/datum/spell/interim_range_actor_probe
	range = 1
	selection_type = "range"
	var/atom/near_target
	var/atom/far_target
	var/before_actor_ref
	var/cast_actor_ref
	var/cast_target_count

/datum/spell/interim_range_actor_probe/choose_targets(mob/user)
	return list(near_target, far_target)

/datum/spell/interim_range_actor_probe/before_cast(list/targets, mob/user)
	before_actor_ref = user ? REF(user) : null
	return ..(targets, user)

/datum/spell/interim_range_actor_probe/cast(list/targets, mob/user)
	cast_actor_ref = user ? REF(user) : null
	cast_target_count = length(targets)

/datum/unit_test/interim_spell_range_actor/Run()
	var/turf/near = run_loc_floor_bottom_left
	var/turf/far = run_loc_floor_top_right
	TEST_ASSERT(get_dist(near, far) > 1, "the fixture has targets outside the spell's range")
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, near)
	var/obj/item/pen/near_target = allocate(/obj/item/pen, near)
	var/obj/item/pen/far_target = allocate(/obj/item/pen, far)
	var/datum/spell/interim_range_actor_probe/spell = allocate(/datum/spell/interim_range_actor_probe)
	rel_set(spell, nameof(spell.near_target), near_target)
	rel_set(spell, nameof(spell.far_target), far_target)
	var/list/targets = list(near_target, far_target)
	var/list/valid = spell.before_cast(targets, user)
	TEST_ASSERT_EQUAL(length(valid), 1, "range filtering retains exactly one nearby target")
	TEST_ASSERT(near_target in valid, "range filtering uses the explicit caster's location")
	TEST_ASSERT(!(far_target in valid), "range filtering excludes the distant target")
	user.forceMove(far)
	valid = spell.before_cast(targets, user)
	TEST_ASSERT_EQUAL(length(valid), 1, "moving the caster still retains exactly one target")
	TEST_ASSERT(far_target in valid, "moving the caster changes the valid target")
	TEST_ASSERT(!(near_target in valid), "the formerly nearby target is now outside range")
	spell.before_actor_ref = null
	spell.perform_cast(user, TRUE)
	TEST_ASSERT_EQUAL(spell.before_actor_ref, REF(user), "perform_cast passes the caster to the real range wrapper")
	TEST_ASSERT_EQUAL(spell.cast_actor_ref, REF(user), "the same caster reaches the spell effect")
	TEST_ASSERT_EQUAL(spell.cast_target_count, 2, "actor plumbing preserves the existing unfiltered effect target list")

/// Proximity selection excludes the supplied caster until INCLUDEUSER is enabled.
/datum/unit_test/interim_spell_proximity_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/caster = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/origin = allocate(/obj/item/pen, T)
	var/datum/spell/targeted/projectile/spell = allocate(/datum/spell/targeted/projectile)
	spell.cast_prox_range = 0
	spell.spell_flags = NONE
	var/list/targets = spell.choose_prox_targets(caster, origin)
	TEST_ASSERT(!(caster in targets), "the explicit caster is excluded from proximity targets")
	TEST_ASSERT(other in targets, "another living target in range remains eligible")
	spell.spell_flags |= INCLUDEUSER
	targets = spell.choose_prox_targets(caster, origin)
	TEST_ASSERT(caster in targets, "INCLUDEUSER permits the explicit caster")
	TEST_ASSERT(other in targets, "INCLUDEUSER preserves the other target")

/// Charging a holder-var spell adjusts only the explicitly supplied actor's real status.
/datum/unit_test/interim_spell_charge_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	var/datum/spell/spell = allocate(/datum/spell)
	spell.charge_type = Sp_HOLDVAR
	spell.holder_var_type = "stunned"
	spell.holder_var_amount = 2 SECONDS
	TEST_ASSERT(!target.has_status(STAT_STUNNED), "the supplied actor starts unstunned")
	TEST_ASSERT(!bystander.has_status(STAT_STUNNED), "the bystander starts unstunned")
	TEST_ASSERT(spell.take_charge(target, FALSE), "the real holder-var charge path succeeds")
	TEST_ASSERT(target.has_status(STAT_STUNNED), "charging applies real stun to the supplied actor")
	TEST_ASSERT(!bystander.has_status(STAT_STUNNED), "charging leaves the bystander unaffected")
	spell.adjust_var(target, "stunned", -2 SECONDS)
	TEST_ASSERT(!target.has_status(STAT_STUNNED), "signed adjustment removes the supplied actor's stun")

/// Record validation's actor while retaining all real spell checks and rune construction.
/datum/spell/rune_write/interim_actor_probe
	spell_flags = NONE
	var/check_actor_ref
	var/check_count = 0

/datum/spell/rune_write/interim_actor_probe/choose_targets(mob/user)
	picked_rune = "Stun"
	return list(user)

/datum/spell/rune_write/interim_actor_probe/cast_check(skipcharge = 0, mob/user)
	check_actor_ref = user ? REF(user) : null
	check_count++
	return ..(skipcharge, user)

/datum/unit_test/interim_rune_validation_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/datum/spell/rune_write/interim_actor_probe/spell = allocate(/datum/spell/rune_write/interim_actor_probe)
	spell.charge_counter = 42
	spell.perform_cast(user, TRUE)
	own_turf_contents(T)
	TEST_ASSERT_EQUAL(spell.check_count, 1, "the selected rune runs its real secondary casting validation")
	TEST_ASSERT_EQUAL(spell.check_actor_ref, REF(user), "secondary validation receives the explicitly supplied caster")
	var/obj/effect/rune/rune = locate_within(T, /obj/effect/rune)
	TEST_ASSERT(istype(rune), "the real spell creates a rune at the caster's location")
	TEST_ASSERT_EQUAL(rune.word1, GLOB.cultwords["join"], "the rune receives the first Stun word")
	TEST_ASSERT_EQUAL(rune.word2, GLOB.cultwords["hide"], "the rune receives the second Stun word")
	TEST_ASSERT_EQUAL(rune.word3, GLOB.cultwords["technology"], "the rune receives the third Stun word")
	TEST_ASSERT_EQUAL(spell.charge_counter, 42, "skip-charge validation preserves the existing spell charge")
