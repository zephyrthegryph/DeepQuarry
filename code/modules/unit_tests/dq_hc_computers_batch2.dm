// Computers, batch 2: the ID card modification console and the guest pass terminal. See dq_hc_computers_base.dm for the rules.

/// A card that can change IDs (the operator's).
/datum/unit_test/dq_hc_computers/proc/hc_operator_card()
	var/obj/item/card/id/I = allocate(/obj/item/card/id, hc_side())
	I.access = list(ACCESS_CHANGE_IDS)
	return I

/// A plain card with a name and one access.
/datum/unit_test/dq_hc_computers/proc/hc_subject_card()
	var/obj/item/card/id/I = allocate(/obj/item/card/id, hc_side())
	I.registered_name = "Test Subject"
	I.access = list(ACCESS_ENGINE)
	return I

/// Puts the card in the person's active hand.
/datum/unit_test/dq_hc_computers/proc/hc_hold(mob/living/carbon/human/H, obj/item/I)
	H.drop_item()
	if(I)
		H.put_in_active_hand(I)

// ---- ID card modification console ----

/// A console with an operator card scanned and a subject card to modify, and the person who works it.
/datum/unit_test/dq_hc_computers/proc/hc_card_ready()
	var/obj/machinery/computer/card/C = hc_console(/obj/machinery/computer/card)
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/card/id/op = hc_operator_card()
	var/obj/item/card/id/subject = hc_subject_card()
	hc_hold(H, op)
	press(H, C, "scan")
	hc_hold(H, subject)
	press(H, C, "modify")
	return list(C, H, op, subject)

/datum/unit_test/dq_hc_computers/card_insert_and_eject
/datum/unit_test/dq_hc_computers/card_insert_and_eject/run_gate()
	var/list/R = hc_card_ready()
	var/obj/machinery/computer/card/C = R[1]
	var/mob/living/carbon/human/H = R[2]
	TEST_ASSERT_EQUAL(C.scan, R[3], "the operator's card is scanned")
	TEST_ASSERT_EQUAL(C.modify, R[4], "the subject's card is loaded")
	var/list/data = hc_data(C, H)
	TEST_ASSERT(data["authenticated"], "the operator is authenticated")
	TEST_ASSERT(data["has_modify"], "the window shows a card to modify")
	press(H, C, "modify")
	TEST_ASSERT(isnull(C.modify), "the subject's card comes out")
	var/obj/item/card/id/subject = R[4]
	TEST_ASSERT(subject.loc != C, "and is out of the console")
	hc_hold(H, null)
	press(H, C, "scan")
	TEST_ASSERT(isnull(C.scan), "the operator's card comes out")

/datum/unit_test/dq_hc_computers/card_access_toggle
/datum/unit_test/dq_hc_computers/card_access_toggle/run_gate()
	var/list/R = hc_card_ready()
	var/obj/machinery/computer/card/C = R[1]
	var/mob/living/carbon/human/H = R[2]
	var/obj/item/card/id/subject = R[4]
	subject.access = list()
	press(H, C, "access", list("access_target" = ACCESS_ENGINE, "allowed" = 0))
	TEST_ASSERT(ACCESS_ENGINE in subject.access, "an access the card lacks is granted")
	press(H, C, "access", list("access_target" = ACCESS_ENGINE, "allowed" = 1))
	TEST_ASSERT(!(ACCESS_ENGINE in subject.access), "an access it has is taken away")
	press(H, C, "access", list("access_target" = 99999, "allowed" = 0))
	TEST_ASSERT(!length(subject.access), "a number that is no access does nothing")

/datum/unit_test/dq_hc_computers/card_unauthenticated_changes_nothing
/datum/unit_test/dq_hc_computers/card_unauthenticated_changes_nothing/run_gate()
	var/obj/machinery/computer/card/C = hc_console(/obj/machinery/computer/card)
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/card/id/subject = hc_subject_card()
	hc_hold(H, subject)
	press(H, C, "modify")
	TEST_ASSERT_EQUAL(C.modify, subject, "a card can be loaded without an operator")
	press(H, C, "access", list("access_target" = ACCESS_ENGINE, "allowed" = 1))
	TEST_ASSERT(ACCESS_ENGINE in subject.access, "but its access is not changed")
	press(H, C, "terminate")
	TEST_ASSERT_NOTEQUAL(subject.assignment, "Dismissed", "nor is it dismissed")
	press(H, C, "reg", list("reg" = "Someone Else"))
	TEST_ASSERT_EQUAL(subject.registered_name, "Test Subject", "nor renamed")
	press(H, C, "account", list("account" = 1234))
	TEST_ASSERT_NOTEQUAL(subject.associated_account_number, 1234, "nor given an account")

