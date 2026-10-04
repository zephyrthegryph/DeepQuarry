// Computers, batch 3: the medical, security and employment records consoles. See dq_hc_computers_base.dm for the rules.

/// A person holding a card with `access`, standing by the console.
/datum/unit_test/dq_hc_computers/proc/hc_records_user(list/access)
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/card/id/I = allocate(/obj/item/card/id, hc_side())
	I.registered_name = "Records Reader"
	I.assignment = "Tester"
	I.access = access
	hc_hold(H, I)
	return H

/// Scans the held card and logs in with it.
/datum/unit_test/dq_hc_computers/proc/hc_records_login(mob/H, datum/console)
	press(H, console, "scan")
	press(H, console, "login", list("login_type" = LOGIN_TYPE_NORMAL))

/// A general record with a name and id, kept for the test to clean up.
/datum/unit_test/dq_hc_computers/proc/hc_general_record(name, id)
	var/datum/data/record/G = GLOB.data_core.CreateGeneralRecord(null, id)
	G.fields["name"] = name
	LAZYADD(hc_records, G)
	return G

// ---- medical records ----

/datum/unit_test/dq_hc_computers/med_login_needs_access
/datum/unit_test/dq_hc_computers/med_login_needs_access/run_gate()
	var/obj/machinery/computer/med_data/C = hc_console(/obj/machinery/computer/med_data)
	var/mob/living/carbon/human/nobody = hc_records_user(list())
	hc_records_login(nobody, C)
	TEST_ASSERT(!C.authenticated, "a card with no medical access does not log in")
	press(nobody, C, "screen", list("screen" = 4))
	TEST_ASSERT(isnull(C.screen), "and the screens stay shut")
	var/mob/living/carbon/human/doctor = hc_records_user(list(ACCESS_MEDICAL))
	var/obj/machinery/computer/med_data/C2 = hc_console(/obj/machinery/computer/med_data, get_step(hc_spot(), NORTH))
	hc_records_login(doctor, C2)
	TEST_ASSERT_EQUAL(C2.authenticated, "Records Reader", "a medical card logs in")
	TEST_ASSERT_EQUAL(C2.screen, 2, "to the record list")
	TEST_ASSERT_EQUAL(hc_data(C2, doctor)["scan"], C2.scan.name, "the window names the card")
	press(doctor, C2, "logout")
	TEST_ASSERT(!C2.authenticated, "logout logs out")
	TEST_ASSERT(isnull(C2.scan), "and returns the card")

/datum/unit_test/dq_hc_computers/med_records
/datum/unit_test/dq_hc_computers/med_records/run_gate()
	var/obj/machinery/computer/med_data/C = hc_console(/obj/machinery/computer/med_data)
	var/mob/living/carbon/human/doctor = hc_records_user(list(ACCESS_MEDICAL))
	var/datum/data/record/G = hc_general_record("Patient Zed", "0ZED")
	hc_records_login(doctor, C)
	press(doctor, C, "d_rec", list("d_rec" = "[REF(G)]"))
	TEST_ASSERT_EQUAL(C.active1(), G, "a record is opened")
	TEST_ASSERT_EQUAL(C.screen, 4, "on the record screen")
	press(doctor, C, "d_rec", list("d_rec" = "junk"))
	TEST_ASSERT_EQUAL(C.active1(), G, "a junk reference changes nothing")
	press(doctor, C, "new")
	var/datum/data/record/M = C.active2()
	TEST_ASSERT(M, "a medical record is made for the person")
	LAZYADD(hc_records, M)
	TEST_ASSERT_EQUAL(M.fields["name"], "Patient Zed", "with their name")
	TEST_ASSERT(M in GLOB.data_core.medical, "held by the data core")
	M.fields["comments"] = list(list(header = "h1", text = "one"), list(header = "h2", text = "two"))
	press(doctor, C, "del_c", list("del_c" = 1))
	TEST_ASSERT_EQUAL(length(M.fields["comments"]), 1, "a comment is deleted")
	press(doctor, C, "screen", list("screen" = 2))
	TEST_ASSERT(isnull(C.active1()), "going to another screen closes the record")
	press(doctor, C, "search", list("t1" = "patient zed"))
	TEST_ASSERT_EQUAL(C.active2(), M, "a search finds the medical record by name")
	TEST_ASSERT_EQUAL(C.active1(), G, "and its general record")
	press(doctor, C, "search", list("t1" = "nobody by this name"))
	TEST_ASSERT(isnull(C.active2()), "a search for nothing finds nothing")
	TEST_ASSERT(C.temp, "and says so")
	press(doctor, C, "cleartemp")
	TEST_ASSERT(isnull(C.temp), "the message is cleared")
	press(doctor, C, "search", list("t1" = "patient zed"))
	press(doctor, C, "del_r")
	TEST_ASSERT(!(M in GLOB.data_core.medical), "a medical record is deleted")

