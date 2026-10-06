/mob/living/proc/inbelly_spawn_prompt(client/potential_prey)
	if(!potential_prey || !istype(potential_prey))		// Did our prey cease to exist?
		return
	// Are we cool with this prey spawning in at all? The pred answers, then the prey confirms.
	var/datum/inbelly_spawn_review/review = new
	rel_set(review, nameof(review.actor), src)
	review.prey_ckey = potential_prey.ckey
	review.prey_name = potential_prey.prefs.read_preference(/datum/preference/name/real_name)
	review.start()

/// A ghost asks to spawn in a belly: the pred (actor) accepts, picks the belly, confirms a digest
/// belly, picks absorbed or not and confirms; then the prey confirms. A no or a cancel at any
/// step tells both sides, by the step it stopped at.
/datum/inbelly_spawn_review
	parent_type = /datum/prompt_workflow
	var/mob/living/actor
	/// Same identity lookup as the old flow's parked client, without retaining a client.
	var/prey_ckey
	var/prey_name
	var/obj/belly/belly
	var/belly_selected = FALSE
	var/absorbed = FALSE
	var/stage

CAPABILITIES(/datum/inbelly_spawn_review)
	ref_one(nameof(actor), /mob/living)
	ref_one(nameof(belly), /obj/belly)

/datum/prompt/yes_no/inbelly_spawn
	title = "Inbelly Spawning"
	timeout = 0
	var/accept_no = FALSE

/datum/prompt/yes_no/inbelly_spawn/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/inbelly_spawn_review/review = owner
	// Most old No answers stopped before the flow's captured-state recheck.
	return value == FALSE && !accept_no ? null : review.why_not()

/datum/prompt/choice/inbelly_spawn
	timeout = 0

/datum/prompt/choice/inbelly_spawn/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/selected = value
	if(isdatum(selected) && QDELETED(selected))
		return "gone"
	var/datum/inbelly_spawn_review/review = owner
	return review.why_not()

/datum/inbelly_spawn_review/proc/prey_client()
	RETURN_TYPE(/client)
	return GLOB.directory[prey_ckey]

/datum/inbelly_spawn_review/proc/why_not()
	return QDELETED(actor) || !prey_client() || (belly_selected && QDELETED(belly)) ? "gone" : null

/datum/inbelly_spawn_review/proc/start()
	if(why_not())
		retire()
		return
	run_step(PROC_REF(start_step))

/datum/inbelly_spawn_review/proc/run_step(step, datum/act/request/A)
	var/datum/result/result = safe_call(step, A)
	if(!result.ok)
		stack_trace("inbelly spawn step [step]: [result.error]")
		stopped("error")

/datum/inbelly_spawn_review/proc/stopped(reason)
	notify_stopped(reason)
	retire()

/datum/inbelly_spawn_review/proc/failed_answer(datum/request/R)
	if(QDELETED(actor) || (R.answerer_expected && QDELETED(R.answerer)))
		stopped("gone")
		return
	stopped(isnull(R.value) ? "cancelled" : R.last_error)

/datum/inbelly_spawn_review/proc/start_step()
	stage = "accept"
	open_request(src, /datum/prompt/yes_no/inbelly_spawn, PROC_REF(accepted), answerer = actor, asker = actor, question = "[prey_name] wants to spawn in one of your bellies. Do you accept?")

/datum/inbelly_spawn_review/proc/accepted(datum/act/request/A)
	run_step(PROC_REF(accepted_step), A)

/datum/inbelly_spawn_review/proc/accepted_step(datum/act/request/A)
	if(!A.answer)
		failed_answer(A.request)
		return
	if(A.request.value == FALSE)
		stopped("declined")
		return
	var/client/prey = prey_client()
	to_chat(prey, span_notice("Predator agreed to your request. Wait a bit while they choose a belly."))
	stage = "belly"
	open_request(src, /datum/prompt/choice/inbelly_spawn, PROC_REF(belly_picked), answerer = actor, asker = actor, title = "Belly Choice", question = "Choose Target Belly", choices = actor.vore_organs)

/datum/inbelly_spawn_review/proc/belly_picked(datum/act/request/A)
	run_step(PROC_REF(belly_picked_step), A)

/datum/inbelly_spawn_review/proc/belly_picked_step(datum/act/request/A)
	if(!A.answer)
		failed_answer(A.request)
		return
	rel_set(src, nameof(belly), A.request.value)
	if(QDELETED(belly))
		stopped("gone")
		return
	belly_selected = TRUE
	if(belly.digest_mode == DM_DIGEST)
		stage = "digest"
		open_request(src, /datum/prompt/yes_no/inbelly_spawn, PROC_REF(digest_confirmed), answerer = actor, asker = actor, question = "[belly] is currently set to Digest. Are you sure you want to spawn prey there?")
		return
	ask_absorbed()

/datum/inbelly_spawn_review/proc/digest_confirmed(datum/act/request/A)
	if(!A.answer)
		failed_answer(A.request)
		return
	if(A.request.value == FALSE)
		stopped("declined")
		return
	run_step(PROC_REF(ask_absorbed))

/datum/inbelly_spawn_review/proc/ask_absorbed()
	stage = "absorbed"
	open_request(src, /datum/prompt/yes_no/inbelly_spawn, PROC_REF(absorbed_picked), answerer = actor, asker = actor, question = "Do you want them to start absorbed?", accept_no = TRUE)

