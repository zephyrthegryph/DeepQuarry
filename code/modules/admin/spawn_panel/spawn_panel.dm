#define WHERE_FLOOR_BELOW_MOB "Current location"
#define WHERE_SUPPLY_BELOW_MOB "Current location (droppod)"
#define WHERE_MOB_HAND "In own mob's hand"
#define WHERE_MARKED_OBJECT "At a marked object"
#define WHERE_IN_MARKED_OBJECT "In the marked object"
#define WHERE_TARGETED_LOCATION "Targeted location"
#define WHERE_TARGETED_LOCATION_POD "Targeted location (droppod)"
#define WHERE_TARGETED_MOB_HAND "In targeted mob's hand"

#define PRECISE_MODE_OFF "Off"
#define PRECISE_MODE_TARGET "Target"
#define PRECISE_MODE_MARK "Mark"
#define PRECISE_MODE_COPY "Copy"

#define OFFSET_ABSOLUTE "Absolute offset"
#define OFFSET_RELATIVE "Relative offset"

/*
	An instance of a /tg/UI™ Spawn Panel. Stores preferences, spawns things, controls the UI. Unique for each user (their ckey).
*/
/datum/spawnpanel
	/// Where and how the atom should be spawned.
	var/where_target_type = WHERE_FLOOR_BELOW_MOB
	/// The atom selected from the panel.
	/// The type path to spawn (the copy mode picks an object's type).
	var/selected_atom = null
	/// The icon selected for the atom from the panel.
	var/selected_atom_icon = null
	/// The icon state selected for the atom from the panel.
	var/selected_atom_icon_state = null
	/// Should selected icon/icon state override the initial ones? Added as an edge case to not replace animated GAGS icons.
	var/apply_icon_override = FALSE
	/// A list of icon states to display in preview panels.
	var/list/available_icon_states = null
	/// Override for the icon size of the spawned mob.
	var/atom_icon_size = 100
	/// How many atoms will be spawned at once.
	var/atom_amount = 1
	/// Custom atom name (leave `null` for initial).
	var/atom_name = null
	/// Custom atom description (leave `null` for initial).
	var/atom_desc = null
	/// Custom atom dir (leave `null` for `2`).
	var/atom_dir = 1
	/// An associative list of x-y-z offsets.
	var/offset = list()
	/// The pivot point for offsetting — relative or absolute.
	var/offset_type = OFFSET_RELATIVE
	/// Precise mode toggle. Used for build-mode-like spawning experience and targeting datums.
	var/precise_mode = PRECISE_MODE_OFF

/datum/spawnpanel/New()
	. = ..()
	offset = list("X" = 0, "Y" = 0, "Z" = 0)

DECLARE_UI(/datum/spawnpanel, "SpawnPanel")

/datum/spawnpanel/tgui_close(mob/user)
	. = ..()
	if (precise_mode && precise_mode != PRECISE_MODE_OFF)
		toggle_precise_mode(PRECISE_MODE_OFF, user)

DECLARE_UI_STATE(/datum/spawnpanel, ADMIN_STATE(R_SPAWN))

/datum/spawnpanel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!check_rights_for(ui.user.client, R_SPAWN))
		return FALSE
	return TRUE

UI_ACT(/datum/spawnpanel, "select-new-DMI", ui_act_select_new_dmi)
UI_ACT_PROC(/datum/spawnpanel, ui_act_select_new_dmi)
	var/icon/new_icon = input("Select a new icon file:", "Icon") as null|icon // ALLOW(scheduler): file uploads need the BYOND file dialog
	if(new_icon)
		selected_atom_icon = new_icon
		available_icon_states = icon_states(selected_atom_icon)
		if(!(selected_atom_icon_state in available_icon_states))
			selected_atom_icon_state = available_icon_states[1]
	return TRUE

UI_ACT(/datum/spawnpanel, "set-apply-icon-override", ui_act_set_apply_icon_override, UI_ARG_BOOL("value"))
UI_ACT_PROC(/datum/spawnpanel, ui_act_set_apply_icon_override)
	apply_icon_override = !!params["value"]
	return TRUE

UI_ACT(/datum/spawnpanel, "reset-DMI-icon", ui_act_reset_dmi_icon)
UI_ACT_PROC(/datum/spawnpanel, ui_act_reset_dmi_icon)
	selected_atom_icon = null
	selected_atom_icon_state = null
	if(selected_atom)
		var/atom/selected_type = selected_atom
		selected_atom_icon = initial(selected_type.icon)
		selected_atom_icon_state = initial(selected_type.icon_state)
		available_icon_states = icon_states(selected_atom_icon)
	else
		available_icon_states = list()
	return TRUE

UI_ACT(/datum/spawnpanel, "select-new-icon-state", ui_act_select_new_icon_state, UI_ARG_VALUE("new_state"))
UI_ACT_PROC(/datum/spawnpanel, ui_act_select_new_icon_state)
	selected_atom_icon_state = params["new_state"]
	return TRUE

