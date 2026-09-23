
/datum/money_account
	var/owner_name = ""
	var/account_number = 0
	var/remote_access_pin = 0
	var/money = 0
	var/list/transaction_log
	var/suspended = 0
	var/security_level = 0	//0 - auto-identify from worn ID, require only account number
							//1 - require manual login / account number and pin
							//2 - require card and manual login
	var/offmap = FALSE //Should this account be hidden from station consoles?
	/// Stable department key for station budget accounts; null for personal accounts.
	var/department_id
	/// Budget accounts may be selected by procurement and Command allocation UIs.
	var/is_budget_account = FALSE
	/// Department policy controls, meaningful only for budget accounts.
	var/wage_multiplier = 1
	/// Station-funded operating budget applied at the start of each 15-minute budget period.
	var/monthly_allocation = 0
	/// Percentage of the recurring station operating pool assigned to this department.
	var/allocation_percent = 0
	/// TRUE once Command has deliberately overridden the automatic policy share.
	var/allocation_configured = FALSE
	/// Results of the most recently completed payroll cycle.
	var/last_payroll_due = 0
	var/last_payroll_paid = 0
	/// Unspent operating funds retained across budget periods.
	var/savings = 0
	/// Income and expenditure since the most recent budget rollover.
	var/monthly_income = 0
	var/monthly_expenses = 0
	var/last_month_income = 0
	var/last_month_expenses = 0
	/// Current-period income grouped by payer/source for Command reporting.
	var/list/monthly_income_sources
	var/list/last_month_income_sources
	var/export_share = 0.75
	var/service_subsidy = 0
	var/procurement_limit = 0
	var/total_revenue = 0
	var/total_expenses = 0

/datum/money_account/proc/record_transaction(target, purpose, amount, terminal_id)
	var/datum/transaction/transaction = new
	transaction.target_name = target
	transaction.purpose = purpose
	transaction.amount = amount < 0 ? "([abs(amount)])" : "[amount]"
	transaction.date = GLOB.current_date_string
	transaction.time = stationtime2text()
	transaction.source_terminal = terminal_id
	LAZYADD(transaction_log, transaction)

/datum/money_account/proc/credit(amount, source_name, purpose, terminal_id = "Station budget ledger", external = TRUE, allow_suspended = FALSE)
	if(!isnum(amount) || amount <= 0 || (suspended && !allow_suspended))
		return FALSE
	money += amount
	record_transaction(source_name, purpose, amount, terminal_id)
	total_revenue += amount
	if(tracks_budget_period())
		monthly_income += amount
		LAZYINITLIST(monthly_income_sources)
		monthly_income_sources[source_name] = (monthly_income_sources[source_name] || 0) + amount
	if(external)
		SSsupply?.record_currency_created(amount, source_name)
	return TRUE

/datum/money_account/proc/debit(amount, target_name, purpose, terminal_id = "Station budget ledger", external = TRUE)
	if(!isnum(amount) || amount <= 0 || suspended)
		return FALSE
	var/available = available_funds()
	if(available < amount)
		return FALSE
	var/operating_spend = min(money, amount)
	money -= operating_spend
	if(operating_spend < amount)
		savings -= amount - operating_spend
	record_transaction(target_name, purpose, -amount, terminal_id)
	total_expenses += amount
	if(tracks_budget_period())
		monthly_expenses += amount
	if(external)
		SSsupply?.record_currency_destroyed(amount, target_name)
	return TRUE

/datum/money_account/proc/available_funds()
	return money + (is_department_budget() ? savings : 0)

/datum/money_account/proc/is_department_budget()
	return is_budget_account && department_id && department_id != "Station" && department_id != "Vendor"

/datum/money_account/proc/tracks_budget_period()
	return is_budget_account && department_id && department_id != "Vendor"

/datum/money_account/proc/roll_accounting_period()
	if(!tracks_budget_period())
		return FALSE
	last_month_income = monthly_income
	last_month_expenses = monthly_expenses
	last_month_income_sources = monthly_income_sources
	monthly_income = 0
	monthly_expenses = 0
	monthly_income_sources = null
	return TRUE

/datum/money_account/proc/roll_budget_period()
	if(!is_department_budget())
		return FALSE
	roll_accounting_period()
	if(money > 0)
		savings += money
		record_transaction(owner_name, "Unused operating funds moved to savings", 0, "Automated budget cycle")
		money = 0
	return TRUE

/proc/department_for_mob(mob/living/user)
	if(!istype(user) || !user.job)
		return
	var/datum/department/department = SSjob.get_primary_department_of_job(user.job)
	if(department?.name in GLOB.department_accounts)
		return department.name

