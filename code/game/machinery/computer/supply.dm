// While it initially feels like the ordering console should be a subtype of the main console,
// their function is similar enough that the ordering console emerges as the less specialized,
// and therefore more deserving of parent-class status -- Ater

// Supply requests console
/obj/machinery/computer/supplycomp
	name = "supply ordering console"
	desc = "Request crates from here! Delivery not guaranteed."
	icon_screen = "request"
	circuit = /obj/item/circuitboard/supplycomp
	tgui_id = "SupplyConsole"
	var/authorization = 0
	var/temp = null
	/// Cooldown between printed requisition forms.
	COOLDOWN_DECLARE(reqtime)
	var/can_order_contraband = 0
	var/active_category = null
	var/menu_tab = 0
	var/list/expanded_packs

// Supply control console
/obj/machinery/computer/supplycomp/control
	name = "supply control console"
	desc = "Control the cargo shuttle's functions remotely."
	icon_keyboard = "tech_key"
	icon_screen = "supply"
	light_color = "#b88b2e"
	//req_access = list(ACCESS_CARGO) //removing hard access locks.
	circuit = /obj/item/circuitboard/supplycomp/control
	authorization = SUP_SEND_SHUTTLE | SUP_ACCEPT_ORDERS

CAPABILITIES(/obj/machinery/computer/supplycomp)
	op("open_ui", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req(PROC_REF(lets_in_holds), because = PROC_REF(lets_in_refusal))), then(TYPE_PROC_REF(/atom, op_open_ui)))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)

