/proc/contract_evidence_compare(actual, comparator, expected)
	switch(comparator)
		if(CONTRACT_EVIDENCE_COMPARE_EQUAL)
			return actual == expected
		if(CONTRACT_EVIDENCE_COMPARE_NOT_EQUAL)
			return actual != expected
		if(CONTRACT_EVIDENCE_COMPARE_AT_LEAST)
			return isnum(actual) && isnum(expected) && actual >= expected
		if(CONTRACT_EVIDENCE_COMPARE_AT_MOST)
			return isnum(actual) && isnum(expected) && actual <= expected
		if(CONTRACT_EVIDENCE_COMPARE_GREATER)
			return isnum(actual) && isnum(expected) && actual > expected
		if(CONTRACT_EVIDENCE_COMPARE_LESS)
			return isnum(actual) && isnum(expected) && actual < expected
	return FALSE

/// Declarative, reusable matcher shared by count and sustained-state evidence.
/datum/contract_event_filter
	var/scope_mode = CONTRACT_EVIDENCE_SCOPE_ANY
	var/list/exact_values
	var/list/allowed_values
	var/list/forbidden_values
	var/list/required_tags
	var/list/numeric_checks

/datum/contract_event_filter/New(_scope_mode = CONTRACT_EVIDENCE_SCOPE_ANY)
	. = ..()
	scope_mode = _scope_mode
	exact_values = list()
	allowed_values = list()
	forbidden_values = list()
	required_tags = list()
	numeric_checks = list()

/datum/contract_event_filter/Destroy()
	exact_values = null
	allowed_values = null
	forbidden_values = null
	required_tags = null
	numeric_checks = null
	return ..()

/datum/contract_event_filter/proc/require_value(key, expected)
	if(!istext(key) || !length(key))
		return FALSE
	exact_values[key] = expected
	return TRUE

/datum/contract_event_filter/proc/require_any_value(key, list/allowed)
	if(!istext(key) || !length(key) || !length(allowed))
		return FALSE
	allowed_values[key] = allowed.Copy()
	return TRUE

/datum/contract_event_filter/proc/forbid_value(key, forbidden)
	if(!istext(key) || !length(key))
		return FALSE
	forbidden_values[key] = forbidden
	return TRUE

/datum/contract_event_filter/proc/require_tag(tag)
	if(!istext(tag) || !length(tag))
		return FALSE
	required_tags |= tag
	return TRUE

/datum/contract_event_filter/proc/require_number(key, comparator, expected)
	if(!istext(key) || !length(key) || !isnum(expected) || !(comparator in list(
		CONTRACT_EVIDENCE_COMPARE_EQUAL,
		CONTRACT_EVIDENCE_COMPARE_NOT_EQUAL,
		CONTRACT_EVIDENCE_COMPARE_AT_LEAST,
		CONTRACT_EVIDENCE_COMPARE_AT_MOST,
		CONTRACT_EVIDENCE_COMPARE_GREATER,
		CONTRACT_EVIDENCE_COMPARE_LESS,
	)))
		return FALSE
	numeric_checks.Add(list(list("key" = key, "comparator" = comparator, "expected" = expected)))
	return TRUE

/datum/contract_event_filter/proc/set_number_requirement(key, comparator, expected)
	for(var/list/check as anything in numeric_checks)
		if(check["key"] == key && check["comparator"] == comparator)
			check["expected"] = expected
			return TRUE
	return require_number(key, comparator, expected)

