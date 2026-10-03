/// Emagging the actual emitter unlocks its controls permanently through the real declared interaction requirements.
/datum/unit_test/interim_emitter_emag_lock/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/emitter/emitter = allocate(/obj/machinery/power/emitter, T)
	var/obj/item/card/id/id = allocate(/obj/item/card/id, T)
	id.access = list(ACCESS_ENGINE_EQUIP)
	TEST_ASSERT(user.put_in_active_hand(id), "the actual actor holds an engineering-equipment ID")
	TEST_ASSERT(emitter.allowed(user), "the held ID grants actual emitter access")
	var/datum/interaction/machine_item/emitter_toggle_lock/toggle
	for(var/datum/interaction/candidate as anything in interaction_candidates(emitter))
		if(istype(candidate, /datum/interaction/machine_item/emitter_toggle_lock))
			toggle = candidate
			break
	TEST_ASSERT_NOTNULL(toggle, "the actual emitter offers its declared lock interaction")
	TEST_ASSERT(!emitter.emagged && !emitter.locked, "the actual emitter starts with intact unlocked controls")
	TEST_ASSERT_NULL(toggle.why_not(user, emitter, id), "the intact lock permits the authorized ID interaction")
	TEST_ASSERT(toggle.perform(user, emitter, id), "the actual declared ID interaction locks the controls")
	TEST_ASSERT(emitter.locked, "successful locking changes the actual emitter state")
	TEST_ASSERT_EQUAL(emag_target(emitter, 1, user), 1, "the actual declared emag consumes one use")
	TEST_ASSERT(emitter.emagged, "the actual emitter records its damaged authentication lock")
	TEST_ASSERT(!emitter.locked, "emagging immediately unlocks the actual controls")
	TEST_ASSERT_EQUAL(toggle.why_not(user, emitter, id), "the lock seems to be broken", "even an authorized ID cannot operate the damaged lock")
	TEST_ASSERT(!toggle.perform(user, emitter, id), "the actual interaction boundary refuses relocking after emagging")
	TEST_ASSERT(!emitter.locked, "refused relocking preserves the unlocked controls")
	TEST_ASSERT_EQUAL(emag_target(emitter, 1, user), EMAG_DECLINED, "a repeated emag consumes no additional use")
	TEST_ASSERT(emitter.emagged && !emitter.locked, "repeat refusal preserves the bypassed lock state")
	TEST_ASSERT(!emitter.active, "lock and emag operations never activate the actual emitter")