/// Quotes a personal account for station services. A subsidy may cover part of
/// the price, but the remaining amount must be available before checkout.
/proc/department_service_quote(datum/money_account/customer, department, amount)
	var/datum/money_account/provider = GLOB.department_accounts[department]
	if(!customer || !provider || customer.suspended || provider.suspended || !isnum(amount) || amount <= 0 || customer == provider)
		return
	amount = round(amount)
	var/subsidy = 0
	if(customer.money < 100)
		subsidy = min(amount, GLOB.station_account?.money || 0)
	else if(provider.service_subsidy > 0)
		subsidy = min(amount, round(amount * provider.service_subsidy), GLOB.station_account?.money || 0)
	var/remainder = amount - subsidy
	if(customer.money < remainder)
		return
	return list(
		"total" = amount,
		"subsidy" = subsidy,
		"personal" = remainder
	)

/proc/charge_department_service(datum/money_account/customer, department, amount, purpose, provider_name = "Station services", list/result)
	var/datum/money_account/provider = GLOB.department_accounts[department]
	var/list/quote = department_service_quote(customer, department, amount)
	if(!provider || !quote)
		return FALSE
	amount = quote["total"]
	var/subsidy = quote["subsidy"]
	if(subsidy > 0)
		if(!transfer_account_funds(GLOB.station_account, provider, subsidy, "Subsidy: [purpose]", provider_name))
			return FALSE
		SSsupply.service_subsidies += subsidy
	var/paid = quote["personal"]
	if(paid > 0 && customer.debit(paid, provider.owner_name, purpose, provider_name, FALSE))
		provider.credit(paid, customer.owner_name, purpose, provider_name, FALSE)
	if(result)
		result += quote
	return TRUE

/proc/charge_mob_for_department_service(mob/living/customer_mob, department, amount, purpose, provider_name)
	var/obj/item/card/id/id = customer_mob?.GetIdCard()
	var/datum/money_account/customer = id ? get_account(id.associated_account_number) : customer_mob?.mind?.initial_account
	return charge_department_service(customer, department, amount, purpose, provider_name)

/proc/transfer_account_funds(datum/money_account/source, datum/money_account/target, amount, purpose, terminal_id = "Station budget ledger")
	if(!source || !target || source == target || !isnum(amount) || amount <= 0 || target.suspended)
		return FALSE
	if(!source.debit(amount, target.owner_name, purpose, terminal_id, FALSE))
		return FALSE
	if(!target.credit(amount, source.owner_name, purpose, terminal_id, FALSE))
		// Target state changed between checks. Restore the source and retain an
		// auditable reversal rather than losing funds.
		source.credit(amount, target.owner_name, "Reversal: [purpose]", terminal_id, FALSE)
		return FALSE
	emit_contract_event(CONTRACT_EVENT_MONEY_TRANSFERRED, list(
		"actor_account" = source.account_number,
		"actor_name" = source.owner_name,
		"actor_department" = source.department_id,
		"source_account" = source.account_number,
		"source_department" = source.department_id,
		"target_account" = target.account_number,
		"target_department" = target.department_id,
		"source_is_station" = source == GLOB.station_account,
		"target_is_department" = target.is_department_budget(),
		"purpose" = purpose,
		"terminal_id" = terminal_id,
		"metrics" = list("amount" = amount),
		"detail" = "Transferred [amount] Thalers from [source.owner_name] to [target.owner_name]",
	))
	return TRUE

/datum/transaction
	var/target_name = ""
	var/purpose = ""
	var/amount = 0
	var/date = ""
	var/time = ""
	var/source_terminal = ""

/proc/create_account(new_owner_name = "Default user", starting_funds = 0, obj/machinery/account_database/source_db, offmap = FALSE)

	//create a new account
	var/datum/money_account/M = new()
	M.offmap = offmap
	M.owner_name = new_owner_name
	M.remote_access_pin = rand(1111, 111111)
	M.money = starting_funds

	//create an entry in the account transaction log for when it was created
	var/datum/transaction/T = new()
	T.target_name = new_owner_name
	T.purpose = "Account creation"
	T.amount = starting_funds
	if(!source_db)
		//set a random date, time and location some time over the past few decades
		T.date = "[num2text(rand(1,28))] [pick("January","February","March","April","May","June","July","August","September","October","November","December")], 23[rand(12,19)]"
		T.time = "[rand(0,24)]:[rand(11,59)]"
		T.source_terminal = "NTGalaxyNet Terminal #[rand(111,1111)]"

		M.account_number = rand(111111, 999999)
	else
		T.date = GLOB.current_date_string
		T.time = stationtime2text()
		T.source_terminal = source_db.machine_id

		M.account_number = GLOB.next_account_number
		GLOB.next_account_number += rand(1,25)

		//create a sealed package containing the account details
		var/obj/item/smallDelivery/P = new /obj/item/smallDelivery(source_db.loc)

		var/obj/item/paper/R = new /obj/item/paper(P)
		P.wrapped = R
		R.name = "Account information: [M.owner_name]"
		R.info = span_bold("Account details (confidential)") + "<br><hr><br>"
		R.info += "<i>Account holder:</i> [M.owner_name]<br>"
		R.info += "<i>Account number:</i> [M.account_number]<br>"
		R.info += "<i>Account pin:</i> [M.remote_access_pin]<br>"
		R.info += "<i>Starting balance:</i> $[M.money]<br>"
		R.info += "<i>Date and time:</i> [stationtime2text()], [GLOB.current_date_string]<br><br>"
		R.info += "<i>Creation terminal ID:</i> [source_db.machine_id]<br>"
		R.info += "<i>Authorised NT officer overseeing creation:</i> [source_db.held_card.registered_name]<br>"

		//stamp the paper
		var/image/stampoverlay = image('icons/obj/bureaucracy.dmi')
		stampoverlay.icon_state = "paper_stamp-cent"
		if(!R.stamped)
			R.stamped = new
		R.stamped += /obj/item/stamp
		R.add_overlay(stampoverlay)
		R.stamps += "<HR><i>This paper has been stamped by the Accounts Database.</i>"

	//add the account
	LAZYADD(M.transaction_log, T)
	GLOB.all_money_accounts.Add(M)

	return M

