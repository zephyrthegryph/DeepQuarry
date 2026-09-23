#define SUPPLY_THALERS_PER_LEGACY_POINT 50
#define ALLOCATION_POLICY_EQUAL "equal"
#define ALLOCATION_POLICY_STAFFING "staffing"
#define ALLOCATION_POLICY_PAYROLL "payroll"
#define DEPARTMENT_BASE_OPERATING_ALLOCATION 1000

//Supply packs are in /code/datums/supplypacks
//Computers are in /code/game/machinery/computer/supply.dm
SUBSYSTEM_DEF(supply)
	name = "Supply"
	wait = 20 SECONDS
	priority = FIRE_PRIORITY_SUPPLY
	//Initializes at default time
	flags = SS_NO_TICK_CHECK

	var/points_per_slip = 2
	var/points_per_money = 0.02 // Legacy export values convert at 1 point = 50 Thalers.
	var/next_payroll = 0
	/// NanoTrasen's default contribution toward the station's projected gross payroll.
	var/nt_salary_support = 0.75
	/// Command-selected rule for dividing the projected station payroll pool.
	var/allocation_policy = ALLOCATION_POLICY_EQUAL
	/// Shift-level ledger metrics for admin economy observability.
	var/currency_created = 0
	var/currency_destroyed = 0
	var/currency_refunded = 0
	/// Refunds that restore a prior external sink and therefore affect net flow.
	var/currency_sink_refunded = 0
	/// Reversals of internal transfers; useful operationally but monetary-base neutral.
	var/currency_internal_refunded = 0
	var/service_subsidies = 0
	var/service_invoice_counter = 0
	var/list/service_invoices = list()
	/// Identifies the current 15-minute accounting window for Service invoices.
	var/service_accounting_period = 1
	/// Portion of an optional gratuity paid directly to the identified worker.
	var/service_tip_staff_share = 0.5
	var/list/currency_sources = list()
	var/list/currency_sinks = list()
	//control
	var/ordernum = 0						// Start at zero, it's per-shift tracking
	var/list/shoppinglist = list()			// Approved orders
	var/list/supply_pack = list()			// All supply packs
	var/list/exported_crates = list()		// Crates sent from the station
	var/list/order_history = list()			// History of orders, showing edits made by users
	var/list/adm_order_history = list() 	// Complete history of all orders, for admin use
	var/list/adm_export_history = list()	// Complete history of all crates sent back on the shuttle, for admin use
	//shuttle movement
	var/movetime = 1200
	var/datum/shuttle/autodock/ferry/supply/shuttle

/datum/controller/subsystem/supply/Initialize()
	reset_shift_economy_tracking()
	// build master supply list
	for(var/typepath in subtypesof(/datum/supply_pack))
		var/datum/supply_pack/P = new typepath()
		if(P.name)
			supply_pack[P.name] = P
		else
			qdel(P)
	initialize_cargo_market()

	next_payroll = world.time + 15 MINUTES
	return SS_INIT_SUCCESS

/datum/controller/subsystem/supply/proc/reset_shift_economy_tracking()
	QDEL_LIST(service_invoices)
	service_invoice_counter = 0
	service_accounting_period = 1
	currency_created = 0
	currency_destroyed = 0
	currency_refunded = 0
	currency_sink_refunded = 0
	currency_internal_refunded = 0
	service_subsidies = 0
	currency_sources.Cut()
	currency_sinks.Cut()

/datum/controller/subsystem/supply/fire(resumed)
	process_cargo_market()
	if(world.time < next_payroll)
		return
	next_payroll = world.time + 15 MINUTES
	var/completed_service_period = service_accounting_period
	var/list/funded_allocations = run_department_budget_cycle()
	run_department_payroll()
	publish_budget_cycle_settlement(funded_allocations, completed_service_period)
	settle_service_contract_period(completed_service_period)

/datum/controller/subsystem/supply/proc/run_department_budget_cycle()
	var/list/funded_allocations = list()
	GLOB.station_account.roll_accounting_period()
	var/list/plan = department_budget_plan()
	var/nt_payroll_grant = plan["nt_grant"]
	if(nt_payroll_grant > 0)
		GLOB.station_account.credit(nt_payroll_grant, "NanoTrasen", "Pay-period payroll support (75%)", "NanoTrasen budget office")
	var/list/department_plans = plan["departments"]
	for(var/department in GLOB.department_accounts)
		if(department == "Vendor")
			continue
		var/datum/money_account/budget = GLOB.department_accounts[department]
		if(!budget?.roll_budget_period())
			continue
		var/list/department_plan = department_plans[department]
		if(!department_plan)
			continue
		budget.monthly_allocation = department_plan["requested"]
	for(var/department in department_plans)
		var/datum/money_account/budget = GLOB.department_accounts[department]
		var/list/department_plan = department_plans[department]
		var/funded_amount = department_plan["funded"] || 0
		if(funded_amount > 0 && transfer_account_funds(GLOB.station_account, budget, funded_amount, "Pay-period department allocation", "Automated budget cycle"))
			funded_allocations[department] = funded_amount
		else
			funded_allocations[department] = 0
	service_accounting_period++
	return funded_allocations

