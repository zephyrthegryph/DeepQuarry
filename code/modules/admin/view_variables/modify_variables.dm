GLOBAL_LIST_INIT(VVlocked, list("vars", "datum_flags", "client", "mob")) //Requires DEBUG
GLOBAL_PROTECT(VVlocked)
GLOBAL_LIST_INIT(VVicon_edit_lock, list("icon", "icon_state", "overlays", "underlays")) //Requires DEBUG or FUN
GLOBAL_PROTECT(VVicon_edit_lock)
GLOBAL_LIST_INIT(VVckey_edit, list("key", "ckey")) //Requires DEBUG or SPAWN
GLOBAL_PROTECT(VVckey_edit)
GLOBAL_LIST_INIT(VVpixelmovement, list("bound_x", "bound_y", "step_x", "step_y", "step_size", "bound_height", "bound_width", "bounds")) //No editing ever.
GLOBAL_PROTECT(VVpixelmovement)

/// One View Variables value asked on its own: `pick_params` are the value picker's settings (its vars, by name). The answer is get("picked").
/datum/ask_sequence/admin/vv_value
	var/list/pick_params

/datum/ask_sequence/admin/vv_value/initial_steps()
	return list(TYPE_PROC_REF(/client, vv_value_ask))

/client/proc/vv_value_ask(datum/ask_sequence/admin/vv_value/asked)
	return asked.ask_child(/datum/ask_sequence/picker/vv_pick, "picked", asked.pick_params)

/// The direction a number reads as, said to the admin ("If a direction, direction is: ...").
/client/proc/vv_say_direction(value)
	var/dir_text = ""
	if(value > 0 && value < 16)
		if(value & 1)
			dir_text += "NORTH"
		if(value & 2)
			dir_text += "SOUTH"
		if(value & 4)
			dir_text += "EAST"
		if(value & 8)
			dir_text += "WEST"

	if(dir_text)
		to_chat(src, "If a direction, direction is: [dir_text]", confidential = TRUE)

// ---------------------------------------------------------------- adding to a list

/// View Variables adding an entry to a list. `target_list` is the list, `objectvar` the var of the subject that holds it (null subject: a loose list).
/datum/ask_sequence/admin/vv_list_add
	var/list/target_list
	var/original_name
	var/objectvar
	var/has_object = FALSE
	var/associate

/datum/ask_sequence/admin/vv_list_add/initial_steps()
	return list(
		TYPE_PROC_REF(/client, vv_add_pick),
		TYPE_PROC_REF(/client, vv_add_parse),
		question_step("associate", /datum/prompt/choice, question = "Would you like to associate a value with the list entry?", choices = list("Yes","No"), buttons = TRUE),
		TYPE_PROC_REF(/client, vv_add_assoc_pick),
		TYPE_PROC_REF(/client, vv_add_assoc_parse))

/client/proc/mod_list_add(list/L, atom/O, original_name, objectvar)
	ask_admin(/datum/ask_sequence/admin/vv_list_add, O, null, PROC_REF(vv_add_apply), list("target_list" = L, "original_name" = original_name, "objectvar" = objectvar, "has_object" = !isnull(O)))

/client/proc/vv_add_pick(datum/ask_sequence/admin/vv_list_add/asked)
	if(asked.has_object && !asked.subject())
		return ASK_STOP
	return asked.ask_child(/datum/ask_sequence/picker/vv_pick, "picked", list("restricted_classes" = list(VV_RESTORE_DEFAULT)))

/client/proc/vv_add_parse(datum/ask_sequence/admin/vv_list_add/asked)
	var/list/picked = asked.get("picked")
	var/class = picked["class"]
	if(!class)
		return ASK_STOP
	if(class == VV_TEXT || class == VV_MESSAGE)
		return asked.ask_child(/datum/ask_sequence/picker/parse_vars, "parsed", list("source_w" = rerun_wrap(asked.subject()), "source_text" = picked["value"]))
	return null

/client/proc/vv_add_assoc_pick(datum/ask_sequence/admin/vv_list_add/asked)
	if(asked.get("associate") != "Yes")
		return null
	return asked.ask_child(/datum/ask_sequence/picker/vv_pick, "assoc_picked", list("restricted_classes" = list(VV_RESTORE_DEFAULT)))

