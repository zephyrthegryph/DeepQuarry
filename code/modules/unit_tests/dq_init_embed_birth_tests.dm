// Frozen birth embedding uses actual derived constructor size.
/obj/item/dq_embed_birth
	w_class = 2
CAPABILITIES(/obj/item/dq_embed_birth)
	configure(item_combat(force = 60, sharp = TRUE))
/obj/item/dq_embed_birth/blunt
CAPABILITIES(/obj/item/dq_embed_birth/blunt)
	configure(item_combat(force = 60, sharp = FALSE))
/obj/item/dq_embed_birth/disabled
	embed_chance = 0
/obj/item/dq_embed_birth/fixed
	embed_chance = 17
/obj/item/dq_embed_birth/mapped/Initialize(mapload, mapped_chance)
	embed_chance = mapped_chance
	return ..()
/obj/item/computer_hardware/dq_embed_birth
	w_class = 4
	hardware_size = 1
CAPABILITIES(/obj/item/computer_hardware/dq_embed_birth)
	configure(item_combat(force = 60, sharp = TRUE))

/datum/unit_test/dq_init_embed_birth/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/sharp = allocate(/obj/item/dq_embed_birth, test_floor())
	var/obj/item/blunt = allocate(/obj/item/dq_embed_birth/blunt, test_floor())
	var/obj/item/disabled = allocate(/obj/item/dq_embed_birth/disabled, test_floor())
	var/obj/item/fixed = allocate(/obj/item/dq_embed_birth/fixed, test_floor())
	var/obj/item/mapped = allocate(/obj/item/dq_embed_birth/mapped, test_floor(), 23)
	var/obj/item/computer_hardware/hardware = allocate(/obj/item/computer_hardware/dq_embed_birth, test_floor())
	TEST_ASSERT_EQUAL(sharp.embed_chance, 30, "sharp birth calculation uses actual combat force and class")
	TEST_ASSERT_EQUAL(blunt.embed_chance, 10, "blunt birth calculation preserves its factor of three")
	TEST_ASSERT_EQUAL(disabled.embed_chance, 0, "explicit zero disables embedding")
	TEST_ASSERT_EQUAL(fixed.embed_chance, 17, "a compiled nonnegative value survives")
	TEST_ASSERT_EQUAL(mapped.embed_chance, 23, "a constructor-supplied nonnegative value survives")
	TEST_ASSERT_EQUAL(hardware.w_class, 1, "the actual hardware birth-size derive ran")
	TEST_ASSERT_EQUAL(hardware.embed_chance, 60, "embedding observes the derived class rather than its compiled class four")
	sharp.set_w_class(1)
	TEST_ASSERT_EQUAL(sharp.embed_chance, 30, "the birth value is frozen across later size edits")

/obj/item/organ/internal/heart/dq_embed_birth
	w_class = 2
CAPABILITIES(/obj/item/organ/internal/heart/dq_embed_birth)
	configure(item_combat(force = 60, sharp = TRUE))

/datum/unit_test/dq_init_embed_organ_birth/Run()
	dq_init_objects_fixture_scope()
	var/mob/living/simple_mob/born_in = allocate(/mob/living/simple_mob, test_floor())
	born_in.set_mob_size(MOB_LARGE)
	var/size_delta = mob_size_difference(born_in.mob_size, MOB_MEDIUM)
	TEST_ASSERT(size_delta > 0, "the real living parent supplies a larger birth-size category")
	var/obj/item/organ/internal/heart/dq_embed_birth/heart = allocate(/obj/item/organ/internal/heart/dq_embed_birth, born_in)
	TEST_ASSERT(!QDELETED(heart), "the actual heart survives its real living-holder constructor")
	TEST_ASSERT_EQUAL(heart.owner, born_in, "the normal organ attachment adopts its real living parent")
	TEST_ASSERT_EQUAL(heart.w_class, 2 + size_delta, "birth_size derives from the actual parent before embedding")
	TEST_ASSERT_EQUAL(heart.embed_chance, max(5, round(60 / (2 + size_delta))), "the frozen embed value uses the derived organ size")
	TEST_ASSERT(heart.embed_chance != 30, "the fixture distinguishes a prematurely computed compiled-size result")
	heart.set_w_class(1)
	TEST_ASSERT_EQUAL(heart.embed_chance, max(5, round(60 / (2 + size_delta))), "later size edits do not recompute the organ birth value")
