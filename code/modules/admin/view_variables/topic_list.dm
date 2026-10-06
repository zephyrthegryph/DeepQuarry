// VV actions on a list (lists aren't datums, so they are the admin client's rows).

#define VV_LIST_TARGET TOPIC_REF(VV_HK_TARGET, /list, TOPIC_ANY)

VV_ADMIN_TOPIC_ACTION(VV_HK_LIST_EDIT, PROC_REF(vv_topic_list_edit), VV_LIST_TARGET, TOPIC_NUM(VV_HK_VARNAME))
VV_ADMIN_TOPIC_ACTION(VV_HK_LIST_CHANGE, PROC_REF(vv_topic_list_change), VV_LIST_TARGET, TOPIC_NUM(VV_HK_VARNAME))
VV_ADMIN_TOPIC_ACTION(VV_HK_LIST_REMOVE, PROC_REF(vv_topic_list_remove), VV_LIST_TARGET, TOPIC_NUM(VV_HK_VARNAME))
VV_ADMIN_TOPIC_ACTION(VV_HK_LIST_ADD, PROC_REF(vv_topic_list_add), VV_LIST_TARGET)
VV_ADMIN_TOPIC_ACTION(VV_HK_LIST_ERASE_DUPES, PROC_REF(vv_topic_list_dupes), VV_LIST_TARGET)
VV_ADMIN_TOPIC_ACTION(VV_HK_LIST_ERASE_NULLS, PROC_REF(vv_topic_list_nulls), VV_LIST_TARGET)
VV_ADMIN_TOPIC_ACTION(VV_HK_LIST_SET_LENGTH, PROC_REF(vv_topic_list_length), VV_LIST_TARGET)
VV_ADMIN_TOPIC_ACTION(VV_HK_LIST_SHUFFLE, PROC_REF(vv_topic_list_shuffle), VV_LIST_TARGET)

#undef VV_LIST_TARGET

/client/proc/vv_topic_list_edit(mob/user, list/args)
	var/target_index = args[VV_HK_VARNAME]
	if(!target_index)
		return
	mod_list(args[VV_HK_TARGET], null, "list", "contents", target_index, autodetect_class = TRUE)
	return TRUE

/client/proc/vv_topic_list_change(mob/user, list/args)
	var/target_index = args[VV_HK_VARNAME]
	if(!target_index)
		return
	mod_list(args[VV_HK_TARGET], null, "list", "contents", target_index, autodetect_class = FALSE)
	return TRUE

/client/proc/vv_topic_list_remove(mob/user, list/args)
	var/list/target = args[VV_HK_TARGET]
	var/target_index = args[VV_HK_VARNAME]
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

/client/proc/vv_topic_list_add(mob/user, list/args)
	mod_list_add(args[VV_HK_TARGET], null, "list", "contents")
	return TRUE

/client/proc/vv_topic_list_dupes(mob/user, list/args)
	uniqueList_inplace(args[VV_HK_TARGET])
	log_world("### ListVarEdit by [src]: /list contents: CLEAR DUPES")
	log_admin("[key_name(src)] modified list's contents: CLEAR DUPES")
	message_admins("[key_name_admin(src)] modified list's contents: CLEAR DUPES")
	return TRUE

/client/proc/vv_topic_list_nulls(mob/user, list/args)
	list_clear_nulls(args[VV_HK_TARGET])
	log_world("### ListVarEdit by [src]: /list contents: CLEAR NULLS")
	log_admin("[key_name(src)] modified list's contents: CLEAR NULLS")
	message_admins("[key_name_admin(src)] modified list's contents: CLEAR NULLS")
	return TRUE

/client/proc/vv_topic_list_length(mob/user, list/args)
	var/list/target = args[VV_HK_TARGET]
	var/value = vv_get_value(VV_NUM)
	if (value["class"] != VV_NUM || value["value"] > max(50000, target.len)) //safety - would rather someone not put an extra 0 and erase the server's memory lmao.
		return
	target.len = value["value"]
	log_world("### ListVarEdit by [src]: /list len: [target.len]")
	log_admin("[key_name(src)] modified list's len: [target.len]")
	message_admins("[key_name_admin(src)] modified list's len: [target.len]")
	return TRUE

/client/proc/vv_topic_list_shuffle(mob/user, list/args)
	shuffle_inplace(args[VV_HK_TARGET])
	log_world("### ListVarEdit by [src]: /list contents: SHUFFLE")
	log_admin("[key_name(src)] modified list's contents: SHUFFLE")
	message_admins("[key_name_admin(src)] modified list's contents: SHUFFLE")
	return TRUE
