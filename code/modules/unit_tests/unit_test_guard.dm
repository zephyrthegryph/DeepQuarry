// The leak guards' session (unit_test.dm judges every test with it). The whole-map baselines (air, floor temperatures, map machinery) are taken once for the run
// and kept current as tests end; a test is judged only on what it could have touched:
//   - air: the mixtures whose revision (the engine's own change counter) moved, found with one batched read of every revision;
//   - floors: the batched temperature read, compared turf by turf in one pass, no per-turf call into the engine;
//   - machines: those standing in the areas the test touched (where its air or floors changed, where its allocated things stood, where it declared air);
//   - a full compare of every watched machine every UNIT_TEST_FULL_COMPARE_EVERY tests (the `dq_guard_full_every` world param overrides it) and at the end of the run,
//     so a slow drift or a change made out of the touched areas is still caught, and named with the tests that ran since the last full compare.
// Areas, gravity and globals are cheap and are snapshotted per test as before.

/// How many tests may pass between full compares of the watched machines.
#define UNIT_TEST_FULL_COMPARE_EVERY 20

GLOBAL_DATUM(unit_test_guard, /datum/unit_test_guard)

/datum/unit_test_guard
	/// The air snapshot (unit_test_air_snapshot()) kept current as tests end.
	var/list/air
	/// The floor temperatures (unit_test_solid_snapshot()) kept current as tests end.
	var/list/solids
	/// Every watched machine's guarded settings, machine -> list(var name -> value), kept current as tests end.
	var/list/machine_state
	/// area -> the watched machines standing in it.
	var/list/machines_by_area
	/// Tests judged since the last full compare of the machines, by name.
	var/list/since_full = list()

/// The run's guard session, built on the first test (the only whole-map snapshot of the run).
/proc/unit_test_guard_session()
	if(GLOB.unit_test_guard)
		return GLOB.unit_test_guard
	var/datum/unit_test_guard/guard = new
	guard.air = unit_test_air_snapshot()
	guard.air["session"] = TRUE
	guard.solids = unit_test_solid_snapshot()
	guard.solids["session"] = TRUE
	guard.machine_state = unit_test_machine_snapshot()
	guard.machines_by_area = list()
	for(var/obj/machinery/M as anything in guard.machine_state)
		LAZYADD(guard.machines_by_area[get_area(M)], M)
	GLOB.unit_test_guard = guard
	return guard

/// A test starts: whatever the world did since the last one (the rooms drift by the second, a machine answers a pending wake) becomes the baseline, not the test's.
/datum/unit_test_guard/proc/begin()
	unit_test_air_refresh(air)
	unit_test_solid_refresh(solids)

/// The full-compare interval: the `dq_guard_full_every` world param, else UNIT_TEST_FULL_COMPARE_EVERY.
/proc/unit_test_full_compare_every()
	var/param = text2num(world.params["dq_guard_full_every"])
	return isnum(param) && param > 0 ? round(param) : UNIT_TEST_FULL_COMPARE_EVERY

/// The machines to judge after a test: the ones in `touched` (an area -> TRUE list), or every watched machine when it is time for the full compare. Logs and adds to
/// `found` each guarded setting that changed, then takes the machine's present settings as its baseline (a leak fails its test once, not every test after it).
/datum/unit_test_guard/proc/judge_machines(test_path, list/touched, list/found, force_full = FALSE, quiet = FALSE)
	if(!force_full)
		since_full += "[test_path]"
	var/full = force_full || length(since_full) >= unit_test_full_compare_every()
	var/list/judged = list()
	if(full)
		judged = machine_state
	else
		for(var/area/A as anything in touched)
			for(var/obj/machinery/M as anything in machines_by_area[A])
				judged[M] = TRUE
	var/who = full ? "[test_path] (the full compare after [length(since_full)] tests: [jointext(since_full, ", ")]; the leak is among these)" : "[test_path]"
	for(var/obj/machinery/M as anything in judged)
		if(QDELETED(M))
			continue
		var/list/was = machine_state[M]
		if(!was)
			continue
		for(var/name in was)
			if(M.vars[name] != was[name])
				var/text = "STATE LEAK: [who] left [M] ([M.type]) at ([M.x],[M.y],[M.z]) with [name] = [M.vars[name]] (was [was[name]]). Every later test sees the changed machine: set it through set_var() or put it back in the test."
				if(!quiet)
					log_test(text)
				found?.Add(text)
				was[name] = M.vars[name]
	if(full)
		since_full = list()

