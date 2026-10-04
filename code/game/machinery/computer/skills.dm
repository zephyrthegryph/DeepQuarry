//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

#define GENERAL_RECORD_LIST 2
#define GENERAL_RECORD_MAINT 3
#define GENERAL_RECORD_DATA 4
#define GENERAL_RECORD_FINANCES 5
#define GENERAL_RECORD_CONTRACTS 6

#define FIELD(N, V, E) list(field = N, value = V, edit = E)

/obj/machinery/computer/skills//TODO:SANITY //[TO DO] Change name to PCU and update mapdata to include replacement computers
	name = "department management console"
	desc = "A secure management console for employment records, departmental finances, and station budget allocation."
	icon_screen = "pcu_generic"
	icon_state = "pcu"
	icon_keyboard = "pcu_key"
	light_color = "#5284e7"
	req_one_access = list(ACCESS_HEADS)
	circuit = /obj/item/circuitboard/skills/pcu
	density = FALSE
	var/obj/item/card/id/scan = null
	var/authenticated = null
	var/rank = null
	var/screen = null
	var/datum/data/record/active1
	var/a_id = null
	var/list/temp = null
	var/printing = null
	var/can_change_id = 0
	// The below are used to make modal generation more convenient
	var/static/list/field_edit_questions
	var/static/list/field_edit_choices

/obj/machinery/computer/skills/Initialize(mapload)
	. = ..()
	field_edit_questions = list(
		// General
		"name" = "Please input new name:",
		"id" = "Please input new ID:",
		"sex" = "Please select new sex:",
		"species" = "Please input new species:",
		"age" = "Please input new age:",
		"fingerprint" = "Please input new fingerprint hash:",
		"home_system" = "Please input new home:",
		"birthplace" = "Please input new birthplace:",
		"citizenship" = "Please input new citizenship:",
		"languages" = "Please input known languages:",
		"faction" = "Please input the corrected employer:",
		"religion" = "Please input new religion:",
	)
	field_edit_choices = list(
		// General
		"sex" = all_genders_text_list,
		"p_stat" = list("*Deceased*", "*SSD*", "Active", "Physically Unfit", "Disabled"),
		"m_stat" = list("*Insane*", "*Unstable*", "*Watch*", "Stable"),
	)

/obj/machinery/computer/skills/proc/can_allocate_station_budget()
	return scan && ((ACCESS_CAPTAIN in scan.access) || (ACCESS_HOP in scan.access) || (ACCESS_CENT_CAPTAIN in scan.access))

/obj/machinery/computer/skills/proc/can_view_department(department)
	if(!scan || !(department in GLOB.department_accounts))
		return FALSE
	if(can_allocate_station_budget())
		return TRUE
	var/datum/job/job = SSjob.get_job(scan.rank || scan.assignment)
	return istype(job) && (department in job.department_accounts)

/obj/machinery/computer/skills/proc/finance_transaction_rows(datum/money_account/account)
	var/list/rows = list()
	var/start = max(1, length(account.transaction_log) - 49)
	for(var/index = length(account.transaction_log), index >= start, index--)
		var/datum/transaction/transaction = LAZYACCESS(account.transaction_log, index)
		rows.Add(list(list(
			"date" = transaction.date,
			"time" = transaction.time,
			"target" = transaction.target_name,
			"purpose" = transaction.purpose,
			"amount" = transaction.amount,
			"terminal" = transaction.source_terminal
		)))
	return rows

/obj/machinery/computer/skills/proc/finance_income_source_rows(datum/money_account/account)
	var/list/rows = list()
	for(var/source in account.monthly_income_sources)
		rows.Add(list(list(
			"source" = source,
			"amount" = account.monthly_income_sources[source]
		)))
	return rows

/obj/machinery/computer/skills/proc/set_department_wage(department, new_multiplier)
	var/datum/money_account/budget = GLOB.department_accounts[department]
	if(!budget || !isnum(new_multiplier) || new_multiplier < 0.5 || new_multiplier > 2 || !can_view_department(department))
		return FALSE
	budget.wage_multiplier = new_multiplier
	budget.record_transaction(authenticated, "Department wage policy set to x[budget.wage_multiplier]", 0, name)
	return TRUE

