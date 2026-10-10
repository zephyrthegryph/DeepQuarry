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
	rel_take(src, nameof(shipping_ledger))
	shipping_ledger_snapshot = null

/obj/structure/closet/crate/proc/freight_snapshot()
	var/list/snapshot = list()
	latent_materialize_all() // the ledger records each real item (C5)
	for(var/atom/movable/cargo as anything in contents) // ALLOW(latent): walk reviewed: reads what is materialized on purpose
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
	var/value = item.scan_profit()
	return isnum(value) ? max(0, SSsupply.export_revenue(value)) : 0

/proc/storefront_department_authorized(mob/living/user, department)
	READS_FROM(user) // the actor's job and the access on their card, read when the op is tried
	if(!user || !department)
		return FALSE
	if(department_for_mob(user) == department)
		return TRUE
	var/obj/item/card/id/id_card = user.GetIdCard()
	return id_card && ((ACCESS_CAPTAIN in id_card.access) || (ACCESS_HOP in id_card.access) || (ACCESS_CENT_CAPTAIN in id_card.access))

/obj/item/retail_scanner/proc/certify_freight_crate(obj/structure/closet/crate/crate, mob/living/user)
	return certify_freight_stage(crate, user, list())

/obj/item/retail_scanner/proc/certify_freight_stage(obj/structure/closet/crate/crate, mob/living/user, list/freight_answers)
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
	for(var/obj/item/cargo as anything in contents_of(crate))
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
	// Each answer re-runs this certification with every check above made again.
	var/go_on = freight_answers["value"]
	if(isnull(go_on))
		open_request(src, /datum/prompt/choice/freight_certification, PROC_REF(freight_certification_answered), answerer = user, shipment = crate, freight_answers = freight_answers, answer_key = "value", question = preview, title = "Freight valuation", choices = list("Continue", "Cancel"))
		return FALSE
	if(go_on != "Continue" || crate.opened || get_dist(src, crate) > 1)
		return FALSE
	var/destination = freight_answers["destination"]
	if(isnull(destination))
		open_request(src, /datum/prompt/text/freight_certification, PROC_REF(freight_certification_answered), answerer = user, shipment = crate, freight_answers = freight_answers, answer_key = "destination", question = "Who is this shipment consigned to?", title = "Freight ledger", default = "External buyer")
		return FALSE
	destination = trim(destination, 80)
	if(!destination || crate.opened || get_dist(src, crate) > 1)
		return FALSE
	var/list/producer_percentages = list()
	if(length(producer_values))
		var/allocation_choice = freight_answers["allocation"]
		if(isnull(allocation_choice))
			open_request(src, /datum/prompt/choice/freight_certification, PROC_REF(freight_certification_answered), answerer = user, shipment = crate, freight_answers = freight_answers, answer_key = "allocation", question = "Suggested producer pool: 5% divided by authenticated contribution value. Cargo always receives 20%.", title = "Producer allocation", choices = list("Use suggested", "Edit shares", "No producer share", "Cancel"))
			return FALSE
		if(isnull(allocation_choice) || allocation_choice == "Cancel")
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
				var/share = freight_answers["share[account_number]"]
				if(isnull(share))
					open_request(src, /datum/prompt/number/freight_certification, PROC_REF(freight_certification_answered), answerer = user, shipment = crate, freight_answers = freight_answers, answer_key = "share[account_number]", question = "Percentage for [producer?.owner_name || "account [account_number]"] (maximum remaining: [20 - allocated]%)", title = "Producer allocation", default = 0, max_value = 20 - allocated)
					return FALSE
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
	var/print_answer = freight_answers["print"]
	if(isnull(print_answer))
		open_request(src, /datum/prompt/choice/freight_certification, PROC_REF(freight_certification_answered), answerer = user, shipment = crate, freight_answers = freight_answers, answer_key = "print", question = final_summary, title = "Print freight ledger?", choices = list("Print", "Cancel"))
		return FALSE
	if(print_answer != "Print" || crate.opened || get_dist(src, crate) > 1)
		return FALSE
	if(!length(freight_form_paper))
		return FALSE
	crate.void_shipping_ledger("superseded by scanner certification")
	var/obj/item/paper/ledger = freight_form_paper[length(freight_form_paper)]
	rel_remove(src, nameof(src.freight_form_paper), ledger)
	move_into(crate, nameof(crate.shipping_ledger), ledger, force = TRUE) // printed into the crate, full or not
	var/ledger_id = "FL-[stationtime2text()]-[rand(1000, 9999)]"
	ledger.shipping_ledger_data = list("id" = ledger_id, "valid" = TRUE, "department" = department, "destination" = destination, "department_percent" = department_percent, "cargo_percent" = 20, "producer_percentages" = producer_percentages.Copy(), "sealed_by" = user.real_name, "scanner" = machine_id)
	ledger.set_content("FREIGHT LEDGER [ledger_id]\n\nConsignor: [department]\nConsignee: [destination]\nCertified by: [user.real_name]\nScanner: [machine_id]\nEstimated eligible value: [eligible_value] Th\n\nRevenue: [department_percent]% [department], 20% Cargo[length(producer_rows) ? ", [jointext(producer_rows, "; ")]" : ""].\n\nOpening or changing the certified crate voids this document.", "freight ledger [ledger_id]")
	crate.shipping_ledger_snapshot = crate.freight_snapshot()
	play_sfx(src, SFX_MACHINES_CHIME, 0.5, vary = FALSE)
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

