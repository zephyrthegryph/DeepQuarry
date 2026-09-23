#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_economy_transfer_is_conservative

/datum/unit_test/dq_economy_transfer_is_conservative/Run()
	var/created_before = SSsupply.currency_created
	var/destroyed_before = SSsupply.currency_destroyed
	var/datum/money_account/source = new
	var/datum/money_account/target = new
	source.owner_name = "Source"
	target.owner_name = "Target"
	source.money = 100
	target.money = 25
	TEST_ASSERT(transfer_account_funds(source, target, 40, "Test transfer"), "valid transfer was rejected")
	TEST_ASSERT_EQUAL(source.money, 60, "source balance was incorrect")
	TEST_ASSERT_EQUAL(target.money, 65, "target balance was incorrect")
	TEST_ASSERT(!transfer_account_funds(source, target, 100, "Overdraft"), "overdraft transfer was accepted")
	TEST_ASSERT_EQUAL(source.money + target.money, 125, "transfer created or destroyed Thalers")
	TEST_ASSERT_EQUAL(SSsupply.currency_created, created_before, "internal transfer was counted as currency creation")
	TEST_ASSERT_EQUAL(SSsupply.currency_destroyed, destroyed_before, "internal transfer was counted as currency destruction")
	qdel(source)
	qdel(target)

/datum/unit_test/dq_economy_service_requires_funding

/datum/unit_test/dq_economy_service_requires_funding/Run()
	var/datum/money_account/original_medical = GLOB.department_accounts[DEPARTMENT_MEDICAL]
	var/datum/money_account/provider = new
	var/datum/money_account/customer = new
	provider.owner_name = "Medical test budget"
	provider.is_budget_account = TRUE
	provider.money = 0
	customer.owner_name = "Patient"
	customer.money = 0
	GLOB.department_accounts[DEPARTMENT_MEDICAL] = provider
	var/station_before = GLOB.station_account.money
	TEST_ASSERT(charge_department_service(customer, DEPARTMENT_MEDICAL, 20, "Test care"), "service charge failed")
	TEST_ASSERT_EQUAL(provider.money, 20, "poor-patient subsidy did not reach Medical")
	TEST_ASSERT_EQUAL(GLOB.station_account.money, station_before - 20, "station subsidy was not conserved")
	customer.money = 100
	provider.service_subsidy = 0
	TEST_ASSERT(!department_service_quote(customer, DEPARTMENT_MEDICAL, 120), "underfunded service purchase produced a quote")
	TEST_ASSERT(!charge_department_service(customer, DEPARTMENT_MEDICAL, 120, "Unaffordable care"), "underfunded service purchase was accepted")
	GLOB.station_account.money = station_before
	GLOB.department_accounts[DEPARTMENT_MEDICAL] = original_medical
	qdel(provider)
	qdel(customer)

/datum/unit_test/dq_department_management_scope

/datum/unit_test/dq_department_management_scope/Run()
	var/obj/machinery/computer/skills/console = new(run_loc_floor_bottom_left)
	var/obj/item/card/id/head_id = new(console)
	head_id.rank = JOB_CHIEF_ENGINEER
	head_id.assignment = JOB_CHIEF_ENGINEER
	console.scan = head_id
	TEST_ASSERT(console.can_view_department(DEPARTMENT_ENGINEERING), "Chief Engineer could not view Engineering finances")
	TEST_ASSERT(!console.can_view_department(DEPARTMENT_MEDICAL), "Chief Engineer could view Medical finances")
	TEST_ASSERT(!console.can_allocate_station_budget(), "Chief Engineer could allocate Station funds")
	head_id.access |= ACCESS_CAPTAIN
	TEST_ASSERT(console.can_allocate_station_budget(), "Captain access could not allocate Station funds")
	TEST_ASSERT(console.can_view_department(DEPARTMENT_MEDICAL), "Captain access could not view every department")
	console.authenticated = "Budget tester"
	var/list/data = console.tgui_data(null)
	TEST_ASSERT(length(data["department_finances"]), "Captain finance payload contained no department accounts")
	var/datum/money_account/engineering_budget = GLOB.department_accounts[DEPARTMENT_ENGINEERING]
	var/old_wage_multiplier = engineering_budget.wage_multiplier
	var/old_allocation = engineering_budget.monthly_allocation
	var/old_allocation_percent = engineering_budget.allocation_percent
	var/old_allocation_configured = engineering_budget.allocation_configured
	var/old_allocation_policy = SSsupply.allocation_policy
	TEST_ASSERT(console.set_department_wage(DEPARTMENT_ENGINEERING, 1.25), "valid department wage policy was rejected")
	TEST_ASSERT_EQUAL(engineering_budget.wage_multiplier, 1.25, "department wage policy did not update")
	TEST_ASSERT(console.set_department_allocation_percent(DEPARTMENT_ENGINEERING, 25), "valid recurring allocation share was rejected")
	TEST_ASSERT_EQUAL(engineering_budget.allocation_percent, 25, "recurring allocation percentage did not update")
	TEST_ASSERT(engineering_budget.allocation_configured, "explicit allocation was not recorded as a department override")
	TEST_ASSERT(console.set_department_allocation_percent(DEPARTMENT_ENGINEERING, 15), "lower recurring share was rejected")
	var/list/custom_plan = SSsupply.department_budget_plan()
	TEST_ASSERT(custom_plan["unallocated_operating"] > 0, "reducing a custom share did not retain the freed amount as operating reserve")
	TEST_ASSERT_EQUAL(SSsupply.allocation_policy, old_allocation_policy, "one department override disabled the station-wide automatic policy")
	TEST_ASSERT(SSsupply.set_allocation_policy("staffing", TRUE), "staffing allocation policy was rejected")
	TEST_ASSERT_EQUAL(SSsupply.allocation_policy, "staffing", "staffing allocation policy did not update")
	TEST_ASSERT(!engineering_budget.allocation_configured, "selecting an automatic policy did not clear stale overrides")
	TEST_ASSERT(!SSsupply.set_allocation_policy("embezzlement"), "invalid allocation policy was accepted")
	var/list/data_after_policy = console.tgui_data(null)
	var/list/finance_row = data_after_policy["department_finances"][1]
	TEST_ASSERT(!isnull(finance_row["payroll_coverage"]), "finance UI omitted expected payroll coverage")
	TEST_ASSERT(!isnull(finance_row["last_payroll_shortfall"]), "finance UI omitted last payroll shortfall")
	var/list/service_finance_row
	for(var/list/department_row as anything in data_after_policy["department_finances"])
		if(department_row["department"] == DEPARTMENT_CIVILIAN)
			service_finance_row = department_row
			break
	TEST_ASSERT(islist(service_finance_row?["service_invoices"]), "Service finance UI omitted the invoice accounting breakdown")
	engineering_budget.wage_multiplier = old_wage_multiplier
	engineering_budget.monthly_allocation = old_allocation
	engineering_budget.allocation_percent = old_allocation_percent
	engineering_budget.allocation_configured = old_allocation_configured
	SSsupply.allocation_policy = old_allocation_policy
	qdel(console)

/datum/unit_test/dq_department_budget_plan_is_immediate_and_funded

/datum/unit_test/dq_department_budget_plan_is_immediate_and_funded/Run()
	var/list/original_players = GLOB.player_list
	var/original_policy = SSsupply.allocation_policy
	var/list/original_allocations = list()
	var/list/original_percentages = list()
	var/list/original_overrides = list()
	for(var/department in GLOB.department_accounts)
		var/datum/money_account/budget = GLOB.department_accounts[department]
		original_allocations[department] = budget.monthly_allocation
		original_percentages[department] = budget.allocation_percent
		original_overrides[department] = budget.allocation_configured
		budget.allocation_configured = FALSE
	GLOB.player_list = list()
	var/mob/living/carbon/human/employee = new(run_loc_floor_bottom_left)
	employee.job = JOB_ENGINEER
	var/datum/mind/employee_mind = new("budget_plan_employee")
	var/datum/money_account/employee_account = new
	employee_account.account_number = 812345
	employee_mind.initial_account = employee_account
	employee_mind.transfer_to(employee)
	GLOB.player_list += employee
	SSsupply.allocation_policy = "equal"
	var/list/plan = SSsupply.department_budget_plan()
	var/list/departments = plan["departments"]
	var/list/engineering = departments[DEPARTMENT_ENGINEERING]
	var/list/medical = departments[DEPARTMENT_MEDICAL]
	TEST_ASSERT_EQUAL(engineering["requested"], engineering["payroll"] + 1000, "default plan did not immediately cover Engineering payroll plus its operating allowance")
	TEST_ASSERT_EQUAL(engineering["funded"], engineering["requested"], "affordable default plan did not report its exact expected funding")
	TEST_ASSERT_EQUAL(medical["requested"], 1000, "default plan did not give an unstaffed department its equal recurring operating share")
	TEST_ASSERT_EQUAL(plan["operating_requested"], plan["operating_pool"], "equal preset did not assign the complete operating pool")
	TEST_ASSERT_EQUAL(plan["payroll_funded"] + plan["operating_funded"] + plan["remaining"], plan["available"], "waterfall did not reconcile available funds")
	TEST_ASSERT_EQUAL(plan["requested"], plan["funded"] + plan["shortfall"], "budget preview did not reconcile requested, funded, and shortfall totals")
	var/datum/money_account/engineering_budget = GLOB.department_accounts[DEPARTMENT_ENGINEERING]
	engineering_budget.allocation_percent = 25
	engineering_budget.allocation_configured = TRUE
	plan = SSsupply.department_budget_plan()
	departments = plan["departments"]
	engineering = departments[DEPARTMENT_ENGINEERING]
	TEST_ASSERT_EQUAL(engineering["requested"], engineering["payroll"] + round(plan["operating_pool"] * 0.25), "department percentage override did not replace only its recurring operating share")
	TEST_ASSERT(engineering["overridden"], "budget preview did not identify the department override")
	GLOB.player_list = original_players
	SSsupply.allocation_policy = original_policy
	for(var/department in GLOB.department_accounts)
		var/datum/money_account/budget = GLOB.department_accounts[department]
		budget.monthly_allocation = original_allocations[department]
		budget.allocation_percent = original_percentages[department]
		budget.allocation_configured = original_overrides[department]
	qdel(employee_mind)
	qdel(employee)
	qdel(employee_account)

/datum/unit_test/dq_payroll_uses_all_available_funds_fairly