/obj/machinery/computer/skills/proc/set_department_allocation_percent(department, percent, mob/living/user = null)
	if(!can_allocate_station_budget() || !isnum(percent) || percent < 0 || percent > 100)
		return FALSE
	var/datum/money_account/budget = GLOB.department_accounts[department]
	if(!budget || department == "Vendor")
		return FALSE
	// The first manual edit freezes the currently previewed policy shares into a
	// coherent custom plan. Further edits then create or consume an explicit
	// reserve instead of silently redistributing every other department.
	var/list/current_plan = SSsupply.department_budget_plan()
	var/list/current_departments = current_plan["departments"]
	var/fixed_other_percent = 0
	var/automatic_other_percent = 0
	for(var/other_department in GLOB.department_accounts)
		if(other_department == department || other_department == "Vendor")
			continue
		var/datum/money_account/other_budget = GLOB.department_accounts[other_department]
		var/list/other_plan = current_departments?[other_department]
		if(!other_budget?.is_department_budget())
			continue
		if(other_budget.allocation_configured)
			fixed_other_percent += other_plan?["allocation_percent"] || 0
		else
			automatic_other_percent += other_plan?["allocation_percent"] || 0
	if(fixed_other_percent + percent > 100.001)
		return FALSE
	var/automatic_scale = 1
	if(fixed_other_percent + automatic_other_percent + percent > 100 && automatic_other_percent > 0)
		automatic_scale = max(0, 100 - fixed_other_percent - percent) / automatic_other_percent
	for(var/other_department in GLOB.department_accounts)
		var/datum/money_account/other_budget = GLOB.department_accounts[other_department]
		var/list/other_plan = current_departments?[other_department]
		if(!other_budget?.is_department_budget() || !other_plan)
			continue
		var/effective_percent = other_plan["allocation_percent"]
		if(other_department != department && !other_budget.allocation_configured)
			effective_percent *= automatic_scale
		other_budget.allocation_percent = effective_percent
		other_budget.allocation_configured = TRUE
	var/old_percent = budget.allocation_percent
	var/old_requested = current_departments?[department]?["requested"] || 0
	budget.allocation_percent = percent
	budget.allocation_configured = TRUE
	budget.record_transaction(authenticated, "Recurring operating share set to [percent]%", 0, name)
	if(old_percent != percent)
		var/list/plan = SSsupply.department_budget_plan()
		var/list/department_plan = plan["departments"]?[department]
		// Report only the change in the planned request, never the whole
		// figure: a policy edit is a plan, and re-toggling a plan is not new aid.
		var/requested_delta = max(0, (department_plan?["requested"] || 0) - old_requested)
		emit_contract_event(CONTRACT_EVENT_BUDGET_ALLOCATION_CHANGED, list(
			"department" = DEPARTMENT_COMMAND,
			"source_department" = "Station",
			"target_department" = department,
			"target_account" = budget.account_number,
			"target_is_department" = budget.is_department_budget(),
			"metrics" = list("amount" = requested_delta, "allocation_percent" = percent),
			"detail" = "Assigned [department] [percent]% of the recurring operating pool",
		), "budget-allocation:[REF(budget)]:[world.time]:[percent]", src, user)
	return TRUE

/obj/machinery/computer/skills/proc/transfer_department_funds(department, amount, mob/living/user = null)
	if(!can_allocate_station_budget() || !isnum(amount) || amount <= 0)
		return FALSE
	var/datum/money_account/budget = GLOB.department_accounts[department]
	if(!budget?.is_department_budget())
		return FALSE
	amount = round(amount)
	if(!transfer_account_funds(GLOB.station_account, budget, amount, "One-time Command funding", name))
		to_chat(user, span_warning("The station account cannot fund that transfer."))
		return FALSE
	to_chat(user, span_notice("Transferred [amount] Thalers to [department]."))
	// Money actually moved, so this counts as settled aid.
	emit_contract_event(CONTRACT_EVENT_BUDGET_ALLOCATION_CHANGED, list(
		"department" = DEPARTMENT_COMMAND,
		"source_department" = "Station",
		"target_department" = department,
		"target_account" = budget.account_number,
		"target_is_department" = TRUE,
		"metrics" = list("amount" = amount, "settled" = 1),
		"detail" = "Transferred [amount] Thalers of one-time Command funding to [department]",
	), "budget-transfer:[REF(budget)]:[world.time]:[amount]", src, user)
	return TRUE

/obj/machinery/computer/skills/proc/clear_department_allocation(department, mob/living/user = null)
	if(!can_allocate_station_budget())
		return FALSE
	var/datum/money_account/budget = GLOB.department_accounts[department]
	if(!budget?.is_department_budget() || !budget.allocation_configured)
		return FALSE
	budget.allocation_configured = FALSE
	var/list/plan = SSsupply.department_budget_plan()
	var/list/department_plan = plan["departments"]?[department]
	var/old_requested = budget.monthly_allocation
	budget.allocation_percent = 0
	budget.monthly_allocation = department_plan?["requested"] || 0
	budget.record_transaction(authenticated, "Recurring operating share returned to automatic policy", 0, name)
	emit_contract_event(CONTRACT_EVENT_BUDGET_ALLOCATION_CHANGED, list(
		"department" = DEPARTMENT_COMMAND,
		"source_department" = "Station",
		"target_department" = department,
		"target_account" = budget.account_number,
		"target_is_department" = TRUE,
		"metrics" = list("amount" = max(0, budget.monthly_allocation - old_requested)),
		"detail" = "Returned [department] to the automatic recurring funding policy",
	), "budget-allocation:[REF(budget)]:[world.time]:automatic", src, user)
	return TRUE

/obj/machinery/computer/skills/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/skills_insert_id,
		/datum/interaction/machine_hand/skills_open_ui,
	)
	..()

/// Old attackby: insert an ID card, else falls through to ..().
/datum/interaction/machine_item/skills_insert_id
	id = "skills_insert_id"
	name = "Insert ID"
	held_type = /obj/item/card/id
	effect = /obj/machinery/computer/skills/proc/interaction_insert_id