TRACKED(/obj/machinery/department_storefront, department_id)

/obj/machinery/department_storefront/proc/set_up_storefront(datum/act/timer/A)
	machine_id = "[station_name()] STOREFRONT #[GLOB.num_financial_terminals++]"
	stock_prices = list()
	stock_suggested_prices = list()
	stock_stocker_accounts = list()

/obj/machinery/department_storefront/examine(mob/user)
	. = ..()
	. += "It deposits revenue into the [department_id] budget. Department staff can stock it by using an item on it."

/// Requirement (was REQ_* can_stock): the legacy check answers TRUE to pass.
/obj/machinery/department_storefront/proc/can_stock_holds(datum/act/op/A)
	var/answer = can_stock(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_stock_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/department_storefront/proc/can_stock_refusal(datum/act/op/A)
	var/answer = can_stock(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/machinery/department_storefront/proc/interaction_id_fallthrough(datum/act/op/A)
	return OP_DECLINE

/// Requirement: TRUE, or why this item can't be stocked by this user.
/obj/machinery/department_storefront/proc/can_stock(mob/user, atom/target, obj/item/held)
	if(!storefront_staff_authorized(user))
		return "only [department_id] staff may stock this storefront"
	if(held.anchored || istype(held, /obj/item/paper) || istype(held, /obj/item/card/id))
		return "[held] cannot be offered through this storefront"
	return TRUE

/obj/machinery/department_storefront/proc/interaction_stock(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/item = A.held
	var/suggested = storefront_suggested_price(item)
	var/price = max(1, round(suggested * (100 + markup_percent) / 100))
	if(!user.drop_from_inventory(item, src))
		to_chat(user, span_warning("You cannot release [item] into the storefront."))
		return OP_OK
	item.forceMove(src)
	var/item_ref = REF(item)
	stock_suggested_prices[item_ref] = suggested
	stock_prices[item_ref] = price
	stock_stocker_accounts[item_ref] = user.mind?.initial_account()?.account_number || 0
	to_chat(user, span_notice("You stock [item] at [price] Thalers (suggested [suggested])."))
	SStgui.update_uis(src)
	return OP_OK

/obj/machinery/department_storefront/proc/storefront_staff_authorized(mob/living/user)
	return storefront_department_authorized(user, department_id)

/obj/machinery/department_storefront/proc/storefront_suggested_price(obj/item/item)
	if(item.economic_export_value > 0)
		return max(1, SSsupply.export_revenue(item.economic_export_value))
	return max(5, round(item.w_class * 5))

CAPABILITIES(/obj/machinery/department_storefront)
	after_init(0, then(PROC_REF(set_up_storefront)))
	interface("DepartmentStorefront")
	without("ui_open")
	op("buy", ui_act("buy", arg("ref", schema_ref(/obj/item))), then(PROC_REF(ui_act_buy)))
	op("withdraw", ui_act("withdraw", arg("ref", schema_ref(/obj/item))), then(PROC_REF(ui_act_withdraw)))
	op("set_price", ui_act("set_price", arg("price", num()), arg("ref", schema_ref(/obj/item))), then(PROC_REF(ui_act_set_price)))
	op("set_markup", ui_act("set_markup", arg("markup", num())), then(PROC_REF(ui_act_set_markup)))
	op("storefront_id_fallthrough", item(/obj/item/card/id), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_id_fallthrough)))
	op("storefront_stock", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Stock"), needs(req(PROC_REF(can_stock_holds), because = PROC_REF(can_stock_refusal))), then(PROC_REF(interaction_stock)))

/// /obj/machinery/department_storefront's window data.
/obj/machinery/department_storefront/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/stock = list()
	var/list/rows_by_key = list()
	// Listing never materializes (systems.md §18): stock is placed real by the stocking action.
	FOR_REAL_CONTENTS(var/obj/item/item as anything, src)
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

/obj/machinery/department_storefront/proc/ui_gate(datum/act/op/A)
	latent_materialize_all() // a walk needs real things (C5)
	return TRUE

/obj/machinery/department_storefront/proc/ui_act_buy(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in contents_of(src)))
		return FALSE
	if(isnull(ref))
		return FALSE
	var/obj/item/item = ref // latent contents are materialized by ui_act_allowed()
	return storefront_purchase(item, user)

/obj/machinery/department_storefront/proc/ui_act_withdraw(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in contents_of(src)))
		return FALSE
	var/obj/item/item = ref // latent contents are materialized by ui_act_allowed()
	if(!item || !storefront_staff_authorized(user))
		return FALSE
	storefront_forget_item(item)
	item.forceMove(get_turf(src))
	user.put_in_hands(item)
	return TRUE

