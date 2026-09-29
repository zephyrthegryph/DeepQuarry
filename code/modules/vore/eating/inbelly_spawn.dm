/mob/living/proc/inbelly_spawn_prompt(client/potential_prey)
	if(!potential_prey || !istype(potential_prey))		// Did our prey cease to exist?
		return
	// Are we cool with this prey spawning in at all? The pred answers, then the prey confirms.
	om_flow_start(/datum/om/flow/inbelly_spawn, src, null, prey = potential_prey, prey_name = potential_prey.prefs.read_preference(/datum/preference/name/real_name))

/// A ghost asks to spawn in a belly: the pred (actor) accepts, picks the belly, confirms a digest
/// belly, picks absorbed or not and confirms; then the prey confirms. A no or a cancel at any
/// step tells both sides, by the step it stopped at.
/datum/om/flow/inbelly_spawn
	name = "inbelly spawn"
	/// The ghost's client: held by ckey between steps.
	var/client/prey
	var/prey_name
	var/obj/belly/belly
	var/absorbed = FALSE
	/// The step waiting for an answer, for ended()'s messages.
	var/stage

/datum/om/flow/inbelly_spawn/start()
	stage = "accept"
	om_ask(actor, /datum/om/prompt/confirm, PROC_REF(accepted), title = "Inbelly Spawning", message = "[prey_name] wants to spawn in one of your bellies. Do you accept?")

/datum/om/flow/inbelly_spawn/proc/accepted()
	var/mob/living/pred = actor
	// Let them know so that they don't spam it.
	to_chat(prey, span_notice("Predator agreed to your request. Wait a bit while they choose a belly."))
	stage = "belly"
	om_ask(pred, /datum/om/prompt/choice, PROC_REF(belly_picked), title = "Belly Choice", message = "Choose Target Belly", choices = pred.vore_organs)

/datum/om/flow/inbelly_spawn/proc/belly_picked(datum/om/prompt/choice/ask)
	rel_set(src, nameof(belly), ask.choice)
	// Extra caution never hurts
	if(belly.digest_mode == DM_DIGEST)
		stage = "digest"
		om_ask(actor, /datum/om/prompt/confirm, PROC_REF(ask_absorbed), title = "Inbelly Spawning", message = "[belly] is currently set to Digest. Are you sure you want to spawn prey there?")
		return
	ask_absorbed()

/datum/om/flow/inbelly_spawn/proc/ask_absorbed()
	stage = "absorbed"
	om_ask(actor, /datum/om/prompt/confirm, PROC_REF(absorbed_picked), title = "Inbelly Spawning", message = "Do you want them to start absorbed?", answer_on_no = TRUE, cancel_answer = "No")

/datum/om/flow/inbelly_spawn/proc/absorbed_picked(datum/om/prompt/confirm/ask)
	absorbed = ask.yes
	// Final confirmation for pred
	stage = "sure"
	om_ask(actor, /datum/om/prompt/confirm, PROC_REF(pred_sure), title = "Inbelly Spawning", message = "Are you certain that you want [prey_name] spawned in your [belly][absorbed ? ", absorbed" : ""]?")

/datum/om/flow/inbelly_spawn/proc/pred_sure()
	// And final confirmation for prey
	to_chat(actor, span_notice("Waiting for prey's confirmation..."))
	stage = "prey"
	om_ask(prey, /datum/om/prompt/confirm, PROC_REF(prey_sure), title = "Inbelly Spawning", message = "Are you certain that you to spawn in [actor]'s [belly][absorbed ? ", absorbed" : ""]?")

/datum/om/flow/inbelly_spawn/proc/prey_sure()
	//Now we finally spawn them in!
	if(!is_alien_whitelisted(prey, GLOB.all_species[prey.prefs.read_preference(/datum/preference/choiced/species)]))
		to_chat(prey, span_notice("You are not whitelisted to play as currently selected character."))
		to_chat(actor, span_notice("Prey accepted the confirmation, but something went wrong with spawning their character."))
		return
	inbelly_spawn(prey, actor, belly, absorbed)

