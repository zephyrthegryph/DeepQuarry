/datum/contract_audit_entry
	var/time
	var/category
	var/detail

/datum/contract_audit_entry/New(_category, _detail)
	. = ..()
	time = world.time
	category = _category
	detail = _detail

/proc/contract_unit_test_mode()
	#ifdef CITESTING
	return TRUE
	#else
	return FALSE
	#endif

/// One selectable term within a generic contract negotiation clause.
/datum/contract_clause_option
	var/id
	var/title
	var/description
	var/station_reward_delta = 0
	var/department_reward_delta = 0
	var/staff_reward_delta = 0
	var/station_reputation_delta = 0
	var/department_reputation_delta = 0
	var/staff_reputation_delta = 0
	var/deadline_delta = 0
	/// Generic gameplay semantics selected by this option. Contract subtypes
	/// consume named values without coupling the negotiation engine to content.
	var/list/effects

/datum/contract_clause_option/New(_id, _title, _description)
	. = ..()
	id = _id
	title = _title
	description = _description
	effects = list()

/datum/contract_clause_option/Destroy()
	effects = null
	return ..()

/proc/make_contract_clause_option(id, title, description, station_money = 0, department_money = 0, staff_money = 0, station_rep = 0, department_rep = 0, staff_rep = 0, deadline_change = 0, list/effects) as /datum/contract_clause_option
	var/datum/contract_clause_option/option = new(id, title, description)
	option.station_reward_delta = station_money
	option.department_reward_delta = department_money
	option.staff_reward_delta = staff_money
	option.station_reputation_delta = station_rep
	option.department_reputation_delta = department_rep
	option.staff_reputation_delta = staff_rep
	option.deadline_delta = deadline_change
	option.effects = effects?.Copy() || list()
	return option

/// A mutually-exclusive group of terms. Definitions may add any number of these.
/datum/contract_negotiation_clause
	var/id
	var/title
	var/description
	var/default_option_id
	var/list/options

/datum/contract_negotiation_clause/New(_id, _title, _description)
	. = ..()
	id = _id
	title = _title
	description = _description
	options = list()

/datum/contract_negotiation_clause/Destroy()
	for(var/option_id in options)
		qdel(options[option_id])
	options = null
	return ..()

/datum/contract_negotiation_clause/proc/add_option(datum/contract_clause_option/option, make_default = FALSE)
	if(!option?.id || options[option.id])
		return FALSE
	options[option.id] = option
	if(make_default || !default_option_id)
		default_option_id = option.id
	return TRUE

/// Immutable authoring datum. Gameplay content will subtype this later; the
/// infrastructure intentionally registers no concrete definitions yet.
/datum/contract_definition
	abstract_type = /datum/contract_definition
	var/id
	var/title = "Contract"
	var/description = ""
	var/scope = CONTRACT_SCOPE_STATION
	var/department
	var/issuer_name = "External issuer"
	var/issuer_faction
	var/reward = 0
	var/initial_offers = 0
	var/offer_duration = 15 MINUTES
	/// Expected completion window used to curate a mix of quick and strategic
	/// work before the concrete contract is materialized.
	var/expected_duration = 40 MINUTES
	var/offer_kind = CONTRACT_OFFER_OPPORTUNITY
	var/offer_cooldown = CONTRACT_DEFAULT_OFFER_COOLDOWN
	var/repeat_cooldown = CONTRACT_DEFAULT_REPEAT_COOLDOWN
	var/candidate_duration = 15 MINUTES
	var/auto_replace = FALSE
	var/max_simultaneous = 1
	var/deadline_grace_duration = CONTRACT_DEFAULT_GRACE_DURATION
	var/contract_type = /datum/contract

/datum/contract_definition/proc/is_available(list/context)
	return TRUE

/datum/contract_definition/proc/candidate_key(list/context)
	return context?["offer_key"] || id

/datum/contract_definition/proc/board_key(list/context)
	switch(scope)
		if(CONTRACT_SCOPE_STATION)
			return CONTRACT_SCOPE_STATION
		if(CONTRACT_SCOPE_DEPARTMENT)
			var/target_department = department || context?["department"]
			return target_department ? "[CONTRACT_SCOPE_DEPARTMENT]:[target_department]" : null
		if(CONTRACT_SCOPE_PERSONAL)
			var/owner_account = context?["owner_account"]
			return owner_account ? "[CONTRACT_SCOPE_PERSONAL]:[owner_account]" : null

