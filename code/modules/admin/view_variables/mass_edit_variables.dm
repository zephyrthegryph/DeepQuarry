/// View Variables editing one variable of every instance of the subject's type. `include_subtypes` is the answer of the subtype question.
/datum/ask_sequence/admin/vv_mass
	var/var_name
	var/include_subtypes = FALSE
	var/variable
	var/sure
	var/gliding

/datum/ask_sequence/admin/vv_mass/initial_steps()
	return list(
		question_step("sure", /datum/prompt/choice, question = "Are you sure you'd like to mass-modify every instance of the [var_name] variable? This can break everything if you do not know what you are doing.", title = "Slow down, chief!", choices = list("Yes", "No"), timeout = 60 SECONDS, buttons = TRUE),
		TYPE_PROC_REF(/client, mass_gate),
		TYPE_PROC_REF(/client, mass_ask_subtypes),
		TYPE_PROC_REF(/client, mass_ask_var),
		TYPE_PROC_REF(/client, mass_check_var),
		TYPE_PROC_REF(/client, mass_check_gliding),
		TYPE_PROC_REF(/client, mass_ask_value),
		TYPE_PROC_REF(/client, mass_ask_parse),
		TYPE_PROC_REF(/client, mass_ask_unique),
		TYPE_PROC_REF(/client, mass_ask_many))

/client/proc/cmd_mass_modify_object_variables(datum/target, var_name)
	ask_admin(/datum/ask_sequence/admin/vv_mass, target, null, PROC_REF(mass_apply), list("var_name" = var_name))

/client/proc/mass_gate(datum/ask_sequence/admin/vv_mass/asked)
	if(asked.sure != "Yes")
		return ASK_STOP
	if(!admin_require(src, R_VAREDIT, "cmd_mass_modify_object_variables", TRUE))
		return ASK_STOP
	return null

/// Whether the edit reaches the subtypes too (asked when the type has any).
/client/proc/mass_ask_subtypes(datum/ask_sequence/admin/vv_mass/asked)
	var/datum/target = asked.subject()
	if(target?.type)
		return asked.ask_child(/datum/ask_sequence/picker/subtype_pick, "include_subtypes", list("target_type" = target.type))
	return null

/client/proc/mass_ask_var(datum/ask_sequence/admin/vv_mass/asked)
	if(!admin_require(src, R_VAREDIT, "massmodify_variables", TRUE))
		return ASK_STOP
	var/datum/target = asked.subject()
	if(!istype(target))
		return ASK_STOP
	if(asked.var_name)
		asked.variable = asked.var_name
		return null
	var/list/names = list()
	for (var/V in target.vars)
		names += V
	for(var/slot_label in sparse_slots_of(target))
		names += slot_label

	names = sortList(names)

	return question_step("variable", /datum/prompt/choice, question = "Which var?", title = "Var", choices = names)

/client/proc/mass_check_var(datum/ask_sequence/admin/vv_mass/asked)
	var/datum/target = asked.subject()
	var/variable = asked.variable
	if(!variable || !target.can_vv_get(variable))
		return ASK_STOP

	if(variable in GLOB.VVckey_edit)
		to_chat(src, "It's forbidden to mass-modify ckeys. It'll crash everyone's client you dummy.", confidential = TRUE)
		return ASK_STOP
	if(variable in GLOB.VVlocked)
		if(!admin_require(src, R_DEBUG, "massmodify_variables", TRUE))
			return ASK_STOP
	if(variable in GLOB.VVicon_edit_lock)
		if(!admin_require(src, R_FUN|R_DEBUG, "massmodify_variables", TRUE))
			return ASK_STOP
	if(variable in GLOB.VVpixelmovement)
		if(!admin_require(src, R_DEBUG, "massmodify_variables", TRUE))
			return ASK_STOP
		return question_step("gliding", /datum/prompt/choice, question = "Editing this var may irreparably break tile gliding for the rest of the round. THIS CAN'T BE UNDONE", title = "DANGER", choices = list("ABORT ", "Continue", " ABORT"), buttons = TRUE)
	return null

/client/proc/mass_check_gliding(datum/ask_sequence/admin/vv_mass/asked)
	if((asked.variable in GLOB.VVpixelmovement) && asked.gliding != "Continue")
		return ASK_STOP
	return null

