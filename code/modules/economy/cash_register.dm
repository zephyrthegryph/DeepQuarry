/obj/machinery/cash_register
	name = "cash register"
	desc = "Swipe your ID card to make purchases electronically."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "register_idle"
	flags = NOBLUDGEON
	req_access = list(ACCESS_HEADS)
	anchored = TRUE

	locked = 1
	var/cash_locked = 1
	var/cash_open = 0
	var/machine_id = ""
	var/transaction_amount = 0 // cumulatd amount of money to pay in a single purchase
	var/transaction_purpose = null // text that gets used in ATM transaction logs
	var/list/transaction_logs // list of strings using html code to visualise data
	// ALLOW(instance_list): d: current transaction, index-parallel with price_list
	var/list/item_list = list()  // entities and according
	// ALLOW(instance_list): d: current transaction, index-parallel with item_list
	var/list/price_list = list() // prices for each purchase
	/// Physical objects scanned into this ticket, keyed by object with scanned price.
	var/list/verified_sale_items
	/// Monotonic identity for the complete itemized ticket.
	var/ticket_revision = 1

	var/cash_stored = 0
	var/obj/item/confirm_item
	var/confirm_revision = 0
	var/datum/money_account/linked_account
	var/account_to_connect = null
	var/service_staff_account_number = 0
	var/service_staff_name

// Claim machine ID
REGISTRY_MEMBERSHIP(/obj/machinery/cash_register, REGISTRY_TRANSACTION_DEVICES)

/obj/machinery/cash_register/Initialize(mapload)
	machine_id = "[station_name()] RETAIL #[GLOB.num_financial_terminals++]"
	. = ..()
	cash_stored = rand(10, 70)*10
	if(GLOB.economy_init && account_to_connect)
		rel_set(src, nameof(linked_account), GLOB.department_accounts[account_to_connect])

/obj/machinery/cash_register/examine(mob/user)
	. = ..(user)
	if(transaction_amount)
		. += "It has a purchase of [transaction_amount] pending[transaction_purpose ? " for [transaction_purpose]" : ""]."
	if(cash_open)
		if(cash_stored)
			. += "It holds [cash_stored] Thaler\s."
		else
			. += "It's completely empty."

/obj/machinery/cash_register/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	// Don't be accessible from the wrong side of the machine
	if(get_dir(src, user) & GLOB.reverse_dir[src.dir])
		return OP_OK

	if(cash_open)
		if(cash_stored)
			spawn_money(cash_stored, loc, user)
			cash_stored = 0
			cut_overlay("register_cash")
			return OP_OK
		open_cash_box(user)
		return OP_OK
	tgui_interact(user)
	return OP_OK

/obj/machinery/cash_register/proc/interaction_open_box_alt(datum/act/op/A)
	var/mob/user = A.actor
	open_cash_box(user)
	return OP_OK

/**
 * Old attackby: paying methods (ID/e-wallet/cash) or a price scan for anything else. An emag
 * declined (returns FALSE) so dispatch falls through to `..()`, exactly as the old
 * `else if(istype(O, /obj/item/card/emag)) return ..()` branch did.
 */