/datum/contract_definition/proc/offer_remains_available(datum/contract/contract)
	return is_available(contract.offer_context)

/datum/contract_definition/proc/active_remains_possible(datum/contract/contract)
	return TRUE

/// Final event-driven feasibility reconciliation at acceptance time. Definitions
/// may scale terms to the live crew or reject a missing hard dependency.
/datum/contract_definition/proc/prepare_accept(datum/contract/contract, datum/money_account/accepting_account, mob/living/user, atom/source)
	return TRUE

/// Return TRUE after making a viable amendment. Returning FALSE withdraws the
/// impossible contract without penalty.
/datum/contract_definition/proc/amend_impossible_contract(datum/contract/contract, reason)
	return FALSE

/datum/contract_definition/proc/create_contract(list/context)
	if(!is_available(context))
		return null
	var/datum/contract/contract = new contract_type
	contract.title = title
	contract.description = description
	contract.scope = scope
	contract.department = department
	contract.issuer_name = issuer_name
	contract.issuer_faction = issuer_faction
	contract.reward = reward
	contract.definition_id = id
	contract.offer_kind = context?["offer_kind"] || offer_kind
	contract.offer_key = context?["offer_key"] || candidate_key(context)
	contract.offer_reason = context?["offer_reason"] || "Direct offer creation"
	contract.board_key = context?["board_key"] || board_key(context)
	contract.offer_context = context ? deepCopyList(context) : list()
	contract.deadline_grace_duration = deadline_grace_duration
	configure_contract(contract, context)
	finalize_contract_authoring(contract, context)
	if(!contract.finalize_offer(offer_duration))
		qdel(contract)
		return null
	return contract

/datum/contract_definition/proc/configure_contract(datum/contract/contract, list/context)
	return

/// Last authoring pass after a concrete definition has added its objectives.
/// Families use this to derive negotiation choices from the finished contract.
/datum/contract_definition/proc/finalize_contract_authoring(datum/contract/contract, list/context)
	return

/datum/contract
	var/id
	var/definition_id
	var/title = "Untitled contract"
	var/description = ""
	var/scope = CONTRACT_SCOPE_STATION
	var/state = CONTRACT_OFFERED
	var/issuer_name = "External issuer"
	var/issuer_faction
	var/department
	var/owner_account_number
	var/funding_mode = CONTRACT_FUNDING_EXTERNAL
	var/datum/money_account/funding_account
	var/reward = 0
	var/escrow_balance = 0
	/// Cumulative award already settled through project milestones. Final
	/// settlement pays only the remainder, so every tranche is exactly-once.
	var/paid_reward = 0
	var/paid_station_reward = 0
	var/paid_department_reward = 0
	var/paid_staff_reward = 0
	/// Set only after every planned recipient has accepted the complete payout.
	/// This prevents a later lifecycle error from paying the same contract twice.
	var/payout_distributed = FALSE
	var/station_share = 1
	var/department_share = 0
	var/contributor_share = 0
	var/station_reputation_reward = 0
	var/department_reputation_reward = 0
	var/personal_reputation_reward = 0
	var/deadline = 0
	var/deadline_duration = 0
	var/deadline_timer
	var/deadline_grace_duration = CONTRACT_DEFAULT_GRACE_DURATION
	var/grace_until = 0
	var/offer_expires_at = 0
	var/offer_timer
	var/accepted_at = 0
	var/accepted_by_account = 0
	var/closed_at = 0
	var/offer_kind = CONTRACT_OFFER_OPPORTUNITY
	var/offer_key
	var/board_key
	var/offer_reason
	var/closure_code
	var/list/offer_context
	var/list/requirements
	var/list/children
	var/datum/contract/parent
	var/list/contributions
	var/list/contributor_names
	var/list/audit_log
	var/list/negotiation_clauses
	var/list/negotiation_selections
	var/list/negotiated_effects
	var/negotiation_locked = FALSE
	var/base_terms_captured = FALSE
	var/base_reward = 0
	var/base_deadline_duration = 0
	var/base_station_reputation_reward = 0
	var/base_department_reputation_reward = 0
	var/base_personal_reputation_reward = 0
	var/negotiated_station_bonus = 0
	var/negotiated_department_bonus = 0
	var/negotiated_staff_bonus = 0
	var/standing_score = 0
	var/standing_tier = AFFILIATION_NEUTRAL
	var/standing_reward_modifier = 0
	/// Additional station-level faction consequences selected by negotiation.
	var/list/secondary_faction_reputation_rewards

