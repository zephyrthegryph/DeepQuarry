// asks(..., repeats = PROC_REF(x)) (doc/rewrite/framework_gaps.md H4), and the ban flows built on it: every ban question is an asks() step of its op, the
// ban is written once after the last answer, a cancel at any step writes nothing.

// ---------------------------------------------------------------- the part itself

/// A machine that collects items one question at a time until the admin says "done".
/obj/h4_collector
	name = "h4 collector"
	anchored = TRUE
	var/list/collected
	var/ran = 0

CAPABILITIES(/obj/h4_collector)
	op("collect", ui_act("collect"), asks(/datum/prompt/text, fields = list("question" = computed(PROC_REF(next_question)), "timeout" = 0), step = "item", repeats = PROC_REF(wants_more)), then(PROC_REF(collected)))
	op("collect_limited", ui_act("collect_limited"), asks(/datum/prompt/choice, fields = list("question" = "Collect how?", "choices" = list("many", "none"), "timeout" = 0), step = "mode"), asks(/datum/prompt/text, fields = list("question" = computed(PROC_REF(next_question)), "timeout" = 0), step = "item", when = PROC_REF(mode_is_many), repeats = PROC_REF(under_limit)), then(PROC_REF(collected)))

/obj/h4_collector/proc/next_question(datum/act/op/A)
	return "Item [length(A.step_values("item")) + 1]?"

/obj/h4_collector/proc/wants_more(datum/act/op/A)
	return A.step_value("item") != "done"

/obj/h4_collector/proc/mode_is_many(datum/act/op/A)
	return A.step_value("mode") == "many"

/obj/h4_collector/proc/under_limit(datum/act/op/A)
	return length(A.step_values("item")) < 2

/obj/h4_collector/proc/collected(datum/act/op/A)
	ran++
	collected = A.step_values("item")
	return OP_OK

/datum/unit_test/dq_h4
	abstract_type = /datum/unit_test/dq_h4

/datum/unit_test/dq_h4/Run()
	test_driver_begin()
	test_prompts_reset()
	run_h4()
	GLOB.test_prompts = null
	test_driver_end()

/datum/unit_test/dq_h4/proc/run_h4()
	return

/datum/unit_test/dq_h4/proc/actor()
	return allocate(/mob/living/simple_mob/e0_fixture)

/datum/unit_test/dq_h4/repeat_asks_until_the_handler_says_stop

/datum/unit_test/dq_h4/repeat_asks_until_the_handler_says_stop/run_h4()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/h4_collector/C = allocate(/obj/h4_collector)
	var/datum/op_result/waiting = test_ui(M, C, "collect", list())
	TEST_ASSERT_NULL(waiting?.outcome, "the op waits on its first question")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "one question is open")
	var/datum/prompt/first = GLOB.test_prompts[1]
	TEST_ASSERT_EQUAL(first.question, "Item 1?", "the first round's question")
	var/datum/op_result/second = test_answer(M, "a")
	TEST_ASSERT_NULL(second?.outcome, "an answer the handler wants more after asks again")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 2, "a second question opened")
	var/datum/prompt/second_prompt = GLOB.test_prompts[2]
	TEST_ASSERT_EQUAL(second_prompt.question, "Item 2?", "its fields were computed again: it names the next round")
	test_answer(M, "b")
	TEST_ASSERT_EQUAL(C.ran, 0, "the effect has not run while the loop goes on")
	var/datum/op_result/done = test_answer(M, "done")
	TEST_ASSERT_EQUAL(done?.outcome, ACT_COMMITTED, "the answer that makes the handler return false ends the loop and the op commits")
	TEST_ASSERT_EQUAL(C.ran, 1, "the effect ran once")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 3, "and no question was asked after it")

/datum/unit_test/dq_h4/repeat_answers_accumulate_in_order

