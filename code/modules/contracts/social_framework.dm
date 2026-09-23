/// One reusable participation role on a social contract. Roles describe who
/// must collaborate; proposals bind a stable account to one of these roles.
/datum/contract_stakeholder_role
	var/id
	var/title
	var/description
	var/list/eligible_departments
	var/minimum_approved = 1
	var/maximum_approved = 0
	/// Set when the contract is accepted. Authored slots beyond this remain optional.
	var/required_minimum = -1
	/// An approval is only qualified after this much attributable contract work.
	var/minimum_contribution = 1

/datum/contract_stakeholder_role/New(_id, _title, _description, list/_eligible_departments, _minimum_approved = 1, _maximum_approved = 0, _minimum_contribution = 1)
	. = ..()
	id = _id
	title = _title
	description = _description
	eligible_departments = _eligible_departments?.Copy() || list()
	minimum_approved = max(0, _minimum_approved)
	maximum_approved = max(0, _maximum_approved)
	minimum_contribution = max(0, _minimum_contribution)

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
	var/approved_weight = 0
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
	var/stakeholder_requirements_locked = FALSE
	/// Highest cumulative grade award paid while the project was underway.
	/// This survives reversible progress and makes milestones exactly-once.
	var/settled_project_multiplier = 0

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
	lock_stakeholder_requirements()
	. = ..()

	if(!length(personal_side_definitions))
		return
	for(var/side_definition_id in personal_side_definitions)
		offer_social_personal_contract(side_definition_id, user)

/datum/contract/social/proc/requirement_completion_floor(datum/contract_requirement/requirement)
	var/list/floors = negotiated_effect("requirement_floors", null)
	if(!length(floors) || isnull(floors[requirement.name]))
		return 1
	return clamp(floors[requirement.name], 0.25, 1)

/datum/contract/social/proc/social_personal_offer_context(side_definition_id)
	return list(
		"parent_contract_id" = id,
		"parent_definition_id" = definition_id,
		"department" = department,
	)

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

/// Returns each active crew account once. Unit tests may supply a synthetic
/// account list to exercise the planner without manufacturing clients.
/datum/contract/social/proc/stakeholder_population_accounts(list/supplied_accounts)
	var/list/accounts = list()
	var/list/seen = list()
	if(!isnull(supplied_accounts))
		for(var/datum/money_account/account in supplied_accounts)
			if(account.account_number && !seen["[account.account_number]"])
				seen["[account.account_number]"] = TRUE
				accounts += account
		return accounts
	for(var/mob/living/player in GLOB.player_list)
		if(!player.client || player.stat == DEAD)
			continue
		var/datum/money_account/account = contract_account_for_mob(player)
		if(!account?.account_number || seen["[account.account_number]"])
			continue
		seen["[account.account_number]"] = TRUE
		accounts += account
	return accounts

/// Produces a feasible slate without assigning one person to multiple roles.
/// Slots are allocated in rounds so scarce populations retain breadth instead
/// of filling every authored slot in the first role.
/datum/contract/social/proc/stakeholder_minimum_plan(list/supplied_accounts)
	var/list/accounts = stakeholder_population_accounts(supplied_accounts)
	var/list/plan = list()
	var/list/assigned_accounts = list()
	var/list/role_order = list()
	var/list/eligible_counts = list()
	var/highest_minimum = 0
	for(var/role_id in stakeholder_roles)
		var/datum/contract_stakeholder_role/role = stakeholder_roles[role_id]
		plan[role_id] = 0
		var/eligible_count = 0
		for(var/datum/money_account/account in accounts)
			if(role.account_is_eligible(account))
				eligible_count++
		eligible_counts[role_id] = eligible_count
		var/inserted = FALSE
		for(var/order_index in 1 to length(role_order))
			if(eligible_count < eligible_counts[role_order[order_index]])
				role_order.Insert(order_index, role_id)
				inserted = TRUE
				break
		if(!inserted)
			role_order += role_id
		var/authored_required = role.maximum_approved > 0 ? min(role.minimum_approved, role.maximum_approved) : role.minimum_approved
		highest_minimum = max(highest_minimum, authored_required)
	for(var/slot_round in 1 to highest_minimum)
		for(var/role_id in role_order)
			var/datum/contract_stakeholder_role/role = stakeholder_roles[role_id]
			var/authored_required = role.maximum_approved > 0 ? min(role.minimum_approved, role.maximum_approved) : role.minimum_approved
			if(authored_required < slot_round)
				continue
			for(var/datum/money_account/account in accounts)
				var/account_key = "[account.account_number]"
				if(assigned_accounts[account_key] || !role.account_is_eligible(account))
					continue
				assigned_accounts[account_key] = TRUE
				plan[role_id] = plan[role_id] + 1
				break
	return plan

