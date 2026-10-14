// VV actions on a list (lists aren't datums, so they are the admin client's rows).

/client/proc/vv_topic_list_edit(mob/user, href_target, href_targetvar)
	var/target_index = href_targetvar
	if(!target_index)
		return
	mod_list(href_target, null, "list", "contents", target_index, autodetect_class = TRUE)
	return TRUE

/client/proc/vv_topic_list_change(mob/user, href_target, href_targetvar)
	var/target_index = href_targetvar
	if(!target_index)
		return
	mod_list(href_target, null, "list", "contents", target_index, autodetect_class = FALSE)
	return TRUE

/client/proc/vv_topic_list_remove(mob/user, href_target, href_targetvar)
	var/list/target = href_target
	var/target_index = href_targetvar
	if(!target_index || target_index > length(target))
		return
	var/variable = target[target_index]
	var/prompt = flow_ask(mob, "list:remove", /datum/prompt/choice, question = "Do you want to remove item number [target_index] from list?", title = "Confirm", choices = list("Yes", "No"), buttons = TRUE)
	if (prompt != "Yes")
		return
	target.Cut(target_index, target_index+1)
	log_world("### ListVarEdit by [src]: /list's contents: REMOVED=[html_encode("[variable]")]")
	log_admin("[key_name(src)] modified list's contents: REMOVED=[variable]")
	message_admins("[key_name_admin(src)] modified list's contents: REMOVED=[variable]")
	return TRUE

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
	var/value = vv_get_value(VV_NUM)
	if (value["class"] != VV_NUM || value["value"] > max(50000, target.len)) //safety - would rather someone not put an extra 0 and erase the server's memory lmao.
		return
	target.len = value["value"]
	log_world("### ListVarEdit by [src]: /list len: [target.len]")
	log_admin("[key_name(src)] modified list's len: [target.len]")
	message_admins("[key_name_admin(src)] modified list's len: [target.len]")
	return TRUE

/client/proc/vv_topic_list_shuffle(mob/user, href_target)
	shuffle_inplace(href_target)
	log_world("### ListVarEdit by [src]: /list contents: SHUFFLE")
	log_admin("[key_name(src)] modified list's contents: SHUFFLE")
	message_admins("[key_name_admin(src)] modified list's contents: SHUFFLE")
	return TRUE
