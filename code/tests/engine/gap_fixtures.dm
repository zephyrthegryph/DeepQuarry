// Fixtures of the framework gap closures (OP_DECLINE, ...). Compiled under UNIT_TESTS only; code/modules/unit_tests/dq_gap_tests.dm drives them.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// An op that may decline at run time, with a second op on the same input beneath it.
/obj/gap_decline
	name = "gap decline target"
	var/declines = TRUE
	var/first = 0
	var/second = 0

CAPABILITIES(/obj/gap_decline)
	op("first", item(/obj/item), priority(OP_PRIORITY_TAKE_OUT), then(PROC_REF(ran_first)))
	op("second", item(/obj/item), then(PROC_REF(ran_second)))

/obj/gap_decline/proc/ran_first(datum/act/op/A)
	if(declines)
		return OP_DECLINE
	first++
	return OP_OK

/obj/gap_decline/proc/ran_second(datum/act/op/A)
	second++
	return OP_OK

/// The only op declines: nothing else answers.
/obj/gap_decline_alone
	name = "gap decline alone target"
	var/first = 0

CAPABILITIES(/obj/gap_decline_alone)
	op("first", item(/obj/item), then(PROC_REF(ran_first)))

/obj/gap_decline_alone/proc/ran_first(datum/act/op/A)
	first++
	return OP_DECLINE

/// A type-level every() held by a tracked var: it parks while the var is false and wakes when it is set.
/obj/gap_every
	name = "gap every target"
	var/active = FALSE
	var/ticks = 0

TRACKED(/obj/gap_every, active)

CAPABILITIES(/obj/gap_every)
	every(1 SECOND, then(PROC_REF(tick)), when = nameof(active))

/obj/gap_every/proc/tick(datum/act/timer/A)
	ticks++

/// The same, running from creation.
/obj/gap_every/running
	active = TRUE

/// A gate that is a proc (its reads may be incomplete): the every() keeps polling instead of parking.
/obj/gap_every_proc
	name = "gap every proc target"
	var/on = FALSE
	var/ticks = 0

TRACKED(/obj/gap_every_proc, on)

CAPABILITIES(/obj/gap_every_proc)
	every(1 SECOND, then(PROC_REF(tick)), when = PROC_REF(is_on))

/obj/gap_every_proc/proc/is_on(datum/act/A)
	return on

/obj/gap_every_proc/proc/tick(datum/act/timer/A)
	ticks++

/// A mob with every verb_entry form: always, login, a condition, a hide of a verb its type declares, and verbs for runtime grants.
/mob/gap_verb_mob
	name = "gap verb mob"
	var/flag = FALSE

TRACKED(/mob/gap_verb_mob, flag)

CAPABILITIES(/mob/gap_verb_mob)
	verb_entry(/mob/gap_verb_mob/proc/gv_always)
	verb_entry(/mob/gap_verb_mob/proc/gv_login, login = TRUE)
	verb_entry(/mob/gap_verb_mob/proc/gv_when, when = nameof(flag))
	verb_entry(/mob/gap_verb_mob/verb/gv_inherited, hidden = TRUE)

/mob/gap_verb_mob/proc/gv_always()
	set name = "Gap Always"
	set category = VERB_CAT_ABILITIES

/mob/gap_verb_mob/proc/gv_login()
	set name = "Gap Login"
	set category = VERB_CAT_ABILITIES

/mob/gap_verb_mob/proc/gv_when()
	set name = "Gap When"
	set category = VERB_CAT_ABILITIES

/mob/gap_verb_mob/verb/gv_inherited()
	set name = "Gap Inherited"
	set category = VERB_CAT_ABILITIES

/mob/gap_verb_mob/proc/gv_runtime()
	set name = "Gap Runtime"
	set category = VERB_CAT_ABILITIES

