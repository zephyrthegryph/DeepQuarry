// Recorded on unconverted master before changing custom requirement semantics.
/datum/unit_test/dq_requirement_protocol_pin
	parent_type = /datum/unit_test/dq_conversion_pin

/datum/unit_test/dq_requirement_protocol_pin/snapshot_directory()
	return "code/modules/unit_tests/snapshots/requirements_protocol_1008/"

/datum/unit_test/dq_requirement_protocol_pin/snapshot_name()
	return "requirements_protocol_1008"

// Validate the legacy medical card bridge before its separate conversion.
/datum/unit_test/dq_medical_capability_pin
	parent_type = /datum/unit_test/dq_conversion_pin

/datum/unit_test/dq_medical_capability_pin/New()
	..()
	capture_roots = list(/obj/machinery/computer/med_data)
