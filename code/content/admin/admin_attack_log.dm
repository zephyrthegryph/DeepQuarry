/// `user` is who did it (null: the game did, logged as an EVENT).
/proc/log_and_message_admins(message as text, mob/user)
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
