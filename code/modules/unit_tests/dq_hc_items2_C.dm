// Behaviour-preservation tests for items group C (implants, capture crystal, ghost hunting, fantasy items, leash, POI items, UAV, TV camera, tape recorder,
// personal shield, translocator, megaphone, motion tracker, chameleon projector, spy bug, beacons and the small devices). They pin what a player observes
// through clicks, questions and the kernel clock, so the same file passes before and after the group moves to the final forms. The helpers (hci_click,
// hci_answer, person, tile, settle) are in dq_hc_items_behaviour.dm.

// ---------------------------------------------------------------------------------------------------------------------
// Implants (batch 1)
// ---------------------------------------------------------------------------------------------------------------------

/// Adapter: takes the implant out of an implanter the way its verb does (the verb is a menu entry: only its handler is reachable here).
/proc/hcic_remove_implant(mob/user, obj/item/implanter/I)
	test_op_handler(I, "remove_implant_effect", user)

/// Adapter: one step of the generator's periodic work.
/proc/hcic_generator_step(obj/item/implant/reagent_generator/G)
	G.reagent_step(null)

/datum/unit_test/dq_hc_items/c_implanter_in_hand_toggles_and_compliance_asks_laws

/datum/unit_test/dq_hc_items/c_implanter_in_hand_toggles_and_compliance_asks_laws/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/implanter/I = allocate(/obj/item/implanter, tile(2, 2))
	TEST_ASSERT(I.active, "starts active")
	hci_click(H, I, I)
	settle()
	TEST_ASSERT(!I.active, "in-hand use deactivates it")
	hci_click(H, I, I)
	settle()
	TEST_ASSERT(I.active, "and activates it again")
	var/obj/item/implanter/compliance/C = allocate(/obj/item/implanter/compliance, tile(3, 3))
	var/obj/item/implant/compliance/imp = C.imp
	TEST_ASSERT(istype(imp), "the compliance implanter is loaded")
	hci_click(H, C, C)
	settle()
	hci_answer(H, "Obey the doorknob")
	settle()
	TEST_ASSERT_EQUAL(imp.laws, "Obey the doorknob", "the laws typed are set on the implant")
	TEST_ASSERT(C.active, "using the compliance implanter does not toggle it")

/datum/unit_test/dq_hc_items/c_implant_is_loaded_into_an_implanter_and_taken_out

/datum/unit_test/dq_hc_items/c_implant_is_loaded_into_an_implanter_and_taken_out/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/implanter/I = allocate(/obj/item/implanter, T)
	var/obj/item/implant/tracking/imp = allocate(/obj/item/implant/tracking, T)
	hci_click(H, imp, I)
	settle()
	TEST_ASSERT_EQUAL(I.imp, imp, "clicking an implant with an implanter loads it")
	TEST_ASSERT_EQUAL(I.icon_state, "implanter1_1", "the implanter shows it is loaded")
	H.drop_item()
	hcic_remove_implant(H, I)
	settle()
	TEST_ASSERT_NULL(I.imp, "the implant comes out")
	TEST_ASSERT_EQUAL(I.icon_state, "implanter0_1", "and the implanter shows empty")

/datum/unit_test/dq_hc_items/c_implant_case_label_and_swap

/datum/unit_test/dq_hc_items/c_implant_case_label_and_swap/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/implantcase/tracking/C = allocate(/obj/item/implantcase/tracking, T)
	var/obj/item/pen/P = allocate(/obj/item/pen, T)
	hci_click(H, C, P)
	settle()
	hci_answer(H, "Bob")
	settle()
	TEST_ASSERT_EQUAL(C.name, "Glass Case - 'Bob'", "the label is set")
	var/obj/item/implanter/I = allocate(/obj/item/implanter, T)
	var/obj/item/implant/tracking/imp = C.imp
	TEST_ASSERT(istype(imp), "the case holds an implant")
	hci_click(H, C, I)
	settle()
	TEST_ASSERT_EQUAL(I.imp, imp, "an empty implanter takes the case's implant")
	TEST_ASSERT_NULL(C.imp, "the case is empty")
	hci_click(H, C, I)
	settle()
	TEST_ASSERT_EQUAL(C.imp, imp, "a loaded implanter puts it back into an empty case")
	TEST_ASSERT_NULL(I.imp, "the implanter is empty again")

/datum/unit_test/dq_hc_items/c_implant_questions_configure_the_implant