/datum/unit_test/dq_hc_computers/card_edits
/datum/unit_test/dq_hc_computers/card_edits/run_gate()
	var/list/R = hc_card_ready()
	var/obj/machinery/computer/card/C = R[1]
	var/mob/living/carbon/human/H = R[2]
	var/obj/item/card/id/subject = R[4]
	press(H, C, "reg", list("reg" = "Jane Doe"))
	TEST_ASSERT_EQUAL(subject.registered_name, "Jane Doe", "the card is renamed")
	TEST_ASSERT(findtext(subject.name, "Jane Doe"), "and its name follows")
	press(H, C, "account", list("account" = 4321))
	TEST_ASSERT_EQUAL(subject.associated_account_number, 4321, "the account number is set")
	press(H, C, "terminate")
	TEST_ASSERT_EQUAL(subject.assignment, "Dismissed", "terminate dismisses")
	TEST_ASSERT(!length(subject.access), "and strips its access")
	press(H, C, "mode", list("mode_target" = 1))
	TEST_ASSERT_EQUAL(C.mode, 1, "the console goes to the manifest mode")
	TEST_ASSERT_EQUAL(hc_data(C, H)["mode"], 1, "the window says so")

/datum/unit_test/dq_hc_computers/card_assign_unknown_and_custom
/datum/unit_test/dq_hc_computers/card_assign_unknown_and_custom/run_gate()
	var/list/R = hc_card_ready()
	var/obj/machinery/computer/card/C = R[1]
	var/mob/living/carbon/human/H = R[2]
	var/obj/item/card/id/subject = R[4]
	subject.assignment = "Assistant"
	press(H, C, "assign", list("assign_target" = "No Such Job"))
	TEST_ASSERT_EQUAL(subject.assignment, "Assistant", "a job nobody has a log for changes nothing")
	press(H, C, "assign_custom")
	TEST_ASSERT(p2cl_has_question(H), "a custom assignment asks for the text")

/datum/unit_test/dq_hc_computers/card_print
/datum/unit_test/dq_hc_computers/card_print/run_gate()
	var/list/R = hc_card_ready()
	var/obj/machinery/computer/card/C = R[1]
	var/mob/living/carbon/human/H = R[2]
	var/before = 0
	for(var/obj/item/paper/P in C.loc)
		before++
	press(H, C, "print")
	test_time(10 SECONDS)
	var/after = 0
	for(var/obj/item/paper/P in C.loc)
		after++
	TEST_ASSERT_EQUAL(after, before + 1, "a printout comes out after the printing time")
	TEST_ASSERT(!C.printing, "the printer is free again")

// ---- guest pass terminal ----

/datum/unit_test/dq_hc_computers/guestpass_settings
/datum/unit_test/dq_hc_computers/guestpass_settings/run_gate()
	var/obj/machinery/computer/guestpass/C = hc_console(/obj/machinery/computer/guestpass)
	var/mob/living/carbon/human/H = hc_actor()
	press(H, C, "mode", list("mode" = 1))
	TEST_ASSERT_EQUAL(C.mode, 1, "the log mode")
	TEST_ASSERT_EQUAL(hc_data(C, H)["mode"], 1, "the window shows it")
	press(H, C, "giv_name")
	TEST_ASSERT(p2cl_has_question(H), "the name is asked")
	press(H, C, "reason")
	TEST_ASSERT(p2cl_has_question(H), "the reason is asked")
	press(H, C, "duration")
	TEST_ASSERT(p2cl_has_question(H), "the duration is asked")

/datum/unit_test/dq_hc_computers/guestpass_issue
/datum/unit_test/dq_hc_computers/guestpass_issue/run_gate()
	var/obj/machinery/computer/guestpass/C = hc_console(/obj/machinery/computer/guestpass)
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/card/id/giver = hc_subject_card()
	giver.registered_name = "Giver"
	giver.access = list(ACCESS_ENGINE, ACCESS_CHANGE_IDS)
	var/passes = 0
	for(var/obj/item/card/id/guest/G in C.loc)
		passes++
	press(H, C, "issue")
	var/now = 0
	for(var/obj/item/card/id/guest/G in C.loc)
		now++
	TEST_ASSERT_EQUAL(now, passes, "no pass is issued without an ID in the terminal")
	hc_hold(H, giver)
	press(H, C, "id")
	TEST_ASSERT_EQUAL(C.giver, giver, "the issuing ID goes in")
	press(H, C, "access", list("access" = ACCESS_ENGINE))
	TEST_ASSERT(ACCESS_ENGINE in C.accesses, "an access the card has is selected")
	press(H, C, "access", list("access" = 99999))
	TEST_ASSERT(!(99999 in C.accesses), "one it lacks is refused")
	var/list/data = hc_data(C, H)
	TEST_ASSERT(length(data["area"]), "the window lists the card's areas")
	press(H, C, "issue")
	var/obj/item/card/id/guest/pass
	for(var/obj/item/card/id/guest/G in C.loc)
		pass = G
	TEST_ASSERT(pass, "a pass is printed")
	TEST_ASSERT(ACCESS_ENGINE in pass.temp_access, "with the selected access")
	TEST_ASSERT_EQUAL(length(C.internal_log), 1, "and one line in the log")
	press(H, C, "access", list("access" = ACCESS_ENGINE))
	TEST_ASSERT(!(ACCESS_ENGINE in C.accesses), "selecting it again deselects it")
	press(H, C, "id")
	TEST_ASSERT(isnull(C.giver), "the ID comes out")
	TEST_ASSERT(giver.loc != C, "and is out of the terminal")

