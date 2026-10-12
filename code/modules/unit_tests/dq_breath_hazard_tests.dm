// Breathing hazards through the LIVE Life sequence (not by calling the breath procs): a human stands
// in steady air long enough for its breathing step to fall asleep, then the room's air turns bad.
// Within a bounded time the scheduler must wake the breather and the gas must act on it.
//
// Regression: the per-proc tests (dq_phoron_breath_*) passed while players stood in phoron unharmed:
// the breathing step slept in steady air with a 30 s rewake and only breathed on every 4th run, so a
// sleeping breather took one breath every two minutes and gas arriving in place woke nothing.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A visible gas (phoron, N2O) arriving wakes the breathers on the turf: it acts within two Life cycles, seconds.
#define BREATH_HAZARD_VISIBLE (2 * LIFE_CYCLE_SECONDS)
/// An invisible change (CO2, oxygen draining) is caught by the steady-air resample: one resample and a cycle, seconds.
#define BREATH_HAZARD_INVISIBLE (BREATH_STEADY_RESAMPLE / 10 + LIFE_CYCLE_SECONDS + 1)

/datum/unit_test/life_om/breath_hazard
	abstract_type = /datum/unit_test/life_om/breath_hazard
	var/mob/living/carbon/human/H
	var/turf/open/T

/// A human on a floor with breathable air, its breathing step asleep in it.
/datum/unit_test/life_om/breath_hazard/proc/setup_breather(with_internals = FALSE)
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air && !(locate(/mob/living) in cand))
			T = cand
			break
	if(!T)
		TEST_FAIL("no floor with air for the breathing test")
		return FALSE
	T.air.clear()
	T.air.adjust_gas(/datum/gas/oxygen, MOLES_O2STANDARD)
	T.air.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	heat_set(T.air, T20C, HEAT_SOURCE_OTHER)
	T.update_visuals()
	H = allocate(/mob/living/carbon/human, T)
	life_test_place(H)
	if(with_internals)
		H.equip_to_slot_or_del(new /obj/item/clothing/mask/breath(H), SLOT_ID_MASK)
		H.equip_to_slot_or_del(new /obj/item/tank/oxygen(H), SLOT_ID_BACK)
		rel_set(H, nameof(H.internal), H.get_equipped_item(SLOT_ID_BACK))
		if(!H.internal)
			TEST_FAIL("couldn't put the test human on internals")
			return FALSE
	// Steady air: let the breathing step take its breaths and (without internals) fall asleep.
	for(var/i in 1 to 8)
		life_test_advance(LIFE_CYCLE_SECONDS)
	if(!with_internals && !life_test_asleep(H, "life_breathing"))
		TEST_FAIL("breathing never slept in steady air (awake: [jointext(life_test_awake(H), ", ")]); the test can't show it waking")
		return FALSE
	return TRUE

/// Releases `moles` of `gas` into the test turf through the production API (gas_release, as a canister does).
/datum/unit_test/life_om/breath_hazard/proc/release(gas, moles)
	var/datum/gas_mixture/donor = new(1000)
	donor.adjust_gas(gas, moles)
	heat_set(donor, T20C, HEAT_SOURCE_OTHER)
	gas_dump(donor, T)

/// Lets up to `limit` seconds pass, a Life cycle at a time, until check() holds. Returns the seconds it took, or 0.
/datum/unit_test/life_om/breath_hazard/proc/wait_for(check_proc, limit)
	var/waited = 0
	while(waited < limit)
		life_test_advance(1)
		waited++
		if(call(src, check_proc)())
			log_world("breath_hazard [type]: acted after [waited] s (breathing asleep: [life_test_asleep(H, "life_breathing")])")
			return waited
	return 0

/datum/unit_test/life_om/breath_hazard/proc/poisoned()
	return H.reagents.get_reagent_amount(REAGENT_ID_TOXIN) > 0 || H.bloodstr?.get_reagent_amount(REAGENT_ID_TOXIN) > 0

/datum/unit_test/life_om/breath_hazard/proc/sedated()
	return H.has_status(STAT_PARALYZED)

/datum/unit_test/life_om/breath_hazard/proc/suffocating()
	return H.alerts?["oxy"] || H.failed_last_breath

/datum/unit_test/life_om/breath_hazard/proc/short_of_breath()
	var/datum/physiology/P = H.body?.physiology
	return P && P.breath_quality < 1

/// Phoron filling the room poisons a breather with no internals.
/datum/unit_test/life_om/breath_hazard/phoron

/datum/unit_test/life_om/breath_hazard/phoron/run_life()
	if(!setup_breather())
		return
	release(/datum/gas/plasma, 60)
	TEST_ASSERT(wait_for(PROC_REF(poisoned), BREATH_HAZARD_VISIBLE), "a human standing in phoron took no toxin within [BREATH_HAZARD_VISIBLE] s")
	TEST_ASSERT(H.alerts?["tox_in_air"], "no toxin-in-air alert while breathing phoron")

/// The same room, on internals behind a breath mask: no toxin.
/datum/unit_test/life_om/breath_hazard/phoron_internals

/datum/unit_test/life_om/breath_hazard/phoron_internals/run_life()
	if(!setup_breather(with_internals = TRUE))
		return
	release(/datum/gas/plasma, 60)
	TEST_ASSERT(!wait_for(PROC_REF(poisoned), BREATH_HAZARD_INVISIBLE), "a human on internals took toxin from the room's phoron")

/// Nitrous oxide puts a breather to sleep.
/datum/unit_test/life_om/breath_hazard/sleeping_gas

/datum/unit_test/life_om/breath_hazard/sleeping_gas/run_life()
	if(!setup_breather())
		return
	TEST_ASSERT(!sedated(), "the test human was already paralysed before any N2O")
	release(/datum/gas/nitrous_oxide, 100)
	TEST_ASSERT(wait_for(PROC_REF(sedated), BREATH_HAZARD_VISIBLE), "a human standing in N2O was not knocked out (paralysed) within [BREATH_HAZARD_VISIBLE] s")

/// The oxygen drained out of the room in place: the breather suffocates.
/datum/unit_test/life_om/breath_hazard/no_oxygen

/datum/unit_test/life_om/breath_hazard/no_oxygen/run_life()
	if(!setup_breather())
		return
	T.air.set_moles(/datum/gas/oxygen, 0)
	TEST_ASSERT(wait_for(PROC_REF(suffocating), BREATH_HAZARD_INVISIBLE), "a human in air with no oxygen didn't fail a breath within [BREATH_HAZARD_INVISIBLE] s")

/// CO2 building up in the room: hypercapnia worsens the breath.
/datum/unit_test/life_om/breath_hazard/carbon_dioxide

/datum/unit_test/life_om/breath_hazard/carbon_dioxide/run_life()
	if(!setup_breather())
		return
	release(/datum/gas/carbon_dioxide, 200)
	TEST_ASSERT(wait_for(PROC_REF(short_of_breath), BREATH_HAZARD_INVISIBLE), "a human in CO2-heavy air kept full breath quality for [BREATH_HAZARD_INVISIBLE] s")

#undef BREATH_HAZARD_VISIBLE
#undef BREATH_HAZARD_INVISIBLE

#endif