/// Build the exact next-cycle allocation plan used by both execution and UI.
/// Payroll portions are funded before operating allowances, and explicit
/// department overrides do not disable automatic planning elsewhere.
/datum/controller/subsystem/supply/proc/department_budget_plan()
	var/projected_payroll = projected_station_payroll()
	var/nt_grant = max(0, round(projected_payroll * nt_salary_support))
	var/available = max(0, round((GLOB.station_account?.money || 0) + nt_grant))
	var/department_count = 0
	var/automatic_departments = 0
	var/automatic_staff = 0
	var/configured_percent = 0
	for(var/department in GLOB.department_accounts)
		if(department == "Vendor")
			continue
		department_count++
		var/datum/money_account/budget = GLOB.department_accounts[department]
		if(budget?.allocation_configured)
			configured_percent += clamp(budget.allocation_percent, 0, 100)
		else
			automatic_departments++
			automatic_staff += active_department_employee_count(department)
	var/automatic_percent = automatic_departments ? max(0, 100 - configured_percent) / automatic_departments : 0
	var/operating_pool = department_count * DEPARTMENT_BASE_OPERATING_ALLOCATION
	var/list/department_plans = list()
	var/list/payroll_requests = list()
	var/list/operating_requests = list()
	var/total_requested = 0
	for(var/department in GLOB.department_accounts)
		if(department == "Vendor")
			continue
		var/datum/money_account/budget = GLOB.department_accounts[department]
		var/staff = active_department_employee_count(department)
		var/payroll = projected_department_payroll(department)
		var/policy_percent = automatic_percent
		if(!budget?.allocation_configured)
			switch(allocation_policy)
				if(ALLOCATION_POLICY_STAFFING)
					policy_percent = automatic_staff ? max(0, 100 - configured_percent) * staff / automatic_staff : automatic_percent
				if(ALLOCATION_POLICY_PAYROLL)
					policy_percent = 0
		var/allocation_percent = budget?.allocation_configured ? clamp(budget.allocation_percent, 0, 100) : policy_percent
		var/operating = round(operating_pool * allocation_percent / 100)
		var/automatic = payroll + operating
		var/requested = automatic
		if(budget?.suspended)
			requested = 0
		var/payroll_request = min(payroll, requested)
		var/operating_request = max(0, requested - payroll_request)
		payroll_requests[department] = payroll_request
		operating_requests[department] = operating_request
		total_requested += requested
		department_plans[department] = list(
			"staff" = staff,
			"payroll" = payroll,
			"automatic" = automatic,
			"allocation_percent" = allocation_percent,
			"requested" = requested,
			"payroll_requested" = payroll_request,
			"operating_requested" = operating_request,
			"overridden" = !!budget?.allocation_configured,
			"funded" = 0,
			"shortfall" = requested,
		)
	var/list/funded_payroll = proportional_department_allocations(payroll_requests, available)
	var/payroll_funded = 0
	for(var/department in funded_payroll)
		payroll_funded += funded_payroll[department]
	var/list/funded_operating = proportional_department_allocations(operating_requests, max(0, available - payroll_funded))
	var/total_funded = 0
	var/total_operating_requested = 0
	var/total_operating_funded = 0
	for(var/department in department_plans)
		var/list/department_plan = department_plans[department]
		var/department_payroll_funded = funded_payroll[department] || 0
		var/department_operating_funded = funded_operating[department] || 0
		var/funded = department_payroll_funded + department_operating_funded
		department_plan["payroll_funded"] = department_payroll_funded
		department_plan["operating_funded"] = department_operating_funded
		department_plan["funded"] = funded
		department_plan["shortfall"] = max(0, department_plan["requested"] - funded)
		total_operating_requested += department_plan["operating_requested"]
		total_operating_funded += department_operating_funded
		total_funded += funded
	return list(
		"departments" = department_plans,
		"projected_payroll" = projected_payroll,
		"nt_grant" = nt_grant,
		"available" = available,
		"operating_pool" = operating_pool,
		"configured_percent" = configured_percent,
		"operating_requested" = total_operating_requested,
		"operating_funded" = total_operating_funded,
		"payroll_funded" = payroll_funded,
		"unallocated_operating" = max(0, operating_pool - total_operating_requested),
		"requested" = total_requested,
		"funded" = total_funded,
		"remaining" = max(0, available - total_funded),
		"shortfall" = max(0, total_requested - total_funded),
	)

/// Divide a constrained station allocation pool proportionally. Whole-Thaler
/// remainders are distributed one at a time without allowing list order to
/// decide which departments receive their entire budgets and which get zero.
/datum/controller/subsystem/supply/proc/proportional_department_allocations(list/requested, available)
	var/list/result = list()
	if(!islist(requested) || !isnum(available) || available <= 0)
		return result
	var/total_requested = 0
	for(var/department in requested)
		var/requested_amount = max(0, round(requested[department]))
		if(requested_amount <= 0)
			continue
		total_requested += requested_amount
		result[department] = 0
	if(total_requested <= 0)
		return result
	var/distributable = min(round(available), total_requested)
	var/assigned = 0
	for(var/department in result)
		var/share = floor(distributable * requested[department] / total_requested)
		result[department] = share
		assigned += share
	var/remainder = distributable - assigned
	while(remainder > 0)
		var/distributed_this_pass = FALSE
		for(var/department in result)
			if(result[department] >= requested[department])
				continue
			result[department]++
			remainder--
			distributed_this_pass = TRUE
			if(remainder <= 0)
				break
		if(!distributed_this_pass)
			break
	return result