/datum/unit_test/dq_payroll_uses_all_available_funds_fairly/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/list/original_players = GLOB.player_list
	var/datum/money_account/original_budget = GLOB.department_accounts[DEPARTMENT_ENGINEERING]
	var/datum/money_account/test_budget = new
	test_budget.owner_name = "Test Engineering"
	test_budget.department_id = DEPARTMENT_ENGINEERING
	test_budget.is_budget_account = TRUE
	test_budget.money = 31
	GLOB.department_accounts[DEPARTMENT_ENGINEERING] = test_budget
	GLOB.player_list = list()
	var/list/employees = list()
	var/list/accounts = list()
	for(var/index in 1 to 2)
		var/mob/living/carbon/human/employee = new(test_turf)
		employee.job = JOB_ENGINEER
		var/datum/mind/employee_mind = new("payroll_test_[index]")
		var/datum/money_account/account = new
		account.owner_name = "Employee [index]"
		account.account_number = 810000 + index
		employee_mind.initial_account = account
		employee_mind.transfer_to(employee)
		GLOB.player_list += employee
		employees += employee
		accounts += account
	SSsupply.run_department_payroll()
	var/total_paid = 0
	for(var/datum/money_account/account as anything in accounts)
		TEST_ASSERT(account.money > 0, "insolvent payroll skipped an employee")
		total_paid += account.money
	TEST_ASSERT_EQUAL(total_paid, 31, "payroll did not spend every available Thaler")
	TEST_ASSERT_EQUAL(test_budget.money + test_budget.savings, 0, "payroll left spendable funds while wages were unpaid")
	GLOB.player_list = original_players
	GLOB.department_accounts[DEPARTMENT_ENGINEERING] = original_budget
	for(var/mob/living/carbon/human/employee as anything in employees)
		qdel(employee)
	for(var/datum/money_account/account as anything in accounts)
		qdel(account)
	qdel(test_budget)

/datum/unit_test/dq_department_allocations_are_proportional

/datum/unit_test/dq_department_allocations_are_proportional/Run()
	var/list/requested = list(
		DEPARTMENT_ENGINEERING = 100,
		DEPARTMENT_MEDICAL = 100,
		DEPARTMENT_RESEARCH = 100,
	)
	var/list/funded = SSsupply.proportional_department_allocations(requested, 150)
	TEST_ASSERT_EQUAL(funded[DEPARTMENT_ENGINEERING], 50, "partial station funding favored Engineering by list order")
	TEST_ASSERT_EQUAL(funded[DEPARTMENT_MEDICAL], 50, "partial station funding favored Medical by list order")
	TEST_ASSERT_EQUAL(funded[DEPARTMENT_RESEARCH], 50, "partial station funding starved Research by list order")
	TEST_ASSERT_EQUAL(funded[DEPARTMENT_ENGINEERING] + funded[DEPARTMENT_MEDICAL] + funded[DEPARTMENT_RESEARCH], 150, "proportional allocation left available station money unused")

/datum/unit_test/dq_department_budget_rollover

/datum/unit_test/dq_department_budget_rollover/Run()
	var/datum/money_account/budget = new
	budget.owner_name = "Test department"
	budget.department_id = DEPARTMENT_ENGINEERING
	budget.is_budget_account = TRUE
	budget.money = 1200
	budget.monthly_income = 300
	budget.monthly_expenses = 100
	TEST_ASSERT(budget.roll_budget_period(), "department budget refused rollover")
	TEST_ASSERT_EQUAL(budget.money, 0, "operating funds survived rollover")
	TEST_ASSERT_EQUAL(budget.savings, 1200, "unused operating funds did not enter savings")
	TEST_ASSERT_EQUAL(budget.last_month_income, 300, "monthly income history was not retained")
	TEST_ASSERT_EQUAL(budget.last_month_expenses, 100, "monthly expense history was not retained")
	TEST_ASSERT(budget.debit(200, "Test", "Savings-backed purchase"), "department could not spend retained savings")
	TEST_ASSERT_EQUAL(budget.savings, 1000, "savings-backed purchase debited the wrong amount")
	TEST_ASSERT_EQUAL(budget.available_funds(), 1000, "department spendable balance omitted retained savings")
	qdel(budget)

/datum/unit_test/dq_manual_account_creation_is_conservative

/datum/unit_test/dq_manual_account_creation_is_conservative/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/money_account/original_station = GLOB.station_account
	var/datum/money_account/test_station = new
	test_station.owner_name = "Test Station"
	test_station.money = 100
	test_station.suspended = TRUE
	GLOB.station_account = test_station
	var/obj/machinery/account_database/terminal = new(test_turf)
	var/obj/item/card/id/authorizer = new(terminal)
	authorizer.registered_name = "Account Test Captain"
	terminal.held_card = authorizer
	var/list/preexisting_packages = list()
	for(var/obj/item/smallDelivery/existing_package in test_turf)
		preexisting_packages += existing_package
	var/accounts_before = length(GLOB.all_money_accounts)
	TEST_ASSERT(!create_station_funded_account("Rejected account", 40, terminal), "suspended station budget created a funded account")
	TEST_ASSERT_EQUAL(length(GLOB.all_money_accounts), accounts_before, "failed station debit left an account behind")
	TEST_ASSERT_EQUAL(test_station.money, 100, "failed account activation changed station funds")
	var/created_before = SSsupply.currency_created
	var/destroyed_before = SSsupply.currency_destroyed
	test_station.suspended = FALSE
	var/datum/money_account/account = create_station_funded_account("Conservative account", 40, terminal)
	TEST_ASSERT(account, "valid station-funded account creation failed")
	TEST_ASSERT_EQUAL(test_station.money, 60, "station-funded account did not debit its source")
	TEST_ASSERT_EQUAL(account.money, 40, "station-funded account received the wrong opening balance")
	TEST_ASSERT_EQUAL(test_station.money + account.money, 100, "manual account creation created or destroyed Thalers")
	TEST_ASSERT_EQUAL(SSsupply.currency_created, created_before, "internal account activation was counted as external creation")
	TEST_ASSERT_EQUAL(SSsupply.currency_destroyed, destroyed_before, "internal account activation was counted as external destruction")
	GLOB.all_money_accounts -= account
	GLOB.station_account = original_station
	for(var/obj/item/smallDelivery/new_package in test_turf)
		if(!(new_package in preexisting_packages))
			qdel(new_package)
	qdel(account)
	qdel(terminal)
	qdel(test_station)

/datum/unit_test/dq_station_monthly_income_tracking

/datum/unit_test/dq_station_monthly_income_tracking/Run()
	var/datum/money_account/station = new
	station.owner_name = "Test station"
	station.department_id = "Station"
	station.is_budget_account = TRUE
	TEST_ASSERT_EQUAL(SSsupply.nt_salary_support, 0.75, "NanoTrasen salary support did not default to 75%")
	TEST_ASSERT(station.credit(750, "NanoTrasen", "Payroll support"), "station income credit failed")
	TEST_ASSERT(station.credit(250, "External trade", "Export revenue"), "secondary station income credit failed")
	TEST_ASSERT_EQUAL(station.monthly_income, 1000, "station monthly income total was incorrect")
	TEST_ASSERT_EQUAL(station.monthly_income_sources["NanoTrasen"], 750, "NanoTrasen income source was not tracked")
	TEST_ASSERT_EQUAL(station.monthly_income_sources["External trade"], 250, "trade income source was not tracked")
	TEST_ASSERT(station.roll_accounting_period(), "station accounting period refused rollover")
	TEST_ASSERT_EQUAL(station.last_month_income, 1000, "station income history was not retained")
	TEST_ASSERT_EQUAL(station.monthly_income, 0, "station income did not reset after rollover")
	qdel(station)

/datum/unit_test/dq_personal_supply_order_payment_and_refund

/datum/unit_test/dq_personal_supply_order_payment_and_refund/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/supply_pack/pack
	var/destroyed_before = SSsupply.currency_destroyed
	var/refunded_before = SSsupply.currency_refunded
	var/sink_refunded_before = SSsupply.currency_sink_refunded
	var/old_supply_sink = SSsupply.currency_sinks["Supply procurement"]
	for(var/pack_name in SSsupply.supply_pack)
		pack = SSsupply.supply_pack[pack_name]
		break
	TEST_ASSERT(pack, "supply subsystem had no packs to order")
	var/mob/living/carbon/human/requester = new(test_turf)
	var/datum/mind/requester_mind = new("personal_supply_test")
	var/datum/money_account/account = new
	account.owner_name = "Personal Supply Tester"
	account.account_number = 812345
	account.money = SSsupply.pack_price(pack) + 10
	GLOB.all_money_accounts += account
	requester_mind.initial_account = account
	requester_mind.transfer_to(requester)
	var/starting_balance = account.money
	var/datum/supply_order/order = SSsupply.create_order(pack, requester, "Personal test order", TRUE)
	TEST_ASSERT(order?.personal_order, "personal supply order was not created")
	TEST_ASSERT_EQUAL(account.money, starting_balance - SSsupply.pack_price(pack), "personal order was not charged immediately")
	TEST_ASSERT_EQUAL(order.funding_account_number, account.account_number, "personal order did not retain stable account identity")
	TEST_ASSERT(SSsupply.cancel_personal_order(order, account, requester), "owner could not cancel a pending personal order")
	TEST_ASSERT_EQUAL(account.money, starting_balance, "personal order refund did not restore the purchaser")
	TEST_ASSERT_EQUAL(order.status, SUP_ORDER_DENIED, "cancelled personal order did not enter denied state")
	SSsupply.order_history -= order
	for(var/datum/supply_order/admin_order in SSsupply.adm_order_history)
		if(admin_order.ordernum == order.ordernum)
			SSsupply.adm_order_history -= admin_order
			qdel(admin_order)
			break
	GLOB.all_money_accounts -= account
	SSsupply.currency_destroyed = destroyed_before
	SSsupply.currency_refunded = refunded_before
	SSsupply.currency_sink_refunded = sink_refunded_before
	if(isnull(old_supply_sink))
		SSsupply.currency_sinks -= "Supply procurement"
	else
		SSsupply.currency_sinks["Supply procurement"] = old_supply_sink
	qdel(order)
	qdel(requester)
	qdel(account)

/datum/unit_test/dq_service_checkout_uses_service_billing

