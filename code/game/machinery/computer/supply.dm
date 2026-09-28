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

/obj/machinery/computer/supplycomp/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/supplycomp_open_ui,
	)
	..()

/// The old attack_hand's access check.
/datum/interaction/machine_hand/supplycomp_open_ui
	id = "supplycomp_open_ui"
	name = "Use"
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null), REQ_ON(PRED_TARGET, /obj/machinery/computer/supplycomp/proc/lets_in, "you don't have the required access to use this console"))
	effect = /atom/proc/interaction_open_ui

/obj/machinery/computer/supplycomp/proc/lets_in(mob/actor, atom/target, obj/item/held)
	return allowed(actor)

/obj/machinery/computer/supplycomp/emag_act(remaining_charges, mob/user)
	if(!can_order_contraband)
		to_chat(user, span_notice("Special supplies unlocked."))
		authorization |= SUP_CONTRABAND
		req_access = list()
		can_order_contraband = TRUE
		return 1

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


// TGUI
/obj/machinery/computer/supplycomp/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "SupplyConsole", name)
		ui.open()

/obj/machinery/computer/supplycomp/tgui_data(mob/user)
	var/list/data = ..()
	var/list/shuttle_status = list()

	var/datum/shuttle/autodock/ferry/supply/shuttle = GLOB.supply_service.shuttle
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
	for(var/datum/supply_order/S in GLOB.supply_service.order_history)
		var/can_fund = S.personal_order ? (authorization & SUP_ACCEPT_ORDERS) : can_manage_budget(user, S.funding_department)
		var/funding_label = S.market_contract_funded ? "Principal contract allowance" : (S.personal_order ? "Personal: [S.ordered_by]" : S.funding_department)
		var/datum/cargo_market_counterparty/market_seller = GLOB.supply_service.market_counterparties?[S.market_counterparty_id]
		orders.Add(list(list(
			"ref" = "\ref[S]",
			"status" = S.status,
			"cost" = GLOB.supply_service.order_price(S),
			"can_approve" = can_fund,
			"entries" = list(
				list("field" = "Supply Pack", "entry" = S.name),
				list("field" = "Funding Source", "entry" = funding_label),
				list("field" = "Charged", "entry" = S.paid_amount ? "[S.paid_amount] Thalers" : "Unpaid"),
				list("field" = "Cost", "entry" = "[GLOB.supply_service.order_price(S)] Thalers"),
				list("field" = "Seller", "entry" = GLOB.supply_service.market_display_name(market_seller, user, S.market_cover_name) || "NanoTrasen catalog"),
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
	for(var/datum/exported_crate/E in GLOB.supply_service.exported_crates)
		var/datum/cargo_market_counterparty/market_buyer = GLOB.supply_service.market_counterparties?[E.market_counterparty_id]
		receipts.Add(list(list(
			"ref" = "\ref[E]",
			"contents" = E.contents,
			"error" = E.contents["error"],
			"title" = list(
				list("field" = "Name", "entry" = E.name),
				list("field" = "Value", "entry" = E.value),
				list("field" = "Buyer", "entry" = GLOB.supply_service.market_display_name(market_buyer, user, E.market_cover_name) || "Spot market"),
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
	data["market"] = GLOB.supply_service.cargo_market_ui_data(user, can_order_contraband || (authorization & SUP_CONTRABAND), can_trade_market(user))
	data["modal"] = tgui_modal_data(src)
	return data

/obj/machinery/computer/supplycomp/tgui_static_data(mob/user)
	var/list/data = ..()

	var/list/pack_list = list()
	for(var/pack_name in GLOB.supply_service.supply_pack)
		var/datum/supply_pack/P = GLOB.supply_service.supply_pack[pack_name]
		var/list/pack = list(
				"name" = P.name,
				"desc" = P.desc,
				"cost" = GLOB.supply_service.pack_price(P),
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

/obj/machinery/computer/supplycomp/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE
	if(!GLOB.supply_service)
		log_runtime(EXCEPTION("## ERROR: The GLOB.supply_service datum is missing."))
		return TRUE
	var/datum/shuttle/autodock/ferry/supply/shuttle = GLOB.supply_service.shuttle
	if(!shuttle)
		log_runtime(EXCEPTION("## ERROR: The supply shuttle datum is missing."))
		return TRUE

	if(tgui_modal_act(src, action, params))
		return TRUE

	switch(action)
		if("market_request")
			var/datum/cargo_market_listing/listing = GLOB.supply_service.market_listing(params["id"])
			if(!listing)
				return FALSE
			var/personal_funding = !!params["personal"]
			var/contract_funding = !!params["contract"]
			if(!personal_funding && !contract_funding && !can_trade_market(ui.user))
				return FALSE
			om_ask(ui.user, /datum/om/prompt/text/supply_market_justification, PROC_REF(market_request_justified), listing = listing, personal = personal_funding, contract = contract_funding)
			. = TRUE
		if("market_route")
			var/datum/cargo_market_bid/bid = GLOB.supply_service.market_bid(params["bid"])
			var/datum/cargo_market_counterparty/counterparty = GLOB.supply_service.market_counterparties?[bid?.counterparty_id]
			if(!can_trade_market(ui.user) && !has_faction_market_access(ui.user, counterparty?.faction_id))
				return FALSE
			var/obj/structure/closet/crate/crate = locate(params["crate"])
			if(!istype(crate))
				return FALSE
			if(!GLOB.supply_service.route_market_crate(crate, params["bid"], ui.user, can_order_contraband || (authorization & SUP_CONTRABAND)))
				to_chat(ui.user, span_warning("That route is no longer valid for this crate."))
				return FALSE
			. = TRUE
		if("view_crate")
			var/datum/supply_pack/P = locate(params["crate"])
			if(!istype(P))
				return FALSE
			var/list/payload = list(
				"name" = P.name,
				"desc" = P.desc,
				"cost" = P.cost,
				"manifest" = uniqueList(P.manifest),
				"ref" = "\ref[P]",
				"random" = P.num_contained,
			)
			tgui_modal_message(src, action, "", null, payload)
			. = TRUE
		if("request_crate_multi")
			var/datum/supply_pack/S = locate(params["ref"])

			// Invalid ref
			if(!istype(S))
				return FALSE

			if(S.contraband && !(authorization & SUP_CONTRABAND || can_order_contraband))
				return FALSE

			if(!COOLDOWN_FINISHED(src, reqtime))
				visible_message(span_warning("[src]'s monitor flashes, \"[DisplayTimeText(COOLDOWN_TIMELEFT(src, reqtime))] remaining until another requisition form may be printed.\""))
				return FALSE

			om_ask(ui.user, /datum/om/prompt/number/supply_crate_amount, PROC_REF(crate_amount_entered), pack = S, personal = !!params["personal"])
			. = TRUE

		if("request_crate")
			var/datum/supply_pack/S = locate(params["ref"])

			// Invalid ref
			if(!istype(S))
				return FALSE

			if(S.contraband && !(authorization & SUP_CONTRABAND || can_order_contraband))
				return FALSE

			if(!COOLDOWN_FINISHED(src, reqtime))
				visible_message(span_warning("[src]'s monitor flashes, \"[DisplayTimeText(COOLDOWN_TIMELEFT(src, reqtime))] remaining until another requisition form may be printed.\""))
				return FALSE

			om_ask(ui.user, /datum/om/prompt/text/supply_crate_reason, PROC_REF(crate_requested), pack = S, personal = !!params["personal"])
			. = TRUE
		// Approving Orders
		if("edit_order_value")
			var/datum/supply_order/O = locate(params["ref"])
			if(!istype(O))
				return FALSE
			if(!(authorization & SUP_ACCEPT_ORDERS))
				return FALSE
			om_ask(ui.user, /datum/om/prompt/text/supply_field, PROC_REF(order_value_entered), message = params["edit"], default = params["default"], edited = O, field = params["edit"])
			. = TRUE
		if("approve_order")
			var/datum/supply_order/O = locate(params["ref"])
			if(!istype(O))
				return FALSE
			if(O.personal_order ? !(authorization & SUP_ACCEPT_ORDERS) : !can_manage_budget(ui.user, O.funding_department))
				return FALSE
			GLOB.supply_service.approve_order(O, ui.user)
			. = TRUE
		if("deny_order")
			var/datum/supply_order/O = locate(params["ref"])
			if(!istype(O))
				return FALSE
			if(!(authorization & SUP_ACCEPT_ORDERS))
				return FALSE
			GLOB.supply_service.deny_order(O, ui.user)
			. = TRUE
		if("delete_order")
			var/datum/supply_order/O = locate(params["ref"])
			if(!istype(O))
				return FALSE
			if(!(authorization & SUP_ACCEPT_ORDERS))
				return FALSE
			GLOB.supply_service.delete_order(O, ui.user)
			. = TRUE
		if("clear_all_requests")
			if(!(authorization & SUP_ACCEPT_ORDERS))
				return FALSE
			GLOB.supply_service.deny_all_pending(ui.user)
			. = TRUE
		// Exports
		if("export_edit_field")
			var/datum/exported_crate/E = locate(params["ref"])
			// Invalid ref
			if(!istype(E))
				return FALSE
			if(!(authorization & SUP_ACCEPT_ORDERS))
				return FALSE
			om_ask(ui.user, /datum/om/prompt/choice/supply_export_field, PROC_REF(ask_export_value), crate = E, index = params["index"])
			. = TRUE
		if("export_delete_field")
			var/datum/exported_crate/E = locate(params["ref"])
			// Invalid ref
			if(!istype(E))
				return FALSE
			if(!(authorization & SUP_ACCEPT_ORDERS))
				return FALSE
			E.contents.Cut(params["index"], params["index"] + 1) // ALLOW(containment): datum field list named contents, not atom contents
			. = TRUE
		if("export_add_field")
			var/datum/exported_crate/E = locate(params["ref"])
			// Invalid ref
			if(!istype(E))
				return FALSE
			if(!(authorization & SUP_ACCEPT_ORDERS))
				return FALSE
			GLOB.supply_service.add_export_item(E, ui.user)
			. = TRUE
		if("export_edit")
			var/datum/exported_crate/E = locate(params["ref"])
			// Invalid ref
			if(!istype(E))
				return FALSE
			if(!(authorization & SUP_ACCEPT_ORDERS))
				return FALSE
			om_ask(ui.user, /datum/om/prompt/text/supply_field, PROC_REF(export_value_entered), message = params["edit"], default = params["default"], edited = E, field = params["edit"])
			. = TRUE
		if("export_delete")
			var/datum/exported_crate/E = locate(params["ref"])
			// Invalid ref
			if(!istype(E))
				return FALSE
			if(!(authorization & SUP_ACCEPT_ORDERS))
				return FALSE
			GLOB.supply_service.delete_export(E, ui.user)
			. = TRUE
		if("send_shuttle")
			if(!(authorization & SUP_SEND_SHUTTLE))
				return FALSE
			switch(params["mode"])
				if("send_away")
					if (shuttle.forbidden_atoms_check())
						to_chat(ui.user, span_warning("For safety reasons the automated supply shuttle cannot transport live organisms, classified nuclear weaponry or homing beacons."))
					else
						shuttle.launch(src)
						to_chat(ui.user, span_notice("Initiating launch sequence."))

				if("send_to_station")
					shuttle.launch(src)
					to_chat(ui.user, span_notice("The supply shuttle has been called and will arrive in approximately [round(GLOB.supply_service.movetime/600,1)] minutes."))

				if("cancel_shuttle")
					shuttle.cancel_launch(src)

				if("force_shuttle")
					shuttle.force_launch(src)
			. = TRUE

	add_fingerprint(ui.user)

/datum/om/prompt/text/supply_market_justification
	title = "Why should the station purchase this market listing?"
	message = "Procurement justification"
	default = "External market procurement"
	requires = PROMPT_USABLE
	var/datum/cargo_market_listing/listing
	var/personal = FALSE
	var/contract = FALSE

/obj/machinery/computer/supplycomp/proc/market_request_justified(datum/om/prompt/text/supply_market_justification/ask)
	var/mob/user = ask.answerer
	var/reason = ask.text
	var/datum/cargo_market_listing/listing = ask.listing
	var/personal_funding = ask.personal
	var/contract_funding = ask.contract
	if(!reason)
		return FALSE
	if(!GLOB.supply_service.request_market_order(listing, user, reason, can_order_contraband || (authorization & SUP_CONTRABAND), personal_funding, contract_funding))
		to_chat(user, span_warning("The market listing is no longer available."))
		return FALSE
	to_chat(user, span_notice("The quoted market order was submitted[contract_funding ? " against the contract allowance" : (personal_funding ? " with personal funding" : " for departmental approval")]."))
	. = TRUE

/datum/om/prompt/number/supply_crate_amount
	message = "How many crates? (0 to 20)"
	min = 0
	max = 20
	timeout = 1 MINUTE
	requires = PROMPT_USABLE
	var/datum/supply_pack/pack
	var/personal = FALSE

/obj/machinery/computer/supplycomp/proc/crate_amount_entered(datum/om/prompt/number/supply_crate_amount/ask)
	var/amount = clamp(ask.number, 0, 20)
	if(!amount)
		return
	om_ask(ask.answerer, /datum/om/prompt/text/supply_crate_reason, PROC_REF(crates_requested), pack = ask.pack, personal = ask.personal, amount = amount)

/// The requisition reason (single crates, and after the amount for multiple).
/datum/om/prompt/text/supply_crate_reason
	title = "Why do you require this item?"
	message = "Reason:"
	default = ""
	timeout = 1 MINUTE
	requires = PROMPT_USABLE
	var/datum/supply_pack/pack
	var/personal = FALSE
	var/amount = 1

/obj/machinery/computer/supplycomp/proc/crates_requested(datum/om/prompt/text/supply_crate_reason/ask)
	var/mob/user = ask.answerer
	var/datum/supply_pack/S = ask.pack
	var/amount = ask.amount
	var/reason = ask.text
	if(!amount || !reason)
		return FALSE

	var/personal_funding = !!ask.personal
	var/orders_created = 0
	for(var/i in 1 to amount)
		if(!GLOB.supply_service.create_order(S, user, reason, personal_funding))
			break
		orders_created++
	if(!orders_created)
		to_chat(user, span_warning("The order could not be funded."))
		return FALSE

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
	reqform.info += "INDEX: #[GLOB.supply_service.ordernum]<br>"
	reqform.info += "REQUESTED BY: [idname]<br>"
	reqform.info += "RANK: [idrank]<br>"
	reqform.info += "REASON: [reason]<br>"
	reqform.info += "SUPPLY CRATE TYPE: [S.name]<br>"
	reqform.info += "ACCESS RESTRICTION: [SSaccess.get_access_desc(S.access)]<br>"
	reqform.info += "AMOUNT: [orders_created]<br>"
	reqform.info += "CONTENTS:<br>"
	reqform.info +=  S.get_html_manifest()
	reqform.info += "<hr>"
	reqform.info += "STAMP BELOW TO APPROVE THIS REQUISITION:<br>"

	reqform.update_icon()	//Fix for appearing blank when printed.
	COOLDOWN_START(src, reqtime, 0.5 SECONDS)
	. = TRUE

/obj/machinery/computer/supplycomp/proc/crate_requested(datum/om/prompt/text/supply_crate_reason/ask)
	var/mob/user = ask.answerer
	var/reason = ask.text
	var/datum/supply_pack/S = ask.pack
	if(!reason)
		return FALSE

	if(!GLOB.supply_service.create_order(S, user, reason, !!ask.personal))
		to_chat(user, span_warning("The order could not be funded."))
		return FALSE

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
	reqform.info += "INDEX: #[GLOB.supply_service.ordernum]<br>"
	reqform.info += "REQUESTED BY: [idname]<br>"
	reqform.info += "RANK: [idrank]<br>"
	reqform.info += "REASON: [reason]<br>"
	reqform.info += "SUPPLY CRATE TYPE: [S.name]<br>"
	reqform.info += "ACCESS RESTRICTION: [SSaccess.get_access_desc(S.access)]<br>"
	reqform.info += "CONTENTS:<br>"
	reqform.info +=  S.get_html_manifest()
	reqform.info += "<hr>"
	reqform.info += "STAMP BELOW TO APPROVE THIS REQUISITION:<br>"

	reqform.update_icon()	//Fix for appearing blank when printed.
	COOLDOWN_START(src, reqtime, 0.5 SECONDS)
	. = TRUE

/// Edits one field of an order or an export; re-checked on the answer: the console still accepts orders.
/datum/om/prompt/text/supply_field
	title = "Enter the new value for this field:"
	requires = PROMPT_USABLE
	/// The order or exported crate being edited.
	var/datum/edited
	var/field
	/// Export content row (export_edit_field only).
	var/index

/datum/om/prompt/text/supply_field/valid()
	var/obj/machinery/computer/supplycomp/console = subject
	return (console.authorization & SUP_ACCEPT_ORDERS) ? null : "not authorized"

/obj/machinery/computer/supplycomp/proc/order_value_entered(datum/om/prompt/text/supply_field/ask)
	var/datum/supply_order/O = ask.edited
	var/new_val = ask.text
	if(!new_val)
		return FALSE

	switch(ask.field)
		if("Supply Pack")
			O.name = new_val

		if("Cost")
			var/num = text2num(new_val)
			if(num)
				O.cost = num

		if("Index")
			var/num = text2num(new_val)
			if(num)
				O.index = num

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
	. = TRUE

/datum/om/prompt/choice/supply_export_field
	title = "Field Choice"
	message = "Select which field to edit"
	choices = list("Name", "Quantity", "Value")
	buttons = TRUE
	requires = PROMPT_USABLE
	var/datum/exported_crate/crate
	var/index

/obj/machinery/computer/supplycomp/proc/ask_export_value(datum/om/prompt/choice/supply_export_field/ask)
	var/list/L = ask.crate.contents[ask.index]
	var/field = ask.choice
	om_ask(ask.answerer, /datum/om/prompt/text/supply_field, PROC_REF(export_field_edited), message = field, default = L[lowertext(field)], edited = ask.crate, field = field, index = ask.index)

/obj/machinery/computer/supplycomp/proc/export_field_edited(datum/om/prompt/text/supply_field/ask)
	var/datum/exported_crate/E = ask.edited
	var/list/L = E.contents[ask.index]
	var/field = ask.field
	var/new_val = ask.text
	if(!new_val || !islist(L))
		return
	switch(field)
		if("Name")
			L["object"] = new_val

		if("Quantity")
			var/num = text2num(new_val)
			if(num)
				L["quantity"] = num

		if("Value")
			var/num = text2num(new_val)
			if(num)
				L["value"] = num
	. = TRUE

/obj/machinery/computer/supplycomp/proc/export_value_entered(datum/om/prompt/text/supply_field/ask)
	var/datum/exported_crate/E = ask.edited
	var/new_val = ask.text
	if(!new_val)
		return

	switch(ask.field)
		if("Name")
			E.name = new_val

		if("Value")
			var/num = text2num(new_val)
			if(num)
				E.value = num
	. = TRUE

/obj/machinery/computer/supplycomp/proc/post_signal(command)
	var/datum/radio_frequency/frequency = GLOB.radio_service.return_frequency(1435)

	if(!frequency) return

	var/datum/signal/status_signal = new
	status_signal.source_handle = om_handle(src)
	status_signal.transmission_method = TRANSMISSION_RADIO
	status_signal.data["command"] = command

	frequency.post_signal(src, status_signal)
