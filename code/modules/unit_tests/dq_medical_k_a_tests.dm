// MED-9 group A regression tests: shock writer (P2-S14), pain predicate (P2-S4), breath profile
// (P2-S7/D8), photosynthesis (P2-D7), stasis gating (P2-S6), species facts (P2-S5) and the
// split human life procs (A23/A24).

/// P2-S14: adjust_shock()/set_shock() own shock_stage and clamp it to the shock system's range.
/datum/unit_test/dq_k_a_adjust_shock_clamps

/datum/unit_test/dq_k_a_adjust_shock_clamps/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.set_shock(0, "test")
	TEST_ASSERT_EQUAL(H.adjust_shock(20, "test"), 20, "adjust_shock adds to the stage")
	TEST_ASSERT_EQUAL(H.adjust_shock(1000, "test"), 160, "the stage is capped at 160")
	TEST_ASSERT_EQUAL(H.adjust_shock(-1000, "test"), 0, "relief never takes the stage below 0")
	H.set_shock(45, "test")
	TEST_ASSERT_EQUAL(H.shock_stage, 45, "set_shock sets the stage")

/// P2-S4: NO_PAIN is a BF_PAIN_IMMUNITY grant, so can_feel_pain() answers through the factor.
/datum/unit_test/dq_k_a_no_pain_feeds_pain_immunity

/datum/unit_test/dq_k_a_no_pain_feeds_pain_immunity/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(H.can_feel_pain(), "a plain human feels pain")
	TEST_ASSERT(!H.factor(BF_PAIN_IMMUNITY), "a plain human has no pain immunity")
	var/old_flags = H.species.flags
	proto_private(H, nameof(H.species)) // write on the mob's private species copy, never the registered one
	H.species.flags |= NO_PAIN
	H.body.invalidate(BODY_DIRTY_FACTORS)
	var/immune = H.factor(BF_PAIN_IMMUNITY)
	var/feels = H.can_feel_pain()
	H.species.flags = old_flags
	H.body.invalidate(BODY_DIRTY_FACTORS)
	TEST_ASSERT(immune, "a NO_PAIN species grants BF_PAIN_IMMUNITY")
	TEST_ASSERT(!feels, "a NO_PAIN species can't feel pain")

/// P2-S7: breathes()/breath_profile() are the one answer, and does_not_breathe goes through its setter.
/datum/unit_test/dq_k_a_breath_profile

/datum/unit_test/dq_k_a_breath_profile/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/breath_profile/P = H.breath_profile()
	TEST_ASSERT(istype(P) && P.uses_lungs, "a plain human breathes through lungs")
	TEST_ASSERT(H.breathes(), "a plain human breathes")
	TEST_ASSERT(H.needs_to_breathe(), "a plain human is affected by airborne agents")
	H.set_does_not_breathe(TRUE)
	TEST_ASSERT(!H.breathes(), "does_not_breathe stops breathing")
	TEST_ASSERT(!H.needs_to_breathe(), "a non-breather ignores airborne agents")
	TEST_ASSERT(H.body.dirty & BODY_DIRTY_PHYSIOLOGY, "the setter makes the physiology re-read breathing")
	H.set_does_not_breathe(FALSE)
	TEST_ASSERT(H.breathes(), "breathing resumes")

/// P2-D8: alraunes breathe through the skin profile: CO2 in keeps them alive and boosts photosynthesis.
/datum/unit_test/dq_k_a_skin_breathing

/datum/unit_test/dq_k_a_skin_breathing/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.set_species(SPECIES_ALRAUNE)
	var/datum/breath_profile/skin/P = H.breath_profile()
	TEST_ASSERT(istype(P), "an alraune breathes through its skin")
	TEST_ASSERT(!P.uses_lungs, "skin breathing uses no lungs")
	TEST_ASSERT(H.breathes(), "an alraune breathes")

	var/datum/gas_mixture/breath = new(BREATH_VOLUME)
	breath.adjust_gas(/datum/gas/carbon_dioxide, MOLES_O2STANDARD)
	breath.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	heat_set(breath, T20C, HEAT_SOURCE_OTHER)
	var/co2_before = breath.get_moles(/datum/gas/carbon_dioxide)
	H.photosynthesis_boost = 0
	P.skin_exchange(H, breath)
	TEST_ASSERT(!H.failed_last_breath, "a CO2-rich breath is a good breath for a plant")
	TEST_ASSERT(H.photosynthesis_boost > 0, "CO2 in the breath boosts photosynthesis")
	TEST_ASSERT(breath.get_moles(/datum/gas/carbon_dioxide) < co2_before, "the skin takes CO2 in")

	P.skin_exchange(H, null)
	TEST_ASSERT(H.failed_last_breath, "no air is a failed breath")
	TEST_ASSERT_EQUAL(H.photosynthesis_boost, 0, "no air, no boost")

