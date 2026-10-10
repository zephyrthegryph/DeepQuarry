/**
 * Native structures snapshot. The resolver query it recorded (every row empty: no structures type offered a resolver
 * entry) was retired with the interaction bridge; the same types are captured with the native pin capture
 * (menus, refusals, clicks, wires, op keys), as dq_i7_bulk_capture.dm does for machinery.
 */
/datum/unit_test/dq_interaction_domain_snapshot/i7_structures_bulk
	parent_type = /datum/unit_test/dq_conversion_pin

/datum/unit_test/dq_interaction_domain_snapshot/i7_structures_bulk/snapshot_directory()
	return "code/modules/unit_tests/snapshots/i7_structures_bulk/"

/datum/unit_test/dq_interaction_domain_snapshot/i7_structures_bulk/snapshot_name()
	return "i7_structures_bulk"
