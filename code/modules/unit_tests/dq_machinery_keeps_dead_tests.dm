// J6: deleted non-owner arguments must not strand a live machine's cleanup.
/datum/unit_test/machinery_keeps_dead
	abstract_type = /datum/unit_test/machinery_keeps_dead

/datum/unit_test/machinery_keeps_dead/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	set_global("dview_mob", GLOB.dview_mob)
	set_global(nameof(GLOB.test_prompts), list())
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	run_cleanup()

/datum/unit_test/machinery_keeps_dead/proc/run_cleanup()
	return

/datum/unit_test/machinery_keeps_dead/proc/person()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.enable_godmode()
	return H

/datum/unit_test/machinery_keeps_dead/clone_record
/datum/unit_test/machinery_keeps_dead/clone_record/run_cleanup()
	var/obj/machinery/clonepod/M = allocate(/obj/machinery/clonepod, test_floor())
	var/datum/transhuman/body_record/record = allocate(/datum/transhuman/body_record)
	var/datum/mind/mind = allocate(/datum/mind)
	rel_set(M, nameof(M.growing_record), record)
	M.eject_wait = TRUE
	M.attempting = TRUE
	after(M, 0.1 SECONDS, TYPE_PROC_REF(/obj/machinery/clonepod, clear_eject_wait), key = "j6_clone", with = list(record, mind), keeps_dead = TRUE)
	TEST_ASSERT(after_pending(M, "j6_clone"), "the real clone completion is pending before its record is deleted")
	qdel(record)
	test_time(0.2 SECONDS)
	TEST_ASSERT(!M.eject_wait, "a deleted body record still releases the pod's ejection wait")
	TEST_ASSERT(!M.attempting, "the abandoned body attempt is reset")
	TEST_ASSERT_NULL(M.growing_record, "the live pod drops its deleted record")

/datum/unit_test/machinery_keeps_dead/food_print
/datum/unit_test/machinery_keeps_dead/food_print/run_cleanup()
	var/obj/machinery/food_replicator/M = allocate(/obj/machinery/food_replicator, test_floor())
	var/obj/item/reagent_containers/glass/beaker/item = allocate(/obj/item/reagent_containers/glass/beaker, M)
	M.printing = TRUE
	M.set_use_power(USE_POWER_ACTIVE)
	after(M, 0.1 SECONDS, TYPE_PROC_REF(/obj/machinery/food_replicator, print_done), key = "j6_food", with = list(item), keeps_dead = TRUE)
	TEST_ASSERT(after_pending(M, "j6_food"), "the real printing completion is pending")
	qdel(item)
	test_time(0.2 SECONDS)
	TEST_ASSERT(!M.printing, "a deleted printout still releases the real printing flag")
	TEST_ASSERT_EQUAL(M.use_power, USE_POWER_IDLE, "the live machine returns to idle power")

/datum/unit_test/machinery_keeps_dead/gear
	abstract_type = /datum/unit_test/machinery_keeps_dead/gear
	var/dispenser_type = /obj/machinery/gear_dispenser
	var/delete_user = FALSE

/datum/unit_test/machinery_keeps_dead/gear/run_cleanup()
	set_global(nameof(GLOB.gear_distributed_to), GLOB.gear_distributed_to.Copy())
	var/obj/machinery/gear_dispenser/M = allocate(dispenser_type, test_floor())
	var/mob/living/carbon/human/H = person()
	var/datum/gear_disp/S = M.dispenses["???"]
	TEST_ASSERT(S, "the actual machine constructor supplies its real catalog setting")
	own(S)
	S.to_spawn = list(/obj/item/pen)
	M.set_emagged(TRUE)
	var/initial_flags = M.dispenser_flags
	var/datum/op_result/result = test_menu(H, M, "gear_use")
	TEST_ASSERT_EQUAL(result?.key, "gear_use", "the actual menu opens the equipment selection")
	TEST_ASSERT(SSrequests.open_for(H), "the actual request owns the machine's busy state")
	test_answer(H, "???")
	TEST_ASSERT(M.dispenser_flags != initial_flags, "the actual selected dispense remains busy during its animation")
	if(delete_user)
		qdel(H)
	else
		qdel(S)
	test_time(M.dispense_anim_time + 0.2 SECONDS)
	TEST_ASSERT_EQUAL(M.dispenser_flags, initial_flags, "the real dispensing timer releases busy even with its independent argument gone")
	if(istype(M, /obj/machinery/gear_dispenser/suit_fancy))
		TEST_ASSERT(!M.emagged(), "the fancy completion also releases its temporary emag state")
	else if(delete_user)
		var/obj/item/pen/output = locate(/obj/item/pen) in M.loc
		TEST_ASSERT(output, "the live base dispenser still delivers gear after its user vanished")
		own(output)
		TEST_ASSERT(!M.emagged(), "the completed real base dispense resets the emag state")

