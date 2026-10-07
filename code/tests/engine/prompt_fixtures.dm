// Fixtures of the interruption policy of an open prompt (final_api.html section 9, "Interruption and flows"). Compiled under UNIT_TESTS only;
// code/modules/unit_tests/dq_prompt_interrupt_tests.dm drives them.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

MSG_DEF_SELF(prompt/unpowered, "It has no power.")

/// A machine that asks for a number while it needs power: "set" is the default policy, "set_keeps" opts the prompt out of the actor-side keeps,
/// "chain" asks twice in one op and keeps both answers.
/obj/e0_fixture/prompt_base
	name = "prompt box"
	var/powered = TRUE
	var/value = 0
	var/second = 0
	var/runs = 0

TRACKED(/obj/e0_fixture/prompt_base, powered)

/obj/e0_fixture/prompt_base/box
CAPABILITIES(/obj/e0_fixture/prompt_base/box)
	op("set", hand(), needs(req_is(nameof(powered), because = MSG(prompt/unpowered))), asks(/datum/prompt/number, fields = list("question" = "How much?", "timeout" = 0), step = "amount"), then(PROC_REF(apply)))
	op("pen_set", item(/obj/item/pen), needs(req_is(nameof(powered), because = MSG(prompt/unpowered))), asks(/datum/prompt/number, fields = list("question" = "How much?", "timeout" = 0), step = "amount"), then(PROC_REF(apply)))

/// keeps = 0: the prompt outlives the actor walking away.
/obj/e0_fixture/prompt_base/keeps
	name = "prompt box"
CAPABILITIES(/obj/e0_fixture/prompt_base/keeps)
	op("set_keeps", hand(), needs(req_is(nameof(powered), because = MSG(prompt/unpowered))), asks(/datum/prompt/number, fields = list("question" = "How much?", "timeout" = 0), step = "amount", keeps = 0), then(PROC_REF(apply)))

/// Two prompts in one op.
/obj/e0_fixture/prompt_base/chain
	name = "prompt box"
CAPABILITIES(/obj/e0_fixture/prompt_base/chain)
	op("chain", hand(), needs(req_is(nameof(powered), because = MSG(prompt/unpowered))), asks(/datum/prompt/number, fields = list("question" = "First?", "timeout" = 0), step = "first"), asks(/datum/prompt/number, fields = list("question" = "Second?", "timeout" = 0), step = "second"), then(PROC_REF(apply_chain)))

/// Timed work on the hands: "work" holds the actor's hands and body while it waits (it says claims(CLAIM_HANDS | CLAIM_BODY): an op that declares no claims() holds nothing), "hold_target"
/// declares claims(CLAIM_TARGET) only, so it holds the thing and leaves the actor free.
/obj/e0_fixture/prompt_base/lever
	name = "work lever"
CAPABILITIES(/obj/e0_fixture/prompt_base/lever)
	op("work", hand(), wait(2 SECONDS), claims(CLAIM_HANDS | CLAIM_BODY), then(PROC_REF(apply_work)))

/obj/e0_fixture/prompt_base/holder
	name = "held lever"
CAPABILITIES(/obj/e0_fixture/prompt_base/holder)
	op("hold_target", hand(), wait(2 SECONDS), claims(CLAIM_TARGET), then(PROC_REF(apply_work)))

/// A work op that then asks: the question is not exclusive, the work before it is.
/obj/e0_fixture/prompt_base/work_then_ask
	name = "work then ask"
CAPABILITIES(/obj/e0_fixture/prompt_base/work_then_ask)
	op("work_ask", hand(), wait(2 SECONDS), claims(CLAIM_HANDS | CLAIM_BODY), asks(/datum/prompt/number, fields = list("question" = "How much?", "timeout" = 0), step = "amount"), then(PROC_REF(apply)))

/obj/e0_fixture/prompt_base/proc/apply_work(datum/act/op/A)
	runs++
	return OP_OK

/obj/e0_fixture/prompt_base/proc/apply(datum/act/op/A)
	runs++
	value = A.step_value("amount")
	return OP_OK

/obj/e0_fixture/prompt_base/proc/apply_chain(datum/act/op/A)
	runs++
	value = A.step_value("first")
	second = A.step_value("second")
	return OP_OK

#endif