/// Funds which can authoritatively exist at the next budget cycle before any
/// speculative player income. Contract acceptance uses this lower bound so it
/// never promises an allocation the station cannot presently fund.
/datum/controller/subsystem/supply/proc/projected_station_budget_capacity()
	var/current_funds = max(0, GLOB.station_account?.money || 0)
	var/payroll_grant = max(0, round(projected_station_payroll() * nt_salary_support))
	return current_funds + payroll_grant

/datum/controller/subsystem/supply/proc/publish_budget_cycle_settlement(list/funded_allocations, accounting_period)
	var/qualifying_total = 0
	var/funded_department_count = 0
	var/command_allocation = 0
	var/payroll_due = 0
	var/payroll_paid = 0
	for(var/department in GLOB.department_accounts)
		if(department == "Vendor")
			continue
		var/datum/money_account/budget = GLOB.department_accounts[department]
		var/funded = funded_allocations[department] || 0
		payroll_due += budget?.last_payroll_due || 0
		payroll_paid += budget?.last_payroll_paid || 0
		if(department == DEPARTMENT_COMMAND)
			command_allocation = funded
		if(department != DEPARTMENT_PLANET)
			qualifying_total += funded
			if(funded >= 2000)
				funded_department_count++
	emit_contract_event(CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, list(
		"department" = DEPARTMENT_COMMAND,
		"rollup" = "station",
		"accounting_period" = accounting_period,
		"fact_id" = "budget-cycle:[accounting_period]",
		"fact_revision" = 1,
		"fact_active" = TRUE,
		"metrics" = list(
			"funded_allocation_total" = qualifying_total,
			"funded_department_count" = funded_department_count,
			"command_allocation" = command_allocation,
			"payroll_due" = payroll_due,
			"payroll_paid" = payroll_paid,
			"payroll_coverage" = payroll_due > 0 ? payroll_paid / payroll_due : 1,
			"station_balance" = GLOB.station_account?.money || 0,
		),
		"detail" = "Closed station budget and payroll cycle [accounting_period]",
	), "budget-cycle:[accounting_period]:station")

/datum/controller/subsystem/supply/proc/projected_department_payroll(department)
	var/datum/money_account/budget = GLOB.department_accounts[department]
	if(!budget)
		return 0
	var/projected = 0
	for(var/mob/living/carbon/human/employee in GLOB.player_list)
		if(QDELETED(employee) || employee.stat == DEAD || !employee.mind?.initial_account || department_for_mob(employee) != department)
			continue
		var/datum/job/job = SSjob.get_job(employee.job)
		if(job)
			projected += max(1, round(50 * job.economic_modifier * budget.wage_multiplier))
	return projected

/datum/controller/subsystem/supply/proc/projected_station_payroll()
	var/projected = 0
	for(var/department in GLOB.department_accounts)
		if(department != "Vendor")
			projected += projected_department_payroll(department)
	return projected

/datum/controller/subsystem/supply/proc/active_department_employee_count(department)
	var/count = 0
	for(var/mob/living/carbon/human/employee in GLOB.player_list)
		if(!QDELETED(employee) && employee.stat != DEAD && employee.mind?.initial_account && department_for_mob(employee) == department)
			count++
	return count

/datum/controller/subsystem/supply/proc/active_station_employee_count()
	var/count = 0
	for(var/department in GLOB.department_accounts)
		if(department != "Vendor")
			count += active_department_employee_count(department)
	return count

/datum/controller/subsystem/supply/proc/set_allocation_policy(policy, clear_overrides = FALSE)
	if(!(policy in list(ALLOCATION_POLICY_EQUAL, ALLOCATION_POLICY_STAFFING, ALLOCATION_POLICY_PAYROLL)))
		return FALSE
	allocation_policy = policy
	if(clear_overrides)
		for(var/department in GLOB.department_accounts)
			var/datum/money_account/budget = GLOB.department_accounts[department]
			if(budget?.is_department_budget())
				budget.allocation_configured = FALSE
	return TRUE

/datum/controller/subsystem/supply/proc/record_currency_created(amount, source)
	if(!isnum(amount) || amount <= 0)
		return
	currency_created += amount
	currency_sources[source] = (currency_sources[source] || 0) + amount

/datum/controller/subsystem/supply/proc/record_currency_destroyed(amount, sink)
	if(!isnum(amount) || amount <= 0)
		return
	currency_destroyed += amount
	currency_sinks[sink] = (currency_sinks[sink] || 0) + amount

/datum/controller/subsystem/supply/proc/record_currency_refund(amount, reverses_external_sink = FALSE)
	if(!isnum(amount) || amount <= 0)
		return
	currency_refunded += amount
	if(reverses_external_sink)
		currency_sink_refunded += amount
	else
		currency_internal_refunded += amount

