// Computers, batch 4: the messaging monitor and the cloning console. See dq_hc_computers_base.dm for the rules.

// ---- messaging monitor ----

/// A console linked to a message server with a known key.
/datum/unit_test/dq_hc_computers/proc/hc_monitor()
	var/obj/machinery/message_server/S = allocate(/obj/machinery/message_server, get_step(hc_spot(), NORTH))
	S.set_grid_power(TRUE)
	S.set_broken_condition(FALSE)
	S.decryptkey = "sesame"
	var/obj/machinery/computer/message_monitor/C = hc_console(/obj/machinery/computer/message_monitor)
	rel_set(C, nameof(/obj/machinery/computer/message_monitor::linkedServer), S)
	return C

/datum/unit_test/dq_hc_computers/monitor_authentication
/datum/unit_test/dq_hc_computers/monitor_authentication/run_gate()
	var/obj/machinery/computer/message_monitor/C = hc_monitor()
	var/mob/living/carbon/human/H = hc_actor()
	press(H, C, "auth", list("key" = "wrong"))
	TEST_ASSERT(!C.auth, "a wrong key does not authenticate")
	TEST_ASSERT(C.temp, "and says so")
	press(H, C, "cleartemp")
	TEST_ASSERT(isnull(C.temp), "the message is cleared")
	press(H, C, "auth", list("key" = ""))
	TEST_ASSERT(!C.auth, "an empty key does nothing")
	press(H, C, "auth", list("key" = "sesame"))
	TEST_ASSERT(C.auth, "the right key authenticates")
	press(H, C, "deauth")
	TEST_ASSERT(!C.auth, "deauthenticating works")

/datum/unit_test/dq_hc_computers/monitor_needs_auth
/datum/unit_test/dq_hc_computers/monitor_needs_auth/run_gate()
	var/obj/machinery/computer/message_monitor/C = hc_monitor()
	var/mob/living/carbon/human/H = hc_actor()
	var/active = C.linkedServer().active
	press(H, C, "active")
	TEST_ASSERT_EQUAL(C.linkedServer().active, active, "the server is not switched without a key")
	press(H, C, "set_sender", list("val" = "Nobody"))
	TEST_ASSERT_NOTEQUAL(C.customsender, "Nobody", "the sender is not set without a key")
	press(H, C, "addtoken")
	TEST_ASSERT(!p2cl_has_question(H), "no question without a key")

/datum/unit_test/dq_hc_computers/monitor_controls
/datum/unit_test/dq_hc_computers/monitor_controls/run_gate()
	var/obj/machinery/computer/message_monitor/C = hc_monitor()
	var/mob/living/carbon/human/H = hc_actor()
	press(H, C, "auth", list("key" = "sesame"))
	var/active = C.linkedServer().active
	press(H, C, "active")
	TEST_ASSERT_NOTEQUAL(C.linkedServer().active, active, "the server is switched")
	press(H, C, "set_sender", list("val" = "Fake Sender"))
	TEST_ASSERT_EQUAL(C.customsender, "Fake Sender", "the sender is set")
	press(H, C, "set_sender_job", list("val" = "Fake Job"))
	TEST_ASSERT_EQUAL(C.customjob, "Fake Job", "the job is set")
	press(H, C, "set_message", list("val" = "Hello there"))
	TEST_ASSERT_EQUAL(C.custommessage, "Hello there", "the message is set")
	press(H, C, "send_message")
	TEST_ASSERT(C.temp, "sending with no recipient says so")
	var/list/spam = C.linkedServer().spamfilter
	var/count = length(spam)
	press(H, C, "deltoken", list("deltoken" = 1))
	TEST_ASSERT_EQUAL(length(C.linkedServer().spamfilter), count - 1, "a filter token is deleted")

/datum/unit_test/dq_hc_computers/monitor_questions
/datum/unit_test/dq_hc_computers/monitor_questions/run_gate()
	var/obj/machinery/computer/message_monitor/C = hc_monitor()
	var/mob/living/carbon/human/H = hc_actor()
	press(H, C, "auth", list("key" = "sesame"))
	press(H, C, "addtoken")
	TEST_ASSERT(p2cl_has_question(H), "a token is asked for")
	press(H, C, "pass")
	TEST_ASSERT(p2cl_has_question(H), "the current key is asked for")

/datum/unit_test/dq_hc_computers/monitor_find_single_server
/datum/unit_test/dq_hc_computers/monitor_find_single_server/run_gate()
	var/obj/machinery/computer/message_monitor/C = hc_monitor()
	var/mob/living/carbon/human/H = hc_actor()
	rel_clear(C, nameof(/obj/machinery/computer/message_monitor::linkedServer))
	press(H, C, "find")
	TEST_ASSERT(C.temp || p2cl_has_question(H), "finding a server says something or asks which")

// ---- cloning console ----

