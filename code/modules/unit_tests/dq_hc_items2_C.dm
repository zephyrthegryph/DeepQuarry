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
	H.nutrition = 400
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
	H.nutrition = 400
	test_time(7 SECONDS)
	TEST_ASSERT(G.reagents.total_volume > 0, "once implanted the generator makes reagents on its own clock")

// ---------------------------------------------------------------------------------------------------------------------
// Capture crystal and ghost hunting (batch 2)
// ---------------------------------------------------------------------------------------------------------------------

/// Adapters: the crystal's four menu entries (a menu entry is reachable only through its handler here).
/proc/hcic_crystal_menu(obj/item/capture_crystal/C, mob/user, entry)
	switch(entry)
		if("follow")
			test_op_handler(C, "follow_owner_effect", user)
		if("destroy")
			test_op_handler(C, "destroy_crystal_effect", user)
		if("release")
			test_op_handler(C, "release_ownership_effect", user)
		if("ghost")
			test_op_handler(C, "invite_ghost_effect", user)

/// A crystal with a mouse already bound to it and inside it.
/datum/unit_test/dq_hc_items/proc/bound_crystal(turf/T, mob/owner_mob)
	var/obj/item/capture_crystal/C = allocate(/obj/item/capture_crystal, T)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	C.capture(M, owner_mob)
	M.forceMove(C)
	C.active = TRUE
	return C

/// Adapter: one watch step of a trap.
/proc/hcic_trap_step(obj/item/ghost_trap/T)
	T.ghost_trap_step(null)

/datum/unit_test/dq_hc_items/c_crystal_activates_unleashes_and_recalls

/datum/unit_test/dq_hc_items/c_crystal_activates_unleashes_and_recalls/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/capture_crystal/C = allocate(/obj/item/capture_crystal, tile(2, 2))
	C.spawn_mob_type = /mob/living/simple_mob/animal/passive/mouse
	C.update_icon()
	settle()
	TEST_ASSERT_EQUAL(C.icon_state, "full", "a crystal that will spawn its mob shows full")
	hci_click(H, C, C)
	settle()
	TEST_ASSERT_EQUAL(C.owner, H, "the user owns it")
	TEST_ASSERT(C.active, "it is set up")
	var/mob/living/M = C.bound_mob
	TEST_ASSERT(istype(M), "a mob was bound")
	TEST_ASSERT(!(M in C.contents), "and let out")
	C.update_icon()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(C.icon_state, "empty-busy", "the crystal shows empty, busy while the cooldown runs")
	C.recall(H)
	TEST_ASSERT(M in C.contents, "recalling brings the mob back in")
	C.update_icon()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(C.icon_state, "full-busy", "and shows full while the cooldown runs")
	var/obj/item/capture_crystal/idle = allocate(/obj/item/capture_crystal, tile(3, 3))
	idle.update_icon()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(idle.icon_state, "inactive", "a crystal with nothing bound is inactive")
	qdel(M)

/datum/unit_test/dq_hc_items/c_crystal_claim_question

/datum/unit_test/dq_hc_items/c_crystal_claim_question/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/capture_crystal/C = bound_crystal(tile(3, 3), H)
	rel_clear(C, nameof(/obj/item/capture_crystal::owner))
	TEST_ASSERT_NULL(C.owner, "an ownerless crystal")
	hci_click(H, C, C)
	settle()
	hci_answer(H, TRUE)
	settle()
	TEST_ASSERT_EQUAL(C.owner, H, "agreeing claims it")
	var/obj/item/capture_crystal/C2 = bound_crystal(tile(3, 4), H)
	rel_clear(C2, nameof(/obj/item/capture_crystal::owner))
	hci_click(H, C2, C2)
	settle()
	hci_answer(H, null, TRUE)
	settle()
	TEST_ASSERT_NULL(C2.owner, "walking away from the question leaves it ownerless")

/datum/unit_test/dq_hc_items/c_crystal_menu_entries

