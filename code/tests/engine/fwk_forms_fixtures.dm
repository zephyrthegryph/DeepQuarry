// Fixtures of the framework forms of the K19-K25 gaps (doc/rewrite/framework_gaps.md): wait(repeats =, after_step =), wait_until(), perform_op(with =)
// and takes(), asks(keeps_answer =), MSG_BALLOON, costs(locked =). Compiled under UNIT_TESTS only; code/modules/unit_tests/dq_fwk_forms_tests.dm drives them.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

MSG_BALLOON(fwk/too_quick, "Too quick.")

/// A human that records the balloon and the chat line a refusal produced.
/mob/living/carbon/human/fwk_tester
	var/balloon_text
	var/chat_refusals = 0

/mob/living/carbon/human/fwk_tester/op_balloon(text)
	balloon_text = text

/mob/living/carbon/human/fwk_tester/op_notify(text)
	chat_refusals++
	return ..()

/obj/fwk_site
	name = "fwk site"
	var/stock = 3
	var/bags = 0
	var/done = 0
	var/broke = 0
	var/broke_laps = -1
	var/laps_seen = -1
	var/gate = FALSE
	var/charge = 10
	var/hook_dest
	var/hook_bogus = "unset"
	var/list/candidates
	var/picked

TRACKED(/obj/fwk_site, gate)
TRACKED(/obj/fwk_site, bags)
TRACKED(/obj/fwk_site, stock)

CAPABILITIES(/obj/fwk_site)
	op("fill", menu(), wait(2 SECONDS, repeats = PROC_REF(more_stock), after_step = PROC_REF(add_bag)), then(PROC_REF(finished)), on_interrupt(PROC_REF(broken)))
	op("hold", menu(), wait_until(), then(PROC_REF(finished)), on_interrupt(PROC_REF(broken)))
	op("hold_gate", menu(), wait_until(until = nameof(gate)), then(PROC_REF(finished)))
	op("hook", ai(), reach(REACH_ANY), takes("dest", "time"), wait(PROC_REF(hook_time)), then(PROC_REF(hook_done)))
	op("pick", menu(), asks(/datum/prompt/choice, fields = list("question" = "Who?", "choices" = nameof(candidates), "timeout" = 0), step = "who", keeps_answer = TRUE), wait(3 SECONDS), then(PROC_REF(picked_done)))
	op("quick", menu(), needs(req(PROC_REF(never_ok), because = MSG(fwk/too_quick))), then(PROC_REF(finished)))
	op("drain", ui_act("drain"), costs(RES_DARK_ENERGY, PROC_REF(drain_amount), locked = TRUE), wait(2 SECONDS), then(PROC_REF(finished)))
	op("drain_live", ui_act("drain_live"), costs(RES_DARK_ENERGY, PROC_REF(drain_amount)), wait(2 SECONDS), then(PROC_REF(finished)))

/obj/fwk_site/proc/more_stock(datum/act/op/A)
	return bags < stock

/obj/fwk_site/proc/add_bag(datum/act/op/A)
	set_bags(bags + 1)
	return OP_OK

/obj/fwk_site/proc/finished(datum/act/op/A)
	done++
	laps_seen = A.laps()
	return OP_OK

/obj/fwk_site/proc/broken(datum/act/op/A)
	broke++
	broke_laps = A.laps()

/obj/fwk_site/proc/never_ok(datum/act/op/A)
	return FALSE

/obj/fwk_site/proc/hook_time(datum/act/op/A)
	return A.arg("time") || 1 SECOND

/obj/fwk_site/proc/hook_done(datum/act/op/A)
	done++
	hook_dest = A.arg("dest")
	hook_bogus = A.arg("bogus")
	return OP_OK

/obj/fwk_site/proc/picked_done(datum/act/op/A)
	done++
	picked = A.answer_target()
	return OP_OK

/obj/fwk_site/proc/drain_amount(datum/act/op/A)
	return charge

#endif
