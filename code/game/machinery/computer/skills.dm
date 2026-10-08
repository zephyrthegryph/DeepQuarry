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

/obj/machinery/computer/skills/proc/interaction_insert_id(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(scan)
		return OP_DECLINE
	if(!move_into(src, nameof(src.scan), O, user))
		return OP_DECLINE
	to_chat(user, "You insert [O].")
	tgui_interact(user)
	return TRUE

//Someone needs to break down the dat += into chunks instead of long ass lines.
/// Requirement clause: no message (like the old check) beyond the reason text.
/obj/machinery/computer/skills/proc/within_contact_range(mob/actor, atom/target, obj/item/held)
	var/obj/machinery/computer/skills/machine = target
	return !using_map || (machine.z in using_map.contact_levels) // ALLOW(reads): the legacy check is read when the op is tried, never from a cached menu

/// Requirement (was REQ_* within_contact_range): the legacy check answers TRUE to pass.
/obj/machinery/computer/skills/proc/within_contact_range_holds(datum/act/op/A)
	var/answer = within_contact_range(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why within_contact_range_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/computer/skills/proc/within_contact_range_refusal(datum/act/op/A)
	var/answer = within_contact_range(A.actor, src, A.held)
	return istext(answer) ? answer : "you're too far away from the station!"

/obj/machinery/computer/skills/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	tgui_interact(user)
	return TRUE

CAPABILITIES(/obj/machinery/computer/skills)
	ref_one(nameof(active1), /datum/data/record)
	interface("GeneralRecords", title = "Department Management")
	extend("ui_open", priority(OP_PRIORITY_DEFAULT - 2), needs(req(PROC_REF(within_contact_range_holds), because = PROC_REF(within_contact_range_refusal))))
	op("scan", ui_act("scan"), then(PROC_REF(ui_act_scan)))
	op("cleartemp", ui_act("cleartemp"), then(PROC_REF(ui_act_cleartemp)))
	op("login", ui_act("login", arg("login_type", num())), then(PROC_REF(ui_act_login)))
	op("logout", ui_act("logout"), then(PROC_REF(ui_act_logout)))
	op("screen", ui_act("screen", arg("screen", num())), then(PROC_REF(ui_act_screen)))
	op("contract_accept", ui_act("contract_accept", arg("id", schema_text(4096))), then(PROC_REF(ui_act_contract_accept)))
	op("contract_decline", ui_act("contract_decline", arg("id", schema_text(4096))), then(PROC_REF(ui_act_contract_decline)))
	op("contract_negotiate", ui_act("contract_negotiate", arg("clause", schema_text(4096)), arg("id", schema_text(4096)), arg("option", schema_text(4096))), then(PROC_REF(ui_act_contract_negotiate)))
	op("contract_finalize_outcome", ui_act("contract_finalize_outcome", arg("id", schema_text(4096))), then(PROC_REF(ui_act_contract_finalize_outcome)))
	op("contract_print_trial_packet", ui_act("contract_print_trial_packet", arg("id", schema_text(4096))), then(PROC_REF(ui_act_contract_print_trial_packet)))
	op("contract_print_trial_report", ui_act("contract_print_trial_report", arg("adverse", schema_text(4096)), arg("id", schema_text(4096))), then(PROC_REF(ui_act_contract_print_trial_report)))
	op("contract_resupply_trial", ui_act("contract_resupply_trial", arg("id", schema_text(4096))), then(PROC_REF(ui_act_contract_resupply_trial)))
	op("contract_reissue_trial_packet", ui_act("contract_reissue_trial_packet", arg("id", schema_text(4096)), arg("subject_id", schema_text(4096))), then(PROC_REF(ui_act_contract_reissue_trial_packet)))
	op("contract_print_trial_revocation", ui_act("contract_print_trial_revocation", arg("id", schema_text(4096)), arg("subject_id", schema_text(4096))), then(PROC_REF(ui_act_contract_print_trial_revocation)))
	op("contract_print_case_forms", ui_act("contract_print_case_forms", arg("id", schema_text(4096))), then(PROC_REF(ui_act_contract_print_case_forms)))
	op("contract_print_case_revocation", ui_act("contract_print_case_revocation", arg("id", schema_text(4096))), then(PROC_REF(ui_act_contract_print_case_revocation)))
	op("set_department_wages", ui_act("set_department_wages", arg("department", schema_text(4096)), arg("multiplier", num())), then(PROC_REF(ui_act_set_department_wages)))
	op("set_department_allocation_percent", ui_act("set_department_allocation_percent", arg("department", schema_text(4096)), arg("percent", num())), then(PROC_REF(ui_act_set_department_allocation_percent)))
	op("transfer_department_funds", ui_act("transfer_department_funds", arg("amount", num()), arg("department", schema_text(4096))), then(PROC_REF(ui_act_transfer_department_funds)))
	op("clear_department_allocation", ui_act("clear_department_allocation", arg("department", schema_text(4096))), then(PROC_REF(ui_act_clear_department_allocation)))
	op("set_allocation_policy", ui_act("set_allocation_policy", arg("policy", schema_text(4096))), then(PROC_REF(ui_act_set_allocation_policy)))
	op("set_service_subsidy", ui_act("set_service_subsidy", arg("subsidy", num())), then(PROC_REF(ui_act_set_service_subsidy)))
	op("refresh", ui_act("refresh"), then(PROC_REF(ui_act_refresh)))
	op("del_all", ui_act("del_all"), then(PROC_REF(ui_act_del_all)))
	op("sync_r", ui_act("sync_r"), then(PROC_REF(ui_act_sync_r)))
	op("edit_notes", ui_act("edit_notes"), needs(req_adjacent(), req(PROC_REF(records_authenticated), because = MSG(records/not_authenticated))), asks(/datum/prompt/text, fields = list("title" = "Character Preference", "question" = "Enter new information here.", "max_len" = MAX_RECORD_LENGTH, "multiline" = TRUE, "default" = computed(PROC_REF(notes_default))), step = "notes"), asks(/datum/prompt/yes_no/record_notes_delete, fields = list("record" = computed(PROC_REF(notes_record)), "timeout" = 0), step = "delete_notes", when = PROC_REF(notes_empty)), then(PROC_REF(ui_act_edit_notes)))
	op("del_r", ui_act("del_r"), then(PROC_REF(ui_act_del_r)))
	op("d_rec", ui_act("d_rec", arg("d_rec")), then(PROC_REF(ui_act_d_rec)))
	op("new", ui_act("new"), then(PROC_REF(ui_act_new)))
	op("del_c", ui_act("del_c", arg("del_c", num())), then(PROC_REF(ui_act_del_c)))
	op("print_p", ui_act("print_p"), then(PROC_REF(ui_act_print_p)))
	extend(TAG_UI, then(PROC_REF(ui_records_fresh), early = TRUE))
	// The record modals (the old ui_modal_opened()/ui_modal_answered()): a field is edited by a pick or by typing, as the field's kind says.
	op("edit", ui_act("modal:edit", arg("arguments")), needs(req(PROC_REF(edit_field_known), silent = TRUE)),
		asks(/datum/prompt/choice/skills_record_edit, fields = list("arguments" = arg_of("arguments"), "inline" = TRUE, "timeout" = 0), step = "edit_choice", when = PROC_REF(edit_by_choice)),
		asks(/datum/prompt/text/skills_record_edit, fields = list("arguments" = arg_of("arguments"), "inline" = TRUE, "timeout" = 0), step = "edit_text", when = PROC_REF(edit_by_text)),
		then(PROC_REF(modal_edit)))
	op("add_c", ui_act("modal:add_c", arg("arguments")), asks(/datum/prompt/text, fields = list("question" = "Please enter your message:", "inline" = TRUE, "timeout" = 0), step = "comment"), then(PROC_REF(modal_add_comment)))
	op("insert_id", item(/obj/item/card/id), priority(OP_PRIORITY_DEFAULT), label("Insert ID"), then(PROC_REF(interaction_insert_id)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(skills_emp)))

/obj/machinery/computer/skills/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	data["temp"] = temp
	data["authenticated"] = authenticated
	data["rank"] = rank
	data["screen"] = screen
	data["printing"] = printing
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

/// Every button first drops a record the data core no longer holds (the old window guard's side effects).
/obj/machinery/computer/skills/proc/ui_records_fresh(datum/act/op/A)
	add_fingerprint(A.actor)
	if(!(active1() in GLOB.data_core.general))
		rel_clear(src, nameof(active1))
	return OP_OK

/obj/machinery/computer/skills/proc/ui_act_scan(datum/act/op/A)
	. = TRUE
	if(scan)
		scan.forceMove(loc)
		if(ishuman(A.actor) && !A.actor.get_active_hand())
			A.actor.put_in_hands(scan)
		rel_take(src, nameof(src.scan))
	else
		var/obj/item/I = A.actor.get_active_hand()
		if(istype(I, /obj/item/card/id))
			move_into(src, nameof(src.scan), I, A.actor)

/obj/machinery/computer/skills/proc/ui_act_cleartemp(datum/act/op/A)
	. = TRUE
	temp = null

/obj/machinery/computer/skills/proc/ui_act_login(datum/act/op/A, login_type_arg)
	. = TRUE
	var/login_type = login_type_arg
	if(login_type == LOGIN_TYPE_NORMAL && istype(scan))
		if(check_access(scan))
			authenticated = scan.registered_name
			rank = scan.assignment
	else if(login_type == LOGIN_TYPE_AI && isAI(A.actor))
		authenticated = A.actor.name
		rank = JOB_AI
	else if(login_type == LOGIN_TYPE_ROBOT && isrobot(A.actor))
		authenticated = A.actor.name
		var/mob/living/silicon/robot/R = A.actor
		rank = "[R.modtype] [R.braintype]"
	if(authenticated)
		rel_clear(src, nameof(src.active1))
		screen = GENERAL_RECORD_LIST

/obj/machinery/computer/skills/proc/ui_act_logout(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(scan)
		scan.forceMove(loc)
		if(ishuman(A.actor) && !A.actor.get_active_hand())
			A.actor.put_in_hands(scan)
		rel_take(src, nameof(src.scan))
	authenticated = null
	screen = null
	rel_clear(src, nameof(src.active1))

/obj/machinery/computer/skills/proc/ui_act_screen(datum/act/op/A, screen_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/requested_screen = screen_arg
	if(requested_screen in list(GENERAL_RECORD_FINANCES, GENERAL_RECORD_CONTRACTS))
		screen = requested_screen
	else
		screen = clamp(requested_screen || 0, GENERAL_RECORD_LIST, GENERAL_RECORD_MAINT)
	rel_clear(src, nameof(src.active1))

/obj/machinery/computer/skills/proc/ui_act_contract_accept(datum/act/op/A, id_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/contract = SScontracts.contracts_by_id[id_arg]
	return accept_management_contract(contract, A.actor)

/obj/machinery/computer/skills/proc/ui_act_contract_decline(datum/act/op/A, id_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/contract = SScontracts.contracts_by_id[id_arg]
	return decline_management_contract(contract, A.actor)

/obj/machinery/computer/skills/proc/ui_act_contract_negotiate(datum/act/op/A, clause, id_arg, option)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/contract = SScontracts.contracts_by_id[id_arg]
	return negotiate_management_contract(contract, clause, option, A.actor)

/obj/machinery/computer/skills/proc/ui_act_contract_finalize_outcome(datum/act/op/A, id_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/social/contract = SScontracts.contracts_by_id[id_arg]
	return finalize_social_contract(contract, A.actor)

/obj/machinery/computer/skills/proc/ui_act_contract_print_trial_packet(datum/act/op/A, id_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/medical_trial/trial = SScontracts.contracts_by_id[id_arg]
	if(!istype(trial) || !can_view_department(trial.department))
		return FALSE
	var/datum/money_account/account = scan ? get_account(scan.associated_account_number) : null
	return trial.print_clinical_packet(get_turf(src), account?.account_number)

/obj/machinery/computer/skills/proc/ui_act_contract_print_trial_report(datum/act/op/A, adverse, id_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/medical_trial/trial = SScontracts.contracts_by_id[id_arg]
	if(!istype(trial) || !can_view_department(trial.department))
		return FALSE
	return trial.print_final_report(get_turf(src), adverse)

/obj/machinery/computer/skills/proc/ui_act_contract_resupply_trial(datum/act/op/A, id_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/medical_trial/trial = SScontracts.contracts_by_id[id_arg]
	if(!istype(trial) || !can_view_department(trial.department))
		return FALSE
	return trial.request_resupply(get_turf(src))

/obj/machinery/computer/skills/proc/ui_act_contract_reissue_trial_packet(datum/act/op/A, id_arg, subject_id)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/medical_trial/trial = SScontracts.contracts_by_id[id_arg]
	if(!istype(trial) || !can_view_department(trial.department))
		return FALSE
	var/datum/money_account/account = scan ? get_account(scan.associated_account_number) : null
	return trial.reissue_clinical_packet(get_turf(src), subject_id, account?.account_number)

/obj/machinery/computer/skills/proc/ui_act_contract_print_trial_revocation(datum/act/op/A, id_arg, subject_id)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/medical_trial/trial = SScontracts.contracts_by_id[id_arg]
	if(!istype(trial) || !can_view_department(trial.department))
		return FALSE
	var/datum/money_account/account = scan ? get_account(scan.associated_account_number) : null
	return trial.print_consent_revocation(get_turf(src), subject_id, account?.account_number)

/obj/machinery/computer/skills/proc/ui_act_contract_print_case_forms(datum/act/op/A, id_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/medical_case_report/report = SScontracts.contracts_by_id[id_arg]
	if(!istype(report) || !can_view_department(report.department))
		return FALSE
	var/datum/money_account/account = scan ? get_account(scan.associated_account_number) : null
	return report.print_case_forms(get_turf(src), account?.account_number)

/obj/machinery/computer/skills/proc/ui_act_contract_print_case_revocation(datum/act/op/A, id_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/contract/medical_case_report/report = SScontracts.contracts_by_id[id_arg]
	if(!istype(report) || !can_view_department(report.department))
		return FALSE
	var/datum/money_account/account = scan ? get_account(scan.associated_account_number) : null
	return report.print_consent_revocation(get_turf(src), account?.account_number)

/obj/machinery/computer/skills/proc/ui_act_set_department_wages(datum/act/op/A, department_arg, multiplier)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/department = department_arg
	var/new_multiplier = multiplier
	return set_department_wage(department, new_multiplier)

/obj/machinery/computer/skills/proc/ui_act_set_department_allocation_percent(datum/act/op/A, department_arg, percent_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/department = department_arg
	var/percent = percent_arg
	return set_department_allocation_percent(department, percent, A.actor)

/obj/machinery/computer/skills/proc/ui_act_transfer_department_funds(datum/act/op/A, amount, department_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	return transfer_department_funds(department_arg, amount, A.actor)

/obj/machinery/computer/skills/proc/ui_act_clear_department_allocation(datum/act/op/A, department_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	return clear_department_allocation(department_arg, A.actor)

/obj/machinery/computer/skills/proc/ui_act_set_allocation_policy(datum/act/op/A, policy)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(!can_allocate_station_budget())
		return FALSE
	return SSsupply.set_allocation_policy(policy, TRUE)

/obj/machinery/computer/skills/proc/ui_act_set_service_subsidy(datum/act/op/A, subsidy_arg)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(!can_view_department(DEPARTMENT_CIVILIAN))
		return FALSE
	var/subsidy = subsidy_arg
	if(!isnum(subsidy) || subsidy < 0 || subsidy > 1)
		return FALSE
	GLOB.department_accounts[DEPARTMENT_CIVILIAN].service_subsidy = subsidy
	return TRUE

/obj/machinery/computer/skills/proc/ui_act_refresh(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	return TRUE

/obj/machinery/computer/skills/proc/ui_act_del_all(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(GLOB.PDA_Manifest)
		GLOB.PDA_Manifest.Cut()
	for(var/datum/data/record/R in GLOB.data_core.general)
		spent(R)
	set_temp("All employment records deleted.")

/obj/machinery/computer/skills/proc/ui_act_sync_r(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(active1())
		set_temp(client_update_record(src,A.actor))

/obj/machinery/computer/skills/proc/ui_act_edit_notes(datum/act/op/A)
	if(!active1())
		return OP_OK
	var/new_notes = strip_html_simple(A.step_value("notes"), MAX_RECORD_LENGTH)
	if(new_notes != "")
		set_record_notes(active1(), new_notes)
	else if(A.step_value("delete_notes"))
		var/datum/prompt/yes_no/record_notes_delete/R = A.answer
		set_record_notes(R.record, "")
	return OP_OK

/obj/machinery/computer/skills/proc/notes_empty(datum/act/op/A)
	return !!active1() && strip_html_simple(A.step_value("notes"), MAX_RECORD_LENGTH) == ""

/obj/machinery/computer/skills/proc/notes_record(datum/act/op/A)
	return active1()

/obj/machinery/computer/skills/proc/notes_default(datum/act/A)
	return html_decode(active1()?.fields["notes"])

/// The operator is logged in (the old handlers each refused without it).
/obj/machinery/computer/skills/proc/records_authenticated(datum/act/op/A)
	return !!authenticated // ALLOW(reads): who is logged in is asked when the button is pressed and again when the answer arrives, never cached

/obj/machinery/computer/skills/proc/ui_act_del_r(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(GLOB.PDA_Manifest)
		GLOB.PDA_Manifest.Cut()
	if(active1())
		for(var/datum/data/record/R in GLOB.data_core.medical)
			if ((R.fields["name"] == active1().fields["name"] || R.fields["id"] == active1().fields["id"]))
				spent(R)
		set_temp("Employment record deleted.")
		var/datum/data/record/deleted_record = active1()
		rel_clear(src, nameof(src.active1))
		QDEL_NULL(deleted_record)

/obj/machinery/computer/skills/proc/ui_act_d_rec(datum/act/op/A, d_rec)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/datum/data/record/general_record = ui_ref(d_rec, null, /datum/data/record)
	if(!(general_record in GLOB.data_core.general))
		set_temp("Record not found.", "danger")
		return

	rel_set(src, nameof(src.active1), general_record)
	screen = GENERAL_RECORD_DATA

/obj/machinery/computer/skills/proc/ui_act_new(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(GLOB.PDA_Manifest)
		GLOB.PDA_Manifest.Cut()
	rel_set(src, nameof(src.active1), GLOB.data_core.CreateGeneralRecord())
	screen = GENERAL_RECORD_DATA
	set_temp("Employment record created.", "success")

/obj/machinery/computer/skills/proc/ui_act_del_c(datum/act/op/A, del_c)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	var/index = del_c
	if(!index || !istype(active1(), /datum/data/record))
		return

	var/list/comments = active1().fields["comments"]
	index = clamp(index, 1, length(comments))
	if(comments[index])
		comments.Cut(index, index + 1)

/obj/machinery/computer/skills/proc/ui_act_print_p(datum/act/op/A)
	. = TRUE
	if(!(authenticated))
		return FALSE
	. = TRUE
	if(!printing)
		printing = TRUE
		SStgui.update_uis(src)
		after(src, 5 SECONDS, PROC_REF(print_finish))

/obj/machinery/computer/skills/proc/set_record_notes(datum/data/record/R, notes)
	if(R == active1())
		active1().fields["notes"] = notes
		SStgui.update_uis(src)

/// The record field the edit modal names (`arguments["field"]`), when this console can edit it.
/obj/machinery/computer/skills/proc/edit_field(list/arguments)
	var/field = islist(arguments) ? arguments["field"] : null
	return (length(field) && field_edit_questions[field]) ? field : null

/// Requirement: the edit modal names a field this console edits (silently refused otherwise, as the old modal never opened).
/obj/machinery/computer/skills/proc/edit_field_known(datum/act/op/A)
	return !isnull(edit_field(A.args["arguments"]))

/// The field is edited by picking from its choices.
/obj/machinery/computer/skills/proc/edit_by_choice(datum/act/op/A)
	return length(field_edit_choices[edit_field(A.args["arguments"])]) > 0

/// The field is edited by typing.
/obj/machinery/computer/skills/proc/edit_by_text(datum/act/op/A)
	return !edit_by_choice(A)

/// Argument-derived fields are prepared on the typed request, after arg_of() supplies the checked modal arguments.
/datum/prompt/choice/skills_record_edit
	var/list/arguments

/datum/prompt/choice/skills_record_edit/prepare(datum/act/A)
	..()
	var/obj/machinery/computer/skills/console = owner
	var/field = console.edit_field(arguments)
	question = console.field_edit_questions[field]
	choices = console.field_edit_choices[field]
	default = islist(arguments) ? arguments["value"] : null

/datum/prompt/text/skills_record_edit
	var/list/arguments

/datum/prompt/text/skills_record_edit/prepare(datum/act/A)
	..()
	var/obj/machinery/computer/skills/console = owner
	question = console.field_edit_questions[console.edit_field(arguments)]
	default = islist(arguments) ? arguments["value"] : null

/// The edit modal's answer goes into the record field.
/obj/machinery/computer/skills/proc/modal_edit(datum/act/op/A, list/arguments)
	var/answer = A.step_value("edit_choice")
	if(isnull(answer))
		answer = A.step_value("edit_text")
	. = TRUE
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

/// The comment modal's answer is added to the record's log.
/obj/machinery/computer/skills/proc/modal_add_comment(datum/act/op/A, list/arguments)
	var/answer = A.step_value("comment")
	. = TRUE
	if(!length(answer) || !istype(active1(), /datum/data/record) || !length(authenticated))
		return
	active1().fields["comments"] += list(list(
		header = "Made by [authenticated] ([rank]) at [worldtime2stationtime(world.time)]",
		text = answer
	))
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

/// An EMP scrambles or wipes some of the records.
/obj/machinery/computer/skills/proc/skills_emp(datum/act/A)
	var/datum/notice/hit/emp/N = A
	var/datum/damage_packet/packet = N.packet
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
			destroyed(R, null, "emp")
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
