// Behaviour-preservation tests for the hypospray family (phase 2, reagent containers, step 5): hyposprays, autoinjectors, the vial hypospray, the cyborg
// hypospray and drink synthesizer, and blood packs. They use the base and the click helpers of dq_p2_reagent_behaviour.dm.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------------------------------------------------

/// A hypospray of `type` holding `amount` units of water (a stocked one holds its own reagent; 0 empties it first).
/datum/unit_test/dq_p2_reagents/proc/rc_hypo(type = /obj/item/reagent_containers/hypospray, amount = 0)
	var/obj/item/reagent_containers/hypospray/S = allocate(type, run_loc_floor_bottom_left)
	if(amount >= 0)
		S.reagents.clear_reagents()
		if(amount > 0)
			S.reagents.add_reagent(REAGENT_ID_WATER, amount)
	return S

/// The units of the one reagent the cyborg hypospray makes now, and what it is making.
/proc/rc_borg_units(obj/item/reagent_containers/borghypo/B, id)
	return B.reagent_volumes[id]

/// The blood pack's label text as the old code kept it.
/proc/rc_pack_label(obj/item/reagent_containers/blood/B)
	return B.label_text

/// The person labels the blood pack with a pen, answering `text` when asked (a re-run answer today).
/proc/rc_label_pack(mob/actor, obj/item/reagent_containers/blood/B, obj/item/pen/pen, text)
	actor.drop_item()
	actor.put_in_active_hand(pen)
	actor.next_click = 0
	input_submit(new /datum/input_event/click(actor, B, null, null, "left=1"))
	test_answer(actor, text)
	test_time(10 SECONDS)

// ---------------------------------------------------------------------------------------------------------------------
// Hyposprays and autoinjectors
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_reagents/hypos_start_as_declared

/datum/unit_test/dq_p2_reagents/hypos_start_as_declared/run_gate()
	var/obj/item/reagent_containers/hypospray/H = rc_hypo(/obj/item/reagent_containers/hypospray, -1)
	TEST_ASSERT_EQUAL(rc_capacity(H), 30, "a hypospray holds 30")
	TEST_ASSERT_EQUAL(rc_units(H), 0, "and starts empty")
	TEST_ASSERT(rc_open(H), "a hypospray can be poured into")
	var/obj/item/reagent_containers/hypospray/autoinjector/A = rc_hypo(/obj/item/reagent_containers/hypospray/autoinjector, -1)
	TEST_ASSERT_EQUAL(rc_capacity(A), 5, "an autoinjector holds 5")
	TEST_ASSERT_EQUAL(rc_units(A), 5, "and comes loaded")
	TEST_ASSERT(rc_open(A), "and is open")
	var/obj/item/reagent_containers/hypospray/autoinjector/biginjector/B = rc_hypo(/obj/item/reagent_containers/hypospray/autoinjector/biginjector, -1)
	TEST_ASSERT_EQUAL(rc_capacity(B), 15, "a big injector holds 15")
	TEST_ASSERT_EQUAL(rc_units(B), 15, "and comes loaded")
	TEST_ASSERT_EQUAL(rc_amount(B), 15, "and gives it all")
	var/obj/item/reagent_containers/hypospray/autoinjector/used/U = rc_hypo(/obj/item/reagent_containers/hypospray/autoinjector/used, -1)
	TEST_ASSERT(!rc_open(U), "a used autoinjector is shut")
	var/obj/item/reagent_containers/hypospray/science/S = rc_hypo(/obj/item/reagent_containers/hypospray/science, -1)
	TEST_ASSERT(S.prototype, "the science hypospray is the prototype")

/// A click on yourself injects at once: one transfer, into the blood.
/datum/unit_test/dq_p2_reagents/hypospray_injects_yourself

/datum/unit_test/dq_p2_reagents/hypospray_injects_yourself/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/hypospray/S = rc_hypo(/obj/item/reagent_containers/hypospray, 20)
	var/before = rc_blood_units(H)
	rc_click(H, H, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 15, "one transfer left the hypospray, at once")
	TEST_ASSERT(rc_blood_units(H) > before, "and is in the blood")
	TEST_ASSERT(rc_open(S), "the hypospray stays open")

/// An autoinjector is spent by the injection: it is shut afterwards.
/datum/unit_test/dq_p2_reagents/autoinjector_is_spent

