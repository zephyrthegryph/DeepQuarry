#define SERVICE_INVOICE_PAID "Paid"
#define SERVICE_INVOICE_REFUNDED "Refunded"

/// Recompute rather than incrementally trusting a checkout's displayed total.
/// A malformed ticket has no payable total.
/proc/service_ticket_total(list/items, list/prices)
	if(!islist(items) || !islist(prices))
		return null
	var/total = 0
	for(var/item_name in items)
		var/amount = items[item_name]
		var/price = prices[item_name]
		if(!isnum(amount) || amount <= 0 || !isnum(price) || price < 0)
			return null
		total += amount * price
	return round(total)

/// Canonical human-readable form of the exact item rows used to compute a
/// service charge. Item labels are encoded before entering browser/log HTML.
/proc/service_ticket_description(list/items, list/prices)
	var/list/rows = list()
	for(var/item_name in items)
		var/amount = items[item_name]
		var/price = prices[item_name]
		var/safe_name = html_encode("[item_name]")
		var/quantity_text = amount > 1 ? " x[amount]" : ""
		rows += "[safe_name][quantity_text]: [amount * price] Thaler\\s"
	return jointext(rows, "<br>")

/// Validate the complete financial split supplied by a checkout backend. The
/// invoice ledger never trusts a caller-provided total without also proving
/// that every subsidy, personal-payment, and gratuity component reconciles.
/proc/service_checkout_result_valid(list/result, canonical_total)
	if(!islist(result) || !isnum(canonical_total) || canonical_total < 0)
		return FALSE
	for(var/field in list("total", "subsidy", "personal"))
		if(!isnum(result[field]) || result[field] < 0)
			return FALSE
	if(result["total"] != canonical_total || result["subsidy"] + result["personal"] != canonical_total)
		return FALSE
	for(var/field in list("tip", "staff_tip", "service_tip"))
		if(!isnull(result[field]) && (!isnum(result[field]) || result[field] < 0))
			return FALSE
	var/tip = result["tip"] || 0
	var/staff_tip = result["staff_tip"] || 0
	var/service_tip = result["service_tip"] || 0
	if(staff_tip + service_tip != tip)
		return FALSE
	return TRUE

/// Refunds are provider-side financial operations. Ordinary department staff
/// may correct their own sales; Command finance access can intervene station-wide.
/proc/service_refund_authorized(mob/living/user, datum/money_account/provider)
	if(!ishuman(user) || !provider?.is_department_budget())
		return FALSE
	if(department_for_mob(user) == provider.department_id)
		return TRUE
	var/obj/item/card/id/id_card = user.GetIdCard()
	return id_card && ((ACCESS_CAPTAIN in id_card.access) || (ACCESS_HOP in id_card.access) || (ACCESS_CENT_CAPTAIN in id_card.access))

/datum/service_invoice
	var/id = 0
	var/state = SERVICE_INVOICE_PAID
	var/customer_account_number = 0
	var/customer_name
	var/provider_department = DEPARTMENT_CIVILIAN
	var/provider_account_number = 0
	var/terminal_id
	var/payment_method = "ID account"
	var/staff_account_number = 0
	var/staff_name
	var/list/items
	var/list/prices
	var/amount = 0
	var/subsidy = 0
	var/personal = 0
	var/tip = 0
	var/staff_tip = 0
	var/service_tip = 0
	var/created_date
	var/created_time
	var/accounting_period = 0
	var/refund_time
	var/refund_by
	var/refund_accounting_period = 0
	var/contract_revision = 1
	/// Physical, scanner-verified merchandise attached to this checkout.
	var/verified_amount = 0
	var/verified_item_count = 0
	var/list/verified_item_types
	var/list/verified_items
	/// Closed accounting periods are final evidence and cannot be refunded.
	var/settled = FALSE

/datum/service_invoice/Destroy()
	items = null
	prices = null
	verified_item_types = null
	verified_items = null
	return ..()

/datum/service_invoice/proc/as_row()
	return list(
		"invoice_id" = id,
		"log_id" = id,
		"state" = state,
		"customer" = customer_name,
		"payment_method" = payment_method,
		"trans_time" = created_time,
		"trans_date" = created_date,
		"terminal" = terminal_id,
		"staff" = staff_name,
		"items" = items,
		"prices" = prices,
		"amount" = amount,
		"subsidy" = subsidy,
		"personal" = personal,
		"tip" = tip,
		"staff_tip" = staff_tip,
		"service_tip" = service_tip,
		"refunded" = state == SERVICE_INVOICE_REFUNDED,
		"refund_time" = refund_time,
		"refund_by" = refund_by,
		"refundable" = state == SERVICE_INVOICE_PAID && !settled && accounting_period == SSsupply.service_accounting_period,
		"verified_amount" = verified_amount,
		"verified_item_count" = verified_item_count,
	)

