/// Compositional faction operations. Definitions select an operation family;
/// faction doctrine supplies the departments, authoritative gameplay events,
/// evidence pressure, and IC framing. No operation requires a bespoke machine.

/proc/agent_approach_name(approach)
	switch(approach)
		if(AGENT_APPROACH_REGISTERED)
			return "registered partnership"
		if(AGENT_APPROACH_DISCREET)
			return "compartmentalized commission"
		if(AGENT_APPROACH_HOSTILE)
			return "deniable hostile mandate"
	return "unselected approach"

/proc/agent_discovery_name(stage)
	switch(stage)
		if(AGENT_DISCOVERY_SUSPECTED)
			return "suspicion"
		if(AGENT_DISCOVERY_TRACED)
			return "trace recovered"
		if(AGENT_DISCOVERY_IDENTIFIED)
			return "participants identified"
		if(AGENT_DISCOVERY_PROVEN)
			return "operation proven"
	return "clean"

/proc/agent_faction_departments(faction_id) as /list
	switch(faction_id)
		if(REPUTATION_FACTION_NANOTRASEN)
			return list(DEPARTMENT_COMMAND, DEPARTMENT_RESEARCH, DEPARTMENT_CARGO)
		if(REPUTATION_FACTION_SOLGOV)
			return list(DEPARTMENT_SECURITY, DEPARTMENT_MEDICAL, DEPARTMENT_COMMAND)
		if(REPUTATION_FACTION_CHIMERA)
			return list(DEPARTMENT_MEDICAL, DEPARTMENT_RESEARCH, DEPARTMENT_CARGO)
		if(REPUTATION_FACTION_ECLIPSE)
			return list(DEPARTMENT_RESEARCH, DEPARTMENT_ENGINEERING, DEPARTMENT_CARGO)
		if(REPUTATION_FACTION_SYNDICATE)
			return list(DEPARTMENT_CARGO, DEPARTMENT_RESEARCH, DEPARTMENT_ENGINEERING)
		if(REPUTATION_FACTION_TRADERS_GUILD)
			return list(DEPARTMENT_CARGO, DEPARTMENT_CIVILIAN, DEPARTMENT_COMMAND)
		if(REPUTATION_FACTION_TALON)
			return list(DEPARTMENT_ENGINEERING, DEPARTMENT_CARGO, DEPARTMENT_RESEARCH)
		if(REPUTATION_FACTION_WORKERS_UNION)
			return list(DEPARTMENT_ENGINEERING, DEPARTMENT_CIVILIAN, DEPARTMENT_CARGO)
		if(REPUTATION_FACTION_VEYMED)
			return list(DEPARTMENT_MEDICAL, DEPARTMENT_RESEARCH, DEPARTMENT_CARGO)
	return list(DEPARTMENT_CARGO)

/proc/agent_faction_operation_brief(faction_id, operation_family)
	var/objective = "a measurable station outcome"
	switch(operation_family)
		if(AGENT_OPERATION_SOURCING)
			objective = "a multi-department production and sourcing portfolio"
		if(AGENT_OPERATION_DEMONSTRATION)
			objective = "a time-bounded practical demonstration"
		if(AGENT_OPERATION_SERVICE)
			objective = "a sustained station service outcome"
		if(AGENT_OPERATION_CUSTODY)
			objective = "an authenticated custody or asset-transfer outcome"
		if(AGENT_OPERATION_INFLUENCE)
			objective = "an endorsed institutional relationship"
	switch(faction_id)
		if(REPUTATION_FACTION_NANOTRASEN)
			return "NanoTrasen requests [objective] that improves corporate productivity, accountable funding, or proprietary development. Departmental participation is part of the result, not merely paperwork."
		if(REPUTATION_FACTION_SOLGOV)
			return "SolGov requests [objective] emphasizing documented custody, public safety, and regulated institutional conduct."
		if(REPUTATION_FACTION_CHIMERA)
			return "Chimera Genetics requests [objective] grounded in clinical, chemical, or biological work with independently documented results."
		if(REPUTATION_FACTION_ECLIPSE)
			return "Eclipse requests [objective] demonstrating competitive research, reproducible prototypes, and technically credible evaluation."
		if(REPUTATION_FACTION_SYNDICATE)
			return "The principal requests [objective] through compartmentalized station relationships. Ordinary commercial cover does not excuse unauthorized conduct."
		if(REPUTATION_FACTION_TRADERS_GUILD)
			return "The Trader's Guild requests [objective] proven through real purchases, customers, suppliers, and two-way station commerce."
		if(REPUTATION_FACTION_TALON)
			return "TALON requests [objective] proven through field repair, rugged production, and operational industrial work."
		if(REPUTATION_FACTION_WORKERS_UNION)
			return "The Worker's Union requests [objective] that visibly benefits participating workers through compensation, productive work, or departmental leverage."
		if(REPUTATION_FACTION_VEYMED)
			return "VeyMed requests [objective] supported by treatment outcomes, body-scanner records, and controlled clinical handling."
	return "The principal requests [objective]."

