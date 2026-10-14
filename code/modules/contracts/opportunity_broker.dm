/// Generic event-driven opportunity broker.
///
/// Rules consume only validated events from SScontracts.publish_event(). Each
/// rule keeps a bounded rolling window of revision-aware facts. A contract is
/// queued only after every signal lane meets its value, fact-count, actor, and
/// diversity thresholds. Trigger evidence predates acceptance and therefore
/// can never satisfy the resulting contract.

/datum/contract_opportunity_observation
	var/fact_key
	var/revision = 0
	EXPIRY_DECLARE(occurred_at)
	var/value = 0
	var/actor_key
	var/list/diversity_values

/datum/contract_opportunity_observation/New(_fact_key, datum/contract_event/event, datum/contract_opportunity_signal/signal)
	. = ..()
	fact_key = _fact_key
	revision = event.fact_revision
	occurred_at = event.occurred_at
	value = signal.event_value(event)
	actor_key = event.value(signal.actor_field) || event.source_ref || event.value("producer_id")
	diversity_values = list()
	for(var/field in signal.diversity_targets)
		diversity_values[field] = event.value(field)

/// One independently required lane in a broker rule. A rule may combine
/// unrelated systems (for example, production plus real crew sales) without a
/// bespoke callback or polling loop.
/datum/contract_opportunity_signal
	var/id
	var/event_type
	var/target = 1
	var/value_field
	var/aggregation = CONTRACT_OPPORTUNITY_AGGREGATE_SUM
	var/minimum_facts = 1
	var/actor_field = "actor_account"
	var/minimum_actors = 0
	var/maximum_fact_value = 0
	var/maximum_actor_value = 0
	var/require_station_source = FALSE
	var/datum/contract_event_filter/filter
	/// field -> minimum number of distinct values
	var/list/diversity_targets

CAPABILITIES(/datum/contract_opportunity_signal)
	owns_one(nameof(filter), /datum/contract_event_filter)

/datum/contract_opportunity_signal/New(_id, _event_type, _target = 1, _value_field = null)
	. = ..()
	id = _id
	event_type = _event_type
	target = _target
	value_field = _value_field
	rel_set(src, nameof(filter), new /datum/contract_event_filter)
	diversity_targets = list()


/datum/contract_opportunity_signal/proc/require_value(key, expected)
	return filter.require_value(key, expected)

/datum/contract_opportunity_signal/proc/forbid_value(key, forbidden)
	return filter.forbid_value(key, forbidden)

/datum/contract_opportunity_signal/proc/require_number(key, comparator, expected)
	return filter.require_number(key, comparator, expected)

/datum/contract_opportunity_signal/proc/require_diversity(field, count)
	if(!istext(field) || !length(field) || !isnum(count) || count < 1)
		return FALSE
	diversity_targets[field] = round(count)
	return TRUE

/datum/contract_opportunity_signal/proc/event_matches(datum/contract_event/event)
	if(event?.event_type != event_type)
		return FALSE
	if(require_station_source)
		if(!event.z || !(event.z in using_map.station_levels))
			return FALSE
	for(var/key in filter.exact_values)
		if(event.value(key) != filter.exact_values[key])
			return FALSE
	for(var/key in filter.forbidden_values)
		if(event.value(key) == filter.forbidden_values[key])
			return FALSE
	for(var/tag in filter.required_tags)
		if(!(tag in event.tags))
			return FALSE
	for(var/list/check as anything in filter.numeric_checks)
		if(!contract_evidence_compare(event.value(check["key"]), check["comparator"], check["expected"]))
			return FALSE
	return TRUE

/datum/contract_opportunity_signal/proc/event_value(datum/contract_event/event)
	var/measured = value_field ? event.value(value_field) : 1
	if(!isnum(measured) || measured <= 0)
		return 0
	if(maximum_fact_value > 0)
		measured = min(measured, maximum_fact_value)
	return measured

/// A bucket is normally station-wide. Rules may instead bucket by a stable
/// event field, such as the principal account behind covert market activity.
/datum/contract_opportunity_window
	var/key
	var/bucket
	EXPIRY_DECLARE(created_at)
	EXPIRY_DECLARE(last_event_at)
	var/latched = FALSE
	var/list/facts_by_signal
	/// Owns the records indexed by facts_by_signal; the nested maps retain their lookup order.
	var/list/observations
	/// The last event that revised this window during an open batch (a relation; damage_batch.dm).
	var/datum/contract_event/batch_event