/datum/unit_test/dq_service_checkout_uses_service_billing/Run()
	var/datum/money_account/service = GLOB.department_accounts[DEPARTMENT_CIVILIAN]
	var/service_before = service.money
	var/service_income_before = service.monthly_income
	var/service_expenses_before = service.monthly_expenses
	var/service_revenue_before = service.total_revenue
	var/service_total_expenses_before = service.total_expenses
	var/station_before = GLOB.station_account.money
	var/old_subsidy_policy = service.service_subsidy
	var/subsidies_before = SSsupply.service_subsidies
	var/invoice_counter_before = SSsupply.service_invoice_counter
	var/refunds_before = SSsupply.currency_refunded
	var/internal_refunds_before = SSsupply.currency_internal_refunded
	var/datum/money_account/customer = new
	customer.owner_name = "Hungry Tester"
	customer.account_number = 823456
	customer.money = 120
	GLOB.all_money_accounts += customer
	service.service_subsidy = 0.25
	TEST_ASSERT(!department_service_quote(customer, DEPARTMENT_CIVILIAN, 200), "underfunded Service checkout produced a quote")
	customer.money = 150
	var/list/quote = department_service_quote(customer, DEPARTMENT_CIVILIAN, 200)
	TEST_ASSERT_EQUAL(quote["personal"], 150, "Service quote calculated the wrong personal payment")
	TEST_ASSERT_EQUAL(quote["subsidy"], 50, "Service quote calculated the wrong subsidy")
	var/list/result = list()
	TEST_ASSERT(charge_department_service(customer, DEPARTMENT_CIVILIAN, 200, "Meal and drink", "Test checkout", result), "confirmed Service charge failed")
	TEST_ASSERT_EQUAL(service.money, service_before + 200, "Service checkout did not receive funded payment")
	TEST_ASSERT_EQUAL(GLOB.station_account.money, station_before - 50, "Service subsidy was not conserved")
	TEST_ASSERT_EQUAL(customer.money, 0, "Service checkout did not debit the quoted personal amount")
	var/datum/service_invoice/invoice = SSsupply.create_service_invoice(customer, service, "Test checkout", list("meal and drink" = 1), list("meal and drink" = 200), result, 0, null)
	TEST_ASSERT(invoice in SSsupply.service_invoices, "Service invoice was not added to the global ledger")
	var/mob/living/carbon/human/refund_operator = new
	refund_operator.job = JOB_BARTENDER
	TEST_ASSERT(SSsupply.refund_service_invoice(invoice, service, "Test checkout", refund_operator), "Service refund failed")
	TEST_ASSERT_EQUAL(service.money, service_before, "Service refund did not restore department funds")
	TEST_ASSERT_EQUAL(GLOB.station_account.money, station_before, "Service refund did not restore subsidy funds")
	TEST_ASSERT_EQUAL(customer.money, 150, "Service refund did not restore personal payment")
	service.service_subsidy = old_subsidy_policy
	SSsupply.service_subsidies = subsidies_before
	SSsupply.service_invoice_counter = invoice_counter_before
	SSsupply.currency_refunded = refunds_before
	SSsupply.currency_internal_refunded = internal_refunds_before
	SSsupply.service_invoices -= invoice
	service.monthly_income = service_income_before
	service.monthly_expenses = service_expenses_before
	service.total_revenue = service_revenue_before
	service.total_expenses = service_total_expenses_before
	GLOB.all_money_accounts -= customer
	qdel(invoice)
	qdel(customer)
	qdel(refund_operator)

/datum/unit_test/dq_service_invoice_adversarial

/datum/unit_test/dq_service_invoice_adversarial/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/money_account/service = GLOB.department_accounts[DEPARTMENT_CIVILIAN]
	var/service_before = service.money
	var/service_savings_before = service.savings
	var/service_income_before = service.monthly_income
	var/service_expenses_before = service.monthly_expenses
	var/service_revenue_before = service.total_revenue
	var/service_total_expenses_before = service.total_expenses
	var/old_subsidy = service.service_subsidy
	var/invoice_counter_before = SSsupply.service_invoice_counter
	var/refunds_before = SSsupply.currency_refunded
	var/internal_refunds_before = SSsupply.currency_internal_refunded
	var/datum/money_account/customer = new
	customer.owner_name = "Adversarial Customer"
	customer.account_number = 834567
	customer.money = 500
	var/datum/money_account/staff = new
	staff.owner_name = "Service Worker"
	staff.account_number = 834568
	GLOB.all_money_accounts += customer
	GLOB.all_money_accounts += staff
	service.service_subsidy = 0
	var/datum/service_invoice/invoice = complete_service_checkout(customer, service, 100, "Adversarial meal", "Destroyed terminal", list("meal" = 1), list("meal" = 100), staff.account_number, staff.owner_name, 20)
	TEST_ASSERT(invoice, "valid tipped checkout did not create an invoice")
	TEST_ASSERT_EQUAL(invoice.staff_tip, 10, "staff gratuity split was incorrect")
	TEST_ASSERT_EQUAL(invoice.service_tip, 10, "department gratuity split was incorrect")
	TEST_ASSERT_EQUAL(staff.money, 10, "staff did not receive their gratuity")
	TEST_ASSERT_EQUAL(length(SSsupply.service_invoice_rows(customer.account_number)), 1, "customer receipt lookup did not use the global ledger")
	var/datum/money_account/impostor = new
	impostor.account_number = 834569

	var/obj/item/retail_scanner/civilian/terminal = new(test_turf)
	var/mob/living/carbon/human/user = new(test_turf)
	user.job = JOB_ENGINEER
	terminal.linked_account = service
	TEST_ASSERT(!service_checkout_confirmation_valid(terminal, user, 1, 1, 100, 101, customer.account_number, customer.account_number, service, service), "changed ticket amount survived confirmation validation")
	TEST_ASSERT(!service_checkout_confirmation_valid(terminal, user, 1, 2, 100, 100, customer.account_number, customer.account_number, service, service), "equal-value itemization change survived confirmation validation")
	TEST_ASSERT(!service_checkout_confirmation_valid(terminal, user, 1, 1, 100, 100, customer.account_number, impostor.account_number, service, service), "changed ID survived confirmation validation")
	TEST_ASSERT(!service_checkout_confirmation_valid(terminal, user, 1, 1, 100, 100, customer.account_number, customer.account_number, service, GLOB.department_accounts[DEPARTMENT_RESEARCH]), "changed provider survived confirmation validation")
	TEST_ASSERT(!service_checkout_confirmation_valid(terminal, user, 1, 1, 100, 100, customer.account_number, customer.account_number, service, service, staff.account_number, impostor.account_number), "changed staff attribution survived confirmation validation")
	qdel(terminal)
	TEST_ASSERT(!service_checkout_confirmation_valid(terminal, user, 1, 1, 100, 100, customer.account_number, customer.account_number, service, service), "deleted terminal survived confirmation validation")
	TEST_ASSERT(!SSsupply.refund_service_invoice(invoice, service, "Replacement terminal", user), "an unrelated department employee could refund Service revenue")
	user.job = JOB_BARTENDER

	customer.suspended = TRUE
	TEST_ASSERT(!SSsupply.refund_service_invoice(invoice, service, "Replacement terminal", user), "refund was issued to a suspended account")
	customer.suspended = FALSE
	var/funded_service_balance = service.money
	service.money = 0
	service.savings = 0
	TEST_ASSERT(!SSsupply.refund_service_invoice(invoice, service, "Replacement terminal", user), "underfunded provider issued a refund")
	service.money = funded_service_balance
	TEST_ASSERT(transfer_account_funds(staff, impostor, staff.money, "Spent gratuity"), "test could not spend the staff gratuity")
	TEST_ASSERT(!SSsupply.refund_service_invoice(invoice, service, "Replacement terminal", user), "refund succeeded after the staff gratuity was spent")
	TEST_ASSERT_EQUAL(customer.money, 380, "failed refund changed the customer balance")
	TEST_ASSERT(transfer_account_funds(impostor, staff, invoice.staff_tip, "Return gratuity"), "test could not restore the staff gratuity")
	TEST_ASSERT(SSsupply.refund_service_invoice(invoice, service, "Replacement terminal", user), "replacement terminal could not refund a global invoice")
	TEST_ASSERT(!SSsupply.refund_service_invoice(invoice, service, "Replacement terminal", user), "duplicate refund was accepted")
	TEST_ASSERT_EQUAL(customer.money, 500, "refund did not restore purchase and gratuity")
	TEST_ASSERT_EQUAL(staff.money, 0, "refund did not reclaim the staff gratuity")
	TEST_ASSERT_EQUAL(invoice.state, "Refunded", "refund did not become the invoice's terminal state")

	SSsupply.service_invoices -= invoice
	SSsupply.service_invoice_counter = invoice_counter_before
	SSsupply.currency_refunded = refunds_before
	SSsupply.currency_internal_refunded = internal_refunds_before
	service.money = service_before
	service.savings = service_savings_before
	service.monthly_income = service_income_before
	service.monthly_expenses = service_expenses_before
	service.total_revenue = service_revenue_before
	service.total_expenses = service_total_expenses_before
	service.service_subsidy = old_subsidy
	GLOB.all_money_accounts -= customer
	GLOB.all_money_accounts -= staff
	qdel(invoice)
	qdel(impostor)
	qdel(user)
	qdel(customer)
	qdel(staff)

/datum/unit_test/dq_anonymous_service_refund_requires_provider_staff

/datum/unit_test/dq_anonymous_service_refund_requires_provider_staff/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/money_account/service = GLOB.department_accounts[DEPARTMENT_CIVILIAN]
	var/service_money_before = service.money
	var/service_expenses_before = service.monthly_expenses
	var/service_total_expenses_before = service.total_expenses
	var/invoice_counter_before = SSsupply.service_invoice_counter
	var/refunds_before = SSsupply.currency_refunded
	var/internal_refunds_before = SSsupply.currency_internal_refunded
	var/list/preexisting_cash = list()
	for(var/obj/item/spacecash/existing_cash in test_turf)
		preexisting_cash += existing_cash
	service.money += 30
	var/datum/service_invoice/invoice = SSsupply.create_service_external_invoice(service, "Anonymous refund test", list("Cash meal" = 1), list("Cash meal" = 30), "Cash customer", 30, "Cash")
	TEST_ASSERT(invoice, "anonymous cash checkout did not create an invoice")
	var/mob/living/carbon/human/operator = new(test_turf)
	operator.job = JOB_ENGINEER
	TEST_ASSERT(!SSsupply.refund_service_invoice(invoice, service, "Anonymous refund test", operator), "unrelated employee converted an anonymous invoice into cash")
	TEST_ASSERT_EQUAL(invoice.state, "Paid", "unauthorized anonymous refund changed invoice state")
	TEST_ASSERT_EQUAL(service.money, service_money_before + 30, "unauthorized anonymous refund drained Service funds")
	operator.job = JOB_BARTENDER
	TEST_ASSERT(SSsupply.refund_service_invoice(invoice, service, "Anonymous refund test", operator), "authorized Service employee could not refund an anonymous sale")
	TEST_ASSERT_EQUAL(service.money, service_money_before, "authorized anonymous refund did not reverse provider revenue")
	SSsupply.service_invoices -= invoice
	SSsupply.service_invoice_counter = invoice_counter_before
	SSsupply.currency_refunded = refunds_before
	SSsupply.currency_internal_refunded = internal_refunds_before
	service.money = service_money_before
	service.monthly_expenses = service_expenses_before
	service.total_expenses = service_total_expenses_before
	for(var/obj/item/spacecash/new_cash in test_turf)
		if(!(new_cash in preexisting_cash))
			qdel(new_cash)
	qdel(invoice)
	qdel(operator)