/datum/contract/faction_agent/proc/configure_operation(operation_family)
	operation_kind = operation_family
	stakeholder_departments = agent_faction_departments(agent_faction)
	department = stakeholder_departments[1]
	contact_departments = stakeholder_departments.Copy()
	var/profile_id = offer_context?["profile_id"] || agent_target_profile(agent_faction)
	offer_context["profile_id"] = profile_id
	var/datum/reputation_faction/faction = GLOB.reputation_factions[agent_faction]
	title = "[faction?.short_name || "Principal"] [capitalize(operation_family)] Operation"
	description = agent_faction_operation_brief(agent_faction, operation_family)
	switch(operation_family)
		if(AGENT_OPERATION_SOURCING)
			configure_sourcing_operation(profile_id)
		if(AGENT_OPERATION_DEMONSTRATION)
			configure_demonstration_operation(profile_id)
		if(AGENT_OPERATION_SERVICE)
			configure_service_operation(profile_id)
		if(AGENT_OPERATION_CUSTODY)
			configure_custody_operation(profile_id)
		if(AGENT_OPERATION_INFLUENCE)
			configure_influence_operation(profile_id)

/datum/contract/faction_agent/proc/add_agent_count(event_type, target, requirement_name, requirement_description, value_field = null, unique_field = null, list/exact_values, list/numeric_checks)
	var/datum/contract_requirement/event_count/requirement = new(event_type, target, exact_values, value_field, TRUE, CONTRACT_EVIDENCE_SCOPE_ANY)
	requirement.name = requirement_name
	requirement.description = requirement_description
	requirement.unique_field = unique_field
	for(var/list/check as anything in numeric_checks)
		requirement.require_number(check["key"], check["comparator"], check["expected"])
	add_requirement(requirement)
	return requirement

/datum/contract/faction_agent/proc/add_agent_portfolio(event_type, target, category_field, value_field, category_target, requirement_name, requirement_description, list/exact_values)
	var/datum/contract_requirement/fact_portfolio/requirement = new(event_type, target, category_field, value_field, category_target, CONTRACT_EVIDENCE_SCOPE_ANY)
	requirement.name = requirement_name
	requirement.description = requirement_description
	for(var/key in exact_values)
		requirement.filter.require_value(key, exact_values[key])
	add_requirement(requirement)
	return requirement

/datum/contract/faction_agent/proc/add_agent_sustained(event_type, entity_field, numeric_field, comparator, threshold, duration, target, requirement_name, requirement_description, list/exact_values, list/numeric_checks)
	var/datum/contract_requirement/sustained_event/requirement = new(event_type, entity_field, numeric_field, comparator, threshold, duration, target, CONTRACT_EVIDENCE_SCOPE_ANY)
	requirement.name = requirement_name
	requirement.description = requirement_description
	for(var/key in exact_values)
		requirement.filter.require_value(key, exact_values[key])
	for(var/list/check as anything in numeric_checks)
		requirement.filter.require_number(check["key"], check["comparator"], check["expected"])
	add_requirement(requirement)
	return requirement

