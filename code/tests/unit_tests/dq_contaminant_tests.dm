// Contaminant reagents (code/domains/world_model/reagents/contaminants.dm, code/content/reagents/reagents/content/contaminants.dm): impurities are reagents with
// a volume of their own. Purity and grade are properties of a mixture; a cartridge's source profile says how many units of each contaminant come with a unit
// of stock; dispensing, recharging, transferring and ingesting carry them like any reagent; each role does its own harm from its own metabolism; a recipe's
// and no recipe makes or takes a contaminant but neutralisation (code/content/reagents/reactions/instant/neutralisation.dm).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

#define DQ_CONTAM_REGIME "dq_contam"

/// A holder that runs the contaminant fixture regime.
/datum/reagents/dq_contam

/datum/reagents/dq_contam/xform_regime()
	return DQ_CONTAM_REGIME

/transformation/dq_contam

CAPABILITIES(/transformation/dq_contam)
	transformation(regime = DQ_CONTAM_REGIME, says = "")

/// Takes mercury and chlorine, makes tin.
/transformation/dq_contam/plain

CAPABILITIES(/transformation/dq_contam/plain)
	configure(transformation(takes = list(reagent(REAGENT_ID_MERCURY, 1), reagent(REAGENT_ID_CHLORINE, 1)), makes = list(reagent(REAGENT_ID_TIN, 2))))

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

/// Units of contaminants per unit of stock in a holder: its contaminant volume over what is not contaminant.
/datum/unit_test/proc/dq_contam_ratio(datum/reagents/H)
	return H.contaminant_volume() / (H.total_volume - H.contaminant_volume())

/// The sum of a source profile: units of contaminant per unit of stock.
/datum/unit_test/proc/dq_contam_profile_sum(list/profile)
	var/sum = 0
	for(var/id in profile)
		sum += profile[id]
	return sum

/// A cartridge of dexalin (Standard grade, the chemical supply).
/datum/unit_test/proc/dq_contam_cartridge(type = /obj/item/reagent_containers/chem_disp_cartridge/dexalin)
	return allocate(type, test_floor())

/datum/unit_test/dq_contaminant_purity_and_grade
	boot_needs = list()

