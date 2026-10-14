/client/proc/vv_get_class(var_name, var_value)
	if(isnull(var_value))
		. = VV_NULL

	else if(isnum(var_value))
		if(length(get_valid_bitflags(var_name)))
			. = VV_BITFIELD
		else
			. = VV_NUM

	else if(istext(var_value))
		if(findtext(var_value, "\n"))
			. = VV_MESSAGE
		else if(findtext(var_value, GLOB.is_color))
			. = VV_COLOR
		else
			. = VV_TEXT

	else if(isicon(var_value))
		. = VV_ICON

	else if(ismob(var_value))
		. = VV_MOB_REFERENCE

	else if(isloc(var_value))
		. = VV_ATOM_REFERENCE

	else if(istype(var_value, /client))
		. = VV_CLIENT

	else if(isdatum(var_value))
		. = VV_DATUM_REFERENCE

	else if(ispath(var_value))
		if(ispath(var_value, /atom))
			. = VV_ATOM_TYPE
		else if(ispath(var_value, /datum))
			. = VV_DATUM_TYPE
		else
			. = VV_TYPE

	else if(islist(var_value))
		if(var_name in GLOB.color_vars)
			. = VV_COLOR_MATRIX
		else
			. = VV_LIST

	else if(isfile(var_value))
		. = VV_FILE
	else
		. = VV_NULL