/datum/controller/subsystem/supply/proc/create_service_invoice(datum/money_account/customer, datum/money_account/provider, terminal_id, list/items, list/prices, list/result, staff_account_number, staff_name, customer_name_override, payment_method = "ID account", list/verified_sale_items)
	if(!provider || !result || (!customer && !customer_name_override))
		return
	var/canonical_total = service_ticket_total(items, prices)
	if(isnull(canonical_total) || !service_checkout_result_valid(result, canonical_total))
		return
	var/datum/service_invoice/invoice = new
	invoice.id = ++service_invoice_counter
	invoice.customer_account_number = customer?.account_number || 0
	invoice.customer_name = customer?.owner_name || customer_name_override
	invoice.provider_department = provider.department_id
	invoice.provider_account_number = provider.account_number
	invoice.terminal_id = terminal_id
	invoice.payment_method = payment_method
	invoice.staff_account_number = staff_account_number
	invoice.staff_name = staff_name || "Unassigned Service staff"
	invoice.items = items?.Copy() || list()
	invoice.prices = prices?.Copy() || list()
	invoice.amount = result["total"] + (result["tip"] || 0)
	invoice.subsidy = result["subsidy"] || 0
	invoice.personal = result["personal"] || 0
	invoice.tip = result["tip"] || 0
	invoice.staff_tip = result["staff_tip"] || 0
	invoice.service_tip = result["service_tip"] || 0
	invoice.created_date = GLOB.current_date_string
	invoice.created_time = stationtime2text()
	invoice.accounting_period = service_accounting_period
	invoice.verified_item_types = list()
	invoice.verified_items = list()
	// Research credit requires Research provenance. Cargo credit represents its
	// ordinary retail/stock-handling role, so any real scanned item is eligible.
	var/list/remaining_by_name = items?.Copy() || list()
	var/remaining_personal_payment = max(0, invoice.personal)
	for(var/obj/sale_item as anything in verified_sale_items)
		if(QDELETED(sale_item) || sale_item.economic_sale_invoice_id || !remaining_by_name[sale_item.name] || remaining_personal_payment <= 0)
			continue
		if(!(provider.department_id in list(DEPARTMENT_CARGO, DEPARTMENT_CIVILIAN)) && sale_item.economic_department != provider.department_id)
			continue
		var/scanned_value = verified_sale_items[sale_item]
		if(!isnum(scanned_value) || scanned_value <= 0)
			continue
		var/credited_value = min(round(scanned_value), remaining_personal_payment)
		if(credited_value <= 0)
			continue
		sale_item.economic_sale_invoice_id = invoice.id
		invoice.verified_items += sale_item
		invoice.verified_item_types["[sale_item.type]"] = TRUE
		invoice.verified_amount += credited_value
		invoice.verified_item_count++
		if(istype(sale_item, /obj/item))
			var/customer_department = customer?.department_id
			sale_item.AddComponent(/datum/component/economic_adoption, invoice.id, customer?.account_number, customer_department, provider.department_id, credited_value)
		remaining_personal_payment -= credited_value
		remaining_by_name[sale_item.name]--
	service_invoices += invoice
	emit_contract_event(CONTRACT_EVENT_SERVICE_INVOICE_CHANGED, list(
		"actor_account" = customer?.account_number,
		"actor_name" = invoice.customer_name,
		"actor_department" = customer?.department_id,
		"department" = provider.department_id,
		"provider_account" = provider.account_number,
		"staff_account" = invoice.staff_account_number,
		"staff_name" = invoice.staff_name,
		"invoice_id" = invoice.id,
		"fact_id" = "service-invoice:[invoice.id]",
		"fact_revision" = invoice.contract_revision,
		"fact_active" = TRUE,
		"terminal_id" = terminal_id,
		"payment_method" = payment_method,
		"items" = items?.Copy(),
		"metrics" = list(
			"amount" = invoice.amount,
			"personal_amount" = invoice.personal,
			"subsidy" = invoice.subsidy,
			"tip" = invoice.tip,
			"verified_amount" = invoice.verified_amount,
			"verified_item_count" = invoice.verified_item_count,
			"verified_type_count" = length(invoice.verified_item_types),
		),
		"detail" = "Completed service sale #[invoice.id]",
	), "service-invoice:[invoice.id]:[invoice.contract_revision]")
	if(customer)
		notify_service_invoice(invoice, "Service invoice #[invoice.id] was charged to your account.")
	return invoice

