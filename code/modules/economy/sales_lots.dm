/// Physical freight ledgers and crew-facing departmental storefronts share one
/// rule: the machine/crate holds the actual goods, while a small signed record
/// owns pricing and revenue routing. Item provenance verifies a claim; it never
/// silently chooses the payee.

/obj/item/paper/proc/void_shipping_ledger(reason)
	if(!islist(shipping_ledger_data) || !shipping_ledger_data["valid"])
		return FALSE
	shipping_ledger_data["valid"] = FALSE
	shipping_ledger_data["void_reason"] = reason
	shipping_ledger_data["void_time"] = stationtime2text()
	set_content("VOID FREIGHT LEDGER [shipping_ledger_data["id"]]\n\nReason: [reason]\nVoided: [shipping_ledger_data["void_time"]]\n\nThis document no longer authorizes revenue routing.", "VOID freight ledger [shipping_ledger_data["id"]]")
	return TRUE

/obj/structure/closet/crate/proc/void_shipping_ledger(reason)
	shipping_ledger?.void_shipping_ledger(reason)
	shipping_ledger = null
	shipping_ledger_snapshot = null

/obj/structure/closet/crate/proc/freight_snapshot()
	var/list/snapshot = list()
	latent_materialize_all() // the ledger records each real item (C5)
	for(var/atom/movable/cargo as anything in contents) // latent-ok
		if(istype(cargo, /obj/item/paper))
			var/obj/item/paper/document = cargo
			if(document.shipping_ledger_data)
				continue
		snapshot[REF(cargo)] = "[cargo.type]"
	return snapshot

/obj/structure/closet/crate/proc/shipping_ledger_valid()
	if(!shipping_ledger || shipping_ledger.loc != src || !islist(shipping_ledger.shipping_ledger_data) || !islist(shipping_ledger_snapshot))
		return FALSE
	var/list/data = shipping_ledger.shipping_ledger_data
	if(!data["valid"])
		return FALSE
	var/list/current_snapshot = freight_snapshot()
	if(length(current_snapshot) != length(shipping_ledger_snapshot))
		return FALSE
	for(var/cargo_ref in shipping_ledger_snapshot)
		if(current_snapshot[cargo_ref] != shipping_ledger_snapshot[cargo_ref])
			return FALSE
	var/producer_total = 0
	for(var/account_number in data["producer_percentages"])
		producer_total += data["producer_percentages"][account_number]
	return data["id"] && data["department"] && data["department_percent"] + data["cargo_percent"] + producer_total == 100

/obj/structure/closet/crate/proc/apply_shipping_ledger(datum/exported_crate/export)
	if(!shipping_ledger_valid())
		if(shipping_ledger)
			void_shipping_ledger("certified cargo changed")
		return FALSE
	var/list/data = shipping_ledger.shipping_ledger_data
	export.sales_ledger_id = data["id"]
	export.sales_ledger_valid = TRUE
	export.sales_department = data["department"]
	export.sales_destination = data["destination"]
	export.sales_department_percent = data["department_percent"]
	export.sales_cargo_percent = data["cargo_percent"]
	var/list/producer_percentages = data["producer_percentages"]
	export.sales_producer_percentages = producer_percentages?.Copy()
	return TRUE

/obj/item/retail_scanner/proc/freight_item_value(obj/item/item)
	if(item.economic_export_value > 0)
		return SSsupply.export_revenue(item.economic_export_value)
	var/value = SEND_SIGNAL(item, COMSIG_ITEM_SCAN_PROFIT)
	return isnum(value) ? max(0, SSsupply.export_revenue(value)) : 0

/proc/storefront_department_authorized(mob/living/user, department)
	if(!user || !department)
		return FALSE
	if(department_for_mob(user) == department)
		return TRUE
	var/obj/item/card/id/id_card = user.GetIdCard()
	return id_card && ((ACCESS_CAPTAIN in id_card.access) || (ACCESS_HOP in id_card.access) || (ACCESS_CENT_CAPTAIN in id_card.access))

