// The factor oracle against the live body (code/modules/unit_tests/dq_factor_oracle.dm): the old fold, folded from a mob's real sources, gives the
// same vector as what the mob reads now, for a spread of scenarios that drive every kind of source through the production paths.

/datum/unit_test/dq_factor_oracle_parity

/datum/unit_test/dq_factor_oracle_parity/proc/check(mob/living/L, what)
	var/list/diff = factor_oracle_diff(L)
	TEST_ASSERT(!length(diff), "[what]: [jointext(diff, "; ")]")

/datum/unit_test/dq_factor_oracle_parity/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	check(H, "a fresh human (species baseline)")
	// Afflictions: a plain table, a staged one, and the three that fold more than their table.
	H.body.afflict(/datum/affliction/airway_obstruction)
	check(H, "an airway obstruction")
	var/datum/affliction/airway_obstruction/airway = H.body.find_affliction(/datum/affliction/airway_obstruction)
	airway?.set_severity(80)
	check(H, "an airway obstruction at 80")
	H.body.afflict(/datum/affliction/respiratory_arrest)
	check(H, "respiratory arrest")
	H.body.afflict(/datum/affliction/hypovolemic_shock)
	check(H, "hypovolemic shock")
	H.body.afflict(/datum/affliction/tissue_hypoxia)
	var/datum/affliction/tissue_hypoxia/hypoxia = H.body.find_affliction(/datum/affliction/tissue_hypoxia)
	hypoxia?.set_severity(90)
	check(H, "tissue hypoxia")
	// Body effects with stacks.
	H.apply_body_effect(/datum/body_effect/dq_test_slowdown)
	H.apply_body_effect(/datum/body_effect/dq_test_slowdown)
	H.apply_body_effect(/datum/body_effect/dq_test_factors)
	check(H, "body effects with stacks")
	// Reagents: a spread of those that carry a table, at two doses, then the same reagents again (a second dose band).
	var/list/with_factors = list()
	for(var/reagent_id in SSchemistry.ready().chemical_reagents)
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[reagent_id]
		if(length(R.factors) && !R.affects_dead)
			with_factors += reagent_id
	TEST_ASSERT(length(with_factors) > 10, "the scenario needs reagents with factors")
	var/step = max(1, round(length(with_factors) / 8))
	var/added = 0
	for(var/i in 1 to length(with_factors) step step)
		H.bloodstr.add_reagent(with_factors[i], DQ_CHEM_STANDARD_DOSE)
		added++
	check(H, "[added] reagents at a standard dose")
	for(var/i in 1 to length(with_factors) step step)
		H.bloodstr.add_reagent(with_factors[i], DQ_CHEM_STANDARD_DOSE * 2)
	check(H, "the same reagents at three standard doses")
	H.bloodstr.add_reagent(REAGENT_ID_ETHANOL, 60)
	check(H, "ethanol past the liver threshold")
	// Stasis.
	H.set_stasis(/datum/body_effect/stasis/deep, null)
	check(H, "deep stasis")
	// Everything ends: the sources release and the factors come back to the species baseline.
	H.bloodstr.clear_reagents()
	H.clear_body_effects(TRUE)
	H.set_stasis(null, null)
	H.body.clear_afflictions()
	check(H, "after every source ended")
