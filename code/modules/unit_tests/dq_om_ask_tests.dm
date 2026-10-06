// Typed prompts (ask.dm), named task arguments (task.dm) and flows (flow.dm).

/datum/om_test_entity/var/datum/om_test_entity/answered_holder
/datum/om_test_entity/var/answered_yes

/datum/om/prompt/confirm/test_offer
	title = "Offer"
	var/datum/om_test_entity/holder
	var/refuse_with

/datum/om/prompt/confirm/test_offer/prepare()
	message = "Take it from [holder]?"
	return TRUE

/datum/om/prompt/confirm/test_offer/valid()
	return refuse_with

/datum/om/prompt/confirm/test_offer/refused(reason)
	var/datum/om_test_entity/E = subject
	if(E)
		LAZYADD(E.log, "refused:[reason]")

/datum/om/prompt/confirm/test_offer/declined()
	var/datum/om_test_entity/E = subject
	if(E)
		LAZYADD(E.log, "declined")

/datum/om_test_entity/proc/offer_taken(datum/om/prompt/confirm/test_offer/ask)
	LAZYADD(log, "taken")
	rel_set(src, nameof(answered_holder), ask.holder)
	answered_yes = ask.yes

/datum/unit_test/om/typed_prompt_answers

/datum/unit_test/om/typed_prompt_answers/run_om(list/made)
	sched.test_prompts = list()
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/user = entity(made)
	var/datum/om_test_entity/holder = entity(made)
	var/datum/om/prompt/confirm/test_offer/P = om_ask_begin(E, user, /datum/om/prompt/confirm/test_offer, /datum/om_test_entity/proc/offer_taken, list("holder" = holder, "subject" = E))
	TEST_ASSERT(istype(P), "om_ask returns the pending typed prompt")
	TEST_ASSERT_EQUAL(P.message, "Take it from [holder]?", "prepare() built the message from the typed state")
	TEST_ASSERT_NULL(P.holder, "a datum in the state is held as a handle while the window is open")
	TEST_ASSERT_NULL(om_prompt_answer(P, "Yes"), "a yes passes and is delivered")
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "taken", "the answer proc ran on the receiver")
	TEST_ASSERT_EQUAL(E.answered_holder, holder, "the answer proc reads the typed state, resolved")
	TEST_ASSERT(E.answered_yes, "ask.yes is TRUE")

	LAZYCLEARLIST(E.log)
	P = om_ask_begin(E, user, /datum/om/prompt/confirm/test_offer, /datum/om_test_entity/proc/offer_taken, list("holder" = holder, "subject" = E))
	TEST_ASSERT_EQUAL(om_prompt_answer(P, "No"), "declined", "a no is declined")
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "declined", "declined() ran; the answer proc did not")

	LAZYCLEARLIST(E.log)
	P = om_ask_begin(E, user, /datum/om/prompt/confirm/test_offer, /datum/om_test_entity/proc/offer_taken, list("holder" = holder, "subject" = E, "refuse_with" = "busy"))
	TEST_ASSERT_EQUAL(om_prompt_answer(P, "Yes"), "busy", "valid() is re-checked when the answer arrives")
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "refused:busy", "refused() ran with the reason; the answer proc did not")

	LAZYCLEARLIST(E.log)
	P = om_ask_begin(E, user, /datum/om/prompt/confirm/test_offer, /datum/om_test_entity/proc/offer_taken, list("holder" = holder, "subject" = E))
	qdel(holder)
	TEST_ASSERT_EQUAL(om_prompt_answer(P, "Yes"), "gone", "an answer after a datum in the state is deleted is dropped")
	TEST_ASSERT(!("taken" in E.log), "the answer proc did not run")

/datum/unit_test/om/typed_prompt_flags

/datum/unit_test/om/typed_prompt_flags/run_om(list/made)
	sched.test_prompts = list()
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/user = entity(made)
	var/datum/om/prompt/confirm/test_offer/P = om_ask_begin(E, user, /datum/om/prompt/confirm/test_offer, /datum/om_test_entity/proc/offer_taken, list("subject" = E, "ask_flags" = ASK_HELD))
	TEST_ASSERT(!isnull(om_prompt_answer(P, "Yes")), "ASK_HELD refuses when the subject is not in the asker's hands")
	TEST_ASSERT(!("taken" in E.log), "the answer proc did not run")

// ---------------------------------------------------------------- named task arguments

/datum/task/test_named
	name = "test_named"
	duration = 10
	complete_proc = /datum/om_test_entity/proc/named_done
	var/amount
	var/datum/om_test_entity/tool