/datum/unit_test/dq_h4/repeat_answers_accumulate_in_order/run_h4()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/h4_collector/C = allocate(/obj/h4_collector)
	test_ui(M, C, "collect", list())
	test_answer(M, "x")
	test_answer(M, "y")
	test_answer(M, "z")
	var/datum/op_result/done = test_answer(M, "done")
	TEST_ASSERT_EQUAL(done?.outcome, ACT_COMMITTED, "the op commits")
	TEST_ASSERT_EQUAL(json_encode(C.collected), json_encode(list("x", "y", "z", "done")), "the handler reads every answer, in order, as a list")

/datum/unit_test/dq_h4/repeat_composes_with_when_skips

/datum/unit_test/dq_h4/repeat_composes_with_when_skips/run_h4()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/h4_collector/C = allocate(/obj/h4_collector)
	test_ui(M, C, "collect_limited", list())
	test_answer(M, "none")
	TEST_ASSERT_EQUAL(C.ran, 1, "a skipped repeating step asks nothing and the op goes on")
	TEST_ASSERT_EQUAL(length(C.collected), 0, "with no answers")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "only the mode question was asked")
	test_ui(M, C, "collect_limited", list())
	test_answer(M, "many")
	test_answer(M, "p")
	var/datum/op_result/done = test_answer(M, "q")
	TEST_ASSERT_EQUAL(done?.outcome, ACT_COMMITTED, "a reached repeating step loops while the handler says so, then commits")
	TEST_ASSERT_EQUAL(json_encode(C.collected), json_encode(list("p", "q")), "with both answers")

/datum/unit_test/dq_h4/cancelling_mid_loop_leaves_no_pending_op