/obj/machinery/department_storefront/proc/ui_act_set_price(datum/act/op/A, price, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!isnull(ref) && !(ref in contents_of(src)))
		return FALSE
	var/obj/item/item = ref // latent contents are materialized by ui_act_allowed()
	var/item_ref = item ? REF(item) : null
	if(!item || !storefront_staff_authorized(user))
		return FALSE
	var/new_price = price
	if(!isnum(new_price) || new_price < 1 || new_price > 100000)
		return FALSE
	var/old_price = stock_prices[item_ref]
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/matching_item as anything in contents) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		var/matching_ref = REF(matching_item)
		if(matching_item.type == item.type && stock_prices[matching_ref] == old_price)
			stock_prices[matching_ref] = round(new_price)
	return TRUE

/obj/machinery/department_storefront/proc/ui_act_set_markup(datum/act/op/A, markup)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!storefront_staff_authorized(user))
		return FALSE
	var/new_markup = markup
	if(!isnum(new_markup) || new_markup < -90 || new_markup > 500)
		return FALSE
	markup_percent = round(new_markup)
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/stock_item as anything in contents) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		var/stock_ref = REF(stock_item)
		stock_prices[stock_ref] = max(1, round(stock_suggested_prices[stock_ref] * (100 + markup_percent) / 100))
	return TRUE

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
		// Keyed by the price, so a price change asks again.
		var/attempt_pin = rerun_ask(user, "pin[item_ref]:[price]", PROC_REF(storefront_purchase), args, /datum/prompt/number, question = "Enter your account PIN", title = "Storefront purchase")
		if(isnull(attempt_pin))
			return FALSE
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
	play_sfx(src, SFX_MACHINES_CHIME, 0.5, vary = FALSE)
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