/// Create an on-station account whose opening balance is transferred from the
/// station budget. The debit happens first so a suspended or underfunded
/// station account can never leave behind newly minted funds.
/proc/create_station_funded_account(new_owner_name, starting_funds, obj/machinery/account_database/source_db)
	if(!source_db || !new_owner_name || !isnum(starting_funds) || starting_funds < 0)
		return
	starting_funds = round(starting_funds)
	if(starting_funds > 0 && !GLOB.station_account?.debit(starting_funds, new_owner_name, "New account activation", source_db.machine_id, FALSE))
		return
	var/datum/money_account/account = create_account(new_owner_name, starting_funds, source_db)
	if(!account && starting_funds > 0)
		// This is restoration of already-owned internal money, so suspension must
		// freeze access rather than destroy the balance during rollback.
		GLOB.station_account?.credit(starting_funds, new_owner_name, "Reversal: new account activation", source_db.machine_id, FALSE, TRUE)
	return account

/proc/charge_to_account(attempt_account_number, source_name, purpose, terminal_id, amount)
	for(var/datum/money_account/D in GLOB.all_money_accounts)
		if(D.account_number == attempt_account_number && !D.suspended)
			if(amount > 0)
				return D.credit(amount, source_name, purpose, terminal_id)
			if(amount < 0)
				return D.debit(abs(amount), source_name, purpose, terminal_id)
			return TRUE

	return 0

//this returns the first account datum that matches the supplied accnum/pin combination, it returns null if the combination did not match any account
/proc/attempt_account_access(attempt_account_number, attempt_pin_number, security_level_passed = 0)
	for(var/datum/money_account/D in GLOB.all_money_accounts)
		if(D.account_number == attempt_account_number)
			if( D.security_level <= security_level_passed && (!D.security_level || D.remote_access_pin == attempt_pin_number) )
				return D
			break

/proc/get_account(account_number)
	for(var/datum/money_account/D in GLOB.all_money_accounts)
		if(D.account_number == account_number)
			return D

//Performing purchases by ID card
/proc/purchase_with_id_card(obj/item/card/id/I, mob/M, purchase_title = "Company", purchase_terminal = "Terminal", purchase_desc = "Purchase of Something", price = 0, datum/money_account/recipient)
	// Check if account can pay at all
	var/datum/money_account/customer_account = get_account(I.associated_account_number)
	if(!customer_account)
		to_chat(M, span_warning("Error: Unable to access account. Please contact technical support if problem persists."))
		return FALSE
	if(customer_account.suspended)
		to_chat(M, span_warning("Unable to access account: account suspended."))
		return FALSE
	// Have the customer punch in the PIN before checking if there's enough money. Prevents people from figuring out acct is
	// empty at high security levels
	if(customer_account.security_level != 0) //If card requires pin authentication (ie seclevel 1 or 2)
		var/attempt_pin = tgui_input_number(M, "Enter pin code", "Vendor transaction")
		customer_account = attempt_account_access(I.associated_account_number, attempt_pin, 2)
		if(!customer_account)
			to_chat(M, span_warning("Unable to access account: incorrect credentials."))
			return FALSE
	if(price > customer_account.money)
		to_chat(M, span_warning("Insufficient funds in account."))
		return FALSE
	if(price <= 0)
		return TRUE
	if(recipient)
		return transfer_account_funds(customer_account, recipient, price, purchase_desc, purchase_terminal)
	return customer_account.debit(price, "[purchase_title] (via [purchase_terminal])", purchase_desc, purchase_terminal)