CAPABILITIES(/datum/contract_opportunity_window)
	ref_one(nameof(batch_event), /datum/contract_event)
	owns_many(nameof(observations), /datum/contract_opportunity_observation)

/datum/contract_opportunity_window/New(_key, _bucket, datum/contract_opportunity_rule/rule)
	. = ..()
	key = _key
	bucket = _bucket
	EXPIRY_STAMP(src, created_at, CLOCK_WORLD)
	EXPIRY_STAMP(src, last_event_at, CLOCK_WORLD)
	facts_by_signal = list()
	for(var/datum/contract_opportunity_signal/signal in rule.signals)
		facts_by_signal[signal.id] = list()

// its facts (nested per signal) go with it.
/datum/contract_opportunity_window/on_destroy(force)
	for(var/signal_id in facts_by_signal)
		var/list/facts = facts_by_signal[signal_id]
		for(var/fact_key in facts)
			rel_remove(src, nameof(observations), facts[fact_key])
	..()

/datum/contract_opportunity_window/proc/prune(datum/contract_opportunity_rule/rule)
	var/cutoff = world.time - rule.window_duration
	for(var/datum/contract_opportunity_signal/signal in rule.signals)
		var/list/facts = facts_by_signal[signal.id]
		for(var/fact_key in facts.Copy())
			var/datum/contract_opportunity_observation/observation = facts[fact_key]
			if(observation.occurred_at >= cutoff)
				continue
			facts -= fact_key
			rel_remove(src, nameof(observations), observation)

/datum/contract_opportunity_window/proc/revise(datum/contract_opportunity_signal/signal, datum/contract_event/event)
	var/stable_fact_id = event.fact_id || event.occurrence_id
	if(!stable_fact_id)
		return FALSE
	var/fact_key = "[event.event_type]|[stable_fact_id]"
	var/list/facts = facts_by_signal[signal.id]
	var/datum/contract_opportunity_observation/previous = facts[fact_key]
	if(previous)
		if(event.fact_revision > 0 && event.fact_revision <= previous.revision)
			return FALSE
		if(event.fact_revision <= 0)
			return FALSE
		facts -= fact_key
		rel_remove(src, nameof(observations), previous)
	EXPIRY_STAMP(src, last_event_at, CLOCK_WORLD)
	if(!event.fact_active || !signal.event_matches(event))
		return TRUE
	facts[fact_key] = rel_add(src, nameof(observations), new /datum/contract_opportunity_observation(fact_key, event, signal))
	while(length(facts) > CONTRACT_OPPORTUNITY_FACT_LIMIT)
		var/oldest_key
		var/oldest_time = INFINITY
		for(var/candidate_key in facts)
			var/datum/contract_opportunity_observation/candidate = facts[candidate_key]
			if(candidate.occurred_at < oldest_time)
				oldest_key = candidate_key
				oldest_time = candidate.occurred_at
		var/datum/contract_opportunity_observation/expired = facts[oldest_key]
		facts -= oldest_key
		rel_remove(src, nameof(observations), expired)
	return TRUE

/datum/contract_opportunity_window/proc/signal_snapshot(datum/contract_opportunity_signal/signal)
	var/list/facts = facts_by_signal[signal.id]
	var/list/actor_totals = list()
	var/anonymous_total = 0
	var/maximum_value = 0
	var/list/distinct_by_field = list()
	for(var/field in signal.diversity_targets)
		distinct_by_field[field] = list()
	for(var/fact_key in facts)
		var/datum/contract_opportunity_observation/observation = facts[fact_key]
		maximum_value = max(maximum_value, observation.value)
		if(observation.actor_key)
			actor_totals["[observation.actor_key]"] = (actor_totals["[observation.actor_key]"] || 0) + observation.value
		else
			anonymous_total += observation.value
		for(var/field in signal.diversity_targets)
			var/distinct_value = observation.diversity_values[field]
			if(!isnull(distinct_value))
				var/list/field_values = distinct_by_field[field]
				field_values["[distinct_value]"] = TRUE
	var/aggregate = anonymous_total
	for(var/actor_key in actor_totals)
		var/actor_value = actor_totals[actor_key]
		aggregate += signal.maximum_actor_value > 0 ? min(actor_value, signal.maximum_actor_value) : actor_value
	if(signal.aggregation == CONTRACT_OPPORTUNITY_AGGREGATE_MAX)
		aggregate = maximum_value
	var/list/distinct_counts = list()
	var/list/distinct_values = list()
	var/diversity_satisfied = TRUE
	for(var/field in signal.diversity_targets)
		var/list/field_values = distinct_by_field[field]
		distinct_counts[field] = length(field_values)
		distinct_values[field] = field_values.Copy()
		if(length(field_values) < signal.diversity_targets[field])
			diversity_satisfied = FALSE
	var/satisfied = aggregate >= signal.target && length(facts) >= signal.minimum_facts && length(actor_totals) >= signal.minimum_actors && diversity_satisfied
	return list(
		"value" = aggregate,
		"facts" = length(facts),
		"actors" = length(actor_totals),
		"diversity" = distinct_counts,
		"values" = distinct_values,
		"satisfied" = satisfied,
	)