/datum/contract/New()
	. = ..()
	requirements = list()
	children = list()
	contributions = list()
	contributor_names = list()
	audit_log = list()
	negotiation_clauses = list()
	negotiation_selections = list()
	negotiated_effects = list()
	secondary_faction_reputation_rewards = list()

/datum/contract/Destroy()
	if(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE))
		unsubscribe_events()
	if(deadline_timer)
		deltimer(deadline_timer)
		deadline_timer = null
	if(offer_timer)
		deltimer(offer_timer)
		offer_timer = null
	SScontracts?.unregister_contract(src)
	for(var/datum/contract_requirement/requirement in requirements)
		qdel(requirement)
	requirements = null
	for(var/datum/contract/child in children)
		if(child.parent == src)
			child.parent = null
	children = null
	parent = null
	funding_account = null
	contributions = null
	contributor_names = null
	for(var/clause_id in negotiation_clauses)
		qdel(negotiation_clauses[clause_id])
	negotiation_clauses = null
	negotiation_selections = null
	negotiated_effects = null
	secondary_faction_reputation_rewards = null
	offer_context = null
	for(var/datum/contract_audit_entry/entry in audit_log)
		qdel(entry)
	audit_log = null
	return ..()

/datum/contract/proc/finalize_offer(duration)
	if(state != CONTRACT_OFFERED || !isnum(duration) || duration <= 0)
		return FALSE
	capture_base_terms()
	recalculate_negotiated_terms()
	if(validate() || (!id && !SScontracts.register_contract(src)))
		return FALSE
	if(!length(audit_log))
		audit(CONTRACT_AUDIT_CREATED, "Contract offered by [issuer_name].")
	audit(CONTRACT_AUDIT_OFFER, "Published on [board_key || "the contract board"]: [offer_reason || "eligible offer"].")
	offer_expires_at = world.time + duration
	offer_timer = addtimer(CALLBACK(src, PROC_REF(expire_offer)), duration, TIMER_STOPPABLE)
	return TRUE

/datum/contract/proc/expire_offer()
	offer_timer = null
	if(state == CONTRACT_OFFERED)
		close(CONTRACT_CANCELLED, CONTRACT_AUDIT_CANCELLED, "The offer expired without acceptance.", CONTRACT_CLOSE_EXPIRED)

/datum/contract/proc/audit(category, detail)
	audit_log += new /datum/contract_audit_entry(category, detail)

/datum/contract/proc/add_requirement(datum/contract_requirement/requirement)
	if(!requirement || state != CONTRACT_OFFERED)
		return FALSE
	requirement.contract = src
	requirements += requirement
	return TRUE

/datum/contract/proc/add_child(datum/contract/child)
	if(!child || child == src || child.parent)
		return FALSE
	child.parent = src
	children += child
	return TRUE

/datum/contract/proc/add_negotiation_clause(datum/contract_negotiation_clause/clause)
	if(!clause?.id || state != CONTRACT_OFFERED || negotiation_clauses[clause.id] || !length(clause.options))
		return FALSE
	negotiation_clauses[clause.id] = clause
	negotiation_selections[clause.id] = clause.default_option_id
	return TRUE

/datum/contract/proc/capture_base_terms()
	if(base_terms_captured)
		return
	base_terms_captured = TRUE
	base_reward = reward
	base_deadline_duration = deadline_duration
	base_station_reputation_reward = station_reputation_reward
	base_department_reputation_reward = department_reputation_reward
	base_personal_reputation_reward = personal_reputation_reward

/datum/contract/proc/select_negotiation_option(clause_id, option_id, actor_name)
	if(state != CONTRACT_OFFERED || negotiation_locked)
		return FALSE
	var/datum/contract_negotiation_clause/clause = negotiation_clauses[clause_id]
	var/datum/contract_clause_option/option = clause?.options[option_id]
	if(!option)
		return FALSE
	capture_base_terms()
	negotiation_selections[clause_id] = option_id
	recalculate_negotiated_terms()
	audit(CONTRACT_AUDIT_NEGOTIATION, "[actor_name || "An authorized representative"] selected [clause.title]: [option.title].")
	return TRUE

