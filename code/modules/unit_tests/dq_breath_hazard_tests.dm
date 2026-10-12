// Hazards through the LIVE Life sequence (not by calling the step procs): a human stands in steady air, sealed in one
// tile, long enough for its breathing, environment, radiation and chemicals steps to fall asleep; then its air, its
// body or its blood changes. The step that acts on the change must be woken by it: the effect begins within one Life
// cycle (a few seconds), long before any fallback rewake could run the step.
//
// Regression: the per-proc tests (dq_phoron_breath_*) passed while players stood in phoron unharmed: the breathing step
// slept in steady air with a 30 s rewake and only breathed on every 4th run. Then only a visible gas woke breathers
// (its overlays changing); CO2, oxygen, heat, cold and pressure waited for 15-30 s re-checks, and the N2O test passed
// only because its 100 mol release blew the human off its tile (moving woke it). Now each sleeping step is woken by
// its inputs (life_steps.dm woken_by): the air watch, the body heat watch, the radiation writers, the reagent holders.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Seconds a hazard may take to act: the wake is delivered at once, the woken step runs on the mob's next Life frame
/// (at most one cycle away), and the effect shows on that run.
#define LIFE_HAZARD_LIMIT (LIFE_CYCLE_SECONDS + 2)

/datum/unit_test/life_om/breath_hazard
	abstract_type = /datum/unit_test/life_om/breath_hazard
	var/mob/living/carbon/human/H
	var/turf/open/T
	/// The steps that must be asleep before the change, so only a wake can act on it.
	var/list/sleepers = list("life_breathing")

/// A human sealed on a floor tile with standard air, the steps in `sleepers` asleep in it.
/datum/unit_test/life_om/breath_hazard/proc/setup_breather(with_internals = FALSE)
	var/list/pair = dq_atmos_test_find_clear_pipe_run(1)
	if(!pair)
		TEST_FAIL("no clear floor for the hazard test")
		return FALSE
	T = pair[1]
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_isolate_pair(T, T)
	dq_atmos_test_fill_standard_air(T)
	T.air_update_turf(TRUE, FALSE)
	H = allocate(/mob/living/carbon/human, T)
	life_test_place(H)
	if(with_internals)
		H.equip_to_slot_or_del(new /obj/item/clothing/mask/breath(H), SLOT_ID_MASK)
		H.equip_to_slot_or_del(new /obj/item/tank/oxygen(H), SLOT_ID_BACK)
		rel_set(H, nameof(H.internal), H.get_equipped_item(SLOT_ID_BACK))
		if(!H.internal)
			TEST_FAIL("couldn't put the test human on internals")
			return FALSE
	// Steady air: let the steps run and (without internals) fall asleep.
	for(var/i in 1 to 8)
		life_test_advance(LIFE_CYCLE_SECONDS)
	if(H.loc != T)
		TEST_FAIL("the test human left its sealed tile")
		return FALSE
	if(with_internals)
		return TRUE
	// A sleeper whose own rewake (a fallback, or hunger's timer) is about to fire could act on the change without a
	// wake: let it fire and fall asleep again first.
	for(var/i in 1 to 40)
		var/soon = FALSE
		for(var/key in sleepers)
			var/rewake = life_test_rewake_in(H, key)
			if(!life_test_asleep(H, key) || (rewake && rewake <= LIFE_HAZARD_LIMIT * 10))
				soon = TRUE
		if(!soon)
			break
		life_test_advance(1)
	for(var/key in sleepers)
		if(!life_test_asleep(H, key))
			TEST_FAIL("[key] never slept in steady air (awake: [jointext(life_test_awake(H), ", ")]); the test can't show it waking")
			return FALSE
		var/rewake = life_test_rewake_in(H, key)
		if(rewake && rewake <= LIFE_HAZARD_LIMIT * 10)
			TEST_FAIL("[key]'s rewake is due in [rewake / 10] s: it, not a wake, could act on the change")
			return FALSE
	return TRUE