/datum/controller/subsystem/supply/proc/create_service_external_invoice(datum/money_account/provider, terminal_id, list/items, list/prices, customer_name, amount, payment_method, list/verified_sale_items)
	var/list/result = list(
		"total" = amount,
		"subsidy" = 0,
		"personal" = amount,
		"tip" = 0,
		"staff_tip" = 0,
		"service_tip" = 0
	)
	return create_service_invoice(null, provider, terminal_id, items, prices, result, 0, null, customer_name, payment_method, verified_sale_items)

/datum/controller/subsystem/supply/proc/service_invoice_rows(account_number = 0, provider_department)
	var/list/rows = list()
	for(var/index = length(service_invoices), index >= 1, index--)
		var/datum/service_invoice/invoice = service_invoices[index]
		if(account_number && invoice.customer_account_number != account_number)
			continue
		if(provider_department && invoice.provider_department != provider_department)
			continue
		rows.Add(list(invoice.as_row()))
	return rows

/datum/controller/subsystem/supply/proc/get_service_invoice(invoice_id)
	for(var/datum/service_invoice/invoice in service_invoices)
		if(invoice.id == invoice_id)
			return invoice

/datum/controller/subsystem/supply/proc/notify_service_invoice(datum/service_invoice/invoice, message)
	for(var/obj/item/pda/device in REGISTRY_MEMBERS(REGISTRY_PDAS))
		if(device.id?.associated_account_number != invoice.customer_account_number)
			continue
		var/datum/data/pda/app/service_receipts/app = device.find_program(/datum/data/pda/app/service_receipts)
		app?.notify(message)

/datum/controller/subsystem/supply/proc/refund_service_invoice(datum/service_invoice/invoice, datum/money_account/provider, machine_id, mob/user)
	if(!invoice || invoice.state != SERVICE_INVOICE_PAID || invoice.settled || invoice.accounting_period != service_accounting_period || !provider || invoice.provider_account_number != provider.account_number || !service_refund_authorized(user, provider))
		return FALSE
	var/datum/money_account/customer = invoice.customer_account_number ? get_account(invoice.customer_account_number) : null
	if((invoice.customer_account_number && (!customer || customer.suspended)) || (!invoice.customer_account_number && !ishuman(user)))
		return FALSE

	var/datum/money_account/staff_account = invoice.staff_account_number ? get_account(invoice.staff_account_number) : null
	if(invoice.staff_tip && (!staff_account || staff_account == customer || staff_account == provider || staff_account.suspended || staff_account.money < invoice.staff_tip))
		return FALSE
	var/provider_refund = invoice.subsidy + invoice.personal + invoice.service_tip
	if(provider.money + provider.savings < provider_refund)
		return FALSE
	if(invoice.subsidy && (!GLOB.station_account || GLOB.station_account.suspended))
		return FALSE
	if(invoice.staff_tip && !staff_account.debit(invoice.staff_tip, invoice.customer_name, "Gratuity refund for invoice #[invoice.id]", machine_id, FALSE))
		return FALSE
	if(provider_refund && !provider.debit(provider_refund, invoice.customer_name, "Service invoice #[invoice.id] refund", machine_id, FALSE))
		if(invoice.staff_tip)
			staff_account.credit(invoice.staff_tip, invoice.customer_name, "Reversal: gratuity refund for invoice #[invoice.id]", machine_id, FALSE)
		return FALSE
	if(invoice.subsidy)
		if(!GLOB.station_account.credit(invoice.subsidy, provider.owner_name, "Service subsidy refund #[invoice.id]", machine_id, FALSE))
			return FALSE
	if(customer)
		var/customer_refund = invoice.personal + invoice.tip
		if(customer_refund)
			if(!customer.credit(customer_refund, provider.owner_name, "Service invoice #[invoice.id] refund", machine_id, FALSE))
				return FALSE
	else if(invoice.personal + invoice.tip)
		var/mob/living/carbon/human/human_user = user
		spawn_money(invoice.personal + invoice.tip, get_turf(human_user), human_user)
	invoice.state = SERVICE_INVOICE_REFUNDED
	invoice.refund_time = stationtime2text()
	invoice.refund_by = user?.real_name || "Service staff"
	invoice.refund_accounting_period = service_accounting_period
	invoice.contract_revision++
	for(var/obj/sale_item as anything in invoice.verified_items)
		if(QDELETED(sale_item) || sale_item.economic_sale_invoice_id != invoice.id)
			continue
		sale_item.economic_sale_invoice_id = 0
		var/datum/component/economic_adoption/adoption = sale_item.GetComponent(/datum/component/economic_adoption)
		if(adoption)
			qdel(adoption)
	record_currency_refund(invoice.amount, FALSE)
	emit_contract_event(CONTRACT_EVENT_SERVICE_INVOICE_CHANGED, list(
		"actor_account" = invoice.customer_account_number,
		"actor_name" = invoice.customer_name,
		"department" = invoice.provider_department,
		"provider_account" = invoice.provider_account_number,
		"staff_account" = invoice.staff_account_number,
		"staff_name" = invoice.staff_name,
		"invoice_id" = invoice.id,
		"fact_id" = "service-invoice:[invoice.id]",
		"fact_revision" = invoice.contract_revision,
		"fact_active" = FALSE,
		"metrics" = list("amount" = 0, "tip" = 0),
		"detail" = "Refunded service sale #[invoice.id]",
	), "service-invoice:[invoice.id]:[invoice.contract_revision]", null, user)
	if(customer)
		notify_service_invoice(invoice, "Service invoice #[invoice.id] was refunded.")
	return TRUE

