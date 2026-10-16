/// The recorded live actor, or null after that actor is deleted.
/proc/last_attacker_of(atom/target) as /mob
	return link_get(target, LK_LAST_ATTACKER)

/// Recording another attack replaces the old non-owning attribution link.
/proc/set_last_attacker(atom/target, mob/actor)
	return link_set_one(target, LK_LAST_ATTACKER, actor)

/proc/log_and_message_admins(message as text, mob/user = usr)
	log_admin(user ? "[key_name(user)] [message]" : "EVENT [message]")
	message_admins(user ? "[key_name_admin(user)] [message]" : "EVENT [message]")

/proc/log_and_message_admins_many(list/mob/users, message)
	if(!users || !users.len)
		return

	var/list/user_keys = list()
	for(var/mob/user in users)
		user_keys += key_name(user)

	log_admin("[english_list(user_keys)] [message]")
	message_admins("[english_list(user_keys)] [message]")