/obj/machinery/cash_register/proc/interaction_pay(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	// Check for a method of paying (ID, PDA, e-wallet, cash, ect.)
	var/obj/item/card/id/I = O.GetID()
	if(I)
		scan_card(I, O, user)
	else if (istype(O, /obj/item/spacecash/ewallet))
		var/obj/item/spacecash/ewallet/E = O
		scan_wallet(E, user)
	else if (istype(O, /obj/item/spacecash))
		var/obj/item/spacecash/SC = O
		if(cash_open)
			to_chat(user, "You neatly sort the cash into the box.")
			cash_stored += SC.worth
			add_overlay("register_cash")
			if(ishuman(user))
				var/mob/living/carbon/human/H = user
				H.drop_from_inventory(SC)
			consume(SC, user)
		else
			scan_cash(SC, user)
	else if(istype(O, /obj/item/card/emag))
		return OP_DECLINE
	// Not paying: Look up price and add it to transaction_amount
	else
		scan_item_price(O, user)
	return OP_OK

CAPABILITIES(/obj/machinery/cash_register)
	interface("RetailScanner")
	without("ui_open")
	op("toggle_lock", ui_act("toggle_lock"), then(PROC_REF(ui_act_toggle_lock)))
	op("refund_transaction", ui_act("refund_transaction", arg("invoice_id", num()), arg("log_id", num())), then(PROC_REF(ui_act_refund_transaction)))
	op("toggle_cash_lock", ui_act("toggle_cash_lock"), then(PROC_REF(ui_act_toggle_cash_lock)))
	op("link_account", ui_act("link_account", arg("name", num()), arg("pin", num())), then(PROC_REF(ui_act_link_account)))
	op("custom_order", ui_act("custom_order", arg("amount", num()), arg("price", num()), arg("purpose", schema_text(4096))), then(PROC_REF(ui_act_custom_order)))
	op("set_amount", ui_act("set_amount", arg("amount", num()), arg("item", schema_text(4096))), then(PROC_REF(ui_act_set_amount)))
	op("subtract", ui_act("subtract", arg("item", num())), then(PROC_REF(ui_act_subtract)))
	op("add", ui_act("add", arg("item", num())), then(PROC_REF(ui_act_add)))
	op("clear", ui_act("clear", arg("item", num())), then(PROC_REF(ui_act_clear)))
	op("clear_entry", ui_act("clear_entry"), then(PROC_REF(ui_act_clear_entry)))
	op("reset_log", ui_act("reset_log"), then(PROC_REF(ui_act_reset_log)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))
	op("cash_register_pay", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Pay / scan"), then(PROC_REF(interaction_pay)))
	op("cash_register_open_box_alt", hand(), ungated(), gesture(GESTURE_ALT), priority(OP_PRIORITY_DEFAULT - 1), label("Open cash box"), then(PROC_REF(interaction_open_box_alt)))
	op("cash_register_use", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_use)))
	op("cash_register_open_box_verb", menu(), label("Open Cash Box"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_open_box_verb)))
	op("cash_register_drop", item(/obj), gesture(GESTURE_DRAG), priority(OP_PRIORITY_DEFAULT - 1), label("Put on the register"), then(PROC_REF(interaction_drop)))
	emag(then(PROC_REF(on_emag)), powered = FALSE)

/// /obj/machinery/cash_register's window data.
/obj/machinery/cash_register/ui_data(datum/act/eval/A)
	var/department_checkout = linked_account?.is_department_budget()
	return list(
		"locked" = locked,
		"cash_locked" = cash_locked,
		"linked_account" = linked_account?.owner_name,
		"machine_id" = machine_id,
		"department_checkout" = department_checkout,
		"subsidized_checkout" = linked_account?.department_id == DEPARTMENT_CIVILIAN,
		"transaction_logs" = linked_account?.is_department_budget() ? SSsupply.service_invoice_rows(0, linked_account.department_id) : (transaction_logs || list()),
		"current_transactioon" = get_current_transaction()
	)

/obj/machinery/cash_register/proc/ui_act_toggle_lock(datum/act/op/A)
	var/mob/user = A.actor
	if(allowed(user))
		set_locked(!locked)
		return TRUE
	to_chat(user, "[icon2html(src, user.client)]" + span_warning("Insufficient access."))
	return FALSE

/obj/machinery/cash_register/proc/ui_act_refund_transaction(datum/act/op/A, invoice_id, log_id)
	var/mob/user = A.actor
	if(locked || !linked_account?.is_department_budget() || !service_refund_authorized(user, linked_account))
		return FALSE
	var/datum/service_invoice/invoice = SSsupply.get_service_invoice(invoice_id || log_id)
	return SSsupply.refund_service_invoice(invoice, linked_account, machine_id, user)

/obj/machinery/cash_register/proc/ui_act_toggle_cash_lock(datum/act/op/A)
	if(locked)
		return FALSE
	cash_locked = !cash_locked

/obj/machinery/cash_register/proc/ui_act_link_account(datum/act/op/A, name, pin)
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

/obj/machinery/cash_register/proc/ui_act_custom_order(datum/act/op/A, amount_arg, price_arg, purpose)
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

