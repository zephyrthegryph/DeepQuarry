// Wave 4 of the window conversions: the cyborg's own window, the AI law
// manager, the UAV controller, the stock exchange, the prisoner management console, the medical records console, the pipe dispenser and the ghost
// spawn menu send their rows by handle (ref_token()) and take them back only from the lists they show. Every window is checked through the real
// tgui state with a person who has a client-like transport (a clientless mob is closed out by the state and can fail nothing), every handle that is
// not one of the window's own is refused, and no button changes what a clientless or distant person could not already do.

/// A ghost who stands in for one with a client: the real tgui state checks run, only the "no client" close is skipped.
/mob/observer/dead/dq_topic4_ghost

/mob/observer/dead/dq_topic4_ghost/shared_tgui_interaction(src_object)
	if(stat)
		return STATUS_DISABLED
	return STATUS_INTERACTIVE

/// A cyborg who stands in for one with a client: the real tgui state checks run, only the "no client" close is skipped.
/mob/living/silicon/robot/dq_topic4_cyborg

/mob/living/silicon/robot/dq_topic4_cyborg/shared_tgui_interaction(src_object)
	if(stat)
		return STATUS_DISABLED
	return STATUS_INTERACTIVE

/// The cyborg's window: its module's tools by handle, only the ones the window lists (the emag tools only while it shows them).
/datum/unit_test/dq_topic4_robot_window

