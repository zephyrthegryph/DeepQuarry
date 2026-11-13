// Reagent contaminants (code/domains/world_model/reagents/contaminants.dm): purity and grade computed from a sparse contaminant list, blending by volume
// through add_reagent and trans_to_holder, the carry through a reaction, needs_grade, seeded source profiles, the cartridge stamp, and the effect on a patient.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

#define DQ_CONTAM_REGIME "dq_contam"

/// A holder that runs the contaminant fixture regime.
/datum/reagents/dq_contam

/datum/reagents/dq_contam/xform_regime()
	return DQ_CONTAM_REGIME

/transformation/dq_contam

CAPABILITIES(/transformation/dq_contam)
	transformation(regime = DQ_CONTAM_REGIME, says = "")

/// Takes mercury and chlorine, makes tin: the contaminants of the two go into the tin.
/transformation/dq_contam/carry

CAPABILITIES(/transformation/dq_contam/carry)
	configure(transformation(takes = list(reagent(REAGENT_ID_MERCURY, 1), reagent(REAGENT_ID_CHLORINE, 1)), makes = list(reagent(REAGENT_ID_TIN, 2))))

/// Takes fluorine and calcium, but only fluorine of Pharma grade or better.
/transformation/dq_contam/graded

CAPABILITIES(/transformation/dq_contam/graded)
	configure(transformation(takes = list(reagent(REAGENT_ID_FLUORINE, 1), reagent(REAGENT_ID_CALCIUM, 1)), makes = list(reagent(REAGENT_ID_CARBON, 1)), needs_grade = list(REAGENT_ID_FLUORINE = GRADE_PHARMA)))

/// A beaker's holder (the reagents of a real container, in the test world).
/datum/unit_test/proc/dq_contam_holder(type = /obj/item/reagent_containers/glass/beaker/large)
	var/obj/item/reagent_containers/glass/beaker/B = allocate(type, test_floor())
	return B.reagents

/// A fixture holder of the contaminant regime, inside a beaker.
/datum/unit_test/proc/dq_contam_regime_holder()
	var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker, test_floor())
	var/datum/reagents/dq_contam/H = new(1000, B)
	own(H)
	return H

/datum/unit_test/proc/dq_contam_near(a, b)
	return abs(a - b) < 0.001

/datum/unit_test/dq_contaminant_purity_and_grade
	boot_needs = list()

