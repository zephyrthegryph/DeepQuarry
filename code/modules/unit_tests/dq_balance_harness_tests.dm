// The balance harness (code/modules/balance): every scenario runs without a
// runtime and records every key it promises. The run also writes the baseline
// results to data/balance/results.json.

/datum/unit_test/dq_balance_harness

/datum/unit_test/dq_balance_harness/Run()
	var/list/document = run_balance_harness()
	var/list/scenarios = document["scenarios"]
	TEST_ASSERT_EQUAL(length(scenarios), length(balance_scenario_ids()), "every balance scenario should report")
	for(var/scenario_id in scenarios)
		var/list/entry = scenarios[scenario_id]
		TEST_ASSERT_EQUAL(entry["status"], "passed", "balance scenario [scenario_id] failed: [entry["error"]]")
		TEST_ASSERT_EQUAL(entry["runtimes"], 0, "balance scenario [scenario_id] raised [entry["runtimes"]] runtime(s)")
		var/list/missing = entry["missing_keys"]
		TEST_ASSERT(!length(missing), "balance scenario [scenario_id] left [length(missing)] key(s) unrecorded: [jointext(missing.Copy(1, min(length(missing), 10) + 1), ", ")]")
		TEST_ASSERT(length(entry["results"]), "balance scenario [scenario_id] recorded nothing")