/datum/contract/faction_agent/proc/configure_sourcing_operation(profile_id)
	add_agent_portfolio(CONTRACT_EVENT_CARGO_MARKET_EXPORT, 2400, "origin_department", "value", 2, "Multi-department portfolio", "Negotiate and route matching production from at least two departments through the authenticated operation.", list("faction_id" = agent_faction, "profile_id" = profile_id, "market_contract_key" = offer_key))
	add_agent_count(CONTRACT_EVENT_ITEM_PRODUCED, 3, "Local production partners", "Have three distinct station-made product types produced by participating departments.", null, "item_type")

/datum/contract/faction_agent/proc/configure_demonstration_operation(profile_id)
	switch(agent_faction)
		if(REPUTATION_FACTION_CHIMERA, REPUTATION_FACTION_VEYMED)
			add_agent_count(CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, 120, "Measured clinical outcome", "Deliver substantial measurable improvement across participating patients.", "improvement")
			add_agent_count(CONTRACT_EVENT_MEDICAL_SCAN_CREATED, 3, "Documented participants", "File body-scanner records for three distinct participants.", null, "subject_id")
		if(REPUTATION_FACTION_TALON, REPUTATION_FACTION_WORKERS_UNION)
			add_agent_portfolio(CONTRACT_EVENT_ITEM_PRODUCED, 1400, "item_type", "value", 3, "Field equipment suite", "Produce a varied suite of rugged station equipment for field evaluation.", list())
			add_agent_portfolio(CONTRACT_EVENT_CARGO_MARKET_EXPORT, 1200, "item_type", "value", 2, "Independent field consignments", "Fulfil the authenticated offer with at least two station-made equipment types.", list("faction_id" = agent_faction, "profile_id" = profile_id, "market_contract_key" = offer_key))
		else
			add_agent_count(CONTRACT_EVENT_RESEARCH_MILESTONE, 2, "Research validation", "Complete two distinct research milestones during the commission.", null, "node_id")
			add_agent_portfolio(CONTRACT_EVENT_ITEM_PRODUCED, 1200, "item_type", "value", 3, "Demonstration outputs", "Produce 1,200 Thalers of station equipment across three product types.", list())

/datum/contract/faction_agent/proc/configure_service_operation(profile_id)
	switch(agent_faction)
		if(REPUTATION_FACTION_TRADERS_GUILD)
			add_agent_count(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 700, "Verified station commerce", "Close Civilian service accounting with 700 Thalers of verified crew purchases.", "verified_amount", null, list("rollup" = "department", "department" = DEPARTMENT_CIVILIAN))
			add_agent_count(CONTRACT_EVENT_FOOD_CONSUMED, contract_scaled_participant_target(8, 3, 1), "Customer reach", "Serve invoiced food or drink to distinct paying customers.", null, "subject_id", null, list(list("key" = "sale_invoice_id", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 1)))
		if(REPUTATION_FACTION_SOLGOV)
			add_agent_count(CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, 3, "Documented case outcomes", "Resolve three custodial Security cases concerning distinct identifiable people.", null, "subject_id", list("physical_custody_verified" = TRUE))
			add_agent_count(CONTRACT_EVENT_CUSTODY_CHANGED, 2, "Documented custody", "Document custody of two distinct people.", null, "subject_id")
		if(REPUTATION_FACTION_NANOTRASEN)
			add_agent_count(CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 1, "Funded operating cycle", "Close a station budget cycle with at least 75% payroll coverage.", null, null, list("rollup" = "station"), list(list("key" = "payroll_coverage", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 0.75)))
			add_agent_count(CONTRACT_EVENT_MONEY_TRANSFERRED, 600, "Participant consideration", "Move 600 Thalers in real station commerce among distinct recipients.", "amount", "target_account")
		else
			add_agent_count(CONTRACT_EVENT_ITEM_PRODUCED, 4, "Service outputs", "Produce four distinct useful station products.", null, "item_type")
			add_agent_count(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 500, "Operational adoption", "Close 500 Thalers of crew purchases for station-made products or services.", "verified_amount")