/obj/machinery/cash_register/proc/ui_act_set_amount(datum/act/op/A, amount, item)
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

/obj/machinery/cash_register/proc/ui_act_subtract(datum/act/op/A, item)
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

/obj/machinery/cash_register/proc/ui_act_add(datum/act/op/A, item)
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

/obj/machinery/cash_register/proc/ui_act_clear(datum/act/op/A, item)
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

/obj/machinery/cash_register/proc/ui_act_clear_entry(datum/act/op/A)
	if(locked)
		return FALSE
	item_list.Cut()
	price_list.Cut()
	verified_sale_items = null
	rebuild_ticket()
	ticket_changed()
	return TRUE

/obj/machinery/cash_register/proc/ui_act_reset_log(datum/act/op/A)
	var/mob/user = A.actor
	if(locked)
		return FALSE
	if(linked_account?.department_id == DEPARTMENT_CIVILIAN)
		return FALSE
	LAZYCLEARLIST(transaction_logs)
	to_chat(user, "[icon2html(src, user.client)]" + span_notice("Transaction log reset."))
	return TRUE

/obj/machinery/cash_register/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	toggle_anchors(tool, user)
	return OP_OK

/obj/machinery/cash_register/proc/interaction_drop(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/dropping = A.held
	if(Adjacent(dropping) && Adjacent(user) && !user.stat)
		attackby(dropping, user)
	return OP_OK

/obj/machinery/cash_register/proc/confirm(obj/item/I)
	if(confirm_item == I && confirm_revision == ticket_revision)
		return 1
	else
		rel_set(src, nameof(confirm_item), I)
		confirm_revision = ticket_revision
		src.visible_message(span_infoplain("[icon2html(src,viewers(src))]" + span_bold("Total price:") + " [transaction_amount] Thaler\s. Swipe again to confirm."))
		play_sfx(src, SFX_MACHINES_TWOBEEP, 0.5, vary = FALSE)
		return 0

/obj/machinery/cash_register/proc/scan_card(obj/item/card/id/I, obj/item/ID_container, mob/user)
	return scan_card_stage(I, ID_container, user, list())

/obj/machinery/cash_register/proc/scan_card_stage(obj/item/card/id/I, obj/item/ID_container, mob/user, list/answers)
	if(!transaction_amount || !ticket_is_valid())
		return

	if (cash_open)
		play_sfx(src, SFX_MACHINES_BUZZ_SIGH, 0.5)
		to_chat(user, "[icon2html(src, user.client)]" + span_warning("The cash box is open."))
		return

	if(linked_account?.department_id != DEPARTMENT_CIVILIAN && (item_list.len > 1 || item_list[item_list[1]] > 1) && !confirm(I))
		return

	if (!linked_account)
		user.visible_message("[icon2html(src,viewers(src))]" + span_warning("Unable to connect to linked account."))
		return
	var/snapshot_amount = transaction_amount
	var/snapshot_revision = ticket_revision
	var/datum/money_account/snapshot_provider = linked_account
	var/snapshot_payer_account = I.associated_account_number
	var/snapshot_staff_account = service_staff_account_number

	// Access account for transaction
	if(check_account(user))
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
		// Re-validate the complete ticket after the sleeping PIN prompt.
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
					var/tip = service_tip_choice(user, D, quote, transaction_purpose, src, TYPE_PROC_REF(/obj/machinery/cash_register, checkout_answered), answers, I, ID_container, "tip[ticket_revision]:[transaction_amount]")
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

/obj/machinery/cash_register/proc/scan_wallet(obj/item/spacecash/ewallet/E, mob/user)
	if(!transaction_amount || !ticket_is_valid())
		return

	if (cash_open)
		play_sfx(src, SFX_MACHINES_BUZZ_SIGH, 0.5)
		to_chat(user, "[icon2html(src, user.client)]" + span_warning("The cash box is open."))
		return

	if((item_list.len > 1 || item_list[item_list[1]] > 1) && !confirm(E))
		return

	// Access account for transaction
	if(check_account(user))
		if(transaction_amount > E.worth)
			src.visible_message("[icon2html(src,viewers(src))]" + span_warning("Not enough funds."))
		else
			// Transfer the money
			E.set_worth(E.worth - transaction_amount)
			linked_account.credit(transaction_amount, E.owner_name, transaction_purpose, machine_id, FALSE)

			SSsupply.create_service_external_invoice(linked_account, machine_id, item_list, price_list, E.owner_name, transaction_amount, "E-Wallet", verified_sale_items)

			// Confirm and reset
			transaction_complete()

/obj/machinery/cash_register/proc/scan_cash(obj/item/spacecash/SC, mob/user)
	if(!transaction_amount || !ticket_is_valid())
		return

	if (cash_open)
		play_sfx(src, SFX_MACHINES_BUZZ_SIGH, 0.5)
		to_chat(user, "[icon2html(src, user.client)]" + span_warning("The cash box is open."))
		return
	if(!check_account(user))
		return

	if((item_list.len > 1 || item_list[item_list[1]] > 1) && !confirm(SC))
		return

	if(transaction_amount > SC.worth)
		src.visible_message("[icon2html(src, viewers(src))]" + span_warning("Not enough money."))
	else
		// Insert cash into magical slot
		SC.set_worth(SC.worth - transaction_amount)
		if(!SC.worth)
			if(ishuman(SC.loc))
				var/mob/living/carbon/human/H = SC.loc
				H.drop_from_inventory(SC)
			consume(SC, user)
		// Save log
		// Department cash is deposited immediately so the invoice and account
		// books agree and any same-period refund has authoritative funding.
		linked_account.credit(transaction_amount, "Cash customer", transaction_purpose, machine_id, FALSE)
		SSsupply.create_service_external_invoice(linked_account, machine_id, item_list, price_list, "Cash customer", transaction_amount, "Cash", verified_sale_items)

		// Confirm and reset
		transaction_complete()

/obj/machinery/cash_register/proc/scan_item_price(obj/O, mob/user)
	if(!istype(O))	return
	if(length(item_list) >= 10 && !item_list[O.name])
		src.visible_message("[icon2html(src, viewers(src))]" + span_warning("Only up to ten different items allowed per purchase."))
		return
	if (cash_open)
		play_sfx(src, SFX_MACHINES_BUZZ_SIGH, 0.5)
		to_chat(user, "[icon2html(src, user.client)]" + span_warning("The cash box is open."))
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
	play_sfx(src, SFX_MACHINES_TWOBEEP, 0.5, vary = FALSE)

/obj/machinery/cash_register/proc/ticket_changed()
	ticket_revision++
	rel_clear(src, nameof(confirm_item))
	confirm_revision = 0

/obj/machinery/cash_register/proc/get_current_transaction()
	if(!length(item_list))
		return list()

	var/list/current_transactioon = list(
		"items" = item_list,
		"prices" = price_list,
		"amount" = transaction_amount,

	)
	return current_transactioon

/obj/machinery/cash_register/proc/add_transaction_log(c_name, p_method, t_amount, account_number = 0, list/service_result)
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

/obj/machinery/cash_register/proc/check_account(mob/user)
	if (!linked_account)
		user.visible_message("[icon2html(src, viewers(src))]" + span_warning("Unable to connect to linked account."))
		return FALSE

	if(linked_account.suspended)
		src.visible_message("[icon2html(src, viewers(src))]" + span_warning("Connected account has been suspended."))
		return FALSE
	return TRUE

/obj/machinery/cash_register/proc/capture_service_staff(mob/user)
	service_staff_account_number = 0
	service_staff_name = null
	if(!linked_account?.is_department_budget() || !user)
		return
	var/datum/money_account/staff_account = user.mind?.initial_account()
	if(!staff_account || department_for_mob(user) != linked_account.department_id)
		return
	service_staff_account_number = staff_account.account_number
	service_staff_name = user.real_name

/obj/machinery/cash_register/proc/rebuild_ticket()
	var/total = service_ticket_total(item_list, price_list)
	transaction_amount = isnull(total) ? 0 : total
	transaction_purpose = service_ticket_description(item_list, price_list)

/obj/machinery/cash_register/proc/ticket_is_valid()
	var/total = service_ticket_total(item_list, price_list)
	return !isnull(total) && total == transaction_amount

/obj/machinery/cash_register/proc/transaction_complete()
	/// Visible confirmation
	play_sfx(src, SFX_MACHINES_CHIME, 0.5, vary = FALSE)
	src.visible_message("[icon2html(src, viewers(src))]" + span_notice("Transaction complete."))
	flick("register_approve", src)
	reset_memory()

/obj/machinery/cash_register/proc/reset_memory()
	transaction_amount = null
	transaction_purpose = ""
	item_list.Cut()
	price_list.Cut()
	verified_sale_items = null
	service_staff_account_number = 0
	service_staff_name = null
	ticket_changed()

/obj/machinery/cash_register/proc/interaction_open_box_verb(datum/act/op/A)
	var/mob/user = A.actor
	open_cash_box(user)
	return TRUE

/obj/machinery/cash_register/proc/open_cash_box(mob/user)
	if(user.stat) return

	if(cash_open)
		cash_open = 0
		cut_overlay("register_approve")
		cut_overlay("register_open")
		cut_overlay("register_cash")
	else if(!cash_locked)
		cash_open = 1
		add_overlay("register_approve")
		add_overlay("register_open")
		if(cash_stored)
			add_overlay("register_cash")
	else
		to_chat(user, span_warning("The cash box is locked."))

/obj/machinery/cash_register/proc/toggle_anchors(obj/item/W, mob/user)
	if(task_busy(src)) return
	use_tool(user, W, src, delay = 2 SECONDS, volume = 50, start_self = anchored ? "You begin unsecuring \the [src] from the floor." : "You begin securing \the [src] to the floor.", start_others = anchored ? "\The [user] begins unsecuring \the [src] from the floor." : "\The [user] begins securing \the [src] to the floor.", receiver = src, on_done = PROC_REF(toggle_anchors_tool_done), done_args = list(user), claims = TRUE)
	return TRUE

/obj/machinery/cash_register/proc/toggle_anchors_tool_done(mob/user)
	if(!anchored)
		act_message(user, src, MSG_SELF(span_notice("You have secured %T% to the floor.")), MSG_OTHERS(span_notice("%U% has secured %T% to the floor.")))
	else
		act_message(user, src, MSG_SELF(span_notice("You have unsecured %T% from the floor.")), \
			MSG_OTHERS(span_warning("%U% has unsecured %T% from the floor.")))
	set_anchored(!anchored)
	return

/obj/machinery/cash_register/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, others = span_danger("%T%'s cash box springs open as %U% swipes the card through the scanner!"))
	play_sfx(src, SFX_SPARKS)
	req_access = list()
	set_emagged(1)
	set_locked(0)
	cash_locked = 0
	open_cash_box(user)
	return OP_OK