/datum/contract/social/proc/lock_stakeholder_requirements(list/supplied_accounts)
	if(stakeholder_requirements_locked)
		return
	var/list/plan = stakeholder_minimum_plan(supplied_accounts)
	for(var/role_id in stakeholder_roles)
		var/datum/contract_stakeholder_role/role = stakeholder_roles[role_id]
		role.required_minimum = plan[role_id] || 0
		audit(CONTRACT_AUDIT_ACCEPTED, "[role.title] requires [role.required_minimum] qualified participant[role.required_minimum == 1 ? "" : "s"]; [max(0, role.minimum_approved - role.required_minimum)] authored slot[role.minimum_approved - role.required_minimum == 1 ? "" : "s"] became optional for the available crew.")
	stakeholder_requirements_locked = TRUE

/datum/contract/social/proc/account_has_stakeholder_role(account_number, except_role_id)
	for(var/key in stakeholder_proposals)
		var/datum/contract_stakeholder_proposal/proposal = stakeholder_proposals[key]
		if(proposal.account_number != account_number || proposal.role_id == except_role_id)
			continue
		if(proposal.status in list(CONTRACT_STAKEHOLDER_PENDING, CONTRACT_STAKEHOLDER_COUNTERED, CONTRACT_STAKEHOLDER_APPROVED))
			return TRUE
	return FALSE

/datum/contract/social/proc/stakeholder_is_online(account_number)
	var/mob/living/player = find_mob_by_account(account_number)
	return !!(player?.client && player.stat != DEAD)

/datum/contract/social/proc/proposal_key(account_number, role_id)
	return "[account_number]:[role_id]"

/datum/contract/social/proc/account_can_participate(datum/money_account/account)
	if(!account)
		return FALSE
	for(var/proposal_key in stakeholder_proposals)
		var/datum/contract_stakeholder_proposal/proposal = stakeholder_proposals[proposal_key]
		if(proposal.account_number == account.account_number)
			return TRUE
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)))
		return FALSE
	for(var/role_id in stakeholder_roles)
		var/datum/contract_stakeholder_role/role = stakeholder_roles[role_id]
		if(role.account_is_eligible(account))
			return TRUE
	return FALSE

/datum/contract/social/proc/propose_stakeholder(datum/money_account/account, role_id, requested_weight = 1)
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)) || !account)
		return FALSE
	var/datum/contract_stakeholder_role/role = stakeholder_roles[role_id]
	if(!role?.account_is_eligible(account))
		return FALSE
	if(account_has_stakeholder_role(account.account_number, role_id))
		return FALSE
	if(role.maximum_approved > 0 && approved_stakeholder_count(role_id) >= role.maximum_approved)
		return FALSE
	var/key = proposal_key(account.account_number, role_id)
	var/datum/contract_stakeholder_proposal/proposal = stakeholder_proposals[key]
	if(proposal?.status == CONTRACT_STAKEHOLDER_APPROVED)
		return FALSE
	if(!proposal)
		proposal = new(account, role_id, 1)
	proposal.status = CONTRACT_STAKEHOLDER_APPROVED
	proposal.approved_weight = 1
	proposal.contribution = max(proposal.contribution, contributions["[proposal.account_number]"] || 0)
	stakeholder_proposals[key] = proposal
	audit(CONTRACT_AUDIT_PROGRESS, "[proposal.account_name] joined [role.title].")
	emit_contract_event(CONTRACT_EVENT_STAKEHOLDER_APPROVED, list(
		"contract_id" = id,
		"actor_account" = proposal.account_number,
		"actor_name" = proposal.account_name,
		"actor_department" = proposal.department,
		"department" = department,
		"role_id" = role.id,
		"requested_weight" = 1,
		"detail" = "[proposal.account_name] joined [role.title].",
	), "stakeholder-joined:[id]:[proposal.account_number]:[role.id]")
	SScontracts?.notify_contract(src, "[proposal.account_name] joined [role.title] for [title].")
	reconcile_completion()
	return TRUE

