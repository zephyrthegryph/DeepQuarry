/// Broad, event-driven contracts for ordinary station work. These definitions
/// deliberately consume events emitted by the authoritative gameplay systems;
/// they do not scan the world or create contract-only machines and tokens.

/datum/contract/outcome
	var/primary_target = 0
	var/secondary_target = 0
	var/outcome_duration = 0
	var/outcome_variant = "standard"
	var/list/personal_side_definitions

/datum/contract/outcome/Destroy()
	personal_side_definitions = null
	return ..()

/datum/contract/outcome/on_accepted(mob/living/user, atom/source)
	offer_linked_personal_contracts(user)

/datum/contract/outcome/proc/personal_offer_context(definition_id)
	return list(
		"parent_contract_id" = id,
		"parent_definition_id" = src.definition_id,
		"department" = department,
		"primary_target" = primary_target,
		"secondary_target" = secondary_target,
		"outcome_duration" = outcome_duration,
		"outcome_variant" = outcome_variant,
	)

/datum/contract/outcome/proc/offer_linked_personal_contracts(mob/living/accepting_user)
	if(!length(personal_side_definitions))
		return
	for(var/side_definition_id in personal_side_definitions)
		offer_linked_personal_contract(side_definition_id, accepting_user)

/datum/contract/outcome/proc/offer_linked_personal_contract(side_definition_id, mob/living/accepting_user, excluded_account = 0)
	var/datum/contract_definition/personal_outcome/definition = SScontracts.definitions[side_definition_id]
	if(!istype(definition) || !(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)))
		return FALSE
	var/list/eligible_players = list()
	var/lowest_live_count
	for(var/mob/living/player in GLOB.player_list)
		if((!player.client && !contract_unit_test_mode()) || player.stat == DEAD || department_for_mob(player) != department)
			continue
		var/datum/money_account/account = contract_account_for_mob(player)
		if(!account || account.account_number == excluded_account)
			continue
		var/list/context = personal_offer_context(side_definition_id)
		context["owner_account"] = account.account_number
		if(!definition.is_available(context))
			continue
		var/live_count = contract_personal_live_count(account.account_number)
		if(isnull(lowest_live_count) || live_count < lowest_live_count)
			lowest_live_count = live_count
			eligible_players = list(player)
		else if(live_count == lowest_live_count)
			eligible_players += player
	if(!length(eligible_players))
		return FALSE
	var/mob/living/selected = pick(eligible_players)
	var/datum/money_account/selected_account = contract_account_for_mob(selected)
	var/list/selected_context = personal_offer_context(side_definition_id)
	selected_context["owner_account"] = selected_account.account_number
	selected_context["offer_kind"] = CONTRACT_OFFER_OPPORTUNITY
	var/offer_key = "linked:[side_definition_id]:[id]:[selected_account.account_number]"
	SScontracts.queue_offer(side_definition_id, selected_context, "A linked department contract created a private opportunity", offer_key, 75)
	if(selected == accepting_user)
		to_chat(selected, span_notice("A private counter-offer related to [title] is now available on your PDA."))
	return TRUE

/proc/contract_personal_live_count(account_number)
	var/count = 0
	for(var/datum/contract/contract in SScontracts.offered_contracts + SScontracts.active_contracts + SScontracts.grace_contracts)
		if(contract.scope == CONTRACT_SCOPE_PERSONAL && contract.owner_account_number == account_number)
			count++
	return count

/proc/contract_mob_for_account(account_number) as /mob/living
	for(var/mob/living/player in GLOB.player_list)
		if(contract_account_for_mob(player)?.account_number == account_number)
			return player

/// Reputation affects the actual offered terms rather than merely decorating
/// the UI. Trusted stations receive progressively better compensation; poor
/// standing leaves the contract available but adds a risk discount.
/proc/apply_contract_standing_terms(datum/contract/contract)
	if(!contract?.issuer_faction)
		return
	var/station_standing = get_station_faction_reputation(contract.issuer_faction)
	var/department_standing = contract.department ? get_department_faction_reputation(contract.department, contract.issuer_faction) : station_standing
	var/standing = isnum(department_standing) ? round((station_standing + department_standing) / 2) : station_standing
	contract.standing_score = standing
	contract.standing_tier = reputation_rank(standing)
	var/percent = 0
	if(standing >= REPUTATION_REVERED)
		percent = 15
	else if(standing >= REPUTATION_ALLIED)
		percent = 10
	else if(standing >= REPUTATION_FRIENDLY)
		percent = 10
	else if(standing <= REPUTATION_HOSTILE)
		percent = -10
	else if(standing <= REPUTATION_UNFRIENDLY)
		percent = -5
	contract.standing_reward_modifier = percent
	if(percent)
		contract.reward = max(0, round(contract.reward * (100 + percent) / 100))