/obj/machinery/computer/skills/proc/interaction_insert_id(mob/user, obj/item/O, datum/interaction/interaction)
	if(scan)
		return FALSE
	if(!move_into(src, nameof(src.scan), O, user))
		return FALSE
	to_chat(user, "You insert [O].")
	tgui_interact(user)
	return TRUE

//Someone needs to break down the dat += into chunks instead of long ass lines.
/// Old attack_hand.
/datum/interaction/machine_hand/skills_open_ui
	id = "skills_open_ui"
	name = "Use"
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null), REQ_ON(PRED_TARGET, /obj/machinery/computer/skills/proc/within_contact_range, "you're too far away from the station!"))
	effect = /obj/machinery/computer/skills/proc/interaction_open_ui_impl

/// Requirement clause: no message (like the old check) beyond the reason text.
/obj/machinery/computer/skills/proc/within_contact_range(mob/actor, atom/target, obj/item/held)
	var/obj/machinery/computer/skills/machine = target
	return !using_map || (machine.z in using_map.contact_levels)

/obj/machinery/computer/skills/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	tgui_interact(user)
	return TRUE

DECLARE_UI(/obj/machinery/computer/skills, "GeneralRecords", UI_TITLE("Department Management"))

UI_DATA_REPLACE(/obj/machinery/computer/skills, "temp:text", "authenticated", "rank", "screen:num", "printing:num", "merge:ui_data_obj_machinery_computer_skills{scan:text,isAI:num,isRobot:num,can_allocate_station_budget:unknown,station_balance:num,station_monthly_income:num,station_monthly_expenses:num,station_income_sources:unknown,nt_salary_support:num,allocation_policy:unknown,next_budget_cycle:num,budget_plan:unknown,department_finances:list,station_transactions:unknown,contract_departments:list,contract_faction_standings:list,contracts:list,records:list,general:list,modal:unknown}")