/// View Variables' value picker. Runs inside a prompt flow (flow_ask(), prompt_helpers.dm): each
/// question returns null until its answer re-runs the flow's entry, so a null "class" means
/// "cancelled or still asking" and the caller just returns. `key` keeps this pick's answers
/// apart from the flow's other questions. `allow_finish`: closing the type list gives the class
/// "finish" (ends a list being filled).
/client/proc/vv_get_value(class, default_class, current_value, list/restricted_classes, list/extra_classes, list/classes, var_name, key = "value", allow_finish = FALSE)
	. = list("class" = class, "value" = null)
	if(!class)
		if(!classes)
			classes = list (
				VV_NUM,
				VV_TEXT,
				VV_MESSAGE,
				VV_ICON,
				VV_COLOR,
				//VV_COLOR_MATRIX,
				VV_ATOM_REFERENCE,
				VV_DATUM_REFERENCE,
				VV_MOB_REFERENCE,
				VV_CLIENT,
				VV_ATOM_TYPE,
				VV_DATUM_TYPE,
				VV_TYPE,
				VV_FILE,
				VV_NEW_ATOM,
				VV_NEW_DATUM,
				VV_NEW_TYPE,
				VV_NEW_LIST,
				VV_NULL,
				VV_INFINITY,
				VV_RESTORE_DEFAULT,
				VV_TEXT_LOCATE,
				VV_PROCCALL_RETVAL,
				)

		var/markstring
		if(!(VV_MARKED_DATUM in restricted_classes))
			markstring = "[VV_MARKED_DATUM] (CURRENT: [(istype(holder) && istype(holder.marked_datum(), /datum))? holder.marked_datum().type : "NULL"])"
			classes += markstring

		var/list/tagstrings = new
		if(!(VV_TAGGED_DATUM in restricted_classes) && holder && LAZYLEN(holder.tagged_datums))
			var/i = 0
			for(var/datum/iter_tagged_datum as anything in holder.tagged_datums)
				i++
				var/new_tagstring = "[VV_TAGGED_DATUM] #[i]: [iter_tagged_datum.type])"
				tagstrings[new_tagstring] = iter_tagged_datum
				classes += new_tagstring

		if(restricted_classes)
			classes -= restricted_classes

		if(extra_classes)
			classes += extra_classes

		.["class"] = flow_ask(mob, "[key]:class", /datum/prompt/choice, question = "What kind of data?", title = "Variable Type", choices = classes, default = default_class, cancel_answer = allow_finish ? "finish" : null)
		if(.["class"] == "finish")
			return
		if(holder && holder.marked_datum() && .["class"] == markstring)
			.["class"] = VV_MARKED_DATUM

		if(holder && tagstrings[.["class"]])
			var/datum/chosen_datum = tagstrings[.["class"]]
			.["value"] = chosen_datum
			.["class"] = VV_TAGGED_DATUM

	switch(.["class"])
		if(VV_TEXT)
			.["value"] = flow_ask(mob, "[key]:text", /datum/prompt/text, question = "Enter new text:", title = "Text", default = current_value)
			if(.["value"] == null)
				.["class"] = null
				return
		if(VV_MESSAGE)
			.["value"] = flow_ask(mob, "[key]:text", /datum/prompt/text, question = "Enter new text:", title = "Text", default = current_value, multiline = TRUE, max_len = MAX_TGUI_INPUT, name_text = ((MAX_TGUI_INPUT) <= MAX_NAME_LEN))
			if(.["value"] == null)
				.["class"] = null
				return

		if(VV_NUM)
			.["value"] = flow_ask(mob, "[key]:num", /datum/prompt/number, question = "Enter new number:", title = "Num", default = current_value, max_value = INFINITY, min_value = -INFINITY, round_entry = FALSE)
			if(.["value"] == null)
				.["class"] = null
				return

		if(VV_BITFIELD)
			.["value"] = flow_ask(mob, "[key]:bits", /datum/prompt/bitfield, title = "Editing bitfield: [var_name]", bitfield = var_name, default = current_value)
			if(.["value"] == null)
				.["class"] = null
				return

		if(VV_ATOM_TYPE)
			.["value"] = pick_closest_path(FALSE, key = "[key]:path", user = mob)
			if(.["value"] == null)
				.["class"] = null
				return

		if(VV_DATUM_TYPE)
			.["value"] = pick_closest_path(FALSE, GLOBAL_TABLE_GET(get_fancy_list_of_datum_types), "[key]:path", mob)
			if(.["value"] == null)
				.["class"] = null
				return

		if(VV_TYPE)
			var/type = vv_ask_type(current_value, key)
			if(!type)
				.["class"] = null
				return
			.["value"] = type

		if(VV_ATOM_REFERENCE)
			var/type = pick_closest_path(FALSE, key = "[key]:path", user = mob)
			var/subtypes = vv_subtype_prompt(type, key)
			if(subtypes == null)
				.["class"] = null
				return
			var/list/things = vv_reference_list(type, subtypes)
			var/value = flow_ask(mob, "[key]:ref", /datum/prompt/choice, question = "Select reference:", title = "Reference", choices = things, default = current_value)
			if(!value || !things[value])
				.["class"] = null
				return
			.["value"] = things[value]

		if(VV_DATUM_REFERENCE)
			var/type = pick_closest_path(FALSE, GLOBAL_TABLE_GET(get_fancy_list_of_datum_types), "[key]:path", mob)
			var/subtypes = vv_subtype_prompt(type, key)
			if(subtypes == null)
				.["class"] = null
				return
			var/list/things = vv_reference_list(type, subtypes)
			var/value = flow_ask(mob, "[key]:ref", /datum/prompt/choice, question = "Select reference:", title = "Reference", choices = things, default = current_value)
			if(!value || !things[value])
				.["class"] = null
				return
			.["value"] = things[value]

		if(VV_MOB_REFERENCE)
			var/type = pick_closest_path(FALSE, make_types_fancy(typesof(/mob)), "[key]:path", mob)
			var/subtypes = vv_subtype_prompt(type, key)
			if(subtypes == null)
				.["class"] = null
				return
			var/list/things = vv_reference_list(type, subtypes)
			var/value = flow_ask(mob, "[key]:ref", /datum/prompt/choice, question = "Select reference:", title = "Reference", choices = things, default = current_value)
			if(!value || !things[value])
				.["class"] = null
				return
			.["value"] = things[value]

		if(VV_CLIENT)
			.["value"] = flow_ask(mob, "[key]:client", /datum/prompt/choice, question = "Select reference:", title = "Reference", choices = GLOB.clients, default = current_value)
			if(.["value"] == null)
				.["class"] = null
				return

		if(VV_FILE)
			.["value"] = input(mob, "Pick file:", "File") as null|file // ALLOW(scheduler): file uploads need the BYOND file dialog
			if(.["value"] == null)
				.["class"] = null
				return

		if(VV_ICON)
			.["value"] = pick_and_customize_icon(mob, TRUE, "[key]:icon")
			if(.["value"] == null)
				.["class"] = null
				return

		if(VV_MARKED_DATUM)
			.["value"] = holder.marked_datum()
			if(.["value"] == null)
				.["class"] = null
				return

		if(VV_TAGGED_DATUM)
			if(.["value"] == null)
				.["class"] = null
				return

		if(VV_PROCCALL_RETVAL)
			// The call runs when its questions are answered, and again if a later question of
			// this flow is answered after it.
			var/list/get_retval = list()
			callproc_blocking(get_retval, "[key]:call")
			if(!length(get_retval))
				.["class"] = null
				return
			.["value"] = get_retval[1] //should have been set in proccall!
			if(.["value"] == null)
				.["class"] = null
				return

		if(VV_NEW_ATOM)
			var/type = pick_closest_path(FALSE, key = "[key]:path", user = mob)
			if(!type)
				.["class"] = null
				return
			.["type"] = type
			var/atom/newguy = new type()
			newguy.datum_flags |= DF_VAR_EDITED
			.["value"] = newguy

		if(VV_NEW_DATUM)
			var/type = pick_closest_path(FALSE, GLOBAL_TABLE_GET(get_fancy_list_of_datum_types), "[key]:path", mob)
			if(!type)
				.["class"] = null
				return
			.["type"] = type
			var/datum/newguy = new type()
			newguy.datum_flags |= DF_VAR_EDITED
			.["value"] = newguy

		if(VV_NEW_TYPE)
			var/type = vv_ask_type(current_value, key)
			if(!type)
				.["class"] = null
				return
			.["type"] = type
			var/datum/newguy = new type()
			if(istype(newguy))
				newguy.datum_flags |= DF_VAR_EDITED
			.["value"] = newguy

		if(VV_NEW_LIST)
			.["type"] = /list
			var/list/value = list()

			var/expectation = flow_ask(mob, "[key]:populate", /datum/prompt/choice, question = "Would you like to populate the list", title = "Populate List?", choices = list("Yes", "No"), buttons = TRUE)
			if(isnull(expectation))
				.["class"] = null
				return
			if(expectation == "No")
				.["value"] = value
				return .

			// One entry after another; closing the type list finishes the list.
			for(var/i in 1 to 1000)
				var/list/insert = vv_get_value(restricted_classes = list(VV_RESTORE_DEFAULT), key = "[key]:item[i]", allow_finish = TRUE)
				if(insert["class"] == "finish")
					break
				if(!insert["class"])
					.["class"] = null
					return
				value += LIST_VALUE_WRAP_LISTS(insert["value"])

			.["value"] = value

		if(VV_TEXT_LOCATE)
			var/ref = flow_ask(mob, "[key]:locate", /datum/prompt/text, question = "Enter reference:", title = "Reference")
			if(!ref)
				.["class"] = null
				return
			var/datum/D = locate(ref)
			if(!D)
				tgui_alert_async(mob,"Invalid ref!")
				.["class"] = null
				return
			.["type"] = D.type
			.["value"] = D

		if(VV_COLOR)
			.["value"] = flow_ask(mob, "[key]:color", /datum/prompt/color, question = "Enter new color:", title = "Color", default = current_value)
			if(.["value"] == null)
				.["class"] = null
				return

		if(VV_INFINITY)
			.["value"] = INFINITY

/// A type typed in by path; one that doesn't exist is refused (type it again from the start).
/client/proc/vv_ask_type(current_value, key)
	var/type = flow_ask(mob, "[key]:type", /datum/prompt/text, question = "Enter type:", title = "Type", default = current_value)
	if(!type)
		return
	type = text2path(type)
	if(!type)
		to_chat(src, span_warning("Type not found."), confidential = TRUE)
	return type
