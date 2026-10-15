// Record the old user-visible result for both silicon providers before the
// entry-point migration. Metadata keys are covered by the ordinary conversion
// pins; these rows compare the actual menu/refusal and plain-click result.
/datum/unit_test/dq_conversion_pin/silicon_remote/snapshot_name()
	return "silicon_remote"

/datum/unit_test/dq_conversion_pin/silicon_remote/snapshot_directory()
	return "code/modules/unit_tests/snapshots/silicon_remote/"

/datum/unit_test/dq_conversion_pin/silicon_remote/dq_pin_lines(atom/target, turf/T, list/actors)
	var/list/all_rows = ..()
	. = list()
	var/ai_seen = FALSE
	var/borg_seen = FALSE
	for(var/row in all_rows)
		if(findtext(row, "ai|") == 1)
			ai_seen = TRUE
			. += row
		else if(findtext(row, "robot|") == 1)
			borg_seen = TRUE
			. += row
	TEST_ASSERT(ai_seen && borg_seen, "Each live [target.type] fixture records both real AI and cyborg inputs")