/// The computed part of /obj/machinery/computer/skills's window data (declared on its UI_DATA row).
/obj/machinery/computer/skills/proc/ui_data_obj_machinery_computer_skills(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["scan"] = scan ? scan.name : null
	data["isAI"] = isAI(user)
	data["isRobot"] = isrobot(user)
	if(authenticated)
		var/list/budget_plan = SSsupply.department_budget_plan()
		var/list/planned_departments = budget_plan["departments"]
		data["can_allocate_station_budget"] = can_allocate_station_budget()
		data["station_balance"] = can_allocate_station_budget() ? GLOB.station_account.money : null
		data["station_monthly_income"] = can_allocate_station_budget() ? GLOB.station_account.monthly_income : null
		data["station_monthly_expenses"] = can_allocate_station_budget() ? GLOB.station_account.monthly_expenses : null
		data["station_income_sources"] = can_allocate_station_budget() ? finance_income_source_rows(GLOB.station_account) : list()
		data["nt_salary_support"] = can_allocate_station_budget() ? SSsupply.nt_salary_support : null
		data["allocation_policy"] = can_allocate_station_budget() ? SSsupply.allocation_policy : null
		data["next_budget_cycle"] = DisplayTimeText(max(0, SSsupply.next_payroll - world.time), 1)
		data["budget_plan"] = can_allocate_station_budget() ? list(
			"projected_payroll" = budget_plan["projected_payroll"],
			"nt_grant" = budget_plan["nt_grant"],
			"available" = budget_plan["available"],
			"operating_pool" = budget_plan["operating_pool"],
			"operating_requested" = budget_plan["operating_requested"],
			"operating_funded" = budget_plan["operating_funded"],
			"payroll_funded" = budget_plan["payroll_funded"],
			"unallocated_operating" = budget_plan["unallocated_operating"],
			"requested" = budget_plan["requested"],
			"funded" = budget_plan["funded"],
			"remaining" = budget_plan["remaining"],
			"shortfall" = budget_plan["shortfall"],
		) : null
		var/list/department_finances = list()
		for(var/department in GLOB.department_accounts)
			if(department == "Vendor" || !can_view_department(department))
				continue
			var/datum/money_account/budget = GLOB.department_accounts[department]
			var/projected_payroll = SSsupply.projected_department_payroll(department)
			var/list/department_plan = planned_departments[department]
			var/planned_allocation = department_plan?["requested"] || 0
			var/funded_allocation = department_plan?["funded"] || 0
			var/payroll_resources = budget.money + budget.savings + funded_allocation
			department_finances.Add(list(list(
				"department" = department,
				"balance" = budget.money,
				"savings" = budget.savings,
				"monthly_allocation" = planned_allocation,
				"automatic_allocation" = department_plan?["automatic"] || 0,
				"funded_allocation" = funded_allocation,
				"allocation_shortfall" = department_plan?["shortfall"] || 0,
				"allocation_overridden" = !!budget.allocation_configured,
				"allocation_percent" = department_plan?["allocation_percent"] || 0,
				"employee_count" = department_plan?["staff"] || 0,
				"operating_allocation" = department_plan?["operating_requested"] || 0,
				"operating_funded" = department_plan?["operating_funded"] || 0,
				"payroll_funded" = department_plan?["payroll_funded"] || 0,
				"monthly_income" = budget.monthly_income,
				"monthly_expenses" = budget.monthly_expenses,
				"last_month_income" = budget.last_month_income,
				"last_month_expenses" = budget.last_month_expenses,
				"projected_payroll" = projected_payroll,
				"payroll_resources" = payroll_resources,
				"payroll_coverage" = projected_payroll ? min(1, payroll_resources / projected_payroll) : 1,
				"last_payroll_due" = budget.last_payroll_due,
				"last_payroll_paid" = budget.last_payroll_paid,
				"last_payroll_shortfall" = max(0, budget.last_payroll_due - budget.last_payroll_paid),
				"revenue" = budget.total_revenue,
				"expenses" = budget.total_expenses,
				"wage_multiplier" = budget.wage_multiplier,
				"service_subsidy" = budget.service_subsidy,
				"service_invoices" = SSsupply.service_invoice_summary(department),
				"income_sources" = finance_income_source_rows(budget),
				"transactions" = finance_transaction_rows(budget)
			)))
		data["department_finances"] = department_finances
		data["station_transactions"] = can_allocate_station_budget() ? finance_transaction_rows(GLOB.station_account) : list()
		var/list/contract_departments = list()
		for(var/department in GLOB.department_accounts)
			if(department != "Vendor" && can_view_department(department))
				contract_departments += department
		data["contract_departments"] = contract_departments
		var/list/contract_faction_standings = list()
		for(var/faction_id in GLOB.reputation_factions)
			var/datum/reputation_faction/faction = GLOB.reputation_factions[faction_id]
			var/standing = get_station_faction_reputation(faction_id)
			var/list/department_tiers = list()
			for(var/department in contract_departments)
				var/department_standing = get_department_faction_reputation(department, faction_id)
				department_tiers[department] = reputation_rank(isnull(department_standing) ? standing : department_standing)
			contract_faction_standings.Add(list(list(
				"name" = faction.short_name,
				"acronym" = faction.acronym,
				"color" = faction.color,
				"tier" = reputation_rank(standing),
				"department_tiers" = department_tiers
			)))
		data["contract_faction_standings"] = contract_faction_standings
		var/list/contracts = list()
		for(var/id in SScontracts.contracts_by_id)
			var/datum/contract/contract = SScontracts.contracts_by_id[id]
			if(contract.scope == CONTRACT_SCOPE_PERSONAL)
				continue
			if(contract.scope == CONTRACT_SCOPE_STATION && !can_allocate_station_budget())
				continue
			if(contract.scope == CONTRACT_SCOPE_DEPARTMENT && !can_view_department(contract.department))
				continue
			var/list/row = SScontracts.contract_row(user, contract, contract.state == CONTRACT_OFFERED)
			contracts.Add(list(row))
		data["contracts"] = contracts
		switch(screen)
			if(GENERAL_RECORD_LIST)
				if(!isnull(GLOB.data_core.general))
					var/list/records = list()
					data["records"] = records
					for(var/datum/data/record/R in sortRecord(GLOB.data_core.general))
						records[++records.len] = list(
							"ref" = "\ref[R]",
							"id" = R.fields["id"],
							"name" = R.fields["name"],
							"b_dna" = R.fields["b_dna"])
			if(GENERAL_RECORD_DATA)
				var/list/general = list()
				data["general"] = general
				if(istype(active1(), /datum/data/record) && (active1() in GLOB.data_core.general))
					var/list/fields = list()
					general["fields"] = fields
					fields[++fields.len] = FIELD("Name", active1().fields["name"], "name")
					fields[++fields.len] = FIELD("ID", active1().fields["id"], "id")
					fields[++fields.len] = FIELD("Sex", active1().fields["sex"], "sex")
					fields[++fields.len] = FIELD("Species", active1().fields["species"], "species")
					fields[++fields.len] = FIELD("Age", active1().fields["age"], "age")
					fields[++fields.len] = FIELD("Fingerprint", active1().fields["fingerprint"], "fingerprint")
					fields[++fields.len] = FIELD("Home", active1().fields["home_system"], "home_system")
					fields[++fields.len] = FIELD("Birthplace", active1().fields["birthplace"], "birthplace")
					fields[++fields.len] = FIELD("Citizenship", active1().fields["citizenship"], "citizenship")
					fields[++fields.len] = FIELD("Employer", active1().fields["faction"], "faction")
					fields[++fields.len] = FIELD("Religion", active1().fields["religion"], "religion")
					fields[++fields.len] = FIELD("Known Languages", active1().fields["languages"], "languages")
					fields[++fields.len] = FIELD("Physical Status", active1().fields["p_stat"], null)
					fields[++fields.len] = FIELD("Mental Status", active1().fields["m_stat"], null)
					var/list/photos = list()
					general["photos"] = photos
					photos[++photos.len] = active1().fields["photo-south"]
					photos[++photos.len] = active1().fields["photo-west"]
					general["has_photos"] = (active1().fields["photo-south"] || active1().fields["photo-west"] ? 1 : 0)
					if(!active1().fields["comments"] || !islist(active1().fields["comments"]))
						active1().fields["comments"] = list()
					general["skills"] = active1().fields["notes"]
					general["comments"] = active1().fields["comments"]
					general["empty"] = 0
				else
					general["empty"] = 1

	data["modal"] = tgui_modal_data(src)
	return data

/obj/machinery/computer/skills/proc/accept_management_contract(datum/contract/contract, mob/living/user)
	if(!contract || contract.scope == CONTRACT_SCOPE_PERSONAL)
		return FALSE
	if(contract.scope == CONTRACT_SCOPE_STATION && !can_allocate_station_budget())
		return FALSE
	if(contract.scope == CONTRACT_SCOPE_DEPARTMENT && !can_view_department(contract.department))
		return FALSE
	return contract.accept(scan ? get_account(scan.associated_account_number) : null, user, src)

/obj/machinery/computer/skills/proc/decline_management_contract(datum/contract/contract, mob/living/user)
	if(!contract || contract.scope == CONTRACT_SCOPE_PERSONAL)
		return FALSE
	if(contract.scope == CONTRACT_SCOPE_STATION && !can_allocate_station_budget())
		return FALSE
	if(contract.scope == CONTRACT_SCOPE_DEPARTMENT && !can_view_department(contract.department))
		return FALSE
	return contract.decline(user)

/obj/machinery/computer/skills/proc/negotiate_management_contract(datum/contract/contract, clause_id, option_id, mob/living/user)
	if(!contract || contract.scope == CONTRACT_SCOPE_PERSONAL)
		return FALSE
	if(contract.scope == CONTRACT_SCOPE_STATION && !can_allocate_station_budget())
		return FALSE
	if(contract.scope == CONTRACT_SCOPE_DEPARTMENT && !can_view_department(contract.department))
		return FALSE
	return contract.select_negotiation_option(clause_id, option_id, user?.real_name || authenticated)

/obj/machinery/computer/skills/proc/can_manage_social_contract(datum/contract/social/contract)
	if(!istype(contract))
		return FALSE
	if(contract.scope == CONTRACT_SCOPE_STATION)
		return can_allocate_station_budget()
	return contract.scope == CONTRACT_SCOPE_DEPARTMENT && can_view_department(contract.department)

/obj/machinery/computer/skills/proc/finalize_social_contract(datum/contract/social/contract, mob/living/user)
	if(!can_manage_social_contract(contract))
		return FALSE
	return contract.finalize_graded_outcome(user?.real_name || authenticated)

/obj/machinery/computer/skills/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	add_fingerprint(ui.user)
	if(!(active1() in GLOB.data_core.general))
		rel_clear(src, nameof(active1))
	return TRUE

UI_ACT(/obj/machinery/computer/skills, "scan", ui_act_scan)
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_scan)
	. = TRUE
	if(scan)
		scan.forceMove(loc)
		if(ishuman(ui.user) && !ui.user.get_active_hand())
			ui.user.put_in_hands(scan)
		own_take(src, nameof(/obj/item/extrapolator::scan))
	else
		var/obj/item/I = ui.user.get_active_hand()
		if(istype(I, /obj/item/card/id))
			move_into(src, nameof(src.scan), I, ui.user)