/datum/unit_test/dq_hc_items/c_implant_questions_configure_the_implant/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/implant/explosive/E = allocate(/obj/item/implant/explosive, T)
	E.post_implant(H, H)
	settle()
	hci_answer(H, "Destroy Body")
	settle()
	hci_answer(H, "boom now")
	settle()
	TEST_ASSERT_EQUAL(E.elevel, "Destroy Body", "the yield picked is kept")
	TEST_ASSERT_EQUAL(E.phrase, "boom now", "the phrase typed is kept")
	var/obj/item/implant/compressed/C = allocate(/obj/item/implant/compressed, T)
	C.post_implant(H, H)
	settle()
	hci_answer(H, "wink")
	settle()
	TEST_ASSERT_EQUAL(C.activation_emote, "wink", "the compressed implant takes the emote picked")
	var/obj/item/implant/uplink/U = allocate(/obj/item/implant/uplink, T)
	U.post_implant(H, H)
	settle()
	hci_answer(H, "nod")
	settle()
	TEST_ASSERT_EQUAL(U.activation_emote, "nod", "the uplink implant takes the emote picked")
	var/obj/item/implant/organ/limbaugment/A = allocate(/obj/item/implant/organ/limbaugment, T)
	A.post_implant(H, H)
	settle()
	hci_answer(H, O_AUG_R_FOREARM)
	settle()
	TEST_ASSERT(H.organ_in(O_AUG_R_FOREARM) || QDELETED(A) || A.malfunction, "the augment location picked is where it goes")

/datum/unit_test/dq_hc_items/c_implant_emp_makes_malfunction_then_recovers

/datum/unit_test/dq_hc_items/c_implant_emp_makes_malfunction_then_recovers/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/implant/tracking/TR = allocate(/obj/item/implant/tracking, T)
	TR.emp_act(4)
	TEST_ASSERT(TR.malfunction, "an EMP makes a tracker malfunction")
	settle()
	test_time(70 SECONDS)
	TEST_ASSERT(!TR.malfunction, "and it recovers")
	var/obj/item/implant/chem/CH = allocate(/obj/item/implant/chem, T)
	TEST_ASSERT(CH.handle_implant(H), "the chem implant is embedded")
	CH.emp_act(4)
	TEST_ASSERT(CH.malfunction, "an EMP makes a chem implant malfunction")
	test_time(5 SECONDS)
	TEST_ASSERT(!CH.malfunction, "and it recovers after two seconds")
	var/obj/item/implant/death_alarm/DA = allocate(/obj/item/implant/death_alarm, T)
	TEST_ASSERT(DA.handle_implant(H), "the death alarm is embedded")
	DA.emp_act(4)
	TEST_ASSERT(DA.malfunction, "an EMP makes a death alarm malfunction")
	test_time(5 SECONDS)
	TEST_ASSERT(!DA.malfunction, "and it recovers")
	var/obj/item/implant/integrated_circuit/IC = allocate(/obj/item/implant/integrated_circuit, T)
	TEST_ASSERT(IC.IC, "the circuit implant holds an assembly")
	IC.emp_act(4)

/datum/unit_test/dq_hc_items/c_reagent_implant_generates_while_hosted

/datum/unit_test/dq_hc_items/c_reagent_implant_generates_while_hosted/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/implant/reagent_generator/egg/G = allocate(/obj/item/implant/reagent_generator/egg, tile(2, 2))
	TEST_ASSERT(G.handle_implant(H), "embedded")
	G.post_implant(H)
	H.set_nutrition(400)
	hcic_generator_step(G)
	TEST_ASSERT_EQUAL(G.reagents.total_volume, 2, "a step makes two units of egg while hosted")
	TEST_ASSERT_EQUAL(H.nutrition, 399.5, "and costs half a unit of nutrition")

/datum/unit_test/dq_hc_items/c_reagent_implant_every_runs_while_hosted

/datum/unit_test/dq_hc_items/c_reagent_implant_every_runs_while_hosted/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/implant/reagent_generator/egg/G = allocate(/obj/item/implant/reagent_generator/egg, tile(2, 2))
	TEST_ASSERT(G.handle_implant(H), "embedded")
	test_time(7 SECONDS)
	TEST_ASSERT_EQUAL(G.reagents.total_volume, 0, "an implant that was never post-implanted makes nothing")
	G.post_implant(H)
	H.set_nutrition(400)
	test_time(7 SECONDS)
	TEST_ASSERT(G.reagents.total_volume > 0, "once implanted the generator makes reagents on its own clock")
