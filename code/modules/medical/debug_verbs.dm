// Debug verbs for the medical system.
//
// Registered via the upstream ADMIN_VERB macro; they appear in the admin
// Debug verb panel for clients with R_DEBUG. The macro injects an
// implicit `client/user` arg; we get the verb caller's mob via user.mob.

ADMIN_VERB(dq_spawn_medical_dummy, R_DEBUG, "DQ Spawn Medical Dummy", "Spawn a defenseless test human at your location for medical testing.", ADMIN_CATEGORY_DEBUG)
	var/turf/T = get_turf(user.mob)
	if(!T)
		return
	var/mob/living/carbon/human/dummy = new /mob/living/carbon/human(T)
	dummy.real_name = "Test Patient #[rand(1000, 9999)]"
	dummy.name = dummy.real_name
	to_chat(user.mob, span_notice("Spawned conscious medical patient [dummy] at [T]."))
	log_admin("[key_name(user)] spawned a medical dummy at [T].")


ADMIN_VERB(dq_apply_condition, R_DEBUG, "DQ Apply Medical Condition", "Apply a /datum/affliction subtype to a target's organ.", ADMIN_CATEGORY_DEBUG)
	advance_condition(user)

/datum/admin_verb/dq_apply_condition/proc/advance_condition(client/user, stage = 0, picked_target_key = null, picked_key = null, organ_key = null)
	var/list/candidates = _dq_list_living_humans_in_view(user.mob)
	if(!length(candidates))
		to_chat(user, span_warning("No human targets in view."))
		return
	if(stage <= 0)
		var/mob/answerer = user.mob
		if(QDELETED(answerer))
			return
		open_request(src, /datum/prompt/choice/medical_debug_apply, PROC_REF(condition_choice_made), answerer = answerer, question = "Target patient:", choices = candidates, stage = 0, target_key = picked_target_key, condition_key = picked_key)
		return
	if(!picked_target_key)
		return
	var/mob/living/carbon/human/target = candidates[picked_target_key]
	if(!target)
		return
	var/list/options = list()
	for(var/T in GLOBAL_TABLE_GET(dq_catalogued_affliction_types))
		var/datum/affliction/proto = T
		options["[initial(proto.name)] ([T])"] = T
	if(!length(options))
		to_chat(user.mob, span_warning("No /datum/affliction subtypes defined."))
		return
	if(stage <= 1)
		var/mob/answerer = user.mob
		if(QDELETED(answerer))
			return
		open_request(src, /datum/prompt/choice/medical_debug_apply, PROC_REF(condition_choice_made), answerer = answerer, question = "Which condition?", choices = options, stage = 1, target_key = picked_target_key, condition_key = picked_key)
		return
	if(!picked_key)
		return
	var/condition_type = options[picked_key]
	var/list/organ_options = list()
	for(var/obj/item/organ/O as anything in target.organs)
		organ_options["[O.name] (external)"] = O
	for(var/obj/item/organ/O as anything in target.internal_organ_list())
		organ_options["[O.name] (internal)"] = O
	if(stage <= 2)
		var/mob/answerer = user.mob
		if(QDELETED(answerer))
			return
		open_request(src, /datum/prompt/choice/medical_debug_apply, PROC_REF(condition_choice_made), answerer = answerer, question = "Which organ?", choices = organ_options, stage = 2, target_key = picked_target_key, condition_key = picked_key)
		return
	if(!organ_key)
		return
	var/obj/item/organ/picked_organ = organ_options[organ_key]
	if(!picked_organ)
		return
	if(QDELETED(target) || picked_organ.owner != target)
		return
	if(target.body.find_affliction(condition_type, picked_organ))
		to_chat(user.mob, span_warning("[target] already has [picked_key] on [picked_organ]."))
		return
	var/datum/affliction/C = target.body.afflict(condition_type, picked_organ)
	if(!C)
		to_chat(user.mob, span_warning("[picked_key] can't exist on [target]'s [picked_organ.name] (biology mismatch)."))
		return
	to_chat(user.mob, span_notice("Applied [C.name] to [target]'s [picked_organ.name]."))
	log_admin("[key_name(user)] applied condition [condition_type] to [target] / [picked_organ.name].")

/datum/prompt/choice/medical_debug_apply
	parent_type = /datum/prompt/choice/medical_debug_target
	var/stage
	var/target_key
	var/condition_key

