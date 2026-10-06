// Medical and combat balance harness. It changes no gameplay numbers: it runs
// deterministic scenarios on throwaway test mobs through the real pipelines
// (injure_by() and the armour soak, Life(), afflictions, reagents, bellies,
// stasis) and reports what comes out, so people tuning balance can see the
// effect of a change. doc/balance_baseline.md holds the reference run.
//
// Scenarios are /datum/balance_scenario subtypes with an `id`. Each records
// flat numeric results through record() under keys it also lists from
// expected_keys(), built from the same tables, so a test can check that every
// number it promises is present. A value of null means "never happened within
// the scenario's time cap".
//
// Runs:
//  - the unit test /datum/unit_test/dq_balance_harness (every scenario);
//  - `tools/build/build.sh balance`, a -DBENCHMARK world whose `balance`
//    benchmark calls the same runner; `balance-compare` diffs two stored runs.
// Both write BALANCE_RESULTS_FILE.
//
// Time: every trial drives the life pipeline directly, one frame (BALANCE_LIFE_SECONDS) per cycle,
// without sleeping, so world.time stands still during a trial. Effects timed
// by world.time (support windows, modifier durations) therefore hold for the
// whole trial; interventions are re-applied at their normal cadence anyway,
// so they read as "done continuously and correctly". Every trial reseeds the
// RNG with BALANCE_SEED so repeated runs of the same code agree.

#define BALANCE_RESULTS_FILE "data/balance/results.json"
#define BALANCE_SEED 1337
#define BALANCE_LIFE_SECONDS LIFE_CYCLE_SECONDS

/datum/balance_scenario
	/// Scenario name used in results and on the command line. Types without an id are abstract.
	var/id
	var/description = ""
	/// Flat results: key -> number, or null for "never within the cap".
	var/list/results
	/// key -> unit text.
	var/list/units
	/// Free-text notes about what a run measured (assumptions, fallbacks).
	var/list/notes
	/// Where test mobs and items are spawned.
	var/tmp/turf/site
	/// Everything this scenario spawned, deleted by cleanup().
	var/list/spawned

/// Not in the main .dme, so it cannot carry a generated CAPABILITIES declaration: the table proc declares what it spawned.
/datum/balance_scenario/ownership()
	. = ..()
	. += owns(nameof(spawned), is_list = TRUE)

/datum/balance_scenario/on_destroy(force) // the scenario owns what it spawned; cleanup() removes it.
	cleanup()
	..()

/// The scenario body.
/datum/balance_scenario/proc/Run()
	return

/// Every key Run() records, built from the scenario's tables.
/datum/balance_scenario/proc/expected_keys()
	return list()

/// expected_keys() of each scenario type, built once. A scenario whose keys are a fixed list
/// overrides the table directly.
TYPE_TABLE_DECLARE(/datum/balance_scenario, balance_expected_keys, expected_keys())

/datum/balance_scenario/proc/record(key, value, unit = "")
	if(isnum(value))
		value = round(value, 0.01)
	LAZYSET(results, key, value)
	if(unit)
		LAZYSET(units, key, unit)

/datum/balance_scenario/proc/note(text)
	LAZYADD(notes, text)
	log_test("BALANCE [id]: [text]")

/// Spawns `type` at the scenario site and tracks it for cleanup.
/datum/balance_scenario/proc/spawn_thing(type)
	var/atom/movable/thing = new type(site)
	rel_add(src, nameof(spawned), thing)
	return thing

/// Deletes everything the scenario spawned (between trials and at the end).
/datum/balance_scenario/proc/cleanup()
	own_clear(src, nameof(spawned), OWN_DELETE)

/// Starts a trial: fresh RNG seed, nothing left over from the previous trial.
/datum/balance_scenario/proc/begin_trial()
	cleanup()
	rand_seed(BALANCE_SEED)

/// Down: unconscious or worse (or deleted, which some bodies do on death).
/datum/balance_scenario/proc/is_down(mob/living/L)
	return QDELETED(L) || L.stat != CONSCIOUS

/datum/balance_scenario/proc/is_dead(mob/living/L)
	return QDELETED(L) || L.stat == DEAD

/// One Life frame (one LIFE_CYCLE of the life pipeline), run now.
/datum/balance_scenario/proc/live(mob/living/L)
	if(!QDELETED(L))
		seq_run_frame_now(L, /datum/sequence/life)

