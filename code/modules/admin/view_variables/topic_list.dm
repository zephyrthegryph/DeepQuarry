// VV actions on a list (lists aren't datums, so they are the admin client's rows).

/client/proc/vv_topic_list_edit(mob/user, href_target, href_targetvar)
	var/target_index = href_targetvar
	if(!target_index)
		return
	mod_list(href_target, null, "list", "contents", target_index, TRUE)
	return TRUE

/client/proc/vv_topic_list_change(mob/user, href_target, href_targetvar)
	var/target_index = href_targetvar
	if(!target_index)
		return
	mod_list(href_target, null, "list", "contents", target_index, FALSE)
	return TRUE

/client/proc/vv_topic_list_remove(mob/user, href_target, href_targetvar)
	var/list/target = href_target
	var/target_index = href_targetvar
	if(!target_index || target_index > length(target))
		return
	ask_admin(/datum/ask_sequence/admin, null, list(
		question_step("confirm", /datum/prompt/choice, question = "Do you want to remove item number [target_index] from list?", title = "Confirm", choices = list("Yes", "No"), buttons = TRUE)),
		PROC_REF(vv_list_item_removed), null, list("list" = target, "index" = target_index))
	return TRUE

/client/proc/vv_list_item_removed(datum/ask_sequence/admin/asked)
	var/list/target = asked.kept["list"]
	var/target_index = asked.kept["index"]
	if(!target_index || target_index > length(target))
		return
	var/variable = target[target_index]
	if (asked.get("confirm") != "Yes")
		return
	target.Cut(target_index, target_index+1)
	log_world("### ListVarEdit by [src]: /list's contents: REMOVED=[html_encode("[variable]")]")
	log_admin("[key_name(src)] modified list's contents: REMOVED=[variable]")
	message_admins("[key_name_admin(src)] modified list's contents: REMOVED=[variable]")

/client/proc/vv_topic_list_add(mob/user, href_target)
	mod_list_add(href_target, null, "list", "contents")
	return TRUE

/client/proc/vv_topic_list_dupes(mob/user, href_target)
	uniqueList_inplace(href_target)
	log_world("### ListVarEdit by [src]: /list contents: CLEAR DUPES")
	log_admin("[key_name(src)] modified list's contents: CLEAR DUPES")
	message_admins("[key_name_admin(src)] modified list's contents: CLEAR DUPES")
	return TRUE

/client/proc/vv_topic_list_nulls(mob/user, href_target)
	list_clear_nulls(href_target)
	log_world("### ListVarEdit by [src]: /list contents: CLEAR NULLS")
	log_admin("[key_name(src)] modified list's contents: CLEAR NULLS")
	message_admins("[key_name_admin(src)] modified list's contents: CLEAR NULLS")
	return TRUE

/client/proc/vv_topic_list_length(mob/user, href_target)
	var/list/target = href_target
	ask_admin(/datum/ask_sequence/admin/vv_value, null, null, PROC_REF(vv_list_length_picked), list("pick_params" = list("class" = VV_NUM)), list("list" = target))
	return TRUE

/client/proc/vv_list_length_picked(datum/ask_sequence/admin/vv_value/asked)
	var/list/target = asked.kept["list"]
	var/list/value = asked.get("picked")
	if (value["class"] != VV_NUM || value["value"] > max(50000, target.len)) //safety - would rather someone not put an extra 0 and erase the server's memory lmao.
		return
	target.len = value["value"]
	log_world("### ListVarEdit by [src]: /list len: [target.len]")
	log_admin("[key_name(src)] modified list's len: [target.len]")
	message_admins("[key_name_admin(src)] modified list's len: [target.len]")

/client/proc/vv_topic_list_shuffle(mob/user, href_target)
	shuffle_inplace(href_target)
	log_world("### ListVarEdit by [src]: /list contents: SHUFFLE")
	log_admin("[key_name(src)] modified list's contents: SHUFFLE")
	message_admins("[key_name_admin(src)] modified list's contents: SHUFFLE")
	return TRUE
