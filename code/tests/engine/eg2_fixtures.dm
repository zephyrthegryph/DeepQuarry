// Fixtures of the engine gaps the phase-2 conversions hit (prompt kinds, timed stall hooks, held verbs, mob drags, natural-weapon clicks). Compiled under
// UNIT_TESTS only; code/modules/unit_tests/dq_eg2_gap_tests.dm drives them.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// ---- prompt kinds ----

/// One op per prompt kind, each reached by key through the menu; what the answer was lands in `got`.
/obj/eg2_asker
	name = "eg2 asker"
	/// The last answer an op's handler saw.
	var/got
	/// How many handlers ran.
	var/ran = 0
	var/tint = "#336699"

CAPABILITIES(/obj/eg2_asker, \
	op("pick", menu(), asks(/datum/prompt/choice, fields = list("question" = "Which?", "choices" = list("red", "blue"))), then(PROC_REF(answered))), \
	op("pick_proc", menu(), asks(/datum/prompt/choice, fields = list("choices" = computed(PROC_REF(computed_choices)))), then(PROC_REF(answered))), \
	op("pick_none", menu(), asks(/datum/prompt/choice, fields = list("choices" = list())), then(PROC_REF(answered))), \
	op("tint", menu(), asks(/datum/prompt/color, fields = list("default" = nameof(tint))), then(PROC_REF(answered))), \
	op("boxes", menu(), asks(/datum/prompt/checklist, fields = list("choices" = list("a", "b", "c"), "min_picks" = 1, "max_picks" = 2)), then(PROC_REF(answered))), \
	op("flags", menu(), asks(/datum/prompt/bitfield, fields = list("default" = 5, "editable" = 3)), then(PROC_REF(answered))), \
	op("words", menu(), asks(/datum/prompt/text, fields = list("max_len" = 5)), then(PROC_REF(answered))), \
	op("amount", menu(), asks(/datum/prompt/number, fields = list("min_value" = 1, "max_value" = 10, "step" = 1)), then(PROC_REF(answered))))

/obj/eg2_asker/proc/computed_choices(datum/act/op/A)
	var/static/list/names = list("alpha", "beta")
	return names

/obj/eg2_asker/proc/answered(datum/act/op/A)
	var/datum/prompt/P = A.answer
	got = P.value
	ran++
	return OP_OK

#endif
