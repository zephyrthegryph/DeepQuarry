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
	// Knock it out so it doesn't wander. Patient is alive but
	// unconscious — clean substrate for damage / condition application
	// without AI noise.
	dummy.Sleeping(60 SECONDS)
	to_chat(user.mob, span_notice("Spawned [dummy] at [T]. Sleeping for 60s."))
	log_admin("[key_name(user)] spawned a medical dummy at [T].")


ADMIN_VERB(dq_apply_condition, R_DEBUG, "DQ Apply Medical Condition", "Apply a /datum/medical_issue/condition subtype to a target's organ.", ADMIN_CATEGORY_DEBUG)
	var/list/candidates = _dq_list_living_humans_in_view(user.mob)
	if(!length(candidates))
		to_chat(user, span_warning("No human targets in view."))
		return
	var/picked_target_key = tgui_input_list(user.mob, "Target patient:", "DQ Medical", candidates)
	if(!picked_target_key)
		return
	var/mob/living/carbon/human/target = candidates[picked_target_key]
	if(!target)
		return
	var/list/options = list()
	for(var/T in subtypesof(/datum/medical_issue/condition))
		var/datum/medical_issue/condition/proto = T
		options["[initial(proto.name)] ([T])"] = T
	if(!length(options))
		to_chat(user.mob, span_warning("No /datum/medical_issue/condition subtypes defined."))
		return
	var/picked_key = tgui_input_list(user.mob, "Which condition?", "DQ Medical", options)
	if(!picked_key)
		return
	var/condition_type = options[picked_key]
	var/list/organ_options = list()
	for(var/obj/item/organ/O as anything in target.organs)
		organ_options["[O.name] (external)"] = O
	for(var/obj/item/organ/O as anything in target.internal_organs)
		organ_options["[O.name] (internal)"] = O
	var/organ_key = tgui_input_list(user.mob, "Which organ?", "DQ Medical", organ_options)
	if(!organ_key)
		return
	var/obj/item/organ/picked_organ = organ_options[organ_key]
	if(!picked_organ)
		return
	for(var/datum/medical_issue/condition/existing in picked_organ.medical_issues)
		if(existing.type == condition_type)
			to_chat(user.mob, span_warning("[target] already has [picked_key] on [picked_organ]."))
			return
	var/datum/medical_issue/condition/C = new condition_type()
	C.owner = target
	C.affectedorgan = picked_organ
	LAZYADD(picked_organ.medical_issues, C)
	to_chat(user.mob, span_notice("Applied [initial(C.name)] to [target]'s [picked_organ.name]."))
	log_admin("[key_name(user)] applied condition [condition_type] to [target] / [picked_organ.name].")


ADMIN_VERB(dq_clear_conditions, R_DEBUG, "DQ Clear Medical Conditions", "Remove every cascading-condition medical issue from a target.", ADMIN_CATEGORY_DEBUG)
	var/list/candidates = _dq_list_living_humans_in_view(user.mob)
	if(!length(candidates))
		to_chat(user, span_warning("No human targets in view."))
		return
	var/picked_target_key = tgui_input_list(user.mob, "Target patient:", "DQ Medical", candidates)
	if(!picked_target_key)
		return
	var/mob/living/carbon/human/target = candidates[picked_target_key]
	if(!target)
		return
	var/count = 0
	for(var/datum/medical_issue/condition/C in target.get_all_conditions())
		C.cure_issue()
		count++
	to_chat(user.mob, span_notice("Cleared [count] condition\s from [target]."))


ADMIN_VERB(dq_dump_conditions, R_DEBUG, "DQ Inspect Medical Conditions", "Print a target's active conditions and their severity / symptoms.", ADMIN_CATEGORY_DEBUG)
	var/list/candidates = _dq_list_living_humans_in_view(user.mob)
	if(!length(candidates))
		to_chat(user, span_warning("No human targets in view."))
		return
	var/picked_target_key = tgui_input_list(user.mob, "Target patient:", "DQ Medical", candidates)
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
	var/list/conditions = target.get_all_conditions()
	if(!length(conditions))
		to_chat(user, span_notice("  (none)"))
	for(var/datum/medical_issue/condition/C as anything in conditions)
		var/sym_list = ""
		for(var/datum/medical_symptom/S as anything in C.active_symptoms)
			sym_list += "[S.name], "
		to_chat(user, span_notice("  <b>[C.name]</b> on [C.affectedorgan?.name] — severity [round(C.severity, 1)]"))
		if(sym_list)
			to_chat(user, span_notice("    symptoms: [sym_list]"))
	to_chat(user, span_notice("<b>Vitals:</b>"))
	to_chat(user, span_notice("  temperature: [target.get_temperature_reading_c()]°C"))
	to_chat(user, span_notice("  pulse: [target.get_pulse_reading_bpm()] bpm"))
	var/list/bp = target.get_bp_reading()
	to_chat(user, span_notice("  bp: [bp ? "[bp[1]]/[bp[2]] mmHg" : "no reading"]"))
	to_chat(user, span_notice("  o2 sat: [target.get_o2_sat_reading()]%"))
	to_chat(user, span_notice("  respiration: [target.get_respiratory_rate()] /min"))


/// Internal helper: collect candidate target humans near a mob.
/proc/_dq_list_living_humans_in_view(mob/observer)
	var/list/L = list()
	if(!observer)
		return L
	for(var/mob/living/carbon/human/H in view(7, observer))
		L["[H.name] ([H.real_name])"] = H
	return L