/datum/unit_test/dq_p2_reagents/autoinjector_is_spent/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/hypospray/autoinjector/A = rc_hypo(/obj/item/reagent_containers/hypospray/autoinjector, -1)
	var/before = rc_blood_units(H)
	rc_click(H, H, A, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(A), 0, "it gave all of it")
	TEST_ASSERT(rc_blood_units(H) > before, "into the blood")
	TEST_ASSERT(!rc_open(A), "and it is shut now")
	var/text = jointext(A.examine(H), " ")
	TEST_ASSERT(findtext(text, "spent"), "it says it is spent: [text]")
	appearance_flush() // the look is redrawn at the end of the frame
	TEST_ASSERT_EQUAL(A.icon_state, "blue0", "and looks spent")

/// A loaded autoinjector says so and looks loaded.
/datum/unit_test/dq_p2_reagents/autoinjector_loaded_look_and_examine

/datum/unit_test/dq_p2_reagents/autoinjector_loaded_look_and_examine/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/hypospray/autoinjector/A = rc_hypo(/obj/item/reagent_containers/hypospray/autoinjector, -1)
	appearance_flush()
	var/text = jointext(A.examine(H), " ")
	TEST_ASSERT(findtext(text, "loaded"), "it says it is loaded: [text]")
	TEST_ASSERT_EQUAL(A.icon_state, "blue1", "and looks loaded")

/// An empty hypospray injects nothing; a missing limb refuses; a robotic limb does not (the needle is air).
/datum/unit_test/dq_p2_reagents/hypospray_refusals

/datum/unit_test/dq_p2_reagents/hypospray_refusals/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/hypospray/empty = rc_hypo(/obj/item/reagent_containers/hypospray, 0)
	var/before = rc_blood_units(patient)
	rc_click(H, patient, empty)
	TEST_ASSERT_EQUAL(rc_blood_units(patient), before, "an empty hypospray gives nothing")
	var/obj/item/reagent_containers/hypospray/S = rc_hypo(/obj/item/reagent_containers/hypospray, 20)
	H.zone_sel.selecting = BP_L_ARM
	var/obj/item/organ/external/arm = patient.get_organ(BP_L_ARM)
	arm.robotize()
	rc_click(H, patient, S)
	TEST_ASSERT_EQUAL(rc_units(S), 15, "a robotic limb is injected through")
	arm.droplimb(TRUE, DROPLIMB_EDGE)
	rc_click(H, patient, S)
	TEST_ASSERT_EQUAL(rc_units(S), 15, "a missing limb is refused")
	H.zone_sel.selecting = BP_TORSO

/// Armour does not stop it: the nozzle finds a port.
/datum/unit_test/dq_p2_reagents/hypospray_goes_through_armour

/datum/unit_test/dq_p2_reagents/hypospray_goes_through_armour/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	TEST_ASSERT(patient.equip_to_slot_if_possible(allocate(/obj/item/clothing/suit/armor/vest), SLOT_ID_SUIT), "the patient wears a vest")
	var/obj/item/reagent_containers/hypospray/S = rc_hypo(/obj/item/reagent_containers/hypospray, 20)
	rc_click(H, patient, S)
	TEST_ASSERT_EQUAL(rc_units(S), 15, "it goes through the vest")

/// Another person is injected at once unless they are awake, in combat mode and resist (three seconds).
/datum/unit_test/dq_p2_reagents/hypospray_on_another

/datum/unit_test/dq_p2_reagents/hypospray_on_another/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/hypospray/S = rc_hypo(/obj/item/reagent_containers/hypospray, 25)
	rc_click(H, patient, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 20, "a calm patient is injected at once")
	patient.set_combat_mode(TRUE)
	rc_click(H, patient, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 20, "a patient in combat mode resists: nothing at once")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(rc_units(S), 20, "nor after a second")
	rc_settle()
	TEST_ASSERT_EQUAL(rc_units(S), 15, "after three seconds it goes in")
	patient.set_combat_mode(FALSE)
	patient.set_stat(UNCONSCIOUS)
	rc_click(H, patient, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 10, "an unconscious patient is injected at once")
	patient.set_stat(CONSCIOUS)

