/datum/filter_editor
	var/tmp/target_handle

/datum/filter_editor/New(atom/target)
	src.target_handle = om_handle(target)

DECLARE_UI_STATE(/datum/filter_editor, ADMIN_STATE(R_VAREDIT))

DECLARE_UI(/datum/filter_editor, "Filteriffic")

/datum/filter_editor/tgui_static_data(mob/user)
	var/list/data = list()
	data["filter_info"] = GLOB.master_filter_info
	return data

UI_DATA_REPLACE(/datum/filter_editor, "merge:ui_data_datum_filter_editor{target_name:text,target_filter_data:unknown}")

/// The computed part of /datum/filter_editor's window data (declared on its UI_DATA row).
/datum/filter_editor/proc/ui_data_datum_filter_editor(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["target_name"] = target().name
	data["target_filter_data"] = target().filter_data
	return data

UI_ACT(/datum/filter_editor, "add_filter", ui_act_add_filter, UI_ARG_TEXT("name"), UI_ARG_NUM("priority"), UI_ARG_VALUE("type"))
UI_ACT_PROC(/datum/filter_editor, ui_act_add_filter)
	var/target_name = params["name"]
	while(target().filter_data && target().filter_data[target_name])
		target_name = "[target_name]-dupe"
	target().add_filter(target_name, params["priority"], list("type" = params["type"]))
	. = TRUE

UI_ACT(/datum/filter_editor, "remove_filter", ui_act_remove_filter, UI_ARG_TEXT("name"))
UI_ACT_PROC(/datum/filter_editor, ui_act_remove_filter)
	target().remove_filter(params["name"])
	. = TRUE

UI_ACT(/datum/filter_editor, "rename_filter", ui_act_rename_filter, UI_ARG_TEXT("name"), UI_ARG_TEXT("new_name"))
UI_ACT_PROC(/datum/filter_editor, ui_act_rename_filter)
	var/list/filter_data = target().filter_data[params["name"]]
	target().remove_filter(params["name"])
	target().add_filter(params["new_name"], filter_data["priority"], filter_data)
	. = TRUE

UI_ACT(/datum/filter_editor, "edit_filter", ui_act_edit_filter, UI_ARG_VALUE("name"), UI_ARG_VALUE("new_filter"), UI_ARG_VALUE("priority"))
UI_ACT_PROC(/datum/filter_editor, ui_act_edit_filter)
	target().remove_filter(params["name"])
	target().add_filter(params["name"], params["priority"], params["new_filter"])
	. = TRUE

UI_ACT(/datum/filter_editor, "change_priority", ui_act_change_priority, UI_ARG_TEXT("name"), UI_ARG_NUM("new_priority"))
UI_ACT_PROC(/datum/filter_editor, ui_act_change_priority)
	var/new_priority = params["new_priority"]
	target().change_filter_priority(params["name"], new_priority)
	. = TRUE

UI_ACT(/datum/filter_editor, "transition_filter_value", ui_act_transition_filter_value, UI_ARG_TEXT("name"), UI_ARG_VALUE("new_data"))
UI_ACT_PROC(/datum/filter_editor, ui_act_transition_filter_value)
	target().transition_filter(params["name"], params["new_data"], 4)
	. = TRUE

UI_ACT(/datum/filter_editor, "modify_filter_value", ui_act_modify_filter_value, UI_ARG_TEXT("name"), UI_ARG_LIST("new_data"))
UI_ACT_PROC(/datum/filter_editor, ui_act_modify_filter_value)
	var/list/old_filter_data = target().filter_data[params["name"]]
	var/list/new_filter_data = old_filter_data.Copy()
	for(var/entry in params["new_data"])
		new_filter_data[entry] = params["new_data"][entry]
	for(var/entry in new_filter_data)
		if(entry == GLOB.master_filter_info[old_filter_data["type"]]["defaults"][entry])
			new_filter_data.Remove(entry)
	target().remove_filter(params["name"])
	target().add_filter(params["name"], old_filter_data["priority"], new_filter_data)
	. = TRUE

UI_ACT(/datum/filter_editor, "modify_color_value", ui_act_modify_color_value, UI_ARG_TEXT("name"))
UI_ACT_PROC(/datum/filter_editor, ui_act_modify_color_value)
	var/new_color = act_ask(usr, action, params, ui, "color", /datum/om/prompt/color, message = "Pick new filter color", title = "Filteriffic Colors!")
	if(new_color)
		target().transition_filter(params["name"], list("color" = new_color), 4)
		. = TRUE

UI_ACT(/datum/filter_editor, "modify_icon_value", ui_act_modify_icon_value, UI_ARG_TEXT("name"))
UI_ACT_PROC(/datum/filter_editor, ui_act_modify_icon_value)
	if(!GLOB.prompt_flow) // the icon questions re-run this action
		return prompt_flow(src, PROC_REF(tgui_act), args)
	var/icon/new_icon = pick_and_customize_icon(ui.user)
	if(new_icon)
		target().filter_data[params["name"]]["icon"] = new_icon
		target().update_filters()
		. = TRUE

UI_ACT(/datum/filter_editor, "mass_apply", ui_act_mass_apply, UI_ARG_PATH("path", /datum))
UI_ACT_PROC(/datum/filter_editor, ui_act_mass_apply)
	if(!check_rights_for(usr.client, R_FUN))
		to_chat(usr, span_userdanger("Stay in your lane, jannie."))
		return
	var/target_path = params["path"]
	if(!target_path)
		return
	var/filters_to_copy = target().filters
	var/filter_data_to_copy = target().filter_data
	var/count = 0
	// ALLOW(spatial): world search
	for(var/thing in world.contents)
		if(istype(thing, target_path))
			var/atom/thing_at = thing
			thing_at.filters = filters_to_copy
			thing_at.filter_data = filter_data_to_copy
			count += 1
	message_admins("LOCAL CLOWN [usr.ckey] JUST MASS FILTER EDITED [count] WITH PATH OF [params["path"]]!")
	log_admin("LOCAL CLOWN [usr.ckey] JUST MASS FILTER EDITED [count] WITH PATH OF [params["path"]]!")

/// LC-refs: the target this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/filter_editor/proc/target() as /atom
	return om_resolve(target_handle)
