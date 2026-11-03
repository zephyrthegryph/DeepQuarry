// While it initially feels like the ordering console should be a subtype of the main console,
// their function is similar enough that the ordering console emerges as the less specialized,
// and therefore more deserving of parent-class status -- Ater

// Supply requests console
/obj/machinery/computer/supplycomp
	name = "supply ordering console"
	desc = "Request crates from here! Delivery not guaranteed."
	icon_screen = "request"
	circuit = /obj/item/circuitboard/supplycomp
	var/authorization = 0
	var/temp = null
	/// Cooldown between printed requisition forms.
	COOLDOWN_DECLARE(reqtime)
	var/can_order_contraband = 0
	var/active_category = null

// Supply control console
/obj/machinery/computer/supplycomp/control
	name = "supply control console"
	desc = "Control the cargo shuttle's functions remotely."
	icon_keyboard = "tech_key"
	icon_screen = "supply"
	//req_access = list(ACCESS_CARGO) //removing hard access locks.
	circuit = /obj/item/circuitboard/supplycomp/control
	authorization = SUP_SEND_SHUTTLE | SUP_ACCEPT_ORDERS

CAPABILITIES(/obj/machinery/computer/supplycomp/control)
	configure(light_glow(color = "#b88b2e"))

CAPABILITIES(/obj/machinery/computer/supplycomp)
	interface("SupplyConsole")
	// Opening the window takes the console's access; its buttons take the supply system being up.
	extend("ui_open", needs(req(PROC_REF(lets_in))))
	extend(TAG_UI, needs(req(PROC_REF(supply_ready), silent = TRUE)))
	op("market_request", ui_act("market_request", arg("id", schema_text(128)), arg("contract", bool(), optional = TRUE), arg("personal", bool(), optional = TRUE)), needs(req(PROC_REF(market_request_ok))), asks(/datum/prompt/text, fields = list("question" = "Procurement justification", "title" = "Why should the station purchase this market listing?", "default" = "External market procurement", "timeout" = 0), step = "reason"), then(PROC_REF(ui_act_market_request)))
	op("market_route", ui_act("market_route", arg("bid", schema_text(128)), arg("crate", schema_text(4096))), needs(req(PROC_REF(market_route_ok))), then(PROC_REF(ui_act_market_route)), logs(LOG_GAME))
	op("view_crate", ui_act("view_crate", arg("crate", schema_text(4096))), needs(req(PROC_REF(crate_listed))), then(PROC_REF(ui_act_view_crate)))
	op("request_crate", ui_act("request_crate", arg("ref", schema_text(4096)), arg("personal", bool(), optional = TRUE)), needs(req(PROC_REF(pack_orderable))), asks(/datum/prompt/text, fields = list("question" = "Reason:", "title" = "Why do you require this item?", "timeout" = 0), step = "reason"), then(PROC_REF(ui_act_request_crate)))
	op("request_crate_multi", ui_act("request_crate_multi", arg("ref", schema_text(4096)), arg("personal", bool(), optional = TRUE)), needs(req(PROC_REF(pack_orderable))), asks(/datum/prompt/number, fields = list("question" = "How many crates? (0 to 20)", "title" = "Crates", "min_value" = 0, "max_value" = 20, "timeout" = 0), step = "amount"), asks(/datum/prompt/text, fields = list("question" = "Reason:", "title" = "Why do you require this item?", "timeout" = 0), step = "reason"), then(PROC_REF(ui_act_request_crate_multi)))
	op("edit_order_value", ui_act("edit_order_value", arg("ref", schema_text(4096)), arg("edit", schema_text(64)), arg("default", optional = TRUE)), needs(req(PROC_REF(accepts_orders)), req(PROC_REF(order_listed)), req(PROC_REF(order_field_listed))), asks(/datum/prompt/text, fields = list("question" = computed(PROC_REF(field_question)), "title" = "Enter the new value for this field:", "default" = computed(PROC_REF(field_default)), "timeout" = 0), step = "value"), then(PROC_REF(ui_act_edit_order_value)))
	op("approve_order", ui_act("approve_order", arg("ref", schema_text(4096))), needs(req(PROC_REF(order_approvable))), then(PROC_REF(ui_act_approve_order)), logs(LOG_GAME))
	op("deny_order", ui_act("deny_order", arg("ref", schema_text(4096))), needs(req(PROC_REF(accepts_orders)), req(PROC_REF(order_listed))), then(PROC_REF(ui_act_deny_order)), logs(LOG_GAME))
	op("delete_order", ui_act("delete_order", arg("ref", schema_text(4096))), needs(req(PROC_REF(accepts_orders)), req(PROC_REF(order_listed))), then(PROC_REF(ui_act_delete_order)), logs(LOG_GAME))
	op("clear_all_requests", ui_act("clear_all_requests"), needs(req(PROC_REF(accepts_orders))), then(PROC_REF(ui_act_clear_all_requests)), logs(LOG_GAME))
	op("export_edit_field", ui_act("export_edit_field", arg("ref", schema_text(4096)), arg("index", num())), needs(req(PROC_REF(accepts_orders)), req(PROC_REF(export_row_listed))), asks(/datum/prompt/choice, fields = list("question" = "Select which field to edit", "title" = "Field Choice", "choices" = list("Name", "Quantity", "Value"), "timeout" = 0), step = "field"), asks(/datum/prompt/text, fields = list("question" = computed(PROC_REF(export_row_question)), "title" = "Enter the new value for this field:", "default" = computed(PROC_REF(export_row_default)), "timeout" = 0), step = "value"), then(PROC_REF(ui_act_export_edit_field)))
	op("export_delete_field", ui_act("export_delete_field", arg("ref", schema_text(4096)), arg("index", num())), needs(req(PROC_REF(accepts_orders)), req(PROC_REF(export_row_listed))), then(PROC_REF(ui_act_export_delete_field)))
	op("export_add_field", ui_act("export_add_field", arg("ref", schema_text(4096))), needs(req(PROC_REF(accepts_orders)), req(PROC_REF(export_listed))), then(PROC_REF(ui_act_export_add_field)))
	op("export_edit", ui_act("export_edit", arg("ref", schema_text(4096)), arg("edit", schema_text(64)), arg("default", optional = TRUE)), needs(req(PROC_REF(accepts_orders)), req(PROC_REF(export_listed)), req(PROC_REF(export_field_listed))), asks(/datum/prompt/text, fields = list("question" = computed(PROC_REF(field_question)), "title" = "Enter the new value for this field:", "default" = computed(PROC_REF(field_default)), "timeout" = 0), step = "value"), then(PROC_REF(ui_act_export_edit)))
	op("export_delete", ui_act("export_delete", arg("ref", schema_text(4096))), needs(req(PROC_REF(accepts_orders)), req(PROC_REF(export_listed))), then(PROC_REF(ui_act_export_delete)))
	op("send_shuttle", ui_act("send_shuttle", arg("mode", schema_text(64))), needs(req(PROC_REF(controls_shuttle)), req(PROC_REF(shuttle_mode_ok))), then(PROC_REF(ui_act_send_shuttle)), logs(LOG_GAME))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)