/datum/contract/faction_agent/proc/configure_custody_operation(profile_id)
	switch(agent_faction)
		if(REPUTATION_FACTION_SOLGOV)
			add_agent_count(CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, 4, "Controlled disposition docket", "Resolve four custodial Security cases concerning identifiable people.", null, "record_id", list("physical_custody_verified" = TRUE))
			add_agent_count(CONTRACT_EVENT_CUSTODY_CHANGED, 3, "Custody chain", "Establish documented custody of three distinct people.", null, "subject_id")
		if(REPUTATION_FACTION_CHIMERA, REPUTATION_FACTION_VEYMED)
			add_agent_count(CONTRACT_EVENT_MEDICAL_SCAN_CREATED, 4, "Clinical custody records", "File body-scanner records for four distinct clinical subjects.", null, "subject_id")
			add_agent_portfolio(CONTRACT_EVENT_CARGO_MARKET_EXPORT, 1400, "item_type", "value", 2, "Controlled clinical transfer", "Transfer a varied medical portfolio through the signed agreement.", list("faction_id" = agent_faction, "profile_id" = profile_id, "market_contract_key" = offer_key))
		else
			add_agent_portfolio(CONTRACT_EVENT_CARGO_MARKET_EXPORT, 2200, "item_type", "value", 3, "Authenticated asset transfer", "Transfer three distinct matching asset types under the operation's signed custody terms.", list("faction_id" = agent_faction, "profile_id" = profile_id, "market_contract_key" = offer_key))

/datum/contract/faction_agent/proc/configure_influence_operation(profile_id)
	required_endorsements = 2
	add_agent_portfolio(CONTRACT_EVENT_AGENT_ENDORSEMENT_SIGNED, 2, "actor_department", null, 2, "Departmental mandate", "Secure department-head signatures from two distinct stakeholder departments on the physical operation charter.", list("operation_key" = offer_key))
	switch(agent_faction)
		if(REPUTATION_FACTION_WORKERS_UNION)
			add_agent_count(CONTRACT_EVENT_MONEY_TRANSFERRED, 800, "Worker-directed consideration", "Direct 800 Thalers of genuine compensation across distinct station recipients.", "amount", "target_account")
			add_agent_portfolio(CONTRACT_EVENT_ITEM_PRODUCED, 900, "department", "value", 2, "Worker-directed production", "Produce useful equipment through two participating departments.", list())
		if(REPUTATION_FACTION_TRADERS_GUILD)
			add_agent_count(CONTRACT_EVENT_CARGO_MARKET_PURCHASE, 1200, "Endorsed procurement", "Receive 1,200 Thalers of goods through the endorsed supplier relationship.", "value", null, list("faction_id" = agent_faction, "market_contract_key" = offer_key))
			add_agent_count(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 500, "Local resale", "Settle 500 Thalers of verified Civilian service sales.", "verified_amount", null, list("department" = DEPARTMENT_CIVILIAN, "rollup" = "department"))
		else
			add_agent_portfolio(CONTRACT_EVENT_ITEM_PRODUCED, 1000, "department", "value", 2, "Endorsed departmental output", "Produce 1,000 Thalers of useful output across two participating departments.", list())

