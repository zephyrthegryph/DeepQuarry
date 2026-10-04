// Computers, batch 1: atmospheric alerts, prisoner management, the AI restorer, the patient monitor, the timeclock, robotics control.
// See dq_hc_computers_base.dm for the rules.

// ---- atmospheric alert console ----

/datum/unit_test/dq_hc_computers/atmos_alert_data
/datum/unit_test/dq_hc_computers/atmos_alert_data/run_gate()
	var/obj/machinery/computer/atmos_alert/C = hc_console(/obj/machinery/computer/atmos_alert)
	var/mob/living/carbon/human/H = hc_actor()
	var/list/data = hc_data(C, H)
	TEST_ASSERT(islist(data["priority_alarms"]), "the window lists the priority alarms")
	TEST_ASSERT(islist(data["minor_alarms"]), "the window lists the minor alarms")

/datum/unit_test/dq_hc_computers/atmos_alert_clear_unknown
/datum/unit_test/dq_hc_computers/atmos_alert_clear_unknown/run_gate()
	var/obj/machinery/computer/atmos_alert/C = hc_console(/obj/machinery/computer/atmos_alert)
	var/mob/living/carbon/human/H = hc_actor()
	press(H, C, "clear", list("ref" = "[REF(H)]"))
	press(H, C, "clear", list("ref" = "not a ref"))
	press(H, C, "clear", list())
	TEST_ASSERT(!QDELETED(C), "a clear of something that is no alarm does nothing and breaks nothing")

// ---- prisoner management ----

/datum/unit_test/dq_hc_computers/prisoner_lock_needs_access
/datum/unit_test/dq_hc_computers/prisoner_lock_needs_access/run_gate()
	var/obj/machinery/computer/prisoner/C = hc_console(/obj/machinery/computer/prisoner)
	var/mob/living/carbon/human/nobody = hc_actor()
	var/mob/living/carbon/human/boss = hc_boss(get_step(hc_side(), NORTH))
	TEST_ASSERT(!C.screen, "starts locked")
	press(nobody, C, "lock")
	TEST_ASSERT(!C.screen, "somebody with no access cannot unlock it")
	press(boss, C, "lock")
	TEST_ASSERT(C.screen, "somebody with access unlocks it")
	var/list/data = hc_data(C, boss)
	TEST_ASSERT(!data["locked"], "the window says it is unlocked")
	press(boss, C, "lock")
	TEST_ASSERT(!C.screen, "and locks it again")
	TEST_ASSERT(hc_data(C, boss)["locked"], "the window says it is locked")

/datum/unit_test/dq_hc_computers/prisoner_inject_unknown
/datum/unit_test/dq_hc_computers/prisoner_inject_unknown/run_gate()
	var/obj/machinery/computer/prisoner/C = hc_console(/obj/machinery/computer/prisoner)
	var/mob/living/carbon/human/boss = hc_boss()
	press(boss, C, "inject", list("imp" = "[REF(boss)]", "val" = 5))
	press(boss, C, "inject", list("imp" = "junk", "val" = 5))
	TEST_ASSERT(!QDELETED(C), "an inject at something that is no implant does nothing")

/datum/unit_test/dq_hc_computers/prisoner_warn_asks
/datum/unit_test/dq_hc_computers/prisoner_warn_asks/run_gate()
	var/obj/machinery/computer/prisoner/C = hc_console(/obj/machinery/computer/prisoner)
	var/mob/living/carbon/human/boss = hc_boss()
	press(boss, C, "warn", list("imp" = "[REF(boss)]"))
	TEST_ASSERT(p2cl_has_question(boss), "a warning asks the operator what to say")
	p2cl_answer(boss, "stay calm")
	test_time(1 SECONDS)
	TEST_ASSERT(!p2cl_has_question(boss), "the answer closes the question")

// ---- AI restorer ----

/datum/unit_test/dq_hc_computers/aifixer_empty
/datum/unit_test/dq_hc_computers/aifixer_empty/run_gate()
	var/obj/machinery/computer/aifixer/C = hc_console(/obj/machinery/computer/aifixer)
	var/mob/living/carbon/human/boss = hc_boss()
	var/list/data = hc_data(C, boss)
	TEST_ASSERT(!data["AI_present"], "no AI in the terminal")
	TEST_ASSERT(data["error"], "the window asks for a transfer")
	press(boss, C, "PRG_beginReconstruction")
	TEST_ASSERT(!C.restoring, "nothing to restore with no AI")