/obj/machinery/computer/supplycomp/proc/lets_in(datum/act/op/A)
	if(allowed(A.actor))
		return null
	return "you don't have the required access to use this console"

/obj/machinery/computer/supplycomp/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if(!can_order_contraband)
		to_chat(user, span_notice("Special supplies unlocked."))
		set_authorization(authorization | SUP_CONTRABAND)
		set_req_access(list())
		set_can_order_contraband(TRUE)
		return OP_OK
	return OP_DECLINE

/// `authority` is what the input carries (A.authority): a silicon's link is AUTH_REMOTE_ACCESS, the station trusting its AI and a cyborg's card.
/obj/machinery/computer/supplycomp/proc/can_manage_budget(mob/user, department, authority)
	if(authority & AUTH_REMOTE_ACCESS)
		return department == DEPARTMENT_CARGO && (authorization & SUP_ACCEPT_ORDERS)
	if(!ishuman(user))
		return FALSE
	var/mob/living/carbon/human/human_user = user
	var/datum/job/job = SSjob.get_job(human_user.job)
	return istype(job) && (department in job.department_accounts)

/obj/machinery/computer/supplycomp/proc/can_trade_market(mob/user, authority)
	if(!(authorization & SUP_ACCEPT_ORDERS))
		return FALSE
	if(authority & AUTH_REMOTE_ACCESS)
		return TRUE
	var/mob/living/carbon/human/human_user = user
	if(!istype(human_user))
		return FALSE
	var/obj/item/card/id/id_card = human_user.GetIdCard()
	return id_card && ((ACCESS_CARGO in id_card.access) || (ACCESS_HEADS in id_card.access) || can_manage_budget(user, DEPARTMENT_CARGO, authority))

