// The balance harness (code/modules/balance): every scenario runs without a
// runtime and records every key it promises. The run also writes the baseline
// results to data/balance/results.json.

/datum/unit_test/dq_balance_harness
	tier = TEST_TIER_EXHAUSTIVE

/// The scenario ids to run; null runs every scenario.
/datum/unit_test/dq_balance_harness/proc/scenario_ids()
	return null

/// Normal tier: the quick scenarios (each a handful of Life cycles). The
/// many-trial ones (ttk, bleedout) run with the rest in CI and nightly.
/datum/unit_test/dq_balance_harness/representative
	tier = TEST_TIER_NORMAL

/datum/unit_test/dq_balance_harness/representative/scenario_ids()
	return list("baseline", "hypoxia", "stasis")

/datum/unit_test/dq_balance_harness/Run()
	var/list/requested = scenario_ids()
	var/list/document = run_balance_harness(requested)
	var/list/scenarios = document["scenarios"]
	TEST_ASSERT_EQUAL(length(scenarios), length(requested || balance_scenario_ids()), "every requested balance scenario should report")
	for(var/scenario_id in scenarios)
		var/list/entry = scenarios[scenario_id]
		TEST_ASSERT_EQUAL(entry["status"], "passed", "balance scenario [scenario_id] failed: [entry["error"]]")
		TEST_ASSERT_EQUAL(entry["runtimes"], 0, "balance scenario [scenario_id] raised [entry["runtimes"]] runtime(s)")
		var/list/missing = entry["missing_keys"]
		TEST_ASSERT(!length(missing), "balance scenario [scenario_id] left [length(missing)] key(s) unrecorded: [jointext(missing.Copy(1, min(length(missing), 10) + 1), ", ")]")
		TEST_ASSERT(length(entry["results"]), "balance scenario [scenario_id] recorded nothing")
