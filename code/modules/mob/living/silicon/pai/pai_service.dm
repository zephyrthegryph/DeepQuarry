#define PAI_DELAY_TIME 1 MINUTE

////////////////////////////////
//// pAI join and management system (was SSpai)
////////////////////////////////
// The software and chassis tables are set up after SSatoms (the subsystem's atoms dependency). The
// candidate list is refreshed from the observers every 4 s by refresh_candidates.
SYSTEM_DEF(pai)
	name = "Pai"
	needs = list(/datum/system/atoms)
	periodic_runlevels = RUNLEVELS_DEFAULT
	VAR_PRIVATE/list/datum/pai_sprite/pai_chassis_sprites = list()
	VAR_PRIVATE/list/current_run = list()
	/// Candidate ghosts this refresh (REL_LIST, cleared by the framework when a ghost dies).
	VAR_PRIVATE/list/pai_ghosts
	VAR_PRIVATE/list/asked = list()
	/// TRUE while a candidate refresh that ran out of budget waits to resume.
	VAR_PRIVATE/refresh_resuming = FALSE

/datum/system/pai/initialize()
	if(initialized)
		return
	initialized = TRUE
	// Get all software setup
	for(var/type in subtypesof(/datum/pai_software))
		var/datum/pai_software/P = new type()
		GLOB.pai_software_by_key[P.id] = P
		if(P.default)
			GLOB.default_pai_software[P.id] = P

	// Get all valid chassis types
	for(var/datum/pai_sprite/sprite as anything in subtypesof(/datum/pai_sprite))
		if(!initial(sprite.sprite_icon) || initial(sprite.hidden))
			continue
		own_put(src, nameof(pai_chassis_sprites), initial(sprite.name), new sprite())

	log_world("pAI service initialized: [length(GLOB.pai_software_by_key)] software, [length(pai_chassis_sprites)] chassis.")

/datum/system/pai/stat_entry(msg)
	return "[..()]C:[length(pai_ghosts)]"

/datum/system/pai/reactions()
	. = ..()
	. += every(4 SECONDS, PROC_REF(refresh_candidates), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/pai/proc/refresh_candidates(dt)
	if(!refresh_resuming)
		rel_clear(src, nameof(pai_ghosts))
		current_run = REGISTRY_COPY(REGISTRY_OBSERVERS)
	refresh_resuming = FALSE

	while(length(current_run))
		if(KERNEL_OVER_BUDGET)
			refresh_resuming = TRUE
			return STEP_YIELD

		var/mob/observer/ghost = current_run[length(current_run)]
		current_run.len--
		if(!invite_valid(ghost))
			continue

		// Create candidate
		rel_add(src, nameof(pai_ghosts), ghost)
	return STEP_DONE

/datum/system/pai/proc/check_is_delayed(ghost_ref)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(ghost_ref in asked)
		// ALLOW(cooldown): per-ghost ask cooldown table keyed by ref
		if(world.time < asked[ghost_ref] + PAI_DELAY_TIME)
			return TRUE
	return FALSE

/// A ghost is asked to play a pAI. Re-checked on the answer: still that ghost, with a client.
/datum/om/prompt/choice/pai_invite
	title = "pAI Request"
	buttons = TRUE
	choices = list("Yes", "No", "Never for this round")
	var/mob/inquirer
	var/ghost_ref

/datum/om/prompt/choice/pai_invite/prepare()
	message = "[inquirer] is requesting a pAI personality. Would you like to play as a personal AI?"
	return TRUE

/datum/om/prompt/choice/pai_invite/valid()
	var/mob/observer/ghost = answerer
	if(!ghost.client || !isobserver(ghost) || SSpai.get_ghost_from_ref(ghost_ref) != ghost)
		return "not that ghost" // Nice try smartass
	return null

/// The ghost's answer to a pAI invite.
/datum/system/pai/proc/pai_invite_answered(datum/om/prompt/choice/pai_invite/ask)
	var/mob/observer/ghost = ask.answerer
	pai_invite_answer(ask.inquirer, ghost, ask.subject, ask.choice, ghost.client)

/datum/system/pai/proc/pai_invite_answer(mob/inquirer, mob/observer/ghost, obj/item/paicard/card, response, client/target)
	if(check_is_already_pai(target.ckey))
		to_chat(inquirer, span_warning("This pAI has already been downloaded."))
		return
	if(QDELETED(card) || card.pai)
		to_chat(inquirer, span_warning("This [card] can no longer be used to house a pAI."))
		return

	switch(response)
		if("Yes")
			var/new_pai = card.ghost_inhabit(target.mob, TRUE)
			to_chat(inquirer, span_info("[new_pai] has accepted your pAI request!"))
			return
		if("Never for this round")
			SSpai.block_pai_invites(REF(ghost))

	to_chat(inquirer, span_warning("The pAI denied the request."))

/datum/system/pai/relations()
	. = ..()
	. += rel_many(nameof(pai_ghosts))

#undef PAI_DELAY_TIME