/// Marks the first real use of a purchased, station-fabricated item. Checkout
/// proves delivery; this component proves that its customer actually tried to
/// use it. It observes the ordinary item interaction signals and publishes one
/// reversible physical fact rather than teaching individual item types about
/// contracts.
/datum/component/economic_adoption
	dupe_mode = COMPONENT_DUPE_UNIQUE
	var/invoice_id
	var/customer_account
	var/customer_department
	var/provider_department
	var/value
	var/adopted = FALSE

/datum/component/economic_adoption/Initialize(_invoice_id, _customer_account, _customer_department, _provider_department, _value)
	if(!istype(parent, /obj/item) || !_invoice_id || !_customer_account || !_customer_department || !_provider_department || _value <= 0)
		return COMPONENT_INCOMPATIBLE
	invoice_id = _invoice_id
	customer_account = _customer_account
	customer_department = _customer_department
	provider_department = _provider_department
	value = _value
	RegisterSignal(parent, COMSIG_ITEM_ATTACK_SELF, PROC_REF(on_attack_self))
	RegisterSignal(parent, COMSIG_ITEM_ATTACK, PROC_REF(on_attack))

/datum/component/economic_adoption/Destroy()
	UnregisterSignal(parent, list(COMSIG_ITEM_ATTACK_SELF, COMSIG_ITEM_ATTACK))
	return ..()

/datum/component/economic_adoption/proc/on_attack_self(obj/item/source, mob/user)
	SIGNAL_HANDLER
	record_use(user)

/datum/component/economic_adoption/proc/on_attack(obj/item/source, mob/living/target, mob/living/user)
	SIGNAL_HANDLER
	record_use(user)

/datum/component/economic_adoption/proc/record_use(mob/user)
	if(adopted || !user)
		return FALSE
	var/datum/money_account/account = contract_account_for_mob(user)
	if(!account || (account.account_number != customer_account && account.department_id != customer_department))
		return FALSE
	adopted = TRUE
	publish_adoption(user, TRUE)
	return TRUE

/datum/component/economic_adoption/proc/publish_adoption(mob/user, active)
	var/obj/item/item = parent
	return emit_contract_event(CONTRACT_EVENT_EQUIPMENT_ADOPTED, list(
		"actor_account" = customer_account,
		"actor_department" = customer_department,
		"department" = provider_department,
		"customer_department" = customer_department,
		"invoice_id" = invoice_id,
		"physical_item_id" = REF(item),
		"item_type" = item.type,
		"item_name" = item.name,
		"fact_id" = "equipment-adoption:[REF(item)]",
		"fact_revision" = active ? 1 : 2,
		"fact_active" = active,
		"metrics" = list("value" = active ? value : 0),
		"detail" = active ? "[item.name] entered operational use in [customer_department]." : "[item.name]'s sale was reversed before settlement.",
	), "equipment-adoption:[REF(item)]:[active ? 1 : 2]", item, user)

