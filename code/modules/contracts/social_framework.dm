/// One reusable participation role on a social contract. Roles describe who
/// must collaborate; proposals bind a stable account to one of these roles.
/datum/contract_stakeholder_role
	var/id
	var/title
	var/description
	var/list/eligible_departments
	var/minimum_approved = 1
	var/maximum_approved = 0

/datum/contract_stakeholder_role/New(_id, _title, _description, list/_eligible_departments, _minimum_approved = 1, _maximum_approved = 0)
	. = ..()
	id = _id
	title = _title
	description = _description
	eligible_departments = _eligible_departments?.Copy() || list()
	minimum_approved = max(0, _minimum_approved)
	maximum_approved = max(0, _maximum_approved)

/datum/contract_stakeholder_role/Destroy()
	eligible_departments = null
	return ..()

/datum/contract_stakeholder_role/proc/account_is_eligible(datum/money_account/account)
	return account && (!length(eligible_departments) || (account.department_id in eligible_departments))

/// A player's IC subcontract proposal. Requested weight is deliberately a
/// bounded relative share, not an unenforceable exact payment promise.
/datum/contract_stakeholder_proposal
	var/account_number
	var/account_name
	var/department
	var/role_id
	var/requested_weight = 1
	var/status = CONTRACT_STAKEHOLDER_PENDING
	var/contribution = 0
	var/created_at

/datum/contract_stakeholder_proposal/New(datum/money_account/account, _role_id, _requested_weight)
	. = ..()
	account_number = account.account_number
	account_name = account.owner_name
	department = account.department_id
	role_id = _role_id
	requested_weight = clamp(round(_requested_weight), 1, 3)
	created_at = world.time

/// Social contracts keep their exceptional target live until an authorized
/// head finalizes the outcome or the deadline does so automatically. All
/// required dimensions must reach the minimum ratio; a high score in one
/// dimension therefore cannot hide a failed safety, variety, or participation
/// dimension.
/datum/contract/social
	var/outcome_grade = CONTRACT_OUTCOME_UNRATED
	var/outcome_score = 0
	var/outcome_finalized = FALSE
	var/minimum_grade_ratio = CONTRACT_GRADE_MINIMUM_RATIO
	var/success_grade_ratio = CONTRACT_GRADE_SUCCESS_RATIO
	var/list/stakeholder_roles
	var/list/stakeholder_proposals
	var/list/personal_side_definitions

/datum/contract/social/New()
	. = ..()
	stakeholder_roles = list()
	stakeholder_proposals = list()

/datum/contract/social/Destroy()
	for(var/role_id in stakeholder_roles)
		qdel(stakeholder_roles[role_id])
	stakeholder_roles = null
	for(var/proposal_key in stakeholder_proposals)
		qdel(stakeholder_proposals[proposal_key])
	stakeholder_proposals = null
	personal_side_definitions = null
	return ..()

/datum/contract/social/on_negotiated_terms_changed()
	..()
	minimum_grade_ratio = negotiated_effect("minimum_grade_ratio", CONTRACT_GRADE_MINIMUM_RATIO)
	success_grade_ratio = negotiated_effect("success_grade_ratio", CONTRACT_GRADE_SUCCESS_RATIO)

/datum/contract/social/on_accepted(mob/living/user, atom/source)
	..()
	if(!length(personal_side_definitions))
		return
	for(var/side_definition_id in personal_side_definitions)
		offer_social_personal_contract(side_definition_id, user)

/datum/contract/social/proc/social_personal_offer_context(side_definition_id)
	var/list/context = list(
		"parent_contract_id" = id,
		"parent_definition_id" = definition_id,
		"department" = department,
	)
	switch(side_definition_id)
		if("emergency_exclusive_contractor")
			context["role_id"] = "repair"
		if("clinical_priority_coordinator")
			context["role_id"] = "clinician"
	return context