/// The prototype takes three seconds on somebody else and is at once on yourself.
/datum/unit_test/dq_p2_reagents/prototype_hypospray

/datum/unit_test/dq_p2_reagents/prototype_hypospray/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/hypospray/science/S = rc_hypo(/obj/item/reagent_containers/hypospray/science, 20)
	rc_click(H, H, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 15, "on yourself it is at once")
	rc_click(H, patient, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 15, "on another nothing at once")
	rc_settle()
	TEST_ASSERT_EQUAL(rc_units(S), 10, "after the wait it goes in")

/// A hypospray is poured into like any open container.
/datum/unit_test/dq_p2_reagents/hypospray_is_poured_into

/datum/unit_test/dq_p2_reagents/hypospray_is_poured_into/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/hypospray/S = rc_hypo(/obj/item/reagent_containers/hypospray, 0)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	rc_click(H, S, B)
	TEST_ASSERT_EQUAL(rc_units(S), 10, "a beaker pours its ten into the hypospray")
	var/obj/item/reagent_containers/hypospray/autoinjector/used/U = rc_hypo(/obj/item/reagent_containers/hypospray/autoinjector/used, -1)
	var/before = rc_units(U)
	rc_click(H, U, B)
	TEST_ASSERT_EQUAL(rc_units(U), before, "a spent autoinjector is shut to it")

// ---------------------------------------------------------------------------------------------------------------------
// The vial hypospray
// ---------------------------------------------------------------------------------------------------------------------

/// A vial is loaded in three seconds (once); its contents are the hypospray's; an empty hand takes it out when the hypospray is in the other hand.
/datum/unit_test/dq_p2_reagents/vial_hypospray_loads_and_unloads

/datum/unit_test/dq_p2_reagents/vial_hypospray_loads_and_unloads/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/hypospray/vial/S = allocate(/obj/item/reagent_containers/hypospray/vial)
	TEST_ASSERT_NOTNULL(S.loaded_vial, "it comes with a vial")
	var/obj/item/reagent_containers/glass/beaker/vial/old = S.loaded_vial
	H.drop_item()
	H.put_in_inactive_hand(S)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, S, null, null, "left=1"))
	rc_settle()
	TEST_ASSERT_NULL(S.loaded_vial, "an empty hand on it, held in the other hand, takes the vial out")
	TEST_ASSERT(old.loc == H, "into the hand")
	S.forceMove(run_loc_floor_bottom_left)
	var/obj/item/reagent_containers/glass/beaker/vial/fresh = allocate(/obj/item/reagent_containers/glass/beaker/vial)
	fresh.reagents.add_reagent(REAGENT_ID_WATER, 10)
	rc_click(H, S, fresh, I_HELP, FALSE)
	TEST_ASSERT_NULL(S.loaded_vial, "nothing at once")
	rc_settle()
	TEST_ASSERT(S.loaded_vial == fresh, "after the wait the vial is in")
	TEST_ASSERT_EQUAL(rc_units(S), 10, "and what it held is the hypospray's")
	var/obj/item/reagent_containers/glass/beaker/vial/second = allocate(/obj/item/reagent_containers/glass/beaker/vial)
	rc_click(H, S, second)
	TEST_ASSERT(S.loaded_vial == fresh, "a second vial is refused")

// ---------------------------------------------------------------------------------------------------------------------
// The cyborg hypospray and drink synthesizer
// ---------------------------------------------------------------------------------------------------------------------

/// The cyborg hypospray injects the chosen reagent from its store: one transfer into the person, and the store runs down.
/datum/unit_test/dq_p2_reagents/borghypo_injects_a_person

/datum/unit_test/dq_p2_reagents/borghypo_injects_a_person/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/borghypo/B = allocate(/obj/item/reagent_containers/borghypo)
	var/id = REAGENT_ID_TRICORDRAZINE
	TEST_ASSERT_EQUAL(rc_borg_units(B, id), 30, "the store starts full")
	var/before = rc_blood_units(patient)
	rc_click(H, patient, B, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_borg_units(B, id), 25, "one transfer (5) is made")
	TEST_ASSERT(rc_blood_units(patient) > before, "and is in the patient")
	B.reagent_volumes[id] = 3
	var/after = rc_blood_units(patient)
	rc_click(H, patient, B, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_borg_units(B, id), 3, "a store with less than a transfer gives nothing")
	TEST_ASSERT_EQUAL(rc_blood_units(patient), after, "and the patient has nothing more")