/datum/contract/proc/recalculate_negotiated_terms()
	if(!base_terms_captured)
		return
	negotiated_station_bonus = 0
	negotiated_department_bonus = 0
	negotiated_staff_bonus = 0
	station_reputation_reward = base_station_reputation_reward
	department_reputation_reward = base_department_reputation_reward
	personal_reputation_reward = base_personal_reputation_reward
	deadline_duration = base_deadline_duration
	negotiated_effects.Cut()
	secondary_faction_reputation_rewards.Cut()
	for(var/clause_id in negotiation_clauses)
		var/datum/contract_negotiation_clause/clause = negotiation_clauses[clause_id]
		var/datum/contract_clause_option/option = clause.options[negotiation_selections[clause_id]]
		if(!option)
			continue
		negotiated_station_bonus += option.station_reward_delta
		negotiated_department_bonus += option.department_reward_delta
		negotiated_staff_bonus += option.staff_reward_delta
		station_reputation_reward += option.station_reputation_delta
		department_reputation_reward += option.department_reputation_delta
		personal_reputation_reward += option.staff_reputation_delta
		deadline_duration += option.deadline_delta
		for(var/effect_key in option.effects)
			negotiated_effects[effect_key] = LAZYACCESS(option.effects, effect_key)
		var/list/other_reputation = LAZYACCESS(option.effects, "other_faction_reputation")
		for(var/faction_id in other_reputation)
			var/change = other_reputation[faction_id]
			if(!isnum(change) || !change)
				continue
			if(faction_id == issuer_faction)
				station_reputation_reward += change
			else
				secondary_faction_reputation_rewards[faction_id] = (secondary_faction_reputation_rewards[faction_id] || 0) + change
	reward = base_reward + negotiated_station_bonus + negotiated_department_bonus + negotiated_staff_bonus
	on_negotiated_terms_changed()

/// Content may project declarative clause effects into its visible objectives.
/// This is called while an offer is mutable and must not create gameplay state.
/datum/contract/proc/on_negotiated_terms_changed()
	return

/datum/contract/proc/negotiated_effect(effect_key, fallback)
	return (effect_key in negotiated_effects) ? negotiated_effects[effect_key] : fallback

/datum/contract/proc/negotiated_station_amount()
	capture_base_terms()
	return max(0, floor(base_reward * station_share) + negotiated_station_bonus)

/datum/contract/proc/negotiated_department_amount()
	capture_base_terms()
	return max(0, floor(base_reward * department_share) + negotiated_department_bonus)

/datum/contract/proc/negotiated_staff_amount()
	capture_base_terms()
	var/base_station_amount = floor(base_reward * station_share)
	var/base_department_amount = min(base_reward - base_station_amount, floor(base_reward * department_share))
	return max(0, base_reward - base_station_amount - base_department_amount + negotiated_staff_bonus)

/datum/contract/proc/negotiation_complete()
	for(var/clause_id in negotiation_clauses)
		var/datum/contract_negotiation_clause/clause = negotiation_clauses[clause_id]
		if(!clause.options[negotiation_selections[clause_id]])
			return FALSE
	return TRUE

/datum/contract/proc/validate()
	capture_base_terms()
	recalculate_negotiated_terms()
	if(!length(title) || !(scope in list(CONTRACT_SCOPE_STATION, CONTRACT_SCOPE_DEPARTMENT, CONTRACT_SCOPE_PERSONAL)))
		return "Invalid identity or scope."
	if(scope == CONTRACT_SCOPE_DEPARTMENT && !department)
		return "Department contracts require a department."
	if(scope == CONTRACT_SCOPE_PERSONAL && !owner_account_number)
		return "Personal contracts require an owner account."
	if(reward < 0 || station_share < 0 || department_share < 0 || contributor_share < 0)
		return "Invalid reward distribution."
	if(abs((station_share + department_share + contributor_share) - 1) > 0.001)
		return "Reward shares must total 100%."
	if(!negotiation_complete())
		return "Every negotiation clause requires a selected term."
	if(negotiated_station_amount() + negotiated_department_amount() + negotiated_staff_amount() != reward)
		return "Negotiated reward terms do not reconcile."
	if(!length(requirements) && !length(children))
		return "Contracts require at least one requirement or child milestone."
	return null

