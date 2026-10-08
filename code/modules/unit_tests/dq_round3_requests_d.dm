// Public requests retain real state changes and cancellations.
/datum/unit_test/dq_hc_computers/dq_round3_requests_d
	abstract_type = /datum/unit_test/dq_hc_computers/dq_round3_requests_d

/datum/unit_test/dq_hc_computers/dq_round3_requests_d/magnet
/datum/unit_test/dq_hc_computers/dq_round3_requests_d/magnet/run_gate()
	var/obj/machinery/magnetic_controller/C = allocate(/obj/machinery/magnetic_controller, hc_spot())
	C.set_grid_power(TRUE)
	C.set_broken_condition(FALSE)
	var/mob/living/carbon/human/H = hc_actor()
	var/datum/op_result/result = test_ui(H, C, "set_path")
	TEST_ASSERT_EQUAL(result?.key, "set_path", "the real window action selects the path op")
	TEST_ASSERT_NULL(result?.outcome, "the path op waits for the actual text answer")
	TEST_ASSERT(SSrequests.open_for(H), "the operator has a real question")
	test_answer(H, "N;E W")
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "the original op commits after its answer")
	TEST_ASSERT_EQUAL(C.path, "N;E W", "the real controller stores the entered path")
	TEST_ASSERT_EQUAL(C.rpath.Join(), "NEW", "the real path filter preserves movement and removes separators")
	TEST_ASSERT_EQUAL(C.pathpos, 1, "the new route begins from its first step")
	TEST_ASSERT(!C.path_moving, "editing a path stops the actual movement state")
	var/datum/op_result/cancelled = test_ui(H, C, "set_path")
	TEST_ASSERT(SSrequests.open_for(H), "a second real path question exists")
	test_answer(H, null, outcome = REQ_CANCELLED)
	TEST_ASSERT_EQUAL(cancelled?.outcome, ACT_REFUSED, "canceling terminates the second original op")
	TEST_ASSERT_EQUAL(C.path, "N;E W", "canceling preserves the actual route")

/datum/unit_test/dq_hc_computers/dq_round3_requests_d/traffic
/datum/unit_test/dq_hc_computers/dq_round3_requests_d/traffic/run_gate()
	var/obj/machinery/computer/telecomms/traffic/C = hc_console(/obj/machinery/computer/telecomms/traffic)
	var/mob/living/carbon/human/H = hc_boss()
	var/datum/op_result/result = test_ui(H, C, "set_network")
	TEST_ASSERT_EQUAL(result?.key, "set_network", "the actual network action resolves")
	TEST_ASSERT(SSrequests.open_for(H), "a credentialed actor receives the actual network question")
	test_answer(H, "round3-net")
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "answering commits the actual network op")
	TEST_ASSERT_EQUAL(C.network, "round3-net", "the actual console changes its network")
	TEST_ASSERT_EQUAL(C.screen, 0, "the new network returns to the actual main screen")
	TEST_ASSERT_EQUAL(length(C.servers), 0, "the actual server buffer is empty after switching")

/datum/unit_test/dq_hc_computers/dq_round3_requests_d/alien_wire
/datum/unit_test/dq_hc_computers/dq_round3_requests_d/alien_wire/run_gate()
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/stack/cable_coil/alien/C = allocate(/obj/item/stack/cable_coil/alien, hc_side())
	H.put_in_inactive_hand(C)
	TEST_ASSERT_EQUAL(H.get_inactive_hand(), C, "the real endless coil is in the inactive hand")
	var/before = C.amount
	var/datum/op_result/result = test_click(H, C, null)
	TEST_ASSERT_EQUAL(result?.key, "split", "the real hand input resolves the native split")
	TEST_ASSERT(SSrequests.open_for(H), "the actual carried coil asks for a length")
	test_answer(H, 5)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "the real length answer commits the original split")
	var/obj/item/stack/cable_coil/taken = H.get_active_hand()
	TEST_ASSERT(istype(taken) && taken != C, "the actor holds a real separate ordinary coil")
	TEST_ASSERT_EQUAL(taken?.get_amount(), 5, "the real taken coil has the entered length")
	TEST_ASSERT_EQUAL(C.amount, before, "the endless coil retains its source amount")
	TEST_ASSERT_EQUAL(H.get_inactive_hand(), C, "the actual source stays in its original hand")

/datum/unit_test/dq_hc_computers/dq_round3_requests_d/pandemic
	abstract_type = /datum/unit_test/dq_hc_computers/dq_round3_requests_d/pandemic

