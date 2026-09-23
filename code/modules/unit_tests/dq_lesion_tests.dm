// Unit tests for internal organ lesions: organ integrity (`damage`) is
// derived from lesion afflictions located on the organ
// (code/modules/medical/conditions/lesions.dm,
// code/modules/body/parts/organ_integrity.dm). Harm arrives through
// injure() aimed at the organ; healing through mend().

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Test helper: make an organ's integrity exactly `amount` by replacing its
/// lesions with a single default lesion of that size.
/proc/dq_test_set_organ_damage(obj/item/organ/internal/O, amount)
	O.clear_lesions()
	if(amount > 0)
		O.damage_to_at_least(amount)

/// Test helper: exact organ harm through the injury pipeline (no
/// resistances, no pain flash). `lesion_type` picks the lesion kind.
/proc/dq_test_injure_organ(mob/living/carbon/human/H, obj/item/organ/internal/O, amount, lesion_type = null)
	return H.injure(INJURY_BLUNT, amount, O, affliction = lesion_type, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)

/// Test helper: one tick of the shared affliction pipeline for every
/// affliction located on `O` (a fresh treatment snapshot, like a Life tick).
/proc/dq_test_tick_organ(obj/item/organ/internal/O)
	var/datum/body/B = O.owner?.body
	if(!B)
		return
	B.invalidate(BODY_DIRTY_TREATMENT)
	for(var/datum/affliction/A as anything in B.afflictions_at(O))
		if(A.body == B)
			A.tick()

/// Organ damage creates a located lesion and the organ's damage is its size.
/datum/unit_test/dq_lesion_created_from_organ_damage

/datum/unit_test/dq_lesion_created_from_organ_damage/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.internal_organs_by_name[O_LIVER]
	TEST_ASSERT_NOTNULL(liver, "no liver")
	TEST_ASSERT_EQUAL(liver.damage, 0, "a fresh liver should be undamaged")

	dq_test_injure_organ(H, liver, 20)
	var/datum/affliction/lesion/contusion/L = liver.find_lesion(/datum/affliction/lesion/contusion)
	TEST_ASSERT_NOTNULL(L, "blunt organ injury should create a contusion lesion")
	TEST_ASSERT(L in H.body.afflictions, "the lesion should live in the patient's body")
	TEST_ASSERT_EQUAL(L.location, liver, "the lesion should be located on the damaged organ")
	TEST_ASSERT_EQUAL(L.damage, 20, "the lesion should carry the damage dealt")
	TEST_ASSERT_EQUAL(liver.damage, 20, "organ damage should be derived from its lesion")
	TEST_ASSERT_NULL(L.injury_category, "lesions must not count toward injury load")

	dq_test_injure_organ(H, liver, 5)
	TEST_ASSERT_EQUAL(length(liver.get_lesions()), 1, "repeat damage of the same kind should merge into one lesion")
	TEST_ASSERT_EQUAL(L.damage, 25, "the merged lesion should grow")

	dq_test_injure_organ(H, liver, 10, /datum/affliction/lesion/toxic_injury)
	TEST_ASSERT_EQUAL(length(liver.get_lesions()), 2, "a different kind of damage should add a second lesion")
	TEST_ASSERT_NOTNULL(liver.find_lesion(/datum/affliction/lesion/toxic_injury), "the typed damage should create a toxic injury")

/// injure() aimed at an internal organ maps the injury kind to a lesion kind
/// through one static table; perforation only holes hollow organs.
/datum/unit_test/dq_lesion_injury_kind_table

