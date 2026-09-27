/mob/living/proc/inbelly_spawn_prompt(client/potential_prey)
	if(!potential_prey || !istype(potential_prey))		// Did our prey cease to exist?
		return

	// Are we cool with this prey spawning in at all? The pred answers, then the prey confirms.
	var/prey_name = potential_prey.prefs.read_preference(/datum/preference/name/real_name)
	om_prompt_sequence(src, src, list(
		list("key" = "accept", "message" = "[prey_name] wants to spawn in one of your bellies. Do you accept?", "title" = "Inbelly Spawning", "choices" = list("Yes", "No"), "confirm" = "Yes", "on_stop" = PROC_REF(inbelly_spawn_declined)),
		PROC_REF(inbelly_spawn_ask_belly),
		PROC_REF(inbelly_spawn_ask_digest),
		list("key" = "absorbed", "message" = "Do you want them to start absorbed?", "title" = "Inbelly Spawning", "choices" = list("Yes", "No"), "optional" = TRUE),
		PROC_REF(inbelly_spawn_ask_sure),
		PROC_REF(inbelly_spawn_ask_prey),
	), PROC_REF(inbelly_spawn_answered), list("data" = list("prey" = potential_prey, "prey_name" = prey_name)))

/mob/living/proc/inbelly_spawn_declined(mob/user, datum/om/prompt/ask)
	to_chat(ask.get("prey"), span_notice("Your request was turned down."))

/mob/living/proc/inbelly_spawn_ask_belly(mob/user, datum/om/prompt/ask)
	// Let them know so that they don't spam it.
	to_chat(ask.get("prey"), span_notice("Predator agreed to your request. Wait a bit while they choose a belly."))
	return list("key" = "belly", "kind" = "list", "message" = "Choose Target Belly", "title" = "Belly Choice", "choices" = vore_organs, "on_stop" = PROC_REF(inbelly_spawn_no_belly))

/mob/living/proc/inbelly_spawn_no_belly(mob/user, datum/om/prompt/ask)
	to_chat(ask.get("prey"), span_notice("Something went wrong with predator selecting a belly. Try again?"))
	to_chat(src, span_notice("No valid belly selected. Inbelly spawn cancelled."))

// Extra caution never hurts
/mob/living/proc/inbelly_spawn_ask_digest(mob/user, datum/om/prompt/ask)
	var/obj/belly/belly_choice = ask.get("belly")
	if(belly_choice.digest_mode == DM_DIGEST)
		return list("key" = "digest_ok", "message" = "[belly_choice] is currently set to Digest. Are you sure you want to spawn prey there?", "title" = "Inbelly Spawning", "choices" = list("Yes", "No"), "confirm" = "Yes", "on_stop" = PROC_REF(inbelly_spawn_cancelled))

/mob/living/proc/inbelly_spawn_cancelled(mob/user, datum/om/prompt/ask)
	to_chat(ask.get("prey"), span_notice("Something went wrong with predator selecting a belly. Try again?"))
	to_chat(src, span_notice("Inbelly spawn cancelled."))

// Final confirmation for pred
/mob/living/proc/inbelly_spawn_ask_sure(mob/user, datum/om/prompt/ask)
	return list("key" = "sure", "message" = "Are you certain that you want [ask.get("prey_name")] spawned in your [ask.get("belly")][ask.get("absorbed") == "Yes" ? ", absorbed" : ""]?", "title" = "Inbelly Spawning", "choices" = list("Yes", "No"), "confirm" = "Yes", "on_stop" = PROC_REF(inbelly_spawn_pred_gave_up))

/mob/living/proc/inbelly_spawn_pred_gave_up(mob/user, datum/om/prompt/ask)
	to_chat(ask.get("prey"), span_notice("Your pred couldn't finish selection. Try again?"))
	to_chat(src, span_notice("Inbelly spawn cancelled."))

// And final confirmation for prey
/mob/living/proc/inbelly_spawn_ask_prey(mob/user, datum/om/prompt/ask)
	to_chat(src, span_notice("Waiting for prey's confirmation..."))
	return list("key" = "prey_ok", "user" = ask.get("prey"), "message" = "Are you certain that you to spawn in [src]'s [ask.get("belly")][ask.get("absorbed") == "Yes" ? ", absorbed" : ""]?", "title" = "Inbelly Spawning", "choices" = list("Yes", "No"), "confirm" = "Yes", "on_stop" = PROC_REF(inbelly_spawn_prey_declined))

/mob/living/proc/inbelly_spawn_prey_declined(mob/user, datum/om/prompt/ask)
	to_chat(ask.get("prey"), span_notice("Inbelly spawn cancelled."))
	to_chat(src, span_notice("Prey declined."))

/mob/living/proc/inbelly_spawn_answered(mob/user, datum/om/prompt/ask)
	var/client/potential_prey = ask.get("prey")
	var/obj/belly/belly_choice = ask.get("belly")
	var/absorbed = ask.get("absorbed") == "Yes"
	var/confirmation_prey = ask.get("prey_ok")
	if(confirmation_prey == "Yes" && potential_prey && src && belly_choice)
		//Now we finally spawn them in!
		if(!is_alien_whitelisted(potential_prey, GLOB.all_species[potential_prey.prefs.read_preference(/datum/preference/choiced/species)]))
			to_chat(potential_prey, span_notice("You are not whitelisted to play as currently selected character."))
			to_chat(src, span_notice("Prey accepted the confirmation, but something went wrong with spawning their character."))
			return
		inbelly_spawn(potential_prey, src, belly_choice, absorbed)
	else
		to_chat(potential_prey, span_notice("Inbelly spawn cancelled."))
		to_chat(src, span_notice("Prey cancelled their inbelly spawn request."))

