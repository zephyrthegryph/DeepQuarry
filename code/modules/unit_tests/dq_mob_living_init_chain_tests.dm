// /mob/living/Initialize is defined twice (modules/mob/living/living.dm, modules/combat_ai/integration/mob_living.dm).
// DM keeps both: the last-included body runs first and its ..() calls the earlier definition. So the effects land as
// living.dm (after ..(): the HUD slot table), mob_living.dm (after ..(): the AI brain). The body is the owns_one(starts =) of the combat AI block.

/datum/unit_test/dq_mob_living_init_chain

/datum/unit_test/dq_mob_living_init_chain/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	TEST_ASSERT(istype(M.body, M.body_type), "the declared starting body was made: the body plan exists")
	TEST_ASSERT_EQUAL(M.body.owner, M, "and belongs to the mob")
	TEST_ASSERT(M.has_huds && islist(M.hud_list) && length(M.hud_list) == TOTAL_HUDS, "living.dm's Initialize body ran: the HUD slot table exists")
	TEST_ASSERT(M.use_modern_ai && istype(M.ai_brain, /datum/ai_brain), "mob_living.dm's Initialize body ran: the AI brain exists")

// The setup(PROC_REF(x), mapload = TRUE) forms that replaced the gripper's, the NIF's and the AR soul's Initialize() tails.
/datum/unit_test/dq_mob_setup_tails

/datum/unit_test/dq_mob_setup_tails/Run()
	var/turf/T = dq_containment_floor()

	var/obj/item/gripper/loose = allocate(/obj/item/gripper, T)
	TEST_ASSERT(QDELETED(loose), "a gripper in neither a module nor a robot is discarded")

	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	var/obj/item/gripper/held = allocate(/obj/item/gripper, R)
	TEST_ASSERT(!QDELETED(held), "a gripper inside a robot stays")
	TEST_ASSERT_EQUAL(held.our_robot, R, "and names it")
	TEST_ASSERT_EQUAL(length(held.pockets), held.total_pockets, "with all of its pockets")
	TEST_ASSERT_EQUAL(held.current_pocket, peek(held.pockets), "the last one selected, as before")

	var/obj/item/nif/N = allocate(/obj/item/nif, T, 20, list("examine_msg" = "A glint."))
	TEST_ASSERT_EQUAL(N.examine_msg, "A glint.", "a NIF made with saved data takes its examine message")
	TEST_ASSERT_EQUAL(N.durability, 20, "and its wear")
	var/obj/item/nif/blank = allocate(/obj/item/nif, T)
	TEST_ASSERT_EQUAL(blank.examine_msg, "There's a certain spark to their eyes.", "a NIF made without data has the default message")

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/brain/caught_soul/brainless = allocate(/mob/living/carbon/brain/caught_soul, T)
	var/mob/observer/eye/ar_soul/soul = new /mob/observer/eye/ar_soul(brainless, H)
	TEST_ASSERT(QDELETED(soul), "an AR soul whose brain mob has no client is discarded")