/datum/controller/subsystem/supply/proc/service_invoice_summary(department, accounting_period = 0)
	var/list/summary = list(
		"invoice_count" = 0,
		"refund_count" = 0,
		"gross_billed" = 0,
		"refunded_total" = 0,
		"net_billed" = 0,
		"account_sales" = 0,
		"cash_sales" = 0,
		"ewallet_sales" = 0,
		"tips" = 0,
		"staff_tips" = 0,
		"service_tips" = 0
	)
	var/include_all_periods = accounting_period < 0
	if(!accounting_period)
		accounting_period = service_accounting_period
	for(var/datum/service_invoice/invoice in service_invoices)
		if(invoice.provider_department != department)
			continue
		if(include_all_periods || invoice.accounting_period == accounting_period)
			summary["invoice_count"]++
			summary["gross_billed"] += invoice.amount
			summary["tips"] += invoice.tip
			summary["staff_tips"] += invoice.staff_tip
			summary["service_tips"] += invoice.service_tip
			switch(invoice.payment_method)
				if("Cash")
					summary["cash_sales"] += invoice.amount
				if("E-Wallet")
					summary["ewallet_sales"] += invoice.amount
				else
					summary["account_sales"] += invoice.amount
		if(invoice.state == SERVICE_INVOICE_REFUNDED && (include_all_periods || invoice.refund_accounting_period == accounting_period))
			summary["refund_count"]++
			summary["refunded_total"] += invoice.amount
	summary["net_billed"] = summary["gross_billed"] - summary["refunded_total"]
	return summary

/// Produce a deliberately conservative, anti-collusion view of one closed
/// accounting period. Cash/E-wallet sales lack stable customer identity and do
/// not count. Each invoice and customer is capped so a single fabricated price
/// cannot satisfy a market-participation contract.
/datum/controller/subsystem/supply/proc/service_contract_period_metrics(department, accounting_period, staff_account_number = 0)
	var/list/customer_sales = list()
	var/list/customer_tips = list()
	var/list/verified_types = list()
	var/verified_item_count = 0
	for(var/datum/service_invoice/invoice in service_invoices)
		if(invoice.accounting_period != accounting_period || invoice.provider_department != department || invoice.state != SERVICE_INVOICE_PAID)
			continue
		if(staff_account_number && invoice.staff_account_number != staff_account_number)
			continue
		if(!invoice.customer_account_number || invoice.customer_account_number == invoice.provider_account_number || invoice.customer_account_number == invoice.staff_account_number)
			continue
		var/customer_key = "[invoice.customer_account_number]"
		// Sponsor demand measures money paid by a real customer, not a station
		// subsidy. Research/Cargo additionally require physical scanned goods.
		var/eligible_value = (department in list(DEPARTMENT_RESEARCH, DEPARTMENT_CARGO)) ? invoice.verified_amount : invoice.personal
		var/invoice_service_value = min(250, max(0, eligible_value))
		var/invoice_tip_value = min(50, max(0, invoice.tip))
		customer_sales[customer_key] = min(400, (customer_sales[customer_key] || 0) + invoice_service_value)
		customer_tips[customer_key] = min(100, (customer_tips[customer_key] || 0) + invoice_tip_value)
		verified_item_count += invoice.verified_item_count
		for(var/item_type in invoice.verified_item_types)
			verified_types[item_type] = TRUE
	var/net_amount = 0
	var/net_tips = 0
	var/customer_count = 0
	for(var/customer_key in customer_sales)
		var/customer_amount = customer_sales[customer_key]
		net_amount += customer_amount
		net_tips += customer_tips[customer_key] || 0
		if(customer_amount >= 10)
			customer_count++
	return list(
		"amount" = net_amount,
		"tip" = net_tips,
		"customer_count" = customer_count,
		"verified_amount" = net_amount,
		"verified_item_count" = verified_item_count,
		"verified_type_count" = length(verified_types),
	)

