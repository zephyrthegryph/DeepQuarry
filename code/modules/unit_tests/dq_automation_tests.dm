// Unit tests for medical automation deciding from the diagnosis layer:
// medbots pick a reagent by treatment demand, cryo heals through treatment
// tags, and the medigun heals only the tags its loaded modes provide.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// --- Medbot: the right chem for the demand ------------------------------------

/datum/unit_test/dq_medbot_picks_chem_by_demand

/datum/unit_test/dq_medbot_picks_chem_by_demand/Run()
	var/mob/living/bot/medbot/mysterious/bot = allocate(/mob/living/bot/medbot/mysterious)

	var/mob/living/carbon/human/healthy = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NULL(bot.choose_treatment(healthy), "a medbot should not treat an uninjured patient")

	var/mob/living/carbon/human/bleeding = allocate(/mob/living/carbon/human)
	bleeding.injure(INJURY_CUT, 25, BP_L_ARM, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/list/bleed_demand = bleeding.treatment_demand(/datum/diagnostic_profile/automation)
	TEST_ASSERT(bleed_demand?[TREAT_TISSUE_REPAIR], "a cut should demand tissue repair from automated triage")
	var/bleed_choice = bot.choose_treatment(bleeding)
	TEST_ASSERT_EQUAL(bleed_choice, REAGENT_ID_BICARIDINE, "a bleeding patient should get bicaridine (got [bleed_choice])")

	var/mob/living/carbon/human/poisoned = allocate(/mob/living/carbon/human)
	poisoned.injure(INJURY_TOXIN, 30, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/list/poison_demand = poisoned.treatment_demand(/datum/diagnostic_profile/automation)
	TEST_ASSERT(poison_demand?[TREAT_ANTITOXIN], "poisoning should demand antitoxin from automated triage")
	var/poison_choice = bot.choose_treatment(poisoned)
	TEST_ASSERT_EQUAL(poison_choice, REAGENT_ID_ANTITOXIN, "a poisoned patient should get dylovene (got [poison_choice])")

	// Already medicated with the best match: the next best is chosen instead.
	bleeding.reagents.add_reagent(REAGENT_ID_BICARIDINE, 5)
	var/second_choice = bot.choose_treatment(bleeding)
	TEST_ASSERT(second_choice != REAGENT_ID_BICARIDINE, "a medbot should not re-dose a reagent the patient already has")

	// The urgency threshold gates treatment.
	bot.min_urgency = 4
	TEST_ASSERT_NULL(bot.choose_treatment(poisoned), "a medbot set to critical-only should leave a moderate poisoning")


// --- Cryo: healing through treatment tags ---------------------------------------

/datum/unit_test/dq_cryo_heals_via_tags

/datum/unit_test/dq_cryo_heals_via_tags/Run()
	// On a real floor, so a released patient has a turf to step out onto.
	var/obj/machinery/atmospherics/unary/cryo_cell/cell = allocate(/obj/machinery/atmospherics/unary/cryo_cell, test_floor())

	var/list/warm = cell.cryo_treatment_rates(T0C - 10)
	TEST_ASSERT(warm[TREAT_OXYGENATION], "a merely cold cell should oxygenate")
	TEST_ASSERT_NULL(warm[TREAT_TISSUE_REPAIR], "a merely cold cell should not repair tissue")
	var/list/cold = cell.cryo_treatment_rates(100)
	var/list/colder = cell.cryo_treatment_rates(50)
	TEST_ASSERT(cold[TREAT_TISSUE_REPAIR] > 0, "a deep-cold cell should repair tissue")
	TEST_ASSERT(colder[TREAT_TISSUE_REPAIR] > cold[TREAT_TISSUE_REPAIR], "colder should heal faster")

	var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker)
	B.reagents.add_reagent(REAGENT_ID_BICARIDINE, 30)
	rel_set(cell, nameof(cell.beaker), B)
	var/list/boosted = cell.cryo_treatment_rates(100)
	TEST_ASSERT(boosted[TREAT_TISSUE_REPAIR] > cold[TREAT_TISSUE_REPAIR], "bicaridine in the beaker should boost tissue repair")
	TEST_ASSERT_EQUAL(boosted[TREAT_BURN_CARE], cold[TREAT_BURN_CARE], "bicaridine should not boost burn care")
	own_take(cell, nameof(cell.beaker))

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.injure(INJURY_CUT, 25, BP_L_ARM, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/physical_before = H.injury_load(INJURY_CATEGORY_PHYSICAL)
	TEST_ASSERT(move_into(cell, OCCUPANT_SLOT_CRYO, H), "the patient should enter the cryo cell")
	H.set_bodytemperature(100)
	for(var/i in 1 to 5)
		cell.treat_occupant()
	TEST_ASSERT(H.injury_load(INJURY_CATEGORY_PHYSICAL) < physical_before, "cryo should mend the demanded tissue repair ([physical_before] -> [H.injury_load(INJURY_CATEGORY_PHYSICAL)])")
	TEST_ASSERT_EQUAL(occupant_of(cell), H, "cryo should keep treating a patient triage still finds injured")

	// A patient triage finds healthy is released.
	var/mob/living/carbon/human/well = allocate(/mob/living/carbon/human)
	H.forceMove(get_turf(cell)) // free the one-occupant slot
	TEST_ASSERT(move_into(cell, OCCUPANT_SLOT_CRYO, well), "the patient should enter the cryo cell")
	well.set_bodytemperature(100)
	TEST_ASSERT(!cell.treat_occupant(), "cryo should release a patient with no treatment demand")
	TEST_ASSERT_NULL(occupant_of(cell), "the released patient should have left the cell")


// --- Medigun: only its mode's tags -------------------------------------------------

/datum/unit_test/dq_medigun_heals_mode_tags

/datum/unit_test/dq_medigun_heals_mode_tags/Run()
	var/obj/item/medigun_backpack/pack = allocate(/obj/item/medigun_backpack)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.injure(INJURY_CUT, 20, BP_L_ARM, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	H.injure(INJURY_BURN, 20, BP_R_ARM, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	H.injure(INJURY_CELLULAR, 20, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)

	// Brute tank only: trauma mends, burns and cellular damage don't.
	pack.set_brutecharge(60)
	pack.set_burncharge(0)
	pack.set_toxcharge(0)
	var/physical = H.injury_load(INJURY_CATEGORY_PHYSICAL)
	var/thermal = H.injury_load(INJURY_CATEGORY_THERMAL)
	var/genetic = H.injury_load(INJURY_CATEGORY_GENETIC)
	TEST_ASSERT(pack.treat_demand(H, 5) > 0, "a loaded brute tank should treat a cut")
	TEST_ASSERT(H.injury_load(INJURY_CATEGORY_PHYSICAL) < physical, "the brute mode should mend trauma")
	TEST_ASSERT_EQUAL(H.injury_load(INJURY_CATEGORY_THERMAL), thermal, "the brute mode must not mend burns")
	TEST_ASSERT_EQUAL(H.injury_load(INJURY_CATEGORY_GENETIC), genetic, "no medigun mode mends cellular damage")
	TEST_ASSERT(pack.brutecharge < 60, "treating should drain the brute tank")

	// Burn tank only: burns mend, trauma doesn't.
	pack.set_brutecharge(0)
	pack.set_burncharge(60)
	physical = H.injury_load(INJURY_CATEGORY_PHYSICAL)
	thermal = H.injury_load(INJURY_CATEGORY_THERMAL)
	pack.treat_demand(H, 5)
	TEST_ASSERT(H.injury_load(INJURY_CATEGORY_THERMAL) < thermal, "the burn mode should mend burns")
	TEST_ASSERT_EQUAL(H.injury_load(INJURY_CATEGORY_PHYSICAL), physical, "the burn mode must not mend trauma")
	TEST_ASSERT_EQUAL(H.injury_load(INJURY_CATEGORY_GENETIC), genetic, "no medigun mode mends cellular damage")

	// Empty tanks treat nothing.
	pack.set_burncharge(0)
	TEST_ASSERT_EQUAL(pack.treat_demand(H, 5), 0, "empty tanks should treat nothing")

#endif