/// The window's data.
/obj/machinery/computer/supplycomp/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	var/list/shuttle_status = list()

	var/datum/shuttle/autodock/ferry/supply/shuttle = SSsupply.cargo_shuttle()
	if(shuttle)
		if(shuttle.has_arrive_time())
			shuttle_status["location"] = "In transit"
			shuttle_status["mode"] = SUP_SHUTTLE_TRANSIT
			shuttle_status["time"] = shuttle.eta_deciseconds() // tgui expects time for it's formatTime() in DS

		else
			shuttle_status["time"] = 0
			if(shuttle.at_station())
				if(shuttle.shuttle_docking_controller)
					switch(shuttle.shuttle_docking_controller.get_docking_status())
						if("docked")
							shuttle_status["location"] = "Docked"
							shuttle_status["mode"] = SUP_SHUTTLE_DOCKED
						if("undocked")
							shuttle_status["location"] = "Undocked"
							shuttle_status["mode"] = SUP_SHUTTLE_UNDOCKED
						if("docking")
							shuttle_status["location"] = "Docking"
							shuttle_status["mode"] = SUP_SHUTTLE_DOCKING
							shuttle_status["force"] = shuttle.can_force()
						if("undocking")
							shuttle_status["location"] = "Undocking"
							shuttle_status["mode"] = SUP_SHUTTLE_UNDOCKING
							shuttle_status["force"] = shuttle.can_force()

				else
					shuttle_status["location"] = "Station"
					shuttle_status["mode"] = SUP_SHUTTLE_DOCKED

			else
				shuttle_status["location"] = "Away"
				shuttle_status["mode"] = SUP_SHUTTLE_AWAY

			if(shuttle.can_launch())
				shuttle_status["launch"] = 1
			else if(shuttle.can_cancel())
				shuttle_status["launch"] = 2
			else
				shuttle_status["launch"] = 0

		switch(shuttle.moving_status)
			if(SHUTTLE_IDLE)
				shuttle_status["engine"] = "Idle"
			if(SHUTTLE_WARMUP)
				shuttle_status["engine"] = "Warming up"
			if(SHUTTLE_INTRANSIT)
				shuttle_status["engine"] = "Engaged"

	else
		shuttle_status["mode"] = SUP_SHUTTLE_ERROR

	// Compile user-side orders
	// Status determines which menus the entry will display in
	// Organized in field-entry list for iterative display
	// List is nested so both the list of orders, and the list of elements in each order, can be iterated over
	var/list/orders = list()
	for(var/datum/supply_order/S in SSsupply.order_history_snapshot())
		var/can_fund = S.personal_order ? (authorization & SUP_ACCEPT_ORDERS) : can_manage_budget(user, S.funding_department, A.authority)
		var/funding_label = S.market_contract_funded ? "Principal contract allowance" : (S.personal_order ? "Personal: [S.ordered_by]" : S.funding_department)
		var/datum/cargo_market_counterparty/market_seller = SSsupply.order_counterparty(S)
		orders.Add(list(list(
			"ref" = ref_token(S),
			"status" = S.status,
			"cost" = SSsupply.order_price(S),
			"can_approve" = can_fund,
			"entries" = list(
				list("field" = "Supply Pack", "entry" = S.name),
				list("field" = "Funding Source", "entry" = funding_label),
				list("field" = "Charged", "entry" = S.paid_amount ? "[S.paid_amount] Thalers" : "Unpaid"),
				list("field" = "Cost", "entry" = "[SSsupply.order_price(S)] Thalers"),
				list("field" = "Seller", "entry" = SSsupply.market_display_name(market_seller, user, S.market_cover_name) || "NanoTrasen catalog"),
				list("field" = "Index", "entry" = S.index),
				list("field" = "Reason", "entry" = S.comment),
				list("field" = "Ordered by", "entry" = S.ordered_by),
				list("field" = "Ordered at", "entry" = S.ordered_at),
				list("field" = "Approved by", "entry" = S.approved_by),
				list("field" = "Approved at", "entry" = S.approved_at)
				)
			)))

	// Compile exported crates
	var/list/receipts = list()
	for(var/datum/exported_crate/E in SSsupply.export_history_snapshot())
		var/datum/cargo_market_counterparty/market_buyer = SSsupply.export_counterparty(E)
		receipts.Add(list(list(
			"ref" = ref_token(E),
			"contents" = E.rows,
			"error" = E.rows?["error"], // a receipt with no lines has no rows list
			"title" = list(
				list("field" = "Name", "entry" = E.name),
				list("field" = "Value", "entry" = E.value),
				list("field" = "Buyer", "entry" = SSsupply.market_display_name(market_buyer, user, E.market_cover_name) || "Spot market"),
				list("field" = "Market premium", "entry" = E.market_premium)
			)
		)))

	data["shuttle_auth"] = (authorization & SUP_SEND_SHUTTLE) // Whether this ui is permitted to control the supply shuttle
	data["order_auth"] = (authorization & SUP_ACCEPT_ORDERS)   // Whether this ui is permitted to accept/deny requested orders
	data["shuttle"] = shuttle_status
	var/department = DEPARTMENT_CARGO
	if(ishuman(user))
		var/mob/living/carbon/human/human_user = user
		var/datum/department/primary_department = SSjob.get_primary_department_of_job(human_user.job)
		if(primary_department?.name in GLOB.department_accounts)
			department = primary_department.name
	var/datum/money_account/requester_budget = GLOB.department_accounts[department]
	data["supply_points"] = requester_budget?.available_funds() || 0
	var/datum/money_account/personal_account = user?.mind?.initial_account()
	data["can_personal_order"] = !!personal_account
	data["personal_balance"] = personal_account?.money || 0
	data["orders"] = orders
	data["receipts"] = receipts
	data["contraband"] = can_order_contraband || (authorization & SUP_CONTRABAND)
	data["market_auth"] = can_trade_market(user, A.authority)
	data["market"] = SSsupply.cargo_market_ui_data(user, can_order_contraband || (authorization & SUP_CONTRABAND), can_trade_market(user, A.authority))
	data["modal"] = tgui_modal_data(src)
	return data