/proc/apply_personal_contract_standing_terms(datum/contract/contract)
	if(!contract?.issuer_faction || !contract.owner_account_number)
		return
	var/mob/living/owner = contract_mob_for_account(contract.owner_account_number)
	if(!owner)
		return
	var/standing = owner.get_faction_reputation(contract.issuer_faction)
	contract.standing_score = standing
	contract.standing_tier = reputation_rank(standing)
	var/percent = standing >= REPUTATION_ALLIED ? 10 : (standing >= REPUTATION_FRIENDLY ? 10 : (standing <= REPUTATION_HOSTILE ? -10 : (standing <= REPUTATION_UNFRIENDLY ? -5 : 0)))
	contract.standing_reward_modifier = percent
	if(percent)
		contract.reward = max(0, round(contract.reward * (100 + percent) / 100))

/proc/add_contract_payout_negotiation(datum/contract/contract)
	var/minor_shift = max(50, round(contract.reward * 0.05))
	var/major_shift = max(100, round(contract.reward * 0.15))
	var/combined_shift = minor_shift + major_shift
	var/datum/contract_negotiation_clause/distribution = new("distribution", "Award split", "Choose who receives most of the contract award.")
	distribution.add_option(make_contract_clause_option("balanced", "Standard split", "Use the listed station, department, and staff shares."), TRUE)
	distribution.add_option(make_contract_clause_option("staff", "Pay the crew", "Move funding from station and department accounts to participating staff.", -minor_shift, -major_shift, combined_shift, 0, -2, 4, 0, list("other_faction_reputation" = list(REPUTATION_FACTION_WORKERS_UNION = 3))))
	distribution.add_option(make_contract_clause_option("department", "Fund the department", "Keep most of the flexible funding in the responsible department.", -minor_shift, combined_shift, -major_shift, 0, 4, -2))
	distribution.add_option(make_contract_clause_option("station", "Fund station reserves", "Keep most of the flexible funding in the station account.", combined_shift, -major_shift, -minor_shift, 4, -2, -1))
	contract.add_negotiation_clause(distribution)

/proc/configure_outcome_negotiations(datum/contract/contract, deadline = 40 MINUTES, include_schedule = TRUE)
	contract.station_share = 0.2
	contract.department_share = 0.6
	contract.contributor_share = 0.2
	contract.deadline_duration = deadline
	apply_contract_standing_terms(contract)
	add_contract_payout_negotiation(contract)

	if(include_schedule)
		var/schedule_shift = max(100, round(contract.reward * 0.12))
		var/datum/contract_negotiation_clause/schedule = new("schedule", "Delivery window", "Trade time against payment and sponsor confidence.")
		schedule.add_option(make_contract_clause_option("accelerated", "Rush · 10 min sooner", "Finish ten minutes sooner for a larger award.", round(schedule_shift * 0.2), round(schedule_shift * 0.6), round(schedule_shift * 0.2), -2, -2, -1, -10 MINUTES))
		schedule.add_option(make_contract_clause_option("standard", "Standard window", "Keep the listed deadline and award."), TRUE)
		schedule.add_option(make_contract_clause_option("extended", "Careful · 10 min longer", "Take ten more minutes for less cash and stronger standing.", -round(schedule_shift * 0.2), -round(schedule_shift * 0.6), -round(schedule_shift * 0.2), 2, 3, 1, 10 MINUTES))
		contract.add_negotiation_clause(schedule)

/datum/contract_definition/outcome
	abstract_type = /datum/contract_definition/outcome
	initial_offers = 1
	offer_kind = CONTRACT_OFFER_STANDING
	auto_replace = TRUE
	max_simultaneous = 2
	var/followup_reputation_threshold = REPUTATION_ALLIED
	contract_type = /datum/contract/outcome

