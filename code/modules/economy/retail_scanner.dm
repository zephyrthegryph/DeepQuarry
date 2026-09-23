/obj/item/retail_scanner
	name = "retail scanner"
	desc = "Swipe your ID card to make purchases electronically."
	icon = 'icons/obj/device.dmi'
	icon_state = "retail_idle"
	flags = NOBLUDGEON
	slot_flags = SLOT_BELT
	req_access = list(ACCESS_HEADS)
	w_class = ITEMSIZE_SMALL

	var/locked = 1
	var/emagged = 0
	var/machine_id = ""
	var/transaction_amount = 0 // cumulatd amount of money to pay in a single purchase
	var/transaction_purpose = "" // text that gets used in ATM transaction logs
	var/list/transaction_logs // list of strings using html code to visualise data
	var/list/item_list = list()  // entities and according
	var/list/price_list = list() // prices for each purchase
	/// Physical objects scanned into this ticket, keyed by object with scanned price.
	var/list/verified_sale_items
	/// Monotonic ticket identity. Any item, price, staff, or provider change
	/// invalidates confirmations and sleeping PIN/tip prompts.
	var/ticket_revision = 1

	var/obj/item/confirm_item
	var/confirm_revision = 0
	var/datum/money_account/linked_account
	var/account_to_connect = null
	var/service_staff_account_number = 0
	var/service_staff_name
	var/list/freight_form_paper

// Claim machine ID
/obj/item/retail_scanner/Initialize(mapload)
	. = ..()
	machine_id = "[station_name()] RETAIL #[GLOB.num_financial_terminals++]"
	if(locate(/obj/structure/table) in loc)
		pixel_y = 3
	GLOB.transaction_devices += src // Global reference list to be properly set up by /proc/setup_economy()
	if(GLOB.economy_init && account_to_connect)
		linked_account = GLOB.department_accounts[account_to_connect]

/obj/item/retail_scanner/Destroy()
	GLOB.transaction_devices -= src
	freight_form_paper = null
	. = ..()

// Always face the user when put on a table
/obj/item/retail_scanner/afterattack(atom/movable/AM, mob/user, proximity)
	if(!proximity)	return
	if(istype(AM, /obj/structure/table))
		src.pixel_y = 3 // Shift it up slightly to look better on table
		src.dir = get_dir(src, user)
	else if(istype(AM, /obj/structure/closet/crate))
		var/obj/structure/closet/crate/crate = AM
		certify_freight_crate(crate, user)
	else
		scan_item_price(AM, user)

// Reset dir when picked back up
/obj/item/retail_scanner/pickup(mob/user)
	src.dir = SOUTH
	src.pixel_y = 0

/obj/item/retail_scanner/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	tgui_interact(user)

/obj/item/retail_scanner/click_alt(mob/user)
	if(Adjacent(user))
		tgui_interact(user)

/obj/item/retail_scanner/examine(mob/user)
	. = ..()
	if(transaction_amount)
		. += "It has a purchase of [transaction_amount] pending[transaction_purpose ? " for [transaction_purpose]" : ""]."
	. += "Its freight printer contains [length(freight_form_paper)] blank sheet\s. Use it on a closed crate to certify a shipment."

/obj/item/retail_scanner/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	. = ..()
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "RetailScanner", name)
		ui.open()

/obj/item/retail_scanner/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/department_checkout = linked_account?.is_department_budget()
	return list(
		"locked" = locked,
		"linked_account" = linked_account?.owner_name,
		"machine_id" = machine_id,
		"department_checkout" = department_checkout,
		"subsidized_checkout" = linked_account?.department_id == DEPARTMENT_CIVILIAN,
		"transaction_logs" = linked_account?.is_department_budget() ? SSsupply.service_invoice_rows(0, linked_account.department_id) : (transaction_logs || list()),
		"current_transactioon" = get_current_transaction()
	)

/obj/item/retail_scanner/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return

	switch(action)
		if("toggle_lock")
			if(allowed(ui.user))
				locked = !locked
				return TRUE
			to_chat(ui.user, "[icon2html(src, ui.user.client)]" + span_warning("Insufficient access."))
			return FALSE
		if("refund_transaction")
			if(locked || !linked_account?.is_department_budget() || !service_refund_authorized(ui.user, linked_account))
				return FALSE
			var/datum/service_invoice/invoice = SSsupply.get_service_invoice(text2num(params["invoice_id"] || params["log_id"]))
			return SSsupply.refund_service_invoice(invoice, linked_account, machine_id, ui.user)
	return access_action(action, params, ui.user)