/datum/controller/subsystem/supply/proc/settle_service_contract_period(accounting_period)
	var/list/departments = list()
	var/list/staff_by_department = list()
	for(var/datum/service_invoice/invoice in service_invoices)
		if(invoice.accounting_period != accounting_period)
			continue
		invoice.settled = TRUE
		departments[invoice.provider_department] = TRUE
		if(invoice.staff_account_number)
			LAZYINITLIST(staff_by_department[invoice.provider_department])
			staff_by_department[invoice.provider_department]["[invoice.staff_account_number]"] = TRUE
	for(var/department in departments)
		var/list/department_metrics = service_contract_period_metrics(department, accounting_period)
		var/list/staff_accounts = staff_by_department[department]
		var/list/contributor_weights = list()
		var/list/staff_rollups = list()
		for(var/staff_key in staff_accounts)
			var/staff_account = text2num(staff_key)
			var/list/staff_metrics = service_contract_period_metrics(department, accounting_period, staff_account)
			staff_rollups[staff_key] = staff_metrics
			var/contribution_value = (staff_metrics["amount"] || 0) + (staff_metrics["tip"] || 0)
			if(contribution_value > 0)
				contributor_weights[staff_key] = contribution_value
		department_metrics["contributor_weights"] = contributor_weights
		emit_contract_event(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, list(
			"department" = department,
			"rollup" = "department",
			"accounting_period" = accounting_period,
			"fact_id" = "service-period:[accounting_period]:[department]",
			"fact_revision" = 1,
			"fact_active" = TRUE,
			"metrics" = department_metrics,
			"detail" = "Closed accounting-period service ledger for [department]",
		), "service-period:[accounting_period]:[department]:department")
		for(var/staff_key in staff_accounts)
			var/staff_account = text2num(staff_key)
			var/list/staff_metrics = staff_rollups[staff_key]
			emit_contract_event(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, list(
				"actor_account" = staff_account,
				"department" = department,
				"staff_account" = staff_account,
				"rollup" = "staff",
				"accounting_period" = accounting_period,
				"fact_id" = "service-period:[accounting_period]:[department]:[staff_account]",
				"fact_revision" = 1,
				"fact_active" = TRUE,
				"metrics" = staff_metrics,
				"detail" = "Closed staff service ledger for accounting period [accounting_period]",
			), "service-period:[accounting_period]:[department]:staff:[staff_account]")

/proc/service_tip_choice(mob/user, datum/money_account/customer, list/quote, description)
	var/ten_percent = round(quote["total"] * 0.1)
	var/twenty_percent = round(quote["total"] * 0.2)
	var/available = max(0, customer.money - quote["personal"])
	var/list/options = list("Decline", "Confirm - no tip")
	if(ten_percent > 0 && ten_percent <= available)
		options += "Confirm + [ten_percent] Th tip"
	if(twenty_percent > 0 && twenty_percent <= available && twenty_percent != ten_percent)
		options += "Confirm + [twenty_percent] Th tip"
	var/choice = tgui_alert(user, service_quote_text(quote, description, ten_percent, twenty_percent), "Confirm Service Purchase", options)
	if(choice == "Confirm - no tip")
		return 0
	if(choice == "Confirm + [ten_percent] Th tip")
		return ten_percent
	if(choice == "Confirm + [twenty_percent] Th tip")
		return twenty_percent
	return null

/proc/complete_service_checkout(datum/money_account/customer, datum/money_account/provider, amount, purpose, terminal_id, list/items, list/prices, staff_account_number, staff_name, tip, list/verified_sale_items)
	var/canonical_total = service_ticket_total(items, prices)
	if(isnull(canonical_total) || canonical_total != amount)
		return
	var/provider_department = provider?.department_id
	if(!provider_department)
		return
	var/list/quote = department_service_quote(customer, provider_department, amount)
	if(!quote || !isnum(tip) || tip < 0 || customer.money - quote["personal"] < tip)
		return
	var/list/result = list()
	if(!charge_department_service(customer, provider_department, amount, purpose, terminal_id, result))
		return
	var/datum/money_account/staff_account = get_account(staff_account_number)
	var/staff_tip = 0
	if(tip && staff_account && !staff_account.suspended && staff_account != customer)
		staff_tip = round(tip * SSsupply.service_tip_staff_share)
	var/service_tip = tip - staff_tip
	if(tip && !customer.debit(tip, "Service gratuity", purpose, terminal_id, FALSE))
		return
	if(staff_tip)
		staff_account.credit(staff_tip, customer.owner_name, "Service gratuity", terminal_id, FALSE)
	if(service_tip)
		provider.credit(service_tip, customer.owner_name, "Service gratuity", terminal_id, FALSE)
	result["tip"] = tip
	result["staff_tip"] = staff_tip
	result["service_tip"] = service_tip
	return SSsupply.create_service_invoice(customer, provider, terminal_id, items, prices, result, staff_account_number, staff_name, null, "ID account", verified_sale_items)

#undef SERVICE_INVOICE_PAID
#undef SERVICE_INVOICE_REFUNDED