/// Requirement (was REQ_* lets_in): the legacy check answers TRUE to pass.
/obj/machinery/computer/supplycomp/proc/lets_in_holds(datum/act/op/A)
	var/answer = lets_in(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why lets_in_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/computer/supplycomp/proc/lets_in_refusal(datum/act/op/A)
	var/answer = lets_in(A.actor, src, A.held)
	return istext(answer) ? answer : "you don't have the required access to use this console"

/obj/machinery/computer/supplycomp/proc/lets_in(mob/actor, atom/target, obj/item/held)
	return allowed(actor)

/obj/machinery/computer/supplycomp/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if(!can_order_contraband)
		to_chat(user, span_notice("Special supplies unlocked."))
		authorization |= SUP_CONTRABAND
		req_access = list()
		can_order_contraband = TRUE
		return OP_OK
	return OP_DECLINE

/obj/machinery/computer/supplycomp/proc/can_manage_budget(mob/user, department)
	if(issilicon(user))
		return department == DEPARTMENT_CARGO && (authorization & SUP_ACCEPT_ORDERS)
	if(!ishuman(user))
		return FALSE
	var/mob/living/carbon/human/human_user = user
	var/datum/job/job = SSjob.get_job(human_user.job)
	return istype(job) && (department in job.department_accounts)

/obj/machinery/computer/supplycomp/proc/can_trade_market(mob/user)
	if(!(authorization & SUP_ACCEPT_ORDERS))
		return FALSE
	if(issilicon(user))
		return TRUE
	var/mob/living/carbon/human/human_user = user
	if(!istype(human_user))
		return FALSE
	var/obj/item/card/id/id_card = human_user.GetIdCard()
	return id_card && ((ACCESS_CARGO in id_card.access) || (ACCESS_HEADS in id_card.access) || can_manage_budget(user, DEPARTMENT_CARGO))

// TGUI (doc/rewrite/dx_conventions.md §5): tgui_data() and one act_<action> proc per action.
/obj/machinery/computer/supplycomp/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state) // ALLOW(sys_tgui_data_override): the foundation UI form: tgui_data() with act_<action> procs; the sys UI_DATA declaration predates it
	var/list/data = ..()
	var/list/shuttle_status = list()

	var/datum/shuttle/autodock/ferry/supply/shuttle = SSsupply.shuttle
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
	for(var/datum/supply_order/S in SSsupply.order_history)
		var/can_fund = S.personal_order ? (authorization & SUP_ACCEPT_ORDERS) : can_manage_budget(user, S.funding_department)
		var/funding_label = S.market_contract_funded ? "Principal contract allowance" : (S.personal_order ? "Personal: [S.ordered_by]" : S.funding_department)
		var/datum/cargo_market_counterparty/market_seller = SSsupply.market_counterparties?[S.market_counterparty_id]
		orders.Add(list(list(
			"ref" = "\ref[S]",
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
	for(var/datum/exported_crate/E in SSsupply.exported_crates)
		var/datum/cargo_market_counterparty/market_buyer = SSsupply.market_counterparties?[E.market_counterparty_id]
		receipts.Add(list(list(
			"ref" = "\ref[E]",
			"contents" = E.contents,
			"error" = E.contents["error"],
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
	data["market_auth"] = can_trade_market(user)
	data["market"] = SSsupply.cargo_market_ui_data(user, can_order_contraband || (authorization & SUP_CONTRABAND), can_trade_market(user))
	data["modal"] = tgui_modal_data(src)
	return data

/obj/machinery/computer/supplycomp/tgui_static_data(mob/user)
	var/list/data = ..()

	var/list/pack_list = list()
	for(var/pack_name in SSsupply.supply_pack)
		var/datum/supply_pack/P = SSsupply.supply_pack[pack_name]
		var/list/pack = list(
				"name" = P.name,
				"desc" = P.desc,
				"cost" = SSsupply.pack_price(P),
				"group" = P.group,
				"contraband" = P.contraband,
				"manifest" = uniqueList(P.manifest),
				"random" = P.num_contained,
				"ref" = "\ref[P]"
			)

		pack_list.Add(list(pack))
	data["supply_packs"] = pack_list
	data["categories"] = GLOB.all_supply_groups
	return data

/obj/machinery/computer/supplycomp/ui_allowed(mob/user, action)
	if(!SSsupply)
		log_runtime(EXCEPTION("## ERROR: The SSsupply datum is missing."))
		return FALSE
	if(!SSsupply.shuttle)
		log_runtime(EXCEPTION("## ERROR: The supply shuttle datum is missing."))
		return FALSE
	return TRUE

TYPE_TABLE(/obj/machinery/computer/supplycomp, ui_logged_actions, list(
	"approve_order" = LOG_GAME,
	"deny_order" = LOG_GAME,
	"delete_order" = LOG_GAME,
	"clear_all_requests" = LOG_GAME,
	"send_shuttle" = LOG_GAME,
	"market_route" = LOG_GAME,
))

/// Whether this console may order contraband (an emag, or a contraband-authorised board).
/obj/machinery/computer/supplycomp/proc/contraband_ok()
	return can_order_contraband || (authorization & SUP_CONTRABAND)

/// The requisition cooldown refusal, or null when a form can be printed.
/obj/machinery/computer/supplycomp/proc/requisition_wait()
	if(COOLDOWN_FINISHED(src, reqtime))
		return null
	return "[src]'s monitor flashes, \"[DisplayTimeText(COOLDOWN_TIMELEFT(src, reqtime))] remaining until another requisition form may be printed.\""

/obj/machinery/computer/supplycomp/proc/act_market_request(mob/user, contract, id, personal)
	var/datum/cargo_market_listing/listing = SSsupply.market_listing(ui_text(id, 128))
	if(!listing)
		return refuse(user, "That listing is gone.")
	personal = !!personal
	contract = !!contract
	if(!personal && !contract && !can_trade_market(user))
		return refuse(user, "This console can't trade on the market for you.")
	var/reason = ask_text(user, "Procurement justification", "Why should the station purchase this market listing?", "External market procurement")
	if(!reason)
		return
	if(!SSsupply.request_market_order(listing, user, reason, contraband_ok(), personal, contract))
		return refuse(user, "The market listing is no longer available.")
	to_chat(user, span_notice("The quoted market order was submitted[contract ? " against the contract allowance" : (personal ? " with personal funding" : " for departmental approval")]."))
	return TRUE

/obj/machinery/computer/supplycomp/proc/act_market_route(mob/user, bid, crate)
	bid = ui_text(bid, 128)
	var/datum/cargo_market_bid/market_bid = SSsupply.market_bid(bid)
	var/datum/cargo_market_counterparty/counterparty = SSsupply.market_counterparties?[market_bid?.counterparty_id]
	if(!can_trade_market(user) && !has_faction_market_access(user, counterparty?.faction_id))
		return refuse(user, "You can't route crates to that buyer.")
	var/obj/structure/closet/crate/routed = ui_ref(crate, null, /obj/structure/closet/crate)
	if(!routed)
		return refuse(user, "That crate is gone.")
	if(!SSsupply.route_market_crate(routed, bid, user, contraband_ok()))
		return refuse(user, "That route is no longer valid for this crate.")
	return TRUE

/obj/machinery/computer/supplycomp/proc/act_view_crate(mob/user, crate)
	var/datum/supply_pack/P = ui_ref(crate, null, /datum/supply_pack)
	if(!P)
		return refuse(user, null)
	var/list/payload = list(
		"name" = P.name,
		"desc" = P.desc,
		"cost" = P.cost,
		"manifest" = uniqueList(P.manifest),
		"ref" = "\ref[P]",
		"random" = P.num_contained,
	)
	tgui_modal_message(src, "view_crate", "", null, payload)
	return TRUE

/obj/machinery/computer/supplycomp/proc/act_request_crate_multi(mob/user, personal, ref)
	var/datum/supply_pack/S = orderable_pack(user, ref)
	if(!S)
		return UI_REFUSED
	var/amount = ask_number(user, "How many crates? (0 to 20)", 0, 20)
	if(!amount)
		return
	var/reason = ask_text(user, "Reason:", "Why do you require this item?")
	if(!reason)
		return
	return request_crates(user, S, reason, amount, !!personal)

/obj/machinery/computer/supplycomp/proc/act_request_crate(mob/user, personal, ref)
	var/datum/supply_pack/S = orderable_pack(user, ref)
	if(!S)
		return UI_REFUSED
	var/reason = ask_text(user, "Reason:", "Why do you require this item?")
	if(!reason)
		return
	return request_crates(user, S, reason, 1, !!personal)

/// The pack `ref` names if this console may order it now, else null (the user was told why).
/obj/machinery/computer/supplycomp/proc/orderable_pack(mob/user, ref)
	var/datum/supply_pack/S = ui_ref(ref, null, /datum/supply_pack)
	if(!S)
		refuse(user, null)
		return null
	if(S.contraband && !contraband_ok())
		refuse(user, "That pack isn't available from this console.")
		return null
	var/wait = requisition_wait()
	if(wait)
		visible_message(span_warning(wait))
		return null
	return S

/// Files `amount` orders for S and prints one requisition form.
/obj/machinery/computer/supplycomp/proc/request_crates(mob/user, datum/supply_pack/S, reason, amount, personal)
	var/orders_created = 0
	for(var/i in 1 to amount)
		if(!SSsupply.create_order(S, user, reason, personal))
			break
		orders_created++
	if(!orders_created)
		return refuse(user, "The order could not be funded.")
	print_requisition(user, S, reason, amount > 1 ? orders_created : null)
	COOLDOWN_START(src, reqtime, 0.5 SECONDS)
	return TRUE

/obj/machinery/computer/supplycomp/proc/print_requisition(mob/user, datum/supply_pack/S, reason, amount)
	var/idname = "*None Provided*"
	var/idrank = "*None Provided*"
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		idname = H.get_authentification_name()
		idrank = H.get_assignment()
	else if(issilicon(user))
		idname = user.real_name
		idrank = "Stationbound synthetic"
	var/obj/item/paper/reqform = new /obj/item/paper(loc)
	reqform.name = "Requisition Form - [S.name]"
	reqform.info += "<h3>[station_name()] Supply Requisition Form</h3><hr>"
	reqform.info += "INDEX: #[SSsupply.ordernum]<br>"
	reqform.info += "REQUESTED BY: [idname]<br>"
	reqform.info += "RANK: [idrank]<br>"
	reqform.info += "REASON: [reason]<br>"
	reqform.info += "SUPPLY CRATE TYPE: [S.name]<br>"
	reqform.info += "ACCESS RESTRICTION: [SSaccess.get_access_desc(S.access)]<br>"
	if(amount)
		reqform.info += "AMOUNT: [amount]<br>"
	reqform.info += "CONTENTS:<br>"
	reqform.info += S.get_html_manifest()
	reqform.info += "<hr>"
	reqform.info += "STAMP BELOW TO APPROVE THIS REQUISITION:<br>"
	changed(reqform)

/// Refuses unless this console accepts orders.
/obj/machinery/computer/supplycomp/proc/accepts_orders(mob/user)
	if(authorization & SUP_ACCEPT_ORDERS)
		return TRUE
	refuse(user, "This console can't manage orders.")
	return FALSE

/obj/machinery/computer/supplycomp/proc/act_edit_order_value(mob/user, default, edit, ref)
	var/datum/supply_order/O = ui_ref(ref, SSsupply.order_history, /datum/supply_order)
	var/field = ui_choice(edit, list("Supply Pack", "Cost", "Index", "Reason", "Ordered by", "Ordered at", "Approved by", "Approved at"))
	if(!O || !field || !accepts_orders(user))
		return UI_REFUSED
	var/new_val = ask_text(user, field, "Enter the new value for this field:", ui_text(default))
	if(!new_val || !accepts_orders(user))
		return
	switch(field)
		if("Supply Pack")
			O.name = new_val
		if("Cost")
			O.cost = ui_number(new_val, 0) || O.cost
		if("Index")
			O.index = ui_number(new_val, 0, round_to = 1) || O.index
		if("Reason")
			O.comment = new_val
		if("Ordered by")
			O.ordered_by = new_val
		if("Ordered at")
			O.ordered_at = new_val
		if("Approved by")
			O.approved_by = new_val
		if("Approved at")
			O.approved_at = new_val
	return TRUE

/obj/machinery/computer/supplycomp/proc/act_approve_order(mob/user, ref)
	var/datum/supply_order/O = ui_ref(ref, SSsupply.order_history, /datum/supply_order)
	if(!O)
		return refuse(user, null)
	if(O.personal_order ? !(authorization & SUP_ACCEPT_ORDERS) : !can_manage_budget(user, O.funding_department))
		return refuse(user, "You can't approve orders from that budget.")
	SSsupply.approve_order(O, user)
	return TRUE

/obj/machinery/computer/supplycomp/proc/act_deny_order(mob/user, ref)
	var/datum/supply_order/O = ui_ref(ref, SSsupply.order_history, /datum/supply_order)
	if(!O || !accepts_orders(user))
		return UI_REFUSED
	SSsupply.deny_order(O, user)
	return TRUE

/obj/machinery/computer/supplycomp/proc/act_delete_order(mob/user, ref)
	var/datum/supply_order/O = ui_ref(ref, SSsupply.order_history, /datum/supply_order)
	if(!O || !accepts_orders(user))
		return UI_REFUSED
	SSsupply.delete_order(O, user)
	return TRUE

/obj/machinery/computer/supplycomp/proc/act_clear_all_requests(mob/user)
	if(!accepts_orders(user))
		return UI_REFUSED
	SSsupply.deny_all_pending(user)
	return TRUE

/// The exported crate `ref` names, if this console may edit exports.
/obj/machinery/computer/supplycomp/proc/editable_export(mob/user, ref)
	var/datum/exported_crate/E = ui_ref(ref, SSsupply.exported_crates, /datum/exported_crate)
	if(!E)
		refuse(user, null)
		return null
	return accepts_orders(user) ? E : null

/obj/machinery/computer/supplycomp/proc/act_export_edit_field(mob/user, index, ref)
	var/datum/exported_crate/E = editable_export(user, ref)
	index = E && ui_number(index, 1, length(E.contents), round_to = 1)
	if(!index)
		return UI_REFUSED
	var/field = ask_list(user, "Select which field to edit", list("Name", "Quantity", "Value"), "Field Choice")
	if(!field)
		return
	var/list/row = E.contents[index]
	if(!islist(row))
		return
	var/new_val = ask_text(user, field, "Enter the new value for this field:", row[lowertext(field)])
	if(!new_val || QDELETED(E) || length(E.contents) < index || !islist(E.contents[index]))
		return
	row = E.contents[index]
	switch(field)
		if("Name")
			row["object"] = new_val
		if("Quantity")
			row["quantity"] = ui_number(new_val, 0) || row["quantity"]
		if("Value")
			row["value"] = ui_number(new_val, 0) || row["value"]
	return TRUE

/obj/machinery/computer/supplycomp/proc/act_export_delete_field(mob/user, index, ref)
	var/datum/exported_crate/E = editable_export(user, ref)
	index = E && ui_number(index, 1, length(E.contents), round_to = 1)
	if(!index)
		return UI_REFUSED
	E.contents.Cut(index, index + 1) // ALLOW(containment): datum field list named contents, not atom contents
	return TRUE

/obj/machinery/computer/supplycomp/proc/act_export_add_field(mob/user, ref)
	var/datum/exported_crate/E = editable_export(user, ref)
	if(!E)
		return UI_REFUSED
	SSsupply.add_export_item(E, user)
	return TRUE

/obj/machinery/computer/supplycomp/proc/act_export_edit(mob/user, default, edit, ref)
	var/datum/exported_crate/E = editable_export(user, ref)
	var/field = ui_choice(edit, list("Name", "Value"))
	if(!E || !field)
		return UI_REFUSED
	var/new_val = ask_text(user, field, "Enter the new value for this field:", ui_text(default))
	if(!new_val || !accepts_orders(user))
		return
	switch(field)
		if("Name")
			E.name = new_val
		if("Value")
			E.value = ui_number(new_val, 0) || E.value
	return TRUE

/obj/machinery/computer/supplycomp/proc/act_export_delete(mob/user, ref)
	var/datum/exported_crate/E = editable_export(user, ref)
	if(!E)
		return UI_REFUSED
	SSsupply.delete_export(E, user)
	return TRUE

/obj/machinery/computer/supplycomp/proc/act_send_shuttle(mob/user, mode)
	if(!(authorization & SUP_SEND_SHUTTLE))
		return refuse(user, "This console can't control the shuttle.")
	var/datum/shuttle/autodock/ferry/supply/shuttle = SSsupply.shuttle
	switch(ui_choice(mode, list("send_away", "send_to_station", "cancel_shuttle", "force_shuttle")))
		if("send_away")
			if(shuttle.forbidden_atoms_check())
				return refuse(user, "For safety reasons the automated supply shuttle cannot transport live organisms, classified nuclear weaponry or homing beacons.")
			shuttle.launch(src)
			to_chat(user, span_notice("Initiating launch sequence."))
		if("send_to_station")
			shuttle.launch(src)
			to_chat(user, span_notice("The supply shuttle has been called and will arrive in approximately [round(SSsupply.movetime / (1 MINUTES), 1)] minutes."))
		if("cancel_shuttle")
			shuttle.cancel_launch(src)
		if("force_shuttle")
			shuttle.force_launch(src)
		else
			return refuse(user, null)
	return TRUE

/obj/machinery/computer/supplycomp/proc/post_signal(command)
	var/datum/radio_frequency/frequency = SSradio.return_frequency(1435)

	if(!frequency) return

	var/datum/signal/status_signal = new
	rel_set(status_signal, nameof(status_signal.source), src)
	status_signal.transmission_method = TRANSMISSION_RADIO
	status_signal.data["command"] = command

	frequency.post_signal(src, status_signal)