/obj/machinery/computer/supplycomp/tgui_static_data(mob/user)
	var/list/data = ..()

	var/list/pack_list = list()
	for(var/pack_name in SSsupply.catalog_names())
		var/datum/supply_pack/P = SSsupply.catalog_pack(pack_name)
		var/list/pack = list(
				"name" = P.name,
				"desc" = P.desc,
				"cost" = SSsupply.pack_price(P),
				"group" = P.group,
				"contraband" = P.contraband,
				"manifest" = uniqueList(P.manifest),
				"random" = P.num_contained,
				"ref" = ref_token(P)
			)

		pack_list.Add(list(pack))
	data["supply_packs"] = pack_list
	data["categories"] = GLOB.all_supply_groups
	return data

MSG_DEF_SELF(supply/offline, "The supply system is offline.")
MSG_DEF_SELF(supply/no_market_listing, "That listing is gone.")
MSG_DEF_SELF(supply/no_market_trade, "This console can't trade on the market for you.")
MSG_DEF_SELF(supply/no_route, "You can't route crates to that buyer.")
MSG_DEF_SELF(supply/no_crate, "That crate is gone.")
MSG_DEF_SELF(supply/pack_unavailable, "That pack isn't available from this console.")
MSG_DEF_SELF(supply/no_orders, "This console can't manage orders.")
MSG_DEF_SELF(supply/no_budget, "You can't approve orders from that budget.")
MSG_DEF_SELF(supply/no_shuttle_control, "This console can't control the shuttle.")
MSG_DEF_SELF(supply/forbidden_cargo, "For safety reasons the automated supply shuttle cannot transport live organisms, classified nuclear weaponry or homing beacons.")

/// req (every window button): the supply system and its shuttle exist. Silent otherwise, as the window's gate always was.
/obj/machinery/computer/supplycomp/proc/supply_ready(datum/act/op/A)
	if(!SSsupply || !SSsupply.cargo_shuttle())
		return MSG(supply/offline)
	return null

/// The order fields an admin-style edit may name.
GLOBAL_LIST_INIT(supply_order_fields, list("Supply Pack", "Cost", "Index", "Reason", "Ordered by", "Ordered at", "Approved by", "Approved at"))
/// The export fields a title edit may name.
GLOBAL_LIST_INIT(supply_export_title_fields, list("Name", "Value"))

/// Whether this console may order contraband (an emag, or a contraband-authorised board).
/obj/machinery/computer/supplycomp/proc/contraband_ok()
	return can_order_contraband || (authorization & SUP_CONTRABAND)

/// The requisition cooldown refusal, or null when a form can be printed.
/obj/machinery/computer/supplycomp/proc/requisition_wait()
	if(COOLDOWN_FINISHED(src, reqtime))
		return null
	return "[src]'s monitor flashes, \"[DisplayTimeText(COOLDOWN_TIMELEFT(src, reqtime))] remaining until another requisition form may be printed.\""