/datum/contract/proc/accept(datum/money_account/accepting_account, mob/living/user, atom/source)
	var/datum/contract_definition/definition = SScontracts?.definitions[definition_id]
	if(state != CONTRACT_OFFERED || (definition && !definition.prepare_accept(src, accepting_account, user, source)) || validate())
		return FALSE
	if(offer_expires_at && world.time >= offer_expires_at)
		expire_offer()
		return FALSE
	if(scope == CONTRACT_SCOPE_PERSONAL && accepting_account?.account_number != owner_account_number)
		return FALSE
	if(!id && !SScontracts.register_contract(src))
		return FALSE
	if(funding_mode == CONTRACT_FUNDING_INTERNAL && reward > 0)
		if(!funding_account?.debit(reward, "Contract escrow [id]", title, "Contracts", FALSE))
			return FALSE
		escrow_balance = reward
	negotiation_locked = TRUE
	var/old_state = state
	if(offer_timer)
		deltimer(offer_timer)
		offer_timer = null
	offer_expires_at = 0
	state = CONTRACT_ACTIVE
	accepted_at = world.time
	accepted_by_account = accepting_account?.account_number || contract_account_for_mob(user)?.account_number
	if(deadline_duration > 0)
		deadline = world.time + deadline_duration
	if(deadline > world.time)
		deadline_timer = addtimer(CALLBACK(src, PROC_REF(check_deadline)), deadline - world.time, TIMER_STOPPABLE)
	SScontracts.set_contract_state(src, old_state, state)
	subscribe_events()
	for(var/datum/contract_requirement/requirement in requirements)
		requirement.on_contract_activated()
	audit(CONTRACT_AUDIT_ACCEPTED, "Contract accepted.")
	on_accepted(user, source)
	SScontracts?.handle_contract_accepted(src)
	if(offer_kind == CONTRACT_OFFER_OPPORTUNITY)
		SScontracts?.replay_post_trigger_events(src)
	return TRUE

/datum/contract/proc/on_accepted(mob/living/user, atom/source)
	return

/datum/contract/proc/ui_details(mob/living/user)
	return null

/datum/contract/proc/check_deadline()
	deadline_timer = null
	if(state == CONTRACT_ACTIVE && deadline && world.time >= deadline)
		if(deadline_grace_duration > 0)
			enter_grace()
		else
			fail("The deadline expired.")
	else if(state == CONTRACT_GRACE && grace_until && world.time >= grace_until)
		fail("The evidence grace period expired.")

/datum/contract/proc/enter_grace()
	if(state != CONTRACT_ACTIVE || deadline_grace_duration <= 0)
		return FALSE
	var/old_state = state
	state = CONTRACT_GRACE
	grace_until = world.time + deadline_grace_duration
	deadline_timer = addtimer(CALLBACK(src, PROC_REF(check_deadline)), deadline_grace_duration, TIMER_STOPPABLE)
	SScontracts.set_contract_state(src, old_state, state)
	audit(CONTRACT_AUDIT_GRACE, "The operational deadline passed; already-prepared evidence has [DisplayTimeText(deadline_grace_duration)] to arrive.")
	SScontracts?.notify_contract(src, "Contract [id] entered its evidence grace period.")
	return TRUE

/datum/contract/proc/subscribe_events()
	for(var/datum/contract_requirement/requirement in requirements)
		for(var/event_type in requirement.event_types)
			SScontracts.subscribe(src, event_type)

/datum/contract/proc/unsubscribe_events()
	for(var/datum/contract_requirement/requirement in requirements)
		for(var/event_type in requirement.event_types)
			SScontracts.unsubscribe(src, event_type)
		requirement.on_contract_closed()

/datum/contract/proc/receive_event(datum/contract_event/event)
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)))
		return FALSE
	if(state == CONTRACT_ACTIVE && deadline && world.time > deadline)
		check_deadline()
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)))
		return FALSE
	var/matched = FALSE
	for(var/datum/contract_requirement/requirement in requirements)
		if(event.event_type in requirement.event_types)
			matched = requirement.handle_event(event) || matched
	return matched