/datum/unit_test/dq_topic4_robot_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/mob/living/silicon/robot/dq_topic4_cyborg/R = allocate(/mob/living/silicon/robot/dq_topic4_cyborg, get_step(T, EAST))
	if(!R.module)
		rel_set(R, nameof(R.module), new /obj/item/robot_module/robot/standard(R))
	var/datum/tgui_module/robot_ui/window = allocate(/datum/tgui_module/robot_ui, R)
	TEST_ASSERT_EQUAL(window.tgui_status(R, window.tgui_state(R)), STATUS_INTERACTIVE, "the cyborg works its own window")
	TEST_ASSERT_EQUAL(window.tgui_status(user, window.tgui_state(user)), STATUS_CLOSE, "a person standing next to it does not")
	TEST_ASSERT_EQUAL(window.tgui_status(clientless, window.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/obj/item/tool = null
	for(var/obj/item/I in R.module.modules)
		tool = I
		break
	TEST_ASSERT_NOTNULL(tool, "the standard module has tools")
	var/obj/item/tool/crowbar/emag_tool = allocate(/obj/item/tool/crowbar, R.module)
	rel_add(R.module, nameof(R.module.emag), emag_tool)
	var/obj/item/tool/crowbar/stray = allocate(/obj/item/tool/crowbar, T)
	// the readouts: the module's tools by handle, in both the static and the live data
	var/list/static_data = window.tgui_static_data(R)
	var/listed_static = FALSE
	for(var/list/row in static_data["modules_static"])
		if(row["ref"] == ref_token(tool))
			listed_static = TRUE
		TEST_ASSERT(row["ref"] != ref_token(emag_tool), "the emag tool is not listed before the cyborg is emagged")
	TEST_ASSERT(listed_static, "the static data names the tool by handle")
	var/list/data = hc_data(window, R)
	TEST_ASSERT(ref_token(tool) in data["modules"], "the live data keys the tool by handle")
	TEST_ASSERT(!(ref_token(emag_tool) in data["emag_modules"]), "and lists no emag tool before the cyborg is emagged")
	// toggling: a listed tool is taken up, anything else is not
	own(test_ui(R, window, "toggle_module", list("ref" = ref_token(stray))))
	TEST_ASSERT(!R.activated(stray), "a tool that is in no module cannot be taken up")
	own(test_ui(R, window, "toggle_module", list("ref" = "not a handle")))
	TEST_ASSERT(!R.activated(tool), "nor can a made-up name")
	own(test_ui(R, window, "toggle_module", list("ref" = ref_token(emag_tool))))
	TEST_ASSERT(!R.activated(emag_tool), "an emag tool cannot while the cyborg is not emagged")
	own(test_ui(R, window, "toggle_module", list("ref" = ref_token(tool))))
	TEST_ASSERT(R.activated(tool), "the listed tool's handle takes it up")
	own(test_ui(R, window, "toggle_module", list("ref" = ref_token(tool))))
	TEST_ASSERT(!R.activated(tool), "and puts it back")
	R.set_emagged(TRUE)
	data = hc_data(window, R)
	TEST_ASSERT(ref_token(emag_tool) in data["emag_modules"], "an emagged cyborg lists its emag tool by handle")
	own(test_ui(R, window, "toggle_module", list("ref" = ref_token(emag_tool))))
	TEST_ASSERT(R.activated(emag_tool), "and the handle takes it up")

/// The AI law manager: laws and law sets by handle, only the owner's laws and the sets the window lists.
/datum/unit_test/dq_topic4_law_manager_window

/datum/unit_test/dq_topic4_law_manager_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, get_step(T, SOUTH))
	var/obj/item/paper/host = allocate(/obj/item/paper, get_step(T, EAST))
	var/datum/tgui_module/law_manager/window = allocate(/datum/tgui_module/law_manager, R)
	rel_set(window, nameof(/datum/tgui_module::host), host)
	TEST_ASSERT_EQUAL(window.tgui_status(user, window.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the window works it")
	TEST_ASSERT_EQUAL(window.tgui_status(clientless, window.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	R.laws.add_ion_law("Dq topic four first law")
	R.laws.add_ion_law("Dq topic four second law")
	var/datum/ai_law/first = R.laws.ion_laws[length(R.laws.ion_laws) - 1]
	var/datum/ai_law/second = R.laws.ion_laws[length(R.laws.ion_laws)]
	var/datum/ai_law/stray = allocate(/datum/ai_law/ion, "Dq topic four stray law")
	// the readouts
	var/list/data = hc_data(window, user)
	var/found_first = FALSE
	for(var/list/row in data["ion_laws"])
		if(row["ref"] == ref_token(first))
			found_first = TRUE
			TEST_ASSERT_EQUAL(row["law"], first.law, "the law is listed with its text")
	TEST_ASSERT(found_first, "the window names the law by handle")
	TEST_ASSERT(length(data["law_sets"]) > 0, "the window lists the law sets")
	for(var/list/row in data["law_sets"])
		TEST_ASSERT(istext(row["ref"]), "a law set is named by a handle")
	// stating: anybody at the window switches a law of the owner's; another law is not the owner's
	var/stated_first = R.laws.get_state_law(first)
	var/stated_second = R.laws.get_state_law(second)
	own(test_ui(user, window, "state_law", list("ref" = ref_token(stray), "state_law" = 1)))
	TEST_ASSERT_EQUAL(R.laws.get_state_law(first), stated_first, "a law that is not the owner's changes nothing")
	own(test_ui(user, window, "state_law", list("ref" = "not a handle", "state_law" = 1)))
	TEST_ASSERT_EQUAL(R.laws.get_state_law(first), stated_first, "nor does a made-up name")
	own(test_ui(user, window, "state_law", list("ref" = ref_token(second), "state_law" = !stated_second)))
	TEST_ASSERT_EQUAL(R.laws.get_state_law(second), !stated_second, "the law's handle switches it")
	TEST_ASSERT_EQUAL(R.laws.get_state_law(first), stated_first, "and only that one")
	// a person who is not an antagonist deletes and edits nothing
	var/ions = length(R.laws.ion_laws)
	own(test_ui(user, window, "delete_law", list("delete_law" = ref_token(second))))
	TEST_ASSERT_EQUAL(length(R.laws.ion_laws), ions, "a person who is not an antagonist deletes no law")
	var/datum/op_result/edit = test_ui(user, window, "edit_law", list("edit_law" = ref_token(second)))
	TEST_ASSERT_NULL(SSrequests.open_for(user), "and is not asked for a new text")
	own(edit)

/// The UAV controller: the computer's own paired vehicles by handle.
/datum/unit_test/dq_topic4_uav_window

/datum/unit_test/dq_topic4_uav_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/item/modular_computer/laptop/laptop = allocate(/obj/item/modular_computer/laptop, get_step(T, EAST))
	var/datum/tgui_module/uav/window = allocate(/datum/tgui_module/uav, laptop)
	TEST_ASSERT_EQUAL(window.tgui_status(user, window.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the computer works its window")
	TEST_ASSERT_EQUAL(window.tgui_status(clientless, window.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/obj/item/uav/paired = allocate(/obj/item/uav, get_step(T, NORTH))
	var/obj/item/uav/stranger = allocate(/obj/item/uav, get_step(T, NORTH))
	rel_add(laptop, nameof(/obj/item/modular_computer::paired_uavs), paired)
	var/list/data = hc_data(window, user)
	TEST_ASSERT_EQUAL(length(data["paired_uavs"]), 1, "the window lists the one paired vehicle")
	TEST_ASSERT_EQUAL(data["paired_uavs"][1]["uavref"], ref_token(paired), "by handle")
	TEST_ASSERT_EQUAL(data["paired_uavs"][1]["name"], "[paired.nickname]", "with its name")
	// switching: a vehicle this computer is paired with, nothing else
	own(test_ui(user, window, "switch_uav", list("switch_uav" = ref_token(stranger))))
	TEST_ASSERT_NULL(window.current_uav(), "a vehicle this computer is not paired with is not watched")
	own(test_ui(user, window, "switch_uav", list("switch_uav" = "not a handle")))
	TEST_ASSERT_NULL(window.current_uav(), "nor is one by a made-up name")
	own(test_ui(user, window, "switch_uav", list("switch_uav" = ref_token(paired))))
	TEST_ASSERT_EQUAL(window.current_uav(), paired, "the paired vehicle's handle watches it")
	// unpairing
	own(test_ui(user, window, "del_uav", list("del_uav" = ref_token(stranger))))
	TEST_ASSERT(paired in laptop.paired_uavs, "unpairing a vehicle that was never paired changes nothing")
	own(test_ui(user, window, "del_uav", list("del_uav" = ref_token(paired))))
	TEST_ASSERT(!(paired in laptop.paired_uavs), "the paired vehicle's handle unpairs it")
	TEST_ASSERT_NULL(window.current_uav(), "and stops watching it")

/// The stock exchange: stocks by handle, only the ones the exchange lists.
/datum/unit_test/dq_topic4_stock_exchange_window

/datum/unit_test/dq_topic4_stock_exchange_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/computer/stockexchange/console = allocate(/obj/machinery/computer/stockexchange, get_step(T, EAST))
	console.set_grid_power(TRUE)
	TEST_ASSERT_EQUAL(console.tgui_status(user, console.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the console works its window")
	TEST_ASSERT_EQUAL(console.tgui_status(clientless, console.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	TEST_ASSERT(length(GLOB.stockExchange.stocks), "the exchange has stocks")
	var/datum/stock/listed = GLOB.stockExchange.stocks[1]
	var/datum/stock/stray = allocate(/datum/stock)
	var/list/data = hc_data(console, user)
	var/found = FALSE
	for(var/list/row in data["stocks"])
		if(row["REF"] == ref_token(listed))
			found = TRUE
			TEST_ASSERT_EQUAL(row["ID"], listed.short_name, "the stock is listed with its short name")
	TEST_ASSERT(found, "the window names the stock by handle")
	own(test_ui(user, console, "stocks_archive", list("share" = ref_token(stray))))
	TEST_ASSERT_NULL(console.current_stock(), "a stock the exchange does not list is not opened")
	own(test_ui(user, console, "stocks_archive", list("share" = "not a handle")))
	TEST_ASSERT_NULL(console.current_stock(), "nor is one by a made-up name")
	own(test_ui(user, console, "stocks_archive", list("share" = ref_token(listed))))
	TEST_ASSERT_EQUAL(console.current_stock(), listed, "a listed stock's handle opens its archive")
	TEST_ASSERT_EQUAL(console.screen, "archive", "on the archive screen")
	own(test_ui(user, console, "stocks_backbutton"))
	TEST_ASSERT_NULL(console.current_stock(), "the back button closes it")
	// trading a stock that is not listed asks nothing; with no account the listed one asks nothing either, so the refusal is the handle's alone
	own(test_ui(user, console, "stocks_buy", list("share" = ref_token(stray))))
	TEST_ASSERT_NULL(SSrequests.open_for(user), "buying a stock the exchange does not list asks nothing")
	own(test_ui(user, console, "stocks_sell", list("share" = ref_token(stray))))
	TEST_ASSERT_NULL(SSrequests.open_for(user), "nor does selling one")

/// The prisoner management console: implants by handle, only while unlocked and only the ones the window lists for each button.
/datum/unit_test/dq_topic4_prisoner_window

/datum/unit_test/dq_topic4_prisoner_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/prisoner = allocate(/mob/living/carbon/human, get_step(T, SOUTH))
	var/obj/machinery/computer/prisoner/console = allocate(/obj/machinery/computer/prisoner, get_step(T, EAST))
	console.set_grid_power(TRUE)
	TEST_ASSERT_EQUAL(console.tgui_status(user, console.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the console works its window")
	TEST_ASSERT_EQUAL(console.tgui_status(clientless, console.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/obj/item/implant/chem/chem = allocate(/obj/item/implant/chem, T)
	TEST_ASSERT(chem.handle_implant(prisoner), "the chemical implant is embedded")
	chem.reagents.add_reagent(REAGENT_ID_INAPROVALINE, 20)
	var/obj/item/implant/chem/loose_chem = allocate(/obj/item/implant/chem, T)
	loose_chem.reagents.add_reagent(REAGENT_ID_INAPROVALINE, 20)
	var/obj/item/implant/tracking/tracker = allocate(/obj/item/implant/tracking, T)
	TEST_ASSERT(tracker.handle_implant(prisoner), "the tracking implant is embedded")
	// locked: the window lists nothing and no button reaches an implant
	TEST_ASSERT(hc_data(console, user)["locked"], "the console starts locked")
	TEST_ASSERT_EQUAL(length(hc_data(console, user)["chemImplants"]), 0, "a locked console lists no implant")
	var/volume = chem.reagents.total_volume
	own(test_ui(user, console, "inject", list("imp" = ref_token(chem), "val" = 5)))
	TEST_ASSERT_EQUAL(chem.reagents.total_volume, volume, "a locked console injects nothing")
	// unlocked
	console.set_screen(1)
	var/list/data = hc_data(console, user)
	var/found_chem = FALSE
	for(var/list/row in data["chemImplants"])
		if(row["ref"] == ref_token(chem))
			found_chem = TRUE
		TEST_ASSERT(row["ref"] != ref_token(loose_chem), "an implant that is in nobody is not listed")
	TEST_ASSERT(found_chem, "the window names the chemical implant by handle")
	var/found_tracker = FALSE
	for(var/list/row in data["trackImplants"])
		if(row["ref"] == ref_token(tracker))
			found_tracker = TRUE
	TEST_ASSERT(found_tracker, "and the tracking implant")
	own(test_ui(user, console, "inject", list("imp" = ref_token(loose_chem), "val" = 5)))
	TEST_ASSERT_EQUAL(loose_chem.reagents.total_volume, 20, "an implant in nobody is not injected")
	own(test_ui(user, console, "inject", list("imp" = ref_token(tracker), "val" = 5)))
	TEST_ASSERT_EQUAL(chem.reagents.total_volume, volume, "a tracking implant is not a chemical one")
	own(test_ui(user, console, "inject", list("imp" = "not a handle", "val" = 5)))
	TEST_ASSERT_EQUAL(chem.reagents.total_volume, volume, "nor is a made-up name")
	own(test_ui(user, console, "inject", list("imp" = ref_token(chem), "val" = 5)))
	TEST_ASSERT_EQUAL(chem.reagents.total_volume, volume - 5, "the listed implant's handle injects what was asked")
	// warning: only a tracked prisoner can be spoken to
	TEST_ASSERT(!(chem in console.listed_tracking_implants()), "a chemical implant is not one to warn through")
	own(test_ui(user, console, "warn", list("imp" = "not a handle")))
	test_answer(user, "stay calm")
	own(test_ui(user, console, "warn", list("imp" = ref_token(tracker))))
	TEST_ASSERT(istype(SSrequests.open_for(user), /datum/prompt/text), "the tracking implant's handle asks what to say")
	test_answer(user, null, REQ_CANCELLED)

/// The medical records console: records and viruses by handle, only the ones the window lists, and only to a person who is logged in.
/datum/unit_test/dq_topic4_medical_records_window

/datum/unit_test/dq_topic4_medical_records_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/computer/med_data/console = allocate(/obj/machinery/computer/med_data, get_step(T, EAST))
	console.set_grid_power(TRUE)
	console.set_broken_condition(FALSE)
	TEST_ASSERT_EQUAL(console.tgui_status(user, console.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the console works its window")
	TEST_ASSERT_EQUAL(console.tgui_status(clientless, console.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/datum/data/record/listed = GLOB.data_core.CreateGeneralRecord(null, "4TOP")
	listed.set_fields_at("name", "Dq Topic Four")
	var/datum/data/record/stray = new
	stray.set_fields_at("name", "Dq Topic Stray")
	var/list/saved_viruses = GLOB.virusDB
	GLOB.virusDB = list()
	var/datum/data/record/virus = new
	virus.set_fields_at("name", "Dq Topic Plague")
	virus.set_fields_at("tgui_description", "dq topic four description")
	GLOB.virusDB["4001"] = virus
	// logged out: no button reaches a record
	own(test_ui(user, console, "d_rec", list("d_rec" = ref_token(listed))))
	TEST_ASSERT_NULL(console.active1(), "a person who is not logged in opens no record")
	console.set_authenticated("Dq Topic")
	console.set_screen(2) // the record list (MED_DATA_R_LIST, which medical.dm keeps to itself)
	var/list/data = hc_data(console, user)
	var/found = FALSE
	for(var/list/row in data["records"])
		if(row["ref"] == ref_token(listed))
			found = TRUE
			TEST_ASSERT_EQUAL(row["id"], "4TOP", "the record is listed with its id")
			TEST_ASSERT_EQUAL(row["name"], "Dq Topic Four", "and its name")
	TEST_ASSERT(found, "the window names the record by handle")
	own(test_ui(user, console, "d_rec", list("d_rec" = ref_token(stray))))
	TEST_ASSERT_NULL(console.active1(), "a record that is not in the data core is not opened")
	own(test_ui(user, console, "d_rec", list("d_rec" = "not a handle")))
	TEST_ASSERT_NULL(console.active1(), "nor is a made-up name")
	own(test_ui(user, console, "d_rec", list("d_rec" = ref_token(virus))))
	TEST_ASSERT_NULL(console.active1(), "a virus record is not a general record")
	own(test_ui(user, console, "d_rec", list("d_rec" = ref_token(listed))))
	TEST_ASSERT_EQUAL(console.active1(), listed, "a listed record's handle opens it")
	// viruses
	var/list/entries = medical_virus_entries()
	TEST_ASSERT_EQUAL(entries[1]["D"], ref_token(virus), "the virus list names the virus by handle")
	own(test_ui(user, console, "vir", list("vir" = ref_token(stray))))
	TEST_ASSERT_NULL(hc_data(console, user)["modal"], "a record that is not a listed virus opens no description")
	own(test_ui(user, console, "vir", list("vir" = ref_token(virus))))
	TEST_ASSERT_NOTNULL(hc_data(console, user)["modal"], "a listed virus's handle opens its description")
	GLOB.virusDB = saved_viruses
	qdel(listed)
	qdel(stray)
	qdel(virus)

/// The pipe dispenser: recipes by handle, only the ones of its own kind.
/datum/unit_test/dq_topic4_pipe_dispenser_window

/datum/unit_test/dq_topic4_pipe_dispenser_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/turf/spot = get_step(T, EAST)
	var/obj/machinery/pipedispenser/dispenser = allocate(/obj/machinery/pipedispenser, spot)
	TEST_ASSERT_EQUAL(dispenser.tgui_status(user, dispenser.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the dispenser works its window")
	TEST_ASSERT_EQUAL(dispenser.tgui_status(clientless, dispenser.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/list/atmos_category = GLOB.atmos_pipe_recipes[GLOB.atmos_pipe_recipes[1]]
	var/datum/pipe_recipe/recipe = atmos_category[1]
	var/list/disposal_category = GLOB.disposal_pipe_recipes[GLOB.disposal_pipe_recipes[1]]
	var/datum/pipe_recipe/disposal_recipe = disposal_category[1]
	var/list/data = hc_data(dispenser, user)
	var/found = FALSE
	var/found_disposal = FALSE
	for(var/list/category in data["categories"])
		for(var/list/row in category["recipes"])
			if(row["ref"] == ref_token(recipe))
				found = TRUE
			if(row["ref"] == ref_token(disposal_recipe))
				found_disposal = TRUE
	TEST_ASSERT(found, "the window names the recipe by handle")
	TEST_ASSERT(!found_disposal, "and lists no disposal recipe")
	own(test_ui(user, dispenser, "dispense_pipe", list("ref" = ref_token(disposal_recipe))))
	TEST_ASSERT_NULL(locate(/obj/structure/disposalconstruct) in spot, "a disposal recipe makes nothing at an atmospherics dispenser")
	TEST_ASSERT_NULL(locate(/obj/item/pipe) in spot, "and no pipe")
	own(test_ui(user, dispenser, "dispense_pipe", list("ref" = "not a handle")))
	TEST_ASSERT_NULL(locate(/obj/item/pipe) in spot, "nor does a made-up name")
	own(test_ui(user, dispenser, "dispense_pipe", list("ref" = ref_token(recipe))))
	TEST_ASSERT_NOTNULL(locate(/obj/item/pipe) in spot, "a listed recipe's handle dispenses its pipe")
	for(var/obj/item/pipe/made in spot)
		qdel(made)

/// The ghost spawn menu: pods by handle, only the ones the registry lists.
/datum/unit_test/dq_topic4_ghost_spawn_window

/datum/unit_test/dq_topic4_ghost_spawn_window/Run()
	var/turf/T = test_floor()
	var/mob/observer/dead/dq_topic4_ghost/ghost = allocate(/mob/observer/dead/dq_topic4_ghost, T)
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/turf/pod_spot = get_step(T, EAST)
	var/obj/structure/ghost_pod/manual/pod = allocate(/obj/structure/ghost_pod/manual, pod_spot)
	var/obj/structure/closet/crate/stray = allocate(/obj/structure/closet/crate, get_step(T, NORTH))
	registry_join(REGISTRY_GHOST_PODS, pod) // a pod joins the registry when it is activated for ghosts
	var/datum/tgui_module/ghost_spawn_menu/window = allocate(/datum/tgui_module/ghost_spawn_menu)
	TEST_ASSERT_EQUAL(window.tgui_status(ghost, window.tgui_state(ghost)), STATUS_INTERACTIVE, "a ghost works the window")
	TEST_ASSERT_EQUAL(window.tgui_status(clientless, window.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/list/data = hc_data(window, ghost)
	var/found = FALSE
	for(var/list/row in data["all_ghost_pods"])
		if(row["ref"] == ref_token(pod))
			found = TRUE
	TEST_ASSERT(found, "the window names the pod by handle")
	own(test_ui(ghost, window, "select_pod", list("selected_pod" = ref_token(stray))))
	TEST_ASSERT(get_turf(ghost) != pod_spot, "a thing that is not a pod does not take the ghost anywhere")
	own(test_ui(ghost, window, "select_pod", list("selected_pod" = "not a handle")))
	TEST_ASSERT(get_turf(ghost) != pod_spot, "nor does a made-up name")
	own(test_ui(ghost, window, "select_pod", list("selected_pod" = ref_token(pod))))
	TEST_ASSERT_EQUAL(get_turf(ghost), pod_spot, "the pod's handle takes the ghost to it")
	registry_leave(REGISTRY_GHOST_PODS, pod)