/datum/unit_test/dq_contaminant_purity_and_grade/Run()
	var/datum/reagents/H = dq_contam_regime_holder() // 1000u: the Crude step below holds 233u
	TEST_ASSERT_EQUAL(H.purity(), 1, "an empty holder is pure")
	H.add_reagent(REAGENT_ID_DEXALIN, 100, safety = 1)
	TEST_ASSERT_EQUAL(H.contaminant_volume(), 0, "no contaminant yet")
	TEST_ASSERT_EQUAL(H.purity(), 1, "a holder with no contaminant has purity 1")
	TEST_ASSERT_EQUAL(H.grade(), GRADE_REAGENT, "and is Reagent grade")
	TEST_ASSERT_NULL(H.purity_summary(), "a pure mixture has nothing to report beside its contents")
	H.add_reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL, 0.5, safety = 1)
	TEST_ASSERT(dq_contam_near(H.contaminant_volume(), 0.5), "the contaminant is a volume of its own in the holder")
	TEST_ASSERT(dq_contam_near(H.get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL), 0.5), "readable like any reagent")
	TEST_ASSERT(dq_contam_near(H.purity(), 100 / 100.5), "purity is one minus the contaminant share of the total")
	TEST_ASSERT_EQUAL(H.grade(), GRADE_REAGENT, "99.5% is Reagent grade")
	H.add_reagent(REAGENT_ID_CONTAMINANT_SALTS, 7.5, safety = 1)
	TEST_ASSERT(dq_contam_near(H.purity(), 100 / 108), "the contaminants add: 8u in 108u")
	TEST_ASSERT_EQUAL(H.grade(), GRADE_PHARMA, "92.6% is Pharma")
	TEST_ASSERT_EQUAL(H.purity_summary(), "[grade_name(GRADE_PHARMA)] [round(H.purity() * 100)]%", "the summary names grade and purity")
	H.add_reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 25, safety = 1)
	TEST_ASSERT_EQUAL(H.grade(), GRADE_STANDARD, "33u in 133u is Standard")
	H.add_reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 100, safety = 1)
	TEST_ASSERT_EQUAL(H.grade(), GRADE_CRUDE, "133u of contaminant in 233u is Crude")
	// Dilution is physical: pure stock added back raises the purity of the mixture.
	var/datum/reagents/bigger = dq_contam_holder()
	bigger.add_reagent(REAGENT_ID_DEXALIN, 10, safety = 1)
	bigger.add_reagent(REAGENT_ID_CONTAMINANT_INERT_FILLER, 10, safety = 1)
	TEST_ASSERT_EQUAL(bigger.grade(), GRADE_CRUDE, "half and half is Crude")
	bigger.add_reagent(REAGENT_ID_DEXALIN, 40, safety = 1)
	TEST_ASSERT(dq_contam_near(bigger.purity(), 50 / 60), "50u of stock in 60u")
	TEST_ASSERT_EQUAL(bigger.grade(), GRADE_STANDARD, "adding stock dilutes the contaminants")
	TEST_ASSERT_EQUAL(grade_of_purity(0.9), GRADE_PHARMA, "the band edges belong to the grade above")
	TEST_ASSERT_EQUAL(grade_of_purity(0.6), GRADE_STANDARD, "60% is Standard")
	TEST_ASSERT_EQUAL(grade_of_purity(0.99), GRADE_REAGENT, "99% is Reagent")
	TEST_ASSERT_EQUAL(grade_name(GRADE_PHARMA), "Pharma", "grade_name() names a grade")
	TEST_ASSERT(length(purity_band_text(GRADE_STANDARD)), "a grade has its band as text")
	var/list/ids = contaminant_ids()
	TEST_ASSERT(length(ids) >= 10, "the contaminant reagents are found")
	for(var/id in ids)
		var/datum/reagent/contaminant/C = contaminant_def(id)
		TEST_ASSERT_NOTNULL(C, "[id] is a contaminant reagent")
		TEST_ASSERT(C.name && C.contaminant_role && C.description && C.effect_text, "[id] has a name, role, description and effect text for the book")
		TEST_ASSERT_NOTEQUAL(C.description, REAGENT_DESC_DEVELOPER_WARNING, "[id] has its own description")

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
	// The profile is units of each contaminant per unit of stock; stock and contaminants together fall in the grade's band.
	for(var/id in first)
		TEST_ASSERT(contaminant_def(id), "[id] is a contaminant reagent")
		TEST_ASSERT(first[id] > 0, "[id] comes with the stock")
	var/purity = 1 / (1 + dq_contam_profile_sum(first))
	TEST_ASSERT_EQUAL(grade_of_purity(purity), GRADE_STANDARD, "the default profile makes a Standard mixture ([purity])")
	TEST_ASSERT(length(first) >= 2 && length(first) <= 3, "two or three contaminant types ([length(first)])")
	var/list/premium = chem_source_profile(REAGENT_ID_DEXALIN, "medicine supply", GRADE_PHARMA)
	TEST_ASSERT_EQUAL(grade_of_purity(1 / (1 + dq_contam_profile_sum(premium))), GRADE_PHARMA, "a premium source makes a Pharma mixture")
	var/list/crude = chem_source_profile(REAGENT_ID_DEXALIN, "black market", GRADE_CRUDE)
	TEST_ASSERT_EQUAL(grade_of_purity(1 / (1 + dq_contam_profile_sum(crude))), GRADE_CRUDE, "a crude source makes a Crude mixture")
	rolls_fix_seed(9002)
	TEST_ASSERT_NOTEQUAL(contaminants_text(first), contaminants_text(chem_source_profile(REAGENT_ID_DEXALIN, "chemical supply")), "a new round seed rolls a new profile")
	// Drinks, ethanol, water and blood have no impure source, and nor does a contaminant.
	TEST_ASSERT_NULL(chem_source_profile(REAGENT_ID_WATER, "chemical supply"), "water has no profile")
	TEST_ASSERT_NULL(chem_source_profile(REAGENT_ID_ETHANOL, "chemical supply"), "ethanol has no profile")
	TEST_ASSERT_NULL(chem_source_profile(REAGENT_ID_BLOOD, "chemical supply"), "blood has no profile")
	TEST_ASSERT_NULL(chem_source_profile(REAGENT_ID_CONTAMINANT_SALTS, "chemical supply"), "a contaminant has no profile")
	rolls_fix_seed(old_seed)