/client/proc/vv_add_assoc_parse(datum/ask_sequence/admin/vv_list_add/asked)
	if(asked.get("associate") != "Yes")
		return null
	var/list/picked = asked.get("assoc_picked")
	var/class = picked["class"]
	if(!class)
		return ASK_STOP
	if(class == VV_TEXT || class == VV_MESSAGE)
		return asked.ask_child(/datum/ask_sequence/picker/parse_vars, "assoc_parsed", list("source_w" = rerun_wrap(asked.subject()), "source_text" = picked["value"]))
	return null

/client/proc/vv_add_apply(datum/ask_sequence/admin/vv_list_add/asked)
	var/atom/O = asked.subject()
	if(asked.has_object && !O)
		return
	var/list/L = asked.target_list
	var/original_name = asked.original_name
	var/objectvar = asked.objectvar
	var/list/picked = asked.get("picked")
	var/class = picked["class"]
	var/var_value = picked["value"]
	if(class == VV_TEXT || class == VV_MESSAGE)
		var_value = vv_substitute_vars(var_value, asked.get("parsed"), O)

	var/list/assoc
	if(asked.get("associate") == "Yes")
		var/list/assoc_picked = asked.get("assoc_picked")
		var/assoc_value = assoc_picked["value"]
		if(assoc_picked["class"] == VV_TEXT || assoc_picked["class"] == VV_MESSAGE)
			assoc_value = vv_substitute_vars(assoc_value, asked.get("assoc_parsed"), O)
		assoc = list("value" = assoc_value)

	if (O)
		L = L.Copy()

	L += list(var_value) //var_value could be a list
	if(assoc)
		L[var_value] = assoc["value"]
	if (O)
		if (O.vv_edit_var(objectvar, L) == FALSE)
			to_chat(src, "Your edit was rejected by the object.", confidential = TRUE)
			return
	log_world("### ListVarEdit by [src]: [(O ? O.type : "/list")] [objectvar]: ADDED=[var_value]")
	log_admin("[key_name(src)] modified [original_name]'s [objectvar]: ADDED=[var_value]")
	message_admins("[key_name_admin(src)] modified [original_name]'s [objectvar]: ADDED=[var_value]")

// ---------------------------------------------------------------- editing a list

/// View Variables editing one entry of a list (or choosing the entry first). `target_list` is the list, `objectvar` the var of the subject that holds it (null subject: a loose
/// list), `index` the entry when it is known.
/datum/ask_sequence/admin/vv_list
	var/list/target_list
	var/original_name
	var/objectvar
	var/has_object = FALSE
	var/index
	var/autodetect_class = FALSE
	var/list/names
	var/long
	var/entry
	var/which
	var/assoc = 0
	var/assoc_key
	var/old_assoc_value
	var/original_var

/datum/ask_sequence/admin/vv_list/initial_steps()
	return list(
		TYPE_PROC_REF(/client, vv_list_ask_long),
		TYPE_PROC_REF(/client, vv_list_read_long),
		TYPE_PROC_REF(/client, vv_list_ask_entry),
		TYPE_PROC_REF(/client, vv_list_read_entry),
		question_step("which", /datum/prompt/choice, question = "Do you want to edit the key or its assigned value?", title = "Associated List", choices = list("Key", "Assigned Value", "Cancel"), buttons = TRUE),
		TYPE_PROC_REF(/client, vv_list_prepare),
		TYPE_PROC_REF(/client, vv_list_parse))

/client/proc/mod_list(list/L, atom/O, original_name, objectvar, index, autodetect_class = FALSE)
	if(!admin_require(src, R_VAREDIT, "mod_list", TRUE))
		return
	if(!istype(L, /list))
		to_chat(src, "Not a List.", confidential = TRUE)
		return
	ask_admin(/datum/ask_sequence/admin/vv_list, O, null, PROC_REF(vv_list_apply), list("target_list" = L, "original_name" = original_name, "objectvar" = objectvar, "has_object" = !isnull(O), "index" = index, "autodetect_class" = autodetect_class))

/client/proc/vv_list_ask_long(datum/ask_sequence/admin/vv_list/asked)
	if(asked.has_object && !asked.subject())
		return ASK_STOP
	if(!admin_require(src, R_VAREDIT, "mod_list", TRUE))
		return ASK_STOP
	if(length(asked.target_list) > 1000)
		return question_step("long", /datum/prompt/choice, question = "The list you're trying to edit is very long, continuing may crash the server.", title = "Warning", choices = list("Continue", "Abort"), buttons = TRUE)
	return null