/obj/item/retail_scanner/proc/access_action(action, list/params, mob/user)
	if(locked)
		return FALSE

	switch(action)
		if("link_account")
			var/attempt_account_num = text2num(params["name"])
			if(isnull(attempt_account_num))
				return FALSE
			var/attempt_pin = text2num(params["pin"])
			if(isnull(attempt_pin))
				return FALSE
			var/datum/money_account/new_account = attempt_account_access(attempt_account_num, attempt_pin, 1)
			if(new_account)
				if(new_account.suspended)
					visible_message("[icon2html(src, viewers(src))]" + span_warning("Account has been suspended."))
					return FALSE
				var/provider_changed = linked_account != new_account
				linked_account = new_account
				if(provider_changed)
					reset_memory()
				else
					ticket_changed()
				return TRUE
			to_chat(user, "[icon2html(src, user.client)]" + span_warning("Account not found."))
			return FALSE
		if("custom_order")
			var/t_purpose = sanitize(params["purpose"], 200)
			if (!t_purpose)
				return FALSE
			var/amount = params["amount"]
			if(!isnum(amount))
				return FALSE
			amount = CLAMP(round(amount), 1, 20)
			var/price = params["price"]
			if(!isnum(price) || price <= 0)
				return FALSE
			price = CLAMP(round(price), 1, 1000000)
			if(item_list[t_purpose])
				if(price_list[t_purpose] != price || item_list[t_purpose] + amount > 20)
					return FALSE
				item_list[t_purpose] += amount
			else
				if(length(item_list) >= 10)
					return FALSE
				item_list[t_purpose] = amount
			price_list[t_purpose] = price
			capture_service_staff(user)
			rebuild_ticket()
			ticket_changed()
			playsound(src, 'sound/machines/twobeep.ogg', 25)
			visible_message("[icon2html(src, viewers(src))][t_purpose][amount > 1 ? " [amount] x" : ""]: [amount * price] Thaler\s.")
			return TRUE
		if("set_amount")
			var/item_name = params["item"]
			if(!item_name)
				return FALSE
			var/n_amount = text2num(params["amount"])
			if(!isnum(n_amount))
				return FALSE
			n_amount = CLAMP(n_amount, 0, 20)
			if(!item_list[item_name])
				return FALSE
			if(!n_amount)
				item_list -= item_name
				price_list -= item_name
				rebuild_ticket()
				ticket_changed()
				return TRUE
			item_list[item_name] = n_amount
			rebuild_ticket()
			ticket_changed()
			return TRUE
		if("subtract")
			var/item_name = params["item"]
			if(!item_name || !item_list[item_name] || !isnum(price_list[item_name]))
				return FALSE
			item_list[item_name]--
			if(item_list[item_name] <= 0)
				item_list -= item_name
				price_list -= item_name
			rebuild_ticket()
			ticket_changed()
			return TRUE
		if("add")
			var/item_name = params["item"]
			if(!item_name || !item_list[item_name] || !isnum(price_list[item_name]))
				return FALSE
			if(item_list[item_name] >= 20)
				return FALSE
			item_list[item_name]++
			rebuild_ticket()
			ticket_changed()
			return TRUE
		if("clear")
			var/item_name = params["item"]
			if(!item_name || !item_list[item_name] || !isnum(price_list[item_name]))
				return FALSE
			item_list -= item_name
			price_list -= item_name
			rebuild_ticket()
			ticket_changed()
			return TRUE
		if("clear_entry")
			item_list.Cut()
			price_list.Cut()
			verified_sale_items = null
			rebuild_ticket()
			ticket_changed()
			return TRUE
		if("reset_log")
			if(linked_account?.department_id == DEPARTMENT_CIVILIAN)
				return FALSE
			LAZYCLEARLIST(transaction_logs)
			to_chat(user, "[icon2html(src, user.client)]" + span_notice("Transaction log reset."))
			return TRUE