/datum/unit_test/dq_contaminant_purity_and_grade/Run()
	var/datum/reagents/H = dq_contam_holder()
	H.add_reagent(REAGENT_ID_DEXALIN, 10, safety = 1)
	var/datum/reagent/R = H.get_reagent(REAGENT_ID_DEXALIN)
	TEST_ASSERT_NULL(R.contaminants, "a pure reagent carries no list (sparse)")
	TEST_ASSERT_EQUAL(R.purity(), 1, "a pure reagent has purity 1")
	TEST_ASSERT_EQUAL(R.grade(), GRADE_REAGENT, "a pure reagent is Reagent grade")
	TEST_ASSERT_EQUAL(R.potency(), 1, "a pure reagent acts at full potency")
	TEST_ASSERT_NULL(R.purity_summary(), "a pure reagent has nothing to report beside its name")
	R.set_contaminants(list(CONTAMINANT_HEAVY_METAL = 0.005))
	TEST_ASSERT(dq_contam_near(R.purity(), 0.995), "purity is one minus the fractions")
	TEST_ASSERT_EQUAL(R.grade(), GRADE_REAGENT, "99.5% is Reagent grade")
	R.set_contaminants(list(CONTAMINANT_HEAVY_METAL = 0.04, CONTAMINANT_SALTS = 0.04))
	TEST_ASSERT(dq_contam_near(R.purity(), 0.92), "the fractions add")
	TEST_ASSERT_EQUAL(R.grade(), GRADE_PHARMA, "92% is Pharma")
	TEST_ASSERT(dq_contam_near(R.potency(), 0.92), "a contaminated volume acts with its purity")
	R.set_contaminants(list(CONTAMINANT_SALTS = 0.25))
	TEST_ASSERT_EQUAL(R.grade(), GRADE_STANDARD, "75% is Standard")
	R.set_contaminants(list(CONTAMINANT_SALTS = 0.5))
	TEST_ASSERT_EQUAL(R.grade(), GRADE_CRUDE, "50% is Crude")
	R.set_contaminants(list(CONTAMINANT_SALTS = 0.0))
	TEST_ASSERT_NULL(R.contaminants, "a zero fraction is not kept")
	TEST_ASSERT_EQUAL(grade_of_purity(0.9), GRADE_PHARMA, "the band edges belong to the grade above")
	TEST_ASSERT_EQUAL(grade_of_purity(0.6), GRADE_STANDARD, "60% is Standard")
	TEST_ASSERT_EQUAL(grade_of_purity(0.99), GRADE_REAGENT, "99% is Reagent")
	TEST_ASSERT_EQUAL(grade_name(GRADE_PHARMA), "Pharma", "grade_name() names a grade")
	TEST_ASSERT(length(purity_band_text(GRADE_STANDARD)), "a grade has its band as text")
	var/list/defs = contaminant_defs()
	TEST_ASSERT(length(defs) >= 10, "the registry lists the contaminant types")
	for(var/id in defs)
		var/datum/contaminant/C = defs[id]
		TEST_ASSERT(C.name && C.role && C.desc && C.effect_text, "[id] has a name, role, description and effect text for the book")

/datum/unit_test/dq_contaminant_add_reagent_blends_by_volume
	boot_needs = list()

/datum/unit_test/dq_contaminant_add_reagent_blends_by_volume/Run()
	var/datum/reagents/H = dq_contam_holder()
	H.add_reagent(REAGENT_ID_DEXALIN, 10, safety = 1, contaminants = list(CONTAMINANT_HEAVY_METAL = 0.2))
	var/datum/reagent/R = H.get_reagent(REAGENT_ID_DEXALIN)
	TEST_ASSERT(dq_contam_near(R.contaminants[CONTAMINANT_HEAVY_METAL], 0.2), "a new reagent takes the list it arrives with")
	H.add_reagent(REAGENT_ID_DEXALIN, 10, safety = 1)
	TEST_ASSERT(dq_contam_near(R.contaminants[CONTAMINANT_HEAVY_METAL], 0.1), "10u at 20% and 10u pure average to 10%")
	H.add_reagent(REAGENT_ID_DEXALIN, 20, safety = 1, contaminants = list(CONTAMINANT_SULFUR = 0.2))
	TEST_ASSERT(dq_contam_near(R.contaminants[CONTAMINANT_HEAVY_METAL], 0.05), "the old fractions are weighted by the old volume (20 of 40)")
	TEST_ASSERT(dq_contam_near(R.contaminants[CONTAMINANT_SULFUR], 0.1), "the new fractions by the added volume (20 of 40)")
	H.remove_reagent(REAGENT_ID_DEXALIN, 15, safety = 1)
	TEST_ASSERT(dq_contam_near(R.contaminants[CONTAMINANT_HEAVY_METAL], 0.05), "removal does not change a fraction")
	// The list the caller passed is never aliased or edited.
	var/list/mine = list(CONTAMINANT_SALTS = 0.1)
	var/datum/reagents/other = dq_contam_holder()
	other.add_reagent(REAGENT_ID_DEXALIN, 5, safety = 1, contaminants = mine)
	other.add_reagent(REAGENT_ID_DEXALIN, 5, safety = 1)
	TEST_ASSERT(dq_contam_near(mine[CONTAMINANT_SALTS], 0.1), "the caller's list is left alone")
	TEST_ASSERT(dq_contam_near(other.get_reagent(REAGENT_ID_DEXALIN).contaminants[CONTAMINANT_SALTS], 0.05), "the holder blended its own copy")