/datum/om/flow/inbelly_spawn/ended(reason)
	if(reason == "gone")
		return
	switch(stage)
		if("accept")
			to_chat(prey, span_notice("Your request was turned down."))
		if("belly")
			to_chat(prey, span_notice("Something went wrong with predator selecting a belly. Try again?"))
			to_chat(actor, span_notice("No valid belly selected. Inbelly spawn cancelled."))
		if("digest")
			to_chat(prey, span_notice("Something went wrong with predator selecting a belly. Try again?"))
			to_chat(actor, span_notice("Inbelly spawn cancelled."))
		if("sure")
			to_chat(prey, span_notice("Your pred couldn't finish selection. Try again?"))
			to_chat(actor, span_notice("Inbelly spawn cancelled."))
		if("prey")
			to_chat(prey, span_notice("Inbelly spawn cancelled."))
			to_chat(actor, span_notice("Prey declined."))

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
		var/datum/antagonist/antag_data = GLOB.antag_service.get_antag_data(new_character.mind.special_role)
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

	OM_EMIT(new_character, /datum/om/event/human_dna_finalized)

	new_character.regenerate_icons()

	new_character.update_transform()

	target_belly.belly_insert(new_character)		// Now that they're all setup and configured, send them to their destination.

	if(absorbed)
		target_belly.absorb_living(new_character)	// Glorp.

	log_admin("[prey] (as [new_character.real_name] has spawned inside one of [pred]'s bellies.")				// Log it. Avoid abuse.
	message_admins("[prey] (as [new_character.real_name] has spawned inside one of [pred]'s bellies.", 1)

	return new_character			// incase its ever needed

/mob/living/proc/soulcatcher_spawn_prompt(mob/observer/dead/prey, req_time)
	var/_answer_a1 = rerun_ask(src, "a1", PROC_REF(soulcatcher_spawn_prompt), args, /datum/om/prompt/choice/alert, message = "[prey.name] wants to join into your Soulcatcher.", title = "Soulcatcher Request", choices = list("Deny", "Allow"), timeout = 1 MINUTES)
	if(isnull(_answer_a1))
		return
	if(_answer_a1 != "Allow")
		to_chat(prey, span_warning("[src] has denied your request."))
		return

	if(ELAPSED_SINCE(src, req_time, CLOCK_WORLD) > 1 MINUTES)
		to_chat(src, span_warning("The request had already expired. (1 minute waiting max)"))
		return

	if(!soulgem)
		return

	if(prey && prey.key && !stat && soulgem.flag_check(SOULGEM_ACTIVE | SOULGEM_CATCHING_GHOSTS, TRUE))
		if(!prey.mind) //No mind yet, aka haven't played in this round.
			rel_set(prey, nameof(prey.mind), new /datum/mind(prey.key))

		prey.mind.name = prey.name
		rel_set(prey.mind, nameof(/datum/forms::current), prey)
		prey.mind.active = TRUE

		soulgem.catch_mob(prey) //This will result in the prey being deleted so...

/mob/living/carbon/human/proc/nif_soulcatcher_spawn_prompt(mob/observer/dead/prey, req_time)
	var/_answer_a2 = rerun_ask(src, "a2", PROC_REF(nif_soulcatcher_spawn_prompt), args, /datum/om/prompt/choice/alert, message = "[prey.name] wants to join into your Soulcatcher.", title = "Soulcatcher Request", choices = list("Deny", "Allow"), timeout = 1 MINUTES)
	if(isnull(_answer_a2))
		return
	if(_answer_a2 != "Allow")
		to_chat(prey, span_warning("[src] has denied your request."))
		return

	if(ELAPSED_SINCE(src, req_time, CLOCK_WORLD) > 1 MINUTES)
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
			rel_set(prey, nameof(prey.mind), new /datum/mind(prey.key))

		prey.mind.name = prey.name
		rel_set(prey.mind, nameof(/datum/forms::current), prey)
		prey.mind.active = TRUE

		SC.catch_mob(prey) //This will result in the prey being deleted so...