/datum/unit_test/dq_hc_computers/dq_round3_requests_d/pandemic/proc/clear_strain_archive(list/archive)
	for(var/key in archive)
		var/datum/affliction/contagion/engineered/D = archive[key]
		if(!QDELETED(D))
			qdel(D)
	archive.Cut()

/datum/unit_test/dq_hc_computers/dq_round3_requests_d/pandemic/proc/loaded_console()
	var/list/archive = list()
	set_global(nameof(GLOB.archive_diseases), archive)
	defer_cleanup(src, PROC_REF(clear_strain_archive), archive)
	var/datum/affliction/contagion/engineered/D = allocate(/datum/affliction/contagion/engineered, FALSE)
	var/datum/viral_trait/symptom = allocate(/datum/viral_trait/sneeze)
	rel_add(D, nameof(D.symptoms), symptom)
	TEST_ASSERT(D.GetDiseaseID(), "the actual symptom creates a nonempty archived strain identity")
	var/obj/machinery/computer/pandemic/C = hc_console(/obj/machinery/computer/pandemic)
	var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker, hc_spot())
	B.reagents.add_reagent(REAGENT_ID_BLOOD, 1, list("viruses" = list(D)))
	rel_set(C, nameof(C.beaker), B)
	archive[D.GetDiseaseID()] = D
	TEST_ASSERT_EQUAL(C.get_virus_id_by_index(1), D.GetDiseaseID(), "the actual blood catalogue resolves the loaded real strain")
	return C

/datum/unit_test/dq_hc_computers/dq_round3_requests_d/pandemic/proc/request_actor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/round3_request_actor, hc_side())
	H.enable_godmode()
	return H

/datum/unit_test/dq_hc_computers/dq_round3_requests_d/pandemic/unsigned
/datum/unit_test/dq_hc_computers/dq_round3_requests_d/pandemic/unsigned/run_gate()
	var/obj/machinery/computer/pandemic/C = loaded_console()
	var/mob/living/carbon/human/H = request_actor()
	var/datum/op_result/result = test_ui(H, C, "print_release_form", list("index" = 1))
	TEST_ASSERT_EQUAL(result?.key, "print_release_form", "the actual form action resolves")
	var/datum/prompt/text/pandemic_release_reason/reason = SSrequests.open_for(H)
	TEST_ASSERT(istype(reason), "the first actual request asks for a release reason")
	var/datum/affliction/contagion/engineered/strain = reason.affliction
	test_answer(H, "Controlled testing")
	var/datum/prompt/yes_no/pandemic_release_sign/signature = SSrequests.open_for(H)
	TEST_ASSERT(istype(signature), "answering the reason opens the actual signature request")
	TEST_ASSERT_EQUAL(signature.disease, strain, "the signature retains the first question's actual archived strain")
	TEST_ASSERT_EQUAL(signature.reason, "Controlled testing", "the signature retains the actual reason answer")
	test_answer(H, FALSE)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "an answered No prints an unsigned form rather than canceling")
	var/obj/item/paper/P = locate(/obj/item/paper) in C.loc
	TEST_ASSERT(P, "a real release paper exists on the console's tile")
	TEST_ASSERT(findtext(P.info, "Controlled testing"), "the actual paper contains the supplied release reason")
	TEST_ASSERT(!findtext(P.info, H.real_name), "declining the signature omits the operator's actual name")
	TEST_ASSERT(!C.printing, "the actual printing state returns to idle")

/datum/unit_test/dq_hc_computers/dq_round3_requests_d/pandemic/cancel_signature
/datum/unit_test/dq_hc_computers/dq_round3_requests_d/pandemic/cancel_signature/run_gate()
	var/obj/machinery/computer/pandemic/C = loaded_console()
	var/mob/living/carbon/human/H = request_actor()
	var/datum/op_result/result = test_ui(H, C, "print_release_form", list("index" = 1))
	TEST_ASSERT(istype(SSrequests.open_for(H), /datum/prompt/text/pandemic_release_reason), "a real first question exists")
	test_answer(H, "Canceled release")
	TEST_ASSERT(istype(SSrequests.open_for(H), /datum/prompt/yes_no/pandemic_release_sign), "a real second question exists before cancellation")
	test_answer(H, null, outcome = REQ_CANCELLED)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "canceling the second question aborts the original op")
	var/obj/item/paper/P = locate(/obj/item/paper) in C.loc
	TEST_ASSERT_NULL(P, "canceling the signature produces no actual release paper")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "canceling leaves no actor request")