/datum/unit_test/dq_hc_computers/aifixer_restores
/datum/unit_test/dq_hc_computers/aifixer_restores/run_gate()
	var/obj/machinery/computer/aifixer/C = hc_console(/obj/machinery/computer/aifixer)
	var/mob/living/carbon/human/boss = hc_boss()
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, get_step(hc_spot(), NORTH), null, null, null, TRUE)
	rel_set(C, nameof(/obj/machinery/computer/aifixer::occupier), AI)
	AI.adjust_backup_charge(-50)
	var/list/data = hc_data(C, boss)
	TEST_ASSERT(data["AI_present"], "an AI is in the terminal")
	TEST_ASSERT_EQUAL(data["name"], AI.name, "the window names the AI")
	press(boss, C, "PRG_beginReconstruction")
	TEST_ASSERT(C.restoring, "a damaged AI starts to be restored")

// ---- patient monitor ----

/datum/unit_test/dq_hc_computers/operating_toggles
/datum/unit_test/dq_hc_computers/operating_toggles/run_gate()
	var/obj/machinery/computer/operating/C = hc_console(/obj/machinery/computer/operating)
	var/mob/living/carbon/human/H = hc_actor()
	press(H, C, "verboseOff")
	TEST_ASSERT(!C.verbose, "verboseOff")
	press(H, C, "verboseOn")
	TEST_ASSERT(C.verbose, "verboseOn")
	press(H, C, "healthOff")
	TEST_ASSERT(!C.healthAnnounce, "healthOff")
	press(H, C, "healthOn")
	TEST_ASSERT(C.healthAnnounce, "healthOn")
	press(H, C, "critOff")
	TEST_ASSERT(!C.crit, "critOff")
	press(H, C, "critOn")
	TEST_ASSERT(C.crit, "critOn")
	press(H, C, "spo2Off")
	TEST_ASSERT(!C.spo2, "spo2Off")
	press(H, C, "spo2On")
	TEST_ASSERT(C.spo2, "spo2On")
	press(H, C, "choiceOn")
	TEST_ASSERT(C.choice, "choiceOn")
	press(H, C, "choiceOff")
	TEST_ASSERT(!C.choice, "choiceOff")

/datum/unit_test/dq_hc_computers/operating_thresholds
/datum/unit_test/dq_hc_computers/operating_thresholds/run_gate()
	var/obj/machinery/computer/operating/C = hc_console(/obj/machinery/computer/operating)
	var/mob/living/carbon/human/H = hc_actor()
	press(H, C, "spo2_adj", list("new" = 70))
	TEST_ASSERT_EQUAL(C.spo2Alarm, 70, "the saturation alarm is set")
	press(H, C, "spo2_adj", list("new" = 250))
	TEST_ASSERT_EQUAL(C.spo2Alarm, 100, "and clamped to 100")
	press(H, C, "health_adj", list("new" = 30))
	TEST_ASSERT_EQUAL(C.healthAlarm, 30, "the health alarm is set")
	press(H, C, "health_adj", list("new" = -500))
	TEST_ASSERT_EQUAL(C.healthAlarm, -100, "and clamped to -100")
	var/list/data = hc_data(C, H)
	TEST_ASSERT_EQUAL(data["healthAlarm"], -100, "the window shows it")
	TEST_ASSERT_EQUAL(data["hasOccupant"], 0, "no patient on the table")

// ---- timeclock ----

/datum/unit_test/dq_hc_computers/timeclock_card
/datum/unit_test/dq_hc_computers/timeclock_card/run_gate()
	var/obj/machinery/computer/timeclock/C = hc_console(/obj/machinery/computer/timeclock)
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/card/id/I = allocate(/obj/item/card/id, H)
	H.put_in_active_hand(I)
	TEST_ASSERT(isnull(hc_data(C, H)["card"]), "no card in the terminal")
	press(H, C, "id")
	TEST_ASSERT_EQUAL(C.card, I, "the held card goes in")
	TEST_ASSERT(hc_data(C, H)["card"], "the window shows the card")
	press(H, C, "id")
	TEST_ASSERT(isnull(C.card), "pressing it again takes the card out")
	TEST_ASSERT_EQUAL(I.loc, H, "and the card is in the person's hands")
	TEST_ASSERT_EQUAL(hc_data(C, H)["user_name"], "[H]", "the window names the viewer")

