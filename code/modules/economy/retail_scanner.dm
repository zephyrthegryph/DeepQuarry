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
	// ALLOW(instance_list): d: current transaction, index-parallel with price_list
	var/list/item_list = list()  // entities and according
	// ALLOW(instance_list): d: current transaction, index-parallel with item_list
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
REGISTRY_MEMBERSHIP(/obj/item/retail_scanner, REGISTRY_TRANSACTION_DEVICES)

/obj/item/retail_scanner/Initialize(mapload)
	. = ..()
	machine_id = "[station_name()] RETAIL #[GLOB.num_financial_terminals++]"
	if(locate_within(loc, /obj/structure/table))
		pixel_y = 3
	if(GLOB.economy_init && account_to_connect)
		rel_set(src, nameof(linked_account), GLOB.department_accounts[account_to_connect])

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

CAPABILITIES(/obj/item/retail_scanner)
	op("controls", in_hand(), label("Open retail scanner"), then(PROC_REF(retail_scanner_controls_opened)))
	interface("RetailScanner")
	without("ui_open")
	op("toggle_lock", ui_act("toggle_lock"), then(PROC_REF(ui_act_toggle_lock)))
	op("refund_transaction", ui_act("refund_transaction", arg("invoice_id", num()), arg("log_id", num())), then(PROC_REF(ui_act_refund_transaction)))
	op("link_account", ui_act("link_account", arg("name", num()), arg("pin", num())), then(PROC_REF(ui_act_link_account)))
	op("custom_order", ui_act("custom_order", arg("amount", num()), arg("price", num()), arg("purpose", schema_text(4096))), then(PROC_REF(ui_act_custom_order)))
	op("set_amount", ui_act("set_amount", arg("amount", num()), arg("item", schema_text(4096))), then(PROC_REF(ui_act_set_amount)))
	op("subtract", ui_act("subtract", arg("item", num())), then(PROC_REF(ui_act_subtract)))
	op("add", ui_act("add", arg("item", num())), then(PROC_REF(ui_act_add)))
	op("clear", ui_act("clear", arg("item", num())), then(PROC_REF(ui_act_clear)))
	op("clear_entry", ui_act("clear_entry"), then(PROC_REF(ui_act_clear_entry)))
	op("reset_log", ui_act("reset_log"), then(PROC_REF(ui_act_reset_log)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), label("Alternate use"), then(PROC_REF(interaction_alt)))
	emag(then(PROC_REF(on_emag)), powered = FALSE)

/obj/item/retail_scanner/proc/retail_scanner_controls_opened(datum/act/op/A)
	var/mob/user = A.actor
	tgui_interact(user)
	return OP_OK

/// Old click_alt.
/obj/item/retail_scanner/proc/interaction_alt(datum/act/op/A)
	var/mob/user = A.actor
	if(Adjacent(user))
		tgui_interact(user)
	return TRUE

/obj/item/retail_scanner/examine(mob/user)
	. = ..()
	if(transaction_amount)
		. += "It has a purchase of [transaction_amount] pending[transaction_purpose ? " for [transaction_purpose]" : ""]."
	. += "Its freight printer contains [length(freight_form_paper)] blank sheet\s. Use it on a closed crate to certify a shipment."

/// /obj/item/retail_scanner's window data.
/obj/item/retail_scanner/ui_data(datum/act/eval/A)
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

/obj/item/retail_scanner/proc/ui_act_toggle_lock(datum/act/op/A)
	var/mob/user = A.actor
	if(allowed(user))
		locked = !locked
		return TRUE
	to_chat(user, "[icon2html(src, user.client)]" + span_warning("Insufficient access."))
	return FALSE

/obj/item/retail_scanner/proc/ui_act_refund_transaction(datum/act/op/A, invoice_id, log_id)
	var/mob/user = A.actor
	if(locked || !linked_account?.is_department_budget() || !service_refund_authorized(user, linked_account))
		return FALSE
	var/datum/service_invoice/invoice = SSsupply.get_service_invoice(invoice_id || log_id)
	return SSsupply.refund_service_invoice(invoice, linked_account, machine_id, user)