/datum/prompt/choice/freight_certification
	timeout = 0
	buttons = TRUE
	var/obj/structure/closet/crate/shipment
	var/list/freight_answers
	var/answer_key
	var/shipment_expected = FALSE

CAPABILITIES(/datum/prompt/choice/freight_certification)
	ref_one(nameof(shipment), /obj/structure/closet/crate)

/datum/prompt/choice/freight_certification/prepare(datum/act/A)
	. = ..()
	var/obj/structure/closet/crate/captured_shipment = shipment
	shipment_expected = !isnull(captured_shipment)
	rel_clear(src, nameof(shipment))
	if(captured_shipment && !QDELETED(captured_shipment))
		rel_set(src, nameof(shipment), captured_shipment)

/datum/prompt/choice/freight_certification/recheck_extra()
	. = ..()
	if(.)
		return
	if(shipment_expected && QDELETED(shipment))
		return "gone"

/datum/prompt/text/freight_certification
	timeout = 0
	max_len = 80
	var/obj/structure/closet/crate/shipment
	var/list/freight_answers
	var/answer_key
	var/shipment_expected = FALSE

CAPABILITIES(/datum/prompt/text/freight_certification)
	ref_one(nameof(shipment), /obj/structure/closet/crate)

/datum/prompt/text/freight_certification/prepare(datum/act/A)
	. = ..()
	var/obj/structure/closet/crate/captured_shipment = shipment
	shipment_expected = !isnull(captured_shipment)
	rel_clear(src, nameof(shipment))
	if(captured_shipment && !QDELETED(captured_shipment))
		rel_set(src, nameof(shipment), captured_shipment)

/datum/prompt/text/freight_certification/recheck_extra()
	. = ..()
	if(.)
		return
	if(shipment_expected && QDELETED(shipment))
		return "gone"

/datum/prompt/number/freight_certification
	timeout = 0
	min_value = 0
	var/obj/structure/closet/crate/shipment
	var/list/freight_answers
	var/answer_key
	var/shipment_expected = FALSE

CAPABILITIES(/datum/prompt/number/freight_certification)
	ref_one(nameof(shipment), /obj/structure/closet/crate)

/datum/prompt/number/freight_certification/prepare(datum/act/A)
	. = ..()
	var/obj/structure/closet/crate/captured_shipment = shipment
	shipment_expected = !isnull(captured_shipment)
	rel_clear(src, nameof(shipment))
	if(captured_shipment && !QDELETED(captured_shipment))
		rel_set(src, nameof(shipment), captured_shipment)

/datum/prompt/number/freight_certification/recheck_extra()
	. = ..()
	if(.)
		return
	if(shipment_expected && QDELETED(shipment))
		return "gone"

/datum/prompt/number/freight_certification/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, isnull(max_value) ? INFINITY : max_value, isnull(min_value) ? 0 : min_value, timeout, FALSE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/obj/item/retail_scanner/proc/freight_certification_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = freight_certification_apply(A)
	SStgui.update_uis(src)
	return .

/obj/item/retail_scanner/proc/freight_certification_apply(datum/act/request/A)
	var/obj/structure/closet/crate/shipment
	var/list/freight_answers
	var/answer_key
	if(istype(A.answer, /datum/prompt/choice/freight_certification))
		var/datum/prompt/choice/freight_certification/ask = A.answer
		shipment = ask.shipment
		freight_answers = ask.freight_answers
		answer_key = ask.answer_key
	else if(istype(A.answer, /datum/prompt/text/freight_certification))
		var/datum/prompt/text/freight_certification/ask = A.answer
		shipment = ask.shipment
		freight_answers = ask.freight_answers
		answer_key = ask.answer_key
	else
		var/datum/prompt/number/freight_certification/ask = A.answer
		shipment = ask.shipment
		freight_answers = ask.freight_answers
		answer_key = ask.answer_key
	freight_answers[answer_key] = A.answer.value
	return certify_freight_stage(shipment, A.request.answerer, freight_answers)