/datum/unit_test/dq_service_ticket_canonicalization

/datum/unit_test/dq_service_ticket_canonicalization/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/obj/item/retail_scanner/scanner = new(test_turf)
	scanner.locked = FALSE
	TEST_ASSERT(scanner.access_action("custom_order", list("purpose" = "Meal", "amount" = 2, "price" = 10), null), "scanner rejected a valid custom-order row")
	TEST_ASSERT(scanner.access_action("custom_order", list("purpose" = "Meal", "amount" = 3, "price" = 10), null), "scanner did not deterministically merge a duplicate row")
	TEST_ASSERT_EQUAL(scanner.item_list["Meal"], 5, "scanner duplicate row overwrote rather than merged quantity")
	TEST_ASSERT_EQUAL(scanner.transaction_amount, 50, "scanner total diverged from merged itemization")
	TEST_ASSERT(!scanner.access_action("custom_order", list("purpose" = "Meal", "amount" = 1, "price" = 11), null), "scanner accepted one item label with conflicting prices")
	TEST_ASSERT_EQUAL(scanner.transaction_amount, 50, "rejected scanner row changed the payable total")
	TEST_ASSERT(scanner.access_action("custom_order", list("purpose" = "Drink", "amount" = 1, "price" = 7), null), "scanner rejected a second valid custom-order row")
	TEST_ASSERT_EQUAL(scanner.transaction_amount, 57, "scanner did not derive its total from every visible row")
	TEST_ASSERT_EQUAL(service_ticket_total(scanner.item_list, scanner.price_list), scanner.transaction_amount, "scanner itemization and payable total did not reconcile")
	TEST_ASSERT(findtext(scanner.transaction_purpose, "Meal") && findtext(scanner.transaction_purpose, "Drink"), "scanner confirmation description omitted an itemized row")
	var/revision_before_invalid = scanner.ticket_revision
	var/staff_before_invalid = scanner.service_staff_account_number
	TEST_ASSERT(!scanner.access_action("custom_order", list("purpose" = "", "amount" = 1, "price" = 10), null), "scanner accepted an invalid custom order")
	TEST_ASSERT_EQUAL(scanner.ticket_revision, revision_before_invalid, "rejected scanner input mutated the ticket revision")
	TEST_ASSERT_EQUAL(scanner.service_staff_account_number, staff_before_invalid, "rejected scanner input changed staff attribution")
	var/datum/money_account/first_provider = new
	first_provider.owner_name = "First provider"
	first_provider.account_number = 884001
	first_provider.remote_access_pin = 1111
	first_provider.security_level = 1
	first_provider.is_budget_account = TRUE
	first_provider.department_id = DEPARTMENT_CIVILIAN
	var/datum/money_account/second_provider = new
	second_provider.owner_name = "Second provider"
	second_provider.account_number = 884002
	second_provider.remote_access_pin = 2222
	second_provider.security_level = 1
	second_provider.is_budget_account = TRUE
	second_provider.department_id = DEPARTMENT_CARGO
	GLOB.all_money_accounts += first_provider
	GLOB.all_money_accounts += second_provider
	scanner.linked_account = first_provider
	scanner.service_staff_account_number = 884003
	scanner.service_staff_name = "Previous worker"
	TEST_ASSERT(scanner.access_action("link_account", list("name" = "[second_provider.account_number]", "pin" = "[second_provider.remote_access_pin]"), null), "scanner rejected a valid provider relink")
	TEST_ASSERT_EQUAL(length(scanner.item_list), 0, "scanner carried an old ticket into a new provider account")
	TEST_ASSERT_EQUAL(scanner.service_staff_account_number, 0, "scanner carried old staff attribution into a new provider account")

	var/obj/machinery/cash_register/register = new(test_turf)
	register.locked = FALSE
	TEST_ASSERT(register.access_action("custom_order", list("purpose" = "Repair", "amount" = 2, "price" = 15), null), "register rejected a valid custom-order row")
	TEST_ASSERT(register.access_action("custom_order", list("purpose" = "Repair", "amount" = 1, "price" = 15), null), "register did not deterministically merge a duplicate row")
	TEST_ASSERT_EQUAL(register.item_list["Repair"], 3, "register duplicate row overwrote rather than merged quantity")
	TEST_ASSERT_EQUAL(register.transaction_amount, 45, "register total diverged from its itemization")
	TEST_ASSERT(!register.access_action("custom_order", list("purpose" = "Repair", "amount" = 1, "price" = 20), null), "register accepted one item label with conflicting prices")
	TEST_ASSERT_EQUAL(service_ticket_total(register.item_list, register.price_list), register.transaction_amount, "register itemization and payable total did not reconcile")
	register.linked_account = first_provider
	register.service_staff_account_number = 884003
	register.service_staff_name = "Previous worker"
	TEST_ASSERT(register.access_action("link_account", list("name" = "[second_provider.account_number]", "pin" = "[second_provider.remote_access_pin]"), null), "register rejected a valid provider relink")
	TEST_ASSERT_EQUAL(length(register.item_list), 0, "register carried an old ticket into a new provider account")
	TEST_ASSERT_EQUAL(register.service_staff_account_number, 0, "register carried old staff attribution into a new provider account")
	TEST_ASSERT(!SSsupply.create_service_invoice(null, first_provider, "Malformed checkout", list("Meal" = 1), list("Meal" = 10), list("total" = 10, "subsidy" = 0, "personal" = 9, "tip" = 0, "staff_tip" = 0, "service_tip" = 0), 0, null, "Malformed customer"), "invoice accepted a financial split that did not reconcile")
	GLOB.all_money_accounts -= first_provider
	GLOB.all_money_accounts -= second_provider
	qdel(scanner)
	qdel(register)
	qdel(first_provider)
	qdel(second_provider)

/datum/unit_test/dq_service_real_machine_and_pda_lifecycle

/datum/unit_test/dq_service_real_machine_and_pda_lifecycle/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/money_account/service = GLOB.department_accounts[DEPARTMENT_CIVILIAN]
	var/service_money_before = service.money
	var/service_income_before = service.monthly_income
	var/service_expenses_before = service.monthly_expenses
	var/service_revenue_before = service.total_revenue
	var/service_total_expenses_before = service.total_expenses
	var/refunds_before = SSsupply.currency_refunded
	var/internal_refunds_before = SSsupply.currency_internal_refunded
	var/invoice_counter_before = SSsupply.service_invoice_counter
	var/invoice_count_before = length(SSsupply.service_invoices)

	var/datum/money_account/customer_account = new
	customer_account.owner_name = "Lifecycle Customer"
	customer_account.account_number = 845670
	customer_account.money = 200
	GLOB.all_money_accounts += customer_account
	var/mob/living/carbon/human/customer = new(test_turf)
	var/datum/mind/customer_mind = new("service_lifecycle")
	customer_mind.initial_account = customer_account
	customer_mind.transfer_to(customer)
	var/obj/item/card/id/customer_id = new(customer)
	customer_id.registered_name = customer_account.owner_name
	customer_id.associated_account_number = customer_account.account_number
	var/obj/item/pda/customer_pda = new(customer)
	customer_pda.id = customer_id

	var/obj/machinery/cash_register/civilian/register = new(test_turf)
	register.linked_account = service
	register.transaction_amount = 25
	register.transaction_purpose = "Lifecycle meal"
	register.item_list["meal"] = 1
	register.price_list["meal"] = 25
	var/obj/item/spacecash/ewallet/wallet = new(customer)
	wallet.owner_name = customer_account.owner_name
	wallet.worth = 60
	register.scan_wallet(wallet, customer)
	TEST_ASSERT_EQUAL(wallet.worth, 35, "real register did not debit the e-wallet")
	TEST_ASSERT_EQUAL(service.money, service_money_before + 25, "real register did not credit Service for an e-wallet sale")
	var/datum/service_invoice/ewallet_invoice = SSsupply.service_invoices[length(SSsupply.service_invoices)]
	TEST_ASSERT_EQUAL(ewallet_invoice.payment_method, "E-Wallet", "e-wallet invoice recorded the wrong payment channel")

	register.transaction_amount = 30
	register.transaction_purpose = "Lifecycle cash meal"
	register.item_list["cash meal"] = 1
	register.price_list["cash meal"] = 30
	var/cash_before = register.cash_stored
	var/obj/item/spacecash/c50/cash = new(customer)
	register.scan_cash(cash, customer)
	TEST_ASSERT_EQUAL(cash.worth, 20, "real register deducted the wrong cash amount")
	TEST_ASSERT_EQUAL(register.cash_stored, cash_before, "Service cash sale remained off-books in the till")
	TEST_ASSERT_EQUAL(service.money, service_money_before + 55, "Service cash deposit did not reach the department account")
	var/datum/service_invoice/cash_invoice = SSsupply.service_invoices[length(SSsupply.service_invoices)]
	TEST_ASSERT_EQUAL(cash_invoice.payment_method, "Cash", "cash invoice recorded the wrong payment channel")

	var/datum/service_invoice/account_invoice = complete_service_checkout(customer_account, service, 40, "Lifecycle account meal", register.machine_id, list("account meal" = 1), list("account meal" = 40), 0, null, 0)
	TEST_ASSERT(account_invoice, "account checkout backend did not create an invoice")
	var/datum/data/pda/app/service_receipts/receipt_app = customer_pda.find_program(/datum/data/pda/app/service_receipts)
	var/list/pda_data = list()
	receipt_app.update_ui(customer, pda_data)
	TEST_ASSERT_EQUAL(length(pda_data["service_receipts"]), 1, "real PDA did not expose the inserted ID account's receipt")
	TEST_ASSERT_EQUAL(pda_data["service_receipts"][1]["invoice_id"], account_invoice.id, "PDA returned the wrong account receipt")
	var/list/summary = SSsupply.service_invoice_summary(DEPARTMENT_CIVILIAN)
	TEST_ASSERT(summary["invoice_count"] >= 3, "Service summary omitted real payment-channel invoices")
	TEST_ASSERT(summary["cash_sales"] >= 30, "Service summary omitted cash revenue")
	TEST_ASSERT(summary["ewallet_sales"] >= 25, "Service summary omitted e-wallet revenue")

	TEST_ASSERT(!SSsupply.refund_service_invoice(account_invoice, service, register.machine_id, customer), "a customer could refund their own Service invoice")
	var/mob/living/carbon/human/refund_operator = new(test_turf)
	refund_operator.job = JOB_BARTENDER
	TEST_ASSERT(SSsupply.refund_service_invoice(account_invoice, service, register.machine_id, refund_operator), "authorized Service staff could not refund a real invoice")
	receipt_app.update_ui(customer, pda_data)
	TEST_ASSERT_EQUAL(pda_data["service_receipts"][1]["state"], "Refunded", "PDA receipt did not update after refund")

	while(length(SSsupply.service_invoices) > invoice_count_before)
		var/datum/service_invoice/invoice = SSsupply.service_invoices[length(SSsupply.service_invoices)]
		SSsupply.service_invoices -= invoice
		qdel(invoice)
	SSsupply.service_invoice_counter = invoice_counter_before
	SSsupply.currency_refunded = refunds_before
	SSsupply.currency_internal_refunded = internal_refunds_before
	service.money = service_money_before
	service.monthly_income = service_income_before
	service.monthly_expenses = service_expenses_before
	service.total_revenue = service_revenue_before
	service.total_expenses = service_total_expenses_before
	GLOB.all_money_accounts -= customer_account
	qdel(register)
	qdel(customer_pda)
	qdel(customer)
	qdel(customer_account)
	qdel(refund_operator)