/// A red operation uses faction doctrine to choose its actual gameplay loop.
/datum/contract/faction_agent/proc/configure_red_operation(profile_id)
	minimum_contact_risk = 2
	switch(agent_faction)
		if(REPUTATION_FACTION_NANOTRASEN)
			add_agent_count(CONTRACT_EVENT_RESEARCH_MILESTONE, 3, "Proprietary research capture", "Advance three distinct research milestones before transferring the resulting assets.", null, "node_id")
			add_agent_portfolio(CONTRACT_EVENT_CARGO_MARKET_EXPORT, 2600, "item_type", "value", 3, "Corporate asset reclamation", "Covertly transfer three station-developed product types.", list("faction_id" = agent_faction, "profile_id" = profile_id, "market_contract_key" = offer_key))
		if(REPUTATION_FACTION_SOLGOV)
			add_agent_count(CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, 3, "Embargo enforcement docket", "Create three resolved custodial dispositions involving identifiable people.", null, "record_id", list("physical_custody_verified" = TRUE))
			add_agent_portfolio(CONTRACT_EVENT_CARGO_MARKET_EXPORT, 2400, "item_type", "value", 2, "Embargoed arms seizure", "Transfer two controlled armament types outside authorized station custody.", list("faction_id" = agent_faction, "profile_id" = profile_id, "market_contract_key" = offer_key))
		if(REPUTATION_FACTION_CHIMERA)
			add_agent_count(CONTRACT_EVENT_CHEMISTRY_RESULT, 5, "Restricted synthesis", "Complete five distinct chemical reactions for the acquisition program.", null, "reaction_id")
			add_agent_count(CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, 100, "Biological response data", "Document a substantial aggregate change in treated patient conditions.", "improvement")
		if(REPUTATION_FACTION_ECLIPSE)
			add_agent_count(CONTRACT_EVENT_RESEARCH_MILESTONE, 4, "Competitive research capture", "Advance four distinct research milestones.", null, "node_id")
			add_agent_portfolio(CONTRACT_EVENT_ITEM_PRODUCED, 2200, "item_type", "value", 4, "Replicated prototype suite", "Produce four distinct valuable prototype classes for covert evaluation.", list())
		if(REPUTATION_FACTION_TRADERS_GUILD)
			add_agent_count(CONTRACT_EVENT_CARGO_MARKET_PURCHASE, 1600, "Exclusive import position", "Purchase 1,600 Thalers through the principal's private listings.", "value", null, list("faction_id" = agent_faction, "market_contract_key" = offer_key))
			add_agent_portfolio(CONTRACT_EVENT_CARGO_MARKET_EXPORT, 2600, "origin_department", "value", 3, "Diverted commercial portfolio", "Divert production from three station departments into the freeport route.", list("faction_id" = agent_faction, "profile_id" = profile_id, "market_contract_key" = offer_key))
		if(REPUTATION_FACTION_TALON)
			add_agent_portfolio(CONTRACT_EVENT_CARGO_MARKET_EXPORT, 2200, "item_type", "value", 3, "Contested equipment recovery", "Transfer three classes of field equipment into TALON custody.", list("faction_id" = agent_faction, "profile_id" = profile_id, "market_contract_key" = offer_key))
			add_agent_count(CONTRACT_EVENT_ITEM_PRODUCED, 4, "Field-production breadth", "Produce four distinct classes of rugged station equipment for the recovery.", null, "item_type")
		if(REPUTATION_FACTION_WORKERS_UNION)
			add_agent_count(CONTRACT_EVENT_MONEY_TRANSFERRED, 1200, "Worker-controlled funds", "Redirect 1,200 Thalers across distinct station workers or departments.", "amount", "target_account")
			add_agent_count(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 700, "Worker-controlled commerce", "Settle 700 Thalers of paid station service under the arrangement.", "verified_amount")
		if(REPUTATION_FACTION_VEYMED)
			add_agent_count(CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, 180, "Confidential clinical outcomes", "Document substantial aggregate improvement across treated patients.", "improvement")
			add_agent_count(CONTRACT_EVENT_MEDICAL_SCAN_CREATED, 4, "Restricted clinical records", "Produce scans for four distinct clinical subjects.", null, "subject_id")
		else
			add_agent_portfolio(CONTRACT_EVENT_CARGO_MARKET_EXPORT, 5000, "item_type", "value", 3, "Deniable exfiltration portfolio", "Exfiltrate 5,000 Thalers across three matching item types.", list("faction_id" = agent_faction, "profile_id" = profile_id, "market_contract_key" = offer_key))