/datum/unit_test/dq_contaminant_transfer_carries
	boot_needs = list()

/datum/unit_test/dq_contaminant_transfer_carries/Run()
	var/datum/reagents/source = dq_contam_holder()
	source.add_reagent(REAGENT_ID_DEXALIN, 50, safety = 1, contaminants = list(CONTAMINANT_SALTS = 0.1))
	var/datum/reagents/empty = dq_contam_holder()
	source.trans_to_holder(empty, 20)
	var/datum/reagent/moved = empty.get_reagent(REAGENT_ID_DEXALIN)
	TEST_ASSERT_NOTNULL(moved, "the reagent moved")
	TEST_ASSERT(dq_contam_near(moved.contaminants[CONTAMINANT_SALTS], 0.1), "a transfer into an empty holder carries the fractions")
	var/datum/reagents/stocked = dq_contam_holder()
	stocked.add_reagent(REAGENT_ID_DEXALIN, 20, safety = 1)
	source.trans_to_holder(stocked, 20)
	TEST_ASSERT(dq_contam_near(stocked.get_reagent(REAGENT_ID_DEXALIN).contaminants[CONTAMINANT_SALTS], 0.05), "into 20u of pure the 20u at 10% average to 5%")
	TEST_ASSERT(dq_contam_near(source.get_reagent(REAGENT_ID_DEXALIN).contaminants[CONTAMINANT_SALTS], 0.1), "what stays behind keeps its fraction")
	// Moving by id.
	var/obj/item/reagent_containers/glass/beaker/target = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	source.trans_id_to(target, REAGENT_ID_DEXALIN, 5)
	TEST_ASSERT(dq_contam_near(target.reagents.get_reagent(REAGENT_ID_DEXALIN).contaminants[CONTAMINANT_SALTS], 0.1), "trans_id_to carries the fractions")
	var/datum/reagents/by_type = dq_contam_holder()
	source.trans_type_to(by_type, REAGENT_ID_DEXALIN, 5)
	TEST_ASSERT(dq_contam_near(by_type.get_reagent(REAGENT_ID_DEXALIN).contaminants[CONTAMINANT_SALTS], 0.1), "trans_type_to carries the fractions")

/datum/unit_test/dq_contaminant_reaction_carries
	boot_needs = list()

/datum/unit_test/dq_contaminant_reaction_carries/Run()
	var/datum/reagents/dq_contam/H = dq_contam_regime_holder()
	H.add_reagent(REAGENT_ID_MERCURY, 10, safety = 1, contaminants = list(CONTAMINANT_HEAVY_METAL = 0.2))
	H.add_reagent(REAGENT_ID_CHLORINE, 10, safety = 1)
	var/list/fired = xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(length(fired), 1, "the rule fired")
	var/datum/reagent/product = H.get_reagent(REAGENT_ID_TIN)
	TEST_ASSERT_NOTNULL(product, "the product was made")
	TEST_ASSERT_NOTNULL(product.contaminants, "the product carries the reactants' contaminants")
	TEST_ASSERT(dq_contam_near(product.contaminants[CONTAMINANT_HEAVY_METAL], 0.1), "the average over the units used: 10u at 20% and 10u pure is 10%")
	// Two clean reactants make a clean product (sparse).
	var/datum/reagents/dq_contam/clean = dq_contam_regime_holder()
	clean.add_reagent(REAGENT_ID_MERCURY, 10, safety = 1)
	clean.add_reagent(REAGENT_ID_CHLORINE, 10, safety = 1)
	xform_settle_reagents(clean)
	TEST_ASSERT_NULL(clean.get_reagent(REAGENT_ID_TIN).contaminants, "a pure product has no list")

/datum/unit_test/dq_contaminant_needs_grade
	boot_needs = list()