/// A window button was pressed: the console remembers who (what the window dispatcher's fingerprint did for every action).
/obj/machinery/computer/supplycomp/proc/supply_touched(datum/act/op/A)
	var/mob/user = A.actor
	if(isliving(user))
		add_fingerprint(user)

// ---- the market ----

/// req: the market listing exists and this console may buy it the way the button asked.
/obj/machinery/computer/supplycomp/proc/market_request_ok(datum/act/op/A)
	if(!SSsupply.market_listing(ui_text(A.arg("id"), 128)))
		return MSG(supply/no_market_listing)
	if(!A.arg("personal") && !A.arg("contract") && !can_trade_market(A.actor, A.authority))
		return MSG(supply/no_market_trade)
	return null

/obj/machinery/computer/supplycomp/proc/ui_act_market_request(datum/act/op/A, id, contract, personal)
	var/mob/user = A.actor
	supply_touched(A)
	var/datum/cargo_market_listing/listing = SSsupply.market_listing(ui_text(id, 128))
	personal = !!personal
	contract = !!contract
	var/reason = A.step_value("reason")
	if(!listing || !reason)
		return
	if(!SSsupply.request_market_order(listing, user, reason, contraband_ok(), personal, contract))
		to_chat(user, span_warning("The market listing is no longer available."))
		return FALSE
	to_chat(user, span_notice("The quoted market order was submitted[contract ? " against the contract allowance" : (personal ? " with personal funding" : " for departmental approval")]."))
	return TRUE

/// req: the bid's buyer may be routed to by this console or this person, and the crate named is still there.
/obj/machinery/computer/supplycomp/proc/market_route_ok(datum/act/op/A)
	var/datum/cargo_market_bid/market_bid = SSsupply.market_bid(ui_text(A.arg("bid"), 128))
	var/datum/cargo_market_counterparty/counterparty = SSsupply.market_counterparty(market_bid?.counterparty_id)
	if(!can_trade_market(A.actor, A.authority) && !has_faction_market_access(A.actor, counterparty?.faction_id))
		return MSG(supply/no_route)
	if(!ui_token(A.arg("crate"), null, /obj/structure/closet/crate)) // the shuttle check is route_market_crate()'s
		return MSG(supply/no_crate)
	return null

/obj/machinery/computer/supplycomp/proc/ui_act_market_route(datum/act/op/A, bid, crate)
	var/mob/user = A.actor
	supply_touched(A)
	bid = ui_text(bid, 128)
	var/obj/structure/closet/crate/routed = ui_token(crate, null, /obj/structure/closet/crate)
	if(!routed || !SSsupply.route_market_crate(routed, bid, user, contraband_ok()))
		to_chat(user, span_warning("That route is no longer valid for this crate."))
		return FALSE
	return TRUE

// ---- ordering ----

/// The pack a handle names, if it is one of the catalog's.
/obj/machinery/computer/supplycomp/proc/catalog_pack_of(handle)
	return ui_member(handle, SSsupply.catalog_packs(), /datum/supply_pack)

/// The pack the button named (its `ref`).
/obj/machinery/computer/supplycomp/proc/named_pack(datum/act/op/A)
	return catalog_pack_of(A.arg("ref"))

/// req: the button named (crate =) a pack of the catalog.
/obj/machinery/computer/supplycomp/proc/crate_listed(datum/act/op/A)
	return catalog_pack_of(A.arg("crate")) ? null : /datum/msg/req_silent

/// req: the pack may be ordered from this console now.
/obj/machinery/computer/supplycomp/proc/pack_orderable(datum/act/op/A)
	var/datum/supply_pack/S = named_pack(A)
	if(!S)
		return /datum/msg/req_silent
	if(S.contraband && !contraband_ok())
		return MSG(supply/pack_unavailable)
	return requisition_wait()

/obj/machinery/computer/supplycomp/proc/ui_act_view_crate(datum/act/op/A, crate)
	supply_touched(A)
	var/datum/supply_pack/P = catalog_pack_of(crate)
	if(!P)
		return FALSE
	var/list/payload = list(
		"name" = P.name,
		"desc" = P.desc,
		"cost" = P.cost,
		"manifest" = uniqueList(P.manifest),
		"ref" = ref_token(P),
		"random" = P.num_contained,
	)
	tgui_modal_message(src, "view_crate", "", null, payload)
	return TRUE