/datum/contract/faction_agent/proc/select_operation_approach(obj/item/paper/paper, mob/living/user, selected_approach, evidence_id)
	if(state != CONTRACT_ACTIVE || approach)
		return FALSE
	var/datum/money_account/account = contract_account_for_mob(user)
	if(account?.account_number != owner_account_number)
		return FALSE
	if(selected_approach == AGENT_APPROACH_HOSTILE && !red_contract)
		to_chat(user, span_warning("This commission contains no explicit hostile authorization."))
		return FALSE
	if(selected_approach == AGENT_APPROACH_REGISTERED && red_contract)
		to_chat(user, span_warning("The principal does not offer a registered form of this hostile mandate."))
		return FALSE
	approach = selected_approach
	switch(approach)
		if(AGENT_APPROACH_REGISTERED)
			station_share = 0.2
			department_share = 0.2
			contributor_share = 0.6
			failure_reputation_factor = 0.25
			operation_reward_multiplier = 0.9
		if(AGENT_APPROACH_DISCREET)
			failure_reputation_factor = 0.5
			operation_reward_multiplier = 1
			GLOB.station_faction_relations.add_agent_exposure(owner_account_number, agent_faction, 3, "A compartmentalized charter created a recoverable private record.", "CHARTER-[id]")
		if(AGENT_APPROACH_HOSTILE)
			failure_reputation_factor = 1
			operation_reward_multiplier = 1.25
			GLOB.station_faction_relations.add_agent_exposure(owner_account_number, agent_faction, 10, "The hostile mandate created an encrypted operational trace.", "CHARTER-[id]")
	base_reward = round(base_reward * operation_reward_multiplier)
	reward = base_reward + negotiated_station_bonus + negotiated_department_bonus + negotiated_staff_bonus
	emit_contract_event(CONTRACT_EVENT_AGENT_APPROACH_SIGNED, list(
		"contract_id" = id,
		"actor_account" = account.account_number,
		"faction_id" = agent_faction,
		"approach" = approach,
		"evidence_ids" = list(evidence_id),
		"detail" = "[account.owner_name] signed the [agent_approach_name(approach)] charter.",
	), "agent-approach:[id]:[approach]", paper, user, user)
	audit(CONTRACT_AUDIT_NEGOTIATION, "[account.owner_name] selected [agent_approach_name(approach)]; award, institutional share, disclosure, and failure liability are now locked.")
	to_chat(user, span_notice("You signed the [agent_approach_name(approach)]. Its award distribution and exposure consequences are now binding."))
	return TRUE

/datum/contract/faction_agent/proc/advance_discovery(new_stage, detail, exposure = 0)
	if(new_stage <= discovery_stage)
		return FALSE
	discovery_stage = clamp(new_stage, AGENT_DISCOVERY_CLEAN, AGENT_DISCOVERY_PROVEN)
	discovery_detail = detail
	if(exposure > 0)
		GLOB.station_faction_relations.add_agent_exposure(owner_account_number, agent_faction, exposure, detail, "OPERATION-[id]-[discovery_stage]")
	audit(CONTRACT_AUDIT_EVIDENCE, "Discovery advanced to [agent_discovery_name(discovery_stage)]: [detail]")
	notify_faction_agent_account(owner_account_number, "[title] discovery status: [agent_discovery_name(discovery_stage)].")
	if(contact_account_number)
		var/mob/living/contact = find_mob_by_account(contact_account_number)
		to_chat(contact, span_warning("Your contact work on [title] has advanced to [agent_discovery_name(discovery_stage)]."))
	return TRUE

/datum/contract/faction_agent/proc/current_operation_ratio()
	var/ratio = 1
	var/has_required = FALSE
	for(var/datum/contract_requirement/requirement in requirements)
		if(!requirement.required)
			continue
		has_required = TRUE
		ratio = min(ratio, requirement.grade_progress())
	return has_required ? clamp(ratio, 0, 1) : 0

/datum/contract/faction_agent/proc/operation_grade_for_ratio(ratio)
	if(ratio >= CONTRACT_GRADE_EXCEPTIONAL_RATIO)
		return CONTRACT_OUTCOME_EXCEPTIONAL
	if(ratio >= CONTRACT_GRADE_SUCCESS_RATIO)
		return CONTRACT_OUTCOME_SUCCESSFUL
	if(ratio >= CONTRACT_GRADE_MINIMUM_RATIO)
		return CONTRACT_OUTCOME_MINIMUM
	return CONTRACT_OUTCOME_UNRATED

