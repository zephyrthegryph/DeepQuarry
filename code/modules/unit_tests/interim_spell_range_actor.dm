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
