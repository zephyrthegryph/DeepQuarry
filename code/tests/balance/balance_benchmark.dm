// The `balance` benchmark: runs the balance harness inside a -DBENCHMARK world
// so `tools/build/build.sh balance` can boot it like any benchmark. The harness
// writes data/balance/results.json itself; this scenario only reports status.
// Options: `--arg scenarios=ttk,bleedout` runs a subset.

/datum/benchmark/balance
	id = "balance"
	description = "Medical and combat balance harness (code/modules/balance)"

/datum/benchmark/balance/Run()
	wait_for_assets()
	var/requested_text = param("scenarios", "")
	var/list/requested = length(requested_text) ? splittext(requested_text, ",") : list()
	var/list/document = run_balance_harness(requested)
	var/list/scenarios = document["scenarios"]
	var/failed = 0
	for(var/scenario_id in scenarios)
		var/list/entry = scenarios[scenario_id]
		metric("[scenario_id]_results", length(entry["results"]), "values", "none")
		metric("[scenario_id]_seconds", entry["duration_seconds"], "s", "none")
		if(entry["status"] != "passed" || length(entry["missing_keys"]))
			failed++
	if(failed)
		fail("[failed] balance scenario(s) failed or left keys missing; see data/balance/results.json")