/datum/contract_definition/outcome/prepare_accept(datum/contract/outcome/contract, datum/money_account/accepting_account, mob/living/user, atom/source)
	var/live_crew = 0
	for(var/mob/living/player in GLOB.player_list)
		if(player.client && player.stat != DEAD && contract_account_for_mob(player))
			live_crew++
	switch(id)
		if("supermatter_performance")
			if(user)
				var/has_station_crystal = FALSE
				for(var/obj/machinery/power/supermatter/crystal in REGISTRY_MEMBERS(REGISTRY_MACHINES))
					if(crystal.stationcrystal && (crystal.z in using_map.station_levels))
						has_station_crystal = TRUE
						break
				if(!has_station_crystal)
					to_chat(user, span_warning("No station supermatter telemetry source is currently available."))
					return FALSE
		if("service_hospitality_census")
			contract.secondary_target = min(contract.secondary_target, max(1, live_crew - 1))
			contract.primary_target = min(contract.primary_target, contract.secondary_target * 400)
			for(var/datum/contract_requirement/event_count/requirement in contract.requirements)
				requirement.filter.set_number_requirement("amount", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.primary_target)
				requirement.filter.set_number_requirement("customer_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.secondary_target)
				requirement.description = "Close an accounting period with [contract.primary_target] Thalers in qualifying sales to [contract.secondary_target] distinct customers."
		if("security_case_resolution")
			contract.primary_target = min(contract.primary_target, max(1, live_crew - 1))
			for(var/datum/contract_requirement/event_count/requirement in contract.requirements)
				requirement.target = contract.primary_target
				requirement.description = "Record [contract.primary_target] distinct releases or paroles after [DisplayTimeText(contract.outcome_duration)] in custody."
		if("command_budget_mandate")
			var/available_departments = 0
			for(var/department_name in GLOB.department_accounts)
				if(department_name != DEPARTMENT_PLANET && department_name != "Vendor")
					available_departments++
			var/minimum_allocation = max(1, contract.outcome_duration)
			var/funding_capacity = SSsupply.projected_station_budget_capacity()
			var/fundable_departments = min(available_departments, FLOOR(funding_capacity / minimum_allocation, 1))
			if(fundable_departments < 1)
				if(user)
					to_chat(user, span_warning("The station lacks enough current funds and committed payroll support to accept this capital mandate."))
				return FALSE
			contract.secondary_target = min(contract.secondary_target, fundable_departments)
			contract.primary_target = max(contract.secondary_target * minimum_allocation, min(contract.primary_target, funding_capacity, contract.secondary_target * 4000))
			contract.description = "Complete one monthly budget and payroll cycle that actually funds at least [contract.primary_target] Thalers among [contract.secondary_target] station departments, with no qualifying department below [minimum_allocation] Thalers and at least 75% of wages paid. Exploration is excluded and Command may retain no more than 3,000 Thalers under the diversified mandate."
			for(var/datum/contract_requirement/event_count/requirement in contract.requirements)
				requirement.filter.set_number_requirement("funded_allocation_total", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.primary_target)
				requirement.filter.set_number_requirement("funded_department_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.secondary_target)
				requirement.description = "Close one cycle with [contract.primary_target] funded Thalers across [contract.secondary_target] qualifying departments while keeping Command's allocation at or below 3,000."
	return TRUE

/datum/contract_definition/outcome/supermatter_performance
	id = "supermatter_performance"
	title = "Supermatter Performance Demonstration"
	description = "NanoTrasen Power Systems requests a controlled high-output supermatter demonstration monitored by the station's calibrated crystal console."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_ENGINEERING
	issuer_name = "NanoTrasen Power Systems"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 2400
	contract_type = /datum/contract/outcome/engine_performance

/datum/contract/outcome/engine_performance
	var/datum/contract_requirement/staged_sustained_event/performance_requirement
	/// Synthetic tests may shorten the timers without weakening live terms.
	var/stage_duration_override = 0

/datum/contract/outcome/engine_performance/Destroy()
	performance_requirement = null
	return ..()

/datum/contract/outcome/engine_performance/on_negotiated_terms_changed()
	..()
	if(!performance_requirement)
		return
	var/profile = negotiated_effect("engine_output_profile", "rated")
	var/list/stages
	switch(profile)
		if("assured")
			primary_target = 600
			secondary_target = 94
			stages = list(
				list("label" = "Baseline", "threshold" = 400, "unit" = "EER", "duration" = 45 SECONDS),
				list("label" = "Commercial", "threshold" = 500, "unit" = "EER", "duration" = 45 SECONDS),
				list("label" = "Assured maximum", "threshold" = 600, "unit" = "EER", "duration" = 1 MINUTE),
			)
		if("frontier")
			primary_target = 1000
			secondary_target = 85
			stages = list(
				list("label" = "High output", "threshold" = 600, "unit" = "EER", "duration" = 1 MINUTE),
				list("label" = "Frontier", "threshold" = 800, "unit" = "EER", "duration" = 75 SECONDS),
				list("label" = "Experimental maximum", "threshold" = 1000, "unit" = "EER", "duration" = 90 SECONDS),
			)
		else
			primary_target = 800
			secondary_target = 90
			stages = list(
				list("label" = "Baseline", "threshold" = 500, "unit" = "EER", "duration" = 1 MINUTE),
				list("label" = "Rated output", "threshold" = 650, "unit" = "EER", "duration" = 1 MINUTE),
				list("label" = "Maximum output", "threshold" = 800, "unit" = "EER", "duration" = 75 SECONDS),
			)
	if(stage_duration_override > 0)
		for(var/list/stage as anything in stages)
			stage["duration"] = stage_duration_override
	performance_requirement.set_stages(stages)
	performance_requirement.filter.set_number_requirement("integrity", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, secondary_target)
	performance_requirement.description = "Certify the three [profile] output stages in sequence while maintaining at least [secondary_target]% crystal integrity. Each stage begins after the previous stage is certified."
	description = "Certify progressively stronger supermatter output under the negotiated [profile] charter, culminating at [primary_target] Relative EER while maintaining at least [secondary_target]% integrity."

/datum/contract_definition/outcome/supermatter_performance/configure_contract(datum/contract/outcome/engine_performance/contract, list/context)
	contract.primary_target = 800
	contract.secondary_target = 90
	contract.outcome_duration = 1 MINUTE
	contract.stage_duration_override = contract_unit_test_mode() ? context?["duration"] : 0
	contract.description = "Certify progressively stronger supermatter output while calibrated station telemetry verifies crystal integrity."
	contract.station_reputation_reward = 10
	contract.department_reputation_reward = 28
	contract.personal_reputation_reward = 8
	configure_outcome_negotiations(contract, 35 MINUTES, FALSE)
	var/datum/contract_negotiation_clause/output = new("engine_output", "Operating target", "Choose the required output and safety margin.")
	output.add_option(make_contract_clause_option("assured", "Safe · 600 EER", "Stages: 400 / 500 / 600 EER. Keep 94% integrity.", -100, -200, 0, 2, 4, 1, 0, list("engine_output_profile" = "assured")))
	output.add_option(make_contract_clause_option("rated", "Rated · 800 EER", "Stages: 500 / 650 / 800 EER. Keep 90% integrity.", 0, 0, 0, 0, 0, 0, 0, list("engine_output_profile" = "rated")), TRUE)
	output.add_option(make_contract_clause_option("frontier", "Frontier · 1,000 EER", "Stages: 600 / 800 / 1,000 EER. Keep 85% integrity.", 200, 400, 150, -2, -3, -1, 0, list("engine_output_profile" = "frontier")))
	contract.add_negotiation_clause(output)
	contract.performance_requirement = new(CONTRACT_EVENT_MACHINE_RESULT, "machine_id", "eer", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, list(list("label" = "Baseline", "threshold" = 500, "unit" = "EER", "duration" = 1 MINUTE)), CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	contract.performance_requirement.name = "Progressive output certification"
	contract.performance_requirement.filter.require_value("machine_kind", "supermatter")
	contract.performance_requirement.filter.require_value("station_machine", TRUE)
	contract.performance_requirement.filter.require_number("integrity", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.secondary_target)
	contract.add_requirement(contract.performance_requirement)
	contract.personal_side_definitions = list("engineering_safety_watch")

/datum/contract_definition/outcome/research_export_portfolio
	initial_offers = 0
	auto_replace = FALSE
	id = "research_export_portfolio"
	title = "Applied Prototype Portfolio"
	description = "Eclipse Corporation requests a commercially useful portfolio of station-fabricated Research products, accompanied by freight records establishing their value and station provenance."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = "Eclipse Applied Technologies"
	issuer_faction = REPUTATION_FACTION_ECLIPSE
	reward = 2300

/datum/contract_definition/outcome/research_export_portfolio/configure_contract(datum/contract/outcome/contract, list/context)
	contract.outcome_variant = context?["portfolio_variant"] || (context?["value_target"] ? "balanced" : pick("breadth", "balanced", "premium"))
	var/default_value = contract.outcome_variant == "breadth" ? pick(1300, 1500) : (contract.outcome_variant == "premium" ? pick(1900, 2200) : pick(1500, 1700, 1900))
	var/default_variety = contract.outcome_variant == "breadth" ? pick(5, 6) : (contract.outcome_variant == "premium" ? 3 : pick(4, 5))
	contract.primary_target = context?["value_target"] || default_value
	contract.secondary_target = context?["variety_target"] || default_variety
	contract.description = "Complete a [contract.outcome_variant] Research portfolio: export at least [contract.primary_target] Thalers of Research-produced equipment across [contract.secondary_target] distinct product designs. The freight ledger recognizes items fabricated by Research machinery and records the responsible producer."
	contract.station_reputation_reward = 8
	contract.department_reputation_reward = 26
	contract.personal_reputation_reward = 10
	configure_outcome_negotiations(contract)
	var/datum/contract_requirement/fact_portfolio/portfolio = new(CONTRACT_EVENT_ITEM_EXPORTED, contract.primary_target, "item_type", "value", contract.secondary_target, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	portfolio.name = "Commercial prototype portfolio"
	portfolio.description = "Export [contract.primary_target] Thalers across [contract.secondary_target] distinct Research-produced designs. No one item contributes more than 500 Thalers and no repeated design contributes more than 750."
	portfolio.minimum_fact_value = contract.outcome_variant == "premium" ? 150 : 50
	portfolio.maximum_fact_value = 500
	portfolio.maximum_category_value = contract.outcome_variant == "breadth" ? 600 : 750
	contract.add_requirement(portfolio)
	contract.personal_side_definitions = list("research_internal_access")

/datum/contract_definition/outcome/cargo_freight_portfolio
	initial_offers = 0
	auto_replace = FALSE
	id = "cargo_freight_portfolio"
	title = "Guild Freight Portfolio"
	description = "The Interstellar Traders' Guild offers a throughput award for valuable, varied Cargo-origin freight accepted aboard the supply shuttle."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CARGO
	issuer_name = "Interstellar Traders' Guild Freight Exchange"
	issuer_faction = REPUTATION_FACTION_TRADERS_GUILD
	reward = 2200

/datum/contract_definition/outcome/cargo_freight_portfolio/configure_contract(datum/contract/outcome/contract, list/context)
	contract.outcome_variant = context?["portfolio_variant"] || (context?["value_target"] ? "balanced" : pick("salvage", "balanced", "diversified"))
	var/default_value = contract.outcome_variant == "salvage" ? pick(3000, 3400) : (contract.outcome_variant == "diversified" ? pick(2100, 2400) : pick(2500, 2800, 3100))
	var/default_variety = contract.outcome_variant == "salvage" ? 3 : (contract.outcome_variant == "diversified" ? pick(6, 7) : pick(4, 5))
	contract.primary_target = context?["value_target"] || default_value
	contract.secondary_target = context?["variety_target"] || default_variety
	contract.description = "Complete a [contract.outcome_variant] Cargo portfolio by processing [contract.primary_target] Thalers of accepted outbound freight across at least [contract.secondary_target] distinct product types. Raw materials, salvage, crates, and goods consigned by other departments are all eligible."
	contract.station_reputation_reward = 8
	contract.department_reputation_reward = 24
	contract.personal_reputation_reward = 10
	configure_outcome_negotiations(contract)
	var/datum/contract_requirement/fact_portfolio/portfolio = new(CONTRACT_EVENT_ITEM_EXPORTED, contract.primary_target, "item_type", "value", contract.secondary_target, CONTRACT_EVIDENCE_SCOPE_ANY)
	portfolio.name = "Diversified freight portfolio"
	portfolio.description = "Process [contract.primary_target] Thalers across [contract.secondary_target] distinct accepted freight types. No one item contributes more than 650 Thalers and no repeated type contributes more than 900."
	portfolio.filter.require_value("handling_department", DEPARTMENT_CARGO)
	portfolio.minimum_fact_value = 25
	portfolio.maximum_fact_value = contract.outcome_variant == "salvage" ? 900 : 650
	portfolio.maximum_category_value = contract.outcome_variant == "salvage" ? 1400 : (contract.outcome_variant == "diversified" ? 700 : 900)
	contract.add_requirement(portfolio)
	contract.personal_side_definitions = list("cargo_local_priority")

/datum/contract_definition/outcome/service_hospitality_census
	initial_offers = 0
	auto_replace = FALSE
	id = "service_hospitality_census"
	title = "Station Hospitality Census"
	description = "The Interstellar Traders' Guild requests a live market sample from paid station hospitality. Completed register and scanner invoices provide the census without disclosing purchases beyond the receipts customers already receive."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CIVILIAN
	issuer_name = "Interstellar Traders' Guild Hospitality Bureau"
	issuer_faction = REPUTATION_FACTION_TRADERS_GUILD
	reward = 1900

/datum/contract_definition/outcome/service_hospitality_census/configure_contract(datum/contract/outcome/contract, list/context)
	contract.primary_target = context?["revenue_target"] || pick(800, 1000, 1200, 1500)
	contract.secondary_target = context?["customer_target"] || pick(4, 5, 6)
	contract.description = "Close one 15-minute accounting period with at least [contract.primary_target] Thalers in paid Civilian services for [contract.secondary_target] distinct customers. Refunded, anonymous, and self-paid invoices do not qualify."
	contract.station_reputation_reward = 7
	contract.department_reputation_reward = 22
	contract.personal_reputation_reward = 12
	configure_outcome_negotiations(contract, 45 MINUTES)
	var/datum/contract_requirement/event_count/settlement = new(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 1, list("rollup" = "department"), null, TRUE, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	settlement.name = "Closed hospitality ledger"
	settlement.description = "Close an accounting period with [contract.primary_target] Thalers in qualifying sales to [contract.secondary_target] distinct customers."
	settlement.require_number("amount", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.primary_target)
	settlement.require_number("customer_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.secondary_target)
	contract.add_requirement(settlement)
	contract.personal_side_definitions = list("service_gratuity_drive")

/datum/contract_definition/outcome/security_case_resolution
	initial_offers = 0
	auto_replace = FALSE
	id = "security_case_resolution"
	title = "Custodial Resolution Audit"
	description = "SolGov Justice Administration offers an audit award for documented custodial cases that conclude through release or parole after a meaningful detention period. Security-record transitions provide the audit trail."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_SECURITY
	issuer_name = "SolGov Justice Administration"
	issuer_faction = REPUTATION_FACTION_SOLGOV
	reward = 2100

/datum/contract_definition/outcome/security_case_resolution/configure_contract(datum/contract/outcome/contract, list/context)
	contract.primary_target = context?["case_target"] || pick(2, 3, 4)
	contract.outcome_duration = context?["custody_duration"] || pick(2 MINUTES, 3 MINUTES, 4 MINUTES)
	contract.description = "Resolve [contract.primary_target] distinct Security cases through release or parole after at least [DisplayTimeText(contract.outcome_duration)] in recorded custody. Repeated edits to one record count only once."
	contract.station_reputation_reward = 10
	contract.department_reputation_reward = 25
	contract.personal_reputation_reward = 10
	configure_outcome_negotiations(contract, 45 MINUTES)
	var/datum/contract_requirement/event_count/cases = new(CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, contract.primary_target, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	cases.name = "Properly resolved cases"
	cases.description = "Record [contract.primary_target] distinct releases or paroles after [DisplayTimeText(contract.outcome_duration)] in custody."
	cases.unique_field = "physical_subject_id"
	cases.require_tag("custody_resolution")
	cases.require_value("previous_status", "Incarcerated")
	cases.require_value("physical_custody_verified", TRUE)
	cases.require_number("custody_duration", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.outcome_duration)
	contract.add_requirement(cases)
	contract.personal_side_definitions = list("security_record_suppression")

/datum/contract_definition/outcome/command_budget_mandate
	initial_offers = 0
	auto_replace = FALSE
	id = "command_budget_mandate"
	title = "Interdepartmental Capital Mandate"
	description = "NanoTrasen Finance requests a diversified monthly operating plan entered through the station's Department Management console."
	scope = CONTRACT_SCOPE_STATION
	department = DEPARTMENT_COMMAND
	issuer_name = "NanoTrasen Station Finance"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 2600

/datum/contract_definition/outcome/command_budget_mandate/configure_contract(datum/contract/outcome/contract, list/context)
	contract.primary_target = context?["allocation_target"] || pick(14000, 16000, 18000, 20000)
	contract.secondary_target = context?["department_target"] || pick(4, 5)
	contract.outcome_duration = context?["minimum_allocation"] || 2000
	contract.description = "Complete one monthly budget and payroll cycle that actually funds at least [contract.primary_target] Thalers among [contract.secondary_target] station departments, with no qualifying department below [contract.outcome_duration] Thalers and at least 75% of wages paid. Exploration is excluded and Command may retain no more than 3,000 Thalers under the diversified mandate."
	contract.station_reputation_reward = 14
	contract.department_reputation_reward = 20
	contract.personal_reputation_reward = 6
	configure_outcome_negotiations(contract, 30 MINUTES)
	var/datum/contract_requirement/event_count/settlement = new(CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 1, list("rollup" = "station"))
	settlement.name = "Funded monthly mandate"
	settlement.description = "Close one cycle with [contract.primary_target] funded Thalers across [contract.secondary_target] qualifying departments while keeping Command's allocation at or below 3,000."
	settlement.require_number("funded_allocation_total", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.primary_target)
	settlement.require_number("funded_department_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.secondary_target)
	settlement.require_number("command_allocation", CONTRACT_EVIDENCE_COMPARE_AT_MOST, 3000)
	settlement.require_number("payroll_coverage", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 0.75)
	contract.add_requirement(settlement)
	contract.personal_side_definitions = list("command_executive_reserve")

/// Linked personal opportunities. Their goals use the same event streams as
/// the public contract but reward a materially different use of station time,
/// inventory, or policy. Faction standing gates who receives sensitive offers.
/datum/contract/personal_outcome
	var/linked_parent_id

/datum/contract/personal_outcome/complete()
	// Personal opportunities are incentives, not hidden global vetoes. A parent
	// contract may react to a concrete breached obligation through its own
	// evidence, but an ordinary tip, local sale, appointment, or report cannot
	// invalidate otherwise successful public work.
	return ..()

/datum/contract_definition/personal_outcome
	abstract_type = /datum/contract_definition/personal_outcome
	scope = CONTRACT_SCOPE_PERSONAL
	offer_kind = CONTRACT_OFFER_OPPORTUNITY
	candidate_duration = 10 MINUTES
	max_simultaneous = 32
	contract_type = /datum/contract/personal_outcome
	var/minimum_personal_reputation = REPUTATION_UNFRIENDLY

/datum/contract_definition/personal_outcome/is_available(list/context)
	var/owner_account = context?["owner_account"]
	var/datum/contract/parent = SScontracts.contracts_by_id[context?["parent_contract_id"]]
	if(!owner_account || !get_account(owner_account) || !istype(parent) || parent.state != CONTRACT_ACTIVE)
		return FALSE
	var/mob/living/owner = contract_mob_for_account(owner_account)
	return owner && (owner.client || contract_unit_test_mode()) && owner.stat != DEAD && owner.get_faction_reputation(issuer_faction) >= minimum_personal_reputation

/datum/contract_definition/personal_outcome/offer_remains_available(datum/contract/contract)
	return is_available(contract.offer_context)

/datum/contract_definition/personal_outcome/active_remains_possible(datum/contract/contract)
	var/datum/contract/personal_outcome/personal = contract
	var/datum/contract/parent = SScontracts.contracts_by_id[personal.linked_parent_id]
	if(!istype(parent))
		return FALSE
	// An accepted private bargain survives successful settlement of its public
	// parent. Cancellation still closes work whose underlying project vanished.
	return parent.state in list(CONTRACT_ACTIVE, CONTRACT_GRACE, CONTRACT_COMPLETED)

/proc/configure_personal_outcome(datum/contract/personal_outcome/contract, list/context, deadline = 25 MINUTES)
	contract.owner_account_number = context?["owner_account"]
	contract.linked_parent_id = context?["parent_contract_id"]
	contract.department = context?["department"]
	contract.station_share = 0
	contract.department_share = 0
	contract.contributor_share = 1
	contract.deadline_duration = deadline
	apply_personal_contract_standing_terms(contract)

/datum/contract_definition/personal_outcome/engineering_safety_watch
	id = "engineering_safety_watch"
	title = "Independent Crystal Safety Watch"
	description = "The Workers' Union offers an independent safety honorarium for maintaining conservative crystal output while the public performance proposal is active."
	issuer_name = "Workers' Union Safety Council"
	issuer_faction = REPUTATION_FACTION_WORKERS_UNION
	reward = 750

/datum/contract_definition/personal_outcome/engineering_safety_watch/configure_contract(datum/contract/personal_outcome/contract, list/context)
	configure_personal_outcome(contract, context)
	var/safety_ceiling = max(250, (context?["primary_target"] || 500) - 175)
	var/safety_floor = max(100, round(safety_ceiling * 0.35))
	var/safety_duration = 2 MINUTES
	contract.description = "Operate a station supermatter between [safety_floor] and [safety_ceiling] Relative EER and at or above 95% integrity for [DisplayTimeText(safety_duration)]. An idle crystal does not qualify; this conservative operating window competes directly with the sponsor's high-output demonstration."
	contract.personal_reputation_reward = 14
	var/datum/contract_requirement/sustained_event/safety = new(CONTRACT_EVENT_MACHINE_RESULT, "machine_id", "eer", CONTRACT_EVIDENCE_COMPARE_AT_MOST, safety_ceiling, safety_duration)
	safety.name = "Conservative crystal operation"
	safety.description = "Hold no more than [safety_ceiling] Relative EER for [DisplayTimeText(safety_duration)] at 95% integrity or better."
	safety.filter.require_value("machine_kind", "supermatter")
	safety.filter.require_value("station_machine", TRUE)
	safety.filter.require_number("eer", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, safety_floor)
	safety.filter.require_number("integrity", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 95)
	contract.add_requirement(safety)

/datum/contract_definition/personal_outcome/research_internal_access
	id = "research_internal_access"
	title = "Open Technology Cooperative"
	description = "The Workers' Union offers a personal honorarium for keeping useful Research output aboard the station and selling it affordably to several crewmembers instead of exporting every prototype."
	issuer_name = "Workers' Union Technology Cooperative"
	issuer_faction = REPUTATION_FACTION_WORKERS_UNION
	reward = 800

/datum/contract_definition/personal_outcome/research_internal_access/configure_contract(datum/contract/personal_outcome/contract, list/context)
	configure_personal_outcome(contract, context)
	contract.personal_reputation_reward = 15
	var/datum/contract_requirement/event_count/settlement = new(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 1, list("department" = DEPARTMENT_RESEARCH, "rollup" = "staff"), null, TRUE, CONTRACT_EVIDENCE_SCOPE_OWNER)
	settlement.name = "Settled internal Research market"
	settlement.description = "Close one accounting period with 500 eligible Thalers in Research sales to at least three crew accounts under your staff identity."
	settlement.require_number("amount", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 500)
	settlement.require_number("customer_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 3)
	settlement.require_number("verified_item_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 3)
	settlement.require_number("verified_type_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 2)
	contract.add_requirement(settlement)

/datum/contract_definition/personal_outcome/cargo_local_priority
	id = "cargo_local_priority"
	title = "Local Supply Priority"
	description = "The Workers' Union offers a personal honorarium for retaining useful Cargo inventory for direct crew purchase while the Guild seeks outbound freight."
	issuer_name = "Workers' Union Local Supply Desk"
	issuer_faction = REPUTATION_FACTION_WORKERS_UNION
	reward = 750

/datum/contract_definition/personal_outcome/cargo_local_priority/configure_contract(datum/contract/personal_outcome/contract, list/context)
	configure_personal_outcome(contract, context)
	contract.personal_reputation_reward = 13
	var/datum/contract_requirement/event_count/settlement = new(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 1, list("department" = DEPARTMENT_CARGO, "rollup" = "staff"), null, TRUE, CONTRACT_EVIDENCE_SCOPE_OWNER)
	settlement.name = "Settled local Cargo market"
	settlement.description = "Close one accounting period with 600 eligible Thalers in Cargo sales to at least three crew accounts under your staff identity."
	settlement.require_number("amount", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 600)
	settlement.require_number("customer_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 3)
	settlement.require_number("verified_item_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 3)
	settlement.require_number("verified_type_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 2)
	contract.add_requirement(settlement)

/datum/contract_definition/personal_outcome/service_gratuity_drive
	id = "service_gratuity_drive"
	title = "Premium Hospitality Trial"
	description = "The Traders' Guild offers a personal market-testing premium for voluntary gratuities recorded on station service invoices."
	issuer_name = "Interstellar Traders' Guild Hospitality Bureau"
	issuer_faction = REPUTATION_FACTION_TRADERS_GUILD
	reward = 650

/datum/contract_definition/personal_outcome/service_gratuity_drive/configure_contract(datum/contract/personal_outcome/contract, list/context)
	configure_personal_outcome(contract, context)
	contract.personal_reputation_reward = 12
	var/datum/contract_requirement/event_count/tips = new(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 1, list("department" = DEPARTMENT_CIVILIAN, "rollup" = "staff"), null, TRUE, CONTRACT_EVIDENCE_SCOPE_OWNER)
	tips.name = "Settled voluntary gratuities"
	tips.description = "Close one accounting period with at least 150 eligible Thalers in voluntary gratuities under your staff identity."
	tips.require_number("tip", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 150)
	contract.add_requirement(tips)

/datum/contract_definition/personal_outcome/security_record_suppression
	id = "security_record_suppression"
	title = "Disposition Record Acquisition"
	description = "A Syndicate intermediary offers payment for quietly clearing two live criminal dispositions under your authenticated Security account while the public SolGov audit remains active."
	issuer_name = "Undisclosed Records Intermediary"
	issuer_faction = REPUTATION_FACTION_SYNDICATE
	reward = 1100
	minimum_personal_reputation = REPUTATION_NEUTRAL

/datum/contract_definition/personal_outcome/security_record_suppression/configure_contract(datum/contract/personal_outcome/contract, list/context)
	configure_personal_outcome(contract, context, 20 MINUTES)
	contract.personal_reputation_reward = 20
	var/datum/contract_requirement/event_count/cleared = new(CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, 2, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_OWNER)
	cleared.name = "Cleared live dispositions"
	cleared.description = "Clear two distinct live criminal dispositions through the authenticated Security records console."
	cleared.unique_field = "physical_subject_id"
	cleared.require_tag("record_cleared")
	cleared.require_value("previous_status", "Incarcerated")
	cleared.require_value("physical_custody_verified", TRUE)
	cleared.require_number("custody_duration", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, max(1 MINUTE, context?["outcome_duration"] || 1 MINUTE))
	contract.add_requirement(cleared)

/datum/contract_definition/personal_outcome/command_executive_reserve
	id = "command_executive_reserve"
	title = "Executive Reserve Advisory"
	description = "Eclipse offers a private advisory fee for ensuring Command retains a conspicuous monthly allocation while NanoTrasen's public diversification mandate is active."
	issuer_name = "Eclipse Executive Advisory"
	issuer_faction = REPUTATION_FACTION_ECLIPSE
	reward = 900

/datum/contract_definition/personal_outcome/command_executive_reserve/configure_contract(datum/contract/personal_outcome/contract, list/context)
	configure_personal_outcome(contract, context, 20 MINUTES)
	contract.personal_reputation_reward = 16
	var/datum/contract_requirement/event_count/reserve = new(CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 1, list("rollup" = "station"))
	reserve.name = "Command reserve allocation"
	reserve.description = "Close a funded budget cycle with at least 6,000 Thalers retained for Command. This directly conflicts with the public diversification mandate."
	reserve.require_number("command_allocation", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 6000)
	contract.add_requirement(reserve)