/datum/unit_test/dq_h4/cancelling_mid_loop_leaves_no_pending_op/run_h4()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/h4_collector/C = allocate(/obj/h4_collector)
	var/pending_before = length(GLOB.op_pending_all)
	var/datum/op_result/waiting = test_ui(M, C, "collect", list())
	TEST_ASSERT_EQUAL(length(GLOB.op_pending_all), pending_before + 1, "the op is pending")
	test_answer(M, "a")
	test_answer(M, "b")
	var/datum/op_result/cancelled = test_answer(M, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(cancelled?.outcome, ACT_REFUSED, "cancelling the third round refuses the op")
	TEST_ASSERT(cancelled == waiting, "through the same result")
	TEST_ASSERT_EQUAL(C.ran, 0, "the effect never ran")
	TEST_ASSERT_EQUAL(length(GLOB.op_pending_all), pending_before, "no pending op is left")
	TEST_ASSERT_NULL(test_answer(M, "late"), "a late answer finds nothing")

// ---------------------------------------------------------------- claims over the asks() phase, asks(answerer =), starts() refusals

MSG_DEF_SELF(h4/not_now, "Not now.")

/obj/h4_kiosk
	name = "h4 kiosk"
	anchored = TRUE
	var/scans = 0
	var/consent
	/// The mob the scan question goes to.
	var/mob/patient

CAPABILITIES(/obj/h4_kiosk)
	op("held_ask", ui_act("held_ask"), claims(CLAIM_TARGET), asks(/datum/prompt/text, fields = list("question" = "Name?", "timeout" = 0), step = "name"), then(PROC_REF(scanned)))
	op("hands_ask", ui_act("hands_ask"), claims(CLAIM_HANDS), asks(/datum/prompt/text, fields = list("question" = "Name?", "timeout" = 0), step = "name"), then(PROC_REF(scanned)))
	op("hands_other", ai(), claims(CLAIM_HANDS), then(PROC_REF(scanned)))
	op("scan", ui_act("scan"), asks(/datum/prompt/yes_no, fields = list("question" = "Consent to a scan?", "timeout" = 0), step = "consent", answerer = PROC_REF(consenter), ends_on_no = TRUE), then(PROC_REF(scanned)))
	op("refused_start", ui_act("refused_start"), wait(2 SECONDS), starts(PROC_REF(refuse_start)), then(PROC_REF(scanned)))

/obj/h4_kiosk/proc/consenter(datum/act/op/A)
	return patient

/obj/h4_kiosk/proc/refuse_start(datum/act/op/A)
	return MSG(h4/not_now)

/obj/h4_kiosk/proc/scanned(datum/act/op/A)
	scans++
	consent = A.step_value("consent")
	return OP_OK

/datum/unit_test/dq_h4/claims_hold_while_a_question_is_open

/datum/unit_test/dq_h4/claims_hold_while_a_question_is_open/run_h4()
	var/mob/living/simple_mob/e0_fixture/first = actor()
	var/mob/living/simple_mob/e0_fixture/second = actor()
	var/obj/h4_kiosk/K = allocate(/obj/h4_kiosk)
	var/datum/op_result/waiting = test_ui(first, K, "held_ask", list())
	TEST_ASSERT_NULL(waiting?.outcome, "the first actor's question is open")
	var/datum/op_result/refused = test_ui(second, K, "held_ask", list())
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "a second actor is refused while the first one's question is open")
	TEST_ASSERT_EQUAL(refused?.reason, /datum/msg/op/claimed, "because it is in use")
	test_answer(first, null, REQ_CANCELLED)
	var/datum/op_result/allowed = test_ui(second, K, "held_ask", list())
	TEST_ASSERT_NULL(allowed?.outcome, "after the first cancels, the second one's question opens")
	test_answer(second, "ok")
	TEST_ASSERT_EQUAL(K.scans, 1, "and runs to its end")
	// hands: the actor's own claim holds against an input that cannot stop it
	var/datum/op_result/open_hands = test_ui(first, K, "hands_ask", list())
	TEST_ASSERT_NULL(open_hands?.outcome, "the hands claim is taken when the question opens")
	var/datum/op_result/busy = op_perform_by_key(first, K, null, "hands_other", ORIGIN_AI, AUTH_PHYSICAL, FALSE)
	TEST_ASSERT_EQUAL(busy?.outcome, ACT_REFUSED, "an AI input needing the same hands is refused")
	TEST_ASSERT_EQUAL(busy?.reason, /datum/msg/op/busy, "as busy")
	test_answer(first, null, REQ_CANCELLED)
	var/datum/op_result/free = op_perform_by_key(first, K, null, "hands_other", ORIGIN_AI, AUTH_PHYSICAL, FALSE)
	TEST_ASSERT_EQUAL(free?.outcome, ACT_COMMITTED, "the claim is released when the op is cancelled")

/datum/unit_test/dq_h4/a_third_party_answers_the_question