/client/proc/vv_list_read_long(datum/ask_sequence/admin/vv_list/asked)
	if(length(asked.target_list) > 1000 && asked.long != "Continue")
		return ASK_STOP
	return null

/// The entries of the list by name, for picking one.
/client/proc/vv_list_entry_names(list/L)
	var/is_normal_list = IS_NORMAL_LIST(L)
	var/list/names = list()
	for (var/i in 1 to L.len)
		var/entry_key = L[i]
		var/value
		if (is_normal_list && !isnum(entry_key))
			value = L[entry_key]
		if (value == null)
			value = "null"
		names["#[i] [entry_key] = [value]"] = i
	return names

/client/proc/vv_list_ask_entry(datum/ask_sequence/admin/vv_list/asked)
	if(asked.index)
		return null
	asked.names = vv_list_entry_names(asked.target_list)
	return question_step("entry", /datum/prompt/choice, question = "Which var?", title = "Var", choices = asked.names + "(ADD VAR)" + "(CLEAR NULLS)" + "(CLEAR DUPES)" + "(SHUFFLE)")

/// The entry picked, or one of the whole-list actions (done at once; they end the questions).
/client/proc/vv_list_read_entry(datum/ask_sequence/admin/vv_list/asked)
	if(!asked.index)
		var/atom/O = asked.subject()
		var/list/L = asked.target_list
		var/original_name = asked.original_name
		var/objectvar = asked.objectvar
		var/variable = asked.entry

		if(variable == "(ADD VAR)")
			mod_list_add(L, O, original_name, objectvar)
			return ASK_STOP

		if(variable == "(CLEAR NULLS)")
			L = L.Copy()
			list_clear_nulls(L)
			if (!O.vv_edit_var(objectvar, L))
				to_chat(src, "Your edit was rejected by the object.", confidential = TRUE)
				return ASK_STOP
			log_world("### ListVarEdit by [src]: [O.type] [objectvar]: CLEAR NULLS")
			log_admin("[key_name(src)] modified [original_name]'s [objectvar]: CLEAR NULLS")
			message_admins("[key_name_admin(src)] modified [original_name]'s list [objectvar]: CLEAR NULLS")
			return ASK_STOP

		if(variable == "(CLEAR DUPES)")
			L = uniqueList(L)
			if (!O.vv_edit_var(objectvar, L))
				to_chat(src, "Your edit was rejected by the object.", confidential = TRUE)
				return ASK_STOP
			log_world("### ListVarEdit by [src]: [O.type] [objectvar]: CLEAR DUPES")
			log_admin("[key_name(src)] modified [original_name]'s [objectvar]: CLEAR DUPES")
			message_admins("[key_name_admin(src)] modified [original_name]'s list [objectvar]: CLEAR DUPES")
			return ASK_STOP

		if(variable == "(SHUFFLE)")
			L = shuffle(L)
			if (!O.vv_edit_var(objectvar, L))
				to_chat(src, "Your edit was rejected by the object.", confidential = TRUE)
				return ASK_STOP
			log_world("### ListVarEdit by [src]: [O.type] [objectvar]: SHUFFLE")
			log_admin("[key_name(src)] modified [original_name]'s [objectvar]: SHUFFLE")
			message_admins("[key_name_admin(src)] modified [original_name]'s list [objectvar]: SHUFFLE")
			return ASK_STOP

		asked.index = asked.names[variable]

	if (asked.index == null)
		return ASK_STOP
	return null

