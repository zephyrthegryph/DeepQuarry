// These pins contain a list.  Null is not allowed.
/datum/integrated_io/list
	name = "list pin"
	data = list()


/datum/integrated_io/list/ask_for_pin_data(mob/user)
	interact(user)

// interact() body moved to code/modules/integrated_electronics/list_pin_panel.dm (structured TGUI).
/datum/integrated_io/list/proc/interact(mob/user)
	return  // body provided by modular override

/datum/integrated_io/list/proc/add_to_list(mob/user, new_entry)
	if(!new_entry && user)
		ask_for_data_type(user, on_value = PROC_REF(list_entry_chosen))
		return
	if(is_valid(new_entry))
		Add(new_entry)

/datum/integrated_io/list/proc/list_entry_chosen(mob/user, new_entry, datum/pin_value_review/seq)
	if(is_valid(new_entry))
		Add(new_entry)

/datum/integrated_io/list/proc/Add(new_entry)
	var/list/my_list = data
	if(my_list.len > IC_MAX_LIST_LENGTH)
		my_list.Cut(Start=1,End=2)
	my_list.Add(new_entry)

/datum/integrated_io/list/proc/remove_from_list_by_position(mob/user, position)
	var/list/my_list = data
	if(!my_list.len)
		to_chat(user, span_warning("The list is empty, there's nothing to remove."))
		return
	if(!position || position < 1 || position > my_list.len)
		return
	var/target_entry = my_list[position]
	if(target_entry)
		my_list.Remove(target_entry)

/datum/integrated_io/list/proc/remove_from_list(mob/user, target_entry)
	var/list/my_list = data
	if(!my_list.len)
		to_chat(user, span_warning("The list is empty, there's nothing to remove."))
		return
	if(!target_entry)
		start_list_selection(user, "remove")
		return
	if(target_entry)
		my_list.Remove(target_entry)

/datum/integrated_io/list/proc/edit_in_list(mob/user, target_entry)
	var/list/my_list = data
	if(!my_list.len)
		to_chat(user, span_warning("The list is empty, there's nothing to modify."))
		return
	if(!target_entry)
		start_list_selection(user, "edit")
		return
	if(target_entry)
		var/datum/pin_value_review/list_edit/review = new
		review.capture_entry(target_entry)
		ask_for_data_type(user, target_entry, on_value = PROC_REF(list_entry_edited), sequence = review)

/// A list entry being edited: the entry, and its position when edited by position.
/datum/pin_value_review/list_edit
	var/entry_scalar
	var/datum/entry_entity
	var/entry_entity_selected = FALSE
	var/entry_client_ckey
	var/entry_client_selected = FALSE
	var/position

CAPABILITIES(/datum/pin_value_review/list_edit)
	ref_one(nameof(entry_entity), /datum)

/datum/pin_value_review/list_edit/proc/capture_entry(entry, position)
	src.position = position
	if(istype(entry, /client))
		var/client/C = entry
		entry_client_selected = TRUE
		entry_client_ckey = C.ckey
	else if(isdatum(entry))
		entry_entity_selected = TRUE
		rel_set(src, nameof(entry_entity), entry)
	else
		entry_scalar = entry

/datum/pin_value_review/list_edit/proc/entry_value()
	if(entry_client_selected)
		return GLOB.directory[entry_client_ckey]
	return entry_entity_selected ? entry_entity : entry_scalar

/datum/pin_value_review/list_edit/why_not()
	. = ..()
	if(.)
		return
	if(entry_entity_selected && QDELETED(entry_entity))
		return "gone"
	if(entry_client_selected && !entry_value())
		return "gone"

/// The entry is found again by value: it may have moved while they typed.
/datum/integrated_io/list/proc/list_entry_edited(mob/user, edited_entry, datum/pin_value_review/list_edit/seq)
	var/list/my_list = data
	if(!edited_entry)
		return
	var/position = seq.position
	if(position)
		if(position <= my_list.len && my_list[position] == seq.entry_value())
			my_list[position] = edited_entry
		return
	var/idx = my_list.Find(seq.entry_value())
	if(idx)
		my_list[idx] = edited_entry

/datum/integrated_io/list/proc/edit_in_list_by_position(mob/user, position)
	var/list/my_list = data
	if(!my_list.len)
		to_chat(user, span_warning("The list is empty, there's nothing to modify."))
		return
	if(!position || position < 1 || position > my_list.len)
		return
	var/target_entry = my_list[position]
	if(target_entry)
		var/datum/pin_value_review/list_edit/review = new
		review.capture_entry(target_entry, position)
		ask_for_data_type(user, target_entry, on_value = PROC_REF(list_entry_edited), sequence = review)