/datum/unit_test/dq_contaminant_needs_grade/Run()
	var/datum/xform/X = xform_of(/transformation/dq_contam/graded)
	TEST_ASSERT_NOTNULL(X, "the graded rule compiled")
	TEST_ASSERT_EQUAL(X.needs_grade[REAGENT_ID_FLUORINE], GRADE_PHARMA, "needs_grade is kept on the rule")
	var/datum/reagents/dq_contam/low = dq_contam_regime_holder()
	low.add_reagent(REAGENT_ID_FLUORINE, 10, safety = 1, contaminants = list(CONTAMINANT_INERT_FILLER = 0.2))
	low.add_reagent(REAGENT_ID_CALCIUM, 10, safety = 1)
	TEST_ASSERT(!xform_matches(X, low), "Standard fluorine does not meet a Pharma requirement")
	TEST_ASSERT_EQUAL(length(xform_settle_reagents(low)), 0, "so nothing reacts")
	TEST_ASSERT(dq_contam_near(low.get_reagent_amount(REAGENT_ID_FLUORINE), 10), "and nothing is taken")
	var/datum/reagents/dq_contam/high = dq_contam_regime_holder()
	high.add_reagent(REAGENT_ID_FLUORINE, 10, safety = 1, contaminants = list(CONTAMINANT_INERT_FILLER = 0.05))
	high.add_reagent(REAGENT_ID_CALCIUM, 10, safety = 1)
	TEST_ASSERT(xform_matches(X, high), "Pharma fluorine meets it")
	TEST_ASSERT_EQUAL(length(xform_settle_reagents(high)), 1, "and the rule fires")
	var/datum/reagents/dq_contam/pure = dq_contam_regime_holder()
	pure.add_reagent(REAGENT_ID_FLUORINE, 10, safety = 1)
	pure.add_reagent(REAGENT_ID_CALCIUM, 10, safety = 1)
	TEST_ASSERT(xform_matches(X, pure), "a pure reagent meets any grade")
	// Topping up the batch with pure stock lifts it over the line.
	low.add_reagent(REAGENT_ID_FLUORINE, 30, safety = 1)
	TEST_ASSERT(xform_matches(X, low), "10u at 20% blended with 30u pure is 95% pure: Pharma")

/datum/unit_test/dq_contaminant_source_profiles
	boot_needs = list()

/datum/unit_test/dq_contaminant_source_profiles/Run()
	var/old_seed = GLOB.round_seed
	rolls_fix_seed(9001)
	var/list/first = chem_source_profile(REAGENT_ID_DEXALIN, "chemical supply")
	var/list/again = chem_source_profile(REAGENT_ID_DEXALIN, "chemical supply")
	TEST_ASSERT_NOTNULL(first, "a chemistry reagent's source rolls a profile")
	TEST_ASSERT_EQUAL(contaminants_text(first), contaminants_text(again), "the same seed and source roll the same profile")
	var/list/other_reagent = chem_source_profile(REAGENT_ID_FLUORINE, "chemical supply")
	var/list/other_source = chem_source_profile(REAGENT_ID_DEXALIN, "black market")
	TEST_ASSERT_NOTEQUAL(contaminants_text(first), contaminants_text(other_reagent), "two reagents' sources differ")
	TEST_ASSERT_NOTEQUAL(contaminants_text(first), contaminants_text(other_source), "two sources of one reagent differ")
	// The default grade is Standard: the purity sits inside its band and 2-3 types are chosen.
	var/sum = 0
	for(var/id in first)
		sum += first[id]
		TEST_ASSERT(contaminant_def(id), "[id] is a registry row")
	TEST_ASSERT_EQUAL(grade_of_purity(1 - sum), GRADE_STANDARD, "the default profile is Standard grade ([1 - sum])")
	TEST_ASSERT(length(first) >= 2 && length(first) <= 3, "two or three contaminant types ([length(first)])")
	var/list/premium = chem_source_profile(REAGENT_ID_DEXALIN, "medicine supply", GRADE_PHARMA)
	var/premium_sum = 0
	for(var/id in premium)
		premium_sum += premium[id]
	TEST_ASSERT_EQUAL(grade_of_purity(1 - premium_sum), GRADE_PHARMA, "a premium source rolls Pharma ([1 - premium_sum])")
	rolls_fix_seed(9002)
	TEST_ASSERT_NOTEQUAL(contaminants_text(first), contaminants_text(chem_source_profile(REAGENT_ID_DEXALIN, "chemical supply")), "a new round seed rolls a new profile")
	// Drinks, ethanol, water and blood have no impure source.
	TEST_ASSERT_NULL(chem_source_profile(REAGENT_ID_WATER, "chemical supply"), "water has no profile")
	TEST_ASSERT_NULL(chem_source_profile(REAGENT_ID_ETHANOL, "chemical supply"), "ethanol has no profile")
	TEST_ASSERT_NULL(chem_source_profile(REAGENT_ID_BLOOD, "chemical supply"), "blood has no profile")
	rolls_fix_seed(old_seed)

