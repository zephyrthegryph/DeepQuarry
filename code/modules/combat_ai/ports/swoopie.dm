// Swoopie port — restores the swoop_pests / swoop_trash toggles that lived
// on the deleted /datum/ai_holder/simple_mob/retaliate/swoopie subtype.
//
// The settings live on the mob itself now. The change_settings verb toggles
// them; a custom target selector consults them when picking a target.

/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie
	/// Do we go after living pests?
	var/swoop_pests = FALSE
	/// Do we go after trash and junk?
	var/swoop_trash = FALSE

TYPE_TABLE(/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie, get_ai_target_selectors, list( \
		/datum/target_selector/swoopie_filter, \
		/datum/target_selector/closest, \
	))

// Custom target selector — filters visible_hostiles by the swoop toggles, and
// optionally pulls trash items into consideration as targets.
/datum/target_selector/swoopie_filter

/datum/target_selector/swoopie_filter/select(datum/ai_brain/brain, list/candidates)
	if(!length(candidates))
		return null
	var/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/SW = brain.holder
	var/datum/target_selector/closest_selector = dq_get_selector(/datum/target_selector/closest)
	if(!istype(SW))
		return closest_selector.select(brain, candidates)
	var/list/filtered = list()
	for(var/mob/living/M as anything in candidates)
		if(!SW.swoop_pests)
			continue
		filtered += M
	if(SW.swoop_trash)
		for(var/obj/item/trash/T in view(brain.vision_range, SW))
			filtered += T
	if(!length(filtered))
		return null
	return closest_selector.select(brain, filtered)

// Override the change_settings verb to actually flip the toggles now.
/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/verb/change_settings()
	set name = "Change Settings"
	set desc = "Change the swoopie's settings"
	set category = VERB_CAT_IC
	set src in oview(1)
	settings_request_stage(usr)

/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/proc/settings_request_stage(mob/user, setting)
	if(!user || QDELETED(user))
		return
	if(!ai_brain || !IIsAlly(user))
		to_chat(user, span_warning("\The [src] does not respond to your input."))
		return
	if(isnull(setting))
		open_request(src, /datum/prompt/choice/swoopie_settings, PROC_REF(settings_request_answered), answerer = user, question = "Toggle Swoopie Swooping Options", title = "Swoopie Options", choices = list("Swoop Pests", "Swoop Trash"))
		return
	switch(setting)
		if("Swoop Pests")
			swoop_pests = !swoop_pests
			to_chat(user, "You press a button on \the [src], [swoop_pests ? "" : "de"]activating its pest seeking routines!")
		if("Swoop Trash")
			swoop_trash = !swoop_trash
			to_chat(user, "You press a button on \the [src], [swoop_trash ? "" : "de"]activating its trash seeking routines!")
	ai_brain.invalidate_selection()

/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/proc/settings_request_answered(datum/act/request/context)
	if(!context.answer)
		return
	settings_request_stage(context.request.answerer, context.answer.answer_value)
	if(!QDELETED(src))
		SStgui.update_uis(src)

/datum/prompt/choice/swoopie_settings
	timeout = 0
	recheck_on_open = TRUE
