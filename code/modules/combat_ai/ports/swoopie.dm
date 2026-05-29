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

/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/get_ai_target_selectors()
	var/static/list/L = list(
		/datum/target_selector/swoopie_filter,
		/datum/target_selector/closest,
	)
	return L

// Custom target selector — filters visible_hostiles by the swoop toggles, and
// optionally pulls trash items into consideration as targets.
/datum/target_selector/swoopie_filter

/datum/target_selector/swoopie_filter/select(datum/ai_brain/brain, list/candidates)
	if(!length(candidates))
		return null
	var/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/SW = brain.holder
	if(!istype(SW))
		return dq_get_selector(/datum/target_selector/closest).select(brain, candidates)
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
	return dq_get_selector(/datum/target_selector/closest).select(brain, filtered)

// Override the change_settings verb to actually flip the toggles now.
/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie/verb/change_settings()
	set name = "Change Settings"
	set desc = "Change the swoopie's settings"
	set category = "IC"
	set src in oview(1)
	if(!ai_brain || !IIsAlly(usr))
		to_chat(usr, span_warning("\The [src] does not respond to your input."))
		return
	var/setting = tgui_input_list(usr, "Toggle Swoopie Swooping Options", "Swoopie Options", list("Swoop Pests", "Swoop Trash"))
	switch(setting)
		if("Swoop Pests")
			swoop_pests = !swoop_pests
			to_chat(usr, "You press a button on \the [src], [swoop_pests ? "" : "de"]activating its pest seeking routines!")
		if("Swoop Trash")
			swoop_trash = !swoop_trash
			to_chat(usr, "You press a button on \the [src], [swoop_trash ? "" : "de"]activating its trash seeking routines!")
	ai_brain.invalidate_selection()