/datum/contract/proc/record_contribution(account_number, amount, detail, contributor_name)
	if(!account_number || !isnum(amount) || amount <= 0)
		return FALSE
	var/key = "[account_number]"
	contributions[key] = (contributions[key] || 0) + amount
	if(!contributor_name)
		var/datum/money_account/account = get_account(account_number)
		contributor_name = account?.owner_name
	if(contributor_name)
		contributor_names[key] = contributor_name
	if(detail)
		audit(CONTRACT_AUDIT_PROGRESS, "[contributor_name || "Account [account_number]"]: [detail]")
	return TRUE

/datum/contract/proc/reconcile_completion()
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)))
		return FALSE
	for(var/datum/contract_requirement/requirement in requirements)
		if(requirement.required && requirement.state != CONTRACT_REQUIREMENT_COMPLETE)
			return FALSE
	for(var/datum/contract/child in children)
		if(child.state != CONTRACT_COMPLETED)
			return FALSE
	return complete()

/datum/contract/proc/complete()
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)))
		return FALSE
	if(!payout())
		// Gameplay is already complete. An unavailable finance account must not
		// turn an otherwise successful contract into a deadline failure while it
		// waits for the account-status signal that retries payment.
		if(deadline_timer)
			deltimer(deadline_timer)
			deadline_timer = null
		deadline = 0
		grace_until = 0
		audit(CONTRACT_AUDIT_PAYMENT, "Completion is verified, but payment is deferred until every recipient account can accept its share.")
		SScontracts?.notify_contract(src, "Contract [id] completed its requirements, but payment is waiting on an unavailable recipient account.")
		return FALSE
	// Graded internal contracts may settle below their original escrowed ceiling.
	// Return the unearned remainder instead of silently consuming it.
	if(funding_mode == CONTRACT_FUNDING_INTERNAL && escrow_balance > 0)
		refund_escrow()
	SScontracts?.record_contract_completion(src)
	close(CONTRACT_COMPLETED, CONTRACT_AUDIT_COMPLETED, "All required conditions completed.", CONTRACT_CLOSE_COMPLETED)
	if(issuer_faction)
		adjust_station_faction_reputation(issuer_faction, station_reputation_reward)
		if(department)
			adjust_department_faction_reputation(department, issuer_faction, department_reputation_reward)
	for(var/faction_id in secondary_faction_reputation_rewards)
		adjust_station_faction_reputation(faction_id, secondary_faction_reputation_rewards[faction_id])
	var/list/reputation_recipients = reward_recipient_weights()
	var/total_reputation_weight = 0
	for(var/key in reputation_recipients)
		total_reputation_weight += reputation_recipients[key]
	var/reputation_distributed = 0
	for(var/key in reputation_recipients)
		var/reputation_share = total_reputation_weight > 0 ? round(personal_reputation_reward * reputation_recipients[key] / total_reputation_weight) : 0
		reputation_share = min(reputation_share, personal_reputation_reward - reputation_distributed)
		if(reputation_share && adjust_personal_faction_reputation(text2num(key), issuer_faction, reputation_share))
			reputation_distributed += reputation_share
	SScontracts?.maybe_queue_reputation_followup(src)
	parent?.reconcile_completion()
	return TRUE

/datum/contract/proc/find_mob_by_account(account_number)
	for(var/mob/living/living_mob in GLOB.player_list)
		if(living_mob.mind?.initial_account?.account_number == account_number)
			return living_mob

/// Contributor evidence remains the preferred distribution. Some outcomes,
/// such as stable reactor operation, are intentionally machine-authenticated
/// and have no trustworthy single operator; those awards fall back to the
/// active department roster instead of silently diverting the staff share to
/// station reserves. Personal contracts always fall back to their owner.
/datum/contract/proc/reward_recipient_weights()
	if(length(contributions))
		var/list/normalized = list()
		for(var/account_number in contributions)
			// Evidence uses incomparable units: currency, joules, items and people.
			// Logarithmic weighting preserves meaningful effort without allowing a
			// large currency counter to erase every other contributor.
			normalized[account_number] = 1 + log(1 + max(0, contributions[account_number]))
		return normalized
	var/list/recipients = list()
	if(scope == CONTRACT_SCOPE_PERSONAL && owner_account_number)
		recipients["[owner_account_number]"] = 1
		return recipients
	for(var/mob/living/player in GLOB.player_list)
		if(!player.client || player.stat == DEAD)
			continue
		if(department && department_for_mob(player) != department)
			continue
		var/datum/money_account/account = contract_account_for_mob(player)
		if(account)
			recipients["[account.account_number]"] = 1
	return recipients