/obj/machinery/computer/supplycomp/proc/ui_act_request_crate_multi(datum/act/op/A, ref, personal)
	supply_touched(A)
	var/amount = A.step_value("amount")
	var/reason = A.step_value("reason")
	var/datum/supply_pack/S = catalog_pack_of(ref)
	if(!S || !amount || !reason)
		return
	return request_crates(A.actor, S, reason, amount, !!personal, A.authority)

/obj/machinery/computer/supplycomp/proc/ui_act_request_crate(datum/act/op/A, ref, personal)
	supply_touched(A)
	var/reason = A.step_value("reason")
	var/datum/supply_pack/S = catalog_pack_of(ref)
	if(!S || !reason)
		return
	return request_crates(A.actor, S, reason, 1, !!personal, A.authority)

/// Files `amount` orders for S and prints one requisition form.
/obj/machinery/computer/supplycomp/proc/request_crates(mob/user, datum/supply_pack/S, reason, amount, personal, authority)
	var/orders_created = 0
	for(var/i in 1 to amount)
		if(!SSsupply.create_order(S, user, reason, personal))
			break
		orders_created++
	if(!orders_created)
		to_chat(user, span_warning("The order could not be funded."))
		return FALSE
	print_requisition(user, S, reason, amount > 1 ? orders_created : null, authority)
	COOLDOWN_START(src, reqtime, 0.5 SECONDS)
	return TRUE

/obj/machinery/computer/supplycomp/proc/print_requisition(mob/user, datum/supply_pack/S, reason, amount, authority)
	var/idname = "*None Provided*"
	var/idrank = "*None Provided*"
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		idname = H.get_authentification_name()
		idrank = H.get_assignment()
	else
		idname = user.real_name
		if(authority & AUTH_REMOTE_ACCESS)
			idrank = "Stationbound synthetic"
	var/obj/item/paper/reqform = new /obj/item/paper(loc)
	reqform.name = "Requisition Form - [S.name]"
	reqform.set_info(reqform.info + ("<h3>[station_name()] Supply Requisition Form</h3><hr>"))
	reqform.set_info(reqform.info + ("INDEX: #[SSsupply.current_order_index()]<br>"))
	reqform.set_info(reqform.info + ("REQUESTED BY: [idname]<br>"))
	reqform.set_info(reqform.info + ("RANK: [idrank]<br>"))
	reqform.set_info(reqform.info + ("REASON: [reason]<br>"))
	reqform.set_info(reqform.info + ("SUPPLY CRATE TYPE: [S.name]<br>"))
	reqform.set_info(reqform.info + ("ACCESS RESTRICTION: [SSaccess.get_access_desc(S.access)]<br>"))
	if(amount)
		reqform.set_info(reqform.info + ("AMOUNT: [amount]<br>"))
	reqform.set_info(reqform.info + ("CONTENTS:<br>"))
	reqform.set_info(reqform.info + (S.get_html_manifest()))
	reqform.set_info(reqform.info + ("<hr>"))
	reqform.set_info(reqform.info + ("STAMP BELOW TO APPROVE THIS REQUISITION:<br>"))

// ---- the order list ----

/// req: this console accepts orders.
/obj/machinery/computer/supplycomp/proc/accepts_orders(datum/act/op/A)
	return (authorization & SUP_ACCEPT_ORDERS) ? null : MSG(supply/no_orders)

/// The order a handle names, if it is in the history.
/obj/machinery/computer/supplycomp/proc/order_of(handle)
	return ui_member(handle, SSsupply.order_history_snapshot(), /datum/supply_order)

/// The order the button named (its `ref`).
/obj/machinery/computer/supplycomp/proc/named_order(datum/act/op/A)
	return order_of(A.arg("ref"))

/// req: the button named an order of the history.
/obj/machinery/computer/supplycomp/proc/order_listed(datum/act/op/A)
	return named_order(A) ? null : /datum/msg/req_silent

/// req: this person may approve the order from its budget.
/obj/machinery/computer/supplycomp/proc/order_approvable(datum/act/op/A)
	var/datum/supply_order/O = named_order(A)
	if(!O)
		return /datum/msg/req_silent
	if(O.personal_order ? !(authorization & SUP_ACCEPT_ORDERS) : !can_manage_budget(A.actor, O.funding_department, A.authority))
		return MSG(supply/no_budget)
	return null

/// req: the button named a field of an order to edit.
/obj/machinery/computer/supplycomp/proc/order_field_listed(datum/act/op/A)
	return ui_choice(A.arg("edit"), GLOB.supply_order_fields) ? null : /datum/msg/req_silent

