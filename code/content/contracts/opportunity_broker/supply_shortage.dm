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
