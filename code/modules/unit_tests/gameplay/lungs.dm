// Breathing: a player standing in a room that fills with phoron is poisoned; on internals they are not, until they close the valve;
// a room that loses its oxygen suffocates them. The player first stands in steady air long enough for their breathing to settle, so a
// breath that only a timer (and not the changing air) wakes is too late to pass.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Seconds the air may take to act on a breather: the wake reaches the next Life frame, at most one cycle away.
#define GAMEPLAY_BREATH_LIMIT (LIFE_CYCLE_SECONDS + 2)

/datum/unit_test/dq_gameplay/breathing
	abstract_type = /datum/unit_test/dq_gameplay/breathing
	/// The sealed floor the player stands on.
	var/turf/open/room

/// A player on a sealed floor tile of standard air, breathing it long enough for their breathing to settle.
/datum/unit_test/dq_gameplay/breathing/proc/breather(internals = FALSE)
	var/list/pair = dq_atmos_test_find_clear_pipe_run(1)
	if(!pair)
		Fail("no clear floor to stand on", __FILE__, __LINE__)
		return null
	room = pair[1]
	dq_atmos_test_snapshot_air(room)
	dq_atmos_test_isolate_pair(room, room)
	dq_atmos_test_fill_standard_air(room)
	room.air_update_turf(TRUE, FALSE)
	var/mob/living/carbon/human/H = spawn_player(room)
	if(internals)
		H.equip_to_slot_or_del(new /obj/item/clothing/mask/breath(H), SLOT_ID_MASK)
		H.equip_to_slot_or_del(new /obj/item/tank/oxygen(H), SLOT_ID_BACK)
	pass_time(4 * LIFE_CYCLE_SECONDS, gas = TRUE)
	return H

/// Phoron into the room, as a canister dumps it.
/datum/unit_test/dq_gameplay/breathing/proc/release_phoron(moles = 2)
	var/datum/gas_mixture/donor = new(1000)
	donor.adjust_gas(/datum/gas/plasma, moles)
	heat_set(donor, T20C, HEAT_SOURCE_OTHER)
	gas_dump(donor, room)

/// Waits up to `limit` seconds for check() on `H`; the seconds it took, or 0.
/datum/unit_test/dq_gameplay/breathing/proc/within(mob/living/carbon/human/H, check, limit = GAMEPLAY_BREATH_LIMIT)
	for(var/second in 1 to limit)
		pass_time(1, gas = TRUE)
		if(call(src, check)(H))
			return second
	return 0

/datum/unit_test/dq_gameplay/breathing/proc/poisoned(mob/living/carbon/human/H)
	return H.reagents.get_reagent_amount(REAGENT_ID_TOXIN) > 0 || H.bloodstr?.get_reagent_amount(REAGENT_ID_TOXIN) > 0

/datum/unit_test/dq_gameplay/breathing/proc/suffocating(mob/living/carbon/human/H)
	return H.alerts?["oxy"] || H.failed_last_breath

/// Standing in phoron: toxin in the blood, and the toxin warning.
/datum/unit_test/dq_gameplay/breathing/phoron_poisons

/datum/unit_test/dq_gameplay/breathing/phoron_poisons/play()
	var/mob/living/carbon/human/H = breather()
	if(!H)
		return
	TEST_ASSERT(!poisoned(H), "no toxin before the phoron")
	release_phoron()
	TEST_ASSERT(within(H, PROC_REF(poisoned)), "a player standing in phoron took no toxin within [GAMEPLAY_BREATH_LIMIT] s (awake: [jointext(life_test_awake(H), ", ")])")
	TEST_ASSERT(H.alerts?["tox_in_air"], "the player is warned of toxin in the air")

/// On internals (opened at the tank's window) the phoron does nothing; closing the valve lets it in.
/datum/unit_test/dq_gameplay/breathing/internals_protect

/datum/unit_test/dq_gameplay/breathing/internals_protect/play()
	var/mob/living/carbon/human/H = breather(internals = TRUE)
	if(!H)
		return
	var/obj/item/tank/tank = H.get_equipped_item(SLOT_ID_BACK)
	press(H, tank, "toggle")
	TEST_ASSERT_EQUAL(H.internal, tank, "the tank's valve button puts the player on internals")
	release_phoron()
	TEST_ASSERT(!within(H, PROC_REF(poisoned), 2 * LIFE_CYCLE_SECONDS), "a player on internals took toxin from the room's phoron")
	press(H, tank, "toggle")
	TEST_ASSERT_NULL(H.internal, "the button closes the valve again")
	TEST_ASSERT(within(H, PROC_REF(poisoned)), "off internals, the room's phoron poisons the player")

/// The room's oxygen gone: the player fails their breaths.
/datum/unit_test/dq_gameplay/breathing/no_oxygen_suffocates

/datum/unit_test/dq_gameplay/breathing/no_oxygen_suffocates/play()
	var/mob/living/carbon/human/H = breather()
	if(!H)
		return
	TEST_ASSERT(!suffocating(H), "breathing normally in standard air")
	room.air.set_moles(/datum/gas/oxygen, 0)
	TEST_ASSERT(within(H, PROC_REF(suffocating)), "a player in air with no oxygen did not fail a breath within [GAMEPLAY_BREATH_LIMIT] s")

#undef GAMEPLAY_BREATH_LIMIT

#endif
