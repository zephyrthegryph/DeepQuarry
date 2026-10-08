/**
 * Native machinery/atmos/power snapshot. The retired interaction-only query
 * silently returned empty rows once these types moved to ops. Reuse the native
 * pin capture, including held bindings, menu refusals, click selection, wires,
 * deterministic per-type seeds and per-target ownership cleanup.
 */
/datum/unit_test/dq_interaction_domain_snapshot/i7_bulk
	parent_type = /datum/unit_test/dq_conversion_pin

/datum/unit_test/dq_interaction_domain_snapshot/i7_bulk/snapshot_directory()
	return "code/modules/unit_tests/snapshots/i7_bulk/"

/datum/unit_test/dq_interaction_domain_snapshot/i7_bulk/snapshot_name()
	return "i7_bulk"

/datum/unit_test/dq_interaction_domain_snapshot/i7_bulk/Run()
	var/list/bad = list()
	var/list/recorded = dq_snapshot_read_dir(snapshot_directory(), bad)
	TEST_ASSERT(length(recorded) > 0, "The native machinery snapshot has real recorded types to compare")
	..()
