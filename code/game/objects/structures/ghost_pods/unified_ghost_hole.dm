/obj/structure/ghost_pod/ghost_activated/unified_hole
	name = "maintenance critter hole"
	desc = "This is my hole! It was made for me!"
	icon = 'icons/effects/effects.dmi'
	icon_state = "rift"
	icon_state_opened = "tendril_dead"
	density = FALSE
	ghost_query_type = /datum/ghost_query/maints_critter
	anchored = TRUE
	invisibility = INVISIBILITY_OBSERVER
	spawn_active = TRUE
	var/redgate_restricted = FALSE

// a volunteer from the ghost query picks a critter as a ghost's click would
/obj/structure/ghost_pod/ghost_activated/unified_hole/create_occupant(mob/observer/dead/user)
	perform_op(user, src, "critter", null, ORIGIN_SYSTEM)

// the hole asks which critter instead of a yes
CAPABILITIES(/obj/structure/ghost_pod/ghost_activated/unified_hole)
	without("inhabit")
	op("critter", observer(), label("Inhabit"), needs(req(PROC_REF(can_inhabit), because = PROC_REF(inhabit_refusal))),
		asks(/datum/prompt/choice, fields = list("title" = computed(PROC_REF(inhabit_title)), "question" = computed(PROC_REF(inhabit_question)), "choices" = list("Mob", "Morph", "Lurker", "Cancel"), "buttons" = TRUE, "timeout" = 0), keeps = TARGET_PRESENT),
		then(PROC_REF(critter_type_chosen)))

/// Requirement for the critter hole: not banned, OOC notes set, unused.
/obj/structure/ghost_pod/ghost_activated/unified_hole/inhabit_refusal(datum/act/op/A)
	var/why = ghost_role_refusal(A.actor, "You cannot use this spawnpoint because you are banned from playing ghost roles.")
	if(why)
		return why
	if(used)
		return MSG(ghost_pod/taken)
	return null

/obj/structure/ghost_pod/ghost_activated/unified_hole/inhabit_title(datum/act/A)
	return redgate_restricted ? "Redgate Critter Spawner" : "Critter Spawner"

/obj/structure/ghost_pod/ghost_activated/unified_hole/inhabit_question(datum/act/A)
	if(redgate_restricted)
		return "Which type of critter do you wish to spawn as? Note that this is a Redgate Spawner: if you choose the Lurker role you will not be able to leave through the redgate until another character grants you permission by clicking on the redgate with you nearby. Are you absolutely sure you wish to continue?"
	return "Which type of critter do you wish to spawn as?"