/datum/unit_test/dq_h4/a_third_party_answers_the_question/run_h4()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/simple_mob/e0_fixture/doctor = allocate(/mob/living/simple_mob/e0_fixture, T)
	var/mob/living/simple_mob/e0_fixture/patient = allocate(/mob/living/simple_mob/e0_fixture, get_step(T, EAST))
	var/obj/h4_kiosk/K = allocate(/obj/h4_kiosk, T)
	K.patient = patient
	// consent
	var/datum/op_result/waiting = test_ui(doctor, K, "scan", list())
	TEST_ASSERT_NULL(waiting?.outcome, "the op waits for the patient")
	var/datum/prompt/asked = GLOB.test_prompts[1]
	TEST_ASSERT(asked.answerer == patient, "the question went to the patient, not the actor")
	TEST_ASSERT_NULL(test_answer(doctor, TRUE), "the actor has no question to answer")
	var/datum/op_result/done = test_answer(patient, TRUE)
	TEST_ASSERT_EQUAL(done?.outcome, ACT_COMMITTED, "a patient who consents lets the op proceed")
	TEST_ASSERT_EQUAL(K.scans, 1, "the effect ran")
	TEST_ASSERT_EQUAL(K.consent, TRUE, "and read the answer like any other")
	// decline: a no
	test_ui(doctor, K, "scan", list())
	var/datum/op_result/declined = test_answer(patient, FALSE)
	TEST_ASSERT_EQUAL(declined?.outcome, ACT_REFUSED, "a patient who says no ends the op")
	// decline: the window closed
	test_ui(doctor, K, "scan", list())
	var/datum/op_result/closed = test_answer(patient, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(closed?.outcome, ACT_REFUSED, "a patient who closes the prompt ends the op")
	TEST_ASSERT_EQUAL(K.scans, 1, "neither scanned")
	// moves away
	var/datum/op_result/leaving = test_ui(doctor, K, "scan", list())
	TEST_ASSERT_NULL(leaving?.outcome, "the question is open again")
	patient.forceMove(get_step(get_step(get_step(T, EAST), EAST), EAST))
	TEST_ASSERT_EQUAL(leaving?.outcome, ACT_REFUSED, "a patient who moves out of reach ends the op")
	TEST_ASSERT_EQUAL(K.scans, 1, "without a scan")
	TEST_ASSERT_NULL(test_answer(patient, TRUE), "and their question is closed")

/datum/unit_test/dq_h4/a_starts_refusal_ends_the_op_before_the_wait

/datum/unit_test/dq_h4/a_starts_refusal_ends_the_op_before_the_wait/run_h4()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/h4_kiosk/K = allocate(/obj/h4_kiosk)
	var/pending_before = length(GLOB.op_pending_all)
	var/datum/op_result/refused = test_ui(M, K, "refused_start", list())
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "the op ends")
	TEST_ASSERT_EQUAL(refused?.reason, MSG(h4/not_now), "with the handler's message")
	TEST_ASSERT_EQUAL(length(GLOB.op_pending_all), pending_before, "no wait is pending")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(K.scans, 0, "and the effect never ran")

// ---------------------------------------------------------------- the ban flows

/// A holder whose writes are recorded instead of made: the flows are tested up to the write, with exactly what would be written.
/datum/admins/dq_ban_flow_fixture
	var/list/commits = list()
	var/panels = 0

/datum/admins/dq_ban_flow_fixture/ban_commit_temp(mob/user, mob/M, mins, reason)
	commits += list(list("temp", M, mins, reason))

/datum/admins/dq_ban_flow_fixture/ban_commit_perm(mob/user, mob/M, reason, ip_ban)
	commits += list(list("perm", M, reason, ip_ban))

/datum/admins/dq_ban_flow_fixture/jobban_apply(mob/user, mob/M, list/jobs, mins, reason)
	commits += list(list("jobs", M, jobs.Copy(), mins, reason))

/datum/admins/dq_ban_flow_fixture/jobban_lift(mob/user, mob/M, list/jobs)
	commits += list(list("lift", M, jobs.Copy()))

/datum/admins/dq_ban_flow_fixture/unbanpanel()
	panels++

/// A clientless test panel: its links are open to the test actor (the owner check and the token are the panel's own and need a client).
/datum/admins/dq_ban_flow_fixture/op_topic_actor_ok(mob/actor)
	return TRUE

/datum/admins/dq_ban_flow_fixture/op_topic_token_ok(mob/actor, token)
	return TRUE

/datum/unit_test/dq_h4/ban
	abstract_type = /datum/unit_test/dq_h4/ban

/datum/unit_test/dq_h4/ban/proc/holder()
	var/fixture_key = "dq_h4_ban_[type]"
	set_global("admin_datums", GLOB.admin_datums.Copy())
	set_global("deadmins", GLOB.deadmins.Copy())
	var/datum/admins/dq_ban_flow_fixture/H = allocate(/datum/admins/dq_ban_flow_fixture, list(), fixture_key)
	GLOB.admin_datums -= fixture_key
	return H

/// Starts `key` on the holder as an admin call with `arg_values`.
/datum/unit_test/dq_h4/ban/proc/start(mob/actor, datum/admins/H, key, list/arg_values)
	test_prompts_reset()
	arg_values[OP_TOPIC_HREF] = list("admin_token" = "test")
	return op_perform_by_key(actor, H, null, key, ORIGIN_UI, AUTH_ADMIN, FALSE, arg_values)