/// The cyborg hypospray does not go through armour unless it says so.
/datum/unit_test/dq_p2_reagents/borghypo_armour

/datum/unit_test/dq_p2_reagents/borghypo_armour/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	TEST_ASSERT(patient.equip_to_slot_if_possible(allocate(/obj/item/clothing/suit/armor/vest), SLOT_ID_SUIT), "the patient wears a vest")
	var/obj/item/reagent_containers/borghypo/B = allocate(/obj/item/reagent_containers/borghypo)
	rc_click(H, patient, B)
	TEST_ASSERT_EQUAL(rc_borg_units(B, REAGENT_ID_TRICORDRAZINE), 30, "the plain one is stopped by the vest")
	var/obj/item/reagent_containers/borghypo/merc/M = allocate(/obj/item/reagent_containers/borghypo/merc)
	var/id = REAGENT_ID_HEALINGNANITES
	rc_click(H, patient, M)
	TEST_ASSERT_EQUAL(rc_borg_units(M, id), 25, "the advanced one goes through")

/// The cyborg hypospray is examined to two tiles, with what it makes and how much is left.
/datum/unit_test/dq_p2_reagents/borghypo_examine

/datum/unit_test/dq_p2_reagents/borghypo_examine/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/borghypo/B = allocate(/obj/item/reagent_containers/borghypo)
	var/text = jointext(B.examine(H), " ")
	TEST_ASSERT(findtext(text, "30 out of 30"), "examine says how much is left: [text]")

/// The drink synthesizer puts its chosen drink into an open container; a closed one gets nothing; a person is not injected.
/datum/unit_test/dq_p2_reagents/drink_synthesizer_dispenses

/datum/unit_test/dq_p2_reagents/drink_synthesizer_dispenses/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/borghypo/service/S = allocate(/obj/item/reagent_containers/borghypo/service)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	var/id = TYPE_TABLE_GET(S, borghypo_reagent_ids)[S.mode]
	var/store = rc_borg_units(S, id)
	rc_click(H, B, S)
	TEST_ASSERT_EQUAL(rc_units(B), 5, "one transfer goes into the beaker")
	TEST_ASSERT_EQUAL(rc_borg_units(S, id), store - 5, "from the store")
	var/obj/item/reagent_containers/glass/beaker/shut = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	cap_key_set(shut, REAGENT_CONTAINER_LID_OPEN, FALSE)
	rc_click(H, shut, S)
	TEST_ASSERT_EQUAL(rc_units(shut), 0, "a closed container gets nothing")
	var/mob/living/carbon/human/patient = rc_actor()
	var/blood = rc_blood_units(patient)
	rc_click(H, patient, S)
	TEST_ASSERT_EQUAL(rc_blood_units(patient), blood, "a person is not injected with drinks")

/// A selected recipe is dispensed step by step.
/datum/unit_test/dq_p2_reagents/drink_synthesizer_dispenses_a_recipe

/datum/unit_test/dq_p2_reagents/drink_synthesizer_dispenses_a_recipe/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/borghypo/service/S = allocate(/obj/item/reagent_containers/borghypo/service)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	S.saved_recipes = list("mix" = list(list("id" = REAGENT_ID_WATER, "amount" = 5), list("id" = REAGENT_ID_SUGAR, "amount" = 10)))
	S.selected_recipe_id = "mix"
	S.is_dispensing_recipe = TRUE
	rc_click(H, B, S)
	TEST_ASSERT_EQUAL(rc_units(B), 15, "both steps are in the beaker")
	TEST_ASSERT(B.reagents.has_reagent(REAGENT_ID_WATER, 5), "the water")
	TEST_ASSERT(B.reagents.has_reagent(REAGENT_ID_SUGAR, 10), "and the sugar")

// ---------------------------------------------------------------------------------------------------------------------
// Blood packs
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_reagents/blood_packs_start_as_declared

