// preview rendering for play_mode = "robot" / "pai".
//
// For human mode, /datum/preferences/proc/update_preview_icon dresses a
// /mob/living/carbon/human/dummy/mannequin mannequin and flattens it via
// getFlatIcon → icon2base64 into character_preview_b64 (see core
// preferences.dm). For cyborg and pAI mode there's no carbon mannequin —
// the sprite comes straight from the chassis sprite datum / pai.dmi icon.
// These procs write character_preview_b64 directly so the React side can
// render the four-direction preview identically to the organic case.
//
// The hook into update_preview_icon lives in
// code/modules/mob/new_player/preferences_setup.dm — a branch that
// dispatches to update_robot_preview / update_pai_preview based on the
// play_mode pref before falling through to the human mannequin path.

/datum/preferences/proc/dq_resolve_robot_sprite()
	var/preferred_module = read_preference(/datum/preference/text/human/robot_module)
	if(!preferred_module || !(preferred_module in GLOB.robot_modules))
		return GLOB.dq_default_robot_sprite
	var/list/module_sprites = SSrobot_sprites?.cyborg_sprites_by_module?[preferred_module]
	if(!length(module_sprites))
		return GLOB.dq_default_robot_sprite
	var/preferred_chassis = read_preference(/datum/preference/text/human/robot_chassis)
	if(preferred_chassis)
		for(var/datum/robot_sprite/RS as anything in module_sprites)
			if(RS.name == preferred_chassis)
				return RS
	return module_sprites[1]

/datum/preferences/proc/dq_update_robot_preview(south_only = FALSE)
	var/datum/robot_sprite/sprite = dq_resolve_robot_sprite()
	if(!sprite || !sprite.sprite_icon || !sprite.sprite_icon_state)
		clear_character_previews()
		return
	LAZYINITLIST(character_preview_b64)
	var/list/dirs = south_only ? list("south" = SOUTH) : list("south" = SOUTH, "north" = NORTH, "east" = EAST, "west" = WEST)
	for(var/dir_key in dirs)
		var/dir = dirs[dir_key]
		// frame=1, moving=FALSE — without these, animated chassis states
		// (most dogborg variants are animated) come back as the entire frame
		// strip and icon2base64 dumps the whole sheet.
		var/icon/I = icon(sprite.sprite_icon, sprite.sprite_icon_state, dir = dir, frame = 1, moving = FALSE)
		character_preview_b64[dir_key] = icon2base64(I)
	var/bgstate = read_preference(/datum/preference/text/human/bgstate)
	if(bgstate)
		var/icon/bg_icon = icon('icons/effects/setup_backgrounds_vr.dmi', bgstate)
		character_preview_b64["bg"] = icon2base64(bg_icon)

/datum/preferences/proc/dq_update_pai_preview(south_only = FALSE)
	LAZYINITLIST(character_preview_b64)
	var/list/dirs = south_only ? list("south" = SOUTH) : list("south" = SOUTH, "north" = NORTH, "east" = EAST, "west" = WEST)
	for(var/dir_key in dirs)
		var/dir = dirs[dir_key]
		var/icon/I = icon('icons/mob/pai.dmi', "pai-repairbot", dir = dir, frame = 1, moving = FALSE)
		character_preview_b64[dir_key] = icon2base64(I)
	var/bgstate = read_preference(/datum/preference/text/human/bgstate)
	if(bgstate)
		var/icon/bg_icon = icon('icons/effects/setup_backgrounds_vr.dmi', bgstate)
		character_preview_b64["bg"] = icon2base64(bg_icon)

/// Lazy-init holder for the default cyborg sprite singleton (lookup happens
/// post-SSrobot_sprites init). Stored on GLOB rather than via a static-on-proc
/// so the species_picker.dm getter can share it.
GLOBAL_DATUM_INIT(dq_default_robot_sprite, /datum/robot_sprite/default, new)