/datum/contract_opportunity_rule
	abstract_type = /datum/contract_opportunity_rule
	var/id
	var/definition_id
	var/description = "Authoritative station telemetry identified a new commission."
	var/window_duration = CONTRACT_OPPORTUNITY_DEFAULT_WINDOW
	var/cooldown = CONTRACT_OPPORTUNITY_DEFAULT_COOLDOWN
	var/reset_ratio = CONTRACT_OPPORTUNITY_RESET_RATIO
	var/bucket_field
	var/priority = 70
	var/list/signals
	/// event field -> offer-context field
	var/list/context_fields

CAPABILITIES(/datum/contract_opportunity_rule)
	owns_many(nameof(signals))

/datum/contract_opportunity_rule/New()
	. = ..()
	rel_take_all(src, nameof(signals))
	context_fields = list()
	configure()


/datum/contract_opportunity_rule/proc/configure()
	return

/datum/contract_opportunity_rule/proc/add_signal(datum/contract_opportunity_signal/signal)
	if(!signal?.id || !signal.event_type)
		spent(signal)
		return null
	for(var/datum/contract_opportunity_signal/existing in signals)
		if(existing.id == signal.id)
			spent(signal)
			return null
	rel_add(src, nameof(signals), signal)
	return signal

/datum/contract_opportunity_rule/proc/forward_context(event_field, context_field = null)
	if(!istext(event_field) || !length(event_field))
		return FALSE
	context_fields[event_field] = context_field || event_field
	return TRUE

/datum/contract_opportunity_rule/proc/bucket_for(datum/contract_event/event)
	var/bucket_value = bucket_field ? event.value(bucket_field) : "station"
	return isnull(bucket_value) ? null : "[bucket_value]"

/datum/contract_opportunity_rule/proc/window_key(bucket)
	return "[id]|[bucket]"

/datum/contract_opportunity_rule/proc/snapshots(datum/contract_opportunity_window/window)
	var/list/result = list()
	for(var/datum/contract_opportunity_signal/signal in signals)
		result[signal.id] = window.signal_snapshot(signal)
	return result

/datum/contract_opportunity_rule/proc/is_ready(list/signal_snapshots)
	if(!length(signals))
		return FALSE
	for(var/datum/contract_opportunity_signal/signal in signals)
		var/list/snapshot = signal_snapshots[signal.id]
		if(!snapshot?["satisfied"])
			return FALSE
	return TRUE

/datum/contract_opportunity_rule/proc/should_reset(list/signal_snapshots)
	for(var/datum/contract_opportunity_signal/signal in signals)
		var/list/snapshot = signal_snapshots[signal.id]
		if((snapshot?["value"] || 0) < signal.target * reset_ratio)
			return TRUE
	return FALSE

/datum/contract_opportunity_rule/proc/trigger(datum/system/contracts/controller, datum/contract_opportunity_window/window, datum/contract_event/event, list/signal_snapshots)
	var/list/context = list(
		"offer_kind" = CONTRACT_OFFER_OPPORTUNITY,
		"opportunity_rule" = id,
		"opportunity_bucket" = window.bucket,
		"opportunity_triggered_at" = EXPIRY_AT(null, CLOCK_WORLD, 0),
		"trigger_event_id" = event.id,
		"trigger_area" = event.area_name,
		"trigger_signals" = deepCopyList(signal_snapshots),
	)
	var/list/trigger_values = list()
	for(var/signal_id in signal_snapshots)
		var/list/snapshot = signal_snapshots[signal_id]
		var/list/values = snapshot?["values"]
		for(var/field in values)
			LAZYINITLIST(trigger_values[field])
			var/list/field_values = trigger_values[field]
			field_values |= values[field]
	context["trigger_values"] = trigger_values
	for(var/event_field in context_fields)
		context[context_fields[event_field]] = event.value(event_field)
	var/offer_key = "opportunity:[id]:[window.bucket]"
	var/datum/contract/queued = controller.queue_offer(definition_id, context, description, offer_key, priority)
	return !!queued || !!controller.find_live_offer(offer_key) || !!controller.find_candidate(offer_key)

