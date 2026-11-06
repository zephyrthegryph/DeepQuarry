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