/obj/item/retail_scanner/proc/certify_freight_crate(obj/structure/closet/crate/crate, mob/living/user)
	if(!crate || !user || crate.opened)
		to_chat(user, span_warning("The crate must be closed before certification."))
		return FALSE
	if(locked || !linked_account?.is_department_budget() || !storefront_department_authorized(user, linked_account.department_id))
		to_chat(user, span_warning("Unlock and link this scanner to a department you are authorized to represent."))
		return FALSE
	if(!length(freight_form_paper))
		to_chat(user, span_warning("The freight printer has no blank paper loaded."))
		return FALSE
	var/department = linked_account.department_id
	var/total_value = 0
	var/eligible_value = 0
	var/list/ineligible = list()
	var/list/producer_values = list()
	for(var/obj/item/cargo as anything in crate.contents)
		if(istype(cargo, /obj/item/paper))
			var/obj/item/paper/document = cargo
			if(document.shipping_ledger_data)
				continue
		var/value = freight_item_value(cargo)
		total_value += value
		if(cargo.economic_department != department)
			ineligible += "[cargo.name] ([cargo.economic_department || "unattributed"])"
			continue
		eligible_value += value
		if(cargo.economic_producer_account && value > 0)
			var/producer_key = "[cargo.economic_producer_account]"
			producer_values[producer_key] = (producer_values[producer_key] || 0) + value
	if(!eligible_value)
		to_chat(user, span_warning("No [department]-origin goods in this crate qualify for ledger routing."))
		return FALSE
	var/preview = "Estimated gross value: [total_value] Th\nEligible [department] value: [eligible_value] Th"
	if(length(ineligible))
		preview += "\nUncredited cargo: [jointext(ineligible, ", ")]"
	if(length(producer_values))
		preview += "\nDetected contributors: [length(producer_values)]"
	if(tgui_alert(user, preview, "Freight valuation", list("Continue", "Cancel")) != "Continue" || crate.opened || get_dist(src, crate) > 1)
		return FALSE
	var/destination = stripped_input(user, "Who is this shipment consigned to?", "Freight ledger", "External buyer", 80)
	if(!destination || crate.opened || get_dist(src, crate) > 1)
		return FALSE
	var/list/producer_percentages = list()
	if(length(producer_values))
		var/allocation_choice = tgui_alert(user, "Suggested producer pool: 5% divided by authenticated contribution value. Cargo always receives 20%.", "Producer allocation", list("Use suggested", "Edit shares", "No producer share", "Cancel"))
		if(allocation_choice == "Cancel")
			return FALSE
		if(allocation_choice == "Use suggested")
			var/remaining = 5
			var/index = 0
			for(var/account_number in producer_values)
				index++
				var/share = index == length(producer_values) ? remaining : round(5 * producer_values[account_number] / eligible_value, 0.1)
				share = min(remaining, max(0, share))
				producer_percentages[account_number] = share
				remaining -= share
		else if(allocation_choice == "Edit shares")
			var/allocated = 0
			for(var/account_number in producer_values)
				var/datum/money_account/producer = get_account(text2num(account_number))
				var/share = tgui_input_number(user, "Percentage for [producer?.owner_name || "account [account_number]"] (maximum remaining: [20 - allocated]%)", "Producer allocation", 0, 20 - allocated, 0)
				if(isnull(share) || crate.opened || get_dist(src, crate) > 1)
					return FALSE
				share = round(CLAMP(share, 0, 20 - allocated), 0.1)
				if(share)
					producer_percentages[account_number] = share
					allocated += share
	var/producer_total = 0
	var/list/producer_rows = list()
	for(var/account_number in producer_percentages)
		var/share = producer_percentages[account_number]
		producer_total += share
		var/datum/money_account/producer = get_account(text2num(account_number))
		producer_rows += "[producer?.owner_name || "Account [account_number]"]: [share]%"
	var/department_percent = 80 - producer_total
	var/final_summary = "Consignee: [destination]\n[department]: [department_percent]%\nCargo: 20%"
	if(length(producer_rows))
		final_summary += "\n[jointext(producer_rows, "\n")]"
	if(tgui_alert(user, final_summary, "Print freight ledger?", list("Print", "Cancel")) != "Print" || crate.opened || get_dist(src, crate) > 1)
		return FALSE
	crate.void_shipping_ledger("superseded by scanner certification")
	var/obj/item/paper/ledger = freight_form_paper[length(freight_form_paper)]
	freight_form_paper -= ledger
	ledger.forceMove(crate)
	var/ledger_id = "FL-[stationtime2text()]-[rand(1000, 9999)]"
	ledger.shipping_ledger_data = list("id" = ledger_id, "valid" = TRUE, "department" = department, "destination" = destination, "department_percent" = department_percent, "cargo_percent" = 20, "producer_percentages" = producer_percentages.Copy(), "sealed_by" = user.real_name, "scanner" = machine_id)
	ledger.set_content("FREIGHT LEDGER [ledger_id]\n\nConsignor: [department]\nConsignee: [destination]\nCertified by: [user.real_name]\nScanner: [machine_id]\nEstimated eligible value: [eligible_value] Th\n\nRevenue: [department_percent]% [department], 20% Cargo[length(producer_rows) ? ", [jointext(producer_rows, "; ")]" : ""].\n\nOpening or changing the certified crate voids this document.", "freight ledger [ledger_id]")
	crate.shipping_ledger = ledger
	crate.shipping_ledger_snapshot = crate.freight_snapshot()
	playsound(src, 'sound/machines/chime.ogg', 25)
	to_chat(user, span_notice("[src] prints [ledger] into [crate] and seals its authenticated cargo snapshot."))
	return TRUE