/// The prompt kinds asked so far, in order, as short names.
/datum/unit_test/dq_h4/ban/proc/asked()
	var/list/kinds = list()
	for(var/datum/prompt/P in GLOB.test_prompts)
		if(istype(P, /datum/prompt/number))
			kinds += "number"
		else if(istype(P, /datum/prompt/text))
			kinds += "text"
		else if(istype(P, /datum/prompt/choice))
			kinds += "choice"
		else
			kinds += "other"
	return kinds.Join(",")

/datum/unit_test/dq_h4/ban/proc/target()
	var/mob/living/carbon/human/T = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	return T

/datum/unit_test/dq_h4/ban/temporary_ban_with_a_duration

/datum/unit_test/dq_h4/ban/temporary_ban_with_a_duration/run_h4()
	var/mob/living/carbon/human/admin = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/T = target()
	var/datum/admins/dq_ban_flow_fixture/H = holder()
	start(admin, H, "newban", list("newban" = T))
	TEST_ASSERT_EQUAL(asked(), "choice", "the flow opens with the temporary question")
	test_answer(admin, "Yes")
	TEST_ASSERT_EQUAL(asked(), "choice,number", "a temporary ban asks how long")
	test_answer(admin, 90)
	TEST_ASSERT_EQUAL(asked(), "choice,number,text", "then why")
	TEST_ASSERT_EQUAL(length(H.commits), 0, "nothing is written before the last answer")
	var/datum/op_result/done = test_answer(admin, "Griefing")
	TEST_ASSERT_EQUAL(done?.outcome, ACT_COMMITTED, "the last answer commits the op")
	TEST_ASSERT_EQUAL(asked(), "choice,number,text", "and no IP question is asked of a temporary ban")
	TEST_ASSERT_EQUAL(length(H.commits), 1, "one ban was written")
	var/list/commit = H.commits[1]
	TEST_ASSERT_EQUAL(commit[1], "temp", "a temporary one")
	TEST_ASSERT(commit[2] == T, "of the target")
	TEST_ASSERT_EQUAL(commit[3], 90, "for the duration the admin gave")
	TEST_ASSERT_EQUAL(commit[4], "Griefing", "with the reason")

/datum/unit_test/dq_h4/ban/permanent_ban_asks_the_ip_question

/datum/unit_test/dq_h4/ban/permanent_ban_asks_the_ip_question/run_h4()
	var/mob/living/carbon/human/admin = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/T = target()
	var/datum/admins/dq_ban_flow_fixture/H = holder()
	start(admin, H, "newban", list("newban" = T))
	test_answer(admin, "No")
	TEST_ASSERT_EQUAL(asked(), "choice,text", "a permanent ban skips the duration and asks why")
	test_answer(admin, "Evading")
	TEST_ASSERT_EQUAL(asked(), "choice,text,choice", "then asks about the IP")
	var/datum/op_result/done = test_answer(admin, "Yes")
	TEST_ASSERT_EQUAL(done?.outcome, ACT_COMMITTED, "the op commits")
	TEST_ASSERT_EQUAL(length(H.commits), 1, "one ban was written")
	var/list/commit = H.commits[1]
	TEST_ASSERT_EQUAL(commit[1], "perm", "a permanent one")
	TEST_ASSERT_EQUAL(commit[3], "Evading", "with the reason")
	TEST_ASSERT_EQUAL(commit[4], TRUE, "and the IP ban the admin chose")

/datum/unit_test/dq_h4/ban/cancel_writes_nothing

