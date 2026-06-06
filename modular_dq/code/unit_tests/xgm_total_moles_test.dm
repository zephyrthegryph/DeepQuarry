// xgm_total_moles compat helper tests.
//
// Verifies the helper proc that bridges XGM's `mix.total_moles` (var) and
// LINDA's `mix.total_moles()` (proc) for CHOMP callers that need to compile
// in both atmos engines. See modular_dq/code/__defines/atmospherics.dm.
//
// Run with: bin/test.cmd (or whatever invokes dm.exe with -DUNIT_TESTS).
//
// DQEdit — fork is LINDA-only; the historical #ifdef USE_LINDA_ATMOS branch
// has been collapsed.

/datum/unit_test/xgm_total_moles_helper

/datum/unit_test/xgm_total_moles_helper/Run()
	// 1. Helper handles null safely.
	TEST_ASSERT_EQUAL(xgm_total_moles(null), 0, "null mixture should return 0 moles")

	// 2. Helper returns 0 for an empty mixture.
	var/datum/gas_mixture/empty_mix = new(CELL_VOLUME)
	TEST_ASSERT_NOTNULL(empty_mix, "should construct an empty gas_mixture")
	TEST_ASSERT_EQUAL(xgm_total_moles(empty_mix), 0, "empty mixture has 0 total moles")

	// 3. Helper returns the actual molar sum after adding gas.
	// Use the GAS_O2 / GAS_N2 #defines (resolve to LINDA's "o2" / "n2"
	// strings) so the xgm_compat shim can look the gas type up — passing
	// raw "oxygen" / "nitrogen" misses because /datum/gas/oxygen.id is "o2".
	LINDA_GAS_ADJUST(empty_mix, GAS_O2, 5)
	TEST_ASSERT_EQUAL(xgm_total_moles(empty_mix), 5, "after adding 5 moles, total should be 5")

	// 4. Sum is additive across multiple gases.
	LINDA_GAS_ADJUST(empty_mix, GAS_N2, 3)
	TEST_ASSERT_EQUAL(xgm_total_moles(empty_mix), 8, "5 + 3 = 8 total moles")