/datum/contract/social/proc/offer_social_personal_contract(side_definition_id, mob/living/accepting_user)
	var/datum/contract_definition/personal_outcome/definition = SScontracts.definitions[side_definition_id]
	if(!istype(definition) || state != CONTRACT_ACTIVE)
		return FALSE
	var/list/eligible_players = list()
	var/lowest_live_count
	for(var/mob/living/player in GLOB.player_list)
		if((!player.client && !contract_unit_test_mode()) || player.stat == DEAD || department_for_mob(player) != department)
			continue
		var/datum/money_account/account = contract_account_for_mob(player)
		if(!account)
			continue
		var/list/context = social_personal_offer_context(side_definition_id)
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
	var/list/selected_context = social_personal_offer_context(side_definition_id)
	selected_context["owner_account"] = selected_account.account_number
	selected_context["offer_kind"] = CONTRACT_OFFER_OPPORTUNITY
	var/offer_key = "social-linked:[side_definition_id]:[id]:[selected_account.account_number]"
	SScontracts.queue_offer(side_definition_id, selected_context, "A stakeholder contract created a private counter-offer", offer_key, 80)
	if(selected == accepting_user)
		to_chat(selected, span_notice("A private counter-offer related to [title] is now available on your PDA."))
	return TRUE

/datum/contract/social/proc/add_stakeholder_role(datum/contract_stakeholder_role/role)
	if(!role?.id || stakeholder_roles[role.id])
		return FALSE
	stakeholder_roles[role.id] = role
	return TRUE

/datum/contract/social/proc/proposal_key(account_number, role_id)
	return "[account_number]:[role_id]"

/datum/contract/social/proc/account_can_participate(datum/money_account/account)
	if(!account)
		return FALSE
	for(var/proposal_key in stakeholder_proposals)
		var/datum/contract_stakeholder_proposal/proposal = stakeholder_proposals[proposal_key]
		if(proposal.account_number == account.account_number)
			return TRUE
	if(state != CONTRACT_ACTIVE)
		return FALSE
	for(var/role_id in stakeholder_roles)
		var/datum/contract_stakeholder_role/role = stakeholder_roles[role_id]
		if(role.account_is_eligible(account))
			return TRUE
	return FALSE

/datum/contract/social/proc/propose_stakeholder(datum/money_account/account, role_id, requested_weight = 1)
	if(state != CONTRACT_ACTIVE || !account)
		return FALSE
	var/datum/contract_stakeholder_role/role = stakeholder_roles[role_id]
	if(!role?.account_is_eligible(account))
		return FALSE
	var/key = proposal_key(account.account_number, role_id)
	var/datum/contract_stakeholder_proposal/proposal = stakeholder_proposals[key]
	if(proposal?.status == CONTRACT_STAKEHOLDER_APPROVED)
		return FALSE
	if(proposal)
		qdel(proposal)
	proposal = new(account, role_id, requested_weight)
	stakeholder_proposals[key] = proposal
	audit(CONTRACT_AUDIT_PROGRESS, "[proposal.account_name] proposed [role.title] participation at share weight [proposal.requested_weight].")
	SScontracts?.notify_contract(src, "A new stakeholder proposal was filed for [title].")
	return TRUE

/datum/contract/social/proc/decide_stakeholder(account_number, role_id, approved, actor_name)
	if(state != CONTRACT_ACTIVE)
		return FALSE
	var/key = proposal_key(account_number, role_id)
	var/datum/contract_stakeholder_proposal/proposal = stakeholder_proposals[key]
	var/datum/contract_stakeholder_role/role = stakeholder_roles[role_id]
	if(!proposal || !role || proposal.status != CONTRACT_STAKEHOLDER_PENDING)
		return FALSE
	if(approved && role.maximum_approved > 0 && approved_stakeholder_count(role_id) >= role.maximum_approved)
		return FALSE
	proposal.status = approved ? CONTRACT_STAKEHOLDER_APPROVED : CONTRACT_STAKEHOLDER_REJECTED
	audit(CONTRACT_AUDIT_PROGRESS, "[actor_name || "An authorized representative"] [approved ? "approved" : "rejected"] [proposal.account_name]'s [role.title] proposal.")
	if(approved)
		emit_contract_event(CONTRACT_EVENT_STAKEHOLDER_APPROVED, list(
			"contract_id" = id,
			"actor_account" = proposal.account_number,
			"actor_name" = proposal.account_name,
			"actor_department" = proposal.department,
			"department" = department,
			"role_id" = role.id,
			"requested_weight" = proposal.requested_weight,
			"detail" = "[proposal.account_name] received the [role.title] subcontract at share weight [proposal.requested_weight].",
		), "stakeholder-approved:[id]:[proposal.account_number]:[role.id]")
	reconcile_completion()
	return TRUE

