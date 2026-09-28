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

/datum/integrated_io/list/proc/list_entry_chosen(mob/user, new_entry, datum/om/prompt/P)
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
		var/_answer_k48 = rerun_prompt(user, "k48", list("kind" = "list", "message" = "Which piece of data do you want to remove?", "title" = "Remove", "choices" = my_list), PROC_REF(remove_from_list), args)
		if(isnull(_answer_k48))
			return
		target_entry = _answer_k48
	if(target_entry)
		my_list.Remove(target_entry)

/datum/integrated_io/list/proc/edit_in_list(mob/user, target_entry)
	var/list/my_list = data
	if(!my_list.len)
		to_chat(user, span_warning("The list is empty, there's nothing to modify."))
		return
	if(!target_entry)
		var/_answer_k58 = rerun_prompt(user, "k58", list("kind" = "list", "message" = "Which piece of data do you want to edit?", "title" = "Edit", "choices" = my_list), PROC_REF(edit_in_list), args)
		if(isnull(_answer_k58))
			return
		target_entry = _answer_k58
	if(target_entry)
		ask_for_data_type(user, target_entry, on_value = PROC_REF(list_entry_edited), data = list("target" = target_entry))

/// The entry is found again by value: it may have moved while they typed.
/datum/integrated_io/list/proc/list_entry_edited(mob/user, edited_entry, datum/om/prompt/P)
	var/list/my_list = data
	if(!edited_entry)
		return
	var/position = P.get("position")
	if(position)
		if(position <= my_list.len && my_list[position] == P.get("target"))
			my_list[position] = edited_entry
		return
	var/idx = my_list.Find(P.get("target"))
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
		ask_for_data_type(user, target_entry, on_value = PROC_REF(list_entry_edited), data = list("target" = target_entry, "position" = position))

/datum/integrated_io/list/proc/swap_inside_list(mob/user, first_target, second_target)
	var/list/my_list = data
	if(my_list.len <= 1)
		to_chat(user, span_warning("The list is empty, or too small to do any meaningful swapping."))
		return
	if(!first_target)
		var/_answer_k93 = rerun_prompt(user, "k93", list("kind" = "list", "message" = "Which piece of data do you want to swap? (1)", "title" = "Swap", "choices" = my_list), PROC_REF(swap_inside_list), args)
		if(isnull(_answer_k93))
			return
		first_target = _answer_k93

	if(first_target)
		if(!second_target)
			var/_answer_k97 = rerun_prompt(user, "k97", list("kind" = "list", "message" = "Which piece of data do you want to swap? (2)", "title" = "Swap", "choices" = my_list - first_target), PROC_REF(swap_inside_list), args)
			if(isnull(_answer_k97))
				return
			second_target = _answer_k97

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

/datum/integrated_io/list/Topic(href, href_list, state = GLOB.tgui_always_state)
	if(!holder().check_interactivity(usr))
		return
	if(..())
		return 1

	if(href_list["add"])
		add_to_list(usr)

	if(href_list["swap"])
		swap_inside_list(usr)

	if(href_list["clear"])
		clear_list(usr)

	if(href_list["remove"])
		if(href_list["pos"])
			remove_from_list_by_position(usr, text2num(href_list["pos"]))
		else
			remove_from_list(usr)

	if(href_list["edit"])
		if(href_list["pos"])
			edit_in_list_by_position(usr, text2num(href_list["pos"]))
		else
			edit_in_list(usr)

	holder().interact(usr) // Refresh the main UI,
	interact(usr) // and the list UI.