/datum/contract/social/proc/withdraw_stakeholder(datum/money_account/account, role_id)
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)) || !account)
		return FALSE
	var/key = proposal_key(account.account_number, role_id)
	var/datum/contract_stakeholder_proposal/proposal = stakeholder_proposals[key]
	if(!proposal || proposal.status != CONTRACT_STAKEHOLDER_APPROVED)
		return FALSE
	var/datum/contract_stakeholder_role/role = stakeholder_roles[role_id]
	proposal.status = CONTRACT_STAKEHOLDER_WITHDRAWN
	proposal.approved_weight = 0
	audit(CONTRACT_AUDIT_PROGRESS, "[proposal.account_name] withdrew from [role?.title || "a stakeholder role"].")
	reconcile_completion()
	return TRUE

/datum/contract/social/proc/approved_stakeholder_count(role_id)
	. = 0
	for(var/proposal_key in stakeholder_proposals)
		var/datum/contract_stakeholder_proposal/proposal = stakeholder_proposals[proposal_key]
		if(proposal.role_id == role_id && proposal.status == CONTRACT_STAKEHOLDER_APPROVED)
			.++

/datum/contract/social/proc/qualified_stakeholder_count(role_id)
	. = 0
	var/datum/contract_stakeholder_role/role = stakeholder_roles[role_id]
	if(!role)
		return
	for(var/key in stakeholder_proposals)
		var/datum/contract_stakeholder_proposal/proposal = stakeholder_proposals[key]
		if(proposal.role_id == role_id && proposal.status == CONTRACT_STAKEHOLDER_APPROVED && proposal.contribution >= role.minimum_contribution)
			.++

/datum/contract/social/proc/stakeholders_ready()
	for(var/role_id in stakeholder_roles)
		var/datum/contract_stakeholder_role/role = stakeholder_roles[role_id]
		var/required = role.required_minimum >= 0 ? role.required_minimum : role.minimum_approved
		if(qualified_stakeholder_count(role_id) < required)
			return FALSE
	return TRUE

/datum/contract/social/proc/current_outcome_ratio()
	var/ratio = 1
	var/has_required = FALSE
	for(var/datum/contract_requirement/requirement in requirements)
		if(!requirement.required)
			continue
		has_required = TRUE
		var/completion_floor = requirement_completion_floor(requirement)
		ratio = min(ratio, clamp(requirement.grade_progress() / completion_floor, 0, 1))
	return has_required ? clamp(ratio, 0, 1) : 0

/// Pay useful work as it reaches the minimum, full, and exceptional project
/// specifications. Because payout_to_fraction() uses a cumulative target,
/// revisions that reopen a requirement never duplicate a tranche.
/datum/contract/social/proc/settle_reached_project_milestones()
	if(!stakeholders_ready() || !(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)))
		return FALSE
	var/ratio = current_outcome_ratio()
	var/new_multiplier = 0
	var/label
	if(ratio >= CONTRACT_GRADE_EXCEPTIONAL_RATIO)
		new_multiplier = CONTRACT_GRADE_EXCEPTIONAL_REWARD
		label = "Exceptional project milestone"
	else if(ratio >= success_grade_ratio)
		new_multiplier = CONTRACT_GRADE_SUCCESS_REWARD
		label = "Full project milestone"
	else if(ratio >= minimum_grade_ratio)
		new_multiplier = CONTRACT_GRADE_MINIMUM_REWARD
		label = "Viable project milestone"
	if(new_multiplier <= settled_project_multiplier)
		return FALSE
	if(!payout_to_fraction(new_multiplier, label))
		audit(CONTRACT_AUDIT_PAYMENT, "[label] is verified, but its payment is waiting on an unavailable recipient account.")
		return FALSE
	settled_project_multiplier = new_multiplier
	audit(CONTRACT_AUDIT_PROGRESS, "[label] reached; earned payment is retained if later conditions change.")
	return TRUE

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
	settle_reached_project_milestones()
	if(outcome_finalized)
		return complete()
	outcome_score = round(current_outcome_ratio() * 100, 0.1)
	return FALSE