/datum/controller/subsystem/supply/proc/run_department_payroll()
	for(var/department in GLOB.department_accounts)
		if(department == "Vendor")
			continue
		var/datum/money_account/budget = GLOB.department_accounts[department]
		if(!budget)
			continue
		var/list/employees = list()
		var/list/pay_due = list()
		var/total_due = 0
		for(var/mob/living/carbon/human/employee in GLOB.player_list)
			if(QDELETED(employee) || employee.stat == DEAD || !employee.mind?.initial_account || department_for_mob(employee) != department)
				continue
			var/datum/job/job = SSjob.get_job(employee.job)
			if(!job)
				continue
			var/due = max(1, round(50 * job.economic_modifier * budget.wage_multiplier))
			employees += employee
			pay_due[employee] = due
			total_due += due
		if(!total_due)
			budget.last_payroll_due = 0
			budget.last_payroll_paid = 0
			continue
		// Payroll is the first expenditure after allocation. If the department is
		// insolvent, distribute every available Thaler proportionally instead of
		// allowing player iteration order to decide who gets paid.
		var/remaining_funds = min(total_due, round(budget.money + budget.savings))
		var/payroll_funds = remaining_funds
		var/remaining_due = total_due
		for(var/mob/living/carbon/human/employee as anything in employees)
			var/due = pay_due[employee]
			var/pay = remaining_due == due ? remaining_funds : min(due, round(remaining_funds * due / remaining_due))
			remaining_due -= due
			remaining_funds -= pay
			if(pay <= 0 || !transfer_account_funds(budget, employee.mind.initial_account, pay, "Department payroll", "Automated payroll"))
				continue
			if(pay < due)
				to_chat(employee, span_warning("Your [department] paycheck was partially funded: [pay] of [due] Thalers was deposited."))
			else
				to_chat(employee, span_notice("Your [department] paycheck of [pay] Thalers has been deposited."))
		budget.last_payroll_due = total_due
		budget.last_payroll_paid = payroll_funds - remaining_funds

/datum/controller/subsystem/supply/stat_entry(msg)
	var/datum/money_account/cargo = GLOB.department_accounts[DEPARTMENT_CARGO]
	msg = "Cargo budget: [cargo?.money || 0] Thalers"
	return ..()

/datum/controller/subsystem/supply/proc/pack_price(datum/supply_pack/pack)
	return max(1, round(pack.cost * SUPPLY_THALERS_PER_LEGACY_POINT))

/datum/controller/subsystem/supply/proc/export_revenue(legacy_points)
	return max(0, round(legacy_points * SUPPLY_THALERS_PER_LEGACY_POINT))

/datum/controller/subsystem/supply/proc/credit_department(department, legacy_points, purpose)
	var/datum/money_account/account = GLOB.department_accounts[department]
	return account?.credit(export_revenue(legacy_points), "External trade", purpose, "Supply shuttle")

/datum/controller/subsystem/supply/proc/distribute_export_revenue(datum/exported_crate/export)
	if(!export || export.value <= 0)
		return
	var/tagged_value = export.sales_eligible_value
	if(export.sales_ledger_valid && export.sales_eligible_value > 0)
		var/converted_value = export_revenue(export.sales_eligible_value)
		var/datum/money_account/ledger_department = GLOB.department_accounts[export.sales_department]
		var/department_share = round(converted_value * export.sales_department_percent / 100)
		var/cargo_share = round(converted_value * export.sales_cargo_percent / 100)
		ledger_department?.credit(department_share, "External trade", "Freight ledger [export.sales_ledger_id]: [export.sales_destination]", "Supply shuttle")
		var/datum/money_account/cargo_account = GLOB.department_accounts[DEPARTMENT_CARGO]
		cargo_account?.credit(cargo_share, "External trade", "Freight handling: [export.sales_ledger_id]", "Supply shuttle")
		for(var/account_number in export.sales_producer_percentages)
			var/producer_share = round(converted_value * export.sales_producer_percentages[account_number] / 100)
			var/datum/money_account/producer = get_account(text2num(account_number))
			if(producer_share && producer && !producer.suspended)
				producer.credit(producer_share, "External trade", "Producer share: [export.sales_ledger_id]", "Supply shuttle")
			else if(producer_share)
				ledger_department?.credit(producer_share, "External trade", "Unclaimed producer share: [export.sales_ledger_id]", "Supply shuttle")
	for(var/department in export.revenue_by_department)
		var/value = export.revenue_by_department[department]
		tagged_value += value
		var/datum/money_account/department_account = GLOB.department_accounts[department]
		var/share_rate = department_account?.export_share || 0.75
		if(!length(export.revenue_by_producer))
			share_rate = min(0.8, share_rate + 0.05)
		var/department_share = round(export_revenue(value) * share_rate)
		department_account?.credit(department_share, "External trade", "Department-produced exports: [export.name]", "Supply shuttle")
		credit_department(DEPARTMENT_CARGO, value * 0.2, "Cargo export handling fee: [export.name]")
	for(var/account_number in export.revenue_by_producer)
		var/datum/money_account/producer = get_account(text2num(account_number))
		producer?.credit(round(export_revenue(export.revenue_by_producer[account_number]) * 0.05), "External trade", "Production bonus: [export.name]", "Supply shuttle")
	if(export.value > tagged_value)
		credit_department(DEPARTMENT_CARGO, export.value - tagged_value, "Exported goods: [export.name]")

/datum/controller/subsystem/supply/proc/budget_balance()
	var/datum/money_account/cargo = GLOB.department_accounts[DEPARTMENT_CARGO]
	return cargo?.money || 0

/datum/controller/subsystem/supply/proc/adjust_budget(amount, purpose = "External market adjustment")
	var/datum/money_account/cargo = GLOB.department_accounts[DEPARTMENT_CARGO]
	if(!cargo || !amount)
		return FALSE
	if(amount > 0)
		return cargo.credit(amount, "External market", purpose, "Cargo market")
	return cargo.debit(abs(amount), "External market", purpose, "Cargo market")