/obj/machinery/department_storefront
	name = "departmental storefront"
	desc = "A secure, crew-stocked storefront. It prices and sells the actual goods placed inside it."
	icon = 'icons/obj/vending.dmi'
	icon_state = "generic"
	anchored = TRUE
	density = FALSE
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 100
	var/department_id = DEPARTMENT_CIVILIAN
	var/markup_percent = 25
	var/machine_id
	var/list/stock_prices
	var/list/stock_suggested_prices
	var/list/stock_stocker_accounts

/obj/machinery/department_storefront/Initialize(mapload)
	. = ..()
	machine_id = "[station_name()] STOREFRONT #[GLOB.num_financial_terminals++]"
	stock_prices = list()
	stock_suggested_prices = list()
	stock_stocker_accounts = list()

/obj/machinery/department_storefront/Destroy()
	stock_prices = null
	stock_suggested_prices = null
	stock_stocker_accounts = null
	return ..()

/obj/machinery/department_storefront/examine(mob/user)
	. = ..()
	. += "It deposits revenue into the [department_id] budget. Department staff can stock it by using an item on it."

/obj/machinery/department_storefront/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/storefront_id_fallthrough,
		/datum/interaction/machine_item/storefront_stock,
		/datum/interaction/machine_hand/ungated/open_ui,
	)
	..()

/// The old attackby's leading branch: an ID card always fell through to ..().
/datum/interaction/machine_item/storefront_id_fallthrough
	id = "storefront_id_fallthrough"
	name = "Use"
	held_type = /obj/item/card/id
	effect = /obj/machinery/department_storefront/proc/interaction_id_fallthrough

/obj/machinery/department_storefront/proc/interaction_id_fallthrough(mob/user, obj/item/item, datum/interaction/interaction)
	return FALSE

/// The old attackby: stocks the storefront with an offered item.
/datum/interaction/machine_item/storefront_stock
	id = "storefront_stock"
	name = "Stock"
	category = INTERACTION_CAT_INSERT
	held_type = /obj/item
	effect = /obj/machinery/department_storefront/proc/interaction_stock

/obj/machinery/department_storefront/proc/interaction_stock(mob/user, obj/item/item, datum/interaction/interaction)
	if(!storefront_staff_authorized(user))
		to_chat(user, span_warning("Only [department_id] staff may stock this storefront."))
		return TRUE
	if(item.anchored || istype(item, /obj/item/paper) || istype(item, /obj/item/card/id))
		to_chat(user, span_warning("[item] cannot be offered through this storefront."))
		return TRUE
	var/suggested = storefront_suggested_price(item)
	var/price = max(1, round(suggested * (100 + markup_percent) / 100))
	if(!user.drop_from_inventory(item, src))
		to_chat(user, span_warning("You cannot release [item] into the storefront."))
		return TRUE
	item.forceMove(src)
	var/item_ref = REF(item)
	stock_suggested_prices[item_ref] = suggested
	stock_prices[item_ref] = price
	stock_stocker_accounts[item_ref] = user.mind?.initial_account?.account_number || 0
	to_chat(user, span_notice("You stock [item] at [price] Thalers (suggested [suggested])."))
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/department_storefront/proc/storefront_staff_authorized(mob/living/user)
	return storefront_department_authorized(user, department_id)

/obj/machinery/department_storefront/proc/storefront_suggested_price(obj/item/item)
	if(item.economic_export_value > 0)
		return max(1, SSsupply.export_revenue(item.economic_export_value))
	return max(5, round(item.w_class * 5))

/obj/machinery/department_storefront/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "DepartmentStorefront", name)
		ui.open()

/obj/machinery/department_storefront/tgui_data(mob/user)
	var/list/stock = list()
	var/list/rows_by_key = list()
	for(var/obj/item/item as anything in contents)
		var/item_ref = REF(item)
		var/listing_key = "[item.type]|[stock_prices[item_ref]]"
		var/list/row = rows_by_key[listing_key]
		if(row)
			row["quantity"]++
			continue
		row = list(
			"ref" = item_ref,
			"name" = item.name,
			"desc" = item.desc,
			"suggested" = stock_suggested_prices[item_ref],
			"price" = stock_prices[item_ref],
			"quantity" = 1,
		)
		rows_by_key[listing_key] = row
		stock.Add(list(row))
	var/datum/money_account/account = GLOB.department_accounts[department_id]
	return list(
		"department" = department_id,
		"balance" = account?.money || 0,
		"markup" = markup_percent,
		"authorized" = storefront_staff_authorized(user),
		"stock" = stock,
	)

