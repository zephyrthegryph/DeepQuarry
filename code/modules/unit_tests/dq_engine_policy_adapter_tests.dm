// Policy adapters preserve the engine-facing contract while transport stays downstream.
/datum/engine_policy_callback_probe
	var/mob/seen_actor
	var/list/seen_args

/datum/engine_policy_callback_probe/proc/capture(first, second)
	seen_actor = input_actor()
	seen_args = list(first, second)
	return "captured"

/datum/unit_test/dq_engine_policy_callback_compatibility/Run()
	var/mob/before = input_actor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human)
	var/datum/engine_policy_callback_probe/probe = allocate(/datum/engine_policy_callback_probe)
	var/datum/callback/callback = allocate(/datum/callback, probe, TYPE_PROC_REF(/datum/engine_policy_callback_probe, capture), "stored")
	TEST_ASSERT_EQUAL(with_actor(actor, callback, "extra"), "captured", "Compatibility callbacks preserve the handler result")
	TEST_ASSERT_EQUAL(probe.seen_actor, actor, "The legacy callback runs with the explicit actor")
	TEST_ASSERT_EQUAL(probe.seen_args[1], "stored", "Stored arguments precede invocation arguments")
	TEST_ASSERT_EQUAL(probe.seen_args[2], "extra", "Invocation arguments are forwarded")
	TEST_ASSERT_EQUAL(input_actor(), before, "Callback completion restores the previous actor")

/datum/request/engine_policy_extra
	var/extra_checks = 0

/datum/request/engine_policy_extra/recheck_extra()
	extra_checks++
	return "extra refusal"

/datum/unit_test/dq_engine_policy_request_context/Run()
	var/datum/request/engine_policy_extra/request = allocate(/datum/request/engine_policy_extra)
	TEST_ASSERT_EQUAL(request.check_context(), "extra refusal", "No generic flags still runs the request-specific check")
	TEST_ASSERT_EQUAL(request.extra_checks, 1, "The extra policy runs once")
	request.ask_flags = ASK_ALIVE
	TEST_ASSERT_EQUAL(request.check_context(), "not a mob", "A mob-only policy rejects a missing answerer")
	TEST_ASSERT_EQUAL(request.extra_checks, 1, "Rejected generic policy does not invoke the extra handler")
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human)
	request.answerer = actor
	TEST_ASSERT_EQUAL(request.check_context(), "extra refusal", "A live answerer passes generic policy and reaches the extra check")
	TEST_ASSERT_EQUAL(request.extra_checks, 2, "The accepted generic path runs the extra policy exactly once")

/datum/engine_policy_clock_probe
	var/rate

/datum/engine_policy_clock_probe/biological_clock_rate()
	return rate

/datum/unit_test/dq_engine_policy_biological_clock/Run()
	var/datum/engine_policy_clock_probe/probe = allocate(/datum/engine_policy_clock_probe)
	var/datum/scheduler_record/record = scheduler_record_of(probe)
	var/datum/clock_definition/clock = definition_registry().clock_by_id[CLOCK_BIO]
	TEST_ASSERT_NOTNULL(clock, "The real biological clock is registered")
	TEST_ASSERT_EQUAL(clock_compute(record, clock.idx), 1, "An absent biological override retains the ordinary rate")
	probe.rate = 0
	TEST_ASSERT_EQUAL(clock_compute(record, clock.idx), 0, "An explicit zero preserves complete stasis")
	probe.rate = 0.5
	TEST_ASSERT_EQUAL(clock_compute(record, clock.idx), 0.5, "A fractional biological rate survives the adapter")
	probe.rate = -1
	TEST_ASSERT_EQUAL(clock_compute(record, clock.idx), clock.min_rate, "The clock still clamps invalid rates to its declared minimum")

/datum/unit_test/dq_engine_policy_insert_transport/Run()
	var/obj/engine_layering_bay/bay = allocate(/obj/engine_layering_bay)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human)
	var/obj/item/cell/first = allocate(/obj/item/cell)
	var/obj/item/cell/second = allocate(/obj/item/cell)
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = bay
	A.target = bay
	A.actor = actor
	A.held = first
	var/datum/entry/part/effect/put_in/effect = put_in(nameof(bay.cell))
	var/precheck = effect.precheck(A)
	TEST_ASSERT_NULL(precheck, "An empty declared bay passes the requirement stage")
	TEST_ASSERT_NULL(bay.cell, "The requirement does not insert the item")
	TEST_ASSERT_EQUAL(effect.run_effect(A), OP_OK, "The guarded transport inserts after requirements pass")
	TEST_ASSERT_EQUAL(bay.cell, first, "The exact cell becomes the owned occupant")
	TEST_ASSERT_EQUAL(first.loc, bay, "The successful transfer moves the cell physically")
	A.held = second
	TEST_ASSERT_EQUAL(effect.precheck(A), /datum/msg/bay/full, "The requirement rejects a full bay")
	var/atom/previous_location = second.loc
	TEST_ASSERT_EQUAL(effect.run_effect(A), OP_REFUSED, "The transport also guards a stale attempt against the now-full bay")
	TEST_ASSERT_EQUAL(A.reason, /datum/msg/bay/full, "The guarded attempt preserves the refusal reason")
	TEST_ASSERT_EQUAL(bay.cell, first, "A refusal preserves the existing occupant")
	TEST_ASSERT_EQUAL(second.loc, previous_location, "A refusal does not move the attempted cell")
	A.release()