/// The question of the new value (the field is the title).
/obj/machinery/computer/supplycomp/proc/field_question(datum/act/op/A)
	return "[A.arg("edit")]"

/// The default of the new value: what the window showed.
/obj/machinery/computer/supplycomp/proc/field_default(datum/act/op/A)
	return ui_text(A.arg("default"))

/obj/machinery/computer/supplycomp/proc/ui_act_edit_order_value(datum/act/op/A, ref, edit, default)
	supply_touched(A)
	var/datum/supply_order/O = order_of(ref)
	var/field = ui_choice(edit, GLOB.supply_order_fields)
	var/new_val = A.step_value("value")
	if(!O || !field || !new_val || !(authorization & SUP_ACCEPT_ORDERS))
		return
	switch(field)
		if("Supply Pack")
			O.name = text_or_null(new_val)
		if("Cost")
			O.cost = ui_number(new_val, 0) || O.cost
		if("Index")
			O.index = ui_number(new_val, 0, round_to = 1) || O.index
		if("Reason")
			O.set_comment(new_val)
		if("Ordered by")
			O.set_ordered_by(new_val)
		if("Ordered at")
			O.set_ordered_at(new_val)
		if("Approved by")
			O.set_approved_by(new_val)
		if("Approved at")
			O.set_approved_at(new_val)
	return TRUE

/obj/machinery/computer/supplycomp/proc/ui_act_approve_order(datum/act/op/A, ref)
	supply_touched(A)
	var/datum/supply_order/O = order_of(ref)
	if(!O)
		return FALSE
	SSsupply.approve_order(O, A.actor)
	return TRUE

/obj/machinery/computer/supplycomp/proc/ui_act_deny_order(datum/act/op/A, ref)
	supply_touched(A)
	var/datum/supply_order/O = order_of(ref)
	if(!O)
		return FALSE
	SSsupply.deny_order(O, A.actor)
	return TRUE

/obj/machinery/computer/supplycomp/proc/ui_act_delete_order(datum/act/op/A, ref)
	supply_touched(A)
	var/datum/supply_order/O = order_of(ref)
	if(!O)
		return FALSE
	SSsupply.delete_order(O, A.actor)
	return TRUE

/obj/machinery/computer/supplycomp/proc/ui_act_clear_all_requests(datum/act/op/A)
	supply_touched(A)
	SSsupply.deny_all_pending(A.actor)
	return TRUE

// ---- the receipts ----

/// The exported crate a handle names, if it is in the history.
/obj/machinery/computer/supplycomp/proc/export_of(handle)
	return ui_member(handle, SSsupply.export_history_snapshot(), /datum/exported_crate)

/// The exported crate the button named (its `ref`).
/obj/machinery/computer/supplycomp/proc/named_export(datum/act/op/A)
	return export_of(A.arg("ref"))

/// req: the button named a receipt of the history.
/obj/machinery/computer/supplycomp/proc/export_listed(datum/act/op/A)
	return named_export(A) ? null : /datum/msg/req_silent

/// req: the button named a line of the receipt.
/obj/machinery/computer/supplycomp/proc/export_row_listed(datum/act/op/A)
	var/datum/exported_crate/E = named_export(A)
	return (E && ui_number(A.arg("index"), 1, length(E.rows), round_to = 1)) ? null : /datum/msg/req_silent

/// req: the button named a title field of a receipt to edit.
/obj/machinery/computer/supplycomp/proc/export_field_listed(datum/act/op/A)
	return ui_choice(A.arg("edit"), GLOB.supply_export_title_fields) ? null : /datum/msg/req_silent

/// The default of a receipt line's new value: what the line holds for the chosen field.
/obj/machinery/computer/supplycomp/proc/export_row_default(datum/act/op/A)
	var/datum/exported_crate/E = named_export(A)
	var/index = E && ui_number(A.arg("index"), 1, length(E.rows), round_to = 1)
	var/field = A.step_value("field")
	if(!index || !field)
		return null
	var/list/row = E.rows[index]
	return islist(row) ? "[row[lowertext(field)]]" : null

/// The question of a receipt line's new value: the chosen field.
/obj/machinery/computer/supplycomp/proc/export_row_question(datum/act/op/A)
	return "[A.step_value("field")]"

