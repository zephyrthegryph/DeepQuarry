// DQAdd — Apply organ_data + rlimb_data prefs to the character. Walks every defined external
// and internal organ, converts to cyborg / amputated / FBP variants per the saved state.
// Pulled verbatim from /datum/category_item/player_setup_item/general/body/copy_to_mob().
//
// Lives in a hook because it iterates the character mob's organ structure, which the
// per-pref apply for organ_data alone cannot meaningfully do (the order matters; parent
// organs must be set before children).

/datum/preference_apply_hook/organs
	priority = APPLY_HOOK_PRIORITY_ORGANS

/datum/preference_apply_hook/organs/apply(mob/living/carbon/human/target, datum/preferences/preferences)
	if(!ishuman(target))
		return

	target.synthetic = preferences.read_preference(/datum/preference/choiced/species) == "Protean" ? GLOB.all_robolimbs["protean"] : null

	var/list/pref_organ_data = preferences.read_preference(/datum/preference/organ_data)
	var/list/pref_rlimb_data = preferences.read_preference(/datum/preference/rlimb_data)
	if(!pref_organ_data)
		return

	// Process external organs in an order that respects parent-organ relationships.
	var/list/organs_to_edit = list()
	for(var/name in list(BP_TORSO, BP_HEAD, BP_GROIN, BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND, BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT))
		var/obj/item/organ/external/O = target.organs_by_name[name]
		if(O)
			var/x = organs_to_edit.Find(O.parent_organ)
			if(x == 0)
				organs_to_edit += name
			else
				organs_to_edit.Insert(x + (O.robotic == ORGAN_NANOFORM ? 1 : 0), name)
	for(var/name in organs_to_edit)
		var/status = pref_organ_data[name]
		var/obj/item/organ/external/O = target.organs_by_name[name]
		if(!O)
			continue
		if(status == "amputated")
			O.remove_rejuv()
		else if(status == "cyborg")
			if(pref_rlimb_data[name])
				O.robotize(pref_rlimb_data[name])
			else
				O.robotize()

	// Internal organ FBP states.
	for(var/name in list(O_HEART, O_EYES, O_VOICE, O_LUNGS, O_LIVER, O_KIDNEYS, O_SPLEEN, O_STOMACH, O_INTESTINE, O_BRAIN))
		var/status = pref_organ_data[name]
		if(!status)
			continue
		var/obj/item/organ/I = target.internal_organs_by_name[name]
		if(istype(I, /obj/item/organ/internal/brain))
			var/obj/item/organ/external/E = target.get_organ(I.parent_organ)
			if(E.robotic < ORGAN_ASSISTED)
				continue
		if(I)
			if(status == FBP_ASSISTED)
				I.mechassist()
			else if(status == FBP_MECHANICAL)
				I.robotize()
			else if(status == FBP_DIGITAL)
				I.digitize()