/datum/unit_test/dq_hc_computers/med_unauthenticated_changes_nothing
/datum/unit_test/dq_hc_computers/med_unauthenticated_changes_nothing/run_gate()
	var/obj/machinery/computer/med_data/C = hc_console(/obj/machinery/computer/med_data)
	var/mob/living/carbon/human/H = hc_actor()
	var/datum/data/record/G = hc_general_record("Patient Yan", "0YAN")
	press(H, C, "d_rec", list("d_rec" = "[REF(G)]"))
	TEST_ASSERT(isnull(C.active1()), "no record opens before a login")
	press(H, C, "del_all")
	TEST_ASSERT(G in GLOB.data_core.general, "nothing is deleted")

/datum/unit_test/dq_hc_computers/med_print_and_notes
/datum/unit_test/dq_hc_computers/med_print_and_notes/run_gate()
	var/obj/machinery/computer/med_data/C = hc_console(/obj/machinery/computer/med_data)
	var/mob/living/carbon/human/doctor = hc_records_user(list(ACCESS_MEDICAL))
	var/datum/data/record/G = hc_general_record("Patient Xi", "0XI")
	hc_records_login(doctor, C)
	press(doctor, C, "d_rec", list("d_rec" = "[REF(G)]"))
	press(doctor, C, "new")
	LAZYADD(hc_records, C.active2())
	var/before = 0
	for(var/obj/item/paper/P in C.loc)
		before++
	press(doctor, C, "print_p")
	test_time(10 SECONDS)
	var/after = 0
	for(var/obj/item/paper/P in C.loc)
		after++
	TEST_ASSERT_EQUAL(after, before + 1, "a record is printed after the printing time")
	TEST_ASSERT(!C.printing, "the printer is free again")
	press(doctor, C, "edit_notes")
	TEST_ASSERT(p2cl_has_question(doctor), "the notes are asked")

// ---- security records ----

/datum/unit_test/dq_hc_computers/sec_login_needs_access
/datum/unit_test/dq_hc_computers/sec_login_needs_access/run_gate()
	var/obj/machinery/computer/secure_data/C = hc_console(/obj/machinery/computer/secure_data)
	var/mob/living/carbon/human/nobody = hc_records_user(list())
	hc_records_login(nobody, C)
	TEST_ASSERT(!C.authenticated, "a card with no security access does not log in")
	var/mob/living/carbon/human/officer = hc_records_user(list(ACCESS_SECURITY))
	var/obj/machinery/computer/secure_data/C2 = hc_console(/obj/machinery/computer/secure_data, get_step(hc_spot(), NORTH))
	hc_records_login(officer, C2)
	TEST_ASSERT_EQUAL(C2.authenticated, "Records Reader", "a security card logs in")
	TEST_ASSERT_EQUAL(C2.screen, 2, "to the record list")
	press(officer, C2, "logout")
	TEST_ASSERT(!C2.authenticated, "logout logs out")

/datum/unit_test/dq_hc_computers/sec_records
/datum/unit_test/dq_hc_computers/sec_records/run_gate()
	var/obj/machinery/computer/secure_data/C = hc_console(/obj/machinery/computer/secure_data)
	var/mob/living/carbon/human/officer = hc_records_user(list(ACCESS_SECURITY))
	var/datum/data/record/G = hc_general_record("Suspect Wen", "0WEN")
	hc_records_login(officer, C)
	press(officer, C, "d_rec", list("d_rec" = "[REF(G)]"))
	TEST_ASSERT_EQUAL(C.active1(), G, "a record is opened")
	press(officer, C, "new")
	var/datum/data/record/S = C.active2()
	TEST_ASSERT(S, "a security record is made")
	LAZYADD(hc_records, S)
	TEST_ASSERT_EQUAL(S.fields["name"], "Suspect Wen", "with their name")
	TEST_ASSERT(S in GLOB.data_core.security, "held by the data core")
	S.fields["comments"] = list(list(header = "h1", text = "one"), list(header = "h2", text = "two"))
	press(officer, C, "del_c", list("del_c" = 2))
	TEST_ASSERT_EQUAL(length(S.fields["comments"]), 1, "a comment is deleted")
	press(officer, C, "screen", list("screen" = 2))
	press(officer, C, "search", list("t1" = "0wen"))
	TEST_ASSERT_EQUAL(C.active1(), G, "a search finds the general record by id")
	TEST_ASSERT_EQUAL(C.active2(), S, "and the security record")
	press(officer, C, "del_r")
	TEST_ASSERT(!(S in GLOB.data_core.security), "a security record is deleted")
	press(officer, C, "cleartemp")
	TEST_ASSERT(isnull(C.temp), "the message is cleared")