/datum/contract/social/proc/approved_stakeholder_count(role_id)
	. = 0
	for(var/proposal_key in stakeholder_proposals)
		var/datum/contract_stakeholder_proposal/proposal = stakeholder_proposals[proposal_key]
		if(proposal.role_id == role_id && proposal.status == CONTRACT_STAKEHOLDER_APPROVED)
			.++

/datum/contract/social/proc/stakeholders_ready()
	for(var/role_id in stakeholder_roles)
		var/datum/contract_stakeholder_role/role = stakeholder_roles[role_id]
		if(approved_stakeholder_count(role_id) < role.minimum_approved)
			return FALSE
	return TRUE

/datum/contract/social/proc/current_outcome_ratio()
	var/ratio = 1
	var/has_required = FALSE
	for(var/datum/contract_requirement/requirement in requirements)
		if(!requirement.required)
			continue
		has_required = TRUE
		ratio = min(ratio, requirement.grade_progress())
	return has_required ? clamp(ratio, 0, 1) : 0

/datum/contract/social/proc/grade_for_ratio(ratio)
	if(ratio >= CONTRACT_GRADE_EXCEPTIONAL_RATIO)
		return CONTRACT_OUTCOME_EXCEPTIONAL
	if(ratio >= success_grade_ratio)
		return CONTRACT_OUTCOME_SUCCESSFUL
	if(ratio >= minimum_grade_ratio)
		return CONTRACT_OUTCOME_MINIMUM
	return CONTRACT_OUTCOME_UNRATED

/datum/contract/social/proc/reward_multiplier_for_grade(grade)
	switch(grade)
		if(CONTRACT_OUTCOME_MINIMUM)
			return CONTRACT_GRADE_MINIMUM_REWARD
		if(CONTRACT_OUTCOME_SUCCESSFUL)
			return CONTRACT_GRADE_SUCCESS_REWARD
		if(CONTRACT_OUTCOME_EXCEPTIONAL)
			return CONTRACT_GRADE_EXCEPTIONAL_REWARD
	return 0

/datum/contract/social/proc/can_finalize_outcome()
	return !outcome_finalized && (state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)) && stakeholders_ready() && current_outcome_ratio() >= minimum_grade_ratio

/datum/contract/social/reconcile_completion()
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)))
		return FALSE
	if(outcome_finalized)
		return complete()
	outcome_score = round(current_outcome_ratio() * 100, 0.1)
	return FALSE

/datum/contract/social/proc/finalize_graded_outcome(actor_name = "Automatic deadline settlement")
	if(!can_finalize_outcome())
		return FALSE
	var/ratio = current_outcome_ratio()
	var/grade = grade_for_ratio(ratio)
	var/multiplier = reward_multiplier_for_grade(grade)
	if(multiplier <= 0)
		return FALSE
	outcome_finalized = TRUE
	outcome_grade = grade
	outcome_score = round(ratio * 100, 0.1)
	base_reward = round(base_reward * multiplier)
	negotiated_station_bonus = round(negotiated_station_bonus * multiplier)
	negotiated_department_bonus = round(negotiated_department_bonus * multiplier)
	negotiated_staff_bonus = round(negotiated_staff_bonus * multiplier)
	reward = base_reward + negotiated_station_bonus + negotiated_department_bonus + negotiated_staff_bonus
	station_reputation_reward = round(station_reputation_reward * multiplier)
	department_reputation_reward = round(department_reputation_reward * multiplier)
	personal_reputation_reward = round(personal_reputation_reward * multiplier)
	audit(CONTRACT_AUDIT_COMPLETED, "[actor_name] finalized a [grade] outcome at [outcome_score]% of the exceptional specification.")
	return complete()

