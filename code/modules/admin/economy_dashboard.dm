/datum/economy_dashboard

CAPABILITIES(/datum/economy_dashboard)
	interface("EconomyDashboard", title = "Economy Observatory", rights = R_ADMIN|R_DEBUG)
	ui_shape(account_currency = any, personal_currency = any, personal_accounts = any, personal_balance_p10 = any, personal_balance_median = any, personal_balance_p90 = any, personal_zero_balance = any, personal_low_balance = any, department_savings = any, currency_created = any, currency_destroyed = any, currency_refunded = any, currency_sink_refunded = any, currency_internal_refunded = any, net_currency_flow = any, currency_sources = any, currency_sinks = any, projected_payroll = any, last_payroll_due = any, last_payroll_paid = any, unpaid_wages = any, allocation_policy = any, service_subsidies = any, service_invoice_count = any, service_sales_gross = any, service_sales_net = any, service_refund_count = any, service_refund_rate = any, service_tips = any, personal_orders = any, personal_order_spend = any, pending_personal_orders = any, market_generation = any, market_counterparties = any, market_listings = any, market_listing_stock = any, market_bids = any, market_target_units = any, market_fulfilled_units = any, market_purchase_volume = any, market_export_volume = any, covert_market_volume = any, covert_market_traces = any, covert_market_detections = any, faction_agents = any, agent_candidates = any, agent_accredited = any, agent_trusted = any, agent_operatives = any, agent_total_exposure = any, agent_contracts_completed = any, agent_contracts_failed = any, departments = any)

/datum/economy_dashboard/tgui_close(mob/user)
	SStgui.close_uis(src)
	spent(src, user)

/datum/economy_dashboard/proc/ranked_ledger_rows(list/ledger)
	var/list/rows = list()
	for(var/name in ledger)
		rows.Add(list(list("name" = name, "amount" = ledger[name])))
	return rows

/datum/economy_dashboard/proc/balance_percentile(list/sorted_balances, percentile)
	if(!length(sorted_balances))
		return 0
	var/index = clamp(round(1 + (length(sorted_balances) - 1) * percentile), 1, length(sorted_balances))
	return sorted_balances[index]