/proc/inbelly_spawn(client/prey, mob/living/pred, obj/belly/target_belly, absorbed = FALSE)
	// All this is basically admin late spawn-in, but skipping all parts related to records and equipment and with predteremined location
	var/player_key = prey.key
	var/picked_ckey = prey.ckey
	var/picked_slot = prey.prefs.default_slot
	var/mob/living/carbon/human/new_character

	new_character = new(null)		// Spawn them in nullspace first. Can't have "Defaultname Defaultnameson slides into your Stomach".

	if(!new_character)
		return

	prey.prefs.copy_to(new_character)
	if(new_character.dna)
		new_character.dna.ResetUIFrom(new_character)
		new_character.sync_dna_traits(TRUE) // Traitgenes Sync traits to genetics if needed
		new_character.sync_organ_dna()
	new_character.sync_addictions()
	new_character.initialize_vessel()
	new_character.key = player_key
	if(new_character.mind)
		var/datum/antagonist/antag_data = SSantag_job.get_antag_data(new_character.mind.special_role)
		if(antag_data)
			antag_data.add_antagonist(new_character.mind)
			antag_data.place_mob(new_character)
		new_character.mind.loaded_from_ckey = picked_ckey
		new_character.mind.loaded_from_slot = picked_slot
		if(new_character.mind.antag_holder)
			new_character.mind.antag_holder.apply_antags(new_character)

	// migrated language prefs to /datum/preference
	var/list/_prey_alt_languages = prey.prefs.read_preference(/datum/preference/alternate_languages)
	var/list/_prey_lang_custom = prey.prefs.read_preference(/datum/preference/language_custom_keys)
	for(var/lang in _prey_alt_languages)
		var/datum/language/chosen_language = GLOB.all_languages[lang]
		if(chosen_language)
			if(is_lang_whitelisted(prey,chosen_language) || (new_character.species && (chosen_language.name in new_character.species.secondary_langs)))
				new_character.add_language(lang)
	for(var/key in _prey_lang_custom)
		if(_prey_lang_custom[key])
			var/datum/language/keylang = GLOB.all_languages[_prey_lang_custom[key]]
			if(keylang)
				new_character.language_keys[key] = keylang
	// migrated preferred_language
	var/_preferred_language = prey.prefs.read_preference(/datum/preference/text/human/preferred_language)
	if(_preferred_language) // Do we have a preferred language?
		var/datum/language/def_lang = GLOB.all_languages[_preferred_language]
		if(def_lang)
			new_character.default_language = def_lang

	SEND_SIGNAL(new_character, COMSIG_HUMAN_DNA_FINALIZED)

	new_character.regenerate_icons()

	new_character.update_transform()

	target_belly.belly_insert(new_character)		// Now that they're all setup and configured, send them to their destination.

	if(absorbed)
		target_belly.absorb_living(new_character)	// Glorp.

	log_admin("[prey] (as [new_character.real_name] has spawned inside one of [pred]'s bellies.")				// Log it. Avoid abuse.
	message_admins("[prey] (as [new_character.real_name] has spawned inside one of [pred]'s bellies.", 1)

	return new_character			// incase its ever needed

/mob/living/proc/soulcatcher_spawn_prompt(mob/observer/dead/prey, req_time)
	var/_answer_a1 = rerun_prompt(src, "a1", list("message" = "[prey.name] wants to join into your Soulcatcher.", "title" = "Soulcatcher Request", "choices" = list("Deny", "Allow"), "timeout" = 1 MINUTES), PROC_REF(soulcatcher_spawn_prompt), args)
	if(isnull(_answer_a1))
		return
	if(_answer_a1 != "Allow")
		to_chat(prey, span_warning("[src] has denied your request."))
		return

	if((world.time - req_time) > 1 MINUTES)
		to_chat(src, span_warning("The request had already expired. (1 minute waiting max)"))
		return

	if(!soulgem)
		return

	if(prey && prey.key && !stat && soulgem.flag_check(SOULGEM_ACTIVE | SOULGEM_CATCHING_GHOSTS, TRUE))
		if(!prey.mind) //No mind yet, aka haven't played in this round.
			prey.mind = new(prey.key)

		prey.mind.name = prey.name
		prey.mind.current = prey
		prey.mind.active = TRUE

		soulgem.catch_mob(prey) //This will result in the prey being deleted so...

/mob/living/carbon/human/proc/nif_soulcatcher_spawn_prompt(mob/observer/dead/prey, req_time)
	var/_answer_a2 = rerun_prompt(src, "a2", list("message" = "[prey.name] wants to join into your Soulcatcher.", "title" = "Soulcatcher Request", "choices" = list("Deny", "Allow"), "timeout" = 1 MINUTES), PROC_REF(nif_soulcatcher_spawn_prompt), args)
	if(isnull(_answer_a2))
		return
	if(_answer_a2 != "Allow")
		to_chat(prey, span_warning("[src] has denied your request."))
		return

	if((world.time - req_time) > 1 MINUTES)
		to_chat(src, span_warning("The request had already expired. (1 minute waiting max)"))
		return

	if(!nif)
		return

	var/datum/nifsoft/soulcatcher/SC = nif.imp_check(NIF_SOULCATCHER)
	if(!SC)
		to_chat(prey, span_warning("[src] doesn't have the Soulcatcher NIFSoft installed, or their NIF is unpowered."))
		return

	//Final check since we waited for input a couple times.
	if(prey && prey.key && !stat && nif && SC)
		if(!prey.mind) //No mind yet, aka haven't played in this round.
			prey.mind = new(prey.key)

		prey.mind.name = prey.name
		prey.mind.current = prey
		prey.mind.active = TRUE

		SC.catch_mob(prey) //This will result in the prey being deleted so...