/obj/item/retail_scanner/proc/ui_act_link_account(datum/act/op/A, name, pin)
	var/mob/user = A.actor
	if(locked)
		return FALSE
	var/attempt_account_num = name
	if(isnull(attempt_account_num))
		return FALSE
	var/attempt_pin = pin
	if(isnull(attempt_pin))
		return FALSE
	var/datum/money_account/new_account = attempt_account_access(attempt_account_num, attempt_pin, 1)
	if(new_account)
		if(new_account.suspended)
			visible_message("[icon2html(src, viewers(src))]" + span_warning("Account has been suspended."))
			return FALSE
		var/provider_changed = linked_account != new_account
		rel_set(src, nameof(linked_account), new_account)
		if(provider_changed)
			reset_memory()
		else
			ticket_changed()
		return TRUE
	to_chat(user, "[icon2html(src, user.client)]" + span_warning("Account not found."))
	return FALSE

/obj/item/retail_scanner/proc/ui_act_custom_order(datum/act/op/A, amount_arg, price_arg, purpose)
	var/mob/user = A.actor
	if(locked)
		return FALSE
	var/t_purpose = sanitize(purpose, 200)
	if (!t_purpose)
		return FALSE
	var/amount = amount_arg
	if(!isnum(amount))
		return FALSE
	amount = CLAMP(round(amount), 1, 20)
	var/price = price_arg
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
	play_sfx(src, SFX_MACHINES_TWOBEEP, 0.5, vary = FALSE)
	visible_message("[icon2html(src, viewers(src))][t_purpose][amount > 1 ? " [amount] x" : ""]: [amount * price] Thaler\s.")
	return TRUE

/obj/item/retail_scanner/proc/ui_act_set_amount(datum/act/op/A, amount, item)
	if(locked)
		return FALSE
	var/item_name = item
	if(!item_name)
		return FALSE
	var/n_amount = amount
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

/obj/item/retail_scanner/proc/ui_act_subtract(datum/act/op/A, item)
	if(locked)
		return FALSE
	var/item_name = item
	if(!item_name || !item_list[item_name] || !isnum(price_list[item_name]))
		return FALSE
	item_list[item_name]--
	if(item_list[item_name] <= 0)
		item_list -= item_name
		price_list -= item_name
	rebuild_ticket()
	ticket_changed()
	return TRUE

/obj/item/retail_scanner/proc/ui_act_add(datum/act/op/A, item)
	if(locked)
		return FALSE
	var/item_name = item
	if(!item_name || !item_list[item_name] || !isnum(price_list[item_name]))
		return FALSE
	if(item_list[item_name] >= 20)
		return FALSE
	item_list[item_name]++
	rebuild_ticket()
	ticket_changed()
	return TRUE

/obj/item/retail_scanner/proc/ui_act_clear(datum/act/op/A, item)
	if(locked)
		return FALSE
	var/item_name = item
	if(!item_name || !item_list[item_name] || !isnum(price_list[item_name]))
		return FALSE
	item_list -= item_name
	price_list -= item_name
	rebuild_ticket()
	ticket_changed()
	return TRUE

/obj/item/retail_scanner/proc/ui_act_clear_entry(datum/act/op/A)
	if(locked)
		return FALSE
	item_list.Cut()
	price_list.Cut()
	verified_sale_items = null
	rebuild_ticket()
	ticket_changed()
	return TRUE

/obj/item/retail_scanner/proc/ui_act_reset_log(datum/act/op/A)
	var/mob/user = A.actor
	if(locked)
		return FALSE
	if(linked_account?.department_id == DEPARTMENT_CIVILIAN)
		return FALSE
	LAZYCLEARLIST(transaction_logs)
	to_chat(user, "[icon2html(src, user.client)]" + span_notice("Transaction log reset."))
	return TRUE

