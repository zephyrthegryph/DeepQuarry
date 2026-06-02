// DQAdd — Cyborg chargen-driven spawn.
//
// The module-selection popup fires from two places: /mob/living/silicon/robot
// /LateInitialize (atom initialization) AND /mob/living/silicon/robot/Login
// (when a player slots in). We override LateInitialize here in a modular
// file; the Login() call site has its pick_module() replaced inline with a
// DQEdit marker (see code/modules/mob/living/silicon/robot/login.dm).
//
// apply_cyborg_chargen_prefs_or_default reads the chargen prefs (robot_module
// + robot_chassis), looks up the matching sprite, and runs apply_module +
// transform_module. icon_selected gets set; pick_module()'s early-out then
// short-circuits any later trigger.
//
// If the player has no module pref (default ""), an invalid module
// (renamed/removed since their last save), or no whitelist entry for a
// gated module, we silently fall back to a "Standard" module with the
// default chassis sprite — no popup. The player can change post-spawn via
// the in-game robotics console; we just don't pop a modal on them.

#define DQ_DEFAULT_CYBORG_MODULE "Standard"

/mob/living/silicon/robot/proc/apply_cyborg_chargen_prefs_or_default()
	if(icon_selected)
		return
	var/datum/preferences/prefs = client?.prefs
	var/preferred_module = prefs?.read_preference(/datum/preference/text/human/robot_module)
	if(!preferred_module || !(preferred_module in GLOB.robot_modules) || !is_borg_whitelisted(src, preferred_module))
		preferred_module = DQ_DEFAULT_CYBORG_MODULE
	var/list/module_sprites = SSrobot_sprites.get_module_sprites(preferred_module, src)
	if(!length(module_sprites))
		// Module exists but has no sprite list — shouldn't happen for Standard,
		// but if it does we still need to apply something. Fall through to the
		// module-only apply; sprite resolution will land on the SSrobot_sprites
		// default.
		var/obj/item/robot_module/module_type = GLOB.robot_modules[preferred_module]
		if(module_type)
			modtype = preferred_module
			module = new module_type(src)
			set_default_module_icon()
			transform_module()
		return
	var/preferred_chassis = prefs?.read_preference(/datum/preference/text/human/robot_chassis)
	var/datum/robot_sprite/chosen_sprite
	if(preferred_chassis)
		for(var/datum/robot_sprite/RS as anything in module_sprites)
			if(RS.name == preferred_chassis)
				chosen_sprite = RS
				break
	if(!chosen_sprite)
		chosen_sprite = module_sprites[1]
	apply_module(chosen_sprite, preferred_module)
	transform_module()

/mob/living/silicon/robot/LateInitialize()
	// DQEdit Start — upstream calls pick_module() here. If a client is
	// already attached (e.g. admin-spawned borg with a player riding), try
	// chargen-prefs apply; otherwise update_icon() and let the player's
	// eventual Login() take care of it. The popup never opens.
	if(client)
		apply_cyborg_chargen_prefs_or_default()
	update_icon()
	// DQEdit End

#undef DQ_DEFAULT_CYBORG_MODULE