UI_ACT(/obj/machinery/computer/skills, "cleartemp", ui_act_cleartemp)
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_cleartemp)
	. = TRUE
	temp = null

UI_ACT(/obj/machinery/computer/skills, "login", ui_act_login, UI_ARG_NUM("login_type"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_login)
	. = TRUE
	var/login_type = params["login_type"]
	if(login_type == LOGIN_TYPE_NORMAL && istype(scan))
		if(check_access(scan))
			authenticated = scan.registered_name
			rank = scan.assignment
	else if(login_type == LOGIN_TYPE_AI && isAI(ui.user))
		authenticated = ui.user.name
		rank = JOB_AI
	else if(login_type == LOGIN_TYPE_ROBOT && isrobot(ui.user))
		authenticated = ui.user.name
		var/mob/living/silicon/robot/R = ui.user
		rank = "[R.modtype] [R.braintype]"
	if(authenticated)
		rel_clear(src, nameof(/obj/machinery/computer/med_data::active1))
		screen = GENERAL_RECORD_LIST

UI_ACT(/obj/machinery/computer/skills, "logout", ui_act_logout)
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_logout)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(scan)
		scan.forceMove(loc)
		if(ishuman(ui.user) && !ui.user.get_active_hand())
			ui.user.put_in_hands(scan)
		own_take(src, nameof(/obj/item/extrapolator::scan))
	authenticated = null
	screen = null
	rel_clear(src, nameof(/obj/machinery/computer/med_data::active1))