/// Old attackby.
/obj/item/retail_scanner/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/O = A.held
	if(istype(O, /obj/item/paper))
		var/obj/item/paper/form = O
		if(form.info || form.shipping_ledger_data)
			to_chat(user, span_warning("The freight printer accepts only blank ordinary paper."))
			return OP_PASS
		if(!user.drop_from_inventory(form, src))
			return OP_PASS
		rel_add(src, nameof(freight_form_paper), form)
		to_chat(user, span_notice("You load [form] into [src]'s freight printer."))
		return OP_PASS
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
		return OP_DECLINE
	// Not paying: Look up price and add it to transaction_amount
	else
		scan_item_price(O, user)
	return OP_PASS

/obj/item/retail_scanner/showoff(mob/user)
	for (var/mob/M in view(user))
		M.show_message("[user] holds up [src]. <a HREF='byond://?src=\ref[M];clickitem=\ref[src]'>Swipe card or item.</a>",1)

/obj/item/retail_scanner/proc/confirm(obj/item/I)
	if(confirm_item == I && confirm_revision == ticket_revision)
		return 1
	else
		rel_set(src, nameof(confirm_item), I)
		confirm_revision = ticket_revision
		src.visible_message("[icon2html(src, viewers(src))]<b>Total price:</b> [transaction_amount] Thaler\s. Swipe again to confirm.")
		play_sfx(src, SFX_MACHINES_TWOBEEP, 0.5, vary = FALSE)
		return 0

/obj/item/retail_scanner/proc/scan_card(obj/item/card/id/I, obj/item/ID_container, mob/user)
	return scan_card_stage(I, ID_container, user, list())

/obj/item/retail_scanner/proc/scan_card_stage(obj/item/card/id/I, obj/item/ID_container, mob/user, list/answers)
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
		// Answers re-run this scan; they're keyed by the ticket revision, so a changed ticket asks again.
		if(D && D.security_level)
			var/pin_key = "pin[ticket_revision]:[transaction_amount]"
			if(!(pin_key in answers))
				open_request(src, /datum/prompt/number/service_checkout_pin, PROC_REF(checkout_answered), answerer = user, payer_card = I, card_holder = ID_container, operator = user, answers = answers, answer_key = pin_key)
				return
			attempt_pin = answers[pin_key]
			if(isnull(attempt_pin))
				return
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
					var/tip = service_tip_choice(user, D, quote, transaction_purpose, src, TYPE_PROC_REF(/obj/item/retail_scanner, checkout_answered), answers, I, ID_container, "tip[ticket_revision]:[transaction_amount]")
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
			E.set_worth(E.worth - transaction_amount)
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
	play_sfx(src, SFX_MACHINES_TWOBEEP, 0.5, vary = FALSE)

/obj/item/retail_scanner/proc/ticket_changed()
	ticket_revision++
	rel_clear(src, nameof(confirm_item))
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
	var/datum/money_account/staff_account = user.mind?.initial_account()
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
	play_sfx(src, SFX_MACHINES_CHIME, 0.5, vary = FALSE)
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


/obj/item/retail_scanner/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_danger("You stealthily swipe the cryptographic sequencer through \the [src]."))
	play_sfx(src, SFX_SPARKS)
	req_access = list()
	emagged = 1
	return OP_OK

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

/obj/item/retail_scanner/proc/checkout_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = checkout_apply(A)
	SStgui.update_uis(src)

/obj/item/retail_scanner/proc/checkout_apply(datum/act/request/A)
	var/datum/request/ask = A.answer
	if(istype(ask, /datum/prompt/number/service_checkout_pin))
		var/datum/prompt/number/service_checkout_pin/pin = ask
		pin.answers[pin.answer_key] = pin.value
		return scan_card_stage(pin.payer_card, pin.card_holder, pin.operator, pin.answers)
	var/datum/prompt/choice/service_checkout_tip/tip = ask
	tip.answers[tip.answer_key] = tip.value
	return scan_card_stage(tip.payer_card, tip.card_holder, tip.operator, tip.answers)