/datum/contract/social/check_deadline()
	deadline_timer = null
	if(state == CONTRACT_ACTIVE && deadline && world.time >= deadline)
		if(can_finalize_outcome())
			finalize_graded_outcome()
		else
			fail("The delivery window closed before the minimum graded outcome and required stakeholder approvals were reached.")

/datum/contract/social/record_contribution(account_number, amount, detail, contributor_name)
	. = ..()
	if(!. || !account_number)
		return
	for(var/proposal_key in stakeholder_proposals)
		var/datum/contract_stakeholder_proposal/proposal = stakeholder_proposals[proposal_key]
		if(proposal.account_number == account_number && proposal.status == CONTRACT_STAKEHOLDER_APPROVED)
			proposal.contribution += amount

/datum/contract/social/reward_recipient_weights()
	var/list/weights = ..()
	for(var/proposal_key in stakeholder_proposals)
		var/datum/contract_stakeholder_proposal/proposal = stakeholder_proposals[proposal_key]
		if(proposal.status != CONTRACT_STAKEHOLDER_APPROVED)
			continue
		var/key = "[proposal.account_number]"
		var/evidence_weight = max(1, weights[key] || proposal.contribution)
		weights[key] = evidence_weight * proposal.requested_weight
	return weights

/datum/contract/social/ui_details(mob/living/user)
	var/datum/money_account/viewer_account = contract_account_for_mob(user)
	var/projected_grade = outcome_finalized ? outcome_grade : grade_for_ratio(current_outcome_ratio())
	var/projected_multiplier = outcome_finalized ? 1 : reward_multiplier_for_grade(projected_grade)
	var/list/role_rows = list()
	for(var/role_id in stakeholder_roles)
		var/datum/contract_stakeholder_role/role = stakeholder_roles[role_id]
		var/list/proposal_rows = list()
		for(var/proposal_key in stakeholder_proposals)
			var/datum/contract_stakeholder_proposal/proposal = stakeholder_proposals[proposal_key]
			if(proposal.role_id != role_id)
				continue
			proposal_rows.Add(list(list(
				"account" = proposal.account_number,
				"name" = proposal.account_name,
				"department" = proposal.department,
				"weight" = proposal.requested_weight,
				"status" = proposal.status,
				"contribution" = round(proposal.contribution, 0.1),
			)))
		role_rows.Add(list(list(
			"id" = role.id,
			"title" = role.title,
			"description" = role.description,
			"departments" = role.eligible_departments.Copy(),
			"minimum" = role.minimum_approved,
			"maximum" = role.maximum_approved,
			"approved" = approved_stakeholder_count(role.id),
			"viewer_eligible" = role.account_is_eligible(viewer_account),
			"proposals" = proposal_rows,
		)))
	return list(
		"kind" = "social_outcome",
		"grade" = outcome_grade,
		"projected_grade" = projected_grade,
		"projected_reward" = round(reward * projected_multiplier),
		"score" = round(current_outcome_ratio() * 100, 0.1),
		"can_finalize" = can_finalize_outcome(),
		"stakeholders_ready" = stakeholders_ready(),
		"roles" = role_rows,
	)

/datum/contract_definition/social
	abstract_type = /datum/contract_definition/social
	initial_offers = 1
	offer_kind = CONTRACT_OFFER_STANDING
	auto_replace = TRUE
	max_simultaneous = 2
	contract_type = /datum/contract/social

/datum/contract_definition/social/configure_contract(datum/contract/social/contract, list/context)
	configure_social_contract(contract, context)

/proc/configure_social_contract(datum/contract/social/contract, list/context, deadline = 45 MINUTES)
	contract.station_reputation_reward = 10
	contract.department_reputation_reward = 24
	contract.personal_reputation_reward = 12
	configure_outcome_negotiations(contract, deadline)
	contract.station_share = 0.2
	contract.department_share = 0.55
	contract.contributor_share = 0.25