/datum/unit_test/dq_hc_computers/cloning_basics
/datum/unit_test/dq_hc_computers/cloning_basics/run_gate()
	var/obj/machinery/computer/cloning/C = hc_console(/obj/machinery/computer/cloning)
	var/mob/living/carbon/human/H = hc_actor()
	press(H, C, "menu", list("num" = 2))
	TEST_ASSERT_EQUAL(C.menu, 2, "the records menu")
	press(H, C, "menu", list("num" = 9))
	TEST_ASSERT_EQUAL(C.menu, 2, "an out of range menu is clamped to the last")
	press(H, C, "menu", list("num" = 1))
	TEST_ASSERT_EQUAL(C.menu, 1, "the main menu")
	TEST_ASSERT_EQUAL(hc_data(C, H)["menu"], 1, "the window shows it")
	press(H, C, "autoprocess", list("on" = 1))
	TEST_ASSERT(C.autoprocess, "autoprocess goes on")
	press(H, C, "autoprocess", list("on" = 0))
	TEST_ASSERT(!C.autoprocess, "and off")
	C.temp = list(text = "x", style = "info")
	press(H, C, "cleartemp")
	TEST_ASSERT(isnull(C.temp), "the message is cleared")
	press(H, C, "toggle_mode")
	TEST_ASSERT(!C.scan_mode, "without a tier four scanner the best scan is not available")
	press(H, C, "view_rec", list("ref" = "junk"))
	press(H, C, "del_rec")
	press(H, C, "clone", list("ref" = "junk"))
	press(H, C, "selectpod", list("ref" = "junk"))
	press(H, C, "lock")
	press(H, C, "scan")
	press(H, C, "refresh")
	press(H, C, "disk", list("option" = "save"))
	press(H, C, "disk", list("option" = "load"))
	TEST_ASSERT(!QDELETED(C), "buttons that have nothing to work on do nothing")

// ---- added with the conversion: the answers (a test mob has no client, so a legacy prompt could not be answered) ----

/datum/unit_test/dq_hc_computers/monitor_answers
/datum/unit_test/dq_hc_computers/monitor_answers/run_gate()
	var/obj/machinery/computer/message_monitor/C = hc_monitor()
	var/mob/living/carbon/human/H = hc_actor()
	press(H, C, "auth", list("key" = "sesame"))
	press(H, C, "addtoken")
	p2cl_answer(H, "free money")
	test_time(1 SECONDS)
	TEST_ASSERT("free money" in C.linkedServer().spamfilter, "the token joins the filter")
	press(H, C, "pass")
	p2cl_answer(H, "not the key")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(C.linkedServer().decryptkey, "sesame", "a wrong current key changes nothing")
	TEST_ASSERT(!p2cl_has_question(H), "and asks nothing more")
	press(H, C, "pass")
	p2cl_answer(H, "sesame")
	test_time(1 SECONDS)
	TEST_ASSERT(p2cl_has_question(H), "the right key asks for the new one")
	p2cl_answer(H, "opensesame")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(C.linkedServer().decryptkey, "opensesame", "which is set")

/datum/unit_test/dq_hc_computers/monitor_emag_reboot
/datum/unit_test/dq_hc_computers/monitor_emag_reboot/run_gate()
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/card/emag/E = hc_emag(H)
	var/obj/machinery/computer/message_monitor/C = hc_monitor()
	C.linkedServer().decryptkey = "x"
	test_click(H, C, E)
	TEST_ASSERT(C.emag, "a linked working console enters its reboot state")
	TEST_ASSERT_EQUAL(E.uses, 7, "a successful reboot spends one use")
	TEST_ASSERT_EQUAL(C.temp, C.rebootmsg, "the viewer is sent the reboot message")
	var/printouts = 0
	for(var/obj/item/paper/monitorkey/P in hc_spot())
		printouts++
	TEST_ASSERT_EQUAL(printouts, 1, "the successful swipe prints the server key")
	test_click(H, C, E)
	TEST_ASSERT_EQUAL(E.uses, 7, "a console still rebooting declines another swipe")
	test_time(10 SECONDS)
	TEST_ASSERT(!C.emag, "the key-length timer restores the console")
	test_click(H, C, E)
	TEST_ASSERT(C.emag, "the repeatable console can be hacked again after reboot")
	TEST_ASSERT_EQUAL(E.uses, 6, "a new reboot spends a new use")
	rel_clear(C, nameof(/obj/machinery/computer/message_monitor::linkedServer))
	C.set_emag(FALSE)
	test_click(H, C, E)
	TEST_ASSERT_EQUAL(E.uses, 6, "an unlinked console declines without spending a use")
	TEST_ASSERT(!C.emag, "an unlinked console cannot start a reboot")
	for(var/obj/effect/effect/sparks/S in range(2, C)) // the emag's sparks are the test's to clean up
		own(S)