//--Premades--//

/obj/machinery/cash_register/command
	account_to_connect = "Command"

/obj/machinery/cash_register/medical
	account_to_connect = "Medical"

/obj/machinery/cash_register/engineering
	account_to_connect = "Engineering"

/obj/machinery/cash_register/science
	account_to_connect = DEPARTMENT_RESEARCH

/obj/machinery/cash_register/security
	account_to_connect = "Security"

/obj/machinery/cash_register/cargo
	account_to_connect = "Cargo"

/obj/machinery/cash_register/civilian
	account_to_connect = "Civilian"

/obj/machinery/cash_register/proc/checkout_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = checkout_apply(A)
	SStgui.update_uis(src)

/obj/machinery/cash_register/proc/checkout_apply(datum/act/request/A)
	var/datum/request/ask = A.answer
	if(istype(ask, /datum/prompt/number/service_checkout_pin))
		var/datum/prompt/number/service_checkout_pin/pin = ask
		pin.answers[pin.answer_key] = pin.value
		return scan_card_stage(pin.payer_card, pin.card_holder, pin.operator, pin.answers)
	var/datum/prompt/choice/service_checkout_tip/tip = ask
	tip.answers[tip.answer_key] = tip.value
	return scan_card_stage(tip.payer_card, tip.card_holder, tip.operator, tip.answers)