/proc/contract_atom_is_station_infrastructure(atom/source)
	return source?.uses_integrity && source.z && (source.z in using_map.station_levels) && (isstructure(source) || ismachinery(source))

/proc/contract_report_station_damage(atom/source, amount)
	if(!SScontracts || !contract_atom_is_station_infrastructure(source) || !isnum(amount) || amount < 25)
		return
	var/revision = SScontracts.next_infrastructure_revision(source)
	var/current_damage = max(0, source.max_integrity - source.get_integrity())
	var/turf/source_turf = get_turf(source)
	var/asset_label = "[source.name] in [get_area(source)]"
	if(source_turf)
		asset_label += " ([source_turf.x], [source_turf.y], [source_turf.z])"
	emit_contract_event(CONTRACT_EVENT_INFRASTRUCTURE_DAMAGED, list(
		"department" = DEPARTMENT_ENGINEERING,
		"atom_id" = REF(source),
		"asset_name" = source.name,
		"asset_label" = asset_label,
		"atom_type" = source.type,
		"fact_id" = "infrastructure-damage:[REF(source)]",
		"fact_revision" = revision,
		"fact_active" = current_damage > 0,
		"metrics" = list(
			"damage_amount" = current_damage,
			"integrity" = source.get_integrity(),
			"maximum_integrity" = source.max_integrity,
		),
		"detail" = "[source] sustained [round(amount, 0.1)] integrity damage in [get_area(source)].",
	), "infrastructure-damage:[REF(source)]:[revision]", source)

/proc/contract_report_station_repair(atom/source, amount)
	if(!SScontracts || !contract_atom_is_station_infrastructure(source) || !isnum(amount) || amount <= 0)
		return
	var/turf/source_turf = get_turf(source)
	var/asset_label = "[source.name] in [get_area(source)]"
	if(source_turf)
		asset_label += " ([source_turf.x], [source_turf.y], [source_turf.z])"
	emit_contract_event(CONTRACT_EVENT_INFRASTRUCTURE_REPAIRED, list(
		"department" = DEPARTMENT_ENGINEERING,
		"atom_id" = REF(source),
		"asset_name" = source.name,
		"asset_label" = asset_label,
		"atom_type" = source.type,
		"repair_amount" = amount,
		"integrity" = source.get_integrity(),
		"maximum_integrity" = source.max_integrity,
		"detail" = "Restored [round(amount, 0.1)] integrity to [source] in [get_area(source)].",
	), "infrastructure-repair:[REF(source)]:[world.time]:[source.get_integrity()]", source)
	var/revision = SScontracts.next_infrastructure_revision(source)
	var/current_damage = max(0, source.max_integrity - source.get_integrity())
	emit_contract_event(CONTRACT_EVENT_INFRASTRUCTURE_DAMAGED, list(
		"department" = DEPARTMENT_ENGINEERING,
		"atom_id" = REF(source),
		"asset_name" = source.name,
		"asset_label" = asset_label,
		"atom_type" = source.type,
		"fact_id" = "infrastructure-damage:[REF(source)]",
		"fact_revision" = revision,
		"fact_active" = current_damage > 0,
		"metrics" = list(
			"damage_amount" = current_damage,
			"integrity" = source.get_integrity(),
			"maximum_integrity" = source.max_integrity,
		),
		"detail" = "[source] damage state was revised after repairs in [get_area(source)].",
	), "infrastructure-damage:[REF(source)]:[revision]", source)

/// Grade progress is deliberately virtual so portfolios can incorporate both
/// their value and breadth dimensions without teaching the social contract
/// about requirement subtypes.
/datum/contract_requirement/proc/grade_progress()
	return target > 0 ? clamp(progress / target, 0, 1) : 0

/datum/contract_requirement/fact_portfolio/grade_progress()
	var/value_ratio = ..()
	if(distinct_category_target <= 0)
		return value_ratio
	return min(value_ratio, clamp(portfolio_category_count() / distinct_category_target, 0, 1))