/datum/contract/faction_agent/proc/discovery_reward_multiplier()
	switch(discovery_stage)
		if(AGENT_DISCOVERY_SUSPECTED)
			return 0.95
		if(AGENT_DISCOVERY_TRACED)
			return 0.85
		if(AGENT_DISCOVERY_IDENTIFIED)
			return 0.7
		if(AGENT_DISCOVERY_PROVEN)
			return 0.5
	return 1

/datum/contract/faction_agent/proc/finalize_operation(actor_name = "Automatic settlement")
	if(outcome_finalized || !(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)))
		return FALSE
	var/ratio = current_operation_ratio()
	var/grade = operation_grade_for_ratio(ratio)
	var/grade_multiplier = 0
	switch(grade)
		if(CONTRACT_OUTCOME_MINIMUM)
			grade_multiplier = CONTRACT_GRADE_MINIMUM_REWARD
		if(CONTRACT_OUTCOME_SUCCESSFUL)
			grade_multiplier = CONTRACT_GRADE_SUCCESS_REWARD
		if(CONTRACT_OUTCOME_EXCEPTIONAL)
			grade_multiplier = CONTRACT_GRADE_EXCEPTIONAL_REWARD
	if(grade_multiplier <= 0)
		return FALSE
	outcome_finalized = TRUE
	outcome_grade = grade
	outcome_score = round(ratio * 100, 0.1)
	var/settlement_multiplier = grade_multiplier * discovery_reward_multiplier()
	base_reward = round(base_reward * settlement_multiplier)
	negotiated_station_bonus = round(negotiated_station_bonus * settlement_multiplier)
	negotiated_department_bonus = round(negotiated_department_bonus * settlement_multiplier)
	negotiated_staff_bonus = round(negotiated_staff_bonus * settlement_multiplier)
	reward = base_reward + negotiated_station_bonus + negotiated_department_bonus + negotiated_staff_bonus
	station_reputation_reward = round(station_reputation_reward * settlement_multiplier)
	department_reputation_reward = round(department_reputation_reward * settlement_multiplier)
	personal_reputation_reward = round(personal_reputation_reward * settlement_multiplier)
	audit(CONTRACT_AUDIT_COMPLETED, "[actor_name] settled a [grade] result at [outcome_score]% with discovery status [agent_discovery_name(discovery_stage)].")
	return complete()

/datum/contract/faction_agent/reconcile_completion()
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)))
		return FALSE
	if(outcome_finalized)
		return ..()
	for(var/datum/contract_requirement/requirement in requirements)
		if(requirement.required && requirement.state != CONTRACT_REQUIREMENT_COMPLETE)
			outcome_score = round(current_operation_ratio() * 100, 0.1)
			return FALSE
	return finalize_operation("Authoritative operation evidence")

/datum/contract/faction_agent/check_deadline()
	deadline_timer = null
	if(state == CONTRACT_ACTIVE && deadline && world.time >= deadline)
		if(current_operation_ratio() >= CONTRACT_GRADE_MINIMUM_RATIO)
			finalize_operation()
		else
			fail("The operation closed below its minimum graded outcome.")

/datum/contract/faction_agent/apply_failure_reputation()
	if(!issuer_faction)
		return
	var/exposure_multiplier = 1 + (discovery_stage * 0.2)
	var/personal_penalty = -max(1, round(max(1, personal_reputation_reward) * failure_reputation_factor * exposure_multiplier))
	adjust_personal_faction_reputation(owner_account_number, issuer_faction, personal_penalty)
	if(contact_account_number)
		adjust_personal_faction_reputation(contact_account_number, issuer_faction, min(-1, round(personal_penalty * 0.5)))
	if(approach == AGENT_APPROACH_REGISTERED)
		adjust_station_faction_reputation(issuer_faction, -max(1, round(max(1, station_reputation_reward) * failure_reputation_factor)))
		adjust_department_faction_reputation(department, issuer_faction, -max(1, round(max(1, department_reputation_reward) * failure_reputation_factor)))