/datum/unit_test/machinery_keeps_dead/gear/setting
/datum/unit_test/machinery_keeps_dead/gear/user
	delete_user = TRUE
/datum/unit_test/machinery_keeps_dead/gear/fancy_setting
	dispenser_type = /obj/machinery/gear_dispenser/suit_fancy
/datum/unit_test/machinery_keeps_dead/gear/fancy_user
	dispenser_type = /obj/machinery/gear_dispenser/suit_fancy
	delete_user = TRUE

/datum/unit_test/machinery_keeps_dead/robot_stack
/datum/unit_test/machinery_keeps_dead/robot_stack/run_cleanup()
	var/obj/machinery/robotic_fabricator/M = allocate(/obj/machinery/robotic_fabricator, test_floor())
	var/mob/living/carbon/human/H = person()
	var/obj/item/stack/material/steel/S = allocate(/obj/item/stack/material/steel, test_floor(), 3)
	H.put_in_active_hand(S)
	var/before = M.metal_amount
	var/datum/op_result/result = test_menu(H, M, "insert_steel")
	TEST_ASSERT_EQUAL(result?.key, "insert_steel", "the actual menu starts the real metal-loading timer")
	TEST_ASSERT(M.inserting, "the real machine marks its pending insertion")
	qdel(S)
	test_time(1 SECOND)
	TEST_ASSERT(!M.inserting, "the deleted stack does not strand the live insertion flag")
	TEST_ASSERT_EQUAL(M.metal_amount, before, "cleanup never invents metal from a deleted stack")

/datum/unit_test/machinery_keeps_dead/robot_user
/datum/unit_test/machinery_keeps_dead/robot_user/run_cleanup()
	var/obj/machinery/robotic_fabricator/M = allocate(/obj/machinery/robotic_fabricator, test_floor())
	var/mob/living/carbon/human/H = person()
	var/obj/item/stack/material/steel/S = allocate(/obj/item/stack/material/steel, test_floor(), 3)
	H.put_in_active_hand(S)
	var/before = M.metal_amount
	var/unit_amount = S.material_totals()[MAT_STEEL]
	test_menu(H, M, "insert_steel")
	TEST_ASSERT(M.inserting, "the real machine starts loading before the independent actor is deleted")
	// Keep the real supplied stack alive independently of the actor's inventory.
	H.drop_item()
	qdel(H)
	test_time(1 SECOND)
	TEST_ASSERT(!M.inserting, "a deleted actor still releases insertion state")
	TEST_ASSERT_EQUAL(M.metal_amount, before + 3 * unit_amount, "the real surviving three-sheet stack is consumed into metal")
	TEST_ASSERT(QDELETED(S), "the actual surviving stack is completely consumed")

/datum/unit_test/machinery_keeps_dead/protean_initial
/datum/unit_test/machinery_keeps_dead/protean_initial/run_cleanup()
	var/obj/machinery/protean_reconstitutor/M = allocate(/obj/machinery/protean_reconstitutor, test_floor())
	rel_set(M, nameof(M.protean_brain), allocate(/obj/item/mmi/digital/posibrain/nano, M))
	rel_set(M, nameof(M.protean_orchestrator), allocate(/obj/item/organ/internal/nano/orchestrator, M))
	rel_set(M, nameof(M.protean_refactory), allocate(/obj/item/organ/internal/nano/refactory, M))
	M.processing_revive = TRUE
	M.per_organ_delay = 0.1 SECONDS
	M.reconstitute_begin()
	var/mob/living/carbon/human/protean/P = locate(/mob/living/carbon/human/protean) in M
	TEST_ASSERT(P, "the actual initial step creates a real unfinished protean body")
	own(P)
	TEST_ASSERT(M.processing_revive, "the actual initial organ wait is still active")
	qdel(P)
	test_time(0.2 SECONDS)
	TEST_ASSERT(!M.processing_revive, "the initial organ timer releases busy after its unfinished body is deleted")

