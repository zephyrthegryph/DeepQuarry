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