/datum/admin_verb/dq_apply_condition/proc/condition_choice_made(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/medical_debug_apply/ask = A.answer
	var/client/user = ask.answerer?.client
	if(!user)
		return
	switch(ask.stage)
		if(0)
			advance_condition(user, 1, ask.answer_value)
		if(1)
			advance_condition(user, 2, ask.target_key, ask.answer_value)
		if(2)
			advance_condition(user, 3, ask.target_key, ask.condition_key, ask.answer_value)



ADMIN_VERB(dq_clear_conditions, R_DEBUG, "DQ Clear Medical Conditions", "Remove every affliction from a target.", ADMIN_CATEGORY_DEBUG)
	var/list/candidates = _dq_list_living_humans_in_view(user.mob)
	if(!length(candidates))
		to_chat(user, span_warning("No human targets in view."))
		return
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/medical_debug_target, PROC_REF(target_chosen), answerer = answerer, choices = candidates)


ADMIN_VERB(dq_dump_conditions, R_DEBUG, "DQ Inspect Medical Conditions", "Print a target's active conditions and their severity / symptoms.", ADMIN_CATEGORY_DEBUG)
	var/list/candidates = _dq_list_living_humans_in_view(user.mob)
	if(!length(candidates))
		to_chat(user, span_warning("No human targets in view."))
		return
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/medical_debug_target, PROC_REF(target_chosen), answerer = answerer, choices = candidates)


/// Internal helper: collect candidate target humans near a mob.
/proc/_dq_list_living_humans_in_view(mob/observer)
	var/list/L = list()
	if(!observer)
		return L
	for(var/mob/living/carbon/human/H in view(7, observer))
		L["[H.name] ([H.real_name])"] = H
	return L

/// Rebuild the target lookup after an answer, matching the original verb rerun.
/datum/prompt/choice/medical_debug_target
	question = "Target patient:"
	title = "DQ Medical"
	rights = R_DEBUG
	timeout = 0
	recheck_on_open = TRUE

/datum/admin_verb/dq_clear_conditions/proc/target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/client/user = A.request.answerer?.client
	if(!user)
		return
	var/list/candidates = _dq_list_living_humans_in_view(user.mob)
	if(!length(candidates))
		to_chat(user, span_warning("No human targets in view."))
		return
	var/picked_target_key = A.request.answer_value
	if(!picked_target_key)
		return
	var/mob/living/carbon/human/target = candidates[picked_target_key]
	if(!target)
		return
	var/count = LAZYLEN(target.body?.afflictions)
	target.body?.clear_afflictions()
	to_chat(user.mob, span_notice("Cleared [count] condition\s from [target]."))

/datum/admin_verb/dq_dump_conditions/proc/target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/client/user = A.request.answerer?.client
	if(!user)
		return
	var/list/candidates = _dq_list_living_humans_in_view(user.mob)
	if(!length(candidates))
		to_chat(user, span_warning("No human targets in view."))
		return
	var/picked_target_key = A.request.answer_value
	if(!picked_target_key)
		to_chat(user, span_warning("DQ Inspect: cancelled (no target picked)."))
		return
	var/mob/living/carbon/human/target = candidates[picked_target_key]
	if(!target)
		to_chat(user, span_warning("DQ Inspect: target lookup failed."))
		return
	// Output goes to the client (user) rather than user.mob so it
	// shows up even when the admin is aghosted.
	to_chat(user, span_notice("<b>Conditions on [target]:</b>"))
	var/list/conditions = target.get_afflictions()
	if(!length(conditions))
		to_chat(user, span_notice("  (none)"))
	for(var/datum/affliction/C as anything in conditions)
		var/sym_list = ""
		for(var/datum/affliction_symptom/S as anything in affliction_symptoms_of(C))
			sym_list += "[S.name], "
		to_chat(user, span_notice("  <b>[C.name]</b> on [C.location?.name] — severity [round(C.severity, 1)]"))
		if(sym_list)
			to_chat(user, span_notice("    symptoms: [sym_list]"))
	to_chat(user, span_notice("<b>Vitals:</b>"))
	to_chat(user, span_notice("  temperature: [target.get_temperature_reading_c()]°C"))
	to_chat(user, span_notice("  pulse: [target.get_pulse_reading_bpm()] bpm"))
	var/list/bp = target.get_bp_reading()
	to_chat(user, span_notice("  bp: [bp ? "[bp[1]]/[bp[2]] mmHg" : "no reading"]"))
	to_chat(user, span_notice("  o2 sat: [target.get_o2_sat_reading()]%"))
	to_chat(user, span_notice("  respiration: [target.get_respiratory_rate()] /min"))
