#define PAI_DELAY_TIME 1 MINUTE

////////////////////////////////
//// pAI join and management world service (fold wave F3; was SSpai)
////////////////////////////////
// The software and chassis tables are set up by SSatoms.Initialize() (the subsystem's atoms
// dependency). The candidate list is refreshed from the observers every 4 s by
// /datum/om/behaviour/world/pai on the OM global owner (code/datums/om/world_lanes.dm).
GLOBAL_DATUM_INIT(pai_service, /datum/world_service/pai, new)

/datum/world_service/pai
	name = "Pai"
	boot_after = /datum/controller/subsystem/atoms
	lane = /datum/om/behaviour/world/pai
	VAR_PRIVATE/list/datum/pai_sprite/pai_chassis_sprites = list()
	VAR_PRIVATE/list/current_run = list()
	/// Candidate ghosts this refresh (REL_LIST, cleared by the framework when a ghost dies).
	VAR_PRIVATE/list/pai_ghosts
	VAR_PRIVATE/list/asked = list()

/datum/world_service/pai/initialize()
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
		own_put(src, "pai_chassis_sprites", initial(sprite.name), new sprite())

	log_world("pAI service initialized: [length(GLOB.pai_software_by_key)] software, [length(pai_chassis_sprites)] chassis.")

/datum/world_service/pai/stat_line()
	return "C:[length(pai_ghosts)]"

/datum/world_service/pai/service_step(resumed)
	if(!resumed)
		rel_clear(src, "pai_ghosts")
		current_run = REGISTRY_COPY(REGISTRY_OBSERVERS)

	while(length(current_run))
		if(TICK_CHECK)
			return FALSE

		var/mob/observer/ghost = current_run[length(current_run)]
		current_run.len--
		if(!invite_valid(ghost))
			continue

		// Create candidate
		rel_add(src, "pai_ghosts", ghost)
	return TRUE

/datum/world_service/pai/proc/get_chassis_list()
	RETURN_TYPE(/list/datum/pai_sprite)
	SHOULD_NOT_OVERRIDE(TRUE)
	return pai_chassis_sprites

/datum/world_service/pai/proc/chassis_data(id_name)
	RETURN_TYPE(/datum/pai_sprite)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!(id_name in pai_chassis_sprites))
		return pai_chassis_sprites[PAI_DEFAULT_CHASSIS]
	return pai_chassis_sprites[id_name]

/datum/world_service/pai/proc/invite_valid(mob/user)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!user.client?.prefs || !user.ckey)
		return FALSE
	if(!user.MayRespawn())
		return FALSE
	if(jobban_isbanned(user, "pAI"))
		return FALSE
	if(!(user.client.prefs.read_preference(/datum/preference/numeric/human/be_special) & BE_PAI)) // be_special migrated
		return FALSE
	if(check_is_delayed(REF(user)))
		return FALSE
	if(check_is_already_pai(user.ckey))
		return FALSE
	if(user.client.prefs.read_preference(/datum/preference/text/pai_name) == PAI_UNSET) // Forbid unset name
		return FALSE
	return TRUE

/datum/world_service/pai/proc/check_is_delayed(ghost_ref)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(ghost_ref in asked)
		// ALLOW(cooldown): per-ghost ask cooldown table keyed by ref
		if(world.time < asked[ghost_ref] + PAI_DELAY_TIME)
			return TRUE
	return FALSE

/datum/world_service/pai/proc/check_is_already_pai(check_ckey)
	SHOULD_NOT_OVERRIDE(TRUE)
	return (check_ckey in GLOB.paikeys)

/datum/world_service/pai/proc/get_ghost_from_ref(ghost_ref)
	RETURN_TYPE(/mob/observer)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!ghost_ref)
		return null
	return locate_in_list(pai_ghosts, ghost_ref)

/datum/world_service/pai/proc/get_invite_list_data()
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)

	var/list/data = list()
	for(var/mob/observer/ghost as anything in pai_ghosts)
		if(!istype(ghost) || !ghost.client?.prefs)
			continue

		var/datum/preferences/pref = ghost.client.prefs
		var/datum/asset/spritesheet_batched/pai_icons/spritesheet = get_asset_datum(/datum/asset/spritesheet_batched/pai_icons)
		var/chassis = pref.read_preference(/datum/preference/text/pai_chassis)
		var/datum/pai_sprite/sprite_datum = GLOB.pai_service.chassis_data(chassis)
		var/css_class = sanitize_css_class_name("[sprite_datum.type]")
		UNTYPED_LIST_ADD(data, list(
				"ref" = REF(ghost),
				"name" = pref.read_preference(/datum/preference/text/pai_name),
				"gender" = pref.read_preference(/datum/preference/choiced/gender/biological), // Cannot use identifying yet due to byond limits
				"role" = TextPreview(pref.read_preference(/datum/preference/text/pai_role), 152),
				"ad" = TextPreview(pref.read_preference(/datum/preference/text/pai_ad), 244),
				"eyecolor" = pref.read_preference(/datum/preference/color/pai_eye_color),
				"chassis" = chassis,
				"emotion" = pref.read_preference(/datum/preference/text/pai_emotion),
				"sprite_datum_class" = css_class,
				"sprite_datum_size" = spritesheet.icon_size_id(css_class + "S"), // just get the south icon's size, the rest will be the same
			))
	return data