/datum/unit_test/dq_hc_computers/timeclock_no_card_switch
/datum/unit_test/dq_hc_computers/timeclock_no_card_switch/run_gate()
	var/obj/machinery/computer/timeclock/C = hc_console(/obj/machinery/computer/timeclock)
	var/mob/living/carbon/human/H = hc_actor()
	press(H, C, "switch-to-offduty")
	press(H, C, "switch-to-onduty-rank", list("assignment" = "x", "rank" = "y"))
	TEST_ASSERT(isnull(C.card), "with no card inserted a switch does nothing")

// ---- robotics control ----

/datum/unit_test/dq_hc_computers/robotics_needs_access
/datum/unit_test/dq_hc_computers/robotics_needs_access/run_gate()
	var/obj/machinery/computer/robotics/C = hc_console(/obj/machinery/computer/robotics)
	var/mob/living/carbon/human/nobody = hc_actor()
	var/mob/living/carbon/human/boss = hc_boss(get_step(hc_side(), NORTH))
	TEST_ASSERT(C.safety, "the self destruct starts disarmed")
	press(nobody, C, "arm")
	TEST_ASSERT(C.safety, "somebody with no access cannot arm it")
	TEST_ASSERT(!hc_data(C, nobody)["auth"], "the window says they are not authenticated")
	press(boss, C, "arm")
	TEST_ASSERT(!C.safety, "somebody with access arms it")
	TEST_ASSERT(hc_data(C, boss)["auth"], "the window says they are authenticated")
	press(boss, C, "arm")
	TEST_ASSERT(C.safety, "and disarms it")

/datum/unit_test/dq_hc_computers/robotics_nuke_needs_arming
/datum/unit_test/dq_hc_computers/robotics_nuke_needs_arming/run_gate()
	var/obj/machinery/computer/robotics/C = hc_console(/obj/machinery/computer/robotics)
	var/mob/living/carbon/human/boss = hc_boss()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, get_step(hc_spot(), NORTH))
	press(boss, C, "nuke")
	TEST_ASSERT(!QDELETED(R), "with the safety on the borg survives the detonate-all")

/datum/unit_test/dq_hc_computers/robotics_lockdown_toggle
/datum/unit_test/dq_hc_computers/robotics_lockdown_toggle/run_gate()
	var/obj/machinery/computer/robotics/C = hc_console(/obj/machinery/computer/robotics)
	var/mob/living/carbon/human/boss = hc_boss()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, get_step(hc_spot(), NORTH))
	TEST_ASSERT(!R.lockcharge, "not locked down")
	press(boss, C, "stopbot", list("ref" = "[REF(R)]"))
	TEST_ASSERT(R.lockcharge, "the console locks the borg down")
	press(boss, C, "stopbot", list("ref" = "[REF(R)]"))
	TEST_ASSERT(!R.lockcharge, "and releases it")
	var/mob/living/carbon/human/nobody = hc_actor()
	press(nobody, C, "stopbot", list("ref" = "[REF(R)]"))
	TEST_ASSERT(!R.lockcharge, "somebody with no access cannot lock it down")
	press(boss, C, "stopbot", list("ref" = "junk"))
	TEST_ASSERT(!R.lockcharge, "a junk reference changes nothing")

/datum/unit_test/dq_hc_computers/robotics_cyborg_cannot_control_others
/datum/unit_test/dq_hc_computers/robotics_cyborg_cannot_control_others/run_gate()
	var/obj/machinery/computer/robotics/C = hc_console(/obj/machinery/computer/robotics)
	C.req_access = list()
	var/mob/living/silicon/robot/user = allocate(/mob/living/silicon/robot, hc_side())
	var/mob/living/silicon/robot/other = allocate(/mob/living/silicon/robot, get_step(hc_spot(), NORTH))
	press(user, C, "stopbot", list("ref" = "[REF(other)]"))
	TEST_ASSERT(!other.lockcharge, "a cyborg cannot lock down another")
	press(user, C, "arm")
	TEST_ASSERT(C.safety, "a cyborg cannot arm the self destruct")