/datum/contract/social/proc/finalize_graded_outcome(actor_name = "Automatic deadline settlement")
	if(!can_finalize_outcome())
		return FALSE
	var/ratio = current_outcome_ratio()
	var/grade = grade_for_ratio(ratio)
	var/multiplier = max(reward_multiplier_for_grade(grade), settled_project_multiplier)
	if(settled_project_multiplier >= CONTRACT_GRADE_EXCEPTIONAL_REWARD)
		grade = CONTRACT_OUTCOME_EXCEPTIONAL
	else if(settled_project_multiplier >= CONTRACT_GRADE_SUCCESS_REWARD)
		grade = CONTRACT_OUTCOME_SUCCESSFUL
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
	for(var/faction_id in secondary_faction_reputation_rewards)
		secondary_faction_reputation_rewards[faction_id] = round(secondary_faction_reputation_rewards[faction_id] * multiplier)
	audit(CONTRACT_AUDIT_COMPLETED, "[actor_name] finalized a [grade] outcome at [outcome_score]% of the exceptional specification.")
	return complete()

/datum/contract/social/check_deadline()
	deadline_timer = null
	if(state == CONTRACT_ACTIVE && deadline && world.time >= deadline)
		if(can_finalize_outcome())
			finalize_graded_outcome()
		else if(deadline_grace_duration > 0)
			enter_grace()
		else
			fail("The delivery window closed before the minimum graded outcome and required stakeholder participation were reached.")
	else if(state == CONTRACT_GRACE && grace_until && world.time >= grace_until)
		if(can_finalize_outcome())
			finalize_graded_outcome()
		else
			fail("The evidence grace period closed before the minimum graded outcome and required stakeholder participation were reached.")

/datum/contract/social/record_contribution(account_number, amount, detail, contributor_name)
	. = ..()
	if(!. || !account_number)
		return
	for(var/proposal_key in stakeholder_proposals)
		var/datum/contract_stakeholder_proposal/proposal = stakeholder_proposals[proposal_key]
		if(proposal.account_number == account_number && proposal.status == CONTRACT_STAKEHOLDER_APPROVED)
			proposal.contribution += amount
	reconcile_completion()

/datum/contract/social/reward_recipient_weights()
	var/list/weights = ..()
	for(var/proposal_key in stakeholder_proposals)
		var/datum/contract_stakeholder_proposal/proposal = stakeholder_proposals[proposal_key]
		if(proposal.status != CONTRACT_STAKEHOLDER_APPROVED)
			continue
		var/key = "[proposal.account_number]"
		var/evidence_weight = weights[key] || proposal.contribution
		if(evidence_weight > 0)
			weights[key] = evidence_weight * max(1, proposal.approved_weight)
	return weights

