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
