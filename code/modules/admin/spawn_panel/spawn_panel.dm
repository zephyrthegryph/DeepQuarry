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
	var/list/offset
	/// The pivot point for offsetting — relative or absolute.
	var/offset_type = OFFSET_RELATIVE
	/// Precise mode toggle. Used for build-mode-like spawning experience and targeting datums.
	var/precise_mode = PRECISE_MODE_OFF

/datum/spawnpanel/New()
	. = ..()
	offset = list("X" = 0, "Y" = 0, "Z" = 0)

CAPABILITIES(/datum/spawnpanel)
	interface("SpawnPanel", rights = R_SPAWN)
	op("select-new-DMI", ui_act("select-new-DMI"), then(PROC_REF(ui_act_select_new_dmi)))
	op("set-apply-icon-override", ui_act("set-apply-icon-override", arg("value", bool())), then(PROC_REF(ui_act_set_apply_icon_override)))
	op("reset-DMI-icon", ui_act("reset-DMI-icon"), then(PROC_REF(ui_act_reset_dmi_icon)))
	op("select-new-icon-state", ui_act("select-new-icon-state", arg("new_state")), then(PROC_REF(ui_act_select_new_icon_state)))
	op("reset-icon-state", ui_act("reset-icon-state"), then(PROC_REF(ui_act_reset_icon_state)))
	op("set-icon-size", ui_act("set-icon-size", arg("size")), then(PROC_REF(ui_act_set_icon_size)))
	op("reset-icon-size", ui_act("reset-icon-size"), then(PROC_REF(ui_act_reset_icon_size)))
	op("get-icon-states", ui_act("get-icon-states"), then(PROC_REF(ui_act_get_icon_states)))
	op("selected-atom-changed", ui_act("selected-atom-changed", arg("newObj", schema_path(/datum))), then(PROC_REF(ui_act_selected_atom_changed)))
	op("create-atom-action", ui_act("create-atom-action", arg("atom_amount", num()), arg("atom_icon_size"), arg("atom_name"), arg("dir", num()), arg("offset"), arg("offset_type"), arg("selected_atom_icon"), arg("selected_atom_icon_state"), arg("where_target_type")), then(PROC_REF(ui_act_create_atom_action)))
	op("toggle-precise-mode", ui_act("toggle-precise-mode", arg("newPreciseType", schema_text(4096)), arg("where_target_type", schema_text(4096))), then(PROC_REF(ui_act_toggle_precise_mode)))
	op("update-settings", ui_act("update-settings", arg("atom_amount", num()), arg("atom_dir", num()), arg("atom_icon_size", num()), arg("atom_name"), arg("offset"), arg("offset_type"), arg("selected_atom_icon"), arg("selected_atom_icon_state"), arg("where_target_type")), then(PROC_REF(ui_act_update_settings)))

/datum/spawnpanel/tgui_close(mob/user)
	. = ..()
	if (precise_mode && precise_mode != PRECISE_MODE_OFF)
		toggle_precise_mode(PRECISE_MODE_OFF, user)

/datum/spawnpanel/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!check_rights_for(user.client, R_SPAWN))
		return FALSE
	return TRUE