/datum/unit_test/dq_h4/ban/cancel_writes_nothing/run_h4()
	var/mob/living/carbon/human/admin = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/T = target()
	var/datum/admins/dq_ban_flow_fixture/H = holder()
	var/pending_before = length(GLOB.op_pending_all)
	start(admin, H, "newban", list("newban" = T))
	var/datum/op_result/answered_cancel = test_answer(admin, "Cancel")
	TEST_ASSERT_EQUAL(answered_cancel?.outcome, ACT_COMMITTED, "the Cancel choice ends the op")
	TEST_ASSERT_EQUAL(asked(), "choice", "with no further question")
	TEST_ASSERT_EQUAL(length(H.commits), 0, "and nothing written")
	start(admin, H, "newban", list("newban" = T))
	test_answer(admin, "Yes")
	var/datum/op_result/closed = test_answer(admin, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(closed?.outcome, ACT_REFUSED, "closing a question mid-flow refuses the op")
	TEST_ASSERT_EQUAL(length(H.commits), 0, "and nothing was written")
	TEST_ASSERT_EQUAL(length(GLOB.op_pending_all), pending_before, "no pending op is left")

/datum/unit_test/dq_h4/ban/job_ban_over_several_jobs

/datum/unit_test/dq_h4/ban/job_ban_over_several_jobs/run_h4()
	var/mob/living/carbon/human/admin = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/T = target()
	var/datum/admins/dq_ban_flow_fixture/H = holder()
	var/list/expected = H.jobban_job_list("nonhumandept")
	TEST_ASSERT(length(expected) >= 2, "a department names several jobs")
	set_config(/datum/config_entry/flag/ban_legacy_system, FALSE)
	start(admin, H, "jobban3", list("jobban3" = "nonhumandept", "jobban4" = T))
	test_answer(admin, "Yes")
	test_answer(admin, 45)
	var/datum/op_result/done = test_answer(admin, "Absent")
	TEST_ASSERT_EQUAL(done?.outcome, ACT_COMMITTED, "one set of answers bans the whole department")
	TEST_ASSERT_EQUAL(asked(), "choice,number,text", "asked once, not per job")
	TEST_ASSERT_EQUAL(length(H.commits), 1, "one write")
	var/list/commit = H.commits[1]
	TEST_ASSERT_EQUAL(commit[1], "jobs", "a job ban")
	TEST_ASSERT_EQUAL(json_encode(commit[3]), json_encode(expected), "of every job in the department")
	TEST_ASSERT_EQUAL(commit[4], 45, "temporary, for the duration given")
	TEST_ASSERT_EQUAL(commit[5], "Absent", "with the reason")
	// permanent
	H.commits.Cut()
	start(admin, H, "jobban3", list("jobban3" = "nonhumandept", "jobban4" = T))
	test_answer(admin, "No")
	TEST_ASSERT_EQUAL(asked(), "choice,text", "a permanent job ban asks only why")
	test_answer(admin, "Never again")
	TEST_ASSERT_EQUAL(length(H.commits), 1, "one write")
	var/list/perma = H.commits[1]
	TEST_ASSERT_EQUAL(perma[4], -1, "permanent")
	TEST_ASSERT_EQUAL(json_encode(perma[3]), json_encode(expected), "of every job")

/datum/unit_test/dq_h4/ban/job_unban_repeats_per_banned_job

/datum/unit_test/dq_h4/ban/job_unban_repeats_per_banned_job/run_h4()
	var/mob/living/carbon/human/admin = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/T = target()
	var/datum/admins/dq_ban_flow_fixture/H = holder()
	set_config(/datum/config_entry/flag/ban_legacy_system, TRUE)
	var/list/jobs = H.jobban_job_list("nonhumandept")
	TEST_ASSERT(length(jobs) >= 2, "a department names several jobs")
	set_global("jobban_keylist", GLOB.jobban_keylist.Copy())
	for(var/job in jobs)
		GLOB.jobban_keylist += "[T.ckey] - [job] ## test reason"
	start(admin, H, "jobban3", list("jobban3" = "nonhumandept", "jobban4" = T))
	TEST_ASSERT_EQUAL(asked(), "choice", "every job is banned already: the first confirmation opens")
	var/datum/prompt/first = GLOB.test_prompts[1]
	TEST_ASSERT(findtext(first.question, "Job: '[jobs[1]]'"), "and names the first job: [first.question]")
	var/list/want = list()
	for(var/i in 1 to length(jobs))
		var/datum/op_result/step = test_answer(admin, i % 2 ? "Yes" : "No")
		if(i % 2)
			want += jobs[i]
		if(i < length(jobs))
			TEST_ASSERT_NULL(step?.outcome, "the next banned job is asked about")
			var/datum/prompt/next = GLOB.test_prompts[i + 1]
			TEST_ASSERT(findtext(next.question, "Job: '[jobs[i + 1]]'"), "naming the next job: [next.question]")
		else
			TEST_ASSERT_EQUAL(step?.outcome, ACT_COMMITTED, "the last one commits")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), length(jobs), "one question per banned job, no more")
	TEST_ASSERT_EQUAL(length(H.commits), 1, "one lift")
	var/list/commit = H.commits[1]
	TEST_ASSERT_EQUAL(commit[1], "lift", "a lift")
	TEST_ASSERT_EQUAL(json_encode(commit[3]), json_encode(want), "of exactly the jobs the admin confirmed")