//To stop things being sent to CentCom which should not be sent to centcomm. Recursively checks for these types.
/datum/controller/subsystem/supply/proc/forbidden_atoms_check(atom/A)
	if(isliving(A))
		var/mob/living/living_content = A
		// Living passengers must never be exported accidentally. Properly dead
		// bodies, however, are legitimate freight (including contract autopsy
		// shipments) and cannot otherwise reach the outbound contract processor.
		if(living_content.stat != DEAD)
			return 1
	if(istype(A,/obj/item/disk/nuclear))
		return 1
	if(istype(A,/obj/machinery/nuclearbomb))
		return 1
	if(istype(A,/obj/item/radio/beacon))
		return 1
	if(istype(A,/obj/item/perfect_tele_beacon)) // ition: Translocator beacons
		return 1 // ition: Translocator beacons
	if(istype(A,/obj/machinery/power/quantumpad)) // // Quantum pads
		return 1 // Quantum pads
	if(istype(A,/obj/structure/extraction_point )) // Fulton beacons
		return 1

	for(var/atom/B in A.contents)
		if(.(B))
			return 1

//Selling
/datum/controller/subsystem/supply/proc/sell()
	// Loop over each area in the supply shuttle
	SEND_GLOBAL_SIGNAL(COMSIG_GLOB_SUPPLY_SHUTTLE_DEPART, shuttle.shuttle_area)
	for(var/area/subarea in shuttle.shuttle_area)
		for(var/atom/movable/MA in subarea)
			if(MA.anchored)
				continue
			process_contract_export(MA)

			var/datum/exported_crate/EC = new /datum/exported_crate()
			EC.name = "\proper[MA.name]"
			EC.value = 0
			EC.contents = list()
			if(istype(MA, /obj/structure/closet/crate))
				var/obj/structure/closet/crate/routed_crate = MA
				EC.market_bid_id = routed_crate.cargo_market_bid_id
				EC.market_router_account = routed_crate.cargo_market_router_account
				EC.market_contract_key = routed_crate.cargo_market_contract_key
				routed_crate.apply_shipping_ledger(EC)
			var/base_value = 0

			// Most items must be in a crate!
			var/list/things_sold_successfully = list()
			if(istype(MA,/obj/structure/closet/crate))
				var/obj/structure/closet/crate/CR = MA

				credit_department(DEPARTMENT_CARGO, CR.points_per_crate, "Exported shipping crate")
				if(CR.points_per_crate)
					base_value = CR.points_per_crate

				// For each thing in the crate, get the value and quantity
				CR.latent_materialize_all() // selling needs real things (C5)
				for(var/atom/A in CR) // latent-ok
					if(SEND_SIGNAL(A,COMSIG_ITEM_EXPORTED,EC,TRUE))
						things_sold_successfully += A
			else
				// Selling things that are not in crates.
				// Usually it just makes a log that it wasn't shipped properly, and so isn't worth anything
				if(SEND_SIGNAL(MA,COMSIG_ITEM_EXPORTED,EC,FALSE))
					things_sold_successfully += MA

			exported_crates += EC
			distribute_export_revenue(EC)
			EC.value += base_value

			// Duplicate the receipt for the admin-side log
			var/datum/exported_crate/adm = new()
			adm.name = EC.name
			adm.value = EC.value
			adm.contents = deepCopyList(EC.contents)
			adm.market_bid_id = EC.market_bid_id
			adm.market_counterparty_id = EC.market_counterparty_id
			adm.market_router_account = EC.market_router_account
			adm.market_premium = EC.market_premium
			adm.market_cover_name = EC.market_cover_name
			adm.market_contract_key = EC.market_contract_key
			adm.sales_ledger_id = EC.sales_ledger_id
			adm.sales_ledger_valid = EC.sales_ledger_valid
			adm.sales_department = EC.sales_department
			adm.sales_destination = EC.sales_destination
			adm.sales_eligible_value = EC.sales_eligible_value
			adm.sales_producer_percentages = EC.sales_producer_percentages?.Copy()
			adm_export_history += adm

			qdel(MA)

/datum/controller/subsystem/supply/proc/get_clear_turfs()
	var/list/clear_turfs = list()

	for(var/area/subarea in shuttle.shuttle_area)
		for(var/turf/T in subarea)
			if(T.density)
				continue
			var/occupied = 0
			for(var/atom/A in T.contents)
				if(!A.simulated)
					continue
				occupied = 1
				break
			if(!occupied)
				clear_turfs += T

	return clear_turfs

