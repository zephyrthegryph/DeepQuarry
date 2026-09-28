// O-slots (doc/rewrite/completion_plan.md 3.4): internal organs are keyed
// entries in their limb's SLOT_ID_PART_ORGANS slot. There are no mob-side organ
// lists; organ_in() / INTERNAL_ORGANS() read the ledger.

/// Every organ a species lays out is found by its tag, through the keyed slot
/// of the limb it sits in. Data-driven: walks each species' has_organ table.
/datum/unit_test/dq_organ_slots_species_layouts

/datum/unit_test/dq_organ_slots_species_layouts/Run()
	for(var/species_name in list(SPECIES_HUMAN, SPECIES_TAJARAN, SPECIES_UNATHI, SPECIES_SKRELL, SPECIES_DIONA, SPECIES_TESHARI))
		var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
		H.set_species(species_name)
		for(var/tag in H.species.has_organ)
			var/obj/item/organ/O = H.organ_in(tag)
			TEST_ASSERT_NOTNULL(O, "[species_name]: organ_in([tag]) should find the organ its layout declares")
			var/obj/item/organ/external/limb = O.parent_part()
			TEST_ASSERT_NOTNULL(limb, "[species_name]: [tag] should sit in a limb")
			TEST_ASSERT_EQUAL(limb.slot_lookup(SLOT_ID_PART_ORGANS, tag), O, "[species_name]: the limb's keyed slot should hold [tag]")
			TEST_ASSERT(O in INTERNAL_ORGANS(H), "[species_name]: INTERNAL_ORGANS should list [tag]")
		TEST_ASSERT_EQUAL(length(INTERNAL_ORGANS(H)), length(H.body.organs()), "[species_name]: INTERNAL_ORGANS and body.organs() agree")
		dq_assert_body_tree(H, "[species_name] layout")

/// An organ moved (still attached) into another limb is found there, and
/// the move is a ledger move between keyed slots.
/datum/unit_test/dq_organ_slots_relocation

/datum/unit_test/dq_organ_slots_relocation/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/heart = H.organ_in(O_HEART)
	var/obj/item/organ/external/head = H.get_organ(BP_HEAD)
	TEST_ASSERT_NOTNULL(heart, "a human has a heart")
	TEST_ASSERT(heart.move_into(head, SLOT_ID_PART_ORGANS), "the heart moves into the head's organ slot")
	TEST_ASSERT_EQUAL(heart.parent_part(), head, "the heart now sits in the head")
	TEST_ASSERT_EQUAL(H.organ_in(O_HEART), heart, "organ_in still finds the relocated heart")
	TEST_ASSERT_EQUAL(heart.owner, H, "the relocated heart stays attached")
	dq_assert_body_tree(H, "after relocation")

/// Transplant: removing an organ empties its key; a donor organ inserted
/// through the ledger takes the key.
/datum/unit_test/dq_organ_slots_transplant

/datum/unit_test/dq_organ_slots_transplant/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/donor = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/kidneys = H.organ_in(O_KIDNEYS)
	var/obj/item/organ/external/host = kidneys.parent_part()
	TEST_ASSERT(kidneys.removed(), "removal succeeds")
	TEST_ASSERT_NULL(H.organ_in(O_KIDNEYS), "a removed organ's key is empty")
	TEST_ASSERT(!(kidneys in INTERNAL_ORGANS(H)), "INTERNAL_ORGANS drops the removed organ")
	var/obj/item/organ/internal/graft = donor.organ_in(O_KIDNEYS)
	TEST_ASSERT(graft.removed(), "the donor's kidneys come out")
	TEST_ASSERT(graft.move_into(host, SLOT_ID_PART_ORGANS), "the graft goes into the recipient's limb")
	TEST_ASSERT_EQUAL(H.organ_in(O_KIDNEYS), graft, "the graft holds the key")
	TEST_ASSERT_EQUAL(graft.owner, H, "the graft belongs to the recipient")
	TEST_ASSERT_NULL(donor.organ_in(O_KIDNEYS), "the donor has none")
	dq_assert_body_tree(H, "recipient after transplant")
	dq_assert_body_tree(donor, "donor after transplant")

/// A limb that comes off takes its organs out of organ_in(), even while its
/// subtree is released organs-first.
/datum/unit_test/dq_organ_slots_droplimb

/datum/unit_test/dq_organ_slots_droplimb/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain = H.organ_in(O_BRAIN)
	var/obj/item/organ/external/head = brain.parent_part()
	head.droplimb(TRUE, DROPLIMB_EDGE)
	TEST_ASSERT_NULL(H.organ_in(O_BRAIN), "a dropped head's brain is no longer the body's")
	TEST_ASSERT(!(brain in INTERNAL_ORGANS(H)), "INTERNAL_ORGANS drops organs of a dropped limb")
	if(!QDELETED(brain))
		TEST_ASSERT(brain in head.held_organs(), "the brain stays in the head's organ slot")

/// Destroying a body releases its slots before the organs are deleted: nothing
/// is left for organ_in() to find, and every organ is gone.
/datum/unit_test/dq_organ_slots_destroy

/datum/unit_test/dq_organ_slots_destroy/Run()
	var/mob/living/carbon/human/H = new(null)
	var/list/organs = INTERNAL_ORGANS(H)
	TEST_ASSERT(length(organs), "a fresh human has internal organs")
	qdel(H)
	for(var/obj/item/organ/O as anything in organs)
		TEST_ASSERT(QDELETED(O), "[O] ([O.type]) survived its body's deletion")
		TEST_ASSERT_NULL(O.owner, "[O] kept an owner after its body was deleted")

/// A treeless mob keeps its organs loose in SLOT_ID_BODY; organ_in finds them.
/datum/unit_test/dq_organ_slots_treeless

/datum/unit_test/dq_organ_slots_treeless/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(!M.has_part_tree(), "a mouse has no part tree")
	M.spawn_butchery_organs()
	var/obj/item/organ/heart = M.organ_in(O_HEART)
	TEST_ASSERT_NOTNULL(heart, "the butchered heart is found loose in the interior slot")
	TEST_ASSERT(M.has_internal_organ(heart), "has_internal_organ agrees")