/// A capability that carries a verb entry: the verb is there while the capability is granted.
CAPABILITY_DEF(gap_verb_cap, CAP_GAP_VERB_CAP, key = NONE)

/datum/capability/def/gap_verb_cap/entries()
	return list(verb_entry(/mob/gap_verb_mob/proc/gv_runtime))

/// Windows that carry a tgui state: a state global by name, an admin rights mask, and none.
/obj/gap_window_base
	name = "gap window base"

/obj/gap_window_base/proc/noop(datum/act/op/A)
	return

/obj/gap_window_base/state
	name = "gap window state"

CAPABILITIES(/obj/gap_window_base/state)
	interface("GapWindow", state = nameof(GLOB.tgui_always_state))
	op("noop", ui_act("noop"), then(PROC_REF(noop)))

/obj/gap_window_base/rights
	name = "gap window rights"

CAPABILITIES(/obj/gap_window_base/rights)
	interface("GapWindow", rights = R_ADMIN | R_EVENT)
	op("noop", ui_act("noop"), then(PROC_REF(noop)))

/obj/gap_window_base/plain
	name = "gap window plain"

CAPABILITIES(/obj/gap_window_base/plain)
	interface("GapWindow")
	op("noop", ui_act("noop"), then(PROC_REF(noop)))

/// The input kinds of the old compact interactions as op bindings: a drag, an alt-click, telekinesis, a use in hand, a stance, a pass-through.
/obj/gap_inputs
	name = "gap inputs target"
	var/list/ran = list()
	var/powered = TRUE
	var/dragged_what

CAPABILITIES(/obj/gap_inputs)
	op("drag", item(/mob/living), gesture(GESTURE_DRAG), label("Put inside"), then(PROC_REF(dragged_in)))
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), label("Flip"), then(PROC_REF(alt_flipped)))
	op("tk", tk(), label("Nudge"), then(PROC_REF(tk_nudged)))
	op("pet", hand(), stance(I_HELP), label("Pet"), then(PROC_REF(petted)))
	op("bite", hand(), stance(I_HURT), label("Bite"), then(PROC_REF(bitten)))

/obj/gap_inputs/proc/dragged_in(datum/act/op/A)
	var/mob/living/who = A.held
	if(!powered)
		return OP_DECLINE
	dragged_what = who
	ran += "drag"
	return OP_OK

/obj/gap_inputs/proc/alt_flipped(datum/act/op/A)
	ran += "alt"
	return OP_OK

/obj/gap_inputs/proc/tk_nudged(datum/act/op/A)
	ran += "tk"
	return OP_OK

/obj/gap_inputs/proc/petted(datum/act/op/A)
	ran += "pet"
	return OP_OK

/obj/gap_inputs/proc/bitten(datum/act/op/A)
	ran += "bite"
	return OP_OK

/// A hand op and no tk() op: out of reach a telekinetic actor does it through its provider.
/obj/gap_touch
	name = "gap touch target"
	var/list/ran = list()

CAPABILITIES(/obj/gap_touch)
	op("touch", hand(), label("Touch"), then(PROC_REF(touched)))

/obj/gap_touch/proc/touched(datum/act/op/A)
	ran += "touch"
	return OP_OK

/// An op that answers OP_PASS beneath another that takes the input: the pass hands the click on, the next op runs, and a result that does not pass stops there.
/obj/gap_pass
	name = "gap pass target"
	var/passes_it = TRUE
	var/first = 0
	var/second = 0

CAPABILITIES(/obj/gap_pass)
	op("first", item(/obj/item), priority(OP_PRIORITY_TAKE_OUT), then(PROC_REF(ran_first)))
	op("second", item(/obj/item), then(PROC_REF(ran_second)))

/obj/gap_pass/proc/ran_first(datum/act/op/A)
	first++
	return passes_it ? OP_PASS : OP_OK

/obj/gap_pass/proc/ran_second(datum/act/op/A)
	second++
	return OP_OK

#endif