UI_ACT(/datum/spawnpanel, "reset-icon-state", ui_act_reset_icon_state)
UI_ACT_PROC(/datum/spawnpanel, ui_act_reset_icon_state)
	selected_atom_icon_state = null
	if(selected_atom)
		var/atom/selected_type = selected_atom
		selected_atom_icon_state = initial(selected_type.icon_state)
	return TRUE

UI_ACT(/datum/spawnpanel, "set-icon-size", ui_act_set_icon_size, UI_ARG_VALUE("size"))
UI_ACT_PROC(/datum/spawnpanel, ui_act_set_icon_size)
	atom_icon_size = params["size"]
	return TRUE

UI_ACT(/datum/spawnpanel, "reset-icon-size", ui_act_reset_icon_size)
UI_ACT_PROC(/datum/spawnpanel, ui_act_reset_icon_size)
	atom_icon_size = 100
	return TRUE

UI_ACT(/datum/spawnpanel, "get-icon-states", ui_act_get_icon_states)
UI_ACT_PROC(/datum/spawnpanel, ui_act_get_icon_states)
	available_icon_states = icon_states(selected_atom_icon)
	return TRUE

UI_ACT(/datum/spawnpanel, "selected-atom-changed", ui_act_selected_atom_changed, UI_ARG_PATH("newObj", /datum))
UI_ACT_PROC(/datum/spawnpanel, ui_act_selected_atom_changed)
	var/path = params["newObj"]
	if(path)
		var/atom/temp_atom = path
		selected_atom_icon = initial(temp_atom.icon)
		selected_atom_icon_state = initial(temp_atom.icon_state)
		available_icon_states = icon_states(selected_atom_icon)
		selected_atom = temp_atom
	return TRUE

UI_ACT(/datum/spawnpanel, "create-atom-action", ui_act_create_atom_action, UI_ARG_NUM("atom_amount"), UI_ARG_VALUE("atom_icon_size"), UI_ARG_VALUE("atom_name"), UI_ARG_NUM("dir"), UI_ARG_VALUE("offset"), UI_ARG_VALUE("offset_type"), UI_ARG_VALUE("selected_atom_icon"), UI_ARG_VALUE("selected_atom_icon_state"), UI_ARG_VALUE("where_target_type"))
UI_ACT_PROC(/datum/spawnpanel, ui_act_create_atom_action)
	var/list/spawn_params = list(
		"selected_atom" = selected_atom,
		"offset" = params["offset"],
		"atom_dir" = params["dir"] || 1,
		"atom_amount" = params["atom_amount"] || 1,
		"atom_name" = params["atom_name"],
		"where_target_type" = params["where_target_type"] || WHERE_FLOOR_BELOW_MOB,
		"atom_icon_size" = params["atom_icon_size"],
		"offset_type" = params["offset_type"] || OFFSET_RELATIVE,
		"apply_icon_override" = apply_icon_override,
		)

	if(apply_icon_override)
		spawn_params["selected_atom_icon"] = selected_atom_icon
		spawn_params["selected_atom_icon_state"] = selected_atom_icon_state

	spawn_atom(spawn_params, ui.user)
	return TRUE

UI_ACT(/datum/spawnpanel, "toggle-precise-mode", ui_act_toggle_precise_mode, UI_ARG_TEXT("newPreciseType"), UI_ARG_TEXT("where_target_type"))
UI_ACT_PROC(/datum/spawnpanel, ui_act_toggle_precise_mode)
	var/precise_type = params["newPreciseType"]
	if(precise_type == PRECISE_MODE_TARGET && params["where_target_type"])
		where_target_type = params["where_target_type"]
	toggle_precise_mode(precise_type, ui.user)
	return TRUE

UI_ACT(/datum/spawnpanel, "update-settings", ui_act_update_settings, UI_ARG_NUM("atom_amount"), UI_ARG_NUM("atom_dir"), UI_ARG_NUM("atom_icon_size"), UI_ARG_VALUE("atom_name"), UI_ARG_LIST("offset"), UI_ARG_VALUE("offset_type"), UI_ARG_VALUE("selected_atom_icon"), UI_ARG_VALUE("selected_atom_icon_state"), UI_ARG_VALUE("where_target_type"))
UI_ACT_PROC(/datum/spawnpanel, ui_act_update_settings)
	if(params["atom_amount"])
		atom_amount = params["atom_amount"]
	if(params["atom_dir"])
		atom_dir = params["atom_dir"]
	if(params["offset"])
		var/list/temp_offset = params["offset"]
		offset["X"] = temp_offset[1]
		offset["Y"] = temp_offset[2]
		offset["Z"] = temp_offset[3]
	if(params["atom_name"])
		atom_name = params["atom_name"]
	if(params["where_target_type"])
		where_target_type = params["where_target_type"]
	if(params["offset_type"])
		offset_type = params["offset_type"]
	if(params["atom_icon_size"])
		atom_icon_size = params["atom_icon_size"]
	if(params["selected_atom_icon"])
		selected_atom_icon = params["selected_atom_icon"]
	if(params["selected_atom_icon_state"])
		selected_atom_icon_state = params["selected_atom_icon_state"]
	return TRUE

