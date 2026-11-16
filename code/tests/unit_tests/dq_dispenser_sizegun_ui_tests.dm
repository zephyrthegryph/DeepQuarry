// The size gun's size window closes when it is submitted, and a chemical dispenser starts with every cartridge full.

/datum/unit_test/dq_hc_tgui/sizegun_submit_closes_window

/datum/unit_test/dq_hc_tgui/sizegun_submit_closes_window/run_gate()
	var/mob/living/carbon/human/H = hct_actor()
	var/obj/item/gun/energy/sizegun/gun = allocate(/obj/item/gun/energy/sizegun, hct_spot())
	var/datum/request/asked = open_request(gun, /datum/prompt/number/sizegun_size, TYPE_PROC_REF(/obj/item/gun/energy/sizegun, size_selected), answerer = H, question = "Size?", default = gun.size_set_to * 100)
	var/datum/prompt/number/sizegun_size/prompt = asked
	TEST_ASSERT(istype(prompt), "the size question is a size prompt")
	var/datum/tgui_input_number/prompt/box = prompt.present(H)
	TEST_ASSERT(istype(box), "the prompt makes a number window")
	rel_set(prompt, nameof(prompt.window), box)
	var/datum/tgui/ui = hct_window(src, H, box)
	var/datum/op_result/result = test_ui(H, box, "submit", list("entry" = 150))
	TEST_ASSERT_NOTNULL(result, "the submit button is an op of the window")
	TEST_ASSERT_EQUAL(gun.size_set_to, 1.5, "the size is set")
	TEST_ASSERT(!prompt.is_open(), "the question is answered")
	TEST_ASSERT(QDELETED(ui) || !SStgui.get_open_ui(H, box), "the window is closed by the submit")
	log_world("TEST sizegun: ui deleted [QDELETED(ui)] status [ui?.status] box deleted [QDELETED(box)]")

/datum/unit_test/dq_hc_tgui/chem_dispensers_start_with_full_cartridges

/datum/unit_test/dq_hc_tgui/chem_dispensers_start_with_full_cartridges/run_gate()
	var/mob/living/carbon/human/H = hct_actor()
	var/checked = 0
	for(var/type in subtypesof(/obj/machinery/chemical_dispenser))
		var/obj/machinery/chemical_dispenser/proto = type
		if(!initial(proto.spawn_cartridges))
			continue
		var/obj/machinery/chemical_dispenser/D = allocate(type, hct_spot())
		for(var/label in D.cartridges)
			var/obj/item/reagent_containers/chem_disp_cartridge/C = D.cartridges[label]
			TEST_ASSERT(abs(C.reagents.total_volume - CARTRIDGE_VOLUME_LARGE) < 0.01, "[type] starts with [label] at [C.reagents.total_volume]u, not [CARTRIDGE_VOLUME_LARGE]u")
			checked++
		var/list/data = data_of(D, H)
		for(var/list/row in data["chemicals"])
			TEST_ASSERT(abs(row["volume"] - CARTRIDGE_VOLUME_LARGE) < 0.01, "[type] shows [row["name"]] as [row["volume"]]u in its grid")
	TEST_ASSERT(checked > 20, "the dispenser presets were checked ([checked] cartridges)")