/datum/unit_test/dq_p2_reagents/blood_packs_start_as_declared/run_gate()
	var/obj/item/reagent_containers/blood/APlus/pack = allocate(/obj/item/reagent_containers/blood/APlus)
	TEST_ASSERT_EQUAL(rc_capacity(pack), 200, "a pack holds 200")
	TEST_ASSERT_EQUAL(rc_units(pack), 200, "a stock pack is full of blood")
	TEST_ASSERT_EQUAL(rc_pack_label(pack), "A+", "labelled with its type")
	TEST_ASSERT(findtext(pack.name, "A+"), "and named for it: [pack.name]")
	var/obj/item/reagent_containers/blood/empty/empty = allocate(/obj/item/reagent_containers/blood/empty)
	TEST_ASSERT_EQUAL(rc_units(empty), 0, "an empty pack is empty")
	var/obj/item/reagent_containers/blood/prelabeled/APlus/hard = allocate(/obj/item/reagent_containers/blood/prelabeled/APlus)
	TEST_ASSERT_EQUAL(hard.name, "IV Pack (A+)", "a prelabelled pack keeps its printed name")

/// A pen labels a pack: a short label goes in the name, a long one is cut to ten characters with dots, one over fifty is refused, an empty one clears it.
/datum/unit_test/dq_p2_reagents/blood_pack_is_labelled

/datum/unit_test/dq_p2_reagents/blood_pack_is_labelled/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/blood/empty/pack = allocate(/obj/item/reagent_containers/blood/empty)
	var/obj/item/pen/pen = allocate(/obj/item/pen)
	rc_label_pack(H, pack, pen, "Bob")
	TEST_ASSERT_EQUAL(rc_pack_label(pack), "Bob", "the label is kept")
	TEST_ASSERT(findtext(pack.name, "(Bob)"), "and is in the name: [pack.name]")
	rc_label_pack(H, pack, pen, "A very long label indeed")
	TEST_ASSERT(findtext(pack.name, "A very lon..."), "a long label is cut in the name: [pack.name]")
	TEST_ASSERT_EQUAL(rc_pack_label(pack), "A very long label indeed", "but kept whole")
	rc_label_pack(H, pack, pen, "x123456789012345678901234567890123456789012345678901234567890")
	TEST_ASSERT_EQUAL(rc_pack_label(pack), "A very long label indeed", "a label over fifty characters is refused")

/// In a hostile stance, using a pack in hand drinks a tenth of it (a feeding for the one who needs blood); anything but blood is not drunk.
/datum/unit_test/dq_p2_reagents/blood_pack_is_drunk

/datum/unit_test/dq_p2_reagents/blood_pack_is_drunk/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/blood/APlus/pack = allocate(/obj/item/reagent_containers/blood/APlus)
	var/nutrition = H.nutrition
	H.drop_item()
	H.put_in_active_hand(pack)
	H.set_use_stance(I_HURT)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, pack, null, null, "left=1"))
	rc_settle()
	H.set_use_stance(I_HELP)
	TEST_ASSERT_EQUAL(rc_units(pack), 180, "a tenth is drunk")
	TEST_ASSERT(H.nutrition > nutrition, "and feeds")
	rc_use(H, pack)
	TEST_ASSERT_EQUAL(rc_units(pack), 180, "in a friendly stance nothing is drunk")
	var/obj/item/reagent_containers/blood/empty/water = allocate(/obj/item/reagent_containers/blood/empty)
	water.reagents.add_reagent(REAGENT_ID_WATER, 50)
	H.drop_item()
	H.put_in_active_hand(water)
	H.set_use_stance(I_HURT)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, water, null, null, "left=1"))
	rc_settle()
	H.set_use_stance(I_HELP)
	TEST_ASSERT_EQUAL(rc_units(water), 50, "water is not drunk")

/// A syringe draws from a pack (a pack is no open container, but it is one of what a syringe draws from).
/datum/unit_test/dq_p2_reagents/syringe_draws_from_a_blood_pack

/datum/unit_test/dq_p2_reagents/syringe_draws_from_a_blood_pack/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/blood/APlus/pack = allocate(/obj/item/reagent_containers/blood/APlus)
	var/obj/item/reagent_containers/syringe/S = rc_syringe(/obj/item/reagent_containers/syringe, 0, "draw")
	rc_click(H, pack, S)
	TEST_ASSERT_EQUAL(rc_units(S), 5, "the syringe drew one transfer")
	TEST_ASSERT_EQUAL(rc_units(pack), 195, "from the pack")
