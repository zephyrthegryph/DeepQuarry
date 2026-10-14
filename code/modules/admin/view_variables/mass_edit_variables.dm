/client/proc/cmd_mass_modify_object_variables(datum/target, var_name)
	if(!GLOB.prompt_flow) // its questions re-run it (prompt_flow(), prompt_helpers.dm)
		return prompt_flow(src, PROC_REF(cmd_mass_modify_object_variables), args)
	if(flow_ask(mob, "mass:sure", /datum/prompt/choice, question = "Are you sure you'd like to mass-modify every instance of the [var_name] variable? This can break everything if you do not know what you are doing.", title = "Slow down, chief!", choices = list("Yes", "No"), timeout = 60 SECONDS, buttons = TRUE) != "Yes")
		return

	if(!admin_require(src, R_VAREDIT, "cmd_mass_modify_object_variables", TRUE))
		return

	/// if false get only the strict type, get all subtypes too otherwise
	var/strict_type = FALSE
	if(target?.type)
		strict_type = vv_subtype_prompt(target.type, "mass")
		if(isnull(strict_type))
			return

	massmodify_variables(target, var_name, strict_type)
	feedback_add_details("admin_verb","MVV") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/client/proc/massmodify_variables(datum/target, var_name = "", strict_type = FALSE)
	if(!admin_require(src, R_VAREDIT, "massmodify_variables", TRUE))
		return
	if(!istype(target))
		return

	var/variable = ""
	if(!var_name)
		var/list/names = list()
		for (var/V in target.vars)
			names += V

		names = sortList(names)

		variable = flow_ask(mob, "mass:var", /datum/prompt/choice, question = "Which var?", title = "Var", choices = names)
	else
		variable = var_name

	if(!variable || !target.can_vv_get(variable))
		return
	var/default
	var/var_value = target.vars[variable]

	if(variable in GLOB.VVckey_edit)
		to_chat(src, "It's forbidden to mass-modify ckeys. It'll crash everyone's client you dummy.", confidential = TRUE)
		return
	if(variable in GLOB.VVlocked)
		if(!admin_require(src, R_DEBUG, "massmodify_variables", TRUE))
			return
	if(variable in GLOB.VVicon_edit_lock)
		if(!admin_require(src, R_FUN|R_DEBUG, "massmodify_variables", TRUE))
			return
	if(variable in GLOB.VVpixelmovement)
		if(!admin_require(src, R_DEBUG, "massmodify_variables", TRUE))
			return
		var/prompt = flow_ask(mob, "mass:gliding", /datum/prompt/choice, question = "Editing this var may irreparably break tile gliding for the rest of the round. THIS CAN'T BE UNDONE", title = "DANGER", choices = list("ABORT ", "Continue", " ABORT"), buttons = TRUE)
		if (prompt != "Continue")
			return

	default = vv_get_class(variable, var_value)

	if(isnull(default))
		to_chat(src, "Unable to determine variable type.", confidential = TRUE)
	else
		to_chat(src, "Variable appears to be " + span_bold("[uppertext(default)]") + ".", confidential = TRUE)

	to_chat(src, "Variable contains: [var_value]", confidential = TRUE)

	if(default == VV_NUM)
		var/dir_text = ""
		if(var_value > 0 && var_value < 16)
			if(var_value & 1)
				dir_text += "NORTH"
			if(var_value & 2)
				dir_text += "SOUTH"
			if(var_value & 4)
				dir_text += "EAST"
			if(var_value & 8)
				dir_text += "WEST"

		if(dir_text)
			to_chat(src, "If a direction, direction is: [dir_text]", confidential = TRUE)

	var/value = vv_get_value(default_class = default, key = "mass:value")
	var/new_value = value["value"]
	var/class = value["class"]

	if(!class || (new_value == null && class != VV_NULL))
		return

	if (class == VV_MESSAGE)
		class = VV_TEXT

	if (value["type"])
		class = VV_NEW_TYPE

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
				if (D.vv_edit_var(variable, initial(D.vars[variable])) != FALSE)
					accepted++
				else
					rejected++
				CHECK_TICK

		if(VV_TEXT)
			var/list/varsvars = vv_parse_text(target, new_value, "mass")
			if(isnull(varsvars))
				return
			var/pre_processing = new_value
			var/unique
			if (varsvars?.len)
				unique = flow_ask(mob, "mass:unique", /datum/prompt/choice, question = "Process vars unique to each instance, or same for all?", title = "Variable Association", choices = list("Unique", "Same"), buttons = TRUE)
				if(isnull(unique))
					return
				if(unique == "Unique")
					unique = TRUE
				else
					unique = FALSE
					for(var/V in varsvars)
						new_value = replacetext(new_value,"\[[V]]","[target.vars[V]]")

			to_chat(src, "Finding items...", confidential = TRUE)
			var/list/items = get_all_of_type(target.type, strict_type)
			to_chat(src, "Changing [items.len] items...", confidential = TRUE)
			for(var/thing in items)
				if (!thing)
					continue
				var/datum/D = thing
				if(unique)
					new_value = pre_processing
					for(var/V in varsvars)
						new_value = replacetext(new_value,"\[[V]]","[D.vars[V]]")

				if (D.vv_edit_var(variable, new_value) != FALSE)
					accepted++
				else
					rejected++
				CHECK_TICK

		if (VV_NEW_TYPE)
			var/many = flow_ask(mob, "mass:many", /datum/prompt/choice, question = "Create only one [value["type"]] and assign each or a new one for each thing", title = "How Many", choices = list("One", "Many", "Cancel"), buttons = TRUE)
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

	log_world("### MassVarEdit by [src]: [target.type] (A/R [accepted]/[rejected]) [variable]=[html_encode("[target.vars[variable]]")]([list2params(value)])")
	log_admin("[key_name(src)] mass modified [original_name]'s [variable] to [target.vars[variable]] ([accepted] objects modified)")
	message_admins("[key_name_admin(src)] mass modified [original_name]'s [variable] to [target.vars[variable]] ([accepted] objects modified)")

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
