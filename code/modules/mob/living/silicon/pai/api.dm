// The pAI system's API (code/modules/mob/living/silicon/pai/pai_service.dm declares the system).
//
//   SSpai.get_chassis_list() / chassis_data(name)                   the chassis sprites
//   SSpai.invite_valid(ghost) / invite_ghost(inquirer, ref, card)   candidate checks and the request
//   SSpai.get_invite_list_data() / get_detailed_invite_data(ref) / get_ghost_from_ref(ref)
//   SSpai.check_is_already_pai(ckey) / block_pai_invites(ref) / clear_pai_block_delay(ref)

/datum/system/pai/proc/get_chassis_list()
	RETURN_TYPE(/list/datum/pai_sprite)
	SHOULD_NOT_OVERRIDE(TRUE)
	return pai_chassis_sprites

/datum/system/pai/proc/chassis_data(id_name)
	RETURN_TYPE(/datum/pai_sprite)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!(id_name in pai_chassis_sprites))
		return pai_chassis_sprites[PAI_DEFAULT_CHASSIS]
	return pai_chassis_sprites[id_name]

/datum/system/pai/proc/invite_valid(mob/user)
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

/datum/system/pai/proc/invite_ghost(mob/inquirer, ghost_ref, obj/item/paicard/card)
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
	asked[REF(ghost)] = EXPIRY_AT(null, CLOCK_WORLD, 0)

	// Can't play, still respawning
	var/time_till_respawn = ghost.time_till_respawn()
	if(time_till_respawn == -1 || time_till_respawn)
		to_chat(inquirer, span_warning("This pAI is still downloading..."))
		return

	// Send it!
	to_chat(inquirer, span_info("A request has been sent!"))
	var/datum/prompt/choice/pai_invite/invite = open_request(src, /datum/prompt/choice/pai_invite, PROC_REF(pai_invite_answered), answerer = ghost, valid = PROC_REF(pai_invite_askable), title = "pAI Request", question = "[inquirer] is requesting a pAI personality. Would you like to play as a personal AI?", choices = list("Yes", "No", "Never for this round"), buttons = TRUE, ghost_ref = ghost_ref, timeout = 0)
	if(invite)
		rel_set(invite, nameof(invite.card), card)
		rel_set(invite, nameof(invite.inquirer), inquirer)

/datum/system/pai/proc/get_invite_list_data()
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)

	var/list/data = list()
	for(var/mob/observer/ghost as anything in pai_ghosts)
		if(!istype(ghost) || !ghost.client?.prefs)
			continue

		var/datum/preferences/pref = ghost.client.prefs
		var/datum/asset/spritesheet_batched/pai_icons/spritesheet = get_asset_datum(/datum/asset/spritesheet_batched/pai_icons)
		var/chassis = pref.read_preference(/datum/preference/text/pai_chassis)
		var/datum/pai_sprite/sprite_datum = SSpai.chassis_data(chassis)
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

/datum/system/pai/proc/get_detailed_invite_data(ghost_ref)
	RETURN_TYPE(/list)
	SHOULD_NOT_OVERRIDE(TRUE)

	var/mob/observer/ghost = get_ghost_from_ref(ghost_ref)
	if(!istype(ghost) || !ghost.client?.prefs)
		return null

	var/datum/preferences/pref = ghost.client.prefs
	var/datum/asset/spritesheet_batched/pai_icons/spritesheet = get_asset_datum(/datum/asset/spritesheet_batched/pai_icons)
	var/chassis = pref.read_preference(/datum/preference/text/pai_chassis)
	var/datum/pai_sprite/sprite_datum = SSpai.chassis_data(chassis)
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

/datum/system/pai/proc/get_ghost_from_ref(ghost_ref)
	RETURN_TYPE(/mob/observer)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(!ghost_ref)
		return null
	return locate_in_list(pai_ghosts, ghost_ref)

/datum/system/pai/proc/check_is_already_pai(check_ckey)
	SHOULD_NOT_OVERRIDE(TRUE)
	return (check_ckey in GLOB.paikeys)

/datum/system/pai/proc/block_pai_invites(ghost_ref)
	SHOULD_NOT_OVERRIDE(TRUE)
	asked[ghost_ref] = EXPIRY_AT(null, CLOCK_WORLD, 0) + 99 HOURS // We never want to be asked again

/datum/system/pai/proc/clear_pai_block_delay(ghost_ref)
	SHOULD_NOT_OVERRIDE(TRUE)
	asked -= ghost_ref
