// fw-gaps3 content pins for the tgui modals as in-window questions: the chem master, the chemical synthesizer and the chemical dispenser. Written on
// the legacy modal handlers first (ui_modal_opened / ui_modal_answered). A modal opens through the engine's op when the host has one for "modal:<id>",
// else through the legacy act_modal_open(); the client's answer is act_modal_answer() on both.

/datum/unit_test/dq_fwg3_modal
	abstract_type = /datum/unit_test/dq_fwg3_modal

/datum/unit_test/dq_fwg3_modal/Run()
	test_driver_begin()
	p2cl_capture_prompts()
	run_fwg3()
	test_driver_end()
	for(var/turf/T in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
		for(var/obj/item/I in T.contents.Copy())
			qdel(I)

/datum/unit_test/dq_fwg3_modal/proc/run_fwg3()
	return

/datum/unit_test/dq_fwg3_modal/proc/person(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

/// Opens modal `id` of `host`'s window as the client's modal_open does.
/proc/fwg3_modal_open(mob/user, datum/host, id, list/arguments)
	var/datum/op_result/R = test_ui(user, host, OP_UI_MODAL_OPEN, list("id" = id, "arguments" = arguments || list()))
	if(!R)
		host.act_modal_open(user, id, arguments || list())
	return tgui_modal_data(host)

/// Answers the window's modal `id` as the client's modal_answer does.
/proc/fwg3_modal_answer(mob/user, datum/host, id, answer, list/arguments)
	host.act_modal_answer(user, id, answer, arguments || list())
	test_time(1)

/datum/unit_test/dq_fwg3_modal/proc/modal_open(mob/user, datum/host, id, list/arguments)
	return fwg3_modal_open(user, host, id, arguments)

/datum/unit_test/dq_fwg3_modal/proc/modal_answer(mob/user, datum/host, id, answer, list/arguments)
	fwg3_modal_answer(user, host, id, answer, arguments)

/datum/unit_test/dq_fwg3_modal/proc/count_of(turf/T, path)
	. = 0
	for(var/atom/movable/AM in T)
		if(istype(AM, path))
			.++

/// Chem master: the buffer modals move reagents; the pill, patch and bottle modals make them (one modal or a count then a name); the style modals
/// pick a sprite by its index; analyze shows a message modal.
/datum/unit_test/dq_fwg3_modal/chem_master
/datum/unit_test/dq_fwg3_modal/chem_master/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/machinery/chem_master/M = allocate(/obj/machinery/chem_master, T)
	var/obj/item/reagent_containers/glass/beaker/large/B = allocate(/obj/item/reagent_containers/glass/beaker/large, T)
	B.reagents.add_reagent(REAGENT_ID_WATER, 100)
	H.put_in_active_hand(B)
	test_click(H, M, B)
	TEST_ASSERT_EQUAL(M.beaker, B, "the beaker loads")
	hc_ui(H, M, "add", list("id" = REAGENT_ID_WATER, "amount" = 40))
	TEST_ASSERT_EQUAL(M.reagents.get_reagent_amount(REAGENT_ID_WATER), 40, "the add button moves its amount")
	var/list/modal = modal_open(H, M, "create_pill", list("num" = 2))
	TEST_ASSERT_NOTNULL(modal, "the pill question is open")
	modal_answer(H, M, "create_pill", "Test", list("num" = 2))
	TEST_ASSERT_EQUAL(count_of(T, /obj/item/reagent_containers/pill), 2, "two pills made")
	var/obj/item/reagent_containers/pill/P = locate() in T
	TEST_ASSERT_EQUAL(P?.name, "Test pill", "named by the answer")
	modal_open(H, M, "change_pill_style")
	modal_answer(H, M, "change_pill_style", "3")
	TEST_ASSERT_EQUAL(M.pillsprite, 3, "the pill style is the picked index")
	modal_open(H, M, "change_bottle_style")
	modal_answer(H, M, "change_bottle_style", "2")
	TEST_ASSERT_EQUAL(M.bottlesprite, 2, "the bottle style is the picked index")
	hc_ui(H, M, "add", list("id" = REAGENT_ID_WATER, "amount" = 5))
	modal = modal_open(H, M, "analyze", list("idx" = 1, "beaker" = 0))
	TEST_ASSERT_NOTNULL(modal, "analyze shows a message")
	TEST_ASSERT_EQUAL(modal["args"]?["analysis"]?["name"], "Water", "with the reagent's analysis")
	M.act_modal_close(H, "analyze")
	var/mode = M.mode
	hc_ui(H, M, "toggle")
	TEST_ASSERT(M.mode != mode, "toggle flips the mode")
	// the buffer's custom amounts chain to the add and remove buttons (the legacy answer re-ran tgui_act() through the open window, so these two are
	// pinned on the converted form only)
	var/before = M.reagents.get_reagent_amount(REAGENT_ID_WATER)
	modal = modal_open(H, M, "addcustom", list("id" = REAGENT_ID_WATER))
	TEST_ASSERT_NOTNULL(modal, "the add-custom question is the window's modal")
	TEST_ASSERT_EQUAL(modal["id"], "addcustom", "under its id")
	modal_answer(H, M, "addcustom", "10", list("id" = REAGENT_ID_WATER))
	TEST_ASSERT_EQUAL(M.reagents.get_reagent_amount(REAGENT_ID_WATER), before + 10, "the answered amount moved to the buffer")
	TEST_ASSERT_NULL(tgui_modal_data(M), "and the modal closed")
	modal_open(H, M, "removecustom", list("id" = REAGENT_ID_WATER))
	modal_answer(H, M, "removecustom", "10", list("id" = REAGENT_ID_WATER))
	TEST_ASSERT_EQUAL(M.reagents.get_reagent_amount(REAGENT_ID_WATER), before, "removecustom takes the answered amount out")
	M.reagents.add_reagent(REAGENT_ID_WATER, 30)
	modal_open(H, M, "create_bottle_multiple")
	modal_answer(H, M, "create_bottle_multiple", "3")
	modal = tgui_modal_data(M)
	TEST_ASSERT_NOTNULL(modal, "the count answered, the name question follows")
	modal_answer(H, M, "create_bottle", "Water")
	TEST_ASSERT_EQUAL(count_of(T, /obj/item/reagent_containers/glass/bottle), 3, "three bottles made")

/// Chemical synthesizer: the style modals pick a sprite by index; the mode button toggles.
/datum/unit_test/dq_fwg3_modal/synthesizer
/datum/unit_test/dq_fwg3_modal/synthesizer/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/machinery/chemical_synthesizer/S = allocate(/obj/machinery/chemical_synthesizer, T)
	var/list/modal = modal_open(H, S, "change_pill_style")
	TEST_ASSERT_NOTNULL(modal, "the pill style question is the window's modal")
	modal_answer(H, S, "change_pill_style", "4")
	TEST_ASSERT_EQUAL(S.pill_icon, 4, "the pill style is the picked index")
	modal_open(H, S, "change_patch_style")
	modal_answer(H, S, "change_patch_style", "2")
	TEST_ASSERT_EQUAL(S.patch_icon, 2, "the patch style")
	modal_open(H, S, "change_bottle_style")
	modal_answer(H, S, "change_bottle_style", "3")
	TEST_ASSERT_EQUAL(S.bottle_icon, 3, "the bottle style")
	var/mode = S.production_mode
	hc_ui(H, S, "mode_toggle")
	TEST_ASSERT(S.production_mode != mode, "mode_toggle flips the production mode")
	hc_ui(H, S, "drug_form", list("drug_index" = 2))
	TEST_ASSERT_EQUAL(S.drug_substance, 2, "drug_form sets the form")

/// Chemical dispenser: amount and dispense move reagents into the loaded beaker; a recipe records and replays; a broken dispenser ignores its buttons.
/datum/unit_test/dq_fwg3_modal/dispenser
/datum/unit_test/dq_fwg3_modal/dispenser/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/machinery/chemical_dispenser/D = allocate(/obj/machinery/chemical_dispenser, T)
	var/obj/item/reagent_containers/chem_disp_cartridge/water/C = new(T)
	D.add_cartridge(C)
	var/label = C.label
	var/obj/item/reagent_containers/glass/beaker/large/B = allocate(/obj/item/reagent_containers/glass/beaker/large, T)
	H.put_in_active_hand(B)
	test_click(H, D, B)
	TEST_ASSERT_EQUAL(D.container, B, "the beaker loads")
	hc_ui(H, D, "amount", list("amount" = 15))
	TEST_ASSERT_EQUAL(D.amount, 15, "the amount button sets it")
	hc_ui(H, D, "dispense", list("reagent" = label))
	TEST_ASSERT_EQUAL(B.reagents.get_reagent_amount(REAGENT_ID_WATER), 15, "dispense pours that much")
	hc_ui(H, D, "record_recipe")
	TEST_ASSERT_NOTNULL(D.recording_recipe, "recording starts")
	hc_ui(H, D, "dispense", list("reagent" = label))
	TEST_ASSERT_EQUAL(B.reagents.get_reagent_amount(REAGENT_ID_WATER), 15, "while recording, nothing pours")
	TEST_ASSERT_EQUAL(length(D.recording_recipe), 1, "the step is recorded")
	hc_ui(H, D, "cancel_recording")
	TEST_ASSERT_NULL(D.recording_recipe, "cancel drops the recording")
	hc_ui(H, D, "remove", list("reagent" = REAGENT_ID_WATER, "amount" = 5))
	TEST_ASSERT_EQUAL(B.reagents.get_reagent_amount(REAGENT_ID_WATER), 10, "remove takes reagent out of the beaker")
	D.atom_break()
	hc_ui(H, D, "amount", list("amount" = 30))
	TEST_ASSERT_EQUAL(D.amount, 15, "a broken dispenser ignores its buttons")

/// Medical records: the edit modal asks a pick for a field with choices and a text for the rest (the field's kind decides), and the answer is the
/// field's new value; the comment modal adds a log entry. (Pinned on the converted form: the records consoles were converted in this change.)
/datum/unit_test/dq_hc_computers/fwg3_record_modals
/datum/unit_test/dq_hc_computers/fwg3_record_modals/run_gate()
	var/obj/machinery/computer/med_data/C = hc_console(/obj/machinery/computer/med_data)
	var/mob/living/carbon/human/doctor = hc_records_user(list(ACCESS_MEDICAL))
	var/datum/data/record/G = hc_general_record("Patient Zed", "0ZED")
	hc_records_login(doctor, C)
	press(doctor, C, "d_rec", list("d_rec" = "[REF(G)]"))
	press(doctor, C, "new")
	var/datum/data/record/M = C.active2()
	LAZYADD(hc_records, M)
	var/list/modal = fwg3_modal_open(doctor, C, "edit", list("field" = "b_dna", "value" = "old"))
	TEST_ASSERT_EQUAL(modal?["type"], "input", "a text field is asked with an input modal")
	TEST_ASSERT_EQUAL(modal?["value"], "old", "showing the value the window passed")
	fwg3_modal_answer(doctor, C, "edit", "ABC123", list("field" = "b_dna"))
	TEST_ASSERT_EQUAL(M.fields["b_dna"], "ABC123", "the answer is the field's value")
	modal = fwg3_modal_open(doctor, C, "edit", list("field" = "p_stat"))
	TEST_ASSERT_EQUAL(modal?["type"], "choice", "a field with choices is asked with a pick")
	var/list/choices = modal?["choices"]
	TEST_ASSERT(length(choices), "listing them")
	fwg3_modal_answer(doctor, C, "edit", choices[3], list("field" = "p_stat"))
	TEST_ASSERT_EQUAL(G.fields["p_stat"], choices[3], "the picked choice is the general record's field")
	TEST_ASSERT_NULL(fwg3_modal_open(doctor, C, "edit", list("field" = "no_such_field")), "an unknown field opens nothing")
	var/before = length(M.fields["comments"])
	fwg3_modal_open(doctor, C, "add_c")
	fwg3_modal_answer(doctor, C, "add_c", "Seen today.")
	TEST_ASSERT_EQUAL(length(M.fields["comments"]), before + 1, "the comment is logged")