/// The ghost picked a critter (re-checked on the answer: still unused).
/obj/structure/ghost_pod/ghost_activated/unified_hole/proc/critter_type_chosen(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/mob/observer/dead/user = A.actor
	if(!R || !user.client)
		return OP_OK
	switch(R.value)
		if("Cancel")
			return OP_OK
		if("Mob")
			create_simplemob(user)
			return OP_OK
		if("Morph")
			create_morph(user)
		if("Lurker")
			if(!is_alien_whitelisted(user.client, GLOB.all_species[user.client.prefs.read_preference(/datum/preference/choiced/species)]))
				to_chat(user, span_warning("You cannot use this spawnpoint to spawn as a species you are not whitelisted for!"))
				return OP_OK
			create_lurker(user)
	set_used(TRUE)
	icon_state = icon_state_opened
	update_icon()
	registry_leave(REGISTRY_GHOST_PODS, src)
	return OP_OK

/obj/structure/ghost_pod/ghost_activated/unified_hole/proc/create_simplemob(mob/M)
	set_used(TRUE)
	registry_leave(REGISTRY_GHOST_PODS, src)
	ask_maint_critter(M, "What type of critter do you want to play as?", "Critter Choice")

/obj/structure/ghost_pod/ghost_activated/unified_hole/spawn_maint_critter(mob/M, choice)
	if(needscharger)
		new /obj/machinery/recharge_station/ghost_pod_recharger(src.loc)
	var/mobtype = GLOB.maint_mob_pred_options[choice]
	var/mob/living/simple_mob/newPred = new mobtype(get_turf(src))
	own_clear(newPred, nameof(newPred.ai_brain), OWN_DELETE)
	//newPred.movement_cooldown = 0			// The "needless artificial speed cap" exists for a reason
	// R.has_hands = TRUE // Downstream
	if(M.mind)
		M.mind.transfer_to(newPred)
	to_chat(M, span_notice("You are " + span_bold("[newPred]") + ", somehow having stowed away in search of food, shelter, or safety. The environment around you is a strange and unfamiliar one, but sooner or later you'll have to leave your hiding place in search of food. How you choose to do so is up to you, just beware that you don't end up falling prey to some other creature."))
	to_chat(M, span_critical("Please be advised, this role is NOT AN ANTAGONIST."))
	to_chat(M, span_warning("You may be a spooky (or cute!) space critter, but your role is to facilitate roleplay, not to fight the station and slaughter people. You're free to get into any kind of roleplay scene you like if OOC prefs align, but emphasis is on the 'roleplay' here. If you intend to be an actual threat, you MUST seek permission from staff first. GENERALLY, this role should avoid well populated areas, but you might be able to get away with it if you spawn as something relatively innocuous."))
	newPred.ckey = M.ckey
	act_message(newPred, null, others = span_warning("%U% emerges from somewhere!"))
	log_and_message_admins("successfully used a Maintenance Critter spawner to spawn in as a [newPred].", newPred)
	newPred.offer_load_bellies()
	replace_with(src, newPred)

/obj/structure/ghost_pod/ghost_activated/unified_hole/proc/create_morph(mob/M)
	registry_leave(REGISTRY_GHOST_PODS, src)
	var/mob/living/simple_mob/vore/morph/newMorph = new /mob/living/simple_mob/vore/morph(get_turf(src))
	newMorph.voremob_loaded = TRUE // On-demand belly loading.
	if(M.mind)
		M.mind.transfer_to(newMorph)
	to_chat(M, span_notice("You are a " + span_bold("Morph") + ", somehow having stowed away in your wandering. You are in a strange and unfamiliar place, but one that's sure to be full of tasty treats and learning opportunities. If you want to survive here for long you should probably seek a convincing disguise, or at the very least take advantage of your amorphous form to slither through the ventilation system and avoid danger that way."))
	to_chat(M, span_notice("You can use shift + click on objects and creatures to disguise yourself as them, but your strikes are nearly useless when you are disguised. \
	You can undisguise yourself by shift + clicking yourself, but changing your shape (whether changing to a false form or returning to your natural form) has a short cooldown. You can also ventcrawl, \
	by using alt + click on the vent or scrubber. Note that it may be impossible to impersonate certain people due to mechanical preference settings."))
	to_chat(M, span_critical("Please be advised, this role is NOT AN ANTAGONIST."))
	to_chat(M, span_warning("You may be a weird goopy creature, but your role is to facilitate weird goopy creature roleplay, not to fight the station and slaughter people. You're free to get into any kind of roleplay scene you like if OOC prefs align, but emphasis is on the 'roleplay' here. If you intend to be an actual threat, you MUST seek permission from staff first. GENERALLY, this role should avoid well populated areas, but you might be able to get away with it if you play your cards right."))

	newMorph.ckey = M.ckey
	newMorph.visible_message(span_warning("A morph appears to crawl out of somewhere."))
	log_and_message_admins("successfully used a Maintenance Critter spawner to spawn in as a Morph.", newMorph)
	newMorph.offer_load_bellies()
	spent(src, M)

/obj/structure/ghost_pod/ghost_activated/unified_hole/proc/create_lurker(mob/M)
	if(!M?.client)
		reset_ghostpod()
		return
	var/picked_ckey = M.ckey
	var/picked_slot = M.client.prefs.default_slot
	registry_leave(REGISTRY_GHOST_PODS, src)

	var/mob/living/carbon/human/new_character = new(src.loc)
	if(!new_character)
		to_chat(M, span_warning("Something went wrong and spawning failed. Please check your character slot doesn't have any obvious errors, then either try again or send an adminhelp!"))
		reset_ghostpod()
		return
	log_and_message_admins("successfully used a Maintenance Critter spawner to spawn in as their loaded character.", M)

	M.client.prefs.copy_to(new_character)
	new_character.dna.ResetUIFrom(new_character)
	new_character.sync_organ_dna()
	new_character.sync_addictions()
	new_character.key = M.key
	new_character.mind.loaded_from_ckey = picked_ckey
	new_character.mind.loaded_from_slot = picked_slot

	SSjob.equip_rank(new_character, JOB_MAINT_LURKER, 1)

	for(var/lang in new_character.client.prefs.read_preference(/datum/preference/alternate_languages)) // migrated
		var/datum/language/chosen_language = GLOB.all_languages[lang]
		if(chosen_language)
			if(is_lang_whitelisted(M, chosen_language) || (new_character.species && (chosen_language.name in new_character.species.secondary_langs)))
				new_character.add_language(lang)

	OM_EMIT(new_character, /datum/om/event/human_dna_finalized)

	new_character.regenerate_icons()

	new_character.update_transform()
	if(redgate_restricted)
		new_character.redgate_restricted = TRUE
		to_chat(new_character, span_notice("You are an inhabitant of this redgate location, you have no special advantages compared to the rest of the crew, so be cautious! You have spawned with an ID that will allow you free access to basic doors, and should possess all of your chosen loadout items that are not role restricted, and can make use of anything you can find in the redgate map."))
	else
		to_chat(new_character, span_notice("You are a " + span_bold(JOB_MAINT_LURKER) + ", a loose end, stowaway, drifter, or somesuch. You have no special advantages compared to the rest of the crew, so be cautious! You have spawned with an ID that will allow you free access to maintenance areas, and should possess all of your chosen loadout items that are not role restricted. You also have a PDA which you can use for messaging purposes, and are free to make use of anything you can find in maintenance."))
	to_chat(new_character, span_critical("Please be advised, this role is " + span_bold("NOT AN ANTAGONIST.")))
	to_chat(new_character, span_notice("Whoever or whatever your chosen character slot is, your role is to facilitate roleplay focused around that character; this role is not free license to attack and murder people without provocation or explicit out-of-character consent. You should probably be cautious around high-traffic and highly sensitive areas (e.g. Telecomms) as Security personnel would be well within their rights to treat you as a trespasser. That said, good luck!"))

	act_message(new_character, null, others = span_warning("%U% appears to crawl out of somewhere."))
	spent(src, M)

DECLARE_REGISTRY(/obj/structure/ghost_pod/ghost_activated/unified_hole, REGISTRY_GHOST_PODS)

/obj/structure/ghost_pod/ghost_activated/unified_hole/Initialize(mapload)
	. = ..()
	update_icon()

DECLARE_APPEARANCE(/obj/structure/ghost_pod/ghost_activated/unified_hole, "used", list("0" = list(APPEARANCE_OVERLAYS = list("rift_glow")), "" = list(APPEARANCE_OVERLAYS = list("rift_glow"))))
APPEARANCE_EMISSIVE(/obj/structure/ghost_pod/ghost_activated/unified_hole, "used", list("0" = "rift_glow", "" = "rift_glow"))

/obj/structure/ghost_pod/ghost_activated/unified_hole/redgate
	name = "Redspace inhabitant hole"
	desc = "A starting location for critters who exist inside of the redgate!"
	redgate_restricted = TRUE