/// Dispensing gives the stock asked for and the contaminants that come with it, as real volumes in the beaker.
/datum/unit_test/dq_contaminant_dispense_gives_stock_and_contaminants
	boot_needs = list()

/datum/unit_test/dq_contaminant_dispense_gives_stock_and_contaminants/Run()
	var/obj/item/reagent_containers/chem_disp_cartridge/C = dq_contam_cartridge()
	var/list/profile = chem_source_profile(REAGENT_ID_DEXALIN, C.source_key, C.source_grade)
	TEST_ASSERT_NOTNULL(profile, "the cartridge's source has a profile")
	TEST_ASSERT_NOTNULL(C.reagents.get_reagent(REAGENT_ID_DEXALIN), "the cartridge came filled with its stock")
	TEST_ASSERT(dq_contam_near(C.reagents.total_volume, C.volume), "stock and contaminants fill it to its volume")
	TEST_ASSERT(dq_contam_near(dq_contam_ratio(C.reagents), dq_contam_profile_sum(profile)), "the contaminants in it are the profile's per unit of stock")
	for(var/id in profile)
		TEST_ASSERT(dq_contam_near(C.reagents.get_reagent_amount(id), C.reagents.get_reagent_amount(REAGENT_ID_DEXALIN) * profile[id]), "[id] sits in the cartridge at the profile's rate")
	TEST_ASSERT_EQUAL(C.reagents.grade(), GRADE_STANDARD, "the chemical supply is a Standard mixture")
	var/obj/item/reagent_containers/glass/beaker/large/B = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	var/dispensed = C.dispense_to(B, 20)
	TEST_ASSERT(dq_contam_near(dispensed, 20), "the stock asked for is the stock dispensed ([dispensed])")
	TEST_ASSERT(dq_contam_near(B.reagents.get_reagent_amount(REAGENT_ID_DEXALIN), 20), "20u of the stock reached the beaker")
	for(var/id in profile)
		TEST_ASSERT(dq_contam_near(B.reagents.get_reagent_amount(id), 20 * profile[id]), "[id] came along: [profile[id]]u per unit of stock")
	TEST_ASSERT(B.reagents.total_volume > 20, "the beaker holds the stock and its contaminants")
	TEST_ASSERT_EQUAL(B.reagents.grade(), GRADE_STANDARD, "the beaker's mixture is graded like the cartridge's")
	// A synthesizer's pull goes to a holder the same way.
	var/datum/reagents/vessel = dq_contam_holder()
	TEST_ASSERT(dq_contam_near(C.dispense_to_holder(vessel, 10), 10), "10u of stock into a holder")
	TEST_ASSERT(dq_contam_near(vessel.get_reagent_amount(REAGENT_ID_DEXALIN), 10), "the stock is there")
	TEST_ASSERT(dq_contam_near(dq_contam_ratio(vessel), dq_contam_profile_sum(profile)), "and its contaminants in the same proportion")
	// The medicine crate is a premium source; water has no contaminants at all.
	var/obj/item/reagent_containers/chem_disp_cartridge/premium = dq_contam_cartridge(/obj/item/reagent_containers/chem_disp_cartridge/dexalin/small)
	TEST_ASSERT_EQUAL(premium.reagents.grade(), GRADE_PHARMA, "the medicine cartridge holds a Pharma mixture")
	var/obj/item/reagent_containers/chem_disp_cartridge/water = own(variant_new(VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/water), test_floor()))
	TEST_ASSERT_EQUAL(water.reagents.contaminant_volume(), 0, "a water cartridge stays pure")
	TEST_ASSERT(dq_contam_near(water.reagents.get_reagent_amount(REAGENT_ID_WATER), water.volume), "and full of water")

