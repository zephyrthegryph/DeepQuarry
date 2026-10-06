// Unit tests for per-instance list memory in the medical code
// (doc/rewrite/memory_lists_audit.md, "For the medical session"): constant
// tables are shared per type, and usually-empty lists stay null.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Two reagents of the same type share one treatment_tags table (and one
/// factors table), instead of each carrying its own copy.
/datum/unit_test/dq_reagent_tables_shared_per_type

/datum/unit_test/dq_reagent_tables_shared_per_type/Run()
	var/datum/reagent/first = new /datum/reagent/bicaridine()
	var/datum/reagent/second = new /datum/reagent/bicaridine()
	TEST_ASSERT(length(first.treatment_tags), "bicaridine should declare treatment tags")
	TEST_ASSERT(first.treatment_tags == second.treatment_tags, "two bicaridine datums should share one treatment_tags list")
	TEST_ASSERT_EQUAL(first.treatment_tags[TREAT_TISSUE_REPAIR], 1.0, "sharing should keep the declared potency")
	TEST_ASSERT(first.factors == second.factors, "two bicaridine datums should share one factors table")

	var/datum/reagent/other = new /datum/reagent/kelotane()
	TEST_ASSERT(other.treatment_tags != first.treatment_tags, "different reagent types should keep their own tables")
	TEST_ASSERT_EQUAL(other.treatment_tags[TREAT_BURN_CARE], 0.6, "kelotane should keep its own potency")
	qdel(first)
	qdel(second)
	qdel(other)

/// A simple mob allocates no organ lists; a human always has them.
/datum/unit_test/dq_organ_lists_lazy_on_simple_mobs

/datum/unit_test/dq_organ_lists_lazy_on_simple_mobs/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT_NULL(M.organs, "a mouse should have no external organ list")
	TEST_ASSERT_NULL(M.organs_by_name, "a mouse should have no organs_by_name list")
	TEST_ASSERT(!length(INTERNAL_ORGANS(M)), "a mouse should have no internal organs before butchery")
	TEST_ASSERT_NULL(M.organ_in(O_HEART), "a mouse should have no heart before butchery")
	TEST_ASSERT_NULL(M.get_organ(BP_TORSO), "get_organ on a mob without organs should return null, not runtime")

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(length(H.organs), "a human should have external organs")
	TEST_ASSERT_NOTNULL(H.organ_in(O_HEART), "a human should have a heart")
	var/obj/item/organ/external/hand = H.get_organ(BP_L_HAND)
	TEST_ASSERT_NOTNULL(hand, "a human should have a left hand")
	TEST_ASSERT_NULL(hand.children, "a hand has no child limbs, so no children list")
	TEST_ASSERT_NULL(hand.implants, "a fresh hand has no implants list")

/// Butchery organs come from a shared per-type table and are created only
/// when the animal is butchered.
/datum/unit_test/dq_butchery_organs_spawn_from_type_table

/datum/unit_test/dq_butchery_organs_spawn_from_type_table/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	var/list/types = TYPE_TABLE_GET(M, butchery_organ_types)
	TEST_ASSERT(length(types), "an animal should declare butchery organ types")
	M.spawn_butchery_organs()
	TEST_ASSERT_EQUAL(length(INTERNAL_ORGANS(M)), length(types), "butchery should create one organ per declared type")
	M.spawn_butchery_organs()
	TEST_ASSERT_EQUAL(length(INTERNAL_ORGANS(M)), length(types), "butchery organs should only be created once")
	TEST_ASSERT_NOTNULL(M.organ_in(O_HEART), "the butchered heart should be registered by name")

#endif
