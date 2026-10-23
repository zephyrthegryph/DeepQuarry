// Wave 3 of the window conversions: the resleeving console, the supply console, the message monitor, the telecommunications machines, the ship
// engines console and the research server control send their rows by handle (ref_token()) and take them back by it. Every window here is checked
// through the real tgui state with a person who has a client-like transport (a clientless mob is closed out by the state and can fail nothing),
// every handle that is not one of the window's own is refused, and no button changes what a clientless or distant person could not already do.

/// The resleeving console's window: pods, printers, booths and records by handle, and nothing outside its own lists.
/datum/unit_test/dq_topic3_resleeving_window

/datum/unit_test/dq_topic3_resleeving_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/computer/transhuman/resleeving/console = allocate(/obj/machinery/computer/transhuman/resleeving, get_step(T, EAST))
	console.set_grid_power(TRUE)
	var/obj/machinery/transhuman/synthprinter/printer = allocate(/obj/machinery/transhuman/synthprinter, get_step(console, NORTH))
	var/obj/machinery/transhuman/resleever/booth = allocate(/obj/machinery/transhuman/resleever, get_step(console, SOUTH))
	var/obj/machinery/clonepod/transhuman/pod = allocate(/obj/machinery/clonepod/transhuman, get_step(console, EAST))
	console.updatemodules()
	TEST_ASSERT_EQUAL(pod.resleeving_console, console, "the area search links the growpod to the console")
	TEST_ASSERT(pod in console.pods, "the console has its pod")
	TEST_ASSERT(printer in console.spods, "the console finds its printer")
	TEST_ASSERT(booth in console.sleevers, "the console finds its booth")
	// the window's state: a person with a screen works it, one with none is closed out
	TEST_ASSERT_EQUAL(console.tgui_status(user, console.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the console works its window")
	TEST_ASSERT_EQUAL(console.tgui_status(clientless, console.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	// the readouts: every machine, the selection and the records by handle
	var/mob/living/carbon/human/subject = allocate(/mob/living/carbon/human, get_step(T, SOUTH))
	var/datum/transhuman/body_record/listed_body = new
	listed_body.init_from_mob(subject)
	rel_add(console.our_db(), nameof(/datum/transcore_db::body_scans), listed_body, "dq_topic3_body")
	var/datum/transhuman/body_record/foreign_body = new
	foreign_body.init_from_mob(subject)
	var/datum/mind/source_mind = allocate(/datum/mind, "dq-topic3-resleeving")
	source_mind.set_name("dq-topic3-resleeving") // the database lists records by their mind's name
	TEST_ASSERT(transfer_mind(source_mind, subject, "wave 3 fixture"), "the mind goes into the body")
	var/datum/transhuman/mind_record/listed_mind = new /datum/transhuman/mind_record(source_mind, subject, TRUE)
	var/datum/mind/other_mind = allocate(/datum/mind, "dq-topic3-other")
	other_mind.set_name("dq-topic3-other")
	var/datum/transhuman/mind_record/foreign_mind = allocate(/datum/transhuman/mind_record, other_mind, subject, FALSE) // not in the database
	var/list/data = hc_data(console, user)
	TEST_ASSERT_EQUAL(data["pods"][1]["pod"], ref_token(pod), "the window names the pod by handle")
	TEST_ASSERT_EQUAL(data["spods"][1]["spod"], ref_token(printer), "the printer")
	TEST_ASSERT_EQUAL(data["sleevers"][1]["sleever"], ref_token(booth), "the booth")
	var/body_row_found = FALSE
	for(var/list/row in data["bodyrecords"])
		if(row["recref"] == ref_token(listed_body))
			body_row_found = TRUE
	TEST_ASSERT(body_row_found, "a body record")
	var/mind_row_found = FALSE
	for(var/list/row in data["mindrecords"])
		if(row["recref"] == ref_token(listed_mind))
			mind_row_found = TRUE
	TEST_ASSERT(mind_row_found, "a mind record")
	// selecting: a handle of the console's own machine selects it, anything else does nothing
	own(test_ui(user, console, "selectpod", list("ref" = "not a handle")))
	own(test_ui(user, console, "selectpod", list("ref" = ref_token(printer))))
	TEST_ASSERT(console.selected_pod != printer, "a machine of another kind cannot be selected as a pod")
	own(test_ui(user, console, "selectpod", list("ref" = ref_token(pod))))
	TEST_ASSERT_EQUAL(console.selected_pod, pod, "the pod's handle selects it")
	TEST_ASSERT_EQUAL(hc_data(console, user)["selected_pod"], ref_token(pod), "and the window says which")
	var/obj/machinery/clonepod/transhuman/stray_pod = allocate(/obj/machinery/clonepod/transhuman, get_step(T, NORTH))
	own(test_ui(user, console, "selectpod", list("ref" = ref_token(stray_pod))))
	TEST_ASSERT_EQUAL(console.selected_pod, pod, "a pod that is not the console's cannot be selected")
	own(test_ui(user, console, "selectprinter", list("ref" = ref_token(printer))))
	TEST_ASSERT_EQUAL(console.selected_printer, printer, "the printer's handle selects it")
	var/obj/machinery/transhuman/synthprinter/stray_printer = allocate(/obj/machinery/transhuman/synthprinter, get_step(T, NORTH))
	own(test_ui(user, console, "selectprinter", list("ref" = ref_token(stray_printer))))
	TEST_ASSERT_EQUAL(console.selected_printer, printer, "a printer that is not the console's cannot be selected")
	own(test_ui(user, console, "selectsleever", list("ref" = ref_token(booth))))
	TEST_ASSERT_EQUAL(console.selected_sleever, booth, "the booth's handle selects it")
	var/obj/machinery/transhuman/resleever/stray_booth = allocate(/obj/machinery/transhuman/resleever, get_step(T, NORTH))
	own(test_ui(user, console, "selectsleever", list("ref" = ref_token(stray_booth))))
	TEST_ASSERT_EQUAL(console.selected_sleever, booth, "a booth that is not the console's cannot be selected")
	// records: the ones the window lists open, others do not
	own(test_ui(user, console, "view_b_rec", list("ref" = ref_token(foreign_body))))
	TEST_ASSERT_NULL(console.current_br, "a body record the window does not list cannot be opened")
	own(test_ui(user, console, "view_b_rec", list("ref" = "not a handle")))
	TEST_ASSERT_NULL(console.current_br, "nor can a made-up name")
	own(test_ui(user, console, "view_b_rec", list("ref" = ref_token(listed_body))))
	TEST_ASSERT_EQUAL(console.current_br, listed_body, "a listed body record opens")
	TEST_ASSERT_EQUAL(hc_data(console, user)["active_b_rec"]["activerecord"], ref_token(listed_body), "and the window names it by handle")
	own(test_ui(user, console, "clear_b_rec"))
	TEST_ASSERT_NULL(console.current_br, "the close button clears it")
	own(test_ui(user, console, "view_m_rec", list("ref" = ref_token(foreign_mind))))
	TEST_ASSERT_NULL(console.current_mr, "a mind record the window does not list cannot be opened")
	own(test_ui(user, console, "view_m_rec", list("ref" = ref_token(listed_mind))))
	TEST_ASSERT_EQUAL(console.current_mr, listed_mind, "a listed mind record opens")
	TEST_ASSERT_EQUAL(hc_data(console, user)["active_m_rec"]["activerecord"], ref_token(listed_mind), "and the window names it by handle")
	// a record handed to the console on a disk is the one it already has loaded, and opens
	own(test_ui(user, console, "clear_m_rec"))
	rel_set(console, nameof(/obj/machinery/computer/transhuman/resleeving::current_br), foreign_body)
	own(test_ui(user, console, "view_b_rec", list("ref" = ref_token(foreign_body))))
	TEST_ASSERT_EQUAL(console.current_br, foreign_body, "the record loaded from a disk opens again by its handle")
	qdel(listed_mind)
	rel_remove(console.our_db(), nameof(/datum/transcore_db::body_scans), listed_body)

/// The supply console: orders, receipts and packs by handle, taken back only from the live lists.
/datum/unit_test/dq_topic3_supply_window

/datum/unit_test/dq_topic3_supply_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/computer/supplycomp/control/console = allocate(/obj/machinery/computer/supplycomp/control, get_step(T, EAST))
	console.set_grid_power(TRUE)
	TEST_ASSERT_EQUAL(console.tgui_status(user, console.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the console works its window")
	TEST_ASSERT_EQUAL(console.tgui_status(clientless, console.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/list/names = SSsupply.catalog_names()
	TEST_ASSERT(length(names), "the supply catalog has packs")
	var/datum/supply_pack/pack = SSsupply.catalog_pack(names[1])
	var/datum/supply_order/listed = allocate(/datum/supply_order)
	listed.supply_pack_static = pack
	var/datum/supply_order/foreign = allocate(/datum/supply_order)
	foreign.supply_pack_static = pack
	var/datum/exported_crate/receipt = allocate(/datum/exported_crate)
	var/datum/exported_crate/foreign_receipt = allocate(/datum/exported_crate)
	rel_add(SSsupply, nameof(/datum/system/supply::order_history), listed)
	rel_add(SSsupply, nameof(/datum/system/supply::exported_crates), receipt)
	var/list/data = hc_data(console, user)
	var/list/order_tokens = list()
	for(var/list/row in data["orders"])
		order_tokens += row["ref"]
	TEST_ASSERT(ref_token(listed) in order_tokens, "the window names the order by handle")
	var/list/receipt_tokens = list()
	for(var/list/row in data["receipts"])
		receipt_tokens += row["ref"]
	TEST_ASSERT(ref_token(receipt) in receipt_tokens, "and the receipt")
	var/list/static_data = console.tgui_static_data(user)
	var/found_pack = FALSE
	for(var/list/row in static_data["supply_packs"])
		if(row["ref"] == ref_token(pack))
			found_pack = TRUE
	TEST_ASSERT(found_pack, "and the packs")
	// resolving: only what the live lists and the catalog hold
	TEST_ASSERT_EQUAL(SSsupply.order_from_ref(ref_token(listed)), listed, "an order in the history is named by its handle")
	TEST_ASSERT_NULL(SSsupply.order_from_ref(ref_token(foreign)), "an order outside the history is not")
	TEST_ASSERT_NULL(SSsupply.order_from_ref(ref_token(receipt)), "a receipt is not an order")
	TEST_ASSERT_EQUAL(SSsupply.export_from_ref(ref_token(receipt)), receipt, "a receipt in the history is named by its handle")
	TEST_ASSERT_NULL(SSsupply.export_from_ref(ref_token(foreign_receipt)), "a receipt outside the history is not")
	TEST_ASSERT_EQUAL(SSsupply.pack_from_ref(ref_token(pack)), pack, "a catalog pack is named by its handle")
	TEST_ASSERT_NULL(SSsupply.pack_from_ref(ref_token(listed)), "an order is not a pack")
	TEST_ASSERT_NULL(SSsupply.pack_from_ref("not a handle"), "a made-up name is none")
	// the buttons: a listed order or receipt starts its deletion question, a foreign one starts none
	// (the console's dispatcher needs the cargo shuttle, which the test map lacks: the buttons' handlers are called as the dispatcher would)
	console.act_delete_order(user, ref_token(foreign))
	TEST_ASSERT_NULL(SSrequests.open_for(user), "deleting an order outside the history asks nothing")
	console.act_delete_order(user, ref_token(listed))
	TEST_ASSERT(istype(SSrequests.open_for(user), /datum/prompt/yes_no/supply_delete_record), "deleting a listed order asks first")
	test_answer(user, null, REQ_CANCELLED)
	console.act_export_delete(user, ref_token(foreign_receipt))
	TEST_ASSERT_NULL(SSrequests.open_for(user), "deleting a receipt outside the history asks nothing")
	console.act_export_delete(user, ref_token(receipt))
	TEST_ASSERT(istype(SSrequests.open_for(user), /datum/prompt/yes_no/supply_delete_record), "deleting a listed receipt asks first")
	test_answer(user, null, REQ_CANCELLED)
	rel_remove(SSsupply, nameof(/datum/system/supply::order_history), listed)
	rel_remove(SSsupply, nameof(/datum/system/supply::exported_crates), receipt)

/// The message monitor: logs and recipients by handle; a log of another server and a PDA that is not in the registry are not named.
/datum/unit_test/dq_topic3_message_monitor_window

/datum/unit_test/dq_topic3_message_monitor_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(transfer_mind(allocate(/datum/mind, "dq-topic3-monitor-user"), user, "wave 3 fixture"), "the user has a mind, as every person at the monitor does")
	var/obj/machinery/message_server/server = allocate(/obj/machinery/message_server, get_step(T, NORTH))
	server.set_grid_power(TRUE)
	server.set_broken_condition(FALSE)
	server.set_decryptkey("sesame")
	var/obj/machinery/message_server/other_server = allocate(/obj/machinery/message_server, get_step(T, SOUTH))
	var/obj/machinery/computer/message_monitor/console = allocate(/obj/machinery/computer/message_monitor, get_step(T, EAST))
	console.set_grid_power(TRUE)
	console.set_broken_condition(FALSE)
	rel_set(console, nameof(/obj/machinery/computer/message_monitor::linkedServer), server)
	TEST_ASSERT_EQUAL(console.tgui_status(user, console.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the monitor works its window")
	TEST_ASSERT_EQUAL(console.tgui_status(clientless, console.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	// without the key the logs are not shown and not deletable
	server.send_pda_message("recipient", "sender", "message one")
	server.send_pda_message("recipient", "sender", "message two")
	other_server.send_pda_message("recipient", "elsewhere", "another server's message")
	var/datum/data_pda_msg/mine = server.pda_msgs[length(server.pda_msgs) - 1]
	var/datum/data_pda_msg/theirs = other_server.pda_msgs[length(other_server.pda_msgs)]
	var/mine_count = length(server.pda_msgs)
	var/theirs_count = length(other_server.pda_msgs)
	own(test_ui(user, console, "delete", list("id" = ref_token(mine), "type" = "pda")))
	TEST_ASSERT_EQUAL(length(server.pda_msgs), mine_count, "without the key a log cannot be deleted")
	own(test_ui(user, console, "auth", list("key" = "sesame")))
	TEST_ASSERT(console.auth, "the key authenticates")
	var/list/data = hc_data(console, user)
	TEST_ASSERT_EQUAL(length(data["linkedServer"]["pda_msgs"]), mine_count, "the window lists the server's messages")
	var/list/mine_row
	for(var/list/row in data["linkedServer"]["pda_msgs"])
		if(row["ref"] == ref_token(mine))
			mine_row = row
	TEST_ASSERT_NOTNULL(mine_row, "the message is listed by handle")
	TEST_ASSERT_EQUAL(mine_row["message"], "message one", "with its text")
	own(test_ui(user, console, "delete", list("id" = ref_token(theirs), "type" = "pda")))
	TEST_ASSERT_EQUAL(length(other_server.pda_msgs), theirs_count, "a message of another server cannot be deleted from this one")
	own(test_ui(user, console, "delete", list("id" = "not a handle", "type" = "pda")))
	TEST_ASSERT_EQUAL(length(server.pda_msgs), mine_count, "nor can a made-up name")
	own(test_ui(user, console, "delete", list("id" = ref_token(mine), "type" = "rc")))
	TEST_ASSERT_EQUAL(length(server.pda_msgs), mine_count, "a message is not a request-console log")
	own(test_ui(user, console, "delete", list("id" = ref_token(mine), "type" = "pda")))
	TEST_ASSERT_EQUAL(length(server.pda_msgs), mine_count - 1, "a listed message is deleted")
	TEST_ASSERT(!(mine in server.pda_msgs), "and it is that one")
	// recipients: a PDA in the registry that takes messages is named by handle, anything else is not
	var/obj/item/pda/pda = allocate(/obj/item/pda, T)
	pda.owner = "Dq Topic Three"
	data = hc_data(console, user)
	var/listed_pda = FALSE
	for(var/name in data["possibleRecipients"])
		if(data["possibleRecipients"][name] == ref_token(pda))
			listed_pda = TRUE
	TEST_ASSERT(listed_pda, "a PDA that takes messages is listed by handle")
	own(test_ui(user, console, "set_recipient", list("val" = "not a handle")))
	TEST_ASSERT_NULL(console.customrecepient, "a made-up recipient is none")
	own(test_ui(user, console, "set_recipient", list("val" = ref_token(server))))
	TEST_ASSERT_NULL(console.customrecepient, "a machine is not a recipient")
	own(test_ui(user, console, "set_recipient", list("val" = ref_token(pda))))
	TEST_ASSERT_EQUAL(console.customrecepient, pda, "the PDA's handle picks it")

/// The telecommunications machines' window: the links by handle, the status line says the handle, the machines of other networks are not linked.
/datum/unit_test/dq_topic3_telecomms_window

/datum/unit_test/dq_topic3_telecomms_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/telecomms/bus/bus = allocate(/obj/machinery/telecomms/bus, get_step(T, EAST))
	var/obj/machinery/telecomms/hub/hub = allocate(/obj/machinery/telecomms/hub, get_step(T, NORTH))
	var/obj/item/multitool/tool = allocate(/obj/item/multitool, T)
	user.put_in_active_hand(tool)
	TEST_ASSERT_EQUAL(bus.tgui_status(user, bus.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the machine works its window")
	TEST_ASSERT_EQUAL(bus.tgui_status(clientless, bus.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	// the buffer buttons: store this machine, link the stored one to another
	own(test_ui(user, hub, "buffer"))
	TEST_ASSERT_EQUAL(tool.buffer(), hub, "the buffer button stores the machine in the multitool")
	TEST_ASSERT_EQUAL(hub.temp["text"], "-% Successfully stored [ref_token(hub)] [hub.name] in buffer %-", "and says so with its handle and name")
	own(test_ui(user, bus, "link"))
	TEST_ASSERT(hub in bus.links, "the link button links the stored machine")
	TEST_ASSERT_EQUAL(bus.temp["text"], "-% Successfully linked with [ref_token(hub)] [hub.name] %-", "and says so with its handle and name")
	var/list/data = hc_data(bus, user)
	TEST_ASSERT_EQUAL(length(data["linked"]), 1, "the window lists the link")
	TEST_ASSERT_EQUAL(data["linked"][1]["ref"], ref_token(hub), "by handle")
	TEST_ASSERT_EQUAL(data["linked"][1]["name"], "[hub]", "with its name")
	TEST_ASSERT_EQUAL(data["linked"][1]["id"], hub.id, "and its id")
	own(test_ui(user, bus, "unlink", list("unlink" = 1)))
	TEST_ASSERT(!(hub in bus.links), "the unlink button cuts it")
	TEST_ASSERT_EQUAL(bus.temp["text"], "-% Removed [ref_token(hub)] [hub.name] from linked entities. %-", "and says so with its handle and name")
	// a person without a multitool works none of the settings
	user.drop_item()
	own(test_ui(user, bus, "link"))
	TEST_ASSERT(!(hub in bus.links), "without a multitool the link button does nothing")

/// The ship engines console: engines by handle, only the ones of its own ship.
/datum/unit_test/dq_topic3_engine_control_window

/datum/unit_test/dq_topic3_engine_control_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/computer/ship/engines/console = allocate(/obj/machinery/computer/ship/engines, get_step(T, EAST))
	console.set_grid_power(TRUE)
	TEST_ASSERT_EQUAL(console.tgui_status(user, console.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the console works its window")
	TEST_ASSERT_EQUAL(console.tgui_status(clientless, console.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	// no linked ship: no engine is named by any handle
	var/datum/ship_engine/stray = allocate(/datum/ship_engine)
	TEST_ASSERT_NULL(console.engine_of(ref_token(stray)), "with no ship linked no engine is the console's")
	TEST_ASSERT_NULL(console.engine_of("not a handle"), "a made-up name is none")
	TEST_ASSERT_NULL(console.engine_of(null), "nothing is none")
	// a linked ship: its own engines are named, those of another ship are not
	var/obj/effect/overmap/visitable/ship/ship_a = allocate(/obj/effect/overmap/visitable/ship, T)
	var/obj/effect/overmap/visitable/ship/ship_b = allocate(/obj/effect/overmap/visitable/ship, T)
	var/datum/ship_engine/engine_a = allocate(/datum/ship_engine)
	var/datum/ship_engine/engine_b = allocate(/datum/ship_engine)
	rel_add(ship_a, nameof(/obj/effect/overmap/visitable/ship::engines), engine_a)
	rel_add(ship_b, nameof(/obj/effect/overmap/visitable/ship::engines), engine_b)
	rel_set(console, nameof(/obj/machinery/computer/ship::linked), ship_a)
	TEST_ASSERT_EQUAL(console.engine_of(ref_token(engine_a)), engine_a, "an engine of the linked ship is named by its handle")
	TEST_ASSERT_NULL(console.engine_of(ref_token(engine_b)), "an engine of another ship is not")
	TEST_ASSERT_NULL(console.engine_of(ref_token(stray)), "nor is one of no ship")
	var/list/data = hc_data(console, user)
	TEST_ASSERT_EQUAL(length(data["engines_info"]), 1, "the window lists the ship's engine")
	TEST_ASSERT_EQUAL(data["engines_info"][1]["eng_reference"], ref_token(engine_a), "by handle")
	TEST_ASSERT_EQUAL(data["engines_info"][1]["eng_type"], engine_a.name, "with its name")
	TEST_ASSERT_EQUAL(data["engines_info"][1]["eng_on"], engine_a.is_on(), "and whether it is on")
	// the buttons: the ship's engine works, another ship's is refused
	var/datum/op_result/R = test_ui(user, console, "toggle_engine", list("engine" = ref_token(engine_b)))
	TEST_ASSERT_EQUAL(R?.outcome, ACT_REFUSED, "the toggle button refuses an engine of another ship")
	R = test_ui(user, console, "toggle_engine", list("engine" = "not a handle"))
	TEST_ASSERT_EQUAL(R?.outcome, ACT_REFUSED, "and a made-up name")
	R = test_ui(user, console, "toggle_engine", list("engine" = ref_token(engine_a)))
	TEST_ASSERT(R?.outcome != ACT_REFUSED, "and works the ship's own")
	R = test_ui(user, console, "limit", list("engine" = ref_token(engine_b), "limit" = 0.1))
	TEST_ASSERT_EQUAL(R?.outcome, ACT_REFUSED, "the limit button refuses an engine of another ship")
	R = test_ui(user, console, "set_limit", list("engine" = ref_token(engine_b)))
	TEST_ASSERT_EQUAL(R?.outcome, ACT_REFUSED, "so does the thrust limit question")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "which asks nothing")
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = console
	A.target = console
	A.actor = user
	A.args = list("engine" = ref_token(engine_b))
	TEST_ASSERT_EQUAL(console.engine_named(A), /datum/msg/req_failed, "a button naming an engine that is not the console's is refused")
	A.args = list("engine" = ref_token(engine_a))
	TEST_ASSERT_NULL(console.engine_named(A), "one naming the ship's own is not")
	A.release()

/// The research server control: servers and consoles by handle, only those of its techweb.
/datum/unit_test/dq_topic3_server_control_window

/datum/unit_test/dq_topic3_server_control_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/computer/rdservercontrol/console = allocate(/obj/machinery/computer/rdservercontrol, get_step(T, EAST))
	console.set_grid_power(TRUE)
	TEST_ASSERT_EQUAL(console.tgui_status(user, console.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the console works its window")
	TEST_ASSERT_EQUAL(console.tgui_status(clientless, console.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/datum/techweb/web = console.stored_research()
	TEST_ASSERT_NOTNULL(web, "the console is connected to the station's techweb")
	var/obj/machinery/rnd/server/own_server = allocate(/obj/machinery/rnd/server, get_step(T, NORTH))
	if(!(own_server in web.techweb_servers))
		rel_add(web, nameof(/datum/techweb::techweb_servers), own_server)
	var/obj/machinery/rnd/server/stray_server = allocate(/obj/machinery/rnd/server, get_step(T, SOUTH))
	rel_remove(web, nameof(/datum/techweb::techweb_servers), stray_server) // a server of some other techweb: it joins the station's on creation
	TEST_ASSERT(!(stray_server in web.techweb_servers), "the stray server is not the console's")
	var/list/data = hc_data(console, user)
	var/found = FALSE
	for(var/list/row in data["servers"])
		if(row["server_ref"] == ref_token(own_server))
			found = TRUE
	TEST_ASSERT(found, "the window names the server by handle")
	console.set_emagged(TRUE) // opens the console's own access gate, which a person with no ID cannot pass
	var/disabled = own_server.research_disabled
	var/stray_disabled = stray_server.research_disabled
	own(test_ui(user, console, "lockdown_server", list("selected_server" = ref_token(stray_server))))
	TEST_ASSERT_EQUAL(stray_server.research_disabled, stray_disabled, "a server of no techweb of the console's cannot be locked down")
	own(test_ui(user, console, "lockdown_server", list("selected_server" = "not a handle")))
	TEST_ASSERT_EQUAL(own_server.research_disabled, disabled, "nor can a made-up name")
	own(test_ui(user, console, "lockdown_server", list("selected_server" = ref_token(own_server))))
	TEST_ASSERT(own_server.research_disabled != disabled, "the server's own handle locks it down")

/// A growpod in the console's area links through findpods() and updatemodules(), and a rescan releases and relinks it.
/datum/unit_test/dq_resleeving_growpod_link

/datum/unit_test/dq_resleeving_growpod_link/Run()
	var/turf/T = test_floor()
	var/obj/machinery/computer/transhuman/resleeving/console = allocate(/obj/machinery/computer/transhuman/resleeving, T)
	var/obj/machinery/clonepod/transhuman/pod = allocate(/obj/machinery/clonepod/transhuman, get_step(T, EAST))
	console.releasepods()
	TEST_ASSERT_NULL(pod.resleeving_console, "a released pod names no console")
	console.findpods()
	TEST_ASSERT_EQUAL(pod.resleeving_console, console, "findpods() links the growpod to the console")
	TEST_ASSERT(pod in console.pods, "and the console lists it")
	console.updatemodules()
	TEST_ASSERT_EQUAL(pod.resleeving_console, console, "updatemodules() relinks it")
	TEST_ASSERT_EQUAL(length(console.pods), 1, "once")
	qdel(pod)
	TEST_ASSERT_EQUAL(length(console.pods), 0, "a deleted pod leaves the console")