/// The entry and which part of it are known: says what it holds and asks for the new value.
/client/proc/vv_list_prepare(datum/ask_sequence/admin/vv_list/asked)
	if (isnull(asked.which) || asked.which == "Cancel")
		return ASK_STOP
	var/list/L = asked.target_list
	var/index = asked.index
	var/is_normal_list = IS_NORMAL_LIST(L)
	var/objectvar = asked.objectvar
	var/assoc = 0
	var/assoc_key
	if (asked.which == "Assigned Value")
		assoc = 1
		assoc_key = L[index]
	var/default
	var/variable
	var/old_assoc_value //EXPERIMENTAL - Keep old associated value while modifying key, if any
	if(is_normal_list)
		if (assoc)
			variable = L[assoc_key]
		else
			variable = L[index]
			//EXPERIMENTAL - Keep old associated value while modifying key, if any
			if(IS_VALID_ASSOC_KEY(variable))
				var/found = L[variable]
				if(!isnull(found))
					old_assoc_value = found
			//

	default = vv_get_class(objectvar, variable)

	to_chat(src, "Variable appears to be " + span_bold("[uppertext(default)]") + ".", confidential = TRUE)

	to_chat(src, "Variable contains: [variable]", confidential = TRUE)

	if(default == VV_NUM)
		vv_say_direction(variable)

	asked.assoc = assoc
	asked.assoc_key = assoc_key
	asked.old_assoc_value = old_assoc_value
	asked.original_var = variable

	if(asked.autodetect_class)
		if (default == VV_TEXT)
			default = VV_MESSAGE
	return asked.ask_child(/datum/ask_sequence/picker/vv_pick, "picked", list("default_class" = default, "current_value" = variable, "restricted_classes" = list(VV_RESTORE_DEFAULT), "extra_classes" = list(VV_LIST, "DELETE FROM LIST")))

/client/proc/vv_list_parse(datum/ask_sequence/admin/vv_list/asked)
	var/list/picked = asked.get("picked")
	var/class = picked["class"]
	if (!class)
		return ASK_STOP
	if(class == VV_MESSAGE)
		class = VV_TEXT
	if(class == VV_TEXT)
		return asked.ask_child(/datum/ask_sequence/picker/parse_vars, "parsed", list("source_w" = rerun_wrap(asked.subject()), "source_text" = picked["value"]))
	return null

/client/proc/vv_list_apply(datum/ask_sequence/admin/vv_list/asked)
	var/atom/O = asked.subject()
	if(asked.has_object && !O)
		return
	var/list/L = asked.target_list
	var/index = asked.index
	var/objectvar = asked.objectvar
	var/original_name = asked.original_name
	var/assoc = asked.assoc
	var/assoc_key = asked.assoc_key
	var/old_assoc_value = asked.old_assoc_value
	var/original_var = asked.original_var
	var/is_normal_list = IS_NORMAL_LIST(L)
	var/list/picked = asked.get("picked")
	var/class = picked["class"]
	var/new_var = picked["value"]

	if (O)
		L = L.Copy()

	if(class == VV_MESSAGE)
		class = VV_TEXT

	switch(class) //Spits a runtime error if you try to modify an entry in the contents list. Dunno how to fix it, yet.
		if(VV_LIST)
			mod_list(asked.original_var, O, original_name, objectvar)
			return

		if("DELETE FROM LIST")
			L.Cut(index, index+1)
			if (O)
				if (!O.vv_edit_var(objectvar, L))
					to_chat(src, "Your edit was rejected by the object.", confidential = TRUE)
					return
			log_world("### ListVarEdit by [src]: [O.type] [objectvar]: REMOVED=[html_encode("[original_var]")]")
			log_admin("[key_name(src)] modified [original_name]'s [objectvar]: REMOVED=[original_var]")
			message_admins("[key_name_admin(src)] modified [original_name]'s [objectvar]: REMOVED=[original_var]")
			return

		if(VV_TEXT)
			new_var = vv_substitute_vars(new_var, asked.get("parsed"), O)

	if(is_normal_list)
		if(assoc)
			L[assoc_key] = new_var
		else
			L[index] = new_var
			if(!isnull(old_assoc_value) && IS_VALID_ASSOC_KEY(new_var))
				L[new_var] = old_assoc_value
	if (O)
		if (O.vv_edit_var(objectvar, L) == FALSE)
			to_chat(src, "Your edit was rejected by the object.", confidential = TRUE)
			return
	log_world("### ListVarEdit by [src]: [(O ? O.type : "/list")] [objectvar]: [original_var]=[new_var]")
	log_admin("[key_name(src)] modified [original_name]'s [objectvar]: [original_var]=[new_var]")
	message_admins("[key_name_admin(src)] modified [original_name]'s varlist [objectvar]: [original_var]=[new_var]")

/proc/vv_varname_lockcheck(param_var_name)
	if(param_var_name in GLOB.VVlocked)
		if(!check_rights(R_DEBUG))
			return FALSE
	if(param_var_name in GLOB.VVckey_edit)
		if(!check_rights(R_SPAWN|R_DEBUG))
			return FALSE
	if(param_var_name in GLOB.VVicon_edit_lock)
		if(!check_rights(R_FUN|R_DEBUG))
			return FALSE
	return TRUE