//Buying
/datum/controller/subsystem/supply/proc/buy()
	var/list/shoppinglist = list()
	for(var/datum/supply_order/SO in order_history)
		if(SO.status == SUP_ORDER_APPROVED)
			shoppinglist += SO

	var/orderedamount = length(shoppinglist)

	if(!orderedamount)
		return

	var/list/clear_turfs = get_clear_turfs()

	var/shopping_log = "SUPPLY_BUY: "

	for(var/datum/supply_order/SO in shoppinglist)
		if(!length(clear_turfs))
			break

		var/i = rand(1,length(clear_turfs))
		var/turf/pickedloc = clear_turfs[i]
		clear_turfs.Cut(i,i+1)

		SO.status = SUP_ORDER_SHIPPED
		var/datum/supply_pack/SP = SO.object
		emit_contract_event(CONTRACT_EVENT_SUPPLY_ORDER_FULFILLED, list(
			"actor_account" = SO.funding_account_number,
			"department" = SO.funding_department,
			"funding_department" = SO.funding_department,
			"order_id" = SO.ordernum,
			"pack_type" = SP.type,
			"pack_name" = SP.name,
			"pack_group" = SP.group,
			"container_type" = SP.containertype,
			"cold_chain" = ispath(SP.containertype, /obj/structure/closet/crate/freezer),
			"personal_order" = SO.personal_order,
			"fact_id" = "supply-order:[SO.ordernum]",
			"fact_revision" = 1,
			"fact_active" = TRUE,
			"metrics" = list("value" = max(1, SO.paid_amount || SO.cost)),
			"detail" = "Supply order #[SO.ordernum] ([SP.name]) arrived.",
		), "supply-order-fulfilled:[SO.ordernum]")
		if(SO.personal_order)
			notify_personal_order(SO, "Personal Cargo order #[SO.ordernum] ([SO.name]) has arrived on the supply shuttle.")
		complete_market_order(SO)
		shopping_log += "[SP.name];"

		var/obj/A
		if(SP.containertype)
			A = new SP.containertype(pickedloc)
			A.name = "[SP.containername] [SO.comment ? "([SO.comment])":"" ]"
			if(SP.access)
				if(isnum(SP.access))
					A.req_access = list(SP.access)
				else if(islist(SP.access) && SP.one_access)
					var/list/L = SP.access // access var is a plain var, we need a list
					A.req_one_access = L.Copy()
					A.req_access = null
				else if(islist(SP.access) && !SP.one_access)
					var/list/L = SP.access
					A.req_access = L.Copy()
					A.req_one_access = null
				else
					log_runtime(span_danger("Supply pack with invalid access restriction [SP.access] encountered!"))

		//supply manifest generation begin
		var/obj/item/paper/manifest/slip
		if(!SP.contraband)
			if(A)
				slip = new /obj/item/paper/manifest(A)
			else
				slip = new /obj/item/paper/manifest(pickedloc)
			slip.is_copy = 0
			slip.info = "<h3>[command_name()] Shipping Manifest</h3><hr><br>"
			slip.info +="Order #[SO.ordernum]<br>"
			slip.info +="Destination: [station_name()]<br>"
			slip.info +="[orderedamount] PACKAGES IN THIS SHIPMENT<br>"
			slip.info +="CONTENTS:<br><ul>"

		var/list/contains
		// any pack may have a variant_pool; pick from it per spawn.
		var/list/variant_pool_local = SP.variant_pool
		if(istype(SP,/datum/supply_pack/randomised))
			var/datum/supply_pack/randomised/SPR = SP
			contains = list()
			if(length(SPR.contains))
				for(var/j=1,j<=SPR.num_contained,j++)
					contains += pick(SPR.contains)
		else
			contains = SP.contains

		for(var/typepath in contains)
			if(!typepath)
				continue

			// contains values are list(count, variant); for randomised, variant comes from pool.
			var/list/spec = dq_resolve_spawn_value(contains[typepath])
			var/number_of_items = max(1, spec["count"])
			var/variant = spec["variant"]
			for(var/j = 1 to number_of_items)
				var/use_variant = variant
				if(!use_variant && length(variant_pool_local))
					use_variant = pick(variant_pool_local)
				var/atom/B2 = spawn_with_variant(typepath, A || pickedloc, use_variant)

				if(slip)
					slip.info += "<li>[B2.name]</li>" //add the item to the manifest

		//manifest finalisation
		if(slip)
			slip.info += "</ul><br>"
			slip.info += "CHECK CONTENTS AND STAMP BELOW THE LINE TO CONFIRM RECEIPT OF GOODS<hr>"

	log_game(shopping_log)
	return

// Will attempt to purchase the specified order, returning TRUE on success, FALSE on failure
/datum/controller/subsystem/supply/proc/approve_order(datum/supply_order/O, mob/user)
	if(O.paid_amount > 0 && !O.personal_order)
		return FALSE
	var/price = order_price(O)
	if(!O.personal_order)
		var/datum/money_account/funding_account = GLOB.department_accounts[O.funding_department]
		if(funding_account?.procurement_limit > 0 && price > funding_account.procurement_limit)
			return FALSE
		if(!funding_account || !funding_account.debit(price, "Supply procurement", "Order #[O.ordernum]: [O.object.name]", "Supply console"))
			return FALSE
	else if(O.paid_amount != price || !get_account(O.funding_account_number))
		return FALSE

	// Based on the current model, there shouldn't be any entries in order_history, requestlist, or shoppinglist, that aren't matched in adm_order_history
	var/datum/supply_order/adm_order
	for(var/datum/supply_order/temp in adm_order_history)
		if(temp.ordernum == O.ordernum)
			adm_order = temp
			break

	var/idname = "*None Provided*"
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		idname = H.get_authentification_name()
	else if(issilicon(user))
		idname = user.real_name

	// Update order status
	O.status = SUP_ORDER_APPROVED
	O.approved_by = idname
	O.approved_at = stationdate2text() + " - " + stationtime2text()
	// Update admin-side mirror
	if(adm_order)
		adm_order.status = SUP_ORDER_APPROVED
		adm_order.approved_by = idname
		adm_order.approved_at = stationdate2text() + " - " + stationtime2text()

	O.paid_amount = price
	if(adm_order)
		adm_order.paid_amount = price
	if(O.personal_order)
		notify_personal_order(O, "Personal Cargo order #[O.ordernum] ([O.name]) was approved.")
	return TRUE