/obj/machinery/department_storefront/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return
	var/item_ref = params["ref"]
	var/obj/item/item = locate(item_ref) in contents
	switch(action)
		if("buy")
			return storefront_purchase(item, ui.user)
		if("withdraw")
			if(!item || !storefront_staff_authorized(ui.user))
				return FALSE
			storefront_forget_item(item)
			item.forceMove(get_turf(src))
			ui.user.put_in_hands(item)
			return TRUE
		if("set_price")
			if(!item || !storefront_staff_authorized(ui.user))
				return FALSE
			var/new_price = text2num(params["price"])
			if(!isnum(new_price) || new_price < 1 || new_price > 100000)
				return FALSE
			var/old_price = stock_prices[item_ref]
			for(var/obj/item/matching_item as anything in contents)
				var/matching_ref = REF(matching_item)
				if(matching_item.type == item.type && stock_prices[matching_ref] == old_price)
					stock_prices[matching_ref] = round(new_price)
			return TRUE
		if("set_markup")
			if(!storefront_staff_authorized(ui.user))
				return FALSE
			var/new_markup = text2num(params["markup"])
			if(!isnum(new_markup) || new_markup < -90 || new_markup > 500)
				return FALSE
			markup_percent = round(new_markup)
			for(var/obj/item/stock_item as anything in contents)
				var/stock_ref = REF(stock_item)
				stock_prices[stock_ref] = max(1, round(stock_suggested_prices[stock_ref] * (100 + markup_percent) / 100))
			return TRUE
	return FALSE

/obj/machinery/department_storefront/proc/storefront_purchase(obj/item/item, mob/living/user)
	if(!item || !user || get_dist(src, user) > 1 || src.z != user.z)
		return FALSE
	var/obj/item/card/id/id_card = user.GetIdCard()
	var/datum/money_account/customer = get_account(id_card?.associated_account_number)
	var/datum/money_account/provider = GLOB.department_accounts[department_id]
	var/item_ref = REF(item)
	var/price = stock_prices[item_ref]
	if(!customer || !provider || !isnum(price) || price <= 0 || customer == provider)
		to_chat(user, span_warning("The sale could not be authorized."))
		return FALSE
	if(customer.security_level)
		var/attempt_pin = tgui_input_number(user, "Enter your account PIN", "Storefront purchase")
		if(QDELETED(item) || item.loc != src || stock_prices[item_ref] != price || get_dist(src, user) > 1 || src.z != user.z)
			return FALSE
		customer = attempt_account_access(id_card.associated_account_number, attempt_pin, 2)
		if(!customer)
			to_chat(user, span_warning("The account PIN was rejected."))
			return FALSE
	var/list/items = list()
	var/list/prices = list()
	var/list/verified = list()
	items[item.name] = 1
	prices[item.name] = price
	verified[item] = price
	var/list/quote = department_service_quote(customer, department_id, price)
	if(!quote)
		to_chat(user, span_warning("Your account cannot cover this purchase."))
		return FALSE
	var/list/result = list()
	if(!charge_department_service(customer, department_id, price, "Storefront purchase: [item.name]", machine_id, result))
		return FALSE
	var/datum/service_invoice/invoice = SSsupply.create_service_invoice(customer, provider, machine_id, items, prices, result, stock_stocker_accounts[item_ref], null, null, "ID account", verified)
	if(!invoice)
		// The charge was valid but evidence creation should never strand the item.
		// Record it as an ordinary sale and deliver the purchased good.
		log_game("Storefront [machine_id] completed payment but could not create an invoice for [item].")
	storefront_forget_item(item)
	item.forceMove(get_turf(src))
	user.put_in_hands(item)
	playsound(src, 'sound/machines/chime.ogg', 25)
	return TRUE

/obj/machinery/department_storefront/proc/storefront_forget_item(obj/item/item)
	var/item_ref = REF(item)
	stock_prices -= item_ref
	stock_suggested_prices -= item_ref
	stock_stocker_accounts -= item_ref

/obj/machinery/department_storefront/research
	name = "research storefront"
	desc = "A secure storefront for crew-purchased prototypes and Research products."
	department_id = DEPARTMENT_RESEARCH

/obj/machinery/department_storefront/cargo
	name = "cargo storefront"
	desc = "A secure storefront for crew-purchased freight and Cargo stock."
	department_id = DEPARTMENT_CARGO

/obj/machinery/department_storefront/service
	name = "service storefront"
	department_id = DEPARTMENT_CIVILIAN

/obj/machinery/department_storefront/medical
	name = "medical storefront"
	department_id = DEPARTMENT_MEDICAL

/obj/machinery/department_storefront/engineering
	name = "engineering storefront"
	department_id = DEPARTMENT_ENGINEERING

/obj/machinery/department_storefront/security
	name = "security storefront"
	department_id = DEPARTMENT_SECURITY

/obj/machinery/department_storefront/command
	name = "command storefront"
	department_id = DEPARTMENT_COMMAND