/datum/unit_test/dq_hc_items/c_crystal_menu_entries/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/capture_crystal/C = bound_crystal(tile(3, 3), H)
	var/mob/living/simple_mob/animal/passive/mouse/M = C.bound_mob
	H.put_in_active_hand(C)
	TEST_ASSERT(istype(M) && M.ai_brain, "the bound mouse has a brain")
	hcic_crystal_menu(C, H, "follow")
	TEST_ASSERT_EQUAL(M.ai_brain.get_leader(), H, "the first toggle makes the mouse follow the owner")
	hcic_crystal_menu(C, H, "follow")
	TEST_ASSERT_NULL(M.ai_brain.get_leader(), "the second toggle stops it")
	M.forceMove(get_turf(H))
	M.ghostjoin = FALSE
	hcic_crystal_menu(C, H, "ghost")
	settle()
	hci_answer(H, TRUE)
	settle()
	TEST_ASSERT(M.ghostjoin, "offering it to ghosts is confirmed")
	hcic_crystal_menu(C, H, "ghost")
	TEST_ASSERT(!M.ghostjoin, "toggling again withdraws the offer")
	hcic_crystal_menu(C, H, "release")
	TEST_ASSERT_NULL(C.owner, "releasing the ownership clears the owner")
	rel_set(C, nameof(/obj/item/capture_crystal::owner), H)
	hcic_crystal_menu(C, H, "destroy")
	settle()
	TEST_ASSERT(QDELETED(C), "the owner can destroy the crystal")

/datum/unit_test/dq_hc_items/c_crystal_capture_asks_consent_twice

/datum/unit_test/dq_hc_items/c_crystal_capture_asks_consent_twice/run_gate()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/V = person(tile(3, 2))
	var/obj/item/capture_crystal/C = allocate(/obj/item/capture_crystal, tile(2, 2))
	C.capture_player(V, H)
	settle()
	hci_answer(V, TRUE)
	settle()
	TEST_ASSERT_NULL(C.bound_mob, "one yes is not enough")
	hci_answer(V, TRUE)
	settle()
	TEST_ASSERT_EQUAL(C.bound_mob, V, "the second yes binds the volunteer")
	TEST_ASSERT_EQUAL(C.owner, H, "to the one who asked")
	TEST_ASSERT(V.capture_caught, "and marks them caught")
	TEST_ASSERT(V in C.contents, "and they are recalled into the crystal")
	var/mob/living/carbon/human/V2 = person(tile(4, 2))
	var/obj/item/capture_crystal/C2 = allocate(/obj/item/capture_crystal, tile(2, 2))
	C2.capture_player(V2, H)
	settle()
	hci_answer(V2, FALSE)
	settle()
	TEST_ASSERT_NULL(C2.bound_mob, "a no binds nobody")
	TEST_ASSERT(!V2.capture_caught, "and marks nobody")

/datum/unit_test/dq_hc_items/c_crystal_forgets_a_deleted_mob

/datum/unit_test/dq_hc_items/c_crystal_forgets_a_deleted_mob/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/capture_crystal/C = bound_crystal(tile(3, 3), H)
	var/mob/living/M = C.bound_mob
	TEST_ASSERT(C.active, "set up")
	qdel(M)
	settle()
	TEST_ASSERT_NULL(C.bound_mob, "the crystal forgets a mob that is deleted")
	TEST_ASSERT_NULL(C.owner, "and its owner link")
	TEST_ASSERT(!C.active, "and is no longer set up")
	var/obj/item/capture_crystal/C2 = bound_crystal(tile(3, 4), H)
	var/mob/living/M2 = C2.bound_mob
	qdel(H)
	settle()
	TEST_ASSERT_NULL(C2.owner, "a deleted owner is forgotten")
	TEST_ASSERT(!C2.active, "and the crystal is no longer set up")

/// A listener of the trap's capture notice.
/datum/hcic_trap_listener
	var/heard = 0
	var/datum/heard_entity

CAPABILITIES(/datum/hcic_trap_listener)
	ref_one(nameof(heard_entity), /datum)

