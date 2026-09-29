/// Area that holds virtual reality mobs; leaving it derezzes them.
/area/vr
	name = "Virtual Reality"

// Gross system which runs every Life() to check for escaped VR mobs. Tried to do this with Exited() on area/vr but ended up being too heavy.
/datum/om/stage/life/vr_derez
	reads = list("virtual_reality_mob")
	order = LIFE_PHASE_OUTPUT + 50
	name = "vr derez"
	run_if = LIFE_RUN_IF_PLACED
	woken_by = "Moved (a VR mob can only leave the VR area by moving)"

/// Only virtual reality mobs have anything to check, and only after moving.
/datum/om/stage/life/vr_derez/idle(mob/living/self)
	return !self.virtual_reality_mob || istype(get_area(self), /area/vr)

/datum/om/stage/life/vr_derez/perform(mob/living/self, datum/om/frame/life/ctx)
	if(self.virtual_reality_mob && !istype(get_area(self), /area/vr))
		log_admin("[self] escaped virtual reality")
		self.visible_message("[self] blinks out of existence.")
		self.return_from_vr()
		for(var/obj/belly/B in self.vore_organs) // Assume anybody inside an escaped VR mob is also an escaped VR mob.
			for(var/mob/living/L in B)
				log_vore("[L] was inside an escaped VR mob ([self]) and has been deleted.")
				om_stage_run_now(L, /datum/om/stage/life/vr_derez) //Recursive! Let's get EVERYONE properly out of here!
				if(!QDELETED(L)) //This is so we don't double qdel() things when we're doing recursive removal.
					qdel(L)
		qdel(self) // Would like to convert escaped players into AR holograms in the future to encourage exploit finding.

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
	set category = "Abilities.VR"
	set desc = "Become a different creature"

	om_ask(src, /datum/om/prompt/choice, PROC_REF(vr_creature_chosen), choices = GLOB.vr_mob_tf_options, ask_flags = ASK_CONSCIOUS, title = "Mob list", message = "Please select a creature:")

/mob/living/carbon/human/proc/vr_creature_chosen(datum/om/prompt/choice/ask)
	var/tf = GLOB.vr_mob_tf_options[ask.choice]

	var/mob/living/new_form = transform_into_mob(tf, TRUE, TRUE)
	if(isliving(new_form)) // Sanity check
		om_grant(new_form, GRANT_VERB, /mob/living/proc/vr_revert_mob_tf, new_form)
		new_form.set_virtual_reality_mob(TRUE)

/mob/living/proc/vr_revert_mob_tf()
	set name = "Revert Transformation"
	set category = "Abilities.VR"

	revert_mob_tf()

// Exiting VR but for ghosts
/mob/living/carbon/human/proc/fake_exit_vr()
	set name = "Log Out Of Virtual Reality"
	set category = "Abilities.VR"

	om_ask(src, /datum/om/prompt/confirm, PROC_REF(fake_exit_vr_answered), title = "Log out?", message = "Would you like to log out of virtual reality?")

/mob/living/carbon/human/proc/fake_exit_vr_answered(datum/om/prompt/confirm/ask)
	release_vore_contents(TRUE)
	for(var/obj/item/I in contents_of(src))
		drop_from_inventory(I)

	ghostize(src)
	qdel(src)

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
			if(is_lang_whitelisted(usr,chosen_language) || (avatar.species && (chosen_language.name in avatar.species.secondary_langs)))
				avatar.add_language(lang)

	OM_EMIT(avatar, /datum/om/event/human_dna_finalized)

	avatar.regenerate_icons()
	avatar.update_transform()
	SSjob.equip_rank(avatar,JOB_VR, 1, FALSE)
	om_grant(avatar, GRANT_VERB, /mob/living/carbon/human/proc/fake_exit_vr, avatar)
	om_grant(avatar, GRANT_VERB, /mob/living/carbon/human/proc/vr_transform_into_mob, avatar)
	om_grant(avatar, GRANT_VERB, /mob/living/proc/set_size, avatar)
	avatar.set_virtual_reality_mob(TRUE)
	log_and_message_admins("[key_name_admin(avatar)] joined virtual reality from the ghost menu.")

	avatar.ask_vr_ghost_name(src.name)

/mob/living/carbon/human/proc/ask_vr_ghost_name(old_name)
	om_ask(src, /datum/om/prompt/text, PROC_REF(vr_avatar_renamed), message = "You are entering virtual reality. Your username is currently [old_name]. Would you like to change it to something else?", title = "Name change", max_length = MAX_NAME_LEN)

/mob/living/carbon/human/proc/vr_avatar_renamed(datum/om/prompt/text/ask)
	if(ask.text)
		real_name = ask.text
		name = ask.text