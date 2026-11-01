// The admin tools' shared question sequences (code/datums/prompts/sequence.dm): View Variables' value picker and the smaller pickers it is built from. Each is a
// self-contained set of questions: a tool asks one with ask_child() from a step (the answer lands under the key it names) or starts it on its own.

/// The base of the pickers: the steps are the sequence's own procs, and the code under them still reads usr, so it runs as the admin.
/datum/ask_sequence/picker
	self_owned = TRUE
	as_actor = TRUE

// ---------------------------------------------------------------- types

/// Asks for a type: a typed filter, then a pick among the matches (a sole match is taken). `matches` is the name -> path table to pick from. The result is the path.
/datum/ask_sequence/picker/type_pick
	var/list/matches
	var/filter
	var/chosen
	var/list/shown

/datum/ask_sequence/picker/type_pick/initial_steps()
	return list(
		question_step("filter", /datum/prompt/text, question = "Enter type to find (blank for all, cancel to cancel)", title = "Search for type"),
		PROC_REF(choose_match),
		PROC_REF(resolve_match))

/datum/ask_sequence/picker/type_pick/proc/choose_match()
	var/list/pool = matches
	var/typed = trim("[filter]")
	if(typed != "")
		pool = filter_fancy_list(pool, typed)
	if(!length(pool))
		return ASK_STOP
	shown = pool
	if(length(pool) == 1)
		chosen = pool[1]
		return null
	return question_step("chosen", /datum/prompt/choice, question = "Select a type", title = "Pick Type", choices = pool)

/datum/ask_sequence/picker/type_pick/proc/resolve_match()
	if(!chosen || !(chosen in shown))
		return ASK_STOP
	set_result(shown[chosen])
	return null

/// Asks whether to include the subtypes of `target_type` (no question when it has none). The result is TRUE to include them.
/datum/ask_sequence/picker/subtype_pick
	var/target_type
	var/mode

/datum/ask_sequence/picker/subtype_pick/initial_steps()
	return list(PROC_REF(ask_mode), PROC_REF(read_mode))

/datum/ask_sequence/picker/subtype_pick/proc/ask_mode()
	if(!ispath(target_type))
		return ASK_STOP
	if(!length(subtypesof(target_type)))
		set_result(FALSE)
		return ASK_FINISH
	return question_step("mode", /datum/prompt/choice, question = "Strict object type detection?", title = "Type detection", choices = list("Strictly this type", "This type and subtypes", "Cancel"), buttons = TRUE)

/datum/ask_sequence/picker/subtype_pick/proc/read_mode()
	switch(mode)
		if("Strictly this type")
			set_result(FALSE)
		if("This type and subtypes")
			set_result(TRUE)
		else
			return ASK_STOP
	return null

// ---------------------------------------------------------------- text

/// Asks whether the [] in `source_text` are variables of the datum `source_w` (wrapped) to substitute. The result is the list of those var names (empty for none).
/datum/ask_sequence/picker/parse_vars
	var/source_w
	var/source_text
	var/parse

/datum/ask_sequence/picker/parse_vars/initial_steps()
	return list(PROC_REF(ask_parse), PROC_REF(read_parse))

/datum/ask_sequence/picker/parse_vars/proc/ask_parse()
	set_result(list())
	var/datum/source = rerun_unwrap(source_w)
	if(!source || !findtext(source_text, "\["))
		return ASK_FINISH
	return question_step("parse", /datum/prompt/choice, question = "\[] detected in string, process as variables?", title = "Process Variables?", choices = list("Yes", "No"), buttons = TRUE)

/datum/ask_sequence/picker/parse_vars/proc/read_parse()
	if(parse == "Yes")
		set_result(string2listofvars(source_text, rerun_unwrap(source_w)))
	return null

/// `text` with each [var] of `var_names` replaced by that var of `source`.
/proc/vv_substitute_vars(text, list/var_names, datum/source)
	for(var/V in var_names)
		text = replacetext(text, "\[[V]]", "[source.vars[V]]")
	return text

// ---------------------------------------------------------------- icons

/// Asks for an icon (from a file or by path) and offers to customize it (icon_state, dir, frame, moving). `pick_only` skips the customizing. The result is the icon.
/datum/ask_sequence/picker/icon_pick
	var/pick_only = FALSE
	var/source_choice
	var/icon_path
	var/custom
	var/icon_state_name
	var/icon_dir
	var/icon_frame
	var/icon_moving