/obj/item/retail_scanner/attackby(obj/O, mob/user)
	if(istype(O, /obj/item/paper))
		var/obj/item/paper/form = O
		if(form.info || form.shipping_ledger_data)
			to_chat(user, span_warning("The freight printer accepts only blank ordinary paper."))
			return
		if(!user.drop_from_inventory(form, src))
			return
		LAZYADD(freight_form_paper, form)
		to_chat(user, span_notice("You load [form] into [src]'s freight printer."))
		return
	// Check for a method of paying (ID, PDA, e-wallet, cash, ect.)
	var/obj/item/card/id/I = O.GetID()
	if(I)
		scan_card(I, O, user)
	else if (istype(O, /obj/item/spacecash/ewallet))
		var/obj/item/spacecash/ewallet/E = O
		scan_wallet(E)
	else if (istype(O, /obj/item/spacecash))
		to_chat(user, span_warning("This device does not accept cash."))

	else if(istype(O, /obj/item/card/emag))
		return ..()
	// Not paying: Look up price and add it to transaction_amount
	else
		scan_item_price(O, user)

/obj/item/retail_scanner/showoff(mob/user)
	for (var/mob/M in view(user))
		M.show_message("[user] holds up [src]. <a HREF='byond://?src=\ref[M];clickitem=\ref[src]'>Swipe card or item.</a>",1)

/obj/item/retail_scanner/proc/confirm(obj/item/I)
	if(confirm_item == I && confirm_revision == ticket_revision)
		return 1
	else
		confirm_item = I
		confirm_revision = ticket_revision
		src.visible_message("[icon2html(src, viewers(src))]<b>Total price:</b> [transaction_amount] Thaler\s. Swipe again to confirm.")
		playsound(src, 'sound/machines/twobeep.ogg', 25)
		return 0


/obj/item/retail_scanner/proc/scan_card(obj/item/card/id/I, obj/item/ID_container, mob/user)
	if(!transaction_amount || !ticket_is_valid())
		return

	if(linked_account?.department_id != DEPARTMENT_CIVILIAN && (length(item_list) > 1 || item_list[item_list[1]] > 1) && !confirm(I))
		return

	if (!linked_account)
		user.visible_message("[icon2html(src, viewers(src))]" + span_warning("Unable to connect to linked account."))
		return
	var/snapshot_amount = transaction_amount
	var/snapshot_revision = ticket_revision
	var/datum/money_account/snapshot_provider = linked_account
	var/snapshot_payer_account = I.associated_account_number
	var/snapshot_staff_account = service_staff_account_number

	// Access account for transaction
	if(check_account())
		var/datum/money_account/D = get_account(I.associated_account_number)
		var/attempt_pin = ""
		if(D && D.security_level)
			attempt_pin = tgui_input_number(user, "Enter PIN", "Transaction")
			D = null
		if(!service_checkout_confirmation_valid(src, user, snapshot_revision, ticket_revision, snapshot_amount, transaction_amount, snapshot_payer_account, I.associated_account_number, snapshot_provider, linked_account, snapshot_staff_account, service_staff_account_number))
			return
		D = attempt_account_access(I.associated_account_number, attempt_pin, 2)

		if(!D)
			src.visible_message("[icon2html(src, viewers(src))]" + span_warning("Unable to access account. Check security settings and try again."))
		else
			if(D.suspended)
				src.visible_message("[icon2html(src, viewers(src))]" + span_warning("Your account has been suspended."))
			else
				if(linked_account.department_id == DEPARTMENT_CIVILIAN)
					var/list/quote = department_service_quote(D, DEPARTMENT_CIVILIAN, transaction_amount)
					if(!quote || !user)
						return
					var/tip = service_tip_choice(user, D, quote, transaction_purpose)
					if(isnull(tip) || !service_checkout_confirmation_valid(src, user, snapshot_revision, ticket_revision, snapshot_amount, transaction_amount, D.account_number, I.associated_account_number, snapshot_provider, linked_account, snapshot_staff_account, service_staff_account_number))
						return
					if(!complete_service_checkout(D, linked_account, transaction_amount, transaction_purpose, machine_id, item_list, price_list, service_staff_account_number, service_staff_name, tip, verified_sale_items))
						return
				else if(transaction_amount > D.money)
					src.visible_message("[icon2html(src, viewers(src))]" + span_warning("Not enough funds."))
					return
				else if(!transfer_account_funds(D, linked_account, transaction_amount, transaction_purpose, machine_id))
					return

				if(linked_account.department_id != DEPARTMENT_CIVILIAN)
					var/list/department_result = list(
						"total" = transaction_amount,
						"subsidy" = 0,
						"personal" = transaction_amount,
						"tip" = 0,
						"staff_tip" = 0,
						"service_tip" = 0,
					)
					SSsupply.create_service_invoice(D, linked_account, machine_id, item_list, price_list, department_result, service_staff_account_number, service_staff_name, null, "ID account", verified_sale_items)

				// Confirm and reset
				transaction_complete()

