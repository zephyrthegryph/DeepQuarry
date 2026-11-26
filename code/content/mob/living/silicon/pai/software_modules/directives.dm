/datum/pai_software/directives
	name = "Directives"
	ram_cost = 0
	id = "directives"
	toggle = 0
	default = 1

CAPABILITIES(/datum/pai_software/directives)
	interface("pAIDirectives", state = nameof(GLOB.tgui_always_state))
	ui_shape(master = nullable(schema_text()), dna = nullable(schema_text()), prime = schema_text(), supplemental = nullable(schema_text()))
	op("getdna", ui_act("getdna"), needs(req(PROC_REF(dna_refusal))), asks(/datum/prompt/yes_no, fields = list("title" = computed(PROC_REF(dna_title)), "question" = computed(PROC_REF(dna_question)), "timeout" = 0), step = "dna", answerer = PROC_REF(dna_asked), when = PROC_REF(dna_has_carrier)), then(PROC_REF(ui_act_getdna)))

/datum/pai_software/directives/ui_data(datum/act/eval/A)
	var/mob/living/silicon/pai/user = A.actor
	var/list/data = list()

	data["master"] = user.master
	data["dna"] = user.master_dna
	data["prime"] = user.pai_law0
	data["supplemental"] = user.pai_laws

	return data

/// The living carrier of the pAI (its card's holder, up to a few containers out), or null when nobody carries it.
/datum/pai_software/directives/proc/dna_carrier(mob/living/silicon/pai/P)
	var/atom/M = P.loc
	var/count = 0
	// Find the carrier
	while(!isliving(M))
		if(!M || !M.loc || count > 6)
			//For a runtime where M ends up in nullspace (similar to bluespace but less colourful)
			return null
		M = M.loc
		count++
	return M

/// The carrier is who is asked for the sample.
/datum/pai_software/directives/proc/dna_asked(datum/act/op/A)
	return dna_carrier(A.actor)

/// There is a carrier to ask.
/datum/pai_software/directives/proc/dna_has_carrier(datum/act/op/A)
	return !!dna_carrier(A.actor)

/// Why there is nobody to ask, or null.
/datum/pai_software/directives/proc/dna_refusal(datum/act/op/A)
	return dna_carrier(A.actor) ? null : msg_reason("You are not being carried by anyone!")

/datum/pai_software/directives/proc/dna_title(datum/act/op/A)
	return "[A.actor] Check DNA"

/datum/pai_software/directives/proc/dna_question(datum/act/op/A)
	return "[A.actor] is requesting a DNA sample from you. Will you allow it to confirm your identity?"

/// A pAI asks its carrier for a DNA sample. The op goes on on no too (the pAI is told).
/datum/pai_software/directives/proc/ui_act_getdna(datum/act/op/A)
	var/mob/living/silicon/pai/P = A.actor
	var/mob/living/M = dna_carrier(P)
	if(A.step_value("dna"))
		var/turf/T = get_turf(P.loc)
		for (var/mob/v in viewers(T))
			v.show_message(span_notice("[M] presses [M.p_their()] thumb against [P]."), 3, span_notice("[P] makes a sharp clicking sound as it extracts DNA material from [M]."), 2)
		var/datum/dna/dna = M.dna
		to_chat(P, span_infoplain(span_red("<h3>[M]'s UE string : [dna.unique_enzymes]</h3>")))
		if(dna.unique_enzymes == P.master_dna)
			to_chat(P, span_infoplain(span_bold("DNA is a match to stored Master DNA.")))
		else
			to_chat(P, span_infoplain(span_bold("DNA does not match stored Master DNA.")))
	else
		to_chat(P, span_infoplain("[M] does not seem like [M.p_theyre()] going to provide a DNA sample willingly."))
	return TRUE
