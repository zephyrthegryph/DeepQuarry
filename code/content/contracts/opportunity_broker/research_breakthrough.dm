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
