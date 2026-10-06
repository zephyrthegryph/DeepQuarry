/// Observe the supplied actor at the real containment boundary without changing insertion.
/datum/interim_resleever_actor_probe
	var/last_actor_ref
	var/insert_count = 0

/datum/interim_resleever_actor_probe/proc/on_insert(datum/act/check_insert/check)
	SHOULD_NOT_SLEEP(TRUE)
	last_actor_ref = check.actor ? REF(check.actor) : null
	insert_count++
	return HOOK_DECLINE

/datum/unit_test/interim_resleever_actor_roundtrip/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/transhuman/resleever/pod = allocate(/obj/machinery/transhuman/resleever, T)
	var/datum/interim_resleever_actor_probe/probe = allocate(/datum/interim_resleever_actor_probe)
	observe(pod, /datum/act/check_insert, probe, instead(then(TYPE_PROC_REF(/datum/interim_resleever_actor_probe, on_insert))))
	TEST_ASSERT(pod.resleever_interaction_drag(actor, patient, null), "Dragging the patient through the public interaction must succeed")
	TEST_ASSERT_EQUAL(probe.last_actor_ref, REF(actor), "The drag initiator must reach the real insertion boundary")
	TEST_ASSERT_EQUAL(probe.insert_count, 1, "The successful drag must attempt exactly one insertion")
	TEST_ASSERT_EQUAL(pod.get_occupant(), patient, "The machine must record the inserted patient")
	TEST_ASSERT_EQUAL(pod.slot_item(OCCUPANT_SLOT_RESLEEVER), patient, "The real slot must contain the patient")
	TEST_ASSERT_EQUAL(patient.loc, pod, "The patient must be inside the machine")
	TEST_ASSERT_EQUAL(pod.icon_state, "implantchair_on", "Successful insertion must select occupied presentation")
	TEST_ASSERT(!pod.put_mob(actor, actor), "An occupied machine must refuse a second patient")
	TEST_ASSERT_EQUAL(probe.insert_count, 1, "Occupied refusal must never enter the containment transaction")
	TEST_ASSERT_EQUAL(pod.get_occupant(), patient, "Refused insertion must preserve the original occupant")
	pod.go_out()
	TEST_ASSERT_NULL(pod.get_occupant(), "Ejection must clear the recorded occupant")
	TEST_ASSERT_NULL(pod.slot_item(OCCUPANT_SLOT_RESLEEVER), "Ejection must clear the actual occupant slot")
	TEST_ASSERT_EQUAL(patient.loc, T, "Ejection must return the patient to the floor")
	pod.set_stat(0)
	TEST_ASSERT(pod.operable(), "The self-entry fixture must be operable")
	pod.resleever_verb_move_inside(actor, null, null)
	TEST_ASSERT_EQUAL(probe.last_actor_ref, REF(actor), "Self-entry must forward its actor to the insertion boundary")
	TEST_ASSERT_EQUAL(probe.insert_count, 2, "Self-entry must run a fresh actual insertion")
	TEST_ASSERT_EQUAL(pod.get_occupant(), actor, "Self-entry must seat the initiating actor")
	TEST_ASSERT_EQUAL(actor.loc, pod, "Self-entry must actually move the actor into the machine")
	pod.go_out()