/datum/unit_test/dq_economy_shift_tracking_reset

/datum/unit_test/dq_economy_shift_tracking_reset/Run()
	var/datum/money_account/service = GLOB.department_accounts[DEPARTMENT_CIVILIAN]
	SSsupply.create_service_external_invoice(service, "Reset test", list("test" = 1), list("test" = 1), "Reset customer", 1, "Cash")
	SSsupply.currency_created = 10
	SSsupply.currency_destroyed = 5
	SSsupply.currency_refunded = 2
	SSsupply.currency_sink_refunded = 1
	SSsupply.currency_internal_refunded = 1
	SSsupply.service_subsidies = 3
	SSsupply.currency_sources["Test"] = 10
	SSsupply.currency_sinks["Test"] = 5
	SSsupply.reset_shift_economy_tracking()
	TEST_ASSERT_EQUAL(length(SSsupply.service_invoices), 0, "shift reset retained Service invoices")
	TEST_ASSERT_EQUAL(SSsupply.service_invoice_counter, 0, "shift reset retained the invoice sequence")
	TEST_ASSERT_EQUAL(SSsupply.service_accounting_period, 1, "shift reset retained the accounting period")
	TEST_ASSERT_EQUAL(SSsupply.currency_created + SSsupply.currency_destroyed + SSsupply.currency_refunded + SSsupply.currency_sink_refunded + SSsupply.currency_internal_refunded, 0, "shift reset retained currency-flow metrics")
	TEST_ASSERT_EQUAL(SSsupply.service_subsidies, 0, "shift reset retained Service subsidy metrics")
	TEST_ASSERT_EQUAL(length(SSsupply.currency_sources) + length(SSsupply.currency_sinks), 0, "shift reset retained source or sink ledgers")

/datum/unit_test/dq_economy_observatory_metrics

/datum/unit_test/dq_economy_observatory_metrics/Run()
	var/datum/economy_dashboard/dashboard = new
	var/list/data = dashboard.tgui_data(null)
	TEST_ASSERT(!isnull(data["personal_balance_median"]), "economy telemetry omitted median personal balance")
	TEST_ASSERT(!isnull(data["personal_balance_p10"]), "economy telemetry omitted low-balance percentile")
	TEST_ASSERT(!isnull(data["personal_balance_p90"]), "economy telemetry omitted high-balance percentile")
	TEST_ASSERT(!isnull(data["department_savings"]), "economy telemetry omitted department savings")
	TEST_ASSERT(!isnull(data["unpaid_wages"]), "economy telemetry omitted unpaid wages")
	TEST_ASSERT(!isnull(data["service_invoice_count"]), "economy telemetry omitted Service sales volume")
	TEST_ASSERT(!isnull(data["service_refund_rate"]), "economy telemetry omitted Service refund rate")
	TEST_ASSERT(!isnull(data["currency_created"]) && !isnull(data["currency_destroyed"]), "economy telemetry omitted currency creation or destruction")
	TEST_ASSERT(!isnull(data["currency_sink_refunded"]) && !isnull(data["currency_internal_refunded"]), "economy telemetry did not classify refund flow")
	TEST_ASSERT_EQUAL(data["net_currency_flow"], data["currency_created"] - data["currency_destroyed"] + data["currency_sink_refunded"], "economy telemetry used an unreconcilable net-flow identity")
	qdel(dashboard)

/datum/unit_test/dq_department_product_sales

/datum/unit_test/dq_department_product_sales/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/money_account/research = GLOB.department_accounts[DEPARTMENT_RESEARCH]
	var/datum/money_account/cargo = GLOB.department_accounts[DEPARTMENT_CARGO]
	var/research_before = research.money
	var/cargo_before = cargo.money
	var/research_income_before = research.monthly_income
	var/cargo_income_before = cargo.monthly_income
	var/datum/money_account/producer = new
	producer.owner_name = "Research Producer"
	producer.account_number = 918273
	producer.money = 1000
	producer.department_id = DEPARTMENT_ENGINEERING
	GLOB.all_money_accounts += producer
	var/datum/contract_definition/research_definition = SScontracts.definitions["research_export_portfolio"]
	var/datum/contract/outcome/research_contract = research_definition.create_contract(list("value_target" = 100, "variety_target" = 1))
	research_contract.reward = 0
	research_contract.base_reward = 0
	research_contract.station_reputation_reward = 0
	research_contract.department_reputation_reward = 0
	research_contract.personal_reputation_reward = 0
	research_contract.base_station_reputation_reward = 0
	research_contract.base_department_reputation_reward = 0
	research_contract.base_personal_reputation_reward = 0
	TEST_ASSERT(research_contract.accept(), "real-path Research export contract could not be accepted")
	var/datum/contract_definition/cargo_definition = SScontracts.definitions["cargo_freight_portfolio"]
	var/datum/contract/outcome/cargo_contract = cargo_definition.create_contract(list("value_target" = 100, "variety_target" = 2))
	cargo_contract.reward = 0
	cargo_contract.base_reward = 0
	cargo_contract.station_reputation_reward = 0
	cargo_contract.department_reputation_reward = 0
	cargo_contract.personal_reputation_reward = 0
	cargo_contract.base_station_reputation_reward = 0
	cargo_contract.base_department_reputation_reward = 0
	cargo_contract.base_personal_reputation_reward = 0
	TEST_ASSERT(cargo_contract.accept(), "real-path Cargo freight contract could not be accepted")

	// A real R&D output carries department/producer provenance through the generic export signal.
	var/obj/item/prototype = new(test_turf)
	prototype.name = "test R&D prototype"
	prototype.set_economic_provenance(DEPARTMENT_RESEARCH, 10, producer.account_number)
	var/datum/exported_crate/science_export = new
	TEST_ASSERT(SEND_SIGNAL(prototype, COMSIG_ITEM_EXPORTED, science_export, TRUE), "R&D prototype was not recognized as sellable cargo")
	TEST_ASSERT_EQUAL(science_export.value, 10, "R&D prototype export value was incorrect")
	SSsupply.distribute_export_revenue(science_export)
	TEST_ASSERT_EQUAL(research.money - research_before, 375, "Research did not receive its manufactured export share")
	TEST_ASSERT_EQUAL(cargo.money - cargo_before, 100, "Cargo did not receive its R&D export handling share")
	TEST_ASSERT_EQUAL(producer.money, 1025, "R&D producer did not receive their export bonus")
	TEST_ASSERT_EQUAL(research_contract.state, CONTRACT_COMPLETED, "real R&D export did not satisfy Research's portfolio")

	// Untagged salvage/raw trade belongs to Cargo and uses the same shuttle sale path.
	var/obj/item/salvage/cargo_goods = new(test_turf)
	var/datum/exported_crate/cargo_export = new
	TEST_ASSERT(SEND_SIGNAL(cargo_goods, COMSIG_ITEM_EXPORTED, cargo_export, TRUE), "Cargo salvage was not recognized as sellable cargo")
	SSsupply.distribute_export_revenue(cargo_export)
	TEST_ASSERT_EQUAL(cargo.money - cargo_before, 5100, "Cargo did not receive unassigned goods revenue plus handling fees")
	TEST_ASSERT_EQUAL(cargo_contract.state, CONTRACT_COMPLETED, "Cargo's contract did not count both handled Research freight and untagged salvage")

	// The same provenance supplies a crew-facing price through Research's departmental checkout scanner.
	var/obj/item/retail_scanner/science/scanner = new(test_turf)
	scanner.linked_account = research
	var/mob/living/carbon/human/customer = new(test_turf)
	var/obj/item/card/id/customer_id = new(customer)
	customer_id.associated_account_number = producer.account_number
	dq_test_wear_id(customer, customer_id)
	scanner.scan_item_price(prototype, customer)
	TEST_ASSERT_EQUAL(scanner.transaction_amount, 500, "R&D prototype did not receive a crew-facing Thaler price")
	var/research_before_crew_sale = research.money
	scanner.scan_card(customer_id, customer_id, customer)
	TEST_ASSERT_EQUAL(research.money - research_before_crew_sale, 500, "Crew-facing R&D sale did not credit Research")
	TEST_ASSERT_EQUAL(producer.money, 525, "Crew-facing R&D sale did not debit the purchaser")
	var/datum/service_invoice/research_invoice = SSsupply.service_invoices[length(SSsupply.service_invoices)]
	TEST_ASSERT_EQUAL(research_invoice.verified_item_count, 1, "the real Research checkout did not retain physical merchandise evidence")
	TEST_ASSERT_EQUAL(research_invoice.verified_amount, 500, "the real Research checkout recorded the wrong verified sale value")
	var/datum/component/economic_adoption/adoption = prototype.GetComponent(/datum/component/economic_adoption)
	TEST_ASSERT_NOTNULL(adoption, "the purchased prototype was not equipped with post-sale adoption tracking")
	TEST_ASSERT(adoption.record_use(customer), "the purchasing department could not record real operational use of its prototype")
	TEST_ASSERT(adoption.adopted, "operational prototype use did not publish its adoption fact")

	// Legacy fabrication queues must retain the initiating account just like the
	// modern protolathe/autolathe paths.
	var/obj/machinery/partslathe/parts_lathe = new(test_turf)
	var/datum/category_item/partslathe/test_recipe = new
	test_recipe.path = /obj/item
	test_recipe.resources = list()
	parts_lathe.addToQueue(test_recipe, producer.account_number)
	TEST_ASSERT_EQUAL(parts_lathe.queue_producer_accounts[1], producer.account_number, "parts-lathe queue discarded producer identity")
	var/obj/item/parts_output = parts_lathe.build(test_recipe, producer.account_number)
	TEST_ASSERT_EQUAL(parts_output.economic_producer_account, producer.account_number, "parts-lathe output discarded producer identity")
	var/obj/machinery/mecha_part_fabricator_tg/mech_fabricator = new(test_turf)
	var/datum/design_techweb/test_design = new
	test_design.build_path = /obj/item
	TEST_ASSERT(mech_fabricator.add_to_queue(test_design, producer.account_number), "mech fabricator rejected a valid queued design")
	TEST_ASSERT_EQUAL(mech_fabricator.queue_producer_accounts[1], producer.account_number, "mech-fabricator queue discarded producer identity")
	var/turf/fabricator_exit = get_step(test_turf, EAST)
	var/old_exit_density = fabricator_exit.density
	mech_fabricator.drop_direction = EAST
	fabricator_exit.density = TRUE
	mech_fabricator.current_producer_account = producer.account_number
	TEST_ASSERT(!mech_fabricator.dispense_built_part(test_design), "obstructed mech-fabricator unexpectedly dispensed its output")
	TEST_ASSERT_EQUAL(mech_fabricator.stored_part.economic_producer_account, producer.account_number, "obstructed mech-fabricator output lost producer provenance")
	var/obj/item/stored_mech_part = mech_fabricator.stored_part
	fabricator_exit.density = old_exit_density
	mech_fabricator.process()
	TEST_ASSERT_EQUAL(stored_mech_part.loc, fabricator_exit, "mech-fabricator did not release its provenance-tagged stored output")

	research.money = research_before
	cargo.money = cargo_before
	research.monthly_income = research_income_before
	cargo.monthly_income = cargo_income_before
	GLOB.all_money_accounts -= producer
	qdel(scanner)
	qdel(customer)
	qdel(prototype)
	qdel(cargo_goods)
	qdel(parts_output)
	qdel(parts_lathe)
	qdel(mech_fabricator)
	qdel(stored_mech_part)
	qdel(test_recipe)
	qdel(test_design)
	qdel(science_export)
	qdel(cargo_export)
	qdel(research_contract)
	qdel(cargo_contract)
	qdel(producer)