// ---------------------------------------------------------------- editing a variable

/// View Variables editing one variable of a datum (the subject). `variable` is the var when the starter named it. `edit_displays`: the open View Variables window's name,
/// dir, ckey and real_name rows are refreshed after the edit.
/datum/ask_sequence/admin/vv_edit
	var/variable
	var/autodetect_class = 0
	var/edit_displays = FALSE

/datum/ask_sequence/admin/vv_edit/initial_steps()
	return list(
		TYPE_PROC_REF(/client, vv_edit_ask_var),
		TYPE_PROC_REF(/client, vv_edit_pick),
		TYPE_PROC_REF(/client, vv_edit_parse))

/client/proc/modify_variables(atom/O, param_var_name = null, autodetect_class = 0, edit_displays = FALSE)
	if(!admin_require(src, R_VAREDIT, "modify_variables", TRUE))
		return

	var/variable

	if(param_var_name)
		if(!(param_var_name in O.vars))
			if(sparse_slot_named(O, param_var_name))
				param_var_name = sparse_slot_label(sparse_slot_named(O, param_var_name))
			else if(type_trait_field_named(O, param_var_name))
				return modify_trait_field(O, param_var_name)
			to_chat(src, "A variable with this name ([param_var_name]) doesn't exist in this datum ([O])", confidential = TRUE)
			return
		variable = param_var_name

	ask_admin(/datum/ask_sequence/admin/vv_edit, O, null, PROC_REF(vv_edit_apply), list("variable" = variable, "autodetect_class" = autodetect_class, "edit_displays" = edit_displays))

/client/proc/vv_edit_ask_var(datum/ask_sequence/admin/vv_edit/asked)
	var/datum/O = asked.subject()
	if(!O || !admin_require(src, R_VAREDIT, "modify_variables", TRUE))
		return ASK_STOP
	if(asked.variable)
		return null
	var/list/names = list()
	for (var/V in O.vars)
		names += V
	for(var/slot_label in sparse_slots_of(O))
		names += slot_label

	names = sortList(names)

	return question_step("variable", /datum/prompt/choice, question = "Which var?", title = "Var", choices = names)

/client/proc/vv_edit_pick(datum/ask_sequence/admin/vv_edit/asked)
	var/datum/O = asked.subject()
	var/variable = asked.variable
	if(!O || !variable)
		return ASK_STOP

	if(!O.can_vv_get(variable))
		return ASK_STOP

	var/var_value = vv_var_value(O, variable)
	if(!vv_varname_lockcheck(variable))
		return ASK_STOP

	var/default = vv_get_class(variable, var_value)
	var/slot_name = sparse_slot_named(O, variable)
	if(slot_name && isnull(var_value))
		default = sparse_slot_vv_class(sparse_slot_row(O, slot_name)[3])

	if(isnull(default))
		to_chat(src, "Unable to determine variable type.", confidential = TRUE)
	else
		to_chat(src, "Variable appears to be " + span_bold("[uppertext(default)]") + ".", confidential = TRUE)

	to_chat(src, "Variable contains: [var_value]", confidential = TRUE)

	if(default == VV_NUM)
		vv_say_direction(var_value)

	var/class
	if(asked.autodetect_class && default != VV_NULL)
		if (default == VV_TEXT)
			default = VV_MESSAGE
		class = default

	return asked.ask_child(/datum/ask_sequence/picker/vv_pick, "picked", list("class" = class, "default_class" = default, "current_value" = var_value, "extra_classes" = list(VV_LIST), "var_name" = variable))

/client/proc/vv_edit_parse(datum/ask_sequence/admin/vv_edit/asked)
	var/list/picked = asked.get("picked")
	if (!picked["class"])
		return ASK_STOP
	if(picked["class"] == VV_MESSAGE || picked["class"] == VV_TEXT)
		return asked.ask_child(/datum/ask_sequence/picker/parse_vars, "parsed", list("source_w" = rerun_wrap(asked.subject()), "source_text" = picked["value"]))
	return null