/datum/unit_test/dq_engine_policy_binding_ranking/Run()
	var/datum/entry/part/bind/broad = item(/obj/item)
	var/datum/entry/part/bind/quality = tool(TOOL_CROWBAR)
	var/datum/entry/part/bind/narrow = item(/obj/item/tool/crowbar)
	var/datum/entry/part/bind/dragged = item(/mob)
	TEST_ASSERT_EQUAL(op_binding_specificity(broad), 1, "The inventory item root retains its broad rank")
	TEST_ASSERT_EQUAL(op_binding_specificity(quality), 2, "A tool quality ranks above the broad item")
	TEST_ASSERT(op_binding_specificity(narrow) > op_binding_specificity(quality), "An actual narrower inventory type ranks above a tool quality")
	TEST_ASSERT_EQUAL(op_binding_specificity(dragged), 0, "A dragged mob is not ranked as a held inventory item")
	TEST_ASSERT_EQUAL(op_binding_specificity(item(/obj)), 0, "The generic engine object root does not acquire the old inventory-root rank")
	var/datum/op_cand/broad_candidate = allocate(/datum/op_cand)
	var/datum/op_cand/unranked = allocate(/datum/op_cand)
	var/datum/op_cand/tool_candidate = allocate(/datum/op_cand)
	var/datum/op_cand/specific_first = allocate(/datum/op_cand)
	var/datum/op_cand/specific_second = allocate(/datum/op_cand)
	broad_candidate.specificity = op_binding_specificity(broad)
	tool_candidate.specificity = op_binding_specificity(quality)
	specific_first.specificity = op_binding_specificity(narrow)
	specific_second.specificity = op_binding_specificity(narrow)
	var/list/ordered = list(broad_candidate, unranked, tool_candidate, specific_first, specific_second)
	op_specificity_sort(ordered)
	TEST_ASSERT_EQUAL(ordered[1], specific_first, "The first specific binding takes the first ranked position")
	TEST_ASSERT_EQUAL(ordered[2], unranked, "An unranked binding preserves its original position")
	TEST_ASSERT_EQUAL(ordered[3], specific_second, "Equal-specificity bindings retain declaration order")
	TEST_ASSERT_EQUAL(ordered[4], tool_candidate, "The tool quality follows both specific items")
	TEST_ASSERT_EQUAL(ordered[5], broad_candidate, "The broad inventory binding comes last among ranked peers")
	broad_candidate.item_type = /obj/item
	TEST_ASSERT(op_cand_catch_all(broad_candidate), "The real inventory root still defines a catch-all")
	broad_candidate.item_type = /obj/item/tool/crowbar
	TEST_ASSERT(!op_cand_catch_all(broad_candidate), "A narrower inventory binding is not a catch-all")

/datum/unit_test/dq_engine_policy_tool_provider/Run()
	var/obj/item/weldingtool/welder = allocate(/obj/item/weldingtool)
	var/obj/item/multitool/multitool = allocate(/obj/item/multitool)
	var/datum/act/op/A = take(/datum/act/op)
	TEST_ASSERT(isnull(A.held_provider()), "A fresh context exposes no held provider")
	A.set_held_provider(welder)
	TEST_ASSERT_EQUAL(A.held_provider(), welder, "The generic interface preserves the exact inventory provider")
	TEST_ASSERT_EQUAL(A.held.get_welder(), welder, "The unchanged inventory field exposes the real welder")
	TEST_ASSERT_EQUAL(A.held.toolspeed, 1, "Inventory tool speed retains its declared value")
	TEST_ASSERT_EQUAL(A.held.usesound, SFX_ITEMS_WELDER2, "Inventory use sound retains its declared value")
	A.set_held_provider(multitool)
	TEST_ASSERT_EQUAL(A.held.get_multitool(), multitool, "Replacing a provider retains concrete item dispatch")
	qdel(multitool)
	TEST_ASSERT(isnull(A.held_provider()) && isnull(A.held), "Deleting the borrowed provider clears both adapter and inventory field")
	A.set_held_provider(welder)
	A.release()
	var/datum/act/op/reused = take(/datum/act/op)
	TEST_ASSERT(isnull(reused.held_provider()), "A returned context keeps no borrowed provider")
	reused.release()
