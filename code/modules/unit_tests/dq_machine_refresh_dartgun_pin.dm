// One exact old-code capture for the remaining native refresh host.
/datum/unit_test/dq_conversion_pin/machine_refresh_dartgun
	tier = TEST_TIER_NORMAL
	capture_roots = list(/obj/item/gun/projectile/dartgun)

/datum/unit_test/dq_conversion_pin/machine_refresh_dartgun/snapshot_name()
	return "machine_refresh_dartgun"

/datum/unit_test/dq_conversion_pin/machine_refresh_dartgun/snapshot_directory()
	return "code/modules/unit_tests/snapshots/machine_refresh_dartgun/"