/// A recharge adds contaminants in the cartridge's own proportions, so it never raises the purity.
/datum/unit_test/dq_contaminant_recharge_keeps_proportions
	boot_needs = list()

/datum/unit_test/dq_contaminant_recharge_keeps_proportions/Run()
	var/obj/item/reagent_containers/chem_disp_cartridge/C = dq_contam_cartridge()
	var/purity = C.reagents.purity()
	var/ratio = dq_contam_ratio(C.reagents)
	C.reagents.remove_any(200)
	TEST_ASSERT(dq_contam_near(C.reagents.total_volume, C.volume - 200), "a draw took the stock and its contaminants")
	TEST_ASSERT(dq_contam_near(C.reagents.purity(), purity), "which leaves the proportions as they were")
	var/added = C.add_stock(REAGENT_ID_DEXALIN, 5)
	TEST_ASSERT(dq_contam_near(added, 5), "a recharge step adds its 5u of stock ([added])")
	TEST_ASSERT(dq_contam_near(dq_contam_ratio(C.reagents), ratio), "with contaminants in the same proportion")
	TEST_ASSERT(C.reagents.purity() >= purity - 0.0001 && C.reagents.purity() <= purity + 0.0001, "so the purity is the same after the recharge")
	for(var/i in 1 to 10)
		C.add_stock(REAGENT_ID_DEXALIN, 5)
	TEST_ASSERT(dq_contam_near(C.reagents.purity(), purity), "and after many")
	TEST_ASSERT(C.reagents.total_volume <= C.volume + 0.001, "never past the cartridge's volume")
	// The dispenser's own recharge step does the same.
	var/obj/machinery/chemical_dispenser/ert/D = allocate(/obj/machinery/chemical_dispenser/ert, test_floor())
	D.cartridges[C.label] = C
	C.reagents.remove_any(150)
	var/before = C.reagents.total_volume
	D.process_tick = 0
	D.work_step(null)
	TEST_ASSERT(C.reagents.total_volume > before + 0.1, "the dispenser recharged the cartridge")
	TEST_ASSERT(dq_contam_near(dq_contam_ratio(C.reagents), ratio), "and its contaminants came in the same proportion")
	TEST_ASSERT(dq_contam_near(C.reagents.purity(), purity), "the purity did not rise")

/// A transfer carries a contaminant exactly as far as it carries any reagent.
/datum/unit_test/dq_contaminant_transfer_and_ingest_carry
	boot_needs = list()