/datum/spawnpanel/proc/toggle_precise_mode(precise_type, mob/user)
	precise_mode = precise_type
	var/client/admin_client = user.client
	if (!admin_client)
		return

	if(admin_client.holder)
		rel_clear(admin_client.holder, nameof(/mob::click_intercept))

	if (precise_mode != PRECISE_MODE_OFF && admin_client.holder)
		rel_set(admin_client.holder, nameof(/mob::click_intercept), src)
		winset(admin_client, "mapwindow.map", "right-click=true")
	else
		winset(admin_client, "mapwindow.map", "right-click=false")

	/* Unimplemented
	var/mob/holder_mob = admin_client.mob
	holder_mob?.update_mouse_pointer()
	*/

/datum/spawnpanel/proc/InterceptClickOn(mob/user, params, atom/target)
	var/list/modifiers = params2list(params)
	var/left_click = GLOB.input_router.click_is(modifiers, TYPE_TABLE_GET(GLOB.input_router, primary_table), INPUT_ACTION_USE)
	var/right_click = GLOB.input_router.click_is(modifiers, TYPE_TABLE_GET(GLOB.input_router, secondary_table), INPUT_ACTION_ALTERNATE_SECONDARY)

	if(right_click)
		toggle_precise_mode(PRECISE_MODE_OFF, user)
		SStgui.update_uis(src)
		return TRUE

	if(left_click)
		if(istype(target,/atom/movable/screen))
			return FALSE

		var/turf/clicked_turf = get_turf(target)
		if(!clicked_turf)
			return FALSE

		switch(precise_mode)
			if(PRECISE_MODE_TARGET)
				var/list/spawn_params = list(
					"selected_atom" = selected_atom,
					"atom_amount" = atom_amount,
					"offset" = "0,0,0",
					"atom_dir" = atom_dir,
					"atom_name" = atom_name,
					"atom_desc" = atom_desc,
					"offset_type" = OFFSET_ABSOLUTE,
					"where_target_type" = where_target_type,
					"target" = target,
					"atom_icon_size" = atom_icon_size,
					"apply_icon_override" = apply_icon_override,
				)

				if(apply_icon_override)
					spawn_params["selected_atom_icon"] = selected_atom_icon
					spawn_params["selected_atom_icon_state"] = selected_atom_icon_state

				if(where_target_type == WHERE_TARGETED_LOCATION || where_target_type == WHERE_TARGETED_LOCATION_POD)
					spawn_params["X"] = clicked_turf.x
					spawn_params["Y"] = clicked_turf.y
					spawn_params["Z"] = clicked_turf.z

				spawn_atom(spawn_params, user)

			if(PRECISE_MODE_MARK)
				var/client/admin_client = user.client
				admin_client.mark_datum(target)
				to_chat(user, span_notice("Marked object: [icon2html(target, user)] [span_bold("[target]")]"))
				toggle_precise_mode(PRECISE_MODE_OFF, user)
				SStgui.update_uis(src)

			if(PRECISE_MODE_COPY)
				to_chat(user, span_notice("Picked object: [icon2html(target, user)] [span_bold("[target]")]"))
				selected_atom = target.type
				toggle_precise_mode(PRECISE_MODE_OFF, user)
				SStgui.update_uis(src)

		return TRUE

UI_DATA_REPLACE(/datum/spawnpanel, "icon=selected_atom_icon", "iconState=selected_atom_icon_state", "iconSize=atom_icon_size:num", "apply_icon_override:num", "precise_mode", "merge:ui_data_datum_spawnpanel{iconStates:list,selected_object:text}")

/// The computed part of /datum/spawnpanel's window data (declared on its UI_DATA row).
/datum/spawnpanel/proc/ui_data_datum_spawnpanel(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/data = list()
	var/list/states = list()
	if(available_icon_states)
		for(var/icon_state_name in available_icon_states)
			states += icon_state_name
	data["iconStates"] = states
	data["selected_object"] = selected_atom ? "[selected_atom]" : ""
	return data

/datum/spawnpanel/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/json/spawnpanel),
	)

#undef WHERE_FLOOR_BELOW_MOB
#undef WHERE_SUPPLY_BELOW_MOB
#undef WHERE_MOB_HAND
#undef WHERE_MARKED_OBJECT
#undef WHERE_IN_MARKED_OBJECT
#undef WHERE_TARGETED_LOCATION
#undef WHERE_TARGETED_LOCATION_POD
#undef WHERE_TARGETED_MOB_HAND
#undef PRECISE_MODE_OFF
#undef PRECISE_MODE_TARGET
#undef PRECISE_MODE_MARK
#undef PRECISE_MODE_COPY
#undef OFFSET_ABSOLUTE
#undef OFFSET_RELATIVE