/// Releases `moles` of `gas` into the test tile through the production API (gas_dump, as a canister does).
/datum/unit_test/life_om/breath_hazard/proc/release(gas, moles)
	var/datum/gas_mixture/donor = new(1000)
	donor.adjust_gas(gas, moles)
	heat_set(donor, T20C, HEAT_SOURCE_OTHER)
	gas_dump(donor, T)

/// Lets up to `limit` seconds pass, a second at a time, until check() holds. Returns the seconds it took, or 0.
/datum/unit_test/life_om/breath_hazard/proc/wait_for(check_proc, limit = LIFE_HAZARD_LIMIT)
	var/waited = 0
	while(waited < limit)
		// The test clock steps neither the native gas frame nor the world watch lanes: deliver them as the live kernel's
		// phase N does every tick, then let the second pass.
		dq_gas_level_test_deliver()
		life_test_advance(1)
		waited++
		if(call(src, check_proc)())
			log_world("hazard [type]: acted after [waited] s")
			return waited
	return 0

/// The hazard acted, and the human was never moved (moving would wake its steps on its own).
/datum/unit_test/life_om/breath_hazard/proc/assert_acts(check_proc, what)
	TEST_ASSERT(wait_for(check_proc), "[what] within [LIFE_HAZARD_LIMIT] s (awake: [jointext(life_test_awake(H), ", ")]; air watch [H.body?.air_watch ? (H.body.air_watch.is_live() ? "live" : "dead") : "none"] key [H.body?.air_watch_key], levels [json_encode(H.air_watch_levels())])")
	TEST_ASSERT_EQUAL(H.loc, T, "the human stayed on its tile (no move woke it)")

/datum/unit_test/life_om/breath_hazard/proc/poisoned()
	return H.reagents.get_reagent_amount(REAGENT_ID_TOXIN) > 0 || H.bloodstr?.get_reagent_amount(REAGENT_ID_TOXIN) > 0

/datum/unit_test/life_om/breath_hazard/proc/sedated()
	return H.has_status(STAT_PARALYZED)

/datum/unit_test/life_om/breath_hazard/proc/suffocating()
	return H.alerts?["oxy"] || H.failed_last_breath

/datum/unit_test/life_om/breath_hazard/proc/short_of_breath()
	var/datum/physiology/P = H.body?.physiology
	return P && P.breath_quality < 1

/datum/unit_test/life_om/breath_hazard/proc/temperature_alert()
	return H.alerts?["temp"]

/datum/unit_test/life_om/breath_hazard/proc/pressure_alert()
	return H.alerts?["pressure"]

/// The environment exchange ran on the new air and coupled the body to it (inside the comfort range it couples nothing).
/datum/unit_test/life_om/breath_hazard/proc/body_coupled()
	return H.body && (H.body.environment_conductance > 0 || H.body.surface_conductance > 0)

/// Scales the tile's air to `pressure` kPa at its own temperature and composition.
/datum/unit_test/life_om/breath_hazard/proc/set_pressure(pressure)
	var/scale = pressure / T.air.return_pressure()
	T.air.set_moles(/datum/gas/oxygen, T.air.get_moles(/datum/gas/oxygen) * scale)
	T.air.set_moles(/datum/gas/nitrogen, T.air.get_moles(/datum/gas/nitrogen) * scale)

/// Phoron filling the room poisons a breather with no internals.
/datum/unit_test/life_om/breath_hazard/phoron

/datum/unit_test/life_om/breath_hazard/phoron/run_life()
	if(!setup_breather())
		return
	release(/datum/gas/plasma, 2)
	assert_acts(PROC_REF(poisoned), "a human standing in phoron took no toxin")
	TEST_ASSERT(H.alerts?["tox_in_air"], "no toxin-in-air alert while breathing phoron")

/// The same room, on internals behind a breath mask: no toxin.
/datum/unit_test/life_om/breath_hazard/phoron_internals