/client/proc/mass_ask_value(datum/ask_sequence/admin/vv_mass/asked)
	var/datum/target = asked.subject()
	var/variable = asked.variable
	var/var_value = vv_var_value(target, variable)
	var/default = vv_get_class(variable, var_value)
	var/slot_name = sparse_slot_named(target, variable)
	if(slot_name && isnull(var_value))
		default = sparse_slot_vv_class(sparse_slot_row(target, slot_name)[3])

	if(isnull(default))
		to_chat(src, "Unable to determine variable type.", confidential = TRUE)
	else
		to_chat(src, "Variable appears to be " + span_bold("[uppertext(default)]") + ".", confidential = TRUE)

	to_chat(src, "Variable contains: [var_value]", confidential = TRUE)

	if(default == VV_NUM)
		vv_say_direction(var_value)

	return asked.ask_child(/datum/ask_sequence/picker/vv_pick, "picked", list("default_class" = default))

/// The kind of the new value, as the edit below treats it (null: nothing to apply).
/client/proc/mass_class(datum/ask_sequence/admin/vv_mass/asked)
	var/list/value = asked.get("picked")
	var/class = value["class"]
	var/new_value = value["value"]
	if(!class || (new_value == null && class != VV_NULL))
		return null

	if (class == VV_MESSAGE)
		class = VV_TEXT

	if (value["type"])
		class = VV_NEW_TYPE
	return class

/client/proc/mass_ask_parse(datum/ask_sequence/admin/vv_mass/asked)
	var/class = mass_class(asked)
	if(!class)
		return ASK_STOP
	if(class == VV_TEXT)
		var/list/value = asked.get("picked")
		return asked.ask_child(/datum/ask_sequence/picker/parse_vars, "parsed", list("source_w" = rerun_wrap(asked.subject()), "source_text" = value["value"]))
	return null

/client/proc/mass_ask_unique(datum/ask_sequence/admin/vv_mass/asked)
	if(mass_class(asked) == VV_TEXT && length(asked.get("parsed")))
		return question_step("unique", /datum/prompt/choice, question = "Process vars unique to each instance, or same for all?", title = "Variable Association", choices = list("Unique", "Same"), buttons = TRUE)
	return null

/client/proc/mass_ask_many(datum/ask_sequence/admin/vv_mass/asked)
	if(mass_class(asked) == VV_NEW_TYPE)
		var/list/value = asked.get("picked")
		return question_step("many", /datum/prompt/choice, question = "Create only one [value["type"]] and assign each or a new one for each thing", title = "How Many", choices = list("One", "Many", "Cancel"), buttons = TRUE)
	return null

