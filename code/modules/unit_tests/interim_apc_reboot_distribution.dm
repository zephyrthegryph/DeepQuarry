/// The real APC reboot resets distribution and charging state while preserving its actual installed cell and stored energy.
/datum/unit_test/interim_apc_reboot_distribution/Run()
	var/obj/machinery/power/apc/apc = interim_apc_make(run_loc_floor_bottom_left)
	var/obj/item/cell/cell = apc.cell
	TEST_ASSERT_NOTNULL(cell, "the actual APC has its installed cell")
	cell.charge = cell.maxcharge / 2
	var/charge_before = cell.charge
	apc.lighting = POWERCHAN_OFF
	apc.equipment = POWERCHAN_ON
	apc.environ = POWERCHAN_OFF_AUTO
	apc.set_operating(TRUE)
	apc.set_chargemode(FALSE)
	apc.charging = 2
	apc.chargecount = 7
	apc.longtermpower = -1
	apc.main_status = APC_EXTERNAL_POWER_GOOD
	apc.energy_fail(3) // This API counts machine-service intervals, rather than deciseconds.
	TEST_ASSERT(apc.failure_left() > 0, "the actual power-failure entry establishes a pending failure")
	TEST_ASSERT(hold_left(apc, STAT_OPERABLE, SRC_POWER_FAILURE) > 0, "the actual failure has an outstanding revert")
	apc.reboot()
	TEST_ASSERT_EQUAL(apc.lighting, POWERCHAN_ON_AUTO, "actual reboot restores lighting to automatic on")
	TEST_ASSERT_EQUAL(apc.equipment, POWERCHAN_ON_AUTO, "actual reboot restores equipment to automatic on")
	TEST_ASSERT_EQUAL(apc.environ, POWERCHAN_ON_AUTO, "actual reboot restores environment to automatic on")
	TEST_ASSERT(!apc.operating, "actual reboot leaves the breaker off")
	TEST_ASSERT(apc.chargemode, "actual reboot restores charge mode")
	TEST_ASSERT_EQUAL(apc.charging, 0, "actual reboot clears active charging status")
	TEST_ASSERT_EQUAL(apc.chargecount, 0, "actual reboot clears the charging count")
	TEST_ASSERT_EQUAL(apc.longtermpower, 10, "actual reboot resets the distribution's long-term power allowance")
	TEST_ASSERT_EQUAL(apc.main_status, APC_EXTERNAL_POWER_NOTCONNECTED, "actual reboot clears the previously good external-power status")
	TEST_ASSERT(!apc.failure_left(), "actual reboot clears the current power failure")
	TEST_ASSERT_NULL(hold_left(apc, STAT_OPERABLE, SRC_POWER_FAILURE), "actual reboot cancels the outstanding failure revert")
	TEST_ASSERT_EQUAL(apc.cell, cell, "actual reboot retains the same installed cell")
	TEST_ASSERT_EQUAL(cell.loc, apc, "actual reboot preserves physical cell containment")
	TEST_ASSERT_EQUAL(cell.charge, charge_before, "actual reboot does not spend or grant stored cell charge")