/obj/item/retail_scanner/proc/scan_wallet(obj/item/spacecash/ewallet/E)
	if(!transaction_amount || !ticket_is_valid())
		return

	if((length(item_list) > 1 || item_list[item_list[1]] > 1) && !confirm(E))
		return

	// Access account for transaction
	if(check_account())
		if(transaction_amount > E.worth)
			src.visible_message("[icon2html(src, viewers(src))]" + span_warning("Not enough funds."))
		else
			// Transfer the money
			E.worth -= transaction_amount
			linked_account.credit(transaction_amount, E.owner_name, transaction_purpose, machine_id, FALSE)

			SSsupply.create_service_external_invoice(linked_account, machine_id, item_list, price_list, E.owner_name, transaction_amount, "E-Wallet", verified_sale_items)

			// Confirm and reset
			transaction_complete()

/obj/item/retail_scanner/proc/scan_item_price(obj/O, mob/user)
	if(!istype(O))	return
	if(length(item_list) >= 10 && !item_list[O.name])
		src.visible_message("[icon2html(src, viewers(src))]" + span_warning("Only up to ten different items allowed per purchase."))
		return

	// First check if item has a valid price
	var/price = O.get_item_cost()
	if(isnull(price) && O.economic_export_value > 0)
		price = SSsupply.export_revenue(O.economic_export_value)
	if(isnull(price) && istype(O, /obj/item/stack))
		var/obj/item/stack/material_stack = O
		var/datum/material/material = material_stack.get_material()
		if(material?.supply_conversion_value)
			price = SSsupply.export_revenue(material_stack.get_amount() * material.supply_conversion_value)
	if(isnull(price))
		src.visible_message("[icon2html(src, viewers(src))]" + span_warning("Unable to find item in database."))
		return
	capture_service_staff(user)
	// Call out item cost
	src.visible_message("[icon2html(src, viewers(src))]\A [O]: [price ? "[price] Thaler\s" : "free of charge"].")
	for(var/previously_scanned in item_list)
		if(price == price_list[previously_scanned] && O.name == previously_scanned)
			. = item_list[previously_scanned]++
	if(!.)
		item_list[O.name] = 1
		price_list[O.name] = price
		. = 1
	rebuild_ticket()
	if(!O.economic_sale_invoice_id)
		LAZYSET(verified_sale_items, O, price)
	ticket_changed()
	// Animation and sound
	flick("retail_scan", src)
	playsound(src, 'sound/machines/twobeep.ogg', 25)

/obj/item/retail_scanner/proc/ticket_changed()
	ticket_revision++
	confirm_item = null
	confirm_revision = 0

/obj/item/retail_scanner/proc/get_current_transaction()
	if(!length(item_list))
		return list()

	var/list/current_transactioon = list(
		"items" = item_list,
		"prices" = price_list,
		"amount" = transaction_amount,

	)
	return current_transactioon

/obj/item/retail_scanner/proc/add_transaction_log(c_name, p_method, t_amount, account_number = 0, list/service_result)
	var/list/new_entry = list(
		"log_id" = length(transaction_logs) + 1,
		"customer" = c_name,
		"payment_method" = p_method,
		"trans_time" = stationtime2text(),
		"items" = item_list,
		"prices" = price_list,
		"amount" = transaction_amount,
		"account_number" = account_number,
		"subsidy" = service_result ? service_result["subsidy"] : 0,
		"personal" = service_result ? service_result["personal"] : 0,
		"refunded" = FALSE,
		"refund_time" = null,
		"refund_by" = null
	)
	new_entry["items"] = item_list.Copy()
	new_entry["prices"] = price_list.Copy()
	UNTYPED_LIST_ADD(transaction_logs, new_entry)