/datum/controller/subsystem/supply/proc/notify_personal_order(datum/supply_order/O, message)
	if(!O?.personal_order || !O.funding_account_number)
		return
	for(var/obj/item/pda/device in REGISTRY_MEMBERS(REGISTRY_PDAS))
		if(device.id?.associated_account_number != O.funding_account_number)
			continue
		var/datum/data/pda/app/supply_orders/app = device.find_program(/datum/data/pda/app/supply_orders)
		app?.notify(message)

/datum/controller/subsystem/supply/proc/refund_order(datum/supply_order/O, purpose)
	if(!O || O.paid_amount <= 0 || O.status == SUP_ORDER_SHIPPED)
		return FALSE
	if(O.market_contract_funded)
		release_market_contract_funding(O)
		O.paid_amount = 0
		release_market_order_reservation(O)
		return TRUE
	var/datum/money_account/refund_account = O.personal_order ? get_account(O.funding_account_number) : GLOB.department_accounts[O.funding_department]
	if(!refund_account?.credit(O.paid_amount, "Supply procurement", purpose, "Supply console", FALSE))
		return FALSE
	record_currency_refund(O.paid_amount, TRUE)
	O.paid_amount = 0
	release_market_order_reservation(O)
	return TRUE

// Will deny the specified order. Only useful if the order is currently requested, but available at any status
/datum/controller/subsystem/supply/proc/deny_order(datum/supply_order/O, mob/user)
	// Based on the current model, there shouldn't be any entries in order_history, requestlist, or shoppinglist, that aren't matched in adm_order_history
	var/datum/supply_order/adm_order
	for(var/datum/supply_order/temp in adm_order_history)
		if(temp.ordernum == O.ordernum)
			adm_order = temp
			break

	var/idname = "*None Provided*"
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		idname = H.get_authentification_name()
	else if(issilicon(user))
		idname = user.real_name
	refund_order(O, "Refund order #[O.ordernum]: [O.object.name]")
	release_market_order_reservation(O)

	// Update order status
	O.status = SUP_ORDER_DENIED
	O.approved_by = idname
	O.approved_at = stationdate2text() + " - " + stationtime2text()
	// Update admin-side mirror
	if(adm_order)
		adm_order.status = SUP_ORDER_DENIED
		adm_order.approved_by = idname
		adm_order.approved_at = stationdate2text() + " - " + stationtime2text()
		adm_order.paid_amount = O.paid_amount
	if(O.personal_order)
		notify_personal_order(O, "Personal Cargo order #[O.ordernum] ([O.name]) was cancelled and refunded.")
	return

/datum/controller/subsystem/supply/proc/cancel_personal_order(datum/supply_order/O, datum/money_account/requester, mob/user)
	if(!O?.personal_order || O.status != SUP_ORDER_REQUESTED || !requester || O.funding_account_number != requester.account_number)
		return FALSE
	deny_order(O, user)
	return TRUE

// Will deny all requested orders
/datum/controller/subsystem/supply/proc/deny_all_pending(mob/user)
	for(var/datum/supply_order/O in order_history)
		if(O.status == SUP_ORDER_REQUESTED)
			deny_order(O, user)

// Will delete the specified order from the user-side list
/datum/controller/subsystem/supply/proc/delete_order(datum/supply_order/O, mob/user)
	// Making sure they know what they're doing
	if(tgui_alert(user, "Are you sure you want to delete this record? Paid, unshipped orders will be refunded.", "Delete Record",list("No","Yes")) == "Yes")
		if(tgui_alert(user, "Are you really sure? There is no way to recover the order once deleted.", "Delete Record", list("No","Yes")) == "Yes")
			refund_order(O, "Refund deleted order #[O.ordernum]: [O.object.name]")
			release_market_order_reservation(O)
			log_admin("[key_name(user)] has deleted supply order \ref[O] [O] from the user-side order history.")
			order_history -= O
	return