/// /datum/economy_dashboard's window data.
/datum/economy_dashboard/ui_data(datum/act/eval/A)
	var/account_currency = 0
	var/personal_currency = 0
	var/personal_accounts = 0
	var/personal_zero_balance = 0
	var/personal_low_balance = 0
	var/list/personal_balances = list()
	for(var/datum/money_account/account in REGISTRY_MEMBERS(REGISTRY_MONEY_ACCOUNTS))
		account_currency += account.money + account.savings
		if(!account.is_budget_account)
			personal_accounts++
			personal_currency += account.money
			personal_balances += account.money
			if(account.money <= 0)
				personal_zero_balance++
			if(account.money < 100)
				personal_low_balance++
	sortTim(personal_balances, GLOBAL_PROC_REF(cmp_numeric_asc))

	var/projected_payroll = SSsupply.projected_station_payroll()
	var/last_payroll_due = 0
	var/last_payroll_paid = 0
	var/department_savings = 0
	var/list/departments = list()
	for(var/department in GLOB.department_accounts)
		if(department == "Vendor")
			continue
		var/datum/money_account/budget = GLOB.department_accounts[department]
		last_payroll_due += budget.last_payroll_due
		last_payroll_paid += budget.last_payroll_paid
		department_savings += budget.savings
		departments.Add(list(list(
			"name" = department,
			"balance" = budget.money,
			"savings" = budget.savings,
			"income" = budget.monthly_income,
			"expenses" = budget.monthly_expenses,
			"projected_payroll" = SSsupply.projected_department_payroll(department),
			"last_payroll_due" = budget.last_payroll_due,
			"last_payroll_paid" = budget.last_payroll_paid
		)))

	var/personal_orders = 0
	var/personal_order_spend = 0
	var/pending_personal_orders = 0
	for(var/datum/supply_order/order in SSsupply.order_history)
		if(!order.personal_order)
			continue
		personal_orders++
		personal_order_spend += order.paid_amount
		if(order.status == SUP_ORDER_REQUESTED)
			pending_personal_orders++

	var/list/service_sales = SSsupply.service_invoice_summary(DEPARTMENT_CIVILIAN, -1)
	var/market_purchase_volume = 0
	var/market_export_volume = 0
	var/covert_market_volume = 0
	var/covert_market_traces = 0
	var/covert_market_detections = 0
	for(var/datum/cargo_market_transaction/market_transaction in SSsupply.market_transactions)
		if(market_transaction.transaction_type == CARGO_MARKET_BUY)
			market_purchase_volume += market_transaction.value
		else if(market_transaction.transaction_type == CARGO_MARKET_SELL)
			market_export_volume += market_transaction.value
		if(market_transaction.covert)
			covert_market_volume += market_transaction.value
			covert_market_traces++
			if(market_transaction.detected)
				covert_market_detections++
	var/market_listing_stock = 0
	for(var/listing_id in SSsupply.market_listings)
		var/datum/cargo_market_listing/listing = SSsupply.market_listings?[listing_id]
		market_listing_stock += listing.stock
	var/market_target_units = 0
	var/market_fulfilled_units = 0
	for(var/bid_id in SSsupply.market_bids)
		var/datum/cargo_market_bid/bid = SSsupply.market_bids?[bid_id]
		market_target_units += bid.target_units
		market_fulfilled_units += bid.fulfilled_units
	var/agent_contracts_completed = 0
	var/agent_contracts_failed = 0
	var/agent_candidates = 0
	var/agent_accredited = 0
	var/agent_trusted = 0
	var/agent_operatives = 0
	var/agent_total_exposure = 0
	for(var/account_number in GLOB.station_faction_relations.agent_records)
		var/datum/faction_agent_record/agent_record = GLOB.station_faction_relations.agent_records[account_number]
		agent_contracts_completed += agent_record.contracts_completed
		agent_contracts_failed += agent_record.contracts_failed
		agent_total_exposure += agent_record.exposure
		switch(agent_record.tier)
			if(FACTION_AGENT_TIER_CANDIDATE)
				agent_candidates++
			if(FACTION_AGENT_TIER_ACCREDITED)
				agent_accredited++
			if(FACTION_AGENT_TIER_TRUSTED)
				agent_trusted++
			if(FACTION_AGENT_TIER_OPERATIVE)
				agent_operatives++
	return list(
		"account_currency" = account_currency,
		"personal_currency" = personal_currency,
		"personal_accounts" = personal_accounts,
		"personal_balance_p10" = balance_percentile(personal_balances, 0.1),
		"personal_balance_median" = balance_percentile(personal_balances, 0.5),
		"personal_balance_p90" = balance_percentile(personal_balances, 0.9),
		"personal_zero_balance" = personal_zero_balance,
		"personal_low_balance" = personal_low_balance,
		"department_savings" = department_savings,
		"currency_created" = SSsupply.currency_created,
		"currency_destroyed" = SSsupply.currency_destroyed,
		"currency_refunded" = SSsupply.currency_refunded,
		"currency_sink_refunded" = SSsupply.currency_sink_refunded,
		"currency_internal_refunded" = SSsupply.currency_internal_refunded,
		"net_currency_flow" = SSsupply.currency_created - SSsupply.currency_destroyed + SSsupply.currency_sink_refunded,
		"currency_sources" = ranked_ledger_rows(SSsupply.currency_sources),
		"currency_sinks" = ranked_ledger_rows(SSsupply.currency_sinks),
		"projected_payroll" = projected_payroll,
		"last_payroll_due" = last_payroll_due,
		"last_payroll_paid" = last_payroll_paid,
		"unpaid_wages" = max(0, last_payroll_due - last_payroll_paid),
		"allocation_policy" = SSsupply.allocation_policy,
		"service_subsidies" = SSsupply.service_subsidies,
		"service_invoice_count" = service_sales["invoice_count"],
		"service_sales_gross" = service_sales["gross_billed"],
		"service_sales_net" = service_sales["net_billed"],
		"service_refund_count" = service_sales["refund_count"],
		"service_refund_rate" = service_sales["invoice_count"] ? service_sales["refund_count"] / service_sales["invoice_count"] : 0,
		"service_tips" = service_sales["tips"],
		"personal_orders" = personal_orders,
		"personal_order_spend" = personal_order_spend,
		"pending_personal_orders" = pending_personal_orders,
		"market_generation" = SSsupply.market_generation,
		"market_counterparties" = length(SSsupply.market_counterparties),
		"market_listings" = length(SSsupply.market_listings),
		"market_listing_stock" = market_listing_stock,
		"market_bids" = length(SSsupply.market_bids),
		"market_target_units" = market_target_units,
		"market_fulfilled_units" = market_fulfilled_units,
		"market_purchase_volume" = market_purchase_volume,
		"market_export_volume" = market_export_volume,
		"covert_market_volume" = covert_market_volume,
		"covert_market_traces" = covert_market_traces,
		"covert_market_detections" = covert_market_detections,
		"faction_agents" = length(GLOB.station_faction_relations.agent_records),
		"agent_candidates" = agent_candidates,
		"agent_accredited" = agent_accredited,
		"agent_trusted" = agent_trusted,
		"agent_operatives" = agent_operatives,
		"agent_total_exposure" = agent_total_exposure,
		"agent_contracts_completed" = agent_contracts_completed,
		"agent_contracts_failed" = agent_contracts_failed,
		"departments" = departments
	)

ADMIN_VERB(economy_dashboard, R_ADMIN|R_DEBUG, "Economy Observatory", "Inspect currency flow, departmental solvency, payroll, orders, subsidies, and sales.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	var/datum/economy_dashboard/dashboard = new
	dashboard.tgui_interact(user.mob)