/datum/unit_test/dq_contaminant_cartridge_stamp
	boot_needs = list()

/datum/unit_test/dq_contaminant_cartridge_stamp/Run()
	var/obj/item/reagent_containers/chem_disp_cartridge/C = allocate(/obj/item/reagent_containers/chem_disp_cartridge/dexalin, test_floor())
	var/datum/reagent/R = C.reagents.get_reagent(REAGENT_ID_DEXALIN)
	TEST_ASSERT_NOTNULL(R, "the cartridge came filled")
	TEST_ASSERT_NOTNULL(R.contaminants, "a chemical cartridge's stock carries its source's contaminants")
	TEST_ASSERT_EQUAL(R.grade(), GRADE_STANDARD, "the chemical supply is Standard grade")
	var/obj/item/reagent_containers/chem_disp_cartridge/premium = allocate(/obj/item/reagent_containers/chem_disp_cartridge/dexalin/small, test_floor())
	var/datum/reagent/P = premium.reagents.get_reagent(REAGENT_ID_DEXALIN)
	TEST_ASSERT_NOTNULL(P, "the medicine cartridge came filled")
	TEST_ASSERT_EQUAL(P.grade(), GRADE_PHARMA, "the medicine cartridge is a premium source: Pharma")
	var/obj/item/reagent_containers/chem_disp_cartridge/water = own(variant_new(VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/water), test_floor()))
	TEST_ASSERT_NULL(water.reagents.get_reagent(REAGENT_ID_WATER)?.contaminants, "a water cartridge stays pure")

/datum/unit_test/dq_contaminant_effects
	boot_needs = list()

/datum/unit_test/dq_contaminant_effects/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.organ_in(O_LIVER)
	TEST_ASSERT_NOTNULL(liver, "no liver")
	var/datum/reagents/holder = dq_contam_holder()
	holder.add_reagent(REAGENT_ID_DEXALIN, 10, safety = 1)
	var/datum/reagent/pure = holder.get_reagent(REAGENT_ID_DEXALIN)
	pure.apply_contaminants(H, 10)
	TEST_ASSERT_EQUAL(liver.damage, 0, "a pure reagent harms nothing")
	pure.set_contaminants(list(CONTAMINANT_HEAVY_METAL = 0.5))
	TEST_ASSERT(dq_contam_near(pure.potency(), 0.5), "potency is the purity of a contaminated reagent")
	pure.apply_contaminants(H, 10)
	TEST_ASSERT(liver.damage > 0, "heavy metals strain the liver")
	var/small_damage = liver.damage
	liver.clear_lesions()
	pure.apply_contaminants(H, 5)
	TEST_ASSERT(liver.damage > 0 && liver.damage < small_damage, "the damage scales with the amount metabolised")


#endif
