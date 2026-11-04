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
