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

/// A plain datum with type-level every(): one runs always, one while a tracked var is set (J1: armed when the datum is made, ends with it).
/datum/gap_every_datum
	var/ticks = 0
	var/gated_ticks = 0
	var/active = FALSE

TRACKED(/datum/gap_every_datum, active)

CAPABILITIES(/datum/gap_every_datum)
	every(1 SECOND, then(PROC_REF(tick)))
	every(1 SECOND, then(PROC_REF(gated_tick)), when = nameof(active))

/datum/gap_every_datum/proc/tick(datum/act/timer/A)
	ticks++

/datum/gap_every_datum/proc/gated_tick(datum/act/timer/A)
	gated_ticks++

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
	var/list/ran
	var/powered = TRUE
	var/dragged_what

CAPABILITIES(/obj/gap_inputs)
	op("drag", item(/mob/living), gesture(GESTURE_DRAG), label("Put inside"), then(PROC_REF(dragged_in)))
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), label("Flip"), then(PROC_REF(alt_flipped)))
	op("tk", tk(), label("Nudge"), then(PROC_REF(tk_nudged)))
	op("pet", hand(), stance(I_HELP), label("Pet"), then(PROC_REF(petted)))
	op("bite", hand(), stance(I_HURT), label("Bite"), then(PROC_REF(bitten)))

/// What ran, in order, as text; forget_ran() clears it.
/obj/gap_inputs/proc/ran_text()
	return jointext(ran, ",")

/obj/gap_inputs/proc/forget_ran()
	ran = null

/obj/gap_inputs/proc/dragged_in(datum/act/op/A)
	var/mob/living/who = A.held
	if(!powered)
		return OP_DECLINE
	dragged_what = who
	LAZYADD(ran, "drag")
	return OP_OK

/obj/gap_inputs/proc/alt_flipped(datum/act/op/A)
	LAZYADD(ran, "alt")
	return OP_OK

/obj/gap_inputs/proc/tk_nudged(datum/act/op/A)
	LAZYADD(ran, "tk")
	return OP_OK

/obj/gap_inputs/proc/petted(datum/act/op/A)
	LAZYADD(ran, "pet")
	return OP_OK

/obj/gap_inputs/proc/bitten(datum/act/op/A)
	LAZYADD(ran, "bite")
	return OP_OK

/// A hand op and no tk() op: out of reach a telekinetic actor does it through its provider.
/obj/gap_touch
	name = "gap touch target"
	var/list/ran

CAPABILITIES(/obj/gap_touch)
	op("touch", hand(), label("Touch"), then(PROC_REF(touched)))

/obj/gap_touch/proc/ran_text()
	return jointext(ran, ",")

/obj/gap_touch/proc/touched(datum/act/op/A)
	LAZYADD(ran, "touch")
	return OP_OK

/// A ghost's op beside a hand op: observer() needs AFF_OBSERVE, which only the observer mob provides.
/obj/gap_observe
	name = "gap observe target"
	var/list/ran

CAPABILITIES(/obj/gap_observe)
	op("haunt", observer(), label("Haunt"), then(PROC_REF(haunted)))
	op("touch", hand(), label("Touch"), then(PROC_REF(touched)))

/obj/gap_observe/proc/ran_text()
	return jointext(ran, ",")

/obj/gap_observe/proc/haunted(datum/act/op/A)
	LAZYADD(ran, "haunt")
	return OP_OK

/obj/gap_observe/proc/touched(datum/act/op/A)
	LAZYADD(ran, "touch")
	return OP_OK

/// An op only a hulk is offered (req_mutation() in a when()), ahead of the plain touch.
/obj/gap_hulk
	name = "gap hulk target"
	var/list/ran

CAPABILITIES(/obj/gap_hulk)
	op("smash", hand(), label("Smash"), priority(OP_PRIORITY_NORMAL + 1), when(req_mutation(HULK)), then(PROC_REF(smashed)))
	op("touch", hand(), label("Touch"), then(PROC_REF(touched)))

/obj/gap_hulk/proc/ran_text()
	return jointext(ran, ",")

/obj/gap_hulk/proc/smashed(datum/act/op/A)
	LAZYADD(ran, "smash")
	return OP_OK

/obj/gap_hulk/proc/touched(datum/act/op/A)
	LAZYADD(ran, "touch")
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

/// A window with a named button, a fallback for the actions its list names, and two modals (a text question and a labelled yes/no).
/obj/gap_window
	name = "gap window"
	var/static/list/valid_actions = list("alpha", "beta")
	var/list/log

CAPABILITIES(/obj/gap_window)
	interface("GapPanel")
	op("named", ui_act("named"), then(PROC_REF(named_pressed)))
	op("program", ui_act("*"), needs(req(PROC_REF(known_action), silent = TRUE)), then(PROC_REF(program_pressed)))
	op("note", ui_act("modal:note", arg("arguments")), asks(/datum/prompt/text, fields = list("question" = "Note?", "default" = "none", "inline" = TRUE), step = "note"), then(PROC_REF(note_entered)))
	op("style", ui_act("modal:style"), asks(/datum/prompt/choice, fields = list("question" = "Style?", "choices" = list("a", "b", "c"), "bento" = "spritesheet", "inline" = TRUE), step = "style"), then(PROC_REF(styled)))
	op("confirm", ui_act("modal:confirm"), asks(/datum/prompt/yes_no, fields = list("question" = "Sure?", "yes_text" = "Do it", "no_text" = "Leave it", "inline" = TRUE), step = "sure"), then(PROC_REF(confirmed)))

