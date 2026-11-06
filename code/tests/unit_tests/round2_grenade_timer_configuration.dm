/// Real granted BYOND verb invocation through the existing actor-context API; not inbox/client coverage.
/datum/unit_test/round2_grenade_timer_configuration
	var/timer_case = "accepted"

/datum/unit_test/round2_grenade_timer_configuration/Run()
	test_driver_begin()
	exercise_timer()
	test_driver_end()

/datum/unit_test/round2_grenade_timer_configuration/proc/exercise_timer()
	var/turf/surface = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	var/obj/item/grenade/chem_grenade/metalfoam/grenade = allocate(/obj/item/grenade/chem_grenade/metalfoam, surface)
	TEST_ASSERT(user.put_in_active_hand(grenade), "Actual human inventory API holds the real constructed grenade")
	TEST_ASSERT_EQUAL(grenade.loc, user, "Real grenade custody matches the public verb's carried source")
	var/obj/item/assembly_holder/timer_igniter/holder = grenade.detonator
	TEST_ASSERT(istype(holder) && holder.loc == grenade, "Actual grenade constructor adopts its genuine timer-igniter assembly")
	var/obj/item/assembly/timer/timer = holder.a_left
	TEST_ASSERT(istype(timer) && timer.loc == holder && timer.holder() == holder, "Actual constructor installs the real timer on its original left side and holder relation")
	TEST_ASSERT(timer.secured && !timer.timing, "Real freshly constructed timer is secured and idle")
	TEST_ASSERT(/obj/item/assembly_holder/timer_igniter/verb/configure in grenade.verbs, "Actual constructor's grant exposes the existing Set Timer verb on the grenade")
	var/original_time = timer.time
	var/original_name = grenade.name
	var/datum/callback/invocation = allocate(/datum/callback, grenade, /obj/item/assembly_holder/timer_igniter/verb/configure)
	world.push_usr(user, invocation)
	var/datum/prompt/number/grenade_timer_configuration/question = SSrequests.open_for(user)
	TEST_ASSERT(istype(question) && question.owner == grenade && question.answerer == user, "Actual public granted verb with its genuine actor context opens the native request on the grenade")
	TEST_ASSERT_EQUAL(timer.time, original_time, "Opening the actual question leaves the real timer unchanged")
	TEST_ASSERT_EQUAL(grenade.name, original_name, "Opening the actual question leaves the grenade label unchanged")
	if(timer_case == "cancelled")
		test_answer(user, null, REQ_CANCELLED)
	else if(timer_case == "late_ticking")
		timer.activate()
		TEST_ASSERT(timer.timing, "Actual timer activation starts its genuine ticking state after the question opened")
		test_answer(user, 17.5)
		TEST_ASSERT(timer.timing, "Actual current ticking refusal does not stop or restart the timer")
		timer.set_state(FALSE)
	else
		test_answer(user, 17.5)
		TEST_ASSERT_EQUAL(timer.time, 17.5, "Actual native server answer preserves the original fractional timer assignment")
		TEST_ASSERT_EQUAL(grenade.name, "[initial(grenade.name)](17.5 secs)", "Actual accepted continuation renames the original grenade with its new current timer")
	if(timer_case != "accepted")
		TEST_ASSERT_EQUAL(timer.time, original_time, "Actual cancel or current ticking refusal preserves the real timer budget")
		TEST_ASSERT_EQUAL(grenade.name, original_name, "Actual cancel or current ticking refusal preserves the grenade label")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Actual accepted or cancelled request retires without opening another timer question")
	TEST_ASSERT_EQUAL(grenade.detonator, holder, "Configuration does not replace the actual constructor-owned assembly")
	TEST_ASSERT_EQUAL(timer.loc, holder, "Configuration keeps genuine timer custody intact")

/datum/unit_test/round2_grenade_timer_configuration/cancelled
	timer_case = "cancelled"

/datum/unit_test/round2_grenade_timer_configuration/late_ticking
	timer_case = "late_ticking"
