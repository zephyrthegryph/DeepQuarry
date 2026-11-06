/// Broad, event-driven contracts for ordinary station work. These definitions
/// deliberately consume events emitted by the authoritative gameplay systems;
/// they do not scan the world or create contract-only machines and tokens.

/datum/contract/outcome
	var/primary_target = 0
	var/secondary_target = 0
	var/outcome_duration = 0
	/// Per-department funding floor for budget mandates (Thalers), kept apart
	/// from outcome_duration so a money threshold is never read as a time.
	var/minimum_allocation = 0
	var/outcome_variant = "standard"
	var/list/personal_side_definitions

/datum/contract/outcome/on_accepted(mob/living/user, atom/source)
	. = ..()
	offer_linked_personal_contracts(user)

/datum/contract/outcome/proc/personal_offer_context(definition_id)
	return list(
		"parent_contract_id" = id,
		"parent_definition_id" = src.definition_id,
		"department" = department,
		"primary_target" = primary_target,
		"secondary_target" = secondary_target,
		"outcome_duration" = outcome_duration,
		"minimum_allocation" = minimum_allocation,
		"outcome_variant" = outcome_variant,
	)

/datum/contract/outcome/proc/offer_linked_personal_contracts(mob/living/accepting_user)
	if(!length(personal_side_definitions))
		return
	for(var/side_definition_id in personal_side_definitions)
		offer_linked_personal_contract(side_definition_id, accepting_user)

/datum/contract/outcome/proc/offer_linked_personal_contract(side_definition_id, mob/living/accepting_user, excluded_account = 0)
	var/datum/contract_definition/personal_outcome/definition = contracts_definitions()[side_definition_id]
	if(!istype(definition) || !(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)))
		return FALSE
	var/list/eligible_players = list()
	var/lowest_live_count
	for(var/mob/living/player in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
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
	for(var/datum/contract/contract in contracts_offered_contracts() + contracts_active_contracts() + contracts_grace_contracts())
		if(contract.scope == CONTRACT_SCOPE_PERSONAL && contract.owner_account_number == account_number)
			count++
	return count

/proc/contract_mob_for_account(account_number) as /mob/living
	for(var/mob/living/player in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
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
		percent = 5
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
	contract.standing_score = num_or_null(standing)
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

/datum/contract/outcome/engine_performance
	var/datum/contract_requirement/staged_sustained_event/performance_requirement
	/// Synthetic tests may shorten the timers without weakening live terms.
	var/stage_duration_override = 0

CAPABILITIES(/datum/contract/outcome/engine_performance)
	ref_one(nameof(performance_requirement), /datum/contract_requirement/staged_sustained_event)

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

/proc/configure_personal_outcome(datum/contract/personal_outcome/contract, list/context, deadline = 25 MINUTES)
	contract.owner_account_number = context?["owner_account"]
	contract.linked_parent_id = context?["parent_contract_id"]
	contract.department = context?["department"]
	contract.station_share = 0
	contract.department_share = 0
	contract.contributor_share = 1
	contract.deadline_duration = deadline
	apply_personal_contract_standing_terms(contract)