/datum/unit_test/dq_contaminant_transfer_and_ingest_carry/Run()
	var/datum/reagents/source = dq_contam_holder()
	source.add_reagent(REAGENT_ID_DEXALIN, 40, safety = 1)
	source.add_reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL, 4, safety = 1)
	source.add_reagent(REAGENT_ID_CONTAMINANT_SALTS, 2, safety = 1)
	var/datum/reagents/empty = dq_contam_holder()
	source.trans_to_holder(empty, 23)
	TEST_ASSERT(dq_contam_near(empty.total_volume, 23), "23u moved")
	TEST_ASSERT(dq_contam_near(empty.get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL), 2), "half of the mixture took half of the heavy metals (23 of 46)")
	TEST_ASSERT(dq_contam_near(empty.get_reagent_amount(REAGENT_ID_CONTAMINANT_SALTS), 1), "and half of the salts")
	TEST_ASSERT(dq_contam_near(empty.purity(), source.purity()), "the purity of what moved is the purity of what stayed")
	TEST_ASSERT(dq_contam_near(source.get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL), 2), "what stays behind keeps its share")
	// Into a pure stock the contaminants are diluted by volume.
	var/datum/reagents/stocked = dq_contam_holder()
	stocked.add_reagent(REAGENT_ID_DEXALIN, 23, safety = 1)
	empty.trans_to_holder(stocked, 23)
	TEST_ASSERT(dq_contam_near(stocked.get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL), 2), "the contaminants arrived whole")
	TEST_ASSERT(dq_contam_near(stocked.purity(), 1 - 3 / 46), "3u of contaminant in 46u")
	// By id, a stock reagent moves with its share of the contaminants; a contaminant is never picked out on its own (code/domains/world_model/reagents/holder.dm draw_portion()).
	var/datum/reagents/by_type = dq_contam_holder()
	TEST_ASSERT_NULL(stocked.trans_type_to(by_type, REAGENT_ID_CONTAMINANT_SALTS, 0.5), "a contaminant cannot be moved by id")
	TEST_ASSERT_EQUAL(by_type.total_volume, 0, "and nothing arrives")
	var/obj/item/reagent_containers/glass/beaker/target = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	TEST_ASSERT_NULL(stocked.trans_id_to(target, REAGENT_ID_CONTAMINANT_HEAVY_METAL, 1), "nor by trans_id_to")
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 0, "which moves nothing")
	stocked.trans_id_to(target, REAGENT_ID_DEXALIN, 5)
	TEST_ASSERT(dq_contam_near(target.reagents.get_reagent_amount(REAGENT_ID_DEXALIN), 5), "a stock reagent moves by id")
	TEST_ASSERT(dq_contam_near(target.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL), 2 * 5 / 43), "with the share of the contaminants that goes with that much of the stock")
	// Ingested: into the stomach with the mixture, then on into the blood as it is absorbed.
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	source.trans_to_holder(H.ingested, 20)
	TEST_ASSERT(H.ingested.get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL) > 0, "the stomach holds the contaminants that came with it")
	var/datum/reagent/swallowed = H.ingested.get_reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL)
	swallowed.affect_ingest(H, 0, 0.5)
	TEST_ASSERT(dq_contam_near(H.bloodstr.get_reagent_amount(REAGENT_ID_CONTAMINANT_HEAVY_METAL), 0.5), "an ingested contaminant is absorbed into the blood like any reagent")
	// Splashed: the contaminants go with the liquid.
	var/datum/reagents/splash = dq_contam_holder()
	splash.add_reagent(REAGENT_ID_DEXALIN, 10, safety = 1)
	splash.add_reagent(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE, 2, safety = 1)
	var/obj/item/reagent_containers/glass/beaker/splashed = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	splash.trans_to(splashed, 12)
	TEST_ASSERT(dq_contam_near(splashed.reagents.get_reagent_amount(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE), 2), "a pour into a container takes them too")

/// Each role does its own harm from its own metabolism: toxic strains an organ or poisons, reactive burns, biological poisons and warms, inert does nothing.
/datum/unit_test/dq_contaminant_effects
	boot_needs = list()