UI_ACT(/obj/machinery/computer/skills, "screen", ui_act_screen, UI_ARG_NUM("screen"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_screen)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/requested_screen = params["screen"]
	if(requested_screen in list(GENERAL_RECORD_FINANCES, GENERAL_RECORD_CONTRACTS))
		screen = requested_screen
	else
		screen = clamp(requested_screen || 0, GENERAL_RECORD_LIST, GENERAL_RECORD_MAINT)
	rel_clear(src, nameof(/obj/machinery/computer/med_data::active1))

UI_ACT(/obj/machinery/computer/skills, "contract_accept", ui_act_contract_accept, UI_ARG_TEXT("id"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_contract_accept)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/contract = SScontracts.contracts_by_id[params["id"]]
	return accept_management_contract(contract, ui.user)

UI_ACT(/obj/machinery/computer/skills, "contract_decline", ui_act_contract_decline, UI_ARG_TEXT("id"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_contract_decline)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/contract = SScontracts.contracts_by_id[params["id"]]
	return decline_management_contract(contract, ui.user)

UI_ACT(/obj/machinery/computer/skills, "contract_negotiate", ui_act_contract_negotiate, UI_ARG_TEXT("clause"), UI_ARG_TEXT("id"), UI_ARG_TEXT("option"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_contract_negotiate)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/contract = SScontracts.contracts_by_id[params["id"]]
	return negotiate_management_contract(contract, params["clause"], params["option"], ui.user)

UI_ACT(/obj/machinery/computer/skills, "contract_finalize_outcome", ui_act_contract_finalize_outcome, UI_ARG_TEXT("id"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_contract_finalize_outcome)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/social/contract = SScontracts.contracts_by_id[params["id"]]
	return finalize_social_contract(contract, ui.user)

UI_ACT(/obj/machinery/computer/skills, "contract_print_trial_packet", ui_act_contract_print_trial_packet, UI_ARG_TEXT("id"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_contract_print_trial_packet)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/medical_trial/trial = SScontracts.contracts_by_id[params["id"]]
	if(!istype(trial) || !can_view_department(trial.department))
		return FALSE
	var/datum/money_account/account = scan ? get_account(scan.associated_account_number) : null
	return trial.print_clinical_packet(get_turf(src), account?.account_number)

UI_ACT(/obj/machinery/computer/skills, "contract_print_trial_report", ui_act_contract_print_trial_report, UI_ARG_TEXT("adverse"), UI_ARG_TEXT("id"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_contract_print_trial_report)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/medical_trial/trial = SScontracts.contracts_by_id[params["id"]]
	if(!istype(trial) || !can_view_department(trial.department))
		return FALSE
	return trial.print_final_report(get_turf(src), params["adverse"])

UI_ACT(/obj/machinery/computer/skills, "contract_resupply_trial", ui_act_contract_resupply_trial, UI_ARG_TEXT("id"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_contract_resupply_trial)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/medical_trial/trial = SScontracts.contracts_by_id[params["id"]]
	if(!istype(trial) || !can_view_department(trial.department))
		return FALSE
	return trial.request_resupply(get_turf(src))

UI_ACT(/obj/machinery/computer/skills, "contract_reissue_trial_packet", ui_act_contract_reissue_trial_packet, UI_ARG_TEXT("id"), UI_ARG_TEXT("subject_id"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_contract_reissue_trial_packet)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/medical_trial/trial = SScontracts.contracts_by_id[params["id"]]
	if(!istype(trial) || !can_view_department(trial.department))
		return FALSE
	var/datum/money_account/account = scan ? get_account(scan.associated_account_number) : null
	return trial.reissue_clinical_packet(get_turf(src), params["subject_id"], account?.account_number)

UI_ACT(/obj/machinery/computer/skills, "contract_print_trial_revocation", ui_act_contract_print_trial_revocation, UI_ARG_TEXT("id"), UI_ARG_TEXT("subject_id"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_contract_print_trial_revocation)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/medical_trial/trial = SScontracts.contracts_by_id[params["id"]]
	if(!istype(trial) || !can_view_department(trial.department))
		return FALSE
	var/datum/money_account/account = scan ? get_account(scan.associated_account_number) : null
	return trial.print_consent_revocation(get_turf(src), params["subject_id"], account?.account_number)

UI_ACT(/obj/machinery/computer/skills, "contract_print_case_forms", ui_act_contract_print_case_forms, UI_ARG_TEXT("id"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_contract_print_case_forms)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/medical_case_report/report = SScontracts.contracts_by_id[params["id"]]
	if(!istype(report) || !can_view_department(report.department))
		return FALSE
	var/datum/money_account/account = scan ? get_account(scan.associated_account_number) : null
	return report.print_case_forms(get_turf(src), account?.account_number)

UI_ACT(/obj/machinery/computer/skills, "contract_print_case_revocation", ui_act_contract_print_case_revocation, UI_ARG_TEXT("id"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_contract_print_case_revocation)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/medical_case_report/report = SScontracts.contracts_by_id[params["id"]]
	if(!istype(report) || !can_view_department(report.department))
		return FALSE
	var/datum/money_account/account = scan ? get_account(scan.associated_account_number) : null
	return report.print_consent_revocation(get_turf(src), account?.account_number)

UI_ACT(/obj/machinery/computer/skills, "set_department_wages", ui_act_set_department_wages, UI_ARG_TEXT("department"), UI_ARG_NUM("multiplier"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_set_department_wages)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/department = params["department"]
	var/new_multiplier = params["multiplier"]
	return set_department_wage(department, new_multiplier)

UI_ACT(/obj/machinery/computer/skills, "set_department_allocation_percent", ui_act_set_department_allocation_percent, UI_ARG_TEXT("department"), UI_ARG_NUM("percent"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_set_department_allocation_percent)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/department = params["department"]
	var/percent = params["percent"]
	return set_department_allocation_percent(department, percent, ui.user)

UI_ACT(/obj/machinery/computer/skills, "transfer_department_funds", ui_act_transfer_department_funds, UI_ARG_NUM("amount"), UI_ARG_TEXT("department"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_transfer_department_funds)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	return transfer_department_funds(params["department"], params["amount"], ui.user)

UI_ACT(/obj/machinery/computer/skills, "clear_department_allocation", ui_act_clear_department_allocation, UI_ARG_TEXT("department"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_clear_department_allocation)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	return clear_department_allocation(params["department"], ui.user)

UI_ACT(/obj/machinery/computer/skills, "set_allocation_policy", ui_act_set_allocation_policy, UI_ARG_TEXT("policy"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_set_allocation_policy)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(!can_allocate_station_budget())
		return FALSE
	return SSsupply.set_allocation_policy(params["policy"], TRUE)

UI_ACT(/obj/machinery/computer/skills, "set_service_subsidy", ui_act_set_service_subsidy, UI_ARG_NUM("subsidy"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_set_service_subsidy)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(!can_view_department(DEPARTMENT_CIVILIAN))
		return FALSE
	var/subsidy = params["subsidy"]
	if(!isnum(subsidy) || subsidy < 0 || subsidy > 1)
		return FALSE
	GLOB.department_accounts[DEPARTMENT_CIVILIAN].service_subsidy = subsidy
	return TRUE

UI_ACT(/obj/machinery/computer/skills, "refresh", ui_act_refresh)
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_refresh)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	return TRUE

UI_ACT(/obj/machinery/computer/skills, "del_all", ui_act_del_all)
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_del_all)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(GLOB.PDA_Manifest)
		GLOB.PDA_Manifest.Cut()
	for(var/datum/data/record/R in GLOB.data_core.general)
		qdel(R)
	set_temp("All employment records deleted.")

UI_ACT(/obj/machinery/computer/skills, "sync_r", ui_act_sync_r)
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_sync_r)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(active1())
		set_temp(client_update_record(src,ui.user))

UI_ACT(/obj/machinery/computer/skills, "edit_notes", ui_act_edit_notes)
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_edit_notes)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
		// The modal input in tgui is busted for this sadly...
	om_ask(ui.user, /datum/om/prompt/text/record_notes, PROC_REF(record_notes_entered), default = html_decode(active1().fields["notes"]), record = active1())

UI_ACT(/obj/machinery/computer/skills, "del_r", ui_act_del_r)
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_del_r)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(GLOB.PDA_Manifest)
		GLOB.PDA_Manifest.Cut()
	if(active1())
		for(var/datum/data/record/R in GLOB.data_core.medical)
			if ((R.fields["name"] == active1().fields["name"] || R.fields["id"] == active1().fields["id"]))
				qdel(R)
		set_temp("Employment record deleted.")
		var/datum/data/record/deleted_record = active1()
		rel_clear(src, nameof(/obj/machinery/computer/med_data::active1))
		QDEL_NULL(deleted_record)

UI_ACT(/obj/machinery/computer/skills, "d_rec", ui_act_d_rec, UI_ARG_REF("d_rec", null, /datum/data/record))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_d_rec)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/data/record/general_record = params["d_rec"]
	if(!(general_record in GLOB.data_core.general))
		set_temp("Record not found.", "danger")
		return

	rel_set(src, nameof(/obj/machinery/computer/med_data::active1), general_record)
	screen = GENERAL_RECORD_DATA

UI_ACT(/obj/machinery/computer/skills, "new", ui_act_new)
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_new)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(GLOB.PDA_Manifest)
		GLOB.PDA_Manifest.Cut()
	rel_set(src, nameof(/obj/machinery/computer/med_data::active1), GLOB.data_core.CreateGeneralRecord())
	screen = GENERAL_RECORD_DATA
	set_temp("Employment record created.", "success")

UI_ACT(/obj/machinery/computer/skills, "del_c", ui_act_del_c, UI_ARG_NUM("del_c"))
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_del_c)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/index = params["del_c"]
	if(!index || !istype(active1(), /datum/data/record))
		return

	var/list/comments = active1().fields["comments"]
	index = clamp(index, 1, length(comments))
	if(comments[index])
		comments.Cut(index, index + 1)

UI_ACT(/obj/machinery/computer/skills, "print_p", ui_act_print_p)
UI_ACT_PROC(/obj/machinery/computer/skills, ui_act_print_p)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(!printing)
		printing = TRUE
		SStgui.update_uis(src)
		after(src, 5 SECONDS, PROC_REF(print_finish))

/obj/machinery/computer/skills/proc/record_notes_entered(datum/om/prompt/text/record_notes/ask)
	var/new_notes = strip_html_simple(ask.text, MAX_RECORD_LENGTH)
	if(new_notes != "")
		set_record_notes(ask.record, new_notes)
		return
	om_ask(ask.answerer, /datum/om/prompt/confirm/record_notes_delete, PROC_REF(record_notes_confirmed), record = ask.record)

/obj/machinery/computer/skills/proc/record_notes_confirmed(datum/om/prompt/confirm/record_notes_delete/ask)
	set_record_notes(ask.record, "")

/obj/machinery/computer/skills/proc/set_record_notes(datum/data/record/R, notes)
	if(R == active1())
		active1().fields["notes"] = notes
		SStgui.update_uis(src)


/obj/machinery/computer/skills/ui_modal_opened(mob/user, id, list/arguments, datum/tgui/ui, datum/tgui_state/state)
	. = TRUE
	switch(id)
		if("edit")
			var/field = arguments["field"]
			if(!length(field) || !field_edit_questions[field])
				return
			var/question = field_edit_questions[field]
			var/choices = field_edit_choices[field]
			if(length(choices))
				tgui_modal_choice(src, id, question, arguments = arguments, value = arguments["value"], choices = choices)
			else
				tgui_modal_input(src, id, question, arguments = arguments, value = arguments["value"])
		if("add_c")
			tgui_modal_input(src, id, "Please enter your message:")
		else
			return FALSE

/obj/machinery/computer/skills/ui_modal_answered(mob/user, id, answer, list/arguments, datum/tgui/ui, datum/tgui_state/state)
	. = TRUE
	switch(id)
		if("edit")
			var/field = arguments["field"]
			if(!length(field) || !field_edit_questions[field])
				return
			var/list/choices = field_edit_choices[field]
			if(length(choices) && !(answer in choices))
				return

			if(field == "age")
				answer = text2num(answer)

			if(istype(active1(), /datum/data/record) && (field in active1().fields))
				active1().fields[field] = answer
			. = TRUE
		if("add_c")
			if(!length(answer) || !istype(active1(), /datum/data/record) || !length(authenticated))
				return
			active1().fields["comments"] += list(list(
				header = "Made by [authenticated] ([rank]) at [worldtime2stationtime(world.time)]",
				text = answer
			))
		else
			return FALSE
/**
 * Called when the print timer finishes
 */
/obj/machinery/computer/skills/proc/print_finish()
	var/obj/item/paper/P = new(loc)
	P.info = "<center>" + span_bold("Medical Record") + "</center><br>"
	if(istype(active1(), /datum/data/record) && (active1() in GLOB.data_core.general))
		P.info += {"Name: [active1().fields["name"]] ID: [active1().fields["id"]]
		<br>\nSex: [active1().fields["sex"]]
		<br>\nSpecies: [active1().fields["species"]]
		<br>\nAge: [active1().fields["age"]]
		<br>\nFingerprint: [active1().fields["fingerprint"]]
		<br>\nHome: [active1().fields["home_system"]]
		<br>\nBirthplace: [active1().fields["birthplace"]]
		<br>\nCitizenship: [active1().fields["citizenship"]]
		<br>\nEmployer: [active1().fields["faction"]]
		<br>\nReligion: [active1().fields["religion"]]
		<br>\nKnown Languages: [active1().fields["languages"]]
		<br>\nPhysical Status: [active1().fields["p_stat"]]
		<br>\nMental Status: [active1().fields["m_stat"]]<br>
		<br>\nEmployment/Skills Summary: [active1().fields["notes"]]
		<br>\n
		<center><b>Comments/Log</b></center><br>"}
		for(var/c in active1().fields["comments"])
			P.info += "[c["header"]]<br>[c["text"]]<br>"
	else
		P.info += span_bold("General Record Lost!") + "<br>"
	P.info += "</tt>"
	P.name = "paper - 'Employment Record: [active1().fields["name"]]'"
	printing = FALSE
	SStgui.update_uis(src)

/**
 * Sets a temporary message to display to the user
 *
 * Arguments:
 * * text - Text to display, null/empty to clear the message from the UI
 * * style - The style of the message: (color name), info, success, warning, danger, virus
 */
/obj/machinery/computer/skills/proc/set_temp(text = "", style = "info", update_now = FALSE)
	temp = list(text = text, style = style)
	if(update_now)
		SStgui.update_uis(src)

DAMAGE_REACTION(/obj/machinery/computer/skills, DAMAGE_EMP, PROC_REF(skills_emp))
/// An EMP scrambles or wipes some of the records.
/obj/machinery/computer/skills/proc/skills_emp(datum/damage_packet/packet)
	if(!operable())
		return

	for(var/datum/data/record/R in GLOB.data_core.security)
		if(prob(10/packet.severity))
			switch(rand(1,6))
				if(1)
					R.fields["name"] = "[pick(pick(GLOB.first_names_male), pick(GLOB.first_names_female))] [pick(GLOB.last_names)]"
				if(2)
					R.fields["sex"]	= pick("Male", "Female")
				if(3)
					R.fields["age"] = rand(5, 85)
				if(4)
					R.fields["criminal"] = pick("None", "*Arrest*", "Incarcerated", "Parolled", "Released")
				if(5)
					R.fields["p_stat"] = pick("*Unconcious*", "Active", "Physically Unfit")
					if(GLOB.PDA_Manifest.len)
						GLOB.PDA_Manifest.Cut()
				if(6)
					R.fields["m_stat"] = pick("*Insane*", "*Unstable*", "*Watch*", "Stable")
			continue

		else if(prob(1))
			qdel(R)
			continue

#undef GENERAL_RECORD_LIST
#undef GENERAL_RECORD_MAINT
#undef GENERAL_RECORD_DATA

#undef FIELD

/obj/machinery/computer/skills/ownership()
	. = ..()
	. += owns(nameof(scan), policy = OWN_CONTAINED)

/// The selected record (a relation view).
/obj/machinery/computer/skills/proc/active1() as /datum/data/record
	return active1