/client/proc/mass_apply(datum/ask_sequence/admin/vv_mass/asked)
	var/datum/target = asked.subject()
	if(!istype(target) || !admin_require(src, R_VAREDIT, "massmodify_variables", TRUE))
		return
	feedback_add_details("admin_verb","MVV") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	var/variable = asked.variable
	var/strict_type = asked.include_subtypes
	var/list/value = asked.get("picked")
	var/new_value = value["value"]
	var/class = mass_class(asked)
	if(!class)
		return

	var/original_name = "[target]"

	var/rejected = 0
	var/accepted = 0

	switch(class)
		if(VV_RESTORE_DEFAULT)
			to_chat(src, "Finding items...", confidential = TRUE)
			var/list/items = get_all_of_type(target.type, strict_type)
			to_chat(src, "Changing [items.len] items...", confidential = TRUE)
			for(var/thing in items)
				if (!thing)
					continue
				var/datum/D = thing
				if (D.vv_edit_var(variable, vv_var_default(D, variable)) != FALSE)
					accepted++
				else
					rejected++
				CHECK_TICK

		if(VV_TEXT)
			var/list/varsvars = asked.get("parsed")
			var/pre_processing = new_value
			var/unique
			if (varsvars?.len)
				unique = asked.get("unique")
				if(isnull(unique))
					return
				if(unique == "Unique")
					unique = TRUE
				else
					unique = FALSE
					new_value = vv_substitute_vars(new_value, varsvars, target)

			to_chat(src, "Finding items...", confidential = TRUE)
			var/list/items = get_all_of_type(target.type, strict_type)
			to_chat(src, "Changing [items.len] items...", confidential = TRUE)
			for(var/thing in items)
				if (!thing)
					continue
				var/datum/D = thing
				if(unique)
					new_value = vv_substitute_vars(pre_processing, varsvars, D)

				if (D.vv_edit_var(variable, new_value) != FALSE)
					accepted++
				else
					rejected++
				CHECK_TICK

		if (VV_NEW_TYPE)
			var/many = asked.get("many")
			if (isnull(many) || many == "Cancel")
				return
			if (many == "Many")
				many = TRUE
			else
				many = FALSE

			var/type = value["type"]
			to_chat(src, "Finding items...", confidential = TRUE)
			var/list/items = get_all_of_type(target.type, strict_type)
			to_chat(src, "Changing [items.len] items...", confidential = TRUE)
			for(var/thing in items)
				if (!thing)
					continue
				var/datum/D = thing
				if(many && !new_value)
					new_value = new type()

				if (D.vv_edit_var(variable, new_value) != FALSE)
					accepted++
				else
					rejected++
				new_value = null
				CHECK_TICK

		else
			to_chat(src, "Finding items...", confidential = TRUE)
			var/list/items = get_all_of_type(target.type, strict_type)
			to_chat(src, "Changing [items.len] items...", confidential = TRUE)
			for(var/thing in items)
				if (!thing)
					continue
				var/datum/D = thing
				if (D.vv_edit_var(variable, new_value) != FALSE)
					accepted++
				else
					rejected++
				CHECK_TICK


	var/count = rejected+accepted
	if (!count)
		to_chat(src, "No objects found", confidential = TRUE)
		return
	if (!accepted)
		to_chat(src, "Every object rejected your edit", confidential = TRUE)
		return
	if (rejected)
		to_chat(src, "[rejected] out of [count] objects rejected your edit", confidential = TRUE)

	log_world("### MassVarEdit by [src]: [target.type] (A/R [accepted]/[rejected]) [variable]=[html_encode("[vv_var_value(target, variable)]")]([list2params(value)])")
	log_admin("[key_name(src)] mass modified [original_name]'s [variable] to [vv_var_value(target, variable)] ([accepted] objects modified)")
	message_admins("[key_name_admin(src)] mass modified [original_name]'s [variable] to [vv_var_value(target, variable)] ([accepted] objects modified)")

//not using global lists as vv is a debug function and debug functions should rely on as less things as possible.
/proc/get_all_of_type(T, subtypes = TRUE)
	var/list/typecache = list()
	typecache[T] = 1
	if (subtypes)
		typecache = typecacheof(typecache)
	. = list()
	if (ispath(T, /mob))
		for(var/mob/thing in world)
			if (typecache[thing.type])
				. += thing
			CHECK_TICK

	else if (ispath(T, /obj/machinery/door))
		for(var/obj/machinery/door/thing in world)
			if (typecache[thing.type])
				. += thing
			CHECK_TICK

	else if (ispath(T, /obj/machinery))
		for(var/obj/machinery/thing in world)
			if (typecache[thing.type])
				. += thing
			CHECK_TICK

	else if (ispath(T, /obj/item))
		for(var/obj/item/thing in world)
			if (typecache[thing.type])
				. += thing
			CHECK_TICK

	else if (ispath(T, /obj))
		for(var/obj/thing in world)
			if (typecache[thing.type])
				. += thing
			CHECK_TICK

	else if (ispath(T, /atom/movable))
		for(var/atom/movable/thing in world)
			if (typecache[thing.type])
				. += thing
			CHECK_TICK

	else if (ispath(T, /turf))
		for(var/turf/thing in world)
			if (typecache[thing.type])
				. += thing
			CHECK_TICK

	else if (ispath(T, /atom))
		for(var/atom/thing in world)
			if (typecache[thing.type])
				. += thing
			CHECK_TICK

	else if (ispath(T, /client))
		for(var/client/thing in GLOB.clients)
			if (typecache[thing.type])
				. += thing
			CHECK_TICK

	else if (ispath(T, /datum))
		for(var/datum/thing)
			if (typecache[thing.type])
				. += thing
			CHECK_TICK

	else
		for(var/datum/thing in world)
			if (typecache[thing.type])
				. += thing
			CHECK_TICK
