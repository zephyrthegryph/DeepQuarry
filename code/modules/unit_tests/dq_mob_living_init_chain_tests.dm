// /mob/living/Initialize is defined twice (modules/mob/living/living.dm, modules/combat_ai/integration/mob_living.dm).
// DM keeps both: the last-included body runs first and its ..() calls the earlier definition. So the effects land as
// living.dm (after ..(): the HUD slot table), mob_living.dm (after ..(): the AI brain). The body is the owns_one(starts =) of the combat AI block.

/datum/unit_test/dq_mob_living_init_chain

/datum/unit_test/dq_mob_living_init_chain/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	TEST_ASSERT(istype(M.body, M.body_type), "the declared starting body was made: the body plan exists")
	TEST_ASSERT_EQUAL(M.body.owner, M, "and belongs to the mob")
	TEST_ASSERT(living_rules_of(M).has_huds && islist(M.hud_list) && length(M.hud_list) == TOTAL_HUDS, "living.dm's Initialize body ran: the HUD slot table exists")
	TEST_ASSERT(living_rules_of(M).use_modern_ai && istype(M.ai_brain, /datum/ai_brain), "mob_living.dm's Initialize body ran: the AI brain exists")

// Body creation order: the declared starting body (owns_one(starts =) of the combat AI block) is made inside /mob/living/Initialize's chain,
// so a type's own Initialize code that runs before its ..() sees no body and code after ..() sees it. A human is the exception: it runs
// set_species() before ..(), which builds the body there. The probes below record what they saw.
/mob/living/silicon/robot/dq_body_order_probe
	var/body_before_init_chain = "unset"
	var/body_after_init_chain = "unset"

/mob/living/silicon/robot/dq_body_order_probe/setup_radio()
	body_before_init_chain = body // ran before ..() in robot Initialize
	return ..()

/mob/living/silicon/robot/dq_body_order_probe/Initialize(mapload)
	. = ..()
	body_after_init_chain = body

/mob/living/simple_mob/animal/passive/mouse/dq_body_order_probe
	var/body_before_init_chain = "unset"
	var/body_after_init_chain = "unset"

/mob/living/simple_mob/animal/passive/mouse/dq_body_order_probe/Initialize(mapload)
	body_before_init_chain = body
	. = ..()
	body_after_init_chain = body

/mob/living/carbon/human/dq_body_order_probe
	var/body_after_set_species = "unset"
	var/body_after_init_chain = "unset"

/mob/living/carbon/human/dq_body_order_probe/set_species(new_species, keep_organs = FALSE)
	. = ..()
	if(body_after_set_species == "unset")
		body_after_set_species = body // set_species runs before the human's ..()

/mob/living/carbon/human/dq_body_order_probe/Initialize(mapload)
	. = ..()
	body_after_init_chain = body

/datum/unit_test/dq_body_creation_order

/datum/unit_test/dq_body_creation_order/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/silicon/robot/dq_body_order_probe/R = allocate(/mob/living/silicon/robot/dq_body_order_probe, T)
	TEST_ASSERT_NULL(R.body_before_init_chain, "a robot has no body in code that runs before ..()")
	TEST_ASSERT(istype(R.body_after_init_chain, /datum/body), "a robot has its body after ..()")
	var/mob/living/simple_mob/animal/passive/mouse/dq_body_order_probe/M = allocate(/mob/living/simple_mob/animal/passive/mouse/dq_body_order_probe, T)
	TEST_ASSERT_NULL(M.body_before_init_chain, "a mouse has no body in code that runs before ..()")
	TEST_ASSERT(istype(M.body_after_init_chain, /datum/body), "a mouse has its body after ..()")
	var/mob/living/carbon/human/dq_body_order_probe/H = allocate(/mob/living/carbon/human/dq_body_order_probe, T)
	TEST_ASSERT(istype(H.body_after_set_species, /datum/body), "a human already has a body before ..() because set_species builds it")
	TEST_ASSERT(istype(H.body_after_init_chain, /datum/body), "and still has it after ..()")
	TEST_ASSERT_EQUAL(H.body_after_init_chain, H.body_after_set_species, "the same body: the chain does not replace it")

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