/datum/contract/proc/fail(reason)
	if(!(state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)))
		return FALSE
	close(CONTRACT_FAILED, CONTRACT_AUDIT_FAILED, reason, CONTRACT_CLOSE_FAILED)
	refund_escrow()
	apply_failure_reputation()
	return TRUE

/datum/contract/proc/apply_failure_reputation()
	if(!issuer_faction)
		return
	var/station_penalty = -max(1, round(max(1, station_reputation_reward) * CONTRACT_DEFAULT_FAILURE_REPUTATION_FACTOR))
	adjust_station_faction_reputation(issuer_faction, station_penalty)
	if(department)
		var/department_penalty = -max(1, round(max(1, department_reputation_reward) * CONTRACT_DEFAULT_FAILURE_REPUTATION_FACTOR))
		adjust_department_faction_reputation(department, issuer_faction, department_penalty)
	if(accepted_by_account && personal_reputation_reward)
		adjust_personal_faction_reputation(accepted_by_account, issuer_faction, -max(1, round(personal_reputation_reward * CONTRACT_DEFAULT_FAILURE_REPUTATION_FACTOR)))

/datum/contract/proc/cancel(reason = "Cancelled by issuer.")
	if(!(state in list(CONTRACT_OFFERED, CONTRACT_ACTIVE, CONTRACT_GRACE)))
		return FALSE
	close(CONTRACT_CANCELLED, CONTRACT_AUDIT_CANCELLED, reason, CONTRACT_CLOSE_CANCELLED)
	refund_escrow()
	return TRUE

/datum/contract/proc/decline(mob/living/user)
	if(state != CONTRACT_OFFERED)
		return FALSE
	close(CONTRACT_CANCELLED, CONTRACT_AUDIT_CANCELLED, "Offer declined by [user?.real_name || "an authorized representative"].", CONTRACT_CLOSE_DECLINED)
	return TRUE

/datum/contract/proc/withdraw(reason)
	if(!(state in list(CONTRACT_OFFERED, CONTRACT_ACTIVE, CONTRACT_GRACE)))
		return FALSE
	close(CONTRACT_CANCELLED, CONTRACT_AUDIT_CANCELLED, reason || "The offer was withdrawn because it was no longer fulfillable.", CONTRACT_CLOSE_INELIGIBLE)
	refund_escrow()
	return TRUE

/datum/contract/proc/close(new_state, category, detail, _closure_code = CONTRACT_CLOSE_CANCELLED)
	var/old_state = state
	if(old_state in list(CONTRACT_ACTIVE, CONTRACT_GRACE))
		unsubscribe_events()
	if(deadline_timer)
		deltimer(deadline_timer)
		deadline_timer = null
	if(offer_timer)
		deltimer(offer_timer)
		offer_timer = null
	offer_expires_at = 0
	grace_until = 0
	state = new_state
	closure_code = _closure_code
	closed_at = world.time
	SScontracts.set_contract_state(src, old_state, state)
	audit(category, detail)
	SScontracts?.on_contract_closed(src)
	SScontracts?.schedule_contract_evidence_prune(id)

/datum/contract/proc/refund_escrow()
	if(escrow_balance <= 0 || !funding_account)
		return FALSE
	var/refund_amount = escrow_balance
	if(!funding_account.credit(refund_amount, "Contracts", "Refund: [title]", "Contracts", FALSE, TRUE))
		return FALSE
	audit(CONTRACT_AUDIT_PAYMENT, "[escrow_balance] Thalers returned to issuer.")
	escrow_balance = 0
	return TRUE

/datum/contract/proc/payout()
	if(payout_distributed)
		return TRUE
	return payout_to_amount(reward, "Final settlement")