/// The end of the run: one last full compare of the watched machines against the session baseline. A change here is named with the tests since the last full compare.
/// Returns how many settings had changed.
/datum/unit_test_guard/proc/final_compare()
	var/list/found = list()
	if(length(since_full))
		judge_machines("the end of the run", null, found, TRUE)
	if(length(found))
		GLOB.failed_any_test = TRUE
	return length(found)

// ---- air ----

/// Indices of the snapshot's turfs whose mixture revision moved since the snapshot (one batched read of every revision, one pass). Leaves the new revisions in
/// snapshot["revs_now"].
/proc/unit_test_air_changed(list/snapshot)
	// A turf can be given a new air datum (the old handle then names nothing): the handles are looked up again each time, one pass over the watched turfs.
	snapshot["airs"] = unit_test_airs_of(snapshot["turfs"])
	var/list/now = vg_read_mixture_revisions(snapshot["airs"])
	var/list/was = snapshot["revs"]
	var/list/changed = list()
	for(var/i in 1 to length(now))
		if(now[i] != was[i])
			changed += i
	snapshot["revs_now"] = now
	return changed

/// Makes the snapshot current for the mixtures that changed (a between-test drift becomes the baseline): their readings, revisions and cold-room marks.
/proc/unit_test_air_refresh(list/snapshot)
	var/list/changed = unit_test_air_changed(snapshot)
	if(!length(changed))
		return
	var/list/airs = snapshot["airs"]
	var/list/sub = list()
	for(var/i in changed)
		sub += airs[i]
	unit_test_air_take(snapshot, changed, read_gas_mixtures(sub), null)

/// Copies the readings `now` (one record per index in `changed`) into the snapshot for every index except those in `keep` (an "index" -> TRUE list), updates the cold-room
/// marks, and takes the mixtures' present revisions.
/proc/unit_test_air_take(list/snapshot, list/changed, list/now, list/keep)
	var/list/readings = snapshot["readings"]
	var/list/turfs = snapshot["turfs"]
	var/list/skip = snapshot["skip"]
	var/list/airs = snapshot["airs"]
	var/list/revs = snapshot["revs"]
	var/list/sub = list()
	for(var/k in 1 to length(changed))
		var/i = changed[k]
		sub += airs[i]
		if(keep?["[i]"])
			continue
		var/was_off = (i - 1) * GAS_READ_STRIDE
		var/now_off = (k - 1) * GAS_READ_STRIDE
		for(var/j in 1 to GAS_READ_STRIDE)
			readings[was_off + j] = now[now_off + j]
		if(readings[was_off + GAS_READ_TOTAL_MOLES] > 0 && readings[was_off + GAS_READ_TEMPERATURE] < UNIT_TEST_SOLID_COLD_ROOM_KELVIN)
			skip[turfs[i]] = readings[was_off + GAS_READ_TEMPERATURE]
		else
			skip -= turfs[i]
	var/list/present = vg_read_mixture_revisions(sub)
	for(var/k in 1 to length(changed))
		revs[changed[k]] = present[k]

// ---- floors ----

/// Indices of the snapshot's turfs whose floor temperature differs from the snapshot's by more than a hundredth of a kelvin (one batched read, one pass). Leaves
/// the new temperatures in snapshot["now"].
/proc/unit_test_solid_changed(list/snapshot)
	var/list/now = vg_heat_turf_temperatures(snapshot["turfs"])
	var/list/was = snapshot["k"]
	var/list/changed = list()
	for(var/i in 1 to length(now))
		if(abs(now[i] - was[i]) > 0.01)
			changed += i
	snapshot["now"] = now
	return changed

/// Makes the snapshot current for the floors that changed.
/proc/unit_test_solid_refresh(list/snapshot)
	var/list/changed = unit_test_solid_changed(snapshot)
	var/list/was = snapshot["k"]
	var/list/now = snapshot["now"]
	for(var/i in changed)
		was[i] = now[i]