/datum/inbelly_spawn_review/proc/absorbed_picked(datum/act/request/A)
	run_step(PROC_REF(absorbed_picked_step), A)

/datum/inbelly_spawn_review/proc/absorbed_picked_step(datum/act/request/A)
	if(!A.answer)
		// Old cancel_answer No was delivered and resumed with a live captured-state check.
		if(A.request.outcome != REQ_CANCELLED || !isnull(A.request.value) || why_not())
			stopped("gone")
			return
	absorbed = A.answer ? A.request.value : FALSE
	stage = "sure"
	open_request(src, /datum/prompt/yes_no/inbelly_spawn, PROC_REF(pred_sure), answerer = actor, asker = actor, question = "Are you certain that you want [prey_name] spawned in your [belly][absorbed ? ", absorbed" : ""]?")

/datum/inbelly_spawn_review/proc/pred_sure(datum/act/request/A)
	run_step(PROC_REF(pred_sure_step), A)

/datum/inbelly_spawn_review/proc/pred_sure_step(datum/act/request/A)
	if(!A.answer)
		failed_answer(A.request)
		return
	if(A.request.value == FALSE)
		stopped("declined")
		return
	to_chat(actor, span_notice("Waiting for prey's confirmation..."))
	stage = "prey"
	var/client/prey = prey_client()
	// Old om_ask normalized the client to its current mob, and ended with no question if absent.
	if(!prey.mob)
		retire()
		return
	open_request(src, /datum/prompt/yes_no/inbelly_spawn, PROC_REF(prey_sure), answerer = prey.mob, asker = actor, question = "Are you certain that you to spawn in [actor]'s [belly][absorbed ? ", absorbed" : ""]?")

/datum/inbelly_spawn_review/proc/prey_sure(datum/act/request/A)
	run_step(PROC_REF(prey_sure_step), A)

/datum/inbelly_spawn_review/proc/prey_sure_step(datum/act/request/A)
	if(!A.answer)
		failed_answer(A.request)
		return
	if(A.request.value == FALSE)
		stopped("declined")
		return
	var/client/prey = prey_client()
	if(!is_alien_whitelisted(prey, GLOB.all_species[prey.prefs.read_preference(/datum/preference/choiced/species)]))
		to_chat(prey, span_notice("You are not whitelisted to play as currently selected character."))
		to_chat(actor, span_notice("Prey accepted the confirmation, but something went wrong with spawning their character."))
		retire()
		return
	inbelly_spawn(prey, actor, belly, absorbed)
	retire()

/datum/inbelly_spawn_review/proc/notify_stopped(reason)
	var/client/prey = prey_client()
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
		var/datum/antagonist/antag_data = SSantag.get_antag_data(new_character.mind.special_role)
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

	PUBLISH_LEGACY(new_character, /datum/notice/human_dna_finalized)

	new_character.regenerate_icons()

	new_character.update_transform()

	target_belly.belly_insert(new_character)		// Now that they're all setup and configured, send them to their destination.

	if(absorbed)
		target_belly.absorb_living(new_character)	// Glorp.

	log_admin("[prey] (as [new_character.real_name] has spawned inside one of [pred]'s bellies.")				// Log it. Avoid abuse.
	message_admins("[prey] (as [new_character.real_name] has spawned inside one of [pred]'s bellies.", 1)

	return new_character			// incase its ever needed

/mob/living/proc/soulcatcher_spawn_prompt(mob/observer/dead/prey, req_time)
	open_request(src, /datum/prompt/choice/soulcatcher_admission, PROC_REF(soulcatcher_spawn_prompt_answered), answerer = src, subject = prey, req_time = req_time, question = "[prey.name] wants to join into your Soulcatcher.")

/mob/living/proc/soulcatcher_spawn_prompt_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/soulcatcher_admission/ask = context.answer
	soulcatcher_spawn_prompt_apply(context.request.subject, ask.req_time, ask.value)
	SStgui.update_uis(src)

/mob/living/proc/soulcatcher_spawn_prompt_apply(mob/observer/dead/prey, req_time, selected)
	if(selected != "Allow")
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
	open_request(src, /datum/prompt/choice/soulcatcher_admission, PROC_REF(nif_soulcatcher_spawn_prompt_answered), answerer = src, subject = prey, req_time = req_time, question = "[prey.name] wants to join into your Soulcatcher.")

/mob/living/carbon/human/proc/nif_soulcatcher_spawn_prompt_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/soulcatcher_admission/ask = context.answer
	nif_soulcatcher_spawn_prompt_apply(context.request.subject, ask.req_time, ask.value)
	SStgui.update_uis(src)

/mob/living/carbon/human/proc/nif_soulcatcher_spawn_prompt_apply(mob/observer/dead/prey, req_time, selected)
	if(selected != "Allow")
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

/datum/prompt/choice/soulcatcher_admission
	title = "Soulcatcher Request"
	choices = list("Deny", "Allow")
	buttons = TRUE
	timeout = 1 MINUTES
	recheck_on_open = TRUE
	var/req_time

/datum/prompt/choice/soulcatcher_admission/recheck_extra()
	var/mob/living/recipient = owner
	var/mob/observer/dead/prey = subject
	return !istype(recipient) || QDELETED(recipient) || !istype(prey) || QDELETED(prey) ? "gone" : null