/// Settle a cumulative portion of the currently authored award. This is a
/// cumulative target rather than a delta so duplicate/replayed milestone
/// events cannot issue the same money twice.
/datum/contract/proc/payout_to_fraction(fraction, reason = "Project milestone")
	if(!isnum(fraction))
		return FALSE
	return payout_to_amount(round(reward * clamp(fraction, 0, 1)), reason)

/datum/contract/proc/payout_to_amount(target_paid, reason = "Project milestone")
	if(payout_distributed)
		return target_paid <= paid_reward
	target_paid = clamp(round(target_paid), 0, reward)
	if(target_paid <= paid_reward)
		payout_distributed = paid_reward >= reward
		return TRUE
	if(reward <= 0)
		payout_distributed = TRUE
		return TRUE
	var/tranche = target_paid - paid_reward
	var/available = funding_mode == CONTRACT_FUNDING_INTERNAL ? escrow_balance : tranche
	if(available < tranche)
		return FALSE
	var/total_station_amount = negotiated_station_amount()
	var/total_department_amount = negotiated_department_amount()
	var/total_staff_amount = negotiated_staff_amount()
	var/station_amount = round(total_station_amount * target_paid / reward) - paid_station_reward
	var/department_amount = round(total_department_amount * target_paid / reward) - paid_department_reward
	var/contributor_amount = tranche - station_amount - department_amount
	if(target_paid == reward)
		station_amount = total_station_amount - paid_station_reward
		department_amount = total_department_amount - paid_department_reward
		contributor_amount = total_staff_amount - paid_staff_reward
	if(station_amount < 0 || department_amount < 0 || contributor_amount < 0)
		return FALSE
	var/external_funding = funding_mode != CONTRACT_FUNDING_INTERNAL
	var/list/planned_payouts = list()
	if(station_amount > 0)
		if(!GLOB.station_account || GLOB.station_account.suspended)
			return FALSE
		planned_payouts[GLOB.station_account] = station_amount
	if(department_amount > 0)
		var/datum/money_account/department_account = GLOB.department_accounts[department]
		if(!department_account || department_account.suspended)
			return FALSE
		planned_payouts[department_account] = (planned_payouts[department_account] || 0) + department_amount
	var/list/recipient_weights = reward_recipient_weights()
	var/total_contribution = 0
	for(var/key in recipient_weights)
		total_contribution += recipient_weights[key]
	var/paid = 0
	if(contributor_amount > 0 && total_contribution > 0)
		for(var/key in recipient_weights)
			var/datum/money_account/account = get_account(text2num(key))
			if(!account)
				continue
			if(account.suspended)
				return FALSE
			var/share = round(contributor_amount * recipient_weights[key] / total_contribution)
			share = min(share, contributor_amount - paid)
			if(share > 0)
				planned_payouts[account] = (planned_payouts[account] || 0) + share
				paid += share
	var/unclaimed = contributor_amount - paid
	if(unclaimed > 0)
		if(!GLOB.station_account || GLOB.station_account.suspended)
			return FALSE
		planned_payouts[GLOB.station_account] = (planned_payouts[GLOB.station_account] || 0) + unclaimed
	var/planned_total = 0
	for(var/datum/money_account/account as anything in planned_payouts)
		var/account_amount = planned_payouts[account]
		if(QDELETED(account) || account.suspended || !isnum(account_amount) || account_amount <= 0)
			return FALSE
		planned_total += account_amount
	if(planned_total != tranche)
		return FALSE
	// DM cannot interleave another account mutation here: every credit is
	// preflighted above and credit() does not sleep. The batch is therefore
	// atomic with respect to account availability.
	for(var/datum/money_account/account as anything in planned_payouts)
		if(!account.credit(planned_payouts[account], issuer_name, "Contract [id]: [title] — [reason]", "Contracts", external_funding))
			return FALSE
	if(funding_mode == CONTRACT_FUNDING_INTERNAL)
		escrow_balance -= planned_total
	paid_reward += planned_total
	paid_station_reward += station_amount
	paid_department_reward += department_amount
	paid_staff_reward += contributor_amount
	payout_distributed = paid_reward >= reward
	audit(CONTRACT_AUDIT_PAYMENT, "[reason]: distributed [planned_total] Thalers ([paid_reward]/[reward] settled).")
	return TRUE