/// P2-D7: one photosynthesis trait; the alraune data scales gains with the CO2 boost and heals only with it.
/datum/unit_test/dq_k_a_photosynthesis_shared

/datum/unit_test/dq_k_a_photosynthesis_shared/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/trait_state/photosynth/alraune/P = H.add_trait_state(/datum/trait_state/photosynth/alraune)
	TEST_ASSERT(istype(P), "the alraune photosynthesis state attaches")
	H.adjust_nutrition(-H.nutrition)
	H.adjust_nutrition(100)
	P.feed(1, 0)
	TEST_ASSERT_EQUAL(H.nutrition, 105, "full light feeds 5 without CO2")
	P.feed(1, 1)
	TEST_ASSERT_EQUAL(H.nutrition, 135, "full CO2 multiplies the gain by 6")
	H.adjust_nutrition(1000)
	var/capped = H.nutrition
	P.feed(1, 0)
	TEST_ASSERT_EQUAL(H.nutrition, capped, "no gain above the cap")

	var/mob/living/carbon/human/D = allocate(/mob/living/carbon/human)
	D.set_species(SPECIES_DIONA)
	TEST_ASSERT(D.get_trait_state(/datum/trait_state/photosynth), "diona photosynthesise through the shared trait")
	var/mob/living/carbon/human/A = allocate(/mob/living/carbon/human)
	A.set_species(SPECIES_ALRAUNE)
	TEST_ASSERT(A.get_trait_state(/datum/trait_state/photosynth), "alraunes photosynthesise through the shared trait")

/// P2-S6: a paused (total stasis) frame skips breathing through run_if: no breath cycle advances.
/datum/unit_test/life_om/dq_k_a_stasis_skips_breathing

/datum/unit_test/life_om/dq_k_a_stasis_skips_breathing/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.set_stasis(/datum/body_effect/stasis/total, src)
	var/cycle = H.breath_cycle
	var/nutrition = H.nutrition
	for(var/i in 1 to 6)
		seq_run_frame_now(H, /datum/sequence/life)
	TEST_ASSERT_EQUAL(H.breath_cycle, cycle, "total stasis takes no breath")
	TEST_ASSERT_EQUAL(H.nutrition, nutrition, "total stasis metabolises nothing")
	H.set_stasis(null, src)

/// P2-S5: species facts replace species-name checks.
/datum/unit_test/dq_k_a_species_facts

/datum/unit_test/dq_k_a_species_facts/Run()
	var/datum/species/promethean = GLOB.all_species[SPECIES_PROMETHEAN]
	TEST_ASSERT(promethean.is_slime_bodied, "prometheans are slime-bodied")
	TEST_ASSERT(!promethean.can_host_malignant, "prometheans can't host malignant organs")
	var/datum/species/vox = GLOB.all_species[SPECIES_VOX]
	TEST_ASSERT(!vox.can_host_malignant, "vox can't host malignant organs")
	var/datum/species/human = GLOB.all_species[SPECIES_HUMAN]
	TEST_ASSERT(!human.is_slime_bodied && human.can_host_malignant && !human.micro_carry, "humans have none of the special facts")
	var/datum/species/teshari = GLOB.all_species[SPECIES_TESHARI]
	TEST_ASSERT(teshari.micro_carry, "teshari are micro-carried")
	var/datum/species/diona = GLOB.all_species[SPECIES_DIONA]
	TEST_ASSERT(diona.mood_immune, "diona shrug off induced moods")
	var/datum/trait/neutral/bloodsucker/T = new
	TEST_ASSERT_EQUAL(T.var_changes["hunger_alert_style"], HUNGER_ALERT_VAMPIRE, "obligate bloodsuckers use the vampire hunger alerts")
	qdel(T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(H.hunger_alert_style(), HUNGER_ALERT_ORGANIC, "a plain human uses the organic hunger alerts")

/// A23: the radiation dose tier comes from the species' levels in one place.
/datum/unit_test/dq_k_a_radiation_dose_tier

/datum/unit_test/dq_k_a_radiation_dose_tier/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/list/levels = GLOB.radiation_levels[H.species.rad_levels]
	H.decay_radiation(H.radiation)
	TEST_ASSERT_EQUAL(H.life_radiation_dose_tier(), 0, "no dose is tier 0")
	H.add_radiation(levels["danger_2"] + 1)
	TEST_ASSERT_EQUAL(H.life_radiation_dose_tier(), 3, "past danger_2 is tier 3")
	H.decay_radiation(H.radiation)

/// A24: the human status step sleeps for a settled conscious body and wakes for fear.
/datum/unit_test/dq_k_a_status_idle_rule

/datum/unit_test/dq_k_a_status_idle_rule/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.set_fear(50)
	TEST_ASSERT(H.life_status_due(), "fear counting down keeps the status step awake")
	H.set_fear(0)
	TEST_ASSERT(H.life_status_rewake() > 0, "a living human's status step has a rewake for raw writes")