/datum/unit_test/dq_lesion_injury_kind_table/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.internal_organs_by_name[O_LIVER]
	var/obj/item/organ/internal/stomach = H.internal_organs_by_name[O_STOMACH]
	TEST_ASSERT_NOTNULL(liver, "no liver")
	TEST_ASSERT_NOTNULL(stomach, "no stomach")

	TEST_ASSERT(H.injure(INJURY_CUT, 5, liver, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT) > 0, "a cut aimed at the liver should apply")
	TEST_ASSERT_NOTNULL(liver.find_lesion(/datum/affliction/lesion/laceration), "a cut should lacerate the organ")
	H.injure(INJURY_TOXIN, 5, liver, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	TEST_ASSERT_NOTNULL(liver.find_lesion(/datum/affliction/lesion/toxic_injury), "toxin aimed at an organ should be a toxic injury")
	H.injure(INJURY_PIERCE, 5, stomach, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	TEST_ASSERT_NOTNULL(stomach.find_lesion(/datum/affliction/lesion/perforation), "a piercing hit should perforate a hollow organ")
	var/obj/item/organ/internal/kidneys = H.internal_organs_by_name[O_KIDNEYS]
	H.injure(INJURY_PIERCE, 5, kidneys, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	TEST_ASSERT_NULL(kidneys.find_lesion(/datum/affliction/lesion/perforation), "a solid organ can't be perforated")
	TEST_ASSERT_NOTNULL(kidneys.find_lesion(/datum/affliction/lesion/laceration), "a piercing hit should tear a solid organ")
	TEST_ASSERT_EQUAL(H.injure(INJURY_PAIN, 5, liver), 0, "pain can't injure an organ")

	// An organ the body no longer has is not a target: the hit must not
	// spill onto the limbs.
	liver.removed()
	var/before = H.injury_load(INJURY_CATEGORY_PHYSICAL)
	TEST_ASSERT_EQUAL(H.injure(INJURY_BLUNT, 10, liver), 0, "injury aimed at a removed organ should do nothing")
	TEST_ASSERT_EQUAL(H.injury_load(INJURY_CATEGORY_PHYSICAL), before, "injury aimed at a removed organ must not spread to the limbs")

/// Integrity is the sum of lesions, capped at max_damage, and follows healing.
/datum/unit_test/dq_lesion_derived_integrity

/datum/unit_test/dq_lesion_derived_integrity/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/heart = H.internal_organs_by_name[O_HEART]
	TEST_ASSERT_NOTNULL(heart, "no heart")

	dq_test_injure_organ(H, heart, 10, /datum/affliction/lesion/contusion)
	dq_test_injure_organ(H, heart, 15, /datum/affliction/lesion/laceration)
	TEST_ASSERT_EQUAL(heart.damage, 25, "organ damage should be the sum of its lesions")
	TEST_ASSERT(heart.is_bruised(), "is_bruised() should read the derived damage")

	H.mend(TREAT_RESTORATION, 10, heart)
	TEST_ASSERT_EQUAL(heart.damage, 15, "restoring 10 points should shrink the organ's lesions by 10 in total")

	dq_test_injure_organ(H, heart, heart.max_damage * 3)
	TEST_ASSERT_EQUAL(heart.damage, heart.max_damage, "derived damage should cap at max_damage")

	H.fully_heal()
	TEST_ASSERT_EQUAL(heart.damage, 0, "a full heal should clear every lesion")
	TEST_ASSERT(!length(heart.get_lesions()), "no lesions should survive a full heal")

/// Drugs only stabilise a laceration; surgical repair closes it.
/datum/unit_test/dq_lesion_surgical_repair_heals_laceration

/datum/unit_test/dq_lesion_surgical_repair_heals_laceration/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.internal_organs_by_name[O_LIVER]
	TEST_ASSERT_NOTNULL(liver, "no liver")
	dq_test_injure_organ(H, liver, 30, /datum/affliction/lesion/laceration)
	var/datum/affliction/lesion/laceration/L = liver.find_lesion(/datum/affliction/lesion/laceration)
	TEST_ASSERT_NOTNULL(L, "a laceration lesion should exist")

	// The liver's own repair drug mechanism, applied generously, instant and
	// continuous.
	H.mend(TREAT_HEPATORENAL, 1000, liver)
	H.mend(TREAT_TISSUE_REPAIR, 1000, liver)
	H.bloodstr.add_reagent(REAGENT_ID_HEPANEPHRODAXON, 40)
	for(var/i in 1 to 20)
		dq_test_tick_organ(liver)
	TEST_ASSERT(!QDELETED(L), "drugs should not close a laceration")
	TEST_ASSERT(liver.damage >= 30 * L.drug_floor, "drugs should only stabilise a laceration (damage [liver.damage])")
	TEST_ASSERT(L.is_stabilised(), "a drug acting on the laceration should stabilise it")

	H.surgically_repair_organ(liver)
	TEST_ASSERT(QDELETED(L) || !(L in liver.get_lesions()), "surgical repair should close the laceration")
	TEST_ASSERT_EQUAL(liver.damage, 0, "the liver should be whole after surgical repair")

/// Bug 3: surgical repair spends ONE budget: resection only gets what the
/// structural repair left over.
/datum/unit_test/dq_lesion_surgical_repair_single_budget

/datum/unit_test/dq_lesion_surgical_repair_single_budget/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.internal_organs_by_name[O_LIVER]
	TEST_ASSERT_NOTNULL(liver, "no liver")
	dq_test_injure_organ(H, liver, 20, /datum/affliction/lesion/laceration)
	dq_test_injure_organ(H, liver, 20, /datum/affliction/lesion/necrosis)
	var/repaired = H.surgically_repair_organ(liver, 25)
	TEST_ASSERT_EQUAL(repaired, 25, "a 25-point operation should repair exactly 25 points")
	TEST_ASSERT_EQUAL(liver.damage, 15, "the operation should not heal twice its budget (damage [liver.damage])")

/// Bug 2: a respiratory mechanism (the oxygen pump) only stabilises a lung
/// perforation; it never closes a surgery-only lesion.
/datum/unit_test/dq_lesion_respiratory_mend_respects_floor

/datum/unit_test/dq_lesion_respiratory_mend_respects_floor/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/lungs = H.internal_organs_by_name[O_LUNGS]
	TEST_ASSERT_NOTNULL(lungs, "no lungs")
	dq_test_injure_organ(H, lungs, 20, /datum/affliction/lesion/perforation)
	var/datum/affliction/lesion/perforation/P = lungs.find_lesion(/datum/affliction/lesion/perforation)
	TEST_ASSERT_NOTNULL(P, "no lung perforation")
	for(var/i in 1 to 50)
		H.mend(TREAT_RESPIRATORY, 1, lungs)
	TEST_ASSERT(!QDELETED(P), "respiratory treatment must not close a perforation")
	TEST_ASSERT(lungs.damage >= 20 * P.drug_floor, "respiratory treatment must stop at the drug floor (damage [lungs.damage])")

/// Necrosis needs resection.
/datum/unit_test/dq_lesion_necrosis_needs_resection

/datum/unit_test/dq_lesion_necrosis_needs_resection/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/kidneys = H.internal_organs_by_name[O_KIDNEYS]
	TEST_ASSERT_NOTNULL(kidneys, "no kidneys")
	dq_test_injure_organ(H, kidneys, 20, /datum/affliction/lesion/necrosis)
	H.mend(TREAT_HEPATORENAL, 1000, kidneys)
	TEST_ASSERT_EQUAL(kidneys.damage, 20, "the organ repair drug should not touch necrosis")
	H.mend(TREAT_RESECTION, 1000, kidneys)
	TEST_ASSERT_EQUAL(kidneys.damage, 0, "resection should remove necrotic tissue")

/// A transplanted organ carries its lesions into the new body.
/datum/unit_test/dq_lesion_transplant_carries_lesions

/datum/unit_test/dq_lesion_transplant_carries_lesions/Run()
	var/mob/living/carbon/human/donor = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/recipient = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/kidneys = donor.internal_organs_by_name[O_KIDNEYS]
	TEST_ASSERT_NOTNULL(kidneys, "donor has no kidneys")
	dq_test_injure_organ(donor, kidneys, 20, /datum/affliction/lesion/toxic_injury)
	var/datum/affliction/lesion/L = kidneys.find_lesion(/datum/affliction/lesion/toxic_injury)
	TEST_ASSERT_NOTNULL(L, "no toxic injury on the donor kidneys")

	kidneys.removed()
	TEST_ASSERT(!(L in donor.body.afflictions), "the lesion should leave the donor with the organ")
	TEST_ASSERT(!length(donor.body.afflictions_by_location?[kidneys]), "the donor's location index should forget the organ")
	TEST_ASSERT(L in kidneys.detached_afflictions, "the lesion should ride the detached organ")
	TEST_ASSERT_EQUAL(kidneys.damage, 20, "a detached organ keeps its derived damage")

	var/obj/item/organ/internal/old_kidneys = recipient.internal_organs_by_name[O_KIDNEYS]
	if(old_kidneys)
		old_kidneys.removed()
		qdel(old_kidneys)
	var/obj/item/organ/external/host_limb = recipient.get_organ(kidneys.parent_organ)
	TEST_ASSERT_NOTNULL(host_limb, "recipient has no limb to hold the kidneys")
	kidneys.replaced(recipient, host_limb)
	TEST_ASSERT(L in recipient.body.afflictions, "the lesion should join the recipient's body")
	TEST_ASSERT(L in recipient.body.afflictions_by_location?[kidneys], "the recipient's location index should hold the lesion")
	TEST_ASSERT_EQUAL(L.location, kidneys, "the lesion should stay on the transplanted organ")
	TEST_ASSERT_EQUAL(kidneys.damage, 20, "the transplanted organ keeps its damage")

/// Synthetic organs take component faults, never organic lesions.
/datum/unit_test/dq_lesion_synthetic_organ_component_fault

/datum/unit_test/dq_lesion_synthetic_organ_component_fault/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/heart = H.internal_organs_by_name[O_HEART]
	TEST_ASSERT_NOTNULL(heart, "no heart")
	heart.robotize()
	dq_test_injure_organ(H, heart, 10, /datum/affliction/lesion/laceration)
	TEST_ASSERT_NOTNULL(heart.find_lesion(/datum/affliction/lesion/synthetic/component_fault), "a prosthetic organ should take a component fault")
	TEST_ASSERT_NULL(heart.find_lesion(/datum/affliction/lesion/laceration), "a prosthetic organ must not get organic lesions")
	TEST_ASSERT_EQUAL(heart.damage, 8, "prosthetic organs take 80% damage")
	H.mend(TREAT_CARDIAC, 1000, heart)
	TEST_ASSERT_EQUAL(heart.damage, 8, "drug mechanisms must not repair a prosthetic organ")
	H.surgically_repair_organ(heart)
	TEST_ASSERT_EQUAL(heart.damage, 0, "a system restore should repair the component fault")

/// TREAT_RESTORATION repairs every biology, surgical lesions included.
/datum/unit_test/dq_lesion_restoration_repairs_everything

/datum/unit_test/dq_lesion_restoration_repairs_everything/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.internal_organs_by_name[O_LIVER]
	var/obj/item/organ/internal/heart = H.internal_organs_by_name[O_HEART]
	heart.robotize()
	dq_test_injure_organ(H, liver, 20, /datum/affliction/lesion/laceration)
	dq_test_injure_organ(H, heart, 20)
	H.mend(TREAT_RESTORATION, 1000, liver)
	H.mend(TREAT_RESTORATION, 1000, heart)
	TEST_ASSERT_EQUAL(liver.damage, 0, "restoration should close even a surgical lesion")
	TEST_ASSERT_EQUAL(heart.damage, 0, "restoration should repair a prosthetic organ")

/// afflict() constructs with the location, so location-dependent afflictions
/// (lesions) configure for the right organ.
/datum/unit_test/dq_affliction_afflict_configures_location

/datum/unit_test/dq_affliction_afflict_configures_location/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/heart = H.internal_organs_by_name[O_HEART]
	var/datum/affliction/lesion/L = H.body.afflict(/datum/affliction/lesion/contusion, heart)
	TEST_ASSERT_NOTNULL(L, "afflict() should create the lesion")
	TEST_ASSERT_EQUAL(L.location, heart, "the lesion should sit on the heart")
	TEST_ASSERT(L.treated_by?[TREAT_CARDIAC], "a heart lesion should be treated by the heart's repair mechanism")
	TEST_ASSERT(findtext(L.name, heart.name), "a heart lesion should be named for the heart ([L.name])")

#endif