/datum/unit_test/dq_hc_computers/sec_delete_everything_about_a_person
/datum/unit_test/dq_hc_computers/sec_delete_everything_about_a_person/run_gate()
	var/obj/machinery/computer/secure_data/C = hc_console(/obj/machinery/computer/secure_data)
	var/mob/living/carbon/human/officer = hc_records_user(list(ACCESS_SECURITY))
	var/datum/data/record/G = hc_general_record("Suspect Vee", "0VEE")
	hc_records_login(officer, C)
	press(officer, C, "d_rec", list("d_rec" = "[REF(G)]"))
	press(officer, C, "new")
	press(officer, C, "del_r_2")
	TEST_ASSERT(!(G in GLOB.data_core.general), "the general record is gone")
	TEST_ASSERT(isnull(C.active2()), "and the security one")

/datum/unit_test/dq_hc_computers/sec_unauthenticated_changes_nothing
/datum/unit_test/dq_hc_computers/sec_unauthenticated_changes_nothing/run_gate()
	var/obj/machinery/computer/secure_data/C = hc_console(/obj/machinery/computer/secure_data)
	var/mob/living/carbon/human/H = hc_actor()
	var/datum/data/record/G = hc_general_record("Suspect Uma", "0UMA")
	press(H, C, "d_rec", list("d_rec" = "[REF(G)]"))
	TEST_ASSERT(isnull(C.active1()), "no record opens before a login")

/datum/unit_test/dq_hc_computers/sec_print_and_notes
/datum/unit_test/dq_hc_computers/sec_print_and_notes/run_gate()
	var/obj/machinery/computer/secure_data/C = hc_console(/obj/machinery/computer/secure_data)
	var/mob/living/carbon/human/officer = hc_records_user(list(ACCESS_SECURITY))
	var/datum/data/record/G = hc_general_record("Suspect Tau", "0TAU")
	hc_records_login(officer, C)
	press(officer, C, "d_rec", list("d_rec" = "[REF(G)]"))
	press(officer, C, "new")
	LAZYADD(hc_records, C.active2())
	var/before = 0
	for(var/obj/item/paper/P in C.loc)
		before++
	press(officer, C, "print_p")
	test_time(10 SECONDS)
	var/after = 0
	for(var/obj/item/paper/P in C.loc)
		after++
	TEST_ASSERT_EQUAL(after, before + 1, "a record is printed after the printing time")
	press(officer, C, "edit_notes")
	TEST_ASSERT(p2cl_has_question(officer), "the notes are asked")

// ---- employment records ----

/datum/unit_test/dq_hc_computers/skills_login_and_screens
/datum/unit_test/dq_hc_computers/skills_login_and_screens/run_gate()
	var/obj/machinery/computer/skills/C = hc_console(/obj/machinery/computer/skills)
	var/mob/living/carbon/human/nobody = hc_records_user(list())
	hc_records_login(nobody, C)
	TEST_ASSERT(!C.authenticated, "a card with no access does not log in")
	var/mob/living/carbon/human/clerk = hc_records_user(C.req_one_access?.Copy() || C.req_access?.Copy() || list())
	var/obj/machinery/computer/skills/C2 = hc_console(/obj/machinery/computer/skills, get_step(hc_spot(), NORTH))
	hc_records_login(clerk, C2)
	TEST_ASSERT(C2.authenticated, "a card with access logs in")
	press(clerk, C2, "cleartemp")
	TEST_ASSERT(isnull(C2.temp), "the message is cleared")
	press(clerk, C2, "logout")
	TEST_ASSERT(!C2.authenticated, "logout logs out")