// Will generate a new, requested order, for the given supply pack type
/datum/controller/subsystem/supply/proc/create_order(datum/supply_pack/S, mob/user, reason, personal_funding = FALSE, market_listing_id, market_counterparty_id, quoted_price = 0)
	if(!S || supply_pack[S.name] != S)
		return FALSE
	var/datum/supply_order/new_order = new()
	var/datum/supply_order/adm_order = new() // Admin-recorded order must be a separate copy in memory, or user-made edits will corrupt it

	var/idname = "*None Provided*"
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		idname = H.get_authentification_name()
	else if(issilicon(user))
		idname = user.real_name

	new_order.ordernum = ++ordernum // Ordernum is used to track the order between the playerside list of orders and the adminside list
	new_order.index = new_order.ordernum // Index can be fabricated, or falsified. Ordernum is a permanent marker used to track the order
	new_order.object = S
	new_order.name = S.name
	new_order.cost = S.cost
	new_order.market_listing_id = market_listing_id
	new_order.market_counterparty_id = market_counterparty_id
	new_order.quoted_price = max(0, round(quoted_price))
	new_order.market_requester_account = contract_account_for_mob(user)?.account_number || 0
	new_order.funding_department = DEPARTMENT_CARGO
	if(ishuman(user))
		var/mob/living/carbon/human/requester = user
		var/datum/department/primary_department = SSjob.get_primary_department_of_job(requester.job)
		if(primary_department?.name in GLOB.department_accounts)
			new_order.funding_department = primary_department.name
		if(personal_funding)
			var/datum/money_account/personal_account = requester.mind?.initial_account
			var/price = order_price(new_order)
			if(!personal_account || !personal_account.debit(price, "Supply procurement", "Personal order #[new_order.ordernum]: [S.name]", "Supply console"))
				qdel(new_order)
				qdel(adm_order)
				return FALSE
			new_order.personal_order = TRUE
			new_order.funding_account_number = personal_account.account_number
			new_order.paid_amount = price
	else if(personal_funding)
		qdel(new_order)
		qdel(adm_order)
		return FALSE
	new_order.ordered_by = idname
	new_order.comment = reason
	new_order.ordered_at = stationdate2text() + " - " + stationtime2text()
	new_order.status = SUP_ORDER_REQUESTED

	adm_order.ordernum = new_order.ordernum
	adm_order.index = new_order.index
	adm_order.object = new_order.object
	adm_order.name = new_order.name
	adm_order.cost = new_order.cost
	adm_order.funding_department = new_order.funding_department
	adm_order.personal_order = new_order.personal_order
	adm_order.funding_account_number = new_order.funding_account_number
	adm_order.paid_amount = new_order.paid_amount
	adm_order.market_listing_id = new_order.market_listing_id
	adm_order.market_counterparty_id = new_order.market_counterparty_id
	adm_order.market_requester_account = new_order.market_requester_account
	adm_order.quoted_price = new_order.quoted_price
	adm_order.market_stock_reserved = new_order.market_stock_reserved
	adm_order.market_cover_name = new_order.market_cover_name
	adm_order.market_contract_key = new_order.market_contract_key
	adm_order.ordered_by = new_order.ordered_by
	adm_order.comment = new_order.comment
	adm_order.ordered_at = new_order.ordered_at
	adm_order.status = new_order.status

	order_history += new_order
	adm_order_history += adm_order
	return new_order

// Will delete the specified export receipt from the user-side list
/datum/controller/subsystem/supply/proc/delete_export(datum/exported_crate/E, mob/user)
	// Making sure they know what they're doing
	if(tgui_alert(user, "Are you sure you want to delete this record?", "Delete Record",list("No","Yes")) == "Yes")
		if(tgui_alert(user, "Are you really sure? There is no way to recover the receipt once deleted.", "Delete Record", list("No","Yes")) == "Yes")
			log_admin("[key_name(user)] has deleted export receipt \ref[E] [E] from the user-side export history.")
			exported_crates -= E
	return

// Will add an item entry to the specified export receipt on the user-side list
/datum/controller/subsystem/supply/proc/add_export_item(datum/exported_crate/E, mob/user)
	var/new_name = tgui_input_text(user, "Name", "Please enter the name of the item.")
	if(!new_name)
		return

	var/new_quantity = tgui_input_number(user, "Name", "Please enter the quantity of the item.")
	if(!new_quantity)
		return

	var/new_value = tgui_input_number(user, "Name", "Please enter the value of the item.")
	if(!new_value)
		return

	E.contents[++E.contents.len] = list(
			"object" = new_name,
			"quantity" = new_quantity,
			"value" = new_value
		)

/datum/exported_crate
	var/name
	var/value = 0
	var/list/contents
	var/list/revenue_by_department
	var/list/revenue_by_producer
	var/sales_ledger_id
	var/sales_ledger_valid = FALSE
	var/sales_department
	var/sales_destination
	var/sales_department_percent = 0
	var/sales_cargo_percent = 0
	var/list/sales_producer_percentages
	var/sales_eligible_value = 0

/datum/exported_crate/New()
	. = ..()
	contents = list()

/datum/supply_order
	var/ordernum							// Unfabricatable index
	var/index								// Fabricatable index
	var/datum/supply_pack/object = null
	var/cost								// Cost of the supply pack (Fabricatable) (Changes not reflected when purchasing supply packs, this is cosmetic only)
	var/name								// Name of the supply pack datum (Fabricatable)
	var/ordered_by = null					// Who requested the order
	var/comment = null						// What reason was given for the order
	var/approved_by = null					// Who approved the order
	var/ordered_at							// Date and time the order was requested at
	var/approved_at							// Date and time the order was approved at
	var/status								// [Requested, Accepted, Denied, Shipped]
	var/funding_department = DEPARTMENT_CARGO
	var/personal_order = FALSE
	/// Stable server-derived account identity; never accepted from UI input.
	var/funding_account_number = 0
	var/paid_amount = 0

#undef SUPPLY_THALERS_PER_LEGACY_POINT
#undef ALLOCATION_POLICY_EQUAL
#undef ALLOCATION_POLICY_STAFFING
#undef ALLOCATION_POLICY_PAYROLL
#undef DEPARTMENT_BASE_OPERATING_ALLOCATION