/obj/gap_window/proc/styled(datum/act/op/A)
	LAZYADD(log, "style:[A.answer.value]")
	return OP_OK

/obj/gap_window/proc/log_text()
	return jointext(log, ",")

/obj/gap_window/proc/known_action(datum/act/op/A)
	return (A.window_action() in valid_actions)

/obj/gap_window/proc/named_pressed(datum/act/op/A)
	LAZYADD(log, "named")
	return OP_OK

/obj/gap_window/proc/program_pressed(datum/act/op/A)
	LAZYADD(log, "program:[A.window_action()]")
	return OP_OK

/obj/gap_window/proc/note_entered(datum/act/op/A, arguments)
	LAZYADD(log, "note:[A.answer.value]")
	return OP_OK

/obj/gap_window/proc/confirmed(datum/act/op/A)
	LAZYADD(log, "confirmed:[A.answer.value]")
	return OP_OK

/// A subtype that overrides what the button does: then(PROC_REF(named_pressed)) is looked up on the holder, so the override is the handler.
/obj/gap_window/locked
	name = "gap window locked"

/obj/gap_window/locked/named_pressed(datum/act/op/A)
	LAZYADD(log, "locked")
	return OP_OK

/// A console whose window is the window of the unit it points at: every button is the unit's.
/obj/gap_console
	name = "gap console"
	var/obj/gap_window/unit

CAPABILITIES(/obj/gap_console)
	interface("GapPanel", forwards = nameof(unit))
	ui_shape(unit_name = schema_text())
	ref_one(nameof(unit), /obj/gap_window)

/// A yes/no with its own labels.
/datum/prompt/yes_no/gap_labelled
	yes_text = "Launch"
	no_text = "Cancel"

/// What a converted re-run handler looks like: its questions are steps of the op, with literal, var and computed fields.
/obj/gap_asker
	name = "gap asker"
	var/ask_default = "Bae"
	var/static/list/colours = list("red", "blue")
	var/list/log

CAPABILITIES(/obj/gap_asker)
	op("pick", in_hand(), asks(/datum/prompt/choice, fields = list("question" = "Colour?", "choices" = computed(PROC_REF(colour_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(picked)))
	op("name", menu(), asks(/datum/prompt/text, fields = list("question" = "Name?", "default" = nameof(ask_default), "title" = computed(PROC_REF(name_title)), "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "timeout" = 0), step = "k"), then(PROC_REF(named)))

/obj/gap_asker/proc/log_text()
	return jointext(log, ",")

/obj/gap_asker/proc/colour_choices(datum/act/op/A)
	return colours

/obj/gap_asker/proc/name_title(datum/act/op/A)
	return "Name [src]"

/obj/gap_asker/proc/picked(datum/act/op/A)
	var/colour = A.step_value("a1")
	LAZYADD(log, "picked:[colour]")
	return OP_OK

/obj/gap_asker/proc/named(datum/act/op/A)
	LAZYADD(log, "named:[A.step_value("k")]")
	return OP_OK

// ---- req_actor_kind(), interface(observe =), the hand-over and conditional owns_one() policies ----

/// Menu ops gated on who is acting: one only for a human, one for anything but a human.
/obj/gap_actor_kind
	name = "gap actor kind target"
	var/list/ran

CAPABILITIES(/obj/gap_actor_kind)
	op("humans_only", menu(), label("Humans"), needs(req_actor_kind(/mob/living/carbon/human)), then(PROC_REF(ran_it)))
	op("not_humans", menu(), label("Not humans"), needs(req_actor_kind(list(/mob/living/carbon/human), not = TRUE, because = /datum/msg/op/not_available)), then(PROC_REF(ran_it)))

/obj/gap_actor_kind/proc/ran_it(datum/act/op/A)
	LAZYADD(ran, A.key)
	return OP_OK

/obj/gap_actor_kind/proc/ran_text()
	return jointext(ran, ",")

/// A window with the ghost's read-only view, and a requirement shared by it.
/obj/gap_observed_window
	name = "gap observed window"
	var/blocked = FALSE

CAPABILITIES(/obj/gap_observed_window)
	interface("ChemDispenser", observe = TRUE)
	extend("ui_observe", needs(req_is(nameof(blocked), FALSE, because = /datum/msg/op/not_available)))

/obj/gap_observed_window/ui_data(datum/act/eval/A)
	return list("saw_observer" = A.observer)

/// Hands its part to a successor while it has one; the extra part is spilled only while the flag is set.
/obj/gap_handover_holder
	name = "gap handover holder"
	var/obj/item/pen/part
	var/obj/item/pen/kept
	var/obj/gap_handover_successor/heir
	var/tmp/going_out = FALSE

CAPABILITIES(/obj/gap_handover_holder)
	owns_one(nameof(part), /obj/item/pen, on_destroy = ON_DESTROY_HAND_OVER, successor = nameof(heir), successor_var = nameof(heir.salvage))
	owns_one(nameof(kept), /obj/item/pen, on_destroy = ON_DESTROY_SPILL, only_if = nameof(going_out))

/obj/gap_handover_successor
	name = "gap handover successor"
	var/list/salvage

#endif