/datum/unit_test/machinery_keeps_dead/protean_recursive
/datum/unit_test/machinery_keeps_dead/protean_recursive/run_cleanup()
	var/obj/machinery/protean_reconstitutor/M = allocate(/obj/machinery/protean_reconstitutor, test_floor())
	var/mob/living/carbon/human/protean/P = allocate(/mob/living/carbon/human/protean, M)
	var/obj/item/organ/internal/nano/orchestrator/O = allocate(/obj/item/organ/internal/nano/orchestrator, M)
	rel_set(M, nameof(M.protean_orchestrator), O)
	M.processing_revive = TRUE
	M.per_organ_delay = 0.1 SECONDS
	M.reconstitute_organ(P, list(O_ORCH, O_FACT), 1)
	TEST_ASSERT_EQUAL(P.organ_in(O_ORCH), O, "the real first organ step installs the supplied orchestrator before scheduling its successor")
	TEST_ASSERT(M.processing_revive, "the recursive organ wait remains active")
	qdel(P)
	test_time(0.2 SECONDS)
	TEST_ASSERT(!M.processing_revive, "the actual recursive organ timer releases busy when its body is deleted")

/datum/unit_test/machinery_keeps_dead/specops_user
/datum/unit_test/machinery_keeps_dead/specops_user/run_cleanup()
	set_global("specops_shuttle_moving_to_station", TRUE)
	set_global("specops_shuttle_moving_to_centcom", FALSE)
	set_global("specops_shuttle_at_station", FALSE)
	set_global("specops_shuttle_time", world.timeofday + 1 SECOND)
	set_global("specops_shuttle_timeleft", 0)
	var/obj/machinery/computer/specops_shuttle/M = allocate(/obj/machinery/computer/specops_shuttle, test_floor())
	EXPIRY_SET(M, specops_shuttle_timereset, 1 DAY, CLOCK_WORLD)
	var/mob/living/carbon/human/H = person()
	var/obj/item/radio/intercom/radio = allocate(/obj/item/radio/intercom, test_floor())
	SSshuttles.hold_specops_announcer(radio)
	specops_countdown(list(), radio, GLOBAL_PROC_REF(specops_launch), H)
	TEST_ASSERT(GLOB.specops_shuttle_moving_to_station, "the actual countdown is still pending before its user vanishes")
	TEST_ASSERT(!QDELETED(radio), "the real temporary countdown announcer is retained")
	qdel(H)
	set_global("specops_shuttle_time", world.timeofday - 1 SECOND)
	test_time(0.6 SECONDS)
	TEST_ASSERT(!GLOB.specops_shuttle_moving_to_station && !GLOB.specops_shuttle_moving_to_centcom, "the countdown still reaches real movement-state cleanup without its user")
	TEST_ASSERT(QDELETED(radio), "the refused real launch releases its temporary announcer")

/datum/unit_test/machinery_keeps_dead/transport_destination_generation
/datum/unit_test/machinery_keeps_dead/transport_destination_generation/run_cleanup()
	set_global("om_z_generations", GLOB.om_z_generations.Copy())
	var/turf/surface = test_floor()
	var/turf/destination = locate(1, 1, surface.z == 1 ? 2 : 1)
	TEST_ASSERT(destination && destination.z != surface.z, "the independent destination is on a different level from the live pod")
	var/obj/machinery/transportpod/M = allocate(/obj/machinery/transportpod, surface)
	var/handle = entity_handle(destination)
	var/owner_handle = entity_handle(M)
	after(M, 0.1 SECONDS, TYPE_PROC_REF(/obj/machinery/transportpod, arrive), key = "j6_arrive", with = list(destination), keeps_dead = TRUE)
	TEST_ASSERT(after_pending(M, "j6_arrive"), "the real arrival timer captures the live destination handle")
	// Turf positions survive ChangeTurf: release-generation invalidation, not turf qdel,
	// is the real way an independent destination handle becomes dead.
	relation_z_generation_bump(destination.z)
	TEST_ASSERT_NULL(resolve_handle(handle), "the real generation API invalidates the captured destination")
	TEST_ASSERT_EQUAL(resolve_handle(owner_handle), M, "the timer owner remains independently live after destination invalidation")
	test_time(0.6 SECONDS)
	TEST_ASSERT(QDELETED(M), "the live pod still runs its unload and expiry tail with the destination gone")