/datum/contract_opportunity_history_entry
	EXPIRY_DECLARE(time)
	var/rule_id
	var/bucket
	var/event_id
	var/offer_key
	var/list/snapshots

/datum/contract_opportunity_history_entry/New(datum/contract_opportunity_rule/rule, datum/contract_opportunity_window/window, datum/contract_event/event, list/_snapshots)
	. = ..()
	EXPIRY_STAMP(src, time, CLOCK_WORLD)
	rule_id = rule.id
	bucket = window.bucket
	event_id = event.id
	offer_key = "opportunity:[rule.id]:[window.bucket]"
	snapshots = deepCopyList(_snapshots)

// --------------------------------------------------------------------------
// Broker rules
// --------------------------------------------------------------------------

/datum/contract_opportunity_rule/infrastructure_incident
	id = "infrastructure_incident"
	definition_id = "emergency_reconstruction_bond"
	description = "Distributed integrity telemetry identified a multi-asset station incident requiring reconstruction."
	window_duration = 5 MINUTES
	priority = 95

/datum/contract_opportunity_rule/infrastructure_incident/configure()
	var/datum/contract_opportunity_signal/damage = add_signal(new /datum/contract_opportunity_signal("damage", CONTRACT_EVENT_INFRASTRUCTURE_DAMAGED, 600, "damage_amount"))
	damage.minimum_facts = 4
	damage.maximum_fact_value = 250
	damage.require_station_source = TRUE
	damage.require_diversity("atom_id", 4)
	// Capture a readable asset roster for the resulting incident contract.
	damage.require_diversity("asset_label", 1)
	damage.require_diversity("area_name", 2)

/datum/contract_opportunity_rule/power_disruption
	id = "power_disruption"
	definition_id = "opportunity_grid_restoration"
	description = "Independent APC telemetry identified a distributed loss of electrical service."
	window_duration = 4 MINUTES
	priority = 90

/datum/contract_opportunity_rule/power_disruption/configure()
	var/datum/contract_opportunity_signal/outages = add_signal(new /datum/contract_opportunity_signal("outages", CONTRACT_EVENT_POWER_SERVICE_CHANGED, 4))
	outages.minimum_facts = 4
	outages.require_station_source = TRUE
	outages.require_value("operational", FALSE)
	outages.require_diversity("service_id", 4)
	outages.require_diversity("area_name", 3)

/datum/contract_opportunity_rule/atmos_disruption
	id = "atmos_disruption"
	definition_id = "opportunity_atmos_containment"
	description = "Independent air-alarm zones reported a distributed atmospheric incident."
	window_duration = 4 MINUTES
	priority = 92

/datum/contract_opportunity_rule/atmos_disruption/configure()
	var/datum/contract_opportunity_signal/unsafe_zones = add_signal(new /datum/contract_opportunity_signal("unsafe_zones", CONTRACT_EVENT_ATMOS_SERVICE_CHANGED, 3))
	unsafe_zones.minimum_facts = 3
	unsafe_zones.require_station_source = TRUE
	unsafe_zones.require_number("danger_level", CONTRACT_EVIDENCE_COMPARE_GREATER, 0)
	unsafe_zones.require_diversity("service_id", 3)
	unsafe_zones.require_diversity("area_name", 2)

/datum/contract_opportunity_rule/medical_caseload
	id = "medical_caseload"
	definition_id = "opportunity_clinical_aftercare"
	description = "A diverse clinical caseload created a sponsored aftercare opportunity."
	window_duration = 12 MINUTES

/datum/contract_opportunity_rule/medical_caseload/configure()
	var/datum/contract_opportunity_signal/outcomes = add_signal(new /datum/contract_opportunity_signal("outcomes", CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, 150, "improvement"))
	outcomes.minimum_facts = 4
	outcomes.maximum_fact_value = 50
	outcomes.maximum_actor_value = 75
	outcomes.require_station_source = TRUE
	outcomes.require_number("improvement", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 5)
	outcomes.require_diversity("subject_id", 3)
	outcomes.require_diversity("condition_type", 2)