/datum/ask_sequence/picker/icon_pick/initial_steps()
	return list(
		question_step("source_choice", /datum/prompt/choice, question = "Do you wish to pick an icon from file?", title = "File picker icon", choices = list("Yes", "No"), buttons = TRUE),
		PROC_REF(ask_source),
		PROC_REF(read_path),
		PROC_REF(ask_custom),
		PROC_REF(ask_details))

/datum/ask_sequence/picker/icon_pick/proc/ask_source()
	if(source_choice == "Yes")
		var/icon/uploaded = input(actor(), "Pick icon:", "Icon") as null|icon // ALLOW(scheduler): file uploads need the BYOND file dialog
		if(!uploaded)
			return ASK_STOP
		put("icon_result", uploaded)
		return null
	if(source_choice == "No")
		return question_step("icon_path", /datum/prompt/text, question = "Pick icon path", title = "icon path")
	return ASK_STOP

/datum/ask_sequence/picker/icon_pick/proc/read_path()
	if(get("icon_result"))
		return null
	var/path = icon_path
	var/regex/regex = regex(@"^.+icons/")
	path = regex.Replace(replacetext(path, @"\", "/"), "icons/")
	var/copied = fcopy_rsc(path)
	if(!copied)
		to_chat(actor(), span_warning("'[path]' is an invalid icon path!"))
		return ASK_STOP
	put("icon_result", copied)
	return null

/datum/ask_sequence/picker/icon_pick/proc/ask_custom()
	if(!get_icon_dmi_path(get("icon_result")) || pick_only)
		set_result(get("icon_result"))
		return ASK_FINISH
	return question_step("custom", /datum/prompt/choice, question = "Do you wish to specify any arguments for the icon?", title = "Customize Icon", choices = list("Yes", "No"), buttons = TRUE)

/datum/ask_sequence/picker/icon_pick/proc/ask_details()
	if(custom != "Yes")
		set_result(get("icon_result"))
		return ASK_FINISH
	add_steps(list(
		question_step("icon_state_name", /datum/prompt/text, question = "Pick icon_state", title = "icon_state"),
		question_step("icon_dir", /datum/prompt/choice, question = "Pick icon dir", title = "dir", choices = list("North", "East", "South", "West"), default = "South"),
		question_step("icon_frame", /datum/prompt/number, question = "Pick icon frame", title = "frame"),
		question_step("icon_moving", /datum/prompt/choice, question = "Pick icon moving", title = "moving", choices = list("Both", "Movement only", "Non-Movement Only"), default = "Both"),
		PROC_REF(build_icon)))
	return null

/datum/ask_sequence/picker/icon_pick/proc/build_icon()
	var/moving
	switch(icon_moving)
		if("Both")
			moving = null
		if("Movement only")
			moving = 1
		if("Non-Movement Only")
			moving = 0
		else
			return ASK_STOP
	set_result(new /icon(get_icon_dmi_path(get("icon_result")), icon_state_name, text2dir(icon_dir), icon_frame, moving))
	return null

// ---------------------------------------------------------------- View Variables' value picker

/// Asks for a value of any kind View Variables edits with, as its sequence of questions: the kind (unless `class` is preset), then what that kind needs. The result is
/// list("class" = the kind, "value" = the value, and "type" = the type, for the kinds that make a new thing or find one by reference). `allow_finish`: closing the kind list
/// gives the class "finish" (ends a list being filled).
/datum/ask_sequence/picker/vv_pick
	var/class
	var/default_class
	var/current_value
	var/list/restricted_classes
	var/list/extra_classes
	var/list/classes
	var/var_name
	var/allow_finish = FALSE
	var/value_type
	var/markstring
	/// Tagged-datum choice text -> its place in the admin's tagged datums.
	var/list/tag_places
	var/list/ref_matches
	var/ref_path
	var/strict_subtypes
	var/typed
	var/new_type
	var/locate_ref
	var/populate
	var/item_count = 0
	var/list/item

/datum/ask_sequence/picker/vv_pick/initial_steps()
	return list(PROC_REF(ask_class), PROC_REF(open_class))

/datum/ask_sequence/picker/vv_pick/finish()
	if(done)
		return
	var/list/built = list("class" = class, "value" = get("value"))
	if(value_type)
		built["type"] = value_type
	set_result(built)
	return ..()

/datum/ask_sequence/picker/vv_pick/proc/ask_class()
	if(!isnull(class))
		return null
	var/client/admin = actor()?.client
	var/list/pool = classes ? classes.Copy() : list(
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

	var/datum/admins/holder = admin_holder_of(admin)
	if(!(VV_MARKED_DATUM in restricted_classes))
		markstring = "[VV_MARKED_DATUM] (CURRENT: [(istype(holder) && istype(holder.marked_datum(), /datum))? holder.marked_datum().type : "NULL"])"
		pool += markstring

	tag_places = list()
	if(!(VV_TAGGED_DATUM in restricted_classes) && holder && LAZYLEN(holder.tagged_datums))
		var/i = 0
		for(var/datum/iter_tagged_datum as anything in holder.tagged_datums)
			i++
			var/new_tagstring = "[VV_TAGGED_DATUM] #[i]: [iter_tagged_datum.type])"
			tag_places[new_tagstring] = i
			pool += new_tagstring

	if(restricted_classes)
		pool -= restricted_classes

	if(extra_classes)
		pool += extra_classes

	var/list/step = question_step("class", /datum/prompt/choice, question = "What kind of data?", title = "Variable Type", choices = pool, default = default_class)
	step["optional"] = allow_finish // closing the list of kinds ends a list being filled
	return step

/// The kind is known: the marked and tagged datums resolve at once, every other kind asks what it needs.
/datum/ask_sequence/picker/vv_pick/proc/open_class()
	if(isnull(class))
		class = "finish"
		return ASK_FINISH

	var/client/admin = actor()?.client
	var/datum/admins/holder = admin_holder_of(admin)
	if(holder && holder.marked_datum() && markstring && class == markstring)
		class = VV_MARKED_DATUM

	if(holder && tag_places?[class])
		put("value", holder.tagged_datums[tag_places[class]])
		class = VV_TAGGED_DATUM

	switch(class)
		if(VV_TEXT)
			add_steps(list(question_step("value", /datum/prompt/text, question = "Enter new text:", title = "Text", default = current_value)))
		if(VV_MESSAGE)
			add_steps(list(question_step("value", /datum/prompt/text, question = "Enter new text:", title = "Text", default = current_value, multiline = TRUE, max_len = MAX_TGUI_INPUT, name_text = ((MAX_TGUI_INPUT) <= MAX_NAME_LEN))))
		if(VV_NUM)
			add_steps(list(question_step("value", /datum/prompt/number, question = "Enter new number:", title = "Num", default = current_value, max_value = INFINITY, min_value = -INFINITY, round_entry = FALSE)))
		if(VV_BITFIELD)
			add_steps(list(question_step("value", /datum/prompt/bitfield, title = "Editing bitfield: [var_name]", bitfield = var_name, default = current_value)))
		if(VV_ATOM_TYPE)
			return ask_child(/datum/ask_sequence/picker/type_pick, "value", list("matches" = GLOBAL_TABLE_GET(get_fancy_list_of_atom_types)))
		if(VV_DATUM_TYPE)
			return ask_child(/datum/ask_sequence/picker/type_pick, "value", list("matches" = GLOBAL_TABLE_GET(get_fancy_list_of_datum_types)))
		if(VV_TYPE)
			add_steps(list(
				question_step("typed", /datum/prompt/text, question = "Enter type:", title = "Type", default = current_value),
				PROC_REF(read_typed)))
		if(VV_ATOM_REFERENCE)
			ref_matches = GLOBAL_TABLE_GET(get_fancy_list_of_atom_types)
			add_reference_steps()
		if(VV_DATUM_REFERENCE)
			ref_matches = GLOBAL_TABLE_GET(get_fancy_list_of_datum_types)
			add_reference_steps()
		if(VV_MOB_REFERENCE)
			ref_matches = make_types_fancy(typesof(/mob))
			add_reference_steps()
		if(VV_CLIENT)
			add_steps(list(question_step("value", /datum/prompt/choice, question = "Select reference:", title = "Reference", choices = GLOB.clients, default = current_value)))
		if(VV_FILE)
			add_steps(list(PROC_REF(ask_file)))
		if(VV_ICON)
			return ask_child(/datum/ask_sequence/picker/icon_pick, "value", list("pick_only" = TRUE))
		if(VV_MARKED_DATUM)
			put("value", holder?.marked_datum())
			if(isnull(get("value")))
				return ASK_STOP
		if(VV_TAGGED_DATUM)
			if(isnull(get("value")))
				return ASK_STOP
		if(VV_PROCCALL_RETVAL)
			add_steps(list(PROC_REF(ask_proccall), PROC_REF(need_value)))
		if(VV_NEW_ATOM)
			add_steps(list(PROC_REF(ask_new_atom_type), PROC_REF(make_new_atom)))
		if(VV_NEW_DATUM)
			add_steps(list(PROC_REF(ask_new_datum_type), PROC_REF(make_new_datum)))
		if(VV_NEW_TYPE)
			add_steps(list(
				question_step("typed", /datum/prompt/text, question = "Enter type:", title = "Type", default = current_value),
				PROC_REF(read_typed),
				PROC_REF(make_new_typed)))
		if(VV_NEW_LIST)
			value_type = /list
			add_steps(list(
				question_step("populate", /datum/prompt/choice, question = "Would you like to populate the list", title = "Populate List?", choices = list("Yes", "No"), buttons = TRUE),
				PROC_REF(read_populate)))
		if(VV_TEXT_LOCATE)
			add_steps(list(
				question_step("locate_ref", /datum/prompt/text, question = "Enter reference:", title = "Reference"),
				PROC_REF(read_locate)))
		if(VV_COLOR)
			add_steps(list(question_step("value", /datum/prompt/color, question = "Enter new color:", title = "Color", default = current_value)))
		if(VV_INFINITY)
			put("value", INFINITY)
	return null

/datum/ask_sequence/picker/vv_pick/proc/need_value()
	if(isnull(get("value")))
		return ASK_STOP
	return null

/// A type typed in by path; one that doesn't exist is refused.
/datum/ask_sequence/picker/vv_pick/proc/read_typed()
	if(!typed)
		return ASK_STOP
	var/path = text2path(typed)
	if(!path)
		to_chat(actor(), span_warning("Type not found."), confidential = TRUE)
		return ASK_STOP
	new_type = path
	if(class == VV_TYPE)
		put("value", path)
	return null

/datum/ask_sequence/picker/vv_pick/proc/add_reference_steps()
	add_steps(list(PROC_REF(ask_ref_path), PROC_REF(ask_ref_subtypes), PROC_REF(ask_ref_choice), PROC_REF(read_ref_choice)))

/datum/ask_sequence/picker/vv_pick/proc/ask_ref_path()
	return ask_child(/datum/ask_sequence/picker/type_pick, "ref_path", list("matches" = ref_matches))

/datum/ask_sequence/picker/vv_pick/proc/ask_ref_subtypes()
	if(!ispath(ref_path))
		return ASK_STOP
	return ask_child(/datum/ask_sequence/picker/subtype_pick, "strict_subtypes", list("target_type" = ref_path))

/datum/ask_sequence/picker/vv_pick/proc/ask_ref_choice()
	return question_step("value", /datum/prompt/choice, question = "Select reference:", title = "Reference", choices = vv_reference_list(ref_path, strict_subtypes), default = current_value)

/datum/ask_sequence/picker/vv_pick/proc/read_ref_choice()
	var/picked = get("value")
	var/list/things = vv_reference_list(ref_path, strict_subtypes)
	if(!picked || !things[picked])
		return ASK_STOP
	put("value", things[picked])
	return null

/datum/ask_sequence/picker/vv_pick/proc/ask_file()
	var/file = input(actor(), "Pick file:", "File") as null|file // ALLOW(scheduler): file uploads need the BYOND file dialog
	if(isnull(file))
		return ASK_STOP
	put("value", file)
	return null

/// The call runs when its questions are answered; its return value is the value.
/datum/ask_sequence/picker/vv_pick/proc/ask_proccall()
	return ask_child(/datum/ask_sequence/admin/callproc, "value", list("want_result" = TRUE))

/datum/ask_sequence/picker/vv_pick/proc/ask_new_atom_type()
	return ask_child(/datum/ask_sequence/picker/type_pick, "new_type", list("matches" = GLOBAL_TABLE_GET(get_fancy_list_of_atom_types)))

/datum/ask_sequence/picker/vv_pick/proc/ask_new_datum_type()
	return ask_child(/datum/ask_sequence/picker/type_pick, "new_type", list("matches" = GLOBAL_TABLE_GET(get_fancy_list_of_datum_types)))

/datum/ask_sequence/picker/vv_pick/proc/make_new_atom()
	if(!new_type)
		return ASK_STOP
	value_type = new_type
	var/atom/newguy = new new_type()
	newguy.datum_flags |= DF_VAR_EDITED
	put("value", newguy)
	return null

/datum/ask_sequence/picker/vv_pick/proc/make_new_datum()
	if(!new_type)
		return ASK_STOP
	value_type = new_type
	var/datum/newguy = new new_type()
	newguy.datum_flags |= DF_VAR_EDITED
	put("value", newguy)
	return null

/datum/ask_sequence/picker/vv_pick/proc/make_new_typed()
	value_type = new_type
	var/datum/newguy = new new_type()
	if(istype(newguy))
		newguy.datum_flags |= DF_VAR_EDITED
	put("value", newguy)
	return null

/datum/ask_sequence/picker/vv_pick/proc/read_populate()
	put("value", list())
	if(populate == "No")
		return ASK_FINISH
	add_steps(list(PROC_REF(ask_item), PROC_REF(take_item)))
	return null

/// One entry after another; closing the kind list finishes the list.
/datum/ask_sequence/picker/vv_pick/proc/ask_item()
	item_count++
	return ask_child(/datum/ask_sequence/picker/vv_pick, "item", list("restricted_classes" = list(VV_RESTORE_DEFAULT), "allow_finish" = TRUE))

/datum/ask_sequence/picker/vv_pick/proc/take_item()
	if(item["class"] == "finish")
		return ASK_FINISH
	if(!item["class"])
		return ASK_STOP
	var/list/entries = get("value")
	entries += LIST_VALUE_WRAP_LISTS(item["value"])
	if(item_count < 1000)
		add_steps(list(PROC_REF(ask_item), PROC_REF(take_item)))
	return null

/datum/ask_sequence/picker/vv_pick/proc/read_locate()
	if(!locate_ref)
		return ASK_STOP
	var/datum/D = locate(locate_ref)
	if(!D)
		tgui_alert_async(actor(), "Invalid ref!")
		return ASK_STOP
	value_type = D.type
	put("value", D)
	return null

/// The things of `type` (and its subtypes when `subtypes`) a reference can be picked from, by name.
/proc/vv_reference_list(type, subtypes)
	. = list()
	var/list/types = list(type)
	if (subtypes)
		types = typesof(type)

	var/list/fancytypes = make_types_fancy(types)

	for(var/fancytype in fancytypes) //swap the assoication
		types[fancytypes[fancytype]] = fancytype

	var/things = get_all_of_type(type, subtypes)

	var/i = 0
	for(var/thing in things)
		var/datum/D = thing
		i++
		//try one of 3 methods to shorten the type text:
		// fancy type,
		// fancy type with the base type removed from the begaining,
		// the type with the base type removed from the begaining
		var/fancytype = types[D.type]
		if (findtext(fancytype, types[type]))
			fancytype = copytext(fancytype, length(types[type]) + 1)
		var/shorttype = copytext("[D.type]", length("[type]") + 1)
		if (length_char(shorttype) > length_char(fancytype))
			shorttype = fancytype
		if (!length(shorttype))
			shorttype = "/"

		.["[D]([shorttype])[ref_token(D)]#[i]"] = D

// ---------------------------------------------------------------- the tools' own sequences

/// The questions of an admin tool run by a client: the steps and on_done are procs of that client, and its code still reads usr, so they run as the admin.
/datum/ask_sequence/admin
	as_actor = TRUE

/// Starts `sequence_type`'s questions of this client's mob. `steps` null: the type's initial_steps(). `kept` is the tool's own state for on_done (read back as sequence.kept).
/client/proc/ask_admin(sequence_type, datum/subject, list/steps, on_done, list/params, list/kept)
	var/list/set_params = params ? params.Copy() : list()
	if(kept)
		set_params["kept"] = kept
	var/started = ask_sequence_begin(src, sequence_type, mob, subject, steps, on_done, null, null, set_params)
	if(istext(started))
		log_admin("[key_name(src)]: [sequence_type] did not ask its questions ([started])")
	return started