/datum/integrated_io/list/proc/swap_inside_list(mob/user, first_target, second_target)
	var/list/my_list = data
	if(my_list.len <= 1)
		to_chat(user, span_warning("The list is empty, or too small to do any meaningful swapping."))
		return
	if(!first_target || !second_target)
		start_list_selection(user, "swap", first_target, second_target)
		return

	if(first_target)

		if(second_target)
			var/first_pos = my_list.Find(first_target)
			var/second_pos = my_list.Find(second_target)
			my_list.Swap(first_pos, second_pos)

/datum/integrated_io/list/proc/clear_list(mob/user)
	var/list/my_list = data
	my_list.Cut()

/datum/integrated_io/list/scramble()
	var/list/my_list = data
	my_list = shuffle(my_list)
	push_data()

/datum/integrated_io/list/write_data_to_pin(new_data)
	if(islist(new_data))
		var/list/new_list = new_data
		data = new_list.Copy()
		holder().on_data_written()

/datum/integrated_io/list/display_pin_type()
	return IC_FORMAT_LIST


/// List selection retains arbitrary values using the same weak capture rules as pin editing.
/datum/pin_value_review/list_edit/selection
	var/action
	var/original_client_ckey
	var/selecting_second = FALSE

/datum/prompt/choice/pin_list_selection
	timeout = 0

/datum/prompt/choice/pin_list_selection/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/pin_value_review/list_edit/selection/review = owner
	if(review.why_not())
		return "gone"
	var/datum/selected = value
	if(isdatum(selected) && QDELETED(selected))
		return "gone"

/datum/integrated_io/list/proc/start_list_selection(mob/user, action, first_target, second_target)
	var/original_client_ckey
	if(istype(user, /client))
		var/client/C = user
		original_client_ckey = C.ckey
		user = C.mob
	if(!ismob(user) || QDELETED(user))
		return
	var/datum/pin_value_review/list_edit/selection/review = new
	rel_set(review, nameof(review.actor), user)
	rel_set(review, nameof(review.pin), src)
	review.action = action
	review.original_client_ckey = original_client_ckey
	review.capture_default(first_target)
	review.capture_entry(second_target)
	review.selecting_second = !!first_target
	review.begin_selection()

/datum/pin_value_review/list_edit/selection/proc/begin_selection()
	if(why_not())
		retire()
		return
	var/datum/result/result = safe_call(PROC_REF(open_selection))
	if(!result.ok)
		stack_trace("[type] open_selection: [result.error]")
		retire()

/datum/pin_value_review/list_edit/selection/why_not()
	. = ..()
	if(.)
		return
	if(original_client_ckey && !GLOB.directory[original_client_ckey])
		return "gone"

/datum/pin_value_review/list_edit/selection/proc/open_selection()
	if(why_not())
		retire()
		return
	var/datum/integrated_io/list_pin = pin
	var/list/my_list = list_pin.data
	var/title
	var/question
	var/list/choices = my_list
	switch(action)
		if("remove")
			title = "Remove"
			question = "Which piece of data do you want to remove?"
		if("edit")
			title = "Edit"
			question = "Which piece of data do you want to edit?"
		if("swap")
			title = "Swap"
			question = "Which piece of data do you want to swap? ([selecting_second ? 2 : 1])"
			if(selecting_second)
				choices = my_list - default_value()
	open_request(src, /datum/prompt/choice/pin_list_selection, PROC_REF(selection_entered), answerer = actor, title = title, question = question, choices = choices)

/datum/pin_value_review/list_edit/selection/proc/selection_entered(datum/act/request/A)
	var/datum/integrated_io/refreshed_pin = pin
	var/refresh = A.answer && !why_not()
	run_step(PROC_REF(selection_step), A)
	if(refresh && !QDELETED(refreshed_pin))
		SStgui.update_uis(refreshed_pin)

/datum/pin_value_review/list_edit/selection/proc/selection_step(datum/act/request/A)
	var/selected = A.answer.value
	if(!selected)
		retire()
		return
	var/datum/integrated_io/list_pin = pin
	var/mob/user = original_client_ckey ? GLOB.directory[original_client_ckey] : actor
	switch(action)
		if("remove")
			call(list_pin, TYPE_PROC_REF(/datum/integrated_io/list, remove_from_list))(user, selected)
		if("edit")
			call(list_pin, TYPE_PROC_REF(/datum/integrated_io/list, edit_in_list))(user, selected)
		if("swap")
			if(!selecting_second)
				capture_default(selected)
				if(entry_value())
					call(list_pin, TYPE_PROC_REF(/datum/integrated_io/list, swap_inside_list))(user, default_value(), entry_value())
				else
					var/list/my_list = list_pin.data
					if(my_list.len <= 1)
						call(list_pin, TYPE_PROC_REF(/datum/integrated_io/list, swap_inside_list))(user)
					else
						selecting_second = TRUE
						open_selection()
						return
			else
				call(list_pin, TYPE_PROC_REF(/datum/integrated_io/list, swap_inside_list))(user, default_value(), selected)
	retire()