/datum/unit_test/dq_contaminant_effects/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/reagents/holder = dq_contam_regime_holder() // a holder that does not react: an acid and a base would cancel in a beaker
	for(var/id in contaminant_ids())
		holder.add_reagent(id, 10, safety = 1)
	// Toxic, with an organ: the liver.
	var/obj/item/organ/internal/liver = H.organ_in(O_LIVER)
	TEST_ASSERT_NOTNULL(liver, "no liver")
	var/datum/reagent/contaminant/toxic/metal = holder.get_reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL)
	TEST_ASSERT_EQUAL(metal.contaminant_role, CONTAMINANT_ROLE_TOXIC, "heavy metals are toxic")
	metal.affect_blood(H, 0, 10)
	TEST_ASSERT(liver.damage > 0, "heavy metals strain the liver")
	var/big_damage = liver.damage
	liver.clear_lesions()
	metal.affect_blood(H, 0, 5)
	TEST_ASSERT(liver.damage > 0 && liver.damage < big_damage, "the damage scales with the amount metabolised")
	var/obj/item/organ/internal/kidney = H.organ_in(O_KIDNEYS)
	var/datum/reagent/contaminant/toxic/sulfur = holder.get_reagent(REAGENT_ID_CONTAMINANT_SULFUR)
	sulfur.affect_blood(H, 0, 10)
	TEST_ASSERT(kidney.damage > 0, "sulfur compounds strain the kidneys")
	// Toxic, general: no organ, a toxin.
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human)
	var/before_toxin = other.injury_load(INJURY_CATEGORY_TOXIC)
	var/datum/reagent/contaminant/toxic/residue = holder.get_reagent(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE)
	residue.affect_blood(other, 0, 10)
	TEST_ASSERT(other.injury_load(INJURY_CATEGORY_TOXIC) > before_toxin, "organic residue is a general toxin")
	// Reactive: a burn, by chance.
	var/mob/living/carbon/human/burned = allocate(/mob/living/carbon/human)
	var/datum/reagent/contaminant/reactive/acid = holder.get_reagent(REAGENT_ID_CONTAMINANT_ACID_RESIDUE)
	TEST_ASSERT_EQUAL(acid.contaminant_role, CONTAMINANT_ROLE_REACTIVE, "acid residue is reactive")
	var/before_burn = burned.injury_load(INJURY_CATEGORY_THERMAL)
	acid.burn_chance = 0
	acid.affect_blood(burned, 0, 10)
	TEST_ASSERT_EQUAL(burned.injury_load(INJURY_CATEGORY_THERMAL), before_burn, "with no chance it does not burn")
	acid.burn_chance = 100
	acid.affect_blood(burned, 0, 10)
	TEST_ASSERT(burned.injury_load(INJURY_CATEGORY_THERMAL) > before_burn, "when it takes it burns")
	// Biological: a toxin and a fever.
	var/mob/living/carbon/human/feverish = allocate(/mob/living/carbon/human)
	var/datum/reagent/contaminant/biological/endotoxin = holder.get_reagent(REAGENT_ID_CONTAMINANT_BIOLOGICAL)
	TEST_ASSERT_EQUAL(endotoxin.contaminant_role, CONTAMINANT_ROLE_BIOLOGICAL, "endotoxin is biological")
	var/before_temp = feverish.body_temperature()
	var/before_fever_toxin = feverish.injury_load(INJURY_CATEGORY_TOXIC)
	endotoxin.affect_blood(feverish, 0, 10)
	TEST_ASSERT(feverish.body_temperature() > before_temp, "endotoxin raises the patient's temperature")
	TEST_ASSERT(feverish.injury_load(INJURY_CATEGORY_TOXIC) > before_fever_toxin, "and poisons")
	// Inert: nothing at all.
	var/mob/living/carbon/human/calm = allocate(/mob/living/carbon/human)
	var/calm_temp = calm.body_temperature()
	for(var/inert_id in list(REAGENT_ID_CONTAMINANT_INERT_FILLER, REAGENT_ID_CONTAMINANT_OILY_RESIDUE))
		var/datum/reagent/contaminant/inert/filler = holder.get_reagent(inert_id)
		TEST_ASSERT_EQUAL(filler.contaminant_role, CONTAMINANT_ROLE_INERT, "[inert_id] is inert")
		filler.affect_blood(calm, 0, 10)
	TEST_ASSERT_EQUAL(calm.injury_load(INJURY_CATEGORY_TOXIC), 0, "inert contaminants poison nothing")
	TEST_ASSERT_EQUAL(calm.injury_load(INJURY_CATEGORY_THERMAL), 0, "burn nothing")
	TEST_ASSERT_EQUAL(calm.body_temperature(), calm_temp, "and change no temperature")
	TEST_ASSERT_EQUAL(calm.organ_in(O_LIVER).damage, 0, "or any organ")
	// The listing a machine prints says the mixture's grade beside a contaminant.
	var/datum/reagents/mixed = dq_contam_holder()
	mixed.add_reagent(REAGENT_ID_DEXALIN, 10, safety = 1)
	mixed.add_reagent(REAGENT_ID_CONTAMINANT_SALTS, 2, safety = 1)
	TEST_ASSERT(findtext(mixed.get_reagent(REAGENT_ID_CONTAMINANT_SALTS).listing_description(), "Standard"), "a contaminant's listing says the mixture is Standard grade")
	TEST_ASSERT_EQUAL(mixed.get_reagent(REAGENT_ID_DEXALIN).listing_description(), mixed.get_reagent(REAGENT_ID_DEXALIN).description, "a stock reagent's is its description")

