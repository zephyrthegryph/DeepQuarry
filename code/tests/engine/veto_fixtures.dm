// Dynamic hooks on an action (observe(source, /datum/act/x, listener, parts...)): the fixtures of dq_veto_tests.dm. Compiled under UNIT_TESTS only.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// An action with a number a listener may change in flight and a flag word listeners OR into.
ACTION(veto_strike, amount, protection, notice = /datum/notice/veto_struck)

/// What a listener observes.
/obj/veto_fixture
	name = "veto fixture"
	anchored = TRUE

/// A listener: its handlers run on it, with A.holder the listener and A.target the observed entity.
/datum/veto_listener
	/// How many times a handler ran, and on whom.
	var/ran = 0
	var/ran_on_me = FALSE
	var/target_was_observed = FALSE
	var/blocking = TRUE
	/// What the handler answers (null: nothing, HOOK_DECLINE: not mine).
	var/answer
	/// The flag this listener ORs into A.protection.
	var/flag = 0

/// A gate: pure, answers whether the veto applies.
/datum/veto_listener/proc/blocks(datum/act/A)
	return blocking

/// An instead handler: runs on the listener, answers `answer`.
/datum/veto_listener/proc/take(datum/act/A)
	ran++
	ran_on_me = (A.holder == src)
	var/datum/act/action/action = A
	target_was_observed = istype(action.target, /obj/veto_fixture)
	return answer

/// An adjusts_with handler: ORs `flag` into the act's protection and adds one to the amount.
/datum/veto_listener/proc/add_flag(datum/act/A)
	var/datum/act/veto_strike/strike = A
	ran++
	ran_on_me = (A.holder == src)
	strike.protection |= flag
	strike.amount += 1

#endif