/// A human's blood as a fraction of its species' normal volume, or null.
/datum/balance_scenario/proc/blood_fraction(mob/living/carbon/human/H)
	if(QDELETED(H) || !H.vessel || !H.species?.blood_volume)
		return null
	return H.vessel.get_reagent_amount(REAGENT_ID_BLOOD) / H.species.blood_volume

/datum/balance_scenario/proc/brain_of(mob/living/carbon/human/H)
	RETURN_TYPE(/obj/item/organ/internal/brain)
	if(QDELETED(H))
		return null
	return H.organ_in(O_BRAIN)

/// Everything wrong with a mob, as one number: injury load in every category
/// plus oxygen debt. Digestion may land as any of them.
/datum/balance_scenario/proc/total_injury(mob/living/L)
	. = 0
	if(QDELETED(L))
		return
	for(var/category in 1 to INJURY_CATEGORY_COUNT)
		. += L.injury_load(category)
	. += L.oxygen_debt()

/// A floor with breathable air for test mobs, or null.
/proc/balance_harness_site()
	for(var/turf/simulated/floor/T in world)
		var/datum/gas_mixture/air = T.return_air()
		if(!air)
			continue
		var/pressure = air.return_pressure()
		if(pressure > 90 && pressure < 120)
			return T
	return null

/// Every scenario id, in run order.
/proc/balance_scenario_ids()
	var/list/ids = list()
	for(var/datum/balance_scenario/path as anything in subtypesof(/datum/balance_scenario))
		if(initial(path.id))
			ids += initial(path.id)
	return ids

/proc/balance_scenario_type(scenario_id)
	for(var/datum/balance_scenario/path as anything in subtypesof(/datum/balance_scenario))
		if(initial(path.id) == scenario_id)
			return path
	return null

/// Runs the scenarios named in `requested` (all of them when empty), writes
/// BALANCE_RESULTS_FILE and returns the document. Each scenario reports its
/// status, runtimes, duration, results, units, notes and any missing keys.
/proc/run_balance_harness(list/requested, turf/site)
	if(!length(requested))
		requested = balance_scenario_ids()
	site ||= balance_harness_site()
	var/list/scenarios = list()
	log_test("BALANCE: harness starting: [jointext(requested, ", ")] at [site ? AREACOORD(site) : "no site"]")
	for(var/scenario_id in requested)
		var/list/entry = list("id" = scenario_id)
		scenarios[scenario_id] = entry
		var/path = balance_scenario_type(scenario_id)
		if(!path)
			entry["status"] = "unknown"
			entry["error"] = "No balance scenario '[scenario_id]'. Available: [jointext(balance_scenario_ids(), ", ")]"
			continue
		if(!site)
			entry["status"] = "failed"
			entry["error"] = "no breathable floor to run on"
			continue
		var/datum/balance_scenario/scenario = new path
		rel_set(scenario, nameof(scenario.site), site)
		entry["description"] = scenario.description
		var/runtimes_before = GLOB.total_runtimes
		var/start = REALTIMEOFDAY
		try
			scenario.Run()
			entry["status"] = "passed"
		catch(var/exception/error) // ALLOW(silent_catch): the failure is recorded in the scenario result entry
			entry["status"] = "failed"
			entry["error"] = "[error.name] ([error.file]:[error.line])"
		scenario.cleanup()
		entry["duration_seconds"] = (REALTIMEOFDAY - start) / 10
		entry["runtimes"] = GLOB.total_runtimes - runtimes_before
		var/list/results = scenario.results || list()
		var/list/missing = list()
		for(var/key in TYPE_TABLE_GET(scenario, balance_expected_keys))
			if(!(key in results))
				missing += key
		entry["missing_keys"] = missing
		entry["results"] = results
		entry["units"] = scenario.units || list()
		entry["notes"] = scenario.notes || list()
		log_test("BALANCE: [scenario_id] [entry["status"]] in [entry["duration_seconds"]]s: [length(results)] results, [length(missing)] missing, [entry["runtimes"]] runtimes[entry["error"] ? " ([entry["error"]])" : ""]")
		spent(scenario)
		CHECK_TICK
	var/list/document = list(
		"kind" = "balance",
		"byond_version" = "[world.byond_version].[world.byond_build]",
		"map" = using_map?.name,
		"seed" = BALANCE_SEED,
		"life_seconds" = BALANCE_LIFE_SECONDS,
		"scenarios" = scenarios,
	)
	fdel(BALANCE_RESULTS_FILE)
	text2file(json_encode(document), BALANCE_RESULTS_FILE)
	log_test("BALANCE: wrote [BALANCE_RESULTS_FILE]")
	return document