/datum/world_service/pai/proc/get_detailed_invite_data(ghost_ref)
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)

	var/mob/observer/ghost = get_ghost_from_ref(ghost_ref)
	if(!istype(ghost) || !ghost.client?.prefs)
		return null

	var/datum/preferences/pref = ghost.client.prefs
	var/datum/asset/spritesheet_batched/pai_icons/spritesheet = get_asset_datum(/datum/asset/spritesheet_batched/pai_icons)
	var/chassis = pref.read_preference(/datum/preference/text/pai_chassis)
	var/datum/pai_sprite/sprite_datum = GLOB.pai_service.chassis_data(chassis)
	var/css_class = sanitize_css_class_name("[sprite_datum.type]")
	return list(
			"ref" = ghost_ref,
			"name" = pref.read_preference(/datum/preference/text/pai_name),
			"gender" = pref.read_preference(/datum/preference/choiced/gender/biological), // Cannot use identifying yet due to byond limits
			// Description
			"role" = pref.read_preference(/datum/preference/text/pai_role),
			"description" = pref.read_preference(/datum/preference/text/pai_description),
			"ad" = pref.read_preference(/datum/preference/text/pai_ad),
			"comments" = pref.read_preference(/datum/preference/text/pai_comments),
			// Appearance
			"eyecolor" = pref.read_preference(/datum/preference/color/pai_eye_color),
			"chassis" = chassis,
			"emotion" = pref.read_preference(/datum/preference/text/pai_emotion),
			// Sprites
			"sprite_datum_class" = css_class,
			"sprite_datum_size" = spritesheet.icon_size_id(css_class + "S"), // just get the south icon's size, the rest will be the same
		)

/datum/world_service/pai/proc/invite_ghost(mob/inquirer, ghost_ref, obj/item/paicard/card)
	SHOULD_NOT_OVERRIDE(TRUE)
	// Is our card legal to inhabit?
	if(QDELETED(card) || card.pai || card.is_damage_critical())
		to_chat(inquirer, span_warning("This [card] can no longer be used to house a pAI."))
		return

	// Check if the ghost stopped existing
	var/mob/observer/ghost = get_ghost_from_ref(ghost_ref)
	if(!isobserver(ghost) || !ghost.client)
		to_chat(inquirer, span_warning("This pAI has gone offline."))
		return

	// Time delay if the ghost cancels your invite.
	var/ghost_key = REF(ghost) // keyed by ref text: a ghost-less timestamp table, not a relation
	if(check_is_delayed(ghost_key))
		to_chat(inquirer, span_notice("This pAI is responding to a request, but may become available again shortly..."))
		return
	asked[ghost_key] = world.time

	// Can't play, still respawning
	var/time_till_respawn = ghost.time_till_respawn()
	if(time_till_respawn == -1 || time_till_respawn)
		to_chat(inquirer, span_warning("This pAI is still downloading..."))
		return

	// Send it!
	to_chat(inquirer, span_info("A request has been sent!"))
	om_ask(ghost, /datum/om/prompt/choice/pai_invite, PROC_REF(pai_invite_answered), subject = card, inquirer = inquirer, ghost_ref = ghost_ref)

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
	if(!ghost.client || !isobserver(ghost) || GLOB.pai_service.get_ghost_from_ref(ghost_ref) != ghost)
		return "not that ghost" // Nice try smartass
	return null

/// The ghost's answer to a pAI invite.
/datum/world_service/pai/proc/pai_invite_answered(datum/om/prompt/choice/pai_invite/ask)
	var/mob/observer/ghost = ask.answerer
	pai_invite_answer(ask.inquirer, ghost, ask.subject, ask.choice, ghost.client)

/datum/world_service/pai/proc/pai_invite_answer(mob/inquirer, mob/observer/ghost, obj/item/paicard/card, response, client/target)
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
			GLOB.pai_service.block_pai_invites(REF(ghost))

	to_chat(inquirer, span_warning("The pAI denied the request."))

/datum/world_service/pai/proc/block_pai_invites(ghost_ref)
	SHOULD_NOT_OVERRIDE(TRUE)
	asked[ghost_ref] = world.time + 99 HOURS // We never want to be asked again

/datum/world_service/pai/proc/clear_pai_block_delay(ghost_ref)
	SHOULD_NOT_OVERRIDE(TRUE)
	asked -= ghost_ref

REL_LIST(/datum/world_service/pai, pai_ghosts)

#undef PAI_DELAY_TIME