/obj/machinery/computer/supplycomp/proc/ui_act_export_edit_field(datum/act/op/A, ref, index)
	supply_touched(A)
	var/datum/exported_crate/E = export_of(ref)
	index = E && ui_number(index, 1, length(E.rows), round_to = 1)
	var/field = A.step_value("field")
	var/new_val = A.step_value("value")
	if(!index || !field || !new_val || !(authorization & SUP_ACCEPT_ORDERS))
		return
	var/list/row = E.rows[index]
	if(!islist(row))
		return
	switch(field)
		if("Name")
			row["object"] = new_val
		if("Quantity")
			row["quantity"] = ui_number(new_val, 0) || row["quantity"]
		if("Value")
			row["value"] = ui_number(new_val, 0) || row["value"]
	return TRUE

/obj/machinery/computer/supplycomp/proc/ui_act_export_delete_field(datum/act/op/A, ref, index)
	supply_touched(A)
	var/datum/exported_crate/E = export_of(ref)
	index = E && ui_number(index, 1, length(E.rows), round_to = 1)
	if(!index)
		return FALSE
	E.cut_rows(index, index + 1)
	return TRUE

/obj/machinery/computer/supplycomp/proc/ui_act_export_add_field(datum/act/op/A, ref)
	supply_touched(A)
	var/datum/exported_crate/E = export_of(ref)
	if(!E)
		return FALSE
	SSsupply.add_export_item(E, A.actor)
	return TRUE

/obj/machinery/computer/supplycomp/proc/ui_act_export_edit(datum/act/op/A, ref, edit, default)
	supply_touched(A)
	var/datum/exported_crate/E = export_of(ref)
	var/field = ui_choice(edit, GLOB.supply_export_title_fields)
	var/new_val = A.step_value("value")
	if(!E || !field || !new_val || !(authorization & SUP_ACCEPT_ORDERS))
		return
	switch(field)
		if("Name")
			E.name = text_or_null(new_val)
		if("Value")
			E.set_value(ui_number(new_val, 0) || E.value)
	return TRUE

/obj/machinery/computer/supplycomp/proc/ui_act_export_delete(datum/act/op/A, ref)
	supply_touched(A)
	var/datum/exported_crate/E = export_of(ref)
	if(!E)
		return FALSE
	SSsupply.delete_export(E, A.actor)
	return TRUE

// ---- the shuttle ----

/// req: this console controls the shuttle.
/obj/machinery/computer/supplycomp/proc/controls_shuttle(datum/act/op/A)
	return (authorization & SUP_SEND_SHUTTLE) ? null : MSG(supply/no_shuttle_control)

/// req: the mode is one the window offers, and the shuttle may carry what it holds if it is sent away.
/obj/machinery/computer/supplycomp/proc/shuttle_mode_ok(datum/act/op/A)
	var/mode = ui_choice(A.arg("mode"), list("send_away", "send_to_station", "cancel_shuttle", "force_shuttle"))
	if(!mode)
		return /datum/msg/req_silent
	var/datum/shuttle/autodock/ferry/supply/shuttle = SSsupply.cargo_shuttle()
	if(mode == "send_away" && shuttle.forbidden_atoms_check())
		return MSG(supply/forbidden_cargo)
	return null

/obj/machinery/computer/supplycomp/proc/ui_act_send_shuttle(datum/act/op/A, mode)
	var/mob/user = A.actor
	supply_touched(A)
	var/datum/shuttle/autodock/ferry/supply/shuttle = SSsupply.cargo_shuttle()
	switch(ui_choice(mode, list("send_away", "send_to_station", "cancel_shuttle", "force_shuttle")))
		if("send_away")
			shuttle.launch(src)
			to_chat(user, span_notice("Initiating launch sequence."))
		if("send_to_station")
			shuttle.launch(src)
			to_chat(user, span_notice("The supply shuttle has been called and will arrive in approximately [round(SSsupply.shuttle_travel_duration() / (1 MINUTES), 1)] minutes."))
		if("cancel_shuttle")
			shuttle.cancel_launch(src)
		if("force_shuttle")
			shuttle.force_launch(src)
		else
			return FALSE
	return TRUE

/obj/machinery/computer/supplycomp/proc/post_signal(command)
	var/datum/radio_frequency/frequency = SSradio.return_frequency(1435)

	if(!frequency) return

	var/datum/signal/status_signal = new
	rel_set(status_signal, nameof(status_signal.source), src)
	status_signal.transmission_method = TRANSMISSION_RADIO
	status_signal.data["command"] = command

	frequency.post_signal(src, status_signal)