/// No contaminant is part of any transformation but neutralisation (an acid or base residue is spent, salts are made): what any other reaction does leaves them where they are.
/datum/unit_test/dq_contaminant_never_reacts
	boot_needs = list()

/datum/unit_test/dq_contaminant_never_reacts/Run()
	var/list/ids = contaminant_ids()
	for(var/datum/xform/X as anything in GLOB.xform_rules)
		if(X.medium != MEDIUM_REAGENTS)
			continue
		if(X.route_id)
			continue // a generated route (neutralise spends the residues; the others make them): the route tests read those
		for(var/id in ids)
			TEST_ASSERT(!(id in X.reagent_takes) && !(id in X.reagent_catalysts) && !(id in X.reagent_blocked) && X.result != id, "[X.rule_type] names the contaminant [id]")
	var/datum/reagents/dq_contam/H = dq_contam_regime_holder()
	for(var/id in ids)
		H.add_reagent(id, 3, safety = 1)
	H.add_reagent(REAGENT_ID_MERCURY, 10, safety = 1)
	H.add_reagent(REAGENT_ID_CHLORINE, 10, safety = 1)
	var/list/fired = xform_settle_reagents(H)
	TEST_ASSERT_EQUAL(length(fired), 1, "the rule between the stock reagents fired once, none between the contaminants")
	TEST_ASSERT(dq_contam_near(H.get_reagent_amount(REAGENT_ID_TIN), 20), "and made its product")
	for(var/id in ids)
		TEST_ASSERT(dq_contam_near(H.get_reagent_amount(id), 3), "[id] is where it was, untouched")
	var/datum/reagents/dq_contam/only = dq_contam_regime_holder()
	for(var/id in ids)
		only.add_reagent(id, 3, safety = 1)
	TEST_ASSERT_EQUAL(length(xform_settle_reagents(only)), 0, "contaminants together do nothing")
	TEST_ASSERT_EQUAL(only.grade(), GRADE_CRUDE, "a mixture of nothing but contaminant is Crude")
	// A real beaker, with the real recipes: a recipe's product does not take a contaminant with it.
	// (An acid and a base cancel in a real beaker: that is the neutralise process, tested with the routes.)
	var/datum/reagents/real = dq_contam_holder()
	var/list/untouched = list()
	for(var/id in ids)
		var/datum/chem_structure/S = chem_structure_of(id)
		if(S?.is_acid() || S?.is_base())
			continue
		untouched += id
		real.add_reagent(id, 2, safety = 1)
	real.add_reagent(REAGENT_ID_HYDROGEN, 5, safety = 1)
	real.add_reagent(REAGENT_ID_OXYGEN, 5, safety = 1)
	real.handle_reactions()
	for(var/id in untouched)
		TEST_ASSERT(dq_contam_near(real.get_reagent_amount(id), 2), "[id] is still 2u in a beaker that settled")

#endif
