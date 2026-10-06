/// Area that holds virtual reality mobs; leaving it derezzes them.
/area/vr
	name = "Virtual Reality"

// Gross system which runs every Life() to check for escaped VR mobs. Tried to do this with Exited() on area/vr but ended up being too heavy.
/// Only virtual reality mobs have anything to check, and only after moving.
/mob/living/proc/life_vr_derez_due()
	return src.virtual_reality_mob && !istype(get_area(src), /area/vr)

/mob/living/proc/life_vr_derez(datum/seq_frame/life/F)
	if(src.virtual_reality_mob && !istype(get_area(src), /area/vr))
		log_admin("[src] escaped virtual reality")
		act_message(src, null, others = "%U% blinks out of existence.")
		src.return_from_vr()
		for(var/obj/belly/B in src.vore_organs) // Assume anybody inside an escaped VR mob is also an escaped VR mob.
			for(var/mob/living/L in B)
				log_vore("[L] was inside an escaped VR mob ([src]) and has been deleted.")
				L.life_vr_derez() //Recursive! Let's get EVERYONE properly out of here!
				if(!QDELETED(L)) //This is so we don't double qdel() things when we're doing recursive removal.
					spent(L)
		spent(src) // Would like to convert escaped players into AR holograms in the future to encourage exploit finding.

// This proc checks to see two things: 1. If we have a tf_mob_holder (we are a simple mob) and 2. If we are a human. If so, we try to exit VR properly.
/mob/living/proc/return_from_vr()
	if(tf_mob_holder)
		var/mob/living/carbon/human/our_holder = tf_mob_holder
		our_holder.exit_vr() //If we have no vr_holder, perfect, we do nothing. If we DO, we get shoved back into our body.
	else if(ishuman(src)) //Alright! We don't have a tf_mob_holder, so we must be a human in VR.
		var/mob/living/carbon/human/our_holder = src
		our_holder.exit_vr()

/mob/living/carbon/human/proc/vr_transform_into_mob()
	set name = "Transform Into Creature"
	set category = VERB_CAT_ABILITIES_VR
	set desc = "Become a different creature"

	open_request(src, /datum/prompt/choice, PROC_REF(vr_creature_chosen), answerer = src, title = "Mob list", question = "Please select a creature:", choices = GLOB.vr_mob_tf_options, ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/carbon/human/proc/vr_creature_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/tf = GLOB.vr_mob_tf_options[A.answer.value]

	var/mob/living/new_form = transform_into_mob(tf, TRUE, TRUE)
	if(isliving(new_form)) // Sanity check
		grant(new_form, granted_verb(/mob/living/proc/vr_revert_mob_tf), new_form)
		new_form.set_virtual_reality_mob(TRUE)

/mob/living/proc/vr_revert_mob_tf()
	set name = "Revert Transformation"
	set category = VERB_CAT_ABILITIES_VR

	revert_mob_tf()

// Exiting VR but for ghosts
/mob/living/carbon/human/proc/fake_exit_vr()
	set name = "Log Out Of Virtual Reality"
	set category = VERB_CAT_ABILITIES_VR

	open_request(src, /datum/prompt/yes_no, PROC_REF(fake_exit_vr_answered), answerer = src, title = "Log out?", question = "Would you like to log out of virtual reality?", timeout = 0)

/mob/living/carbon/human/proc/fake_exit_vr_answered(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	release_vore_contents(TRUE)
	for(var/obj/item/I in contents_of(src))
		drop_from_inventory(I)

	ghostize(src)
	spent(src)

/mob/observer/dead/proc/fake_enter_vr(landmark)
	if(!landmark)
		return

	var/mob/living/carbon/human/avatar = new(get_turf(landmark), client.prefs.read_preference(/datum/preference/choiced/species))
	if(!avatar)
		to_chat(src, "Something went wrong and spawning failed.")
		return

	//Write the appearance and whatnot out to the character
	var/client/C = client
	C.prefs.copy_to(avatar)
	avatar.key = key
	for(var/lang in C.prefs.read_preference(/datum/preference/alternate_languages)) // migrated
		var/datum/language/chosen_language = GLOB.all_languages[lang]
		if(chosen_language)
			if(is_lang_whitelisted(avatar, chosen_language) || (avatar.species && (chosen_language.name in avatar.species.secondary_langs)))
				avatar.add_language(lang)

	OM_EMIT(avatar, /datum/om/event/human_dna_finalized)

	avatar.regenerate_icons()
	avatar.update_transform()
	SSjob.equip_rank(avatar,JOB_VR, 1, FALSE)
	grant(avatar, granted_verb(/mob/living/carbon/human/proc/fake_exit_vr), avatar)
	grant(avatar, granted_verb(/mob/living/carbon/human/proc/vr_transform_into_mob), avatar)
	grant(avatar, granted_verb(/mob/living/proc/set_size), avatar)
	avatar.set_virtual_reality_mob(TRUE)
	log_and_message_admins("[key_name_admin(avatar)] joined virtual reality from the ghost menu.")

	avatar.ask_vr_ghost_name(src.name)

/mob/living/carbon/human/proc/ask_vr_ghost_name(old_name)
	open_request(src, /datum/prompt/text, PROC_REF(vr_avatar_renamed), answerer = src, title = "Name change", question = "You are entering virtual reality. Your username is currently [old_name]. Would you like to change it to something else?", max_len = MAX_NAME_LEN, name_text = TRUE, timeout = 0)

/mob/living/carbon/human/proc/vr_avatar_renamed(datum/act/request/A)
	if(!A.answer)
		return
	if(A.answer.value)
		real_name = A.answer.value
		name = A.answer.value
