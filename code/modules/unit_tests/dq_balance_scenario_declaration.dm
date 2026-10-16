// What a balance scenario owns. The harness (code/modules/balance/_balance_harness.dm) is compiled only in a test build but lives outside the
// folders the declaration generator treats as test-only, so its CAPABILITIES block sits here, where the generator guards it with the test build.

CAPABILITIES(/datum/balance_scenario)
	owns_many(nameof(spawned))
