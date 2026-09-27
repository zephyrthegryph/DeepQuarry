/datum/unit_test/dq_bluespace_denier_owned_startup_timer
	needs_test_block = FALSE

/datum/unit_test/dq_bluespace_denier_owned_startup_timer/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/obj/machinery/bluespace_denier/denier = new(test_turf)
	var/datum/object_model/schedule_entry/pending = denier.startup_timer
	TEST_ASSERT(pending && om_owner(pending) == denier, "startup belongs to the bluespace denier")
	denier.on_startup_due()
	TEST_ASSERT(!denier.startup_timer, "startup dispatch clears the pending entry")
	qdel(pending)
	denier.startup_timer = denier.After(10 SECONDS, TYPE_PROC_REF(/obj/machinery/bluespace_denier, on_startup_due))
	var/datum/object_model/schedule_entry/rearmed = denier.startup_timer
	TEST_ASSERT(rearmed && om_owner(rearmed) == denier, "startup can be scheduled again")
	qdel(denier)
	TEST_ASSERT(QDELETED(rearmed), "denier deletion cancels startup")

/datum/unit_test/dq_exonet_owned_emp_recovery_timer
	needs_test_block = FALSE

/datum/unit_test/dq_exonet_owned_emp_recovery_timer/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/obj/machinery/exonet_node/node = new(test_turf)
	node.emp_act(2)
	var/datum/object_model/schedule_entry/recovery = node.emp_recovery_timer
	TEST_ASSERT((node.stat & EMPED) && recovery && om_owner(recovery) == node, "EMP schedules an owned recovery")
	node.emp_recover()
	node.emp_act(2)
	var/datum/object_model/schedule_entry/replacement = node.emp_recovery_timer
	TEST_ASSERT(QDELETED(recovery) && replacement && replacement != recovery, "repeated EMP replaces the pending recovery")
	qdel(node)
	TEST_ASSERT(QDELETED(replacement), "node deletion cancels EMP recovery")
