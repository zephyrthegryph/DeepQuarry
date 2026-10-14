// The timed machinery wave captures its own old-code pins before any effects move.
// Keeping this directory separate makes the focused check independent of other lanes.
/datum/unit_test/dq_machinery_timed_conversion_pin
	parent_type = /datum/unit_test/dq_conversion_pin

/datum/unit_test/dq_machinery_timed_conversion_pin/snapshot_directory()
	return "code/modules/unit_tests/snapshots/machinery_timed_1008/"

/datum/unit_test/dq_machinery_timed_conversion_pin/snapshot_name()
	return "machinery_timed_1008"