/proc/service_quote_text(list/quote, description, ten_percent_tip = 0, twenty_percent_tip = 0)
	var/itemization = strip_html_simple(replacetext(description || "Service purchase", "<br>", "\n"), 500)
	return "[itemization]\n\nTotal: [quote["total"]] Thalers\nPersonal account: [quote["personal"]] Thalers\nStation subsidy: [quote["subsidy"]] Thalers\nOptional tips: [ten_percent_tip] Th (10%) / [twenty_percent_tip] Th (20%)\n\nConfirm this itemized Service purchase?"

/proc/service_checkout_confirmation_valid(atom/terminal, mob/user, snapshot_revision, current_revision, snapshot_amount, current_amount, expected_account, presented_account, datum/money_account/expected_provider, datum/money_account/current_provider, expected_staff_account = 0, current_staff_account = 0)
	return !QDELETED(terminal) && user && snapshot_revision == current_revision && snapshot_amount == current_amount && expected_account == presented_account && expected_provider == current_provider && expected_staff_account == current_staff_account && (terminal.loc == user || terminal.Adjacent(user))

/obj/item/retail_scanner/proc/capture_service_staff(mob/user)
	service_staff_account_number = 0
	service_staff_name = null
	if(!linked_account?.is_department_budget() || !user)
		return
	var/datum/money_account/staff_account = user.mind?.initial_account
	if(!staff_account || department_for_mob(user) != linked_account.department_id)
		return
	service_staff_account_number = staff_account.account_number
	service_staff_name = user.real_name

/obj/item/retail_scanner/proc/rebuild_ticket()
	var/total = service_ticket_total(item_list, price_list)
	transaction_amount = isnull(total) ? 0 : total
	transaction_purpose = service_ticket_description(item_list, price_list)

/obj/item/retail_scanner/proc/ticket_is_valid()
	var/total = service_ticket_total(item_list, price_list)
	return !isnull(total) && total == transaction_amount

/obj/item/retail_scanner/proc/check_account()
	if (!linked_account)
		visible_message("[icon2html(src, viewers(src))]" + span_warning("Unable to connect to linked account."))
		return FALSE

	if(linked_account.suspended)
		visible_message("[icon2html(src, viewers(src))]" + span_warning("Connected account has been suspended."))
		return FALSE
	return TRUE

/obj/item/retail_scanner/proc/transaction_complete()
	/// Visible confirmation
	playsound(src, 'sound/machines/chime.ogg', 25)
	visible_message("[icon2html(src, viewers(src))]" + span_notice("Transaction complete."))
	flick("retail_approve", src)
	reset_memory()

/obj/item/retail_scanner/proc/reset_memory()
	transaction_amount = null
	transaction_purpose = ""
	item_list.Cut()
	price_list.Cut()
	verified_sale_items = null
	service_staff_account_number = 0
	service_staff_name = null
	ticket_changed()

/obj/item/retail_scanner/emag_act(remaining_charges, mob/user)
	if(emagged)
		return
	to_chat(user, span_danger("You stealthily swipe the cryptographic sequencer through \the [src]."))
	playsound(src, "sparks", 50, 1)
	req_access = list()
	emagged = 1

//--Premades--//

/obj/item/retail_scanner/command
	account_to_connect = "Command"

/obj/item/retail_scanner/medical
	account_to_connect = "Medical"

/obj/item/retail_scanner/engineering
	account_to_connect = "Engineering"

/obj/item/retail_scanner/service
	name = "service sales scanner"
	account_to_connect = DEPARTMENT_CIVILIAN

/obj/item/retail_scanner/science
	name = "research sales scanner"
	desc = "A departmental checkout scanner for selling R&D prototypes and other Research products to crewmembers."
	account_to_connect = DEPARTMENT_RESEARCH

/obj/item/retail_scanner/security
	account_to_connect = "Security"

/obj/item/retail_scanner/cargo
	name = "cargo sales scanner"
	desc = "A departmental checkout scanner for selling materials, imports, and Cargo stock to crewmembers."
	account_to_connect = "Cargo"

/obj/item/retail_scanner/civilian
	account_to_connect = "Civilian"