/datum/unit_test/dq_cargo_faction_market

/datum/unit_test/dq_cargo_faction_market/Run()
	TEST_ASSERT_EQUAL(length(SSsupply.market_counterparties), 9, "Cargo market did not register all faction counterparties")
	TEST_ASSERT(length(SSsupply.market_listings) > 0, "Cargo market generated no seller listings")
	TEST_ASSERT(length(SSsupply.market_bids) > 0, "Cargo market generated no buyer bids")
	for(var/listing_id in SSsupply.market_listings)
		var/datum/cargo_market_listing/listing = SSsupply.market_listings[listing_id]
		TEST_ASSERT(listing.pack && listing.unit_price > 0 && listing.stock > 0, "Cargo seller listing had invalid stock, pack, or price")
	for(var/bid_id in SSsupply.market_bids)
		var/datum/cargo_market_bid/bid = SSsupply.market_bids[bid_id]
		TEST_ASSERT(bid.profile && bid.price_multiplier > 1 && bid.target_units > 0, "Cargo buyer bid had invalid demand or pricing")

	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/obj/item/test_product = new(test_turf)
	test_product.name = "market integration prototype"
	test_product.set_economic_provenance(DEPARTMENT_RESEARCH, 20)
	var/datum/cargo_market_bid/matching_bid
	for(var/bid_id in SSsupply.market_bids)
		var/datum/cargo_market_bid/candidate = SSsupply.market_bids[bid_id]
		var/datum/cargo_market_counterparty/counterparty = SSsupply.market_counterparties[candidate.counterparty_id]
		if(!counterparty.covert && candidate.profile.matches(test_product))
			matching_bid = candidate
			break
	TEST_ASSERT_NOTNULL(matching_bid, "generated market had no visible buyer for station-manufactured Research output")
	var/fulfilled_before = matching_bid.fulfilled_units
	var/datum/exported_crate/export = new
	export.market_bid_id = matching_bid.id
	TEST_ASSERT(SEND_SIGNAL(test_product, COMSIG_ITEM_EXPORTED, export, TRUE), "routed market freight was not accepted by the generic export path")
	TEST_ASSERT(export.value > 20, "matching buyer demand did not add a market premium")
	TEST_ASSERT_EQUAL(matching_bid.fulfilled_units, fulfilled_before + 1, "market demand did not consume the routed unit")
	TEST_ASSERT_EQUAL(export.market_counterparty_id, matching_bid.counterparty_id, "export receipt lost its external buyer identity")

	var/datum/cargo_market_listing/test_listing
	for(var/listing_id in SSsupply.market_listings)
		var/datum/cargo_market_listing/candidate = SSsupply.market_listings[listing_id]
		var/datum/cargo_market_counterparty/counterparty = SSsupply.market_counterparties[candidate.counterparty_id]
		if(!counterparty.covert)
			test_listing = candidate
			break
	TEST_ASSERT_NOTNULL(test_listing, "generated market had no visible seller listing")
	var/datum/money_account/account = new
	account.account_number = 9654331
	account.owner_name = "Market Order Tester"
	GLOB.all_money_accounts += account
	var/datum/mind/test_mind = new("market_order_tester")
	test_mind.initial_account = account
	var/mob/living/carbon/human/test_buyer = new(test_turf)
	test_mind.transfer_to(test_buyer)
	var/stock_before = test_listing.stock
	var/datum/supply_order/order = SSsupply.request_market_order(test_listing, test_buyer, "Focused market test")
	TEST_ASSERT_NOTNULL(order, "valid market seller listing could not create an ordinary supply order")
	TEST_ASSERT_EQUAL(order.quoted_price, test_listing.unit_price, "market order did not preserve its immutable quoted price")
	TEST_ASSERT_EQUAL(test_listing.stock, stock_before - 1, "market order did not reserve seller stock")
	SSsupply.deny_order(order, test_buyer)
	TEST_ASSERT_EQUAL(test_listing.stock, stock_before, "denied market order did not release reserved stock")
	var/datum/supply_order/admin_order
	for(var/datum/supply_order/candidate in SSsupply.adm_order_history)
		if(candidate.ordernum == order.ordernum)
			admin_order = candidate
			break
	SSsupply.order_history -= order
	SSsupply.adm_order_history -= admin_order
	GLOB.all_money_accounts -= account
	qdel(admin_order)
	qdel(order)
	qdel(test_buyer)
	qdel(test_mind)
	qdel(account)
	qdel(test_product)
	qdel(export)

/datum/unit_test/dq_covert_market_agent_integration

