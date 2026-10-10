// Wave 5 harm: continuous harm (INJURE_CONTINUOUS) is time-invariant, bellies
// insert through the ledger, belly contents see the predator's temperature, and
// the thermal constants have one source.

/// Every injury category's load on `L`, summed.
/proc/harm_test_total_load(mob/living/L)
	. = 0
	for(var/category in 1 to INJURY_CATEGORY_COUNT)
		. += L.injury_load(category)

/// A fresh human given `rate` of `kind` per 6 s as continuous harm, in `ticks`
/// ticks of `seconds` each. Returns its total injury load.
/datum/unit_test/proc/harm_test_rate(kind, rate, ticks, seconds)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	for(var/i in 1 to ticks)
		H.injure(kind, rate * seconds / 6, flags = INJURE_CONTINUOUS)
	return harm_test_total_load(H)

/// 3 x 6 s, 9 x 2 s and 18 x 1 s of the same rate land the same total, for
/// located (wound) and systemic harm alike.
/datum/unit_test/dq_continuous_harm_time_invariant

/datum/unit_test/dq_continuous_harm_time_invariant/Run()
	for(var/kind in list(INJURY_DIGESTION, INJURY_CORROSIVE, INJURY_BURN, INJURY_BLUNT, INJURY_TOXIN))
		var/slow = harm_test_rate(kind, 2, 3, 6)
		var/turbo = harm_test_rate(kind, 2, 9, 2)
		var/fine = harm_test_rate(kind, 2, 18, 1)
		TEST_ASSERT(slow > 0, "[injury_kind_name(kind)]: continuous harm should land ([slow])")
		TEST_ASSERT(abs(turbo - slow) <= slow * 0.01, "[injury_kind_name(kind)]: 9x2 s landed [turbo], 3x6 s landed [slow]")
		TEST_ASSERT(abs(fine - slow) <= slow * 0.01, "[injury_kind_name(kind)]: 18x1 s landed [fine], 3x6 s landed [slow]")
	// Located harm is exactly additive: the rate over the time, nothing lost to rounding.
	var/digested = harm_test_rate(INJURY_DIGESTION, 2, 18, 1)
	TEST_ASSERT(abs(digested - 6) < 0.01, "18x1 s of 2 per 6 s digestion should total 6, got [digested]")

/// A digesting belly deals the same over the same time in normal and turbo cycles.
/datum/unit_test/dq_vore_digestion_time_invariant

/datum/unit_test/dq_vore_digestion_time_invariant/Run()
	var/list/totals = list()
	for(var/list/schedule in list(list(3, 6), list(9, 2), list(18, 1)))
		var/list/pair = vore_test_pair()
		var/obj/belly/B = vore_rate_belly(pair, DM_DIGEST)
		B.digest_brute = 1
		B.digest_burn = 1
		var/mob/living/prey = pair[2]
		vore_test_cycles(B, schedule[1], schedule[2])
		totals += harm_test_total_load(prey)
	TEST_ASSERT(totals[1] > 0, "the digest belly should harm its prey")
	TEST_ASSERT(abs(totals[2] - totals[1]) <= totals[1] * 0.01, "turbo (9x2 s) digestion landed [totals[2]], normal (3x6 s) [totals[1]]")
	TEST_ASSERT(abs(totals[3] - totals[1]) <= totals[1] * 0.01, "18x1 s digestion landed [totals[3]], normal (3x6 s) [totals[1]]")

/// A lollipop's captive goes into the predator's belly through the ledger.
/datum/unit_test/dq_lollipop_prey_enters_belly_slot

/datum/unit_test/dq_lollipop_prey_enters_belly_slot/Run()
	var/list/pair = vore_test_pair()
	var/mob/living/carbon/human/pred = pair[1]
	var/mob/living/carbon/human/prey = pair[2]
	pred.can_be_drop_pred = TRUE
	pred.food_vore = TRUE
	prey.can_be_drop_prey = TRUE
	prey.food_vore = TRUE
	var/obj/item/clothing/mask/chewable/candy/lolli/lolli = new(pred)
	prey.forceMove(lolli)
	rel_set(lolli, nameof(lolli.victims), list(prey))
	lolli.spitout(0)
	var/obj/belly/B = pred.vore_selected
	TEST_ASSERT_EQUAL(prey.loc, B, "the lollipop's captive should end up in the belly")
	var/datum/relation_definition/slot/prey_slot = dq_path_slot_of(B, prey)
	TEST_ASSERT_EQUAL(prey_slot?.slot_id, BELLY_SLOT_INTERIOR, "the captive should hold a belly interior slot entry")
	TEST_ASSERT(B.cycle_token, "the belly should cycle once the captive is inside")
	B.release_all_contents(TRUE, TRUE)

/// Belly contents see the predator's body temperature.
/datum/unit_test/dq_belly_interior_follows_predator

/datum/unit_test/dq_belly_interior_follows_predator/Run()
	var/list/pair = vore_test_pair()
	var/mob/living/carbon/human/pred = pair[1]
	var/mob/living/carbon/human/prey = pair[2]
	var/obj/belly/B = vore_rate_belly(pair, DM_HOLD)
	TEST_ASSERT_EQUAL(B.get_interior_temperature(), pred.body_temperature(), "a belly's interior is the predator's body temperature")
	TEST_ASSERT_EQUAL(prey.get_ambient_temperature(), pred.body_temperature(), "the prey's surroundings are the predator's body")
	pred.set_bodytemperature(pred.species.heat_level_1 + 5)
	TEST_ASSERT_EQUAL(B.get_interior_temperature(), pred.body_temperature(), "the belly follows a feverish predator")
	var/datum/gas_mixture/air = B.return_air_for_internal_lifeform(prey)
	TEST_ASSERT(abs(air.return_temperature() - pred.body_temperature()) < 0.01, "belly air should be at the predator's temperature, is [air.return_temperature()]")
	B.release_all_contents(TRUE, TRUE)

/// The emergent thermal metric uses the species' body temperature.
/datum/unit_test/dq_normal_body_temperature_is_species

/datum/unit_test/dq_normal_body_temperature_is_species/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT_EQUAL(H.dq_normal_body_temperature(), H.species.body_temperature, "the normal temperature is the species'")
	TEST_ASSERT(abs(H.species.body_temperature - BODYTEMP_NORMAL) < 0.01, "a human's species temperature is BODYTEMP_NORMAL")
	TEST_ASSERT(TCMB < 3, "TCMB is the cosmic background temperature ([TCMB] K)")