/datum/hcic_trap_listener/proc/trap_caught(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	heard++
	var/datum/notice/world_ghost_captured/N = A
	rel_set(src, nameof(heard_entity), N.passing_entity)

/// Adapters: the trap's two menu entries.
/proc/hcic_trap_menu(obj/item/ghost_trap/T, mob/user, entry)
	if(entry == "release")
		test_op_handler(T, "release_occupant_effect", user)
	else
		test_op_handler(T, "ghost_trap_hidden_vore_effect", user)

/datum/unit_test/dq_hc_items/c_ghost_trap_deploys_catches_and_releases

/datum/unit_test/dq_hc_items/c_ghost_trap_deploys_catches_and_releases/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/ghost_trap/T = allocate(/obj/item/ghost_trap, tile(2, 2))
	var/obj/item/ghost_trap/start_active/pre = allocate(/obj/item/ghost_trap/start_active, tile(3, 3))
	pre.update_icon()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(pre.icon_state, "on", "a deployed trap shows on")
	hci_click(H, T, T)
	test_time(7 SECONDS)
	TEST_ASSERT(T.deployed, "using the trap in hand deploys it after a delay")
	TEST_ASSERT(T.anchored, "and anchors it")
	T.update_icon()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(T.icon_state, "on", "a deployed trap shows on")
	var/datum/hcic_trap_listener/L = new
	observe(T, /datum/notice/world_ghost_captured, L, then(TYPE_PROC_REF(/datum/hcic_trap_listener, trap_caught)))
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, tile(4, 4))
	T.Crossed(ghost)
	settle()
	TEST_ASSERT_EQUAL(T.captured_entity, ghost, "an incorporeal mob crossing a deployed trap is caught")
	TEST_ASSERT(!T.deployed, "the trap is spent")
	TEST_ASSERT_EQUAL(ghost.loc, T, "the ghost is inside it")
	TEST_ASSERT_EQUAL(L.heard, 1, "the capture is announced")
	TEST_ASSERT_EQUAL(L.heard_entity, ghost, "with the entity")
	T.update_icon()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(T.icon_state, "item_captured", "a trap with a catch shows captured")
	ghost.forceMove(tile(4, 4))
	hcic_trap_step(T)
	TEST_ASSERT_NULL(T.captured_entity, "an entity that gets out is noticed within a few seconds")
	T.update_icon()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(T.icon_state, "item", "and the trap shows empty")
	var/obj/item/ghost_trap/R = allocate(/obj/item/ghost_trap, tile(5, 5))
	var/mob/observer/dead/ghost2 = allocate(/mob/observer/dead, tile(4, 5))
	R.catch_ghost(ghost2)
	TEST_ASSERT_EQUAL(R.captured_entity, ghost2, "caught")
	hcic_trap_menu(R, H, "release")
	TEST_ASSERT_NULL(R.captured_entity, "the release entry lets the catch out")
	TEST_ASSERT(ghost2.loc != R, "outside the trap")

/datum/unit_test/dq_hc_items/c_ghost_trap_hand_picks_it_up_again

/datum/unit_test/dq_hc_items/c_ghost_trap_hand_picks_it_up_again/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/ghost_trap/start_active/T = allocate(/obj/item/ghost_trap/start_active, tile(2, 2))
	hci_click(H, T, null)
	test_time(7 SECONDS)
	TEST_ASSERT(!T.deployed, "an empty hand deactivates a deployed trap after a delay")
	TEST_ASSERT(!T.anchored, "and unanchors it")

/datum/unit_test/dq_hc_items/c_ghost_trap_watch_runs_on_its_own_clock

/datum/unit_test/dq_hc_items/c_ghost_trap_watch_runs_on_its_own_clock/run_gate()
	var/obj/item/ghost_trap/T = allocate(/obj/item/ghost_trap, tile(2, 2))
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, tile(4, 4))
	T.catch_ghost(ghost)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(T.captured_entity, ghost, "a catch that stays inside is kept")
	ghost.forceMove(tile(4, 4))
	test_time(5 SECONDS)
	TEST_ASSERT_NULL(T.captured_entity, "a catch that got out is noticed by the trap's own watch")