/datum/unit_test/dq_covert_market_agent_integration/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/cargo_market_counterparty/syndicate_broker
	for(var/counterparty_id in SSsupply.market_counterparties)
		var/datum/cargo_market_counterparty/candidate = SSsupply.market_counterparties[counterparty_id]
		if(candidate.faction_id == REPUTATION_FACTION_SYNDICATE)
			syndicate_broker = candidate
			break
	TEST_ASSERT_NOTNULL(syndicate_broker, "Syndicate market counterparty was not registered")

	var/datum/money_account/owner_account = new
	owner_account.account_number = 9654340
	owner_account.owner_name = "Covert Principal Tester"
	owner_account.money = 10000
	GLOB.all_money_accounts += owner_account
	var/datum/mind/owner_mind = new("covert_principal_tester")
	owner_mind.initial_account = owner_account
	var/mob/living/carbon/human/owner = new(test_turf)
	owner_mind.transfer_to(owner)

	var/datum/money_account/collaborator_account = new
	collaborator_account.account_number = 9654341
	collaborator_account.owner_name = "Covert Cargo Tester"
	collaborator_account.department_id = DEPARTMENT_CARGO
	GLOB.all_money_accounts += collaborator_account
	var/datum/mind/collaborator_mind = new("covert_cargo_tester")
	collaborator_mind.initial_account = collaborator_account
	var/mob/living/carbon/human/collaborator = new(test_turf)
	collaborator_mind.transfer_to(collaborator)
	var/obj/item/card/id/collaborator_id = new(collaborator)
	collaborator_id.associated_account_number = collaborator_account.account_number
	collaborator_id.access = list(ACCESS_CARGO)
	dq_test_wear_id(collaborator, collaborator_id)

	TEST_ASSERT(!SSsupply.market_counterparty_visible(syndicate_broker, collaborator), "unapproved account could see the covert market feed")
	var/datum/faction_agent_record/record = new
	record.account_number = owner_account.account_number
	record.faction_id = REPUTATION_FACTION_SYNDICATE
	record.agent_mind = owner_mind
	record.tier = FACTION_AGENT_TIER_ACCREDITED
	GLOB.station_faction_relations.agent_records["[owner_account.account_number]"] = record
	TEST_ASSERT(SSsupply.market_counterparty_visible(syndicate_broker, owner), "accredited agent could not see their principal market")
	TEST_ASSERT(SSsupply.market_true_identity_visible(syndicate_broker, owner), "principal account could not identify its own counterparty")
	TEST_ASSERT(!SSsupply.market_counterparty_visible(syndicate_broker, collaborator), "unsigned Cargo contact could see the private feed")

	var/datum/contract/faction_agent/test_contract = new
	test_contract.definition_id = "agent_confidential_brokerage"
	test_contract.owner_account_number = owner_account.account_number
	test_contract.agent_faction = REPUTATION_FACTION_SYNDICATE
	test_contract.offer_key = "covert-market-unit-reservation"
	test_contract.offer_context = list("profile_id" = "research_goods")
	test_contract.deadline = world.time + 20 MINUTES
	test_contract.configure_custody_operation("research_goods")
	test_contract.state = CONTRACT_ACTIVE
	SScontracts.active_contracts += test_contract
	TEST_ASSERT(test_contract.register_contact(null, collaborator, AGENT_CONTACT_CONFIDENTIAL, null), "Cargo contact could not sign a per-contract confidential agreement")
	TEST_ASSERT(SSsupply.market_counterparty_visible(syndicate_broker, collaborator), "signed per-contract Cargo contact could not see the private feed")
	TEST_ASSERT(!SSsupply.market_true_identity_visible(syndicate_broker, collaborator), "Cargo contact was shown the covert principal instead of its cover identity")
	TEST_ASSERT_EQUAL(SSsupply.market_display_name(syndicate_broker, collaborator, syndicate_broker.active_cover_name), syndicate_broker.active_cover_name, "covert cover identity was not stable for a contact")
	TEST_ASSERT(SSsupply.reserve_agent_contract_market(test_contract), "accepted agent contract could not reserve a stable market route")
	TEST_ASSERT_EQUAL(length(test_contract.market_reservation_ids), 1, "targeted contract created an ambiguous number of market routes")
	var/reserved_id = test_contract.market_reservation_ids[1]
	var/datum/cargo_market_bid/reserved_bid = SSsupply.market_bid(reserved_id)
	TEST_ASSERT_NOTNULL(reserved_bid, "reserved export bid was not published")
	SSsupply.refresh_cargo_market()
	TEST_ASSERT_EQUAL(SSsupply.market_bid(reserved_id), reserved_bid, "ordinary market refresh destroyed an accepted contract route")

	var/datum/contract/faction_agent/funding_contract = new
	funding_contract.definition_id = "agent_reciprocal_trade"
	funding_contract.owner_account_number = owner_account.account_number
	funding_contract.agent_faction = REPUTATION_FACTION_SYNDICATE
	funding_contract.offer_key = "covert-market-funding-reservation"
	funding_contract.offer_context = list()
	funding_contract.deadline = world.time + 20 MINUTES
	funding_contract.market_allowance = 10000
	var/datum/contract_requirement/event_count/funding_purchase = new(CONTRACT_EVENT_CARGO_MARKET_PURCHASE, 1)
	funding_contract.add_requirement(funding_purchase)
	funding_contract.state = CONTRACT_ACTIVE
	SScontracts.active_contracts += funding_contract
	TEST_ASSERT(funding_contract.register_contact(null, collaborator, AGENT_CONTACT_STANDARD, null), "Cargo contact could not sign the allowance-backed commission")
	TEST_ASSERT(SSsupply.reserve_agent_contract_market(funding_contract), "preferred-supplier contract could not publish allowance-backed listings")
	var/datum/cargo_market_listing/funded_listing = SSsupply.market_listing(funding_contract.market_reservation_ids[1])
	TEST_ASSERT_NOTNULL(funded_listing, "contract-funded listing reservation was not addressable")
	var/owner_balance_before = owner_account.money
	var/allowance_before = funding_contract.market_allowance - funding_contract.market_spend
	var/funded_stock_before = funded_listing.stock
	var/datum/supply_order/funded_order = SSsupply.request_market_order(funded_listing, collaborator, "Contract allowance integration test", TRUE, FALSE, TRUE)
	TEST_ASSERT_NOTNULL(funded_order, "approved collaborator could not use a principal contract allowance")
	if(!funded_order)
		return
	TEST_ASSERT(funded_order.market_contract_funded && funded_order.paid_amount == funded_listing.unit_price, "contract-funded order did not retain its funding provenance")
	TEST_ASSERT_EQUAL(owner_account.money, owner_balance_before, "contract allowance incorrectly debited the agent's personal balance")
	TEST_ASSERT_EQUAL(funding_contract.market_allowance - funding_contract.market_spend, allowance_before - funded_listing.unit_price, "contract allowance did not reserve the quoted order value")
	SSsupply.deny_order(funded_order, collaborator)
	TEST_ASSERT_EQUAL(funding_contract.market_allowance - funding_contract.market_spend, allowance_before, "denied contract-funded order did not restore its allowance")
	TEST_ASSERT_EQUAL(funded_listing.stock, funded_stock_before, "denied contract-funded order did not restore private listing stock")
	var/datum/supply_order/funded_admin_order
	for(var/datum/supply_order/candidate_order in SSsupply.adm_order_history)
		if(candidate_order.ordernum == funded_order.ordernum)
			funded_admin_order = candidate_order
			break
	SSsupply.order_history -= funded_order
	SSsupply.adm_order_history -= funded_admin_order
	SScontracts.active_contracts -= funding_contract
	qdel(funded_admin_order)
	qdel(funded_order)
	qdel(funding_contract)

	var/datum/cargo_market_transaction/transaction = SSsupply.record_market_transaction(CARGO_MARKET_SELL, syndicate_broker.id, "Covert integration settlement", 1600, collaborator_account.account_number, reserved_bid.cover_name, test_contract.offer_key)
	TEST_ASSERT(transaction.covert && record.exposure > 0, "covert settlement did not create trace/exposure state")
	var/list/collaborator_ui = SSsupply.cargo_market_ui_data(collaborator)
	var/list/visible_transactions = collaborator_ui["transactions"]
	var/list/visible_transaction = visible_transactions[1]
	TEST_ASSERT_EQUAL(visible_transaction["counterparty"], transaction.cover_name, "ordinary market history leaked the covert principal name")

	var/datum/money_account/auditor_account = new
	auditor_account.account_number = 9654342
	auditor_account.owner_name = "Market Auditor"
	GLOB.all_money_accounts += auditor_account
	var/datum/mind/auditor_mind = new("market_auditor")
	auditor_mind.initial_account = auditor_account
	var/mob/living/carbon/human/auditor = new(test_turf)
	auditor_mind.transfer_to(auditor)
	var/obj/item/card/id/auditor_id = new(auditor)
	auditor_id.associated_account_number = auditor_account.account_number
	auditor_id.access = list(ACCESS_SECURITY)
	dq_test_wear_id(auditor, auditor_id)
	TEST_ASSERT(SSsupply.market_security_auditor(auditor), "test Security ID did not authorize market forensics")
	transaction.trace_strength = FACTION_AGENT_INVESTIGATION_THRESHOLD
	TEST_ASSERT(SSsupply.audit_market_transaction(transaction.id, auditor), "authorized Security account could not audit a covert settlement")
	TEST_ASSERT(transaction.detected, "deterministic forensic threshold failed to correlate a covert account")
	TEST_ASSERT_EQUAL(transaction.detected_account, owner_account.account_number, "collaborator traffic did not correlate back to its principal account")
	TEST_ASSERT(!SSsupply.audit_market_transaction(transaction.id, auditor), "the same account could repeatedly audit one settlement")
	record.tier = FACTION_AGENT_TIER_TRUSTED
	TEST_ASSERT(GLOB.station_faction_relations.activate_contract_operative(owner_account.account_number, "TEST-RED-CONTRACT", owner), "trusted Syndicate agent could not explicitly enter the bounded operative role")
	TEST_ASSERT_EQUAL(owner_mind.special_role, "Contract Operative", "red-contract opt-in did not register the antagonist role")
	TEST_ASSERT(GLOB.station_faction_relations.deactivate_contract_operative(owner_account.account_number, "TEST-RED-CONTRACT"), "closing the red contract did not remove its bounded antagonist role")
	TEST_ASSERT_NULL(owner_mind.special_role, "red-contract antagonist role outlived its contract")

	SSsupply.release_agent_contract_market(test_contract)
	TEST_ASSERT(reserved_bid.completed_at, "closed contract left its private buyer route usable")
	for(var/datum/contract_offer_candidate/offer_candidate in SScontracts.offer_candidates.Copy())
		if(offer_candidate.context?["suspect_account"] == owner_account.account_number)
			SScontracts.withdraw_candidate(offer_candidate, "Covert market test cleanup")
	GLOB.station_faction_relations.agent_records -= "[owner_account.account_number]"
	SScontracts.active_contracts -= test_contract
	SSsupply.market_transactions -= transaction
	GLOB.all_money_accounts -= owner_account
	GLOB.all_money_accounts -= collaborator_account
	GLOB.all_money_accounts -= auditor_account
	qdel(transaction)
	qdel(test_contract)
	qdel(record)
	qdel(auditor)
	qdel(auditor_mind)
	qdel(auditor_account)
	qdel(collaborator)
	qdel(collaborator_mind)
	qdel(collaborator_account)
	qdel(owner)
	qdel(owner_mind)
	qdel(owner_account)

/datum/unit_test/dq_agent_physical_freight_and_evidence

