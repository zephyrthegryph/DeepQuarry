/datum/filter_editor
	var/tmp/atom/target

/datum/filter_editor/New(atom/target)
	rel_set(src, nameof(target), target)

CAPABILITIES(/datum/filter_editor)
	interface("Filteriffic", rights = R_VAREDIT)
	op("add_filter", ui_act("add_filter", arg("name", schema_text(4096)), arg("priority", num()), arg("type")), then(PROC_REF(ui_act_add_filter)))
	op("remove_filter", ui_act("remove_filter", arg("name", schema_text(4096))), then(PROC_REF(ui_act_remove_filter)))
	op("rename_filter", ui_act("rename_filter", arg("name", schema_text(4096)), arg("new_name", schema_text(4096))), then(PROC_REF(ui_act_rename_filter)))
	op("edit_filter", ui_act("edit_filter", arg("name"), arg("new_filter"), arg("priority")), then(PROC_REF(ui_act_edit_filter)))
	op("change_priority", ui_act("change_priority", arg("name", schema_text(4096)), arg("new_priority", num())), then(PROC_REF(ui_act_change_priority)))
	op("transition_filter_value", ui_act("transition_filter_value", arg("name", schema_text(4096)), arg("new_data")), then(PROC_REF(ui_act_transition_filter_value)))
	op("modify_filter_value", ui_act("modify_filter_value", arg("name", schema_text(4096)), arg("new_data")), then(PROC_REF(ui_act_modify_filter_value)))
	op("modify_color_value", ui_act("modify_color_value", arg("name", schema_text(4096))), asks(/datum/prompt/color/filter_editor_colour, step = "color"), then(PROC_REF(ui_act_modify_color_value)))
	op("modify_icon_value", ui_act("modify_icon_value", arg("name", schema_text(4096))), then(PROC_REF(ui_act_modify_icon_value)))
	op("mass_apply", ui_act("mass_apply", arg("path", schema_path(/datum))), then(PROC_REF(ui_act_mass_apply)))

/datum/filter_editor/tgui_static_data(mob/user)
	var/list/data = list()
	data["filter_info"] = GLOB.master_filter_info
	return data

/// /datum/filter_editor's window data.
/datum/filter_editor/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["target_name"] = target().name
	data["target_filter_data"] = target().filter_data
	return data

/datum/filter_editor/proc/ui_act_add_filter(datum/act/op/A, name, priority, type)
	var/target_name = name
	while(target().filter_data && target().filter_data[target_name])
		target_name = "[target_name]-dupe"
	target().add_filter(target_name, priority, list("type" = type))
	. = TRUE

/datum/filter_editor/proc/ui_act_remove_filter(datum/act/op/A, name)
	target().remove_filter(name)
	. = TRUE

/datum/filter_editor/proc/ui_act_rename_filter(datum/act/op/A, name, new_name)
	var/list/filter_data = target().filter_data[name]
	target().remove_filter(name)
	target().add_filter(new_name, filter_data["priority"], filter_data)
	. = TRUE

/datum/filter_editor/proc/ui_act_edit_filter(datum/act/op/A, name, new_filter, priority)
	target().remove_filter(name)
	target().add_filter(name, priority, new_filter)
	. = TRUE

/datum/filter_editor/proc/ui_act_change_priority(datum/act/op/A, name, new_priority_arg)
	var/new_priority = new_priority_arg
	target().change_filter_priority(name, new_priority)
	. = TRUE

/datum/filter_editor/proc/ui_act_transition_filter_value(datum/act/op/A, name, new_data)
	target().transition_filter(name, new_data, 4)
	. = TRUE

/datum/filter_editor/proc/ui_act_modify_filter_value(datum/act/op/A, name, new_data)
	if(!isnull(new_data) && !islist(new_data))
		return FALSE
	var/list/old_filter_data = target().filter_data[name]
	var/list/new_filter_data = old_filter_data.Copy()
	for(var/entry in new_data)
		new_filter_data[entry] = new_data[entry]
	for(var/entry in new_filter_data)
		if(entry == GLOB.master_filter_info[old_filter_data["type"]]["defaults"][entry])
			new_filter_data.Remove(entry)
	target().remove_filter(name)
	target().add_filter(name, old_filter_data["priority"], new_filter_data)
	. = TRUE

/datum/filter_editor/proc/ui_act_modify_color_value(datum/act/op/A, name)
	return apply_filter_colour(name, A.step_value("color"))

/datum/filter_editor/proc/ui_act_modify_icon_value(datum/act/op/A, name)
	// the icon questions are a flow of their own (pick_and_customize_icon() parks on each)
	prompt_flow(src, PROC_REF(modify_icon_flow), list(A.actor, name))
	return TRUE

/datum/filter_editor/proc/modify_icon_flow(mob/user, name)
	var/icon/new_icon = pick_and_customize_icon(user)
	if(new_icon)
		target().filter_data[name]["icon"] = new_icon
		target().update_filters()
		. = TRUE

/datum/filter_editor/proc/ui_act_mass_apply(datum/act/op/A, path)
	var/mob/user = A.actor
	if(!check_rights_for(user?.client, R_FUN))
		to_chat(user, span_userdanger("Stay in your lane, jannie."))
		return
	var/target_path = path
	if(!target_path)
		return
	var/filters_to_copy = target().filters
	var/filter_data_to_copy = target().filter_data
	var/count = 0
	// ALLOW(spatial): a deliberate whole-world search: the target is not tied to any holder or z-level index
	for(var/thing in world.contents)
		if(istype(thing, target_path))
			var/atom/thing_at = thing
			thing_at.filters = filters_to_copy
			thing_at.filter_data = filter_data_to_copy
			count += 1
	message_admins("LOCAL CLOWN [user.ckey] JUST MASS FILTER EDITED [count] WITH PATH OF [path]!")
	log_admin("LOCAL CLOWN [user.ckey] JUST MASS FILTER EDITED [count] WITH PATH OF [path]!")

/// The target this refers to (a relation view: null once that is deleted).
/datum/filter_editor/proc/target() as /atom
	return target

/datum/filter_editor/proc/apply_filter_colour(filter_name, value)
	if(value)
		target().transition_filter(filter_name, list("color" = value), 0.4 SECONDS)
		return TRUE

/datum/prompt/color/filter_editor_colour
	question = "Pick new filter color"
	title = "Filteriffic Colors!"
	timeout = 0

/datum/prompt/color/filter_editor_colour/normalize(given)
	return given

/datum/prompt/color/filter_editor_colour/refusal(given)
	return null

/datum/prompt/color/filter_editor_colour/present(mob/user)
	var/datum/tgui_color_picker/prompt/picker = new(user, question, title, default || "#000000", timeout, TRUE, GLOB.tgui_always_state)
	rel_set(picker, nameof(picker.prompt), src)
	picker.tgui_interact(user)
	return picker
