// Cyborg chassis + module picker editor (Looks tab, robot mode).
//
// Lives in appearance/chassis. The category/group filter in
// /datum/preference_middleware/character_setup hides this in human mode.
//
// Sends per-chassis thumbnail refs (icon REF + icon_state) for the React
// <ColorizedImage> component so the chassis picker can show actual sprites
// in its fullscreen grid, not just text.

/datum/preference_editor/robot_chassis
	key = "robot_chassis"
	category = "appearance"
	group = "chassis"
	sort_order = 5
	display_name = "Cyborg Chassis"
	pref_keys = list("robot_module", "robot_chassis")
	// Catalog payload gates on play_mode (returns an empty stub for humans/pAIs).
	static_invalidator_keys = list("play_mode")

/datum/preference_editor/robot_chassis/build_ui_data(datum/preferences/preferences)
	return list(
		"module" = preferences.read_preference(/datum/preference/text/human/robot_module),
		"chassis" = preferences.read_preference(/datum/preference/text/human/robot_chassis),
	)

/datum/preference_editor/robot_chassis/build_ui_static_data(datum/preferences/preferences)
	// Humans never see this editor (the middleware hides the chassis group in
	// human mode). Return an empty stub so we don't iterate ~300 chassis
	// sprites + their REFs on every static_data build for non-robot players.
	var/play_mode = preferences.read_preference(/datum/preference/text/human/play_mode) || "human"
	if(play_mode != "robot")
		return list(
			"all_modules" = list(),
			"chassis_by_module" = list(),
			"chassis_thumbs" = list(),
		)
	var/list/all_modules = list()
	var/list/chassis_by_module = list()
	// {chassis_name -> {icon: REF, icon_state: state}}
	var/list/chassis_thumbs = list()
	for(var/module_name in GLOB.robot_modules)
		all_modules += module_name
		var/list/chassis_names = list()
		var/list/sprites = SSrobot_sprites.cyborg_sprites_by_module[module_name]
		if(islist(sprites))
			for(var/datum/robot_sprite/RS as anything in sprites)
				chassis_names += RS.name
				if(RS.sprite_icon && RS.sprite_icon_state)
					// Multiple modules may share a chassis name (e.g. "Default"). Last
					// write wins; for chargen-preview purposes that's fine since the
					// thumbnail's just a hint, the actual spawned sprite is resolved
					// in apply_cyborg_chargen_prefs by (module, chassis) tuple.
					chassis_thumbs[RS.name] = list(
						"icon" = "[REF(RS.sprite_icon)]",
						"icon_state" = RS.sprite_icon_state,
					)
		chassis_by_module[module_name] = chassis_names
	return list(
		"all_modules" = all_modules,
		"chassis_by_module" = chassis_by_module,
		"chassis_thumbs" = chassis_thumbs,
	)

/datum/preference_editor/robot_chassis/handle_action(datum/preferences/preferences, action, list/params, mob/user)
	switch(action)
		if("set_module")
			var/value = params["value"]
			if(value && !(value in GLOB.robot_modules))
				return PREF_UPDATE_REJECTED
			preferences.update_preference_by_type(/datum/preference/text/human/robot_module, value || "")
			// Reset chassis when the module changes — the previously-chosen sprite
			// may not belong to the new module's catalog.
			preferences.update_preference_by_type(/datum/preference/text/human/robot_chassis, "")
			return PREF_UPDATE_ACCEPTED
		if("set_chassis")
			preferences.update_preference_by_type(/datum/preference/text/human/robot_chassis, params["value"] || "")
			return PREF_UPDATE_ACCEPTED
	return PREF_UPDATE_UNCHANGED