/datum/spawnpanel/proc/ui_act_select_new_dmi(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/icon/new_icon = input("Select a new icon file:", "Icon") as null|icon // ALLOW(scheduler): file uploads need the BYOND file dialog
	if(new_icon)
		selected_atom_icon = new_icon
		available_icon_states = icon_states(selected_atom_icon)
		if(!(selected_atom_icon_state in available_icon_states))
			selected_atom_icon_state = available_icon_states[1]
	return TRUE

/datum/spawnpanel/proc/ui_act_set_apply_icon_override(datum/act/op/A, value)
	if(!ui_gate(A))
		return FALSE
	apply_icon_override = !!value
	return TRUE

/datum/spawnpanel/proc/ui_act_reset_dmi_icon(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
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

/datum/spawnpanel/proc/ui_act_select_new_icon_state(datum/act/op/A, new_state)
	if(!ui_gate(A))
		return FALSE
	selected_atom_icon_state = new_state
	return TRUE

/datum/spawnpanel/proc/ui_act_reset_icon_state(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	selected_atom_icon_state = null
	if(selected_atom)
		var/atom/selected_type = selected_atom
		selected_atom_icon_state = initial(selected_type.icon_state)
	return TRUE

/datum/spawnpanel/proc/ui_act_set_icon_size(datum/act/op/A, size)
	if(!ui_gate(A))
		return FALSE
	atom_icon_size = size
	return TRUE

/datum/spawnpanel/proc/ui_act_reset_icon_size(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	atom_icon_size = 100
	return TRUE

/datum/spawnpanel/proc/ui_act_get_icon_states(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	available_icon_states = icon_states(selected_atom_icon)
	return TRUE

/datum/spawnpanel/proc/ui_act_selected_atom_changed(datum/act/op/A, newObj)
	if(!ui_gate(A))
		return FALSE
	var/path = newObj
	if(path)
		var/atom/temp_atom = path
		selected_atom_icon = initial(temp_atom.icon)
		selected_atom_icon_state = initial(temp_atom.icon_state)
		available_icon_states = icon_states(selected_atom_icon)
		selected_atom = temp_atom
	return TRUE

/datum/spawnpanel/proc/ui_act_create_atom_action(datum/act/op/A, atom_amount, atom_icon_size, atom_name, dir, offset, offset_type, selected_atom_icon_arg, selected_atom_icon_state_arg, where_target_type)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/list/spawn_params = list(
		"selected_atom" = selected_atom,
		"offset" = offset,
		"atom_dir" = dir || 1,
		"atom_amount" = atom_amount || 1,
		"atom_name" = atom_name,
		"where_target_type" = where_target_type || WHERE_FLOOR_BELOW_MOB,
		"atom_icon_size" = atom_icon_size,
		"offset_type" = offset_type || OFFSET_RELATIVE,
		"apply_icon_override" = apply_icon_override,
		)

	if(apply_icon_override)
		spawn_params["selected_atom_icon"] = selected_atom_icon
		spawn_params["selected_atom_icon_state"] = selected_atom_icon_state

	spawn_atom(spawn_params, user)
	return TRUE

/datum/spawnpanel/proc/ui_act_toggle_precise_mode(datum/act/op/A, newPreciseType, where_target_type_arg)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/precise_type = newPreciseType
	if(precise_type == PRECISE_MODE_TARGET && where_target_type_arg)
		where_target_type = where_target_type_arg
	toggle_precise_mode(precise_type, user)
	return TRUE

/datum/spawnpanel/proc/ui_act_update_settings(datum/act/op/A, atom_amount_arg, atom_dir_arg, atom_icon_size_arg, atom_name_arg, offset_arg, offset_type_arg, selected_atom_icon_arg, selected_atom_icon_state_arg, where_target_type_arg)
	if(!ui_gate(A))
		return FALSE
	if(!isnull(offset_arg) && !islist(offset_arg))
		return FALSE
	if(atom_amount_arg)
		atom_amount = atom_amount_arg
	if(atom_dir_arg)
		atom_dir = atom_dir_arg
	if(offset_arg)
		var/list/temp_offset = offset_arg
		offset["X"] = temp_offset[1]
		offset["Y"] = temp_offset[2]
		offset["Z"] = temp_offset[3]
	if(atom_name_arg)
		atom_name = atom_name_arg
	if(where_target_type_arg)
		where_target_type = where_target_type_arg
	if(offset_type_arg)
		offset_type = offset_type_arg
	if(atom_icon_size_arg)
		atom_icon_size = atom_icon_size_arg
	if(selected_atom_icon_arg)
		selected_atom_icon = selected_atom_icon_arg
	if(selected_atom_icon_state_arg)
		selected_atom_icon_state = selected_atom_icon_state_arg
	return TRUE

/datum/spawnpanel/proc/toggle_precise_mode(precise_type, mob/user)
	precise_mode = precise_type
	var/client/admin_client = user.client
	if (!admin_client)
		return

	if(admin_client.admin_datum())
		rel_clear(admin_client.admin_datum(), nameof(/mob::click_intercept))

	if (precise_mode != PRECISE_MODE_OFF && admin_client.admin_datum())
		rel_set(admin_client.admin_datum(), nameof(/mob::click_intercept), src)
		winset(admin_client, SKIN_MAP, "right-click=true")
	else
		winset(admin_client, SKIN_MAP, "right-click=false")

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

/datum/spawnpanel/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["icon"] = selected_atom_icon
	data["iconState"] = selected_atom_icon_state
	data["iconSize"] = atom_icon_size
	data["apply_icon_override"] = apply_icon_override
	data["precise_mode"] = precise_mode
	var/list/merged_1 = ui_data_datum_spawnpanel(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /datum/spawnpanel's window data.
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
