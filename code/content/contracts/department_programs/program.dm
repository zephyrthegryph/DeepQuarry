/datum/contract_definition/social/program
	abstract_type = /datum/contract_definition/social/program
	expected_duration = 25 MINUTES
	max_simultaneous = 1
	var/station_reputation = 8
	var/department_reputation = 24
	var/staff_reputation = 12

/datum/contract_definition/social/program/configure_contract(datum/contract/social/contract, list/context)
	..()
	contract.deadline_duration = expected_duration
	configure_social_identity(contract, station_reputation, department_reputation, staff_reputation)