/datum/contract/social/ui_details(mob/living/user)
	var/datum/money_account/viewer_account = contract_account_for_mob(user)
	var/current_ratio = current_outcome_ratio()
	var/projected_grade = outcome_finalized ? outcome_grade : grade_for_ratio(current_ratio)
	var/projected_multiplier = outcome_finalized ? 1 : reward_multiplier_for_grade(projected_grade)
	var/stage_reward_basis = reward
	if(outcome_finalized)
		var/final_multiplier = reward_multiplier_for_grade(outcome_grade)
		if(final_multiplier > 0)
			stage_reward_basis = round(reward / final_multiplier)
	var/list/outcome_stages = list(
		list("label" = "Viable work", "target" = round(minimum_grade_ratio * 100), "reward" = round(stage_reward_basis * CONTRACT_GRADE_MINIMUM_REWARD), "reached" = current_ratio >= minimum_grade_ratio, "earned" = settled_project_multiplier >= CONTRACT_GRADE_MINIMUM_REWARD),
		list("label" = "Full commission", "target" = round(success_grade_ratio * 100), "reward" = round(stage_reward_basis * CONTRACT_GRADE_SUCCESS_REWARD), "reached" = current_ratio >= success_grade_ratio, "earned" = settled_project_multiplier >= CONTRACT_GRADE_SUCCESS_REWARD),
		list("label" = "Exceptional", "target" = round(CONTRACT_GRADE_EXCEPTIONAL_RATIO * 100), "reward" = round(stage_reward_basis * CONTRACT_GRADE_EXCEPTIONAL_REWARD), "reached" = current_ratio >= CONTRACT_GRADE_EXCEPTIONAL_RATIO, "earned" = settled_project_multiplier >= CONTRACT_GRADE_EXCEPTIONAL_REWARD),
	)
	var/list/preview_plan = stakeholder_requirements_locked ? null : stakeholder_minimum_plan()
	var/list/role_rows = list()
	var/required_total = 0
	var/qualified_total = 0
	var/list/missing_roles = list()
	for(var/role_id in stakeholder_roles)
		var/datum/contract_stakeholder_role/role = stakeholder_roles[role_id]
		var/required = role.required_minimum >= 0 ? role.required_minimum : (preview_plan[role_id] || 0)
		var/qualified = qualified_stakeholder_count(role.id)
		required_total += required
		qualified_total += min(required, qualified)
		if(qualified < required)
			missing_roles += "[role.title] [qualified]/[required]"
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
				"approved_weight" = proposal.approved_weight,
				"status" = proposal.status,
				"contribution" = round(proposal.contribution, 0.1),
				"qualified" = proposal.status == CONTRACT_STAKEHOLDER_APPROVED && proposal.contribution >= role.minimum_contribution,
				"online" = stakeholder_is_online(proposal.account_number),
			)))
		role_rows.Add(list(list(
			"id" = role.id,
			"title" = role.title,
			"description" = role.description,
			"departments" = role.eligible_departments.Copy(),
			"minimum" = required,
			"authored_minimum" = role.minimum_approved,
			"maximum" = role.maximum_approved,
			"approved" = approved_stakeholder_count(role.id),
			"qualified" = qualified,
			"minimum_contribution" = role.minimum_contribution,
			"viewer_eligible" = role.account_is_eligible(viewer_account),
			"viewer_has_other_role" = viewer_account ? account_has_stakeholder_role(viewer_account.account_number, role.id) : FALSE,
			"proposals" = proposal_rows,
		)))
	var/stakeholder_summary = "No required stakeholder slots at current staffing"
	if(required_total)
		stakeholder_summary = "[qualified_total]/[required_total] qualified"
		if(length(missing_roles))
			stakeholder_summary += " — missing [jointext(missing_roles, ", ")]"
	return list(
		"kind" = "social_outcome",
		"grade" = outcome_grade,
		"projected_grade" = projected_grade,
		"projected_reward" = round(reward * projected_multiplier),
		"earned_reward" = paid_reward,
		"score" = round(current_ratio * 100, 0.1),
		"outcome_stages" = outcome_stages,
		"minimum_percent" = round(minimum_grade_ratio * 100),
		"success_percent" = round(success_grade_ratio * 100),
		"exceptional_percent" = round(CONTRACT_GRADE_EXCEPTIONAL_RATIO * 100),
		"can_finalize" = can_finalize_outcome(),
		"stakeholders_ready" = stakeholders_ready(),
		"stakeholder_required" = required_total,
		"stakeholder_qualified" = qualified_total,
		"stakeholder_summary" = stakeholder_summary,
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

/datum/contract_definition/social/finalize_contract_authoring(datum/contract/social/contract, list/context)
	..()
	// Definitions add their own clause when the choice changes the work,
	// ownership, disclosure, liability, or delivery conditions. Reordering
	// generic progress counters is not a negotiation.

/proc/configure_social_contract(datum/contract/social/contract, list/context, deadline = 45 MINUTES)
	contract.station_reputation_reward = 10
	contract.department_reputation_reward = 24
	contract.personal_reputation_reward = 12
	configure_outcome_negotiations(contract, deadline, FALSE)
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