/datum/unit_test/life_om/breath_hazard/phoron_internals/run_life()
	if(!setup_breather(with_internals = TRUE))
		return
	release(/datum/gas/plasma, 2)
	TEST_ASSERT(!wait_for(PROC_REF(poisoned), 3 * LIFE_CYCLE_SECONDS), "a human on internals took toxin from the room's phoron")

/// Nitrous oxide knocks a breather out. A few moles: past the paralysis level, no pressure wave to push the human
/// off its tile (the old 100 mol release woke it by moving it).
/datum/unit_test/life_om/breath_hazard/sleeping_gas

/datum/unit_test/life_om/breath_hazard/sleeping_gas/run_life()
	if(!setup_breather())
		return
	TEST_ASSERT(!sedated(), "the test human was already paralysed before any N2O")
	release(/datum/gas/nitrous_oxide, 3)
	assert_acts(PROC_REF(sedated), "a human standing in N2O was not knocked out (paralysed)")

/// The oxygen drained out of the room in place: the breather suffocates.
/datum/unit_test/life_om/breath_hazard/no_oxygen

/datum/unit_test/life_om/breath_hazard/no_oxygen/run_life()
	if(!setup_breather())
		return
	T.air.set_moles(/datum/gas/oxygen, 0)
	assert_acts(PROC_REF(suffocating), "a human in air with no oxygen didn't fail a breath")

/// CO2 building up in the room (invisible): hypercapnia worsens the breath.
/datum/unit_test/life_om/breath_hazard/carbon_dioxide

/datum/unit_test/life_om/breath_hazard/carbon_dioxide/run_life()
	if(!setup_breather())
		return
	release(/datum/gas/carbon_dioxide, 9)
	assert_acts(PROC_REF(short_of_breath), "a human in CO2-heavy air kept full breath quality")

/// The room heats up: the breath burns and the environment exchange couples the body to the hot air.
/datum/unit_test/life_om/breath_hazard/heat
	sleepers = list("life_breathing", "life_environment")

/datum/unit_test/life_om/breath_hazard/heat/run_life()
	if(!setup_breather())
		return
	heat_set(T.air, 450, HEAT_SOURCE_OTHER)
	// The breath's temperature alert is cleared again by the environment exchange while the body is still comfortable, so the
	// exchange coupling the body to the air (which it skips inside the comfort range) is what shows it woke.
	assert_acts(PROC_REF(body_coupled), "the environment exchange didn't couple the body to 450 K air")

/// The room freezes: the breath frosts and the environment exchange couples the body to the cold air.
/datum/unit_test/life_om/breath_hazard/cold
	sleepers = list("life_breathing", "life_environment")

/datum/unit_test/life_om/breath_hazard/cold/run_life()
	if(!setup_breather())
		return
	heat_set(T.air, 150, HEAT_SOURCE_OTHER)
	// The breath's temperature alert is cleared again by the environment exchange while the body is still comfortable, so the
	// exchange coupling the body to the air (which it skips inside the comfort range) is what shows it woke.
	assert_acts(PROC_REF(body_coupled), "the environment exchange didn't couple the body to 150 K air")

/// The room's pressure falls to a hazard: the environment exchange warns.
/datum/unit_test/life_om/breath_hazard/low_pressure
	sleepers = list("life_breathing", "life_environment")

/datum/unit_test/life_om/breath_hazard/low_pressure/run_life()
	if(!setup_breather())
		return
	set_pressure(HAZARD_LOW_PRESSURE / 2)
	assert_acts(PROC_REF(pressure_alert), "a human in [HAZARD_LOW_PRESSURE / 2] kPa got no pressure alert")

/// The room's pressure climbs to a hazard: the environment exchange warns.
/datum/unit_test/life_om/breath_hazard/high_pressure
	sleepers = list("life_breathing", "life_environment")

/datum/unit_test/life_om/breath_hazard/high_pressure/run_life()
	if(!setup_breather())
		return
	set_pressure(HAZARD_HIGH_PRESSURE * 1.5)
	assert_acts(PROC_REF(pressure_alert), "a human in [HAZARD_HIGH_PRESSURE * 1.5] kPa got no pressure alert")

