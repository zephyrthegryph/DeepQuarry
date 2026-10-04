/// Real slime teleport effects must not precede a refused held-source consumption.
/datum/unit_test/interim_slime_crystal_release
	parent_type = /datum/unit_test/dq_p2_reagents
	var/self_case = FALSE
	var/hit_case = FALSE

/datum/unit_test/interim_slime_crystal_release/self
	self_case = TRUE

/datum/unit_test/interim_slime_crystal_release/hit
	hit_case = TRUE

/datum/unit_test/interim_slime_crystal_release/run_gate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = rc_actor(T)
	var/mob/living/carbon/human/target = self_case ? actor : rc_actor(T)
	var/obj/item/slime_crystal/source = allocate(/obj/item/slime_crystal, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT(target.density && !target.anchored, "The actual unanchored dense target must exclude its starting tile from safe blink")
	TEST_ASSERT(!T.block_tele, "The actual starting floor must permit teleportation")
	var/available_destination = FALSE
	for(var/turf/simulated/D in range(target, 14))
		if(D == T || D.density || D.block_tele || ismineralturf(D))
			continue
		var/blocked = FALSE
		for(var/atom/movable/M in contents_of(D))
			if(M.density)
				blocked = TRUE
		if(!blocked)
			available_destination = TRUE
			break
	TEST_ASSERT(available_destination, "The real map must provide a distinct safe destination")
	if(!self_case && !hit_case)
		source.throw_impact(null)
		TEST_ASSERT(!QDELETED(source), "A missing actual impact target must preserve the source")
		var/obj/structure/table/anchored = allocate(/obj/structure/table, T)
		TEST_ASSERT(anchored.anchored, "The canonical table must be a genuinely anchored impact control")
		source.throw_impact(anchored)
		TEST_ASSERT(!QDELETED(source), "An actual anchored target must preserve the source")
		TEST_ASSERT_EQUAL(anchored.loc, T, "An actual anchored impact must not move the original table")
	TEST_ASSERT(actor.put_in_active_hand(source), "The actor must really hold the exact source crystal")
	add_trait(source, TRAIT_NODROP, "interim_slime_crystal_release")
	exercise_crystal(source, actor, target)
	TEST_ASSERT(!QDELETED(source), "Release refusal must preserve the exact original crystal")
	TEST_ASSERT_EQUAL(source.loc, actor, "Refusal must preserve actual crystal containment")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), source, "Refusal must preserve the exact active hand")
	TEST_ASSERT_EQUAL(target.loc, T, "Refusal must precede the actual target teleport")
	remove_trait(source, TRAIT_NODROP, "interim_slime_crystal_release")
	exercise_crystal(source, actor, target)
	own_turf_contents(T)
	own_turf_contents(get_turf(target))
	TEST_ASSERT(QDELETED(source), "Accepted actual teleport must consume the exact original crystal")
	TEST_ASSERT_NULL(actor.get_active_hand(), "Accepted cleanup must clear the actual crystal hand")
	TEST_ASSERT(target.loc != T, "Actual safe blink must move the original target to a distinct floor")
	TEST_ASSERT(istype(target.loc, /turf/simulated), "The original target must arrive on a real simulated destination")
	var/turf/destination = get_turf(target)
	TEST_ASSERT(!destination.density && !destination.block_tele, "The real destination must permit movement and teleportation")
	TEST_ASSERT(!QDELETED(target) && !QDELETED(actor), "Teleport must preserve both original mobs")
	TEST_ASSERT(!QDELETED(pen), "Teleport must preserve the original unrelated pen")
	TEST_ASSERT_EQUAL(pen.loc, T, "Teleport must preserve the unrelated pen floor")

/datum/unit_test/interim_slime_crystal_release/proc/exercise_crystal(obj/item/slime_crystal/source, mob/living/carbon/human/actor, mob/living/carbon/human/target)
	if(self_case)
		perform_op(actor, source, "self", source)
	else if(hit_case)
		source.apply_hit_effect(target, actor, BP_TORSO)
	else
		source.throw_impact(target)