/datum/contract_opportunity_rule/research_breakthrough
	id = "research_breakthrough"
	definition_id = "opportunity_equipment_deployment"
	description = "A cluster of distinct research milestones attracted a translation grant."
	window_duration = 15 MINUTES

/datum/contract_opportunity_rule/research_breakthrough/configure()
	var/datum/contract_opportunity_signal/milestones = add_signal(new /datum/contract_opportunity_signal("milestones", CONTRACT_EVENT_RESEARCH_MILESTONE, 4500, "point_cost"))
	milestones.minimum_facts = 3
	milestones.maximum_fact_value = 2500
	milestones.require_station_source = TRUE
	milestones.require_diversity("node_id", 3)

/datum/contract_opportunity_rule/security_caseload
	id = "security_caseload"
	definition_id = "opportunity_case_review"
	description = "A varied docket of physically grounded cases created an independent review commission."
	window_duration = 15 MINUTES

/datum/contract_opportunity_rule/security_caseload/configure()
	var/datum/contract_opportunity_signal/cases = add_signal(new /datum/contract_opportunity_signal("cases", CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, 4))
	cases.minimum_facts = 4
	cases.require_value("physical_custody_verified", TRUE)
	cases.require_diversity("record_id", 4)
	cases.require_diversity("physical_subject_id", 3)

/datum/contract_opportunity_rule/covert_trade_trace
	id = "covert_trade_trace"
	description = "Correlated encrypted market traces crossed the Internal Security review threshold."
	bucket_field = "principal_account"
	window_duration = 30 MINUTES
	cooldown = 30 MINUTES
	priority = 100

/datum/contract_opportunity_rule/covert_trade_trace/configure()
	var/datum/contract_opportunity_signal/exposure = add_signal(new /datum/contract_opportunity_signal("exposure", CONTRACT_EVENT_COVERT_MARKET_ACTIVITY, FACTION_AGENT_COUNTER_OFFER_THRESHOLD, "exposure"))
	exposure.aggregation = CONTRACT_OPPORTUNITY_AGGREGATE_MAX
	exposure.minimum_facts = 2
	exposure.require_diversity("transaction_id", 2)

/datum/contract_opportunity_rule/covert_trade_trace/trigger(datum/system/contracts/controller, datum/contract_opportunity_window/window, datum/contract_event/event, list/signal_snapshots)
	var/suspect_account = event.value("principal_account")
	var/datum/faction_agent_record/record = GLOB.station_faction_relations?.get_agent_record(suspect_account)
	if(!record || record.counter_offer_queued)
		return !!record?.counter_offer_queued
	controller.queue_covert_market_investigation(suspect_account)
	var/offer_key = "covert-investigation:[suspect_account]"
	record.counter_offer_queued = !!controller.find_live_offer(offer_key) || !!controller.find_candidate(offer_key)
	return record.counter_offer_queued

/datum/contract_opportunity_rule/supply_shortage
	id = "supply_shortage"
	definition_id = "supply_shortage_response"
	description = "A live NanoTrasen supply-shortage request created a response opportunity."
	bucket_field = "shortage_id"
	window_duration = 1 HOUR
	cooldown = 1 HOUR
	priority = 95

/datum/contract_opportunity_rule/supply_shortage/configure()
	var/datum/contract_opportunity_signal/declaration = add_signal(new /datum/contract_opportunity_signal("declaration", CONTRACT_EVENT_SUPPLY_SHORTAGE_DECLARED, 1))
	declaration.maximum_fact_value = 1
	forward_context("shortage_id")
	forward_context("quantity_target")
	forward_context("variety_target")

/datum/contract_opportunity_rule/budget_performance
	id = "budget_performance"
	definition_id = "opportunity_operational_dividend"
	description = "A broadly funded payroll cycle qualified the station for an operational dividend mandate."
	window_duration = 20 MINUTES
	cooldown = 30 MINUTES

/datum/contract_opportunity_rule/budget_performance/configure()
	var/datum/contract_opportunity_signal/cycle = add_signal(new /datum/contract_opportunity_signal("cycle", CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 1))
	cycle.require_value("rollup", "station")
	cycle.require_number("payroll_coverage", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 0.9)
	cycle.require_number("funded_department_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 6)
	cycle.require_number("funded_allocation_total", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 20000)