/// A radiation dose: the radiation step and the medical metric triggers wake on it.
/datum/unit_test/life_om/breath_hazard/radiation
	sleepers = list("life_radiation", "life_medical")

/datum/unit_test/life_om/breath_hazard/radiation/run_life()
	if(!setup_breather())
		return
	H.add_radiation(150)
	sched.run_pass(1e9)
	TEST_ASSERT(!life_test_asleep(H, "life_radiation"), "the dose didn't wake the radiation step")
	assert_acts(PROC_REF(irradiated), "a human given 150 rads developed no acute radiation sickness")

/datum/unit_test/life_om/breath_hazard/proc/irradiated()
	return H.has_affliction(/datum/affliction/acute_radiation)

/// A reagent injected into the blood: the chemicals step wakes and metabolises it.
/datum/unit_test/life_om/breath_hazard/injection
	sleepers = list("life_chemicals")
	var/dose = 10

/datum/unit_test/life_om/breath_hazard/injection/run_life()
	if(!setup_breather())
		return
	H.bloodstr.add_reagent(REAGENT_ID_INAPROVALINE, dose)
	assert_acts(PROC_REF(metabolised), "an injected reagent was not metabolised")

/datum/unit_test/life_om/breath_hazard/proc/metabolised()
	return H.bloodstr.get_reagent_amount(REAGENT_ID_INAPROVALINE) < 10 // the dose

/// Every Life step that can sleep declares what wakes it (woken_by: its reads and their producers). Nothing polls: the
/// only entry that is not a read is LIFE_WOKEN_BY_TIME, with its reason, and a rewake shorter than LIFE_SAFETY_RESAMPLE
/// is allowed only for such work that drifts with time.
/datum/unit_test/life_om/steps_declare_their_wakes

/datum/unit_test/life_om/steps_declare_their_wakes/run_life()
	var/list/mobs = list(allocate(/mob/living/carbon/human), allocate(/mob/living/simple_mob/animal/passive/mouse), allocate(/mob/living/simple_mob/animal/passive/fish), 		allocate(/mob/living/simple_mob/animal/passive/cat), allocate(/mob/living/simple_mob/slime/xenobio), allocate(/mob/living/carbon/alien/larva), allocate(/mob/living/carbon/brain))
	for(var/mob/living/L as anything in mobs)
		life_test_place(L)
		var/datum/seq_state/state = life_test_state(L)
		TEST_ASSERT_NOTNULL(state, "[L.type] is on the Life sequence")
		if(!state)
			continue
		for(var/datum/seq_step/S as anything in state.table.steps)
			if(S.anchor || S.target_kind != SEQ_TARGET_ENTITY || (!S.should_run && !S.once))
				continue // always awake, or a contributor's step
			var/where = "[L.type] [S.key]"
			if(!islist(S.woken_by) || !length(S.woken_by))
				TEST_FAIL("[where] sleeps but declares no woken_by list")
				continue
			var/list/woken_by = S.woken_by
			for(var/key in woken_by)
				if(key == LIFE_WOKEN_BY_TIME)
					var/reason = woken_by[key]
					if(!istext(reason) || length(reason) < 15)
						TEST_FAIL("[where] declares time without saying what drifts with it")
					if(!S.rewake)
						TEST_FAIL("[where] declares time but has no rewake to follow it")
					continue
				if(!(key in S.reads))
					TEST_FAIL("[where]: woken_by names [key], which is neither among its reads nor time (nothing may poll)")
			if(!S.rewake)
				continue
			var/delay = isnum(S.rewake) ? S.rewake : call(L, S.rewake)()
			if(delay > 0 && delay < LIFE_SAFETY_RESAMPLE && !woken_by[LIFE_WOKEN_BY_TIME])
				TEST_FAIL("[where] re-checks every [delay / 10] s, under the [LIFE_SAFETY_RESAMPLE / 10] s safety resample, without declaring work that drifts with time")

#undef LIFE_HAZARD_LIMIT

#endif