/client/proc/vv_edit_apply(datum/ask_sequence/admin/vv_edit/asked)
	var/atom/O = asked.subject()
	if(!O || !admin_require(src, R_VAREDIT, "modify_variables", TRUE))
		return
	var/variable = asked.variable
	var/var_value = vv_var_value(O, variable)
	var/list/value = asked.get("picked")
	var/class = value["class"]
	if (!class)
		return
	var/var_new = value["value"]

	if(class == VV_MESSAGE)
		class = VV_TEXT

	var/original_name = "[O]"

	switch(class)
		if(VV_LIST)
			if(!islist(var_value))
				mod_list(list(), O, original_name, variable)
				return

			mod_list(var_value, O, original_name, variable)
			return

		if(VV_RESTORE_DEFAULT)
			var_new = vv_var_default(O, variable)

		if(VV_TEXT)
			var_new = vv_substitute_vars(var_new, asked.get("parsed"), O)

	if (O.vv_edit_var(variable, var_new) == FALSE)
		to_chat(src, "Your edit was rejected by the object.", confidential = TRUE)
		return
	vv_update_display(O, "varedited", VV_MSG_EDITED)
	log_world("### VarEdit by [key_name(src)]: [O.type] [variable]=[var_value] => [var_new]")
	log_admin("[key_name(src)] modified [original_name]'s [variable] from [html_encode("[var_value]")] to [html_encode("[var_new]")]")
	var/msg = "[key_name_admin(src)] modified [original_name]'s [variable] from [var_value] to [var_new]"
	message_admins(msg)
	admin_ticket_log(O, msg)
	if(asked.edit_displays)
		vv_edit_displays(O, variable)

/// The View Variables rows an edit of `target_var` changes the text of.
/client/proc/vv_edit_displays(datum/target, target_var)
	switch(target_var)
		if("name")
			vv_update_display(target, "name", "[target]")
		if("dir")
			var/atom/A = target
			if(istype(A))
				vv_update_display(target, "dir", dir2text(A.dir) || A.dir)
		if("ckey")
			var/mob/living/L = target
			if(istype(L))
				vv_update_display(target, "ckey", L.ckey || "No ckey")
		if("real_name")
			var/mob/living/L = target
			if(istype(L))
				vv_update_display(target, "real_name", L.real_name || "No real name")

/// VV edit of a trait field (`@kind.field`): asks the new value and writes the holder's own copy with set_trait(), so the trait's key is
/// published and its readers follow.
/client/proc/modify_trait_field(datum/O, field_name)
	var/list/trait_field = type_trait_field_named(O, field_name)
	if(!trait_field)
		return
	ask_admin(/datum/ask_sequence/admin/vv_edit, O, list(TYPE_PROC_REF(/client, vv_trait_pick)), PROC_REF(vv_trait_apply), list("variable" = field_name))

/client/proc/vv_trait_pick(datum/ask_sequence/admin/vv_edit/asked)
	var/datum/O = asked.subject()
	var/field_name = asked.variable
	var/list/trait_field = O ? type_trait_field_named(O, field_name) : null
	if(!trait_field)
		return ASK_STOP
	var/old_value = type_trait_of(O, trait_field[1]).vars[trait_field[2]]
	var/default = vv_get_class(field_name, old_value)
	return asked.ask_child(/datum/ask_sequence/picker/vv_pick, "picked", list("default_class" = default, "current_value" = old_value, "var_name" = field_name))

/client/proc/vv_trait_apply(datum/ask_sequence/admin/vv_edit/asked)
	var/datum/O = asked.subject()
	var/field_name = asked.variable
	var/list/trait_field = O ? type_trait_field_named(O, field_name) : null
	if(!trait_field)
		return
	var/old_value = type_trait_of(O, trait_field[1]).vars[trait_field[2]]
	var/list/value = asked.get("picked")
	if(!value["class"])
		return
	var/new_value = value["value"]
	if(!O.vv_edit_var(field_name, new_value))
		to_chat(src, "Your edit was rejected by the object.", confidential = TRUE)
		return
	vv_update_display(O, "varedited", VV_MSG_EDITED)
	log_world("### VarEdit by [key_name(src)]: [O.type] [field_name]=[old_value] => [new_value]")
	log_admin("[key_name(src)] modified [O]'s [field_name] from [html_encode("[old_value]")] to [html_encode("[new_value]")]")
	var/msg = "[key_name_admin(src)] modified [O]'s [field_name] from [old_value] to [new_value]"
	message_admins(msg)
	admin_ticket_log(O, msg)