/datum/unit_test/dq_hc_computers/guestpass_print_log
/datum/unit_test/dq_hc_computers/guestpass_print_log/run_gate()
	var/obj/machinery/computer/guestpass/C = hc_console(/obj/machinery/computer/guestpass)
	var/mob/living/carbon/human/H = hc_actor()
	var/before = 0
	for(var/obj/item/paper/P in C.loc)
		before++
	press(H, C, "print")
	var/after = 0
	for(var/obj/item/paper/P in C.loc)
		after++
	TEST_ASSERT_EQUAL(after, before + 1, "the log is printed")

// ---- added with the conversion: what the answers do (a test mob has no client, so a legacy prompt could not be answered) ----

/datum/unit_test/dq_hc_computers/card_custom_assignment_answer
/datum/unit_test/dq_hc_computers/card_custom_assignment_answer/run_gate()
	var/list/R = hc_card_ready()
	var/obj/machinery/computer/card/C = R[1]
	var/mob/living/carbon/human/H = R[2]
	var/obj/item/card/id/subject = R[4]
	press(H, C, "assign_custom")
	p2cl_answer(H, "Space Janitor")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(subject.assignment, "Space Janitor", "the answer is the assignment")

/datum/unit_test/dq_hc_computers/guestpass_answers
/datum/unit_test/dq_hc_computers/guestpass_answers/run_gate()
	var/obj/machinery/computer/guestpass/C = hc_console(/obj/machinery/computer/guestpass)
	var/mob/living/carbon/human/H = hc_actor()
	press(H, C, "giv_name")
	p2cl_answer(H, "Visitor Vee")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(C.giv_name, "Visitor Vee", "the name is set")
	press(H, C, "reason")
	p2cl_answer(H, "Touring the lab")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(C.reason, "Touring the lab", "the reason is set")
	press(H, C, "duration")
	p2cl_answer(H, 30)
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(C.duration, 30, "the duration is set")
	press(H, C, "duration")
	p2cl_answer(H, 0)
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(C.duration, 30, "a duration of nothing is ignored")

/datum/unit_test/dq_hc_computers/guest_pass_deactivation
/datum/unit_test/dq_hc_computers/guest_pass_deactivation/run_gate()
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/card/id/guest/G = allocate(/obj/item/card/id/guest, hc_side())
	EXPIRY_SET(G, expiration_time, 1 HOURS, CLOCK_WORLD)
	G.expired = 0
	G.icon_state = "guest"
	H.set_combat_mode(TRUE)
	hc_hold(H, G)
	TEST_ASSERT_EQUAL(H.get_active_hand(), G, "the real pass is carried before self input")
	TEST_ASSERT_EQUAL(H.input_stance(), I_HURT, "deactivation self input uses the actual harm stance")
	var/datum/op_result/first = own(test_click(H, G, G, GESTURE_SELF))
	TEST_ASSERT(p2cl_has_question(H), "deactivating asks first (key=[first?.key], outcome=[first?.outcome], reason=[first?.reason])")
	p2cl_answer(H, FALSE)
	test_time(1 SECONDS)
	TEST_ASSERT(!G.expired, "a no leaves the pass alone")
	var/datum/op_result/second = own(test_click(H, G, G, GESTURE_SELF))
	TEST_ASSERT(p2cl_has_question(H), "repeat self input opens confirmation (key=[second?.key], outcome=[second?.outcome], reason=[second?.reason])")
	p2cl_answer(H, TRUE)
	test_time(1 SECONDS)
	TEST_ASSERT(G.expired, "a yes deactivates it")

/datum/unit_test/dq_hc_computers/guest_pass_expired_state_gates_deactivation
/datum/unit_test/dq_hc_computers/guest_pass_expired_state_gates_deactivation/run_gate()
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/card/id/guest/G = allocate(/obj/item/card/id/guest, hc_side())
	EXPIRY_SET(G, expiration_time, 1 HOURS, CLOCK_WORLD)
	G.set_expired(TRUE)
	G.icon_state = "guest" // a stale rendering must not reactivate the real expired pass
	H.set_combat_mode(TRUE)
	hc_hold(H, G)
	test_click(H, G, G, GESTURE_SELF)
	TEST_ASSERT(!p2cl_has_question(H), "the gameplay expiry flag refuses deactivation even with a stale sprite")
	TEST_ASSERT(G.expired, "refusal preserves the real expired state")