/datum/contract_event_filter/proc/matches(datum/contract_event/event, datum/contract/contract)
	if(!event || !contract)
		return FALSE
	switch(scope_mode)
		if(CONTRACT_EVIDENCE_SCOPE_CONTRACT)
			if(event.contract_id != contract.id)
				return FALSE
		if(CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
			if((event.department || event.actor_department) != contract.department)
				return FALSE
		if(CONTRACT_EVIDENCE_SCOPE_OWNER)
			if(event.actor_account != contract.owner_account_number)
				return FALSE
	for(var/key in exact_values)
		if(event.value(key) != exact_values[key])
			return FALSE
	for(var/key in allowed_values)
		var/list/allowed = allowed_values[key]
		if(!("[event.value(key)]" in allowed))
			return FALSE
	for(var/key in forbidden_values)
		if(event.value(key) == forbidden_values[key])
			return FALSE
	for(var/tag in required_tags)
		if(!(tag in event.tags))
			return FALSE
	for(var/list/check as anything in numeric_checks)
		if(!contract_evidence_compare(event.value(check["key"]), check["comparator"], check["expected"]))
			return FALSE
	return TRUE

/datum/contract_requirement
	abstract_type = /datum/contract_requirement
	var/name = "Contract requirement"
	var/description = "Complete the specified work."
	var/state = CONTRACT_REQUIREMENT_PENDING
	var/required = TRUE
	var/progress = 0
	var/target = 1
	var/list/event_types
	var/datum/contract/contract

/datum/contract_requirement/New(_required = TRUE)
	. = ..()
	required = _required
	event_types = list()

/datum/contract_requirement/Destroy()
	contract = null
	event_types = null
	return ..()

/datum/contract_requirement/proc/on_contract_activated()
	return

/datum/contract_requirement/proc/on_contract_closed()
	return

/datum/contract_requirement/proc/handle_event(datum/contract_event/event)
	return FALSE

/datum/contract_requirement/proc/add_progress(amount, contributor_account, detail)
	if(state != CONTRACT_REQUIREMENT_PENDING || !isnum(amount) || amount <= 0)
		return FALSE
	var/old_progress = progress
	progress = min(target, progress + amount)
	if(progress >= target)
		state = CONTRACT_REQUIREMENT_COMPLETE
	if(progress != old_progress)
		contract?.record_contribution(contributor_account, progress - old_progress, detail || name)
		contract?.audit(CONTRACT_AUDIT_PROGRESS, "[name]: [progress]/[target]")
		contract?.reconcile_completion()
	return progress != old_progress

/// Reconcile progress that represents current, correctable facts. Unlike
/// add_progress(), this may move backward and reopen the requirement while the
/// contract remains live. Settled/final events should be used when an outcome
/// must not be reopened after payout.
/datum/contract_requirement/proc/set_reversible_progress(amount, contributor_account, detail)
	if(!(state in list(CONTRACT_REQUIREMENT_PENDING, CONTRACT_REQUIREMENT_COMPLETE)) || !isnum(amount) || amount < 0)
		return FALSE
	var/old_progress = progress
	progress = min(target, amount)
	state = progress >= target ? CONTRACT_REQUIREMENT_COMPLETE : CONTRACT_REQUIREMENT_PENDING
	if(progress > old_progress)
		contract?.record_contribution(contributor_account, progress - old_progress, detail || name)
	if(progress != old_progress)
		contract?.audit(CONTRACT_AUDIT_PROGRESS, "[name]: [progress]/[target]")
		contract?.reconcile_completion()
	return progress != old_progress

/datum/contract_requirement/proc/fail(detail)
	if(state != CONTRACT_REQUIREMENT_PENDING)
		return FALSE
	state = CONTRACT_REQUIREMENT_FAILED
	contract?.fail(detail || "A required condition failed.")
	return TRUE

/datum/contract_requirement/proc/progress_text()
	return "[progress] / [target]"

/datum/contract_requirement/proc/ui_stage_rows()
	return list()

/// Requires two real event streams to refer to the same subjects/assets. This
/// prevents unrelated work from satisfying a purported follow-through task.
/datum/contract_requirement/paired_facts
	name = "Linked work"
	var/first_event_type
	var/second_event_type
	var/join_field
	var/second_join_field
	var/datum/contract_event_filter/first_filter
	var/datum/contract_event_filter/second_filter
	var/list/first_facts
	var/list/second_facts
	var/list/credited_facts
	var/list/first_fact_times
	var/list/second_fact_times

/datum/contract_requirement/paired_facts/New(_first_event_type, _second_event_type, _join_field, _target = 1, _scope_mode = CONTRACT_EVIDENCE_SCOPE_ANY, _second_join_field)
	. = ..()
	first_event_type = _first_event_type
	second_event_type = _second_event_type
	join_field = _join_field
	second_join_field = _second_join_field || _join_field
	target = max(1, _target)
	first_filter = new(_scope_mode)
	second_filter = new(_scope_mode)
	first_facts = list()
	second_facts = list()
	credited_facts = list()
	first_fact_times = list()
	second_fact_times = list()
	event_types = list(first_event_type, second_event_type)

/datum/contract_requirement/paired_facts/Destroy()
	QDEL_NULL(first_filter)
	QDEL_NULL(second_filter)
	first_facts = null
	second_facts = null
	credited_facts = null
	first_fact_times = null
	second_fact_times = null
	return ..()

/datum/contract_requirement/paired_facts/handle_event(datum/contract_event/event)
	if(state != CONTRACT_REQUIREMENT_PENDING)
		return FALSE
	var/value = event.value(event.event_type == second_event_type ? second_join_field : join_field)
	if(isnull(value) || value == "")
		return FALSE
	var/key = "[value]"
	if(event.event_type == first_event_type)
		if(!first_filter.matches(event, contract))
			return FALSE
		// A follow-up observed before its prerequisite cannot be banked and then
		// joined later, even when both events share one BYOND world tick.
		if(key in second_facts)
			second_facts -= key
			second_fact_times -= key
		first_facts[key] = event.contributor_account || event.actor_account || TRUE
		first_fact_times[key] = event.occurred_at
	else if(event.event_type == second_event_type)
		if(!second_filter.matches(event, contract))
			return FALSE
		second_facts[key] = event.contributor_account || event.actor_account || TRUE
		second_fact_times[key] = event.occurred_at
	else
		return FALSE
	if(credited_facts[key] || !(key in first_facts) || !(key in second_facts))
		return TRUE
	if(second_fact_times[key] < first_fact_times[key])
		return TRUE
	credited_facts[key] = TRUE
	var/contributor = second_facts[key]
	if(!isnum(contributor) || contributor == TRUE)
		contributor = first_facts[key]
	return add_progress(1, isnum(contributor) && contributor != TRUE ? contributor : null, "Linked [join_field] [key] completed both parts of [name].")

/datum/contract_requirement/paired_facts/progress_text()
	return "[progress] / [target] linked outcomes"

/// Generic event-driven counter. A definition describes its evidence with
/// scope, exact values, tags, numeric predicates, and an optional uniqueness
/// key; no contract-specific polling loop or callback gadget is required.
/datum/contract_requirement/event_count
	name = "Event count"
	var/event_type
	var/datum/contract_event_filter/filter
	var/value_field
	var/contributor_field = "contributor_account"
	var/unique_field
	var/list/accepted_unique_values

/datum/contract_requirement/event_count/New(_event_type, _target = 1, list/_required_context, _value_field, _required = TRUE, _scope_mode = CONTRACT_EVIDENCE_SCOPE_ANY)
	. = ..(_required)
	event_type = _event_type
	target = max(1, _target)
	value_field = _value_field
	filter = new(_scope_mode)
	accepted_unique_values = list()
	for(var/key in _required_context)
		filter.require_value(key, _required_context[key])
	if(event_type)
		event_types += event_type

/datum/contract_requirement/event_count/Destroy()
	QDEL_NULL(filter)
	accepted_unique_values = null
	return ..()

/datum/contract_requirement/event_count/proc/require_value(key, expected)
	return filter.require_value(key, expected)

/datum/contract_requirement/event_count/proc/require_any_value(key, list/allowed)
	return filter.require_any_value(key, allowed)

/datum/contract_requirement/event_count/proc/forbid_value(key, forbidden)
	return filter.forbid_value(key, forbidden)

/datum/contract_requirement/event_count/proc/require_tag(tag)
	return filter.require_tag(tag)

/datum/contract_requirement/event_count/proc/require_number(key, comparator, expected)
	return filter.require_number(key, comparator, expected)

/datum/contract_requirement/event_count/handle_event(datum/contract_event/event)
	if(state != CONTRACT_REQUIREMENT_PENDING || event?.event_type != event_type || !filter.matches(event, contract))
		return FALSE
	var/amount = value_field ? event.value(value_field) : 1
	if(!isnum(amount) || amount <= 0)
		return FALSE
	if(unique_field)
		var/unique_value = event.value(unique_field)
		if(isnull(unique_value) || ("[unique_value]" in accepted_unique_values))
			return FALSE
		accepted_unique_values += "[unique_value]"
	var/list/contributor_weights = event.value("contributor_weights")
	if(length(contributor_weights))
		var/weight_total = 0
		for(var/contributor_key in contributor_weights)
			var/weight = contributor_weights[contributor_key]
			if(isnum(weight) && weight > 0)
				weight_total += weight
		if(weight_total > 0)
			for(var/contributor_key in contributor_weights)
				var/weight = contributor_weights[contributor_key]
				if(isnum(weight) && weight > 0)
					contract?.record_contribution(text2num(contributor_key), amount * weight / weight_total, event.value("detail"))
			return add_progress(amount, null, event.value("detail"))
	return add_progress(amount, event.value(contributor_field), event.value("detail"))

/// Event-driven duration evidence. A qualifying state starts one timer per
/// entity; a later non-qualifying state cancels it. The timer is the completion
/// edge, not a gameplay scan, so stable systems require no periodic work.
/datum/contract_requirement/sustained_event
	name = "Sustained result"
	var/event_type
	var/entity_field
	var/numeric_field
	var/comparator
	var/threshold
	var/duration
	var/datum/contract_event_filter/filter
	var/list/pending_tokens
	var/list/pending_timers
	var/list/completed_entities

/datum/contract_requirement/sustained_event/New(_event_type, _entity_field, _numeric_field, _comparator, _threshold, _duration, _target = 1, _scope_mode = CONTRACT_EVIDENCE_SCOPE_ANY)
	. = ..()
	event_type = _event_type
	entity_field = _entity_field
	numeric_field = _numeric_field
	comparator = _comparator
	threshold = _threshold
	duration = max(1, _duration)
	target = max(1, _target)
	filter = new(_scope_mode)
	pending_tokens = list()
	pending_timers = list()
	completed_entities = list()
	if(event_type)
		event_types += event_type

/datum/contract_requirement/sustained_event/Destroy()
	cancel_pending_timers()
	QDEL_NULL(filter)
	pending_tokens = null
	pending_timers = null
	completed_entities = null
	return ..()

/datum/contract_requirement/sustained_event/proc/require_any_value(key, list/allowed)
	return filter.require_any_value(key, allowed)

/datum/contract_requirement/sustained_event/on_contract_closed()
	cancel_pending_timers()

/datum/contract_requirement/sustained_event/proc/cancel_pending_timers()
	for(var/entity_key in pending_timers)
		var/timer_id = pending_timers[entity_key]
		if(timer_id)
			deltimer(timer_id)
	if(pending_timers)
		pending_timers.Cut()
	if(pending_tokens)
		pending_tokens.Cut()

/datum/contract_requirement/sustained_event/handle_event(datum/contract_event/event)
	if(state != CONTRACT_REQUIREMENT_PENDING || event?.event_type != event_type)
		return FALSE
	var/entity_value = event.value(entity_field)
	if(isnull(entity_value))
		return FALSE
	var/entity_key = "[entity_value]"
	if(entity_key in completed_entities)
		return FALSE
	// Every authoritative update for the same entity replaces its previous
	// qualifying state. Auxiliary predicates are part of that state: a reactor
	// which loses required integrity must cancel its EER timer just as surely as
	// one whose EER itself falls below the threshold.
	if(!filter.matches(event, contract) || !contract_evidence_compare(event.value(numeric_field), comparator, threshold))
		var/timer_id = pending_timers[entity_key]
		if(timer_id)
			deltimer(timer_id)
		pending_timers -= entity_key
		pending_tokens -= entity_key
		return FALSE
	if(pending_timers[entity_key])
		return FALSE
	var/token = event.id
	pending_tokens[entity_key] = token
	pending_timers[entity_key] = addtimer(CALLBACK(src, PROC_REF(complete_duration), entity_key, token, event.actor_account, event.value("detail")), duration, TIMER_STOPPABLE)
	return TRUE

/datum/contract_requirement/sustained_event/proc/complete_duration(entity_key, token, contributor_account, detail)
	if(state != CONTRACT_REQUIREMENT_PENDING || pending_tokens[entity_key] != token)
		return
	pending_tokens -= entity_key
	pending_timers -= entity_key
	completed_entities |= entity_key
	add_progress(1, contributor_account, detail || "Maintained the qualifying state for [DisplayTimeText(duration)].")

/// A sequence of increasingly demanding sustained states. Every tier listens
/// to the same authoritative event stream, but only the next tier may advance,
/// making the authored order a real operational ramp rather than presentation.
/datum/contract_requirement/staged_sustained_event
	name = "Staged sustained result"
	var/event_type
	var/entity_field
	var/numeric_field
	var/comparator = CONTRACT_EVIDENCE_COMPARE_AT_LEAST
	var/datum/contract_event_filter/filter
	/// Ordered entries: list(list("label" = text, "threshold" = number, "duration" = deciseconds)).
	var/list/stages
	var/list/pending_tokens
	var/list/pending_timers
	var/list/pending_stage_indices
	var/list/completed_stages

/datum/contract_requirement/staged_sustained_event/New(_event_type, _entity_field, _numeric_field, _comparator, list/_stages, _scope_mode = CONTRACT_EVIDENCE_SCOPE_ANY)
	. = ..()
	event_type = _event_type
	entity_field = _entity_field
	numeric_field = _numeric_field
	comparator = _comparator
	filter = new(_scope_mode)
	pending_tokens = list()
	pending_timers = list()
	pending_stage_indices = list()
	completed_stages = list()
	set_stages(_stages)
	if(event_type)
		event_types += event_type

/datum/contract_requirement/staged_sustained_event/Destroy()
	cancel_pending_timers()
	QDEL_NULL(filter)
	stages = null
	pending_tokens = null
	pending_timers = null
	pending_stage_indices = null
	completed_stages = null
	return ..()

/datum/contract_requirement/staged_sustained_event/proc/set_stages(list/new_stages)
	if((contract && contract.state != CONTRACT_OFFERED) || !length(new_stages))
		return FALSE
	cancel_pending_timers()
	stages = deepCopyList(new_stages)
	target = length(stages)
	progress = 0
	state = CONTRACT_REQUIREMENT_PENDING
	completed_stages.Cut()
	return TRUE

/datum/contract_requirement/staged_sustained_event/on_contract_closed()
	cancel_pending_timers()

/datum/contract_requirement/staged_sustained_event/proc/cancel_pending_timers()
	for(var/key in pending_timers)
		var/timer_id = pending_timers[key]
		if(timer_id)
			deltimer(timer_id)
	if(pending_timers)
		pending_timers.Cut()
	if(pending_tokens)
		pending_tokens.Cut()
	if(pending_stage_indices)
		pending_stage_indices.Cut()

/datum/contract_requirement/staged_sustained_event/handle_event(datum/contract_event/event)
	if(state != CONTRACT_REQUIREMENT_PENDING || event?.event_type != event_type)
		return FALSE
	var/entity_value = event.value(entity_field)
	if(isnull(entity_value))
		return FALSE
	var/changed = FALSE
	if(!filter.matches(event, contract))
		for(var/stage_index in 1 to length(stages))
			var/stage_key = "[entity_value]:[stage_index]"
			var/timer_id = pending_timers[stage_key]
			if(timer_id)
				deltimer(timer_id)
				pending_timers -= stage_key
				pending_tokens -= stage_key
				pending_stage_indices -= stage_key
				changed = TRUE
		return changed
	// Stages are an actual ramp, not three independent checks that happen to be
	// displayed in order. Only the next tier may hold or complete.
	var/stage_index = progress + 1
	if(stage_index > length(stages))
		return changed
	var/stage_key = "[entity_value]:[stage_index]"
	var/list/stage = stages[stage_index]
	var/qualifies = contract_evidence_compare(event.value(numeric_field), comparator, stage["threshold"])
	if(!qualifies)
		var/timer_id = pending_timers[stage_key]
		if(timer_id)
			deltimer(timer_id)
			pending_timers -= stage_key
			pending_tokens -= stage_key
			pending_stage_indices -= stage_key
			changed = TRUE
		return changed
	if(pending_timers[stage_key])
		return changed
	var/token = event.id
	pending_tokens[stage_key] = token
	pending_stage_indices[stage_key] = stage_index
	pending_timers[stage_key] = addtimer(CALLBACK(src, PROC_REF(complete_stage), stage_key, stage_index, token, event.actor_account, event.value("detail")), max(1, stage["duration"]), TIMER_STOPPABLE)
	changed = TRUE
	return changed

/datum/contract_requirement/staged_sustained_event/proc/complete_stage(stage_key, stage_index, token, contributor_account, detail)
	if(state != CONTRACT_REQUIREMENT_PENDING || pending_tokens[stage_key] != token || ("[stage_index]" in completed_stages))
		return
	completed_stages |= "[stage_index]"
	for(var/other_key in pending_timers.Copy())
		if(pending_stage_indices[other_key] != stage_index)
			continue
		var/timer_id = pending_timers[other_key]
		if(other_key != stage_key && timer_id)
			deltimer(timer_id)
		pending_tokens -= other_key
		pending_timers -= other_key
		pending_stage_indices -= other_key
	var/list/stage = stages[stage_index]
	add_progress(1, contributor_account, detail || "Completed [stage["label"]] at [stage["threshold"]] for [DisplayTimeText(stage["duration"])].")

/datum/contract_requirement/staged_sustained_event/progress_text()
	if(progress >= target)
		return "All [target] stages certified"
	var/list/next_stage = stages[min(target, progress + 1)]
	return "Stage [progress + 1] of [target]: [next_stage["label"]] — [next_stage["threshold"]] for [DisplayTimeText(next_stage["duration"])]"

/datum/contract_requirement/staged_sustained_event/ui_stage_rows()
	var/list/rows = list()
	for(var/stage_index in 1 to length(stages))
		var/list/stage = stages[stage_index]
		var/status = "Waiting"
		if("[stage_index]" in completed_stages)
			status = "Complete"
		else
			for(var/stage_key in pending_stage_indices)
				if(pending_stage_indices[stage_key] == stage_index)
					status = "Holding"
					break
		rows.Add(list(list(
			"index" = stage_index,
			"label" = stage["label"],
			"threshold" = stage["threshold"],
			"unit" = stage["unit"] || "",
			"duration" = DisplayTimeText(stage["duration"]),
			"status" = status,
		)))
	return rows

/// Tracks the latest reported value for each stable entity and completes when
/// their current aggregate reaches the target. Re-reporting one allocation or
/// machine cannot inflate progress, while legitimate edits replace the old
/// value instead of being ignored forever.
/datum/contract_requirement/snapshot_total
	name = "Current aggregate"
	var/event_type
	var/entity_field
	var/value_field
	var/contributor_field = "contributor_account"
	var/datum/contract_event_filter/filter
	var/list/entity_values

/datum/contract_requirement/snapshot_total/New(_event_type, _entity_field, _value_field, _target, _scope_mode = CONTRACT_EVIDENCE_SCOPE_ANY)
	. = ..()
	event_type = _event_type
	entity_field = _entity_field
	value_field = _value_field
	target = max(1, _target)
	filter = new(_scope_mode)
	entity_values = list()
	if(event_type)
		event_types += event_type

/datum/contract_requirement/snapshot_total/Destroy()
	QDEL_NULL(filter)
	entity_values = null
	return ..()

/datum/contract_requirement/snapshot_total/proc/require_value(key, expected)
	return filter.require_value(key, expected)

/datum/contract_requirement/snapshot_total/proc/forbid_value(key, forbidden)
	return filter.forbid_value(key, forbidden)

/datum/contract_requirement/snapshot_total/proc/require_tag(tag)
	return filter.require_tag(tag)

/datum/contract_requirement/snapshot_total/proc/require_number(key, comparator, expected)
	return filter.require_number(key, comparator, expected)

/datum/contract_requirement/snapshot_total/handle_event(datum/contract_event/event)
	if(!(state in list(CONTRACT_REQUIREMENT_PENDING, CONTRACT_REQUIREMENT_COMPLETE)) || event?.event_type != event_type || !filter.matches(event, contract))
		return FALSE
	var/entity_value = event.value(entity_field)
	var/new_value = event.value(value_field)
	if(isnull(entity_value) || !isnum(new_value) || new_value < 0)
		return FALSE
	var/entity_key = "[entity_value]"
	var/old_value = entity_values[entity_key] || 0
	if(old_value == new_value)
		return FALSE
	entity_values[entity_key] = new_value
	var/aggregate = 0
	for(var/key in entity_values)
		aggregate += entity_values[key]
	return set_reversible_progress(aggregate, event.value(contributor_field), event.value("detail"))

/// A generic, correction-aware portfolio of stable facts. It supports value
/// caps per fact and per category plus a distinct-category target, preventing
/// one unusually valuable or repeatedly emitted item from satisfying an
/// entire varied-output contract.
/datum/contract_requirement/fact_portfolio
	name = "Evidence portfolio"
	var/event_type
	var/fact_field = "fact_id"
	var/revision_field = "fact_revision"
	var/active_field = "fact_active"
	var/category_field
	var/value_field
	var/contributor_field = "contributor_account"
	var/distinct_category_target = 0
	var/minimum_fact_value = 0
	var/maximum_fact_value = INFINITY
	var/maximum_category_value = INFINITY
	var/datum/contract_event_filter/filter
	var/list/facts
	var/list/fact_revisions

/datum/contract_requirement/fact_portfolio/New(_event_type, _target, _category_field, _value_field, _distinct_category_target = 0, _scope_mode = CONTRACT_EVIDENCE_SCOPE_ANY)
	. = ..()
	event_type = _event_type
	target = max(1, _target)
	category_field = _category_field
	value_field = _value_field
	distinct_category_target = max(0, _distinct_category_target)
	filter = new(_scope_mode)
	facts = list()
	fact_revisions = list()
	if(event_type)
		event_types += event_type

/datum/contract_requirement/fact_portfolio/Destroy()
	QDEL_NULL(filter)
	facts = null
	fact_revisions = null
	return ..()

/datum/contract_requirement/fact_portfolio/proc/require_value(key, expected)
	return filter.require_value(key, expected)

/datum/contract_requirement/fact_portfolio/proc/forbid_value(key, forbidden)
	return filter.forbid_value(key, forbidden)

/datum/contract_requirement/fact_portfolio/proc/require_tag(tag)
	return filter.require_tag(tag)

/datum/contract_requirement/fact_portfolio/proc/require_number(key, comparator, expected)
	return filter.require_number(key, comparator, expected)

/datum/contract_requirement/fact_portfolio/handle_event(datum/contract_event/event)
	if(!(state in list(CONTRACT_REQUIREMENT_PENDING, CONTRACT_REQUIREMENT_COMPLETE)) || event?.event_type != event_type || !filter.matches(event, contract))
		return FALSE
	var/fact_value = event.value(fact_field)
	var/revision = event.value(revision_field)
	if(isnull(fact_value) || !isnum(revision))
		return FALSE
	var/fact_key = "[fact_value]"
	if(!isnull(fact_revisions[fact_key]) && fact_revisions[fact_key] >= revision)
		return FALSE
	fact_revisions[fact_key] = revision
	if(!event.value(active_field))
		facts -= fact_key
		return recalculate_portfolio(event)
	var/category_value = category_field ? event.value(category_field) : fact_key
	var/amount = value_field ? event.value(value_field) : 1
	if(isnull(category_value) || !isnum(amount) || amount < minimum_fact_value)
		facts -= fact_key
		return recalculate_portfolio(event)
	facts[fact_key] = list(
		"category" = "[category_value]",
		"value" = min(amount, maximum_fact_value),
	)
	return recalculate_portfolio(event)

/datum/contract_requirement/fact_portfolio/proc/recalculate_portfolio(datum/contract_event/event)
	var/list/category_totals = list()
	for(var/fact_key in facts)
		var/list/fact = facts[fact_key]
		var/category = fact["category"]
		category_totals[category] = min(maximum_category_value, (category_totals[category] || 0) + fact["value"])
	var/aggregate = 0
	for(var/category in category_totals)
		aggregate += category_totals[category]
	var/old_progress = progress
	progress = min(target, aggregate)
	state = progress >= target && length(category_totals) >= distinct_category_target ? CONTRACT_REQUIREMENT_COMPLETE : CONTRACT_REQUIREMENT_PENDING
	if(progress > old_progress)
		contract?.record_contribution(event.value(contributor_field), progress - old_progress, event.value("detail"))
	if(progress != old_progress)
		contract?.audit(CONTRACT_AUDIT_PROGRESS, "[name]: [progress]/[target], [length(category_totals)]/[distinct_category_target] categories")
	contract?.reconcile_completion()
	return progress != old_progress

/datum/contract_requirement/fact_portfolio/progress_text()
	return "[progress] / [target]; [portfolio_category_count()] / [distinct_category_target] categories"

/datum/contract_requirement/fact_portfolio/proc/portfolio_category_count()
	var/list/categories = list()
	for(var/fact_key in facts)
		var/list/fact = facts[fact_key]
		categories[fact["category"]] = TRUE
	return length(categories)