/datum/unit_test/dq_agent_physical_freight_and_evidence/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/money_account/principal_account = new
	principal_account.account_number = 9654350
	principal_account.owner_name = "Physical Principal Tester"
	GLOB.all_money_accounts += principal_account
	var/datum/money_account/contact_account = new
	contact_account.account_number = 9654351
	contact_account.owner_name = "Physical Cargo Tester"
	contact_account.department_id = DEPARTMENT_CARGO
	GLOB.all_money_accounts += contact_account
	var/datum/mind/contact_mind = new("physical_cargo_tester")
	contact_mind.initial_account = contact_account
	var/mob/living/carbon/human/contact = new(test_turf)
	contact_mind.transfer_to(contact)
	var/obj/item/card/id/contact_id = new(contact)
	contact_id.associated_account_number = contact_account.account_number
	contact_id.access = list(ACCESS_CARGO)
	dq_test_wear_id(contact, contact_id)

	var/datum/faction_agent_record/record = new
	record.account_number = principal_account.account_number
	record.faction_id = REPUTATION_FACTION_ECLIPSE
	record.tier = FACTION_AGENT_TIER_ACCREDITED
	GLOB.station_faction_relations.agent_records["[principal_account.account_number]"] = record
	var/datum/contract/faction_agent/contract = new
	contract.definition_id = "agent_confidential_brokerage"
	contract.title = "Physical freight integration"
	contract.issuer_name = "Eclipse Commercial Office"
	contract.owner_account_number = principal_account.account_number
	contract.agent_faction = REPUTATION_FACTION_ECLIPSE
	contract.offer_key = "physical-freight-unit-reservation"
	contract.offer_context = list("profile_id" = "research_goods")
	contract.deadline = world.time + 20 MINUTES
	contract.configure_custody_operation("research_goods")
	contract.state = CONTRACT_ACTIVE
	SScontracts.register_contract(contract)
	SScontracts.offered_contracts -= contract
	SScontracts.active_contracts += contract
	TEST_ASSERT(SSsupply.reserve_agent_contract_market(contract), "physical agent contract did not reserve a freight route")
	var/datum/cargo_market_bid/bid = SSsupply.market_bid(contract.market_reservation_ids[1])
	TEST_ASSERT_NOTNULL(bid, "physical agent contract had no reserved buyer")

	var/obj/item/paper/charter = create_contract_document(test_turf, "test operation charter", "<span class=\"paper_field\"></span>", contract.id, CONTRACT_DOCUMENT_AGENT_CHARTER, contract.issuer_name, list("agent_contract_id" = contract.id, "principal_account" = principal_account.account_number, "faction_id" = contract.agent_faction))
	var/datum/mind/principal_mind = new("physical_principal_tester")
	principal_mind.initial_account = principal_account
	var/mob/living/carbon/human/principal = new(test_turf)
	principal_mind.transfer_to(principal)
	var/datum/component/contract_document/charter_document = charter.GetComponent(/datum/component/contract_document)
	TEST_ASSERT(charter_document.register_agent_approach_signature(charter, principal, 2), "principal could not physically select the compartmentalized approach")
	TEST_ASSERT_EQUAL(contract.approach, AGENT_APPROACH_DISCREET, "signed charter did not lock the selected operating approach")
	var/obj/item/paper/agreement = create_contract_document(test_turf, "test freight subcontract", "<span class=\"paper_field\"></span>", contract.id, CONTRACT_DOCUMENT_AGENT_CONTACT, contract.issuer_name, list("agent_contract_id" = contract.id, "principal_account" = principal_account.account_number, "faction_id" = contract.agent_faction))
	var/datum/component/contract_document/document = agreement.GetComponent(/datum/component/contract_document)
	TEST_ASSERT(document.register_agent_contact_signature(agreement, contact, 2), "Cargo contact could not sign the physical confidential agreement")
	TEST_ASSERT_EQUAL(contract.contact_account_number, contact_account.account_number, "signed paper did not bind its Cargo contact")
	var/obj/structure/closet/crate/crate = new(test_turf)
	agreement.forceMove(crate)
	TEST_ASSERT(process_agent_contract_export(crate), "signed agreement inside the crate did not route reserved freight")
	TEST_ASSERT_EQUAL(crate.cargo_market_bid_id, bid.id, "physical agreement selected the wrong reserved buyer")
	TEST_ASSERT_EQUAL(crate.cargo_market_router_account, contact_account.account_number, "physical freight lost the signing contact identity")
	var/list/pre_cooperation_weights = contract.reward_recipient_weights()
	TEST_ASSERT_EQUAL(round(pre_cooperation_weights["[contact_account.account_number]"]), AGENT_CONTACT_CONFIDENTIAL_SHARE, "contact's negotiated cut was not preserved before settlement")
	TEST_ASSERT(document.register_agent_contact_signature(agreement, contact, 4), "signed contact could not physically withdraw and cooperate")
	TEST_ASSERT(contract.contact_cooperated, "cooperation declaration did not mark the contract contact as withdrawn")
	TEST_ASSERT_NULL(crate.cargo_market_bid_id, "withdrawn agreement left an already-loaded crate routed")
	TEST_ASSERT(!process_agent_contract_export(crate), "withdrawn agreement remained a valid physical routing credential")

	var/datum/money_account/auditor_account = new
	auditor_account.account_number = 9654352
	auditor_account.owner_name = "Physical Evidence Tester"
	GLOB.all_money_accounts += auditor_account
	var/datum/mind/auditor_mind = new("physical_evidence_tester")
	auditor_mind.initial_account = auditor_account
	var/mob/living/carbon/human/auditor = new(test_turf)
	auditor_mind.transfer_to(auditor)
	var/obj/item/card/id/auditor_id = new(auditor)
	auditor_id.associated_account_number = auditor_account.account_number
	auditor_id.access = list(ACCESS_SECURITY)
	dq_test_wear_id(auditor, auditor_id)
	contract.record_contribution(auditor_account.account_number, 10, "Authenticated third-department work", auditor_account.owner_name)
	var/list/reward_weights = contract.reward_recipient_weights()
	TEST_ASSERT(reward_weights["[auditor_account.account_number]"] > 0, "authenticated operation performer received no settlement weight")
	TEST_ASSERT(!reward_weights["[contact_account.account_number]"], "cooperating contact retained faction settlement weight after forfeiture")
	TEST_ASSERT(process_agent_forensic_scan(agreement, auditor), "Security could not scan suspicious physical agency paperwork")
	TEST_ASSERT(length(record.investigation_facts) == 1, "physical evidence did not persist a replayable investigation fact")
	TEST_ASSERT(record.exposure >= 20, "physical evidence did not expose the responsible principal")
	TEST_ASSERT_EQUAL(contract.discovery_stage, AGENT_DISCOVERY_PROVEN, "authenticated physical evidence did not advance the operation to proven discovery")
	TEST_ASSERT(document.payload["cooperation_paid"], "Security scan did not settle the physical cooperation declaration")

	SSsupply.release_agent_contract_market(contract)
	GLOB.station_faction_relations.agent_records -= "[principal_account.account_number]"
	GLOB.all_money_accounts -= principal_account
	GLOB.all_money_accounts -= contact_account
	GLOB.all_money_accounts -= auditor_account
	qdel(crate)
	qdel(charter)
	qdel(contract)
	qdel(record)
	qdel(auditor)
	qdel(auditor_mind)
	qdel(auditor_account)
	qdel(contact)
	qdel(contact_mind)
	qdel(contact_account)
	qdel(principal)
	qdel(principal_mind)
	qdel(principal_account)

/datum/unit_test/dq_physical_sales_routing

/datum/unit_test/dq_physical_sales_routing/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/obj/structure/closet/crate/crate = new(test_turf)
	var/obj/item/paper/ledger = new(crate)
	new /obj/item(crate)
	ledger.shipping_ledger_data = list(
		"id" = "FL-UNIT",
		"valid" = TRUE,
		"department" = DEPARTMENT_RESEARCH,
		"destination" = "Unit buyer",
		"department_percent" = 80,
		"cargo_percent" = 20,
		"producer_percentages" = list(),
	)
	crate.shipping_ledger = ledger
	crate.shipping_ledger_snapshot = crate.freight_snapshot()
	TEST_ASSERT(crate.shipping_ledger_valid(), "an unchanged sealed freight ledger was rejected")
	var/datum/exported_crate/export = new
	TEST_ASSERT(crate.apply_shipping_ledger(export), "a valid freight ledger was not copied to export routing")
	TEST_ASSERT_EQUAL(export.sales_department, DEPARTMENT_RESEARCH, "freight ledger lost its explicit department payee")
	var/obj/item/extra = new(crate)
	TEST_ASSERT(!crate.shipping_ledger_valid(), "adding cargo after sealing did not invalidate the freight ledger")
	TEST_ASSERT(!crate.apply_shipping_ledger(export), "tampered freight retained authenticated routing")
	TEST_ASSERT(!ledger.shipping_ledger_data["valid"], "tampered freight ledger was not visibly voided")
	ledger.shipping_ledger_data["valid"] = TRUE
	crate.shipping_ledger = ledger
	crate.shipping_ledger_snapshot = crate.freight_snapshot()
	crate.open()
	TEST_ASSERT(!ledger.shipping_ledger_data["valid"], "opening certified freight did not void its paper ledger")
	TEST_ASSERT(findtext(ledger.name, "VOID"), "voided freight paper did not visibly identify itself")

	var/datum/money_account/customer = new
	customer.account_number = 9876101
	customer.owner_name = "Storefront Unit Customer"
	customer.department_id = DEPARTMENT_ENGINEERING
	customer.money = 500
	GLOB.all_money_accounts += customer
	var/datum/mind/customer_mind = new("storefront_unit_customer")
	customer_mind.initial_account = customer
	var/turf/customer_turf = test_turf
	var/mob/living/carbon/human/customer_mob = new(customer_turf)
	customer_mind.transfer_to(customer_mob)
	customer_mob.forceMove(customer_turf)
	var/obj/item/card/id/customer_id = new(customer_mob)
	customer_id.associated_account_number = customer.account_number
	dq_test_wear_id(customer_mob, customer_id)
	var/obj/machinery/department_storefront/research/store = new(test_turf)
	var/obj/item/store_item = new(store)
	store_item.set_economic_provenance(DEPARTMENT_RESEARCH, 10, 0)
	var/item_ref = REF(store_item)
	store.stock_suggested_prices[item_ref] = 40
	store.stock_prices[item_ref] = 50
	store.stock_stocker_accounts[item_ref] = 0
	var/obj/item/second_store_item = new(store)
	second_store_item.set_economic_provenance(DEPARTMENT_RESEARCH, 10, 0)
	var/second_item_ref = REF(second_store_item)
	store.stock_suggested_prices[second_item_ref] = 40
	store.stock_prices[second_item_ref] = 50
	store.stock_stocker_accounts[second_item_ref] = 0
	var/list/store_data = store.tgui_data(customer_mob)
	var/list/stock_rows = store_data["stock"]
	TEST_ASSERT_EQUAL(length(stock_rows), 1, "identical storefront stock was not consolidated")
	var/list/stock_row = stock_rows[1]
	TEST_ASSERT_EQUAL(stock_row["quantity"], 2, "consolidated storefront quantity was incorrect")
	var/datum/money_account/research = GLOB.department_accounts[DEPARTMENT_RESEARCH]
	var/customer_before = customer.money
	var/research_before = research.money
	TEST_ASSERT_NOTNULL(customer_mob.GetIdCard(), "storefront customer ID was not wearable")
	TEST_ASSERT_EQUAL(get_account(customer_id.associated_account_number), customer, "storefront customer account was not registered")
	TEST_ASSERT_NOTNULL(department_service_quote(customer, DEPARTMENT_RESEARCH, 50), "storefront department could not quote a funded purchase")
	TEST_ASSERT(get_dist(store, customer_mob) <= 1 && store.z == customer_mob.z, "storefront customer was not in purchase range")
	TEST_ASSERT_EQUAL(store.stock_prices[item_ref], 50, "storefront lost its authoritative stock price")
	TEST_ASSERT(store.storefront_purchase(store_item, customer_mob), "a funded storefront purchase failed")
	TEST_ASSERT_EQUAL(customer.money, customer_before - 50, "storefront did not debit the advertised price")
	TEST_ASSERT_EQUAL(research.money, research_before + 50, "storefront did not credit its configured department")
	TEST_ASSERT(store_item.loc != store, "storefront retained the purchased physical item")
	TEST_ASSERT(store_item.economic_sale_invoice_id > 0, "storefront sale did not produce verified invoice evidence")
	var/datum/component/economic_adoption/adoption = store_item.GetComponent(/datum/component/economic_adoption)
	TEST_ASSERT_NOTNULL(adoption, "verified Research sale did not attach operational-use evidence to the physical item")
	TEST_ASSERT(adoption.record_use(customer_mob), "the purchasing department's first real item use did not publish adoption evidence")
	TEST_ASSERT(adoption.adopted, "operational-use evidence did not become exactly-once after publication")

	research.money = research_before
	GLOB.all_money_accounts -= customer
	qdel(store)
	qdel(customer_mob)
	qdel(customer_mind)
	qdel(customer)
	qdel(crate)
	qdel(export)
	qdel(extra)

#endif

/// Puts `id` in `H`'s ID slot, with a jumpsuit first if `H` has none (the ID
/// slot needs one).
/proc/dq_test_wear_id(mob/living/carbon/human/H, obj/item/card/id/id)
	if(!H.get_equipped_item(SLOT_ID_UNIFORM))
		H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), slot_w_uniform)
	H.equip_to_slot(id, slot_wear_id)
