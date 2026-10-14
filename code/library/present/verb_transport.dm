/client/present_verb_changes(list/add, list/remove)
	if(!stat_panel)
		return
	if(remove)
		stat_panel.send_message("remove_verb_list", remove)
	if(add)
		stat_panel.send_message("add_verb_list", add)