/datum/unit_test/dq_h4/ban/edit_a_ban

/datum/unit_test/dq_h4/ban/edit_a_ban/run_h4()
	var/mob/living/carbon/human/admin = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/admins/dq_ban_flow_fixture/H = holder()
	set_config(/datum/config_entry/string/chat_webhook_url, "")
	var/savefile/fixture = new
	set_global("banlist", fixture)
	fixture.cd = "/base/dqh4folder"
	fixture["key"] << "dqh4banned"
	fixture["id"] << "dqh4id"
	fixture["reason"] << "old reason"
	fixture["temp"] << 0
	fixture["bannedby"] << "someone"
	fixture.cd = "/base"
	start(admin, H, "unbane", list("unbane" = "dqh4folder"))
	TEST_ASSERT_EQUAL(asked(), "choice", "the edit opens with the temporary question")
	test_answer(admin, "Yes")
	TEST_ASSERT_EQUAL(asked(), "choice,number", "a temporary edit asks how long")
	var/datum/prompt/number/minutes = GLOB.test_prompts[2]
	TEST_ASSERT_EQUAL(minutes.default, 1440, "defaulting to a day for a ban that was permanent")
	test_answer(admin, 120)
	var/datum/prompt/text/why = GLOB.test_prompts[3]
	TEST_ASSERT_EQUAL(why.default, "old reason", "the reason box starts with the old reason")
	var/datum/op_result/done = test_answer(admin, "new reason")
	TEST_ASSERT_EQUAL(done?.outcome, ACT_COMMITTED, "the op commits")
	fixture.cd = "/base/dqh4folder"
	var/reason
	var/temp
	fixture["reason"] >> reason
	fixture["temp"] >> temp
	TEST_ASSERT_EQUAL(reason, "new reason", "the ban has its new reason")
	TEST_ASSERT_EQUAL(temp, 1, "and is temporary")
	TEST_ASSERT_EQUAL(H.panels, 1, "the panel refreshed once")
	// a permanent edit skips the duration
	start(admin, H, "unbane", list("unbane" = "dqh4folder"))
	test_answer(admin, "No")
	TEST_ASSERT_EQUAL(asked(), "choice,text", "a permanent edit asks only why")
	test_answer(admin, "forever")
	fixture.cd = "/base/dqh4folder"
	fixture["reason"] >> reason
	fixture["temp"] >> temp
	TEST_ASSERT_EQUAL(reason, "forever", "the reason changed")
	TEST_ASSERT_EQUAL(temp, 0, "and it is permanent again")
	// lifting a ban: confirm, or not
	fixture.cd = "/base"
	start(admin, H, "unbanf", list("unbanf" = "dqh4folder"))
	test_answer(admin, "No")
	fixture.cd = "/base"
	TEST_ASSERT("dqh4folder" in fixture.dir, "answering No lifts nothing")
