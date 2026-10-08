// Old-code behavior pins now exercise native questions, prompt claims and the real scan wait.
/datum/unit_test/dq_timed_pin/last_medical_kiosk
	var/end_mode = "complete"

/datum/unit_test/dq_timed_pin/last_medical_kiosk/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/machinery/medical_kiosk/K = allocate(/obj/machinery/medical_kiosk, user.loc)
	K.set_grid_power(TRUE)
	K.set_broken_condition(FALSE)
	K.set_panel_open(FALSE)
	TEST_ASSERT(K.operable(), "The real kiosk starts functional")
	TEST_ASSERT_NULL(K.active_user(), "There is no prior patient")
	TEST_ASSERT_EQUAL(K.use_power, USE_POWER_IDLE, "The kiosk starts in standby")
	test_menu(user, K, "medical_kiosk_interaction_hand")
	var/datum/prompt/choice/P = SSrequests.open_for(user)
	TEST_ASSERT(istype(P), "The real hand operation opens the service choice")
	TEST_ASSERT_EQUAL(length(P.choices), 3, "Exactly the original three service choices remain available")
	TEST_ASSERT("Health Scan" in P.choices, "Health Scan remains available")
	TEST_ASSERT("Backup Scan" in P.choices, "Backup Scan remains available")
	TEST_ASSERT("Cancel" in P.choices, "Cancel remains available")
	TEST_ASSERT(op_claimed(K), "Opening the questions claims the real kiosk")
	TEST_ASSERT_NULL(K.active_user(), "Questions do not start the patient scan")
	TEST_ASSERT_EQUAL(K.use_power, USE_POWER_IDLE, "Questions reserve without active scan power")
	if(end_mode == "competition")
		var/mob/living/carbon/human/other = person(get_turf(user))
		test_menu(other, K, "medical_kiosk_interaction_hand")
		TEST_ASSERT_NULL(SSrequests.open_for(other), "A competing patient cannot start another session while questions are open")
		TEST_ASSERT_EQUAL(SSrequests.open_for(user), P, "Competition preserves the first patient's actual prompt")
	if(end_mode == "cancel")
		test_answer(user, "Cancel")
	else if(end_mode == "timeout")
		test_time(10.1 SECONDS)
	else if(end_mode == "panel")
		K.set_panel_open(TRUE)
		test_answer(user, "Health Scan")
	else
		test_answer(user, "Health Scan")
		var/datum/action = running(user)
		TEST_ASSERT_NOTNULL(action, "Answering Health Scan starts a real timed scan")
		TEST_ASSERT_EQUAL(K.active_user(), user, "The scan records its actual patient")
		TEST_ASSERT_EQUAL(K.use_power, USE_POWER_ACTIVE, "Only an active scan consumes active power")
		test_chat_clear()
		if(end_mode == "move")
			user.forceMove(get_step(get_step(get_turf(K), EAST), EAST))
		else
			test_time(4.9 SECONDS)
			TEST_ASSERT(!said(user, "Health report results:"), "A scan never delivers its diagnosis early")
			test_time(0.2 SECONDS)
			TEST_ASSERT(said(user, "Health report results:"), "The completed scan delivers an actual diagnosis")
		if(end_mode == "move")
			test_time(5.1 SECONDS)
			TEST_ASSERT(was_cancelled(action, user), "Walking away cancels the actual timed scan")
			TEST_ASSERT(!said(user, "Health report results:"), "A cancelled scan gives no diagnosis")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Finishing or cancelling closes the real question")
	TEST_ASSERT_NULL(K.active_user(), "Every finish path releases the actual patient relation")
	TEST_ASSERT(!op_claimed(K), "Every finish path releases the prompt and scan claim")
	TEST_ASSERT_EQUAL(K.use_power, USE_POWER_IDLE, "Every finish path restores standby power")
	TEST_ASSERT_NULL(running(user), "No scan is left running after completion or cancellation")

/datum/unit_test/dq_timed_pin/last_medical_kiosk/cancel
	end_mode = "cancel"
/datum/unit_test/dq_timed_pin/last_medical_kiosk/timeout
	end_mode = "timeout"
/datum/unit_test/dq_timed_pin/last_medical_kiosk/panel
	end_mode = "panel"
/datum/unit_test/dq_timed_pin/last_medical_kiosk/move
	end_mode = "move"
/datum/unit_test/dq_timed_pin/last_medical_kiosk/competition
	end_mode = "competition"