/datum/task/test_named/own
	name = "test_named_own"
	complete_proc = /datum/task/test_named/own/proc/done

/datum/task/test_named/own/proc/done()
	var/datum/om_test_entity/E = actor
	LAZYADD(E.log, "own:[amount]")

/datum/om_test_entity/proc/named_done(datum/task/test_named/task)
	LAZYADD(log, "done:[task.amount]")

/datum/unit_test/om/task_named_args

/datum/unit_test/om/task_named_args/run_om(list/made)
	var/datum/om_test_entity/actor = entity(made)
	var/datum/om_test_entity/target = entity(made)
	var/datum/om_test_entity/tool = entity(made)
	var/datum/task/test_named/T = task_start(/datum/task/test_named, actor, target, amount = 3, tool = tool)
	TEST_ASSERT(istype(T), "a task starts with named arguments")
	TEST_ASSERT_EQUAL(T.amount, 3, "a named argument sets the typed var")
	TEST_ASSERT_EQUAL(T.tool, tool, "a datum argument is set (and held)")
	TEST_ASSERT_EQUAL(T.receiver, target, "the receiver defaults to the first of src, target, actor that has the complete_proc")
	task_cancel(T)

	var/datum/task/test_named/own/O = task_start(/datum/task/test_named/own, actor, null, amount = 5)
	task_complete(O)
	TEST_ASSERT_EQUAL(jointext(actor.log || list(), ","), "own:5", "a complete_proc of the task's own type runs on the task, reading its vars")

// ---------------------------------------------------------------- flows

/datum/om/flow/test_consent
	var/datum/om_test_entity/witness
	var/list/log
	var/refuse_with

/datum/om/flow/test_consent/valid()
	return refuse_with

/datum/om/flow/test_consent/start()
	LAZYADD(log, "start")
	om_ask(target, /datum/om/prompt/confirm, PROC_REF(agreed), message = "ok?")

/datum/om/flow/test_consent/proc/agreed(datum/om/prompt/confirm/ask)
	LAZYADD(log, "agreed:[ask.asker == actor]:[witness ? "witness" : "none"]")

/datum/om/flow/test_consent/ended(reason)
	LAZYADD(log, "ended:[reason]")

/datum/unit_test/om/flow_prompt_steps

/datum/unit_test/om/flow_prompt_steps/run_om(list/made)
	sched.test_prompts = list()
	var/datum/om_test_entity/actor = entity(made)
	var/datum/om_test_entity/other = entity(made)
	var/datum/om_test_entity/witness = entity(made)
	var/datum/om/flow/test_consent/F = om_flow_start(/datum/om/flow/test_consent, actor, other, witness = witness)
	TEST_ASSERT(istype(F), "a flow starts")
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 1, "its first step asked")
	TEST_ASSERT(F.waiting, "it waits on the prompt")
	TEST_ASSERT_NULL(F.witness, "its state is held as handles while it waits")
	var/datum/om/prompt/TP1 = sched.test_prompts[1]
	om_prompt_answer(TP1, "Yes")
	TEST_ASSERT_EQUAL(jointext(F.log || list(), ","), "start,agreed:1:witness", "the next step ran with the typed prompt; asker = actor; state restored")
	TEST_ASSERT(F.done, "a step that goes on to nothing finishes the flow")

	sched.test_prompts = list()
	F = om_flow_start(/datum/om/flow/test_consent, actor, other, witness = witness)
	var/datum/om/prompt/TP2 = sched.test_prompts[1]
	om_prompt_answer(TP2, "No")
	TEST_ASSERT_EQUAL(jointext(F.log || list(), ","), "start,ended:declined", "a no ends the flow through ended()")

	sched.test_prompts = list()
	F = om_flow_start(/datum/om/flow/test_consent, actor, other, witness = witness)
	F.refuse_with = "changed mind"
	var/datum/om/prompt/TP3 = sched.test_prompts[1]
	om_prompt_answer(TP3, "Yes")
	TEST_ASSERT_EQUAL(jointext(F.log || list(), ","), "start,ended:changed mind", "the flow's valid() is re-checked before the next step")

	sched.test_prompts = list()
	F = om_flow_start(/datum/om/flow/test_consent, actor, other, witness = witness)
	qdel(witness)
	var/datum/om/prompt/TP4 = sched.test_prompts[1]
	om_prompt_answer(TP4, "Yes")
	TEST_ASSERT(!F.log?.Find("agreed:1:witness") && F.done, "a datum in the state deleted between steps stops the flow")
