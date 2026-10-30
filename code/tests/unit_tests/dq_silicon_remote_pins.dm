// These are viewer facts, rather than grants of remote authority. In particular,
// the old photocopier field named isAI includes a borg, unlike the fax field.
/datum/unit_test/dq_silicon/remote_viewer_facts

/datum/unit_test/dq_silicon/remote_viewer_facts/run_gate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = make_human(T)
	var/mob/living/silicon/robot/R = make_borg(T)
	var/mob/living/silicon/ai/AI = make_ai(T)
	var/list/actors = list(H, R, AI)
	var/list/subjects = list(
		/obj/machinery/ai_slipper = list("is_silicon" = list(FALSE, TRUE, TRUE)),
		/obj/machinery/partyalarm = list("scrambled" = list(FALSE, TRUE, FALSE)),
		/obj/machinery/photocopier = list("isAI" = list(FALSE, TRUE, TRUE)),
		/obj/machinery/photocopier/faxmachine = list("isAI" = list(FALSE, FALSE, TRUE), "isRobot" = list(FALSE, TRUE, FALSE)),
		/obj/machinery/disposal = list("isAI" = list(FALSE, FALSE, TRUE)),
	)
	for(var/subject_type in subjects)
		var/obj/machinery/subject = allocate(subject_type, T)
		subject.set_grid_power(TRUE)
		var/list/fields = subjects[subject_type]
		for(var/actor_index in 1 to length(actors))
			var/datum/act/eval/A = take(/datum/act/eval)
			A.actor = actors[actor_index]
			A.holder = subject
			var/list/data = subject.ui_data(A)
			A.release()
			for(var/field in fields)
				TEST_ASSERT(field in data, "The real [subject_type] window emits its [field] field")
				var/list/expected = fields[field]
				TEST_ASSERT_EQUAL(!!data[field], expected[actor_index], "The real [subject_type] window preserves [field] for actor [actor_index]")
