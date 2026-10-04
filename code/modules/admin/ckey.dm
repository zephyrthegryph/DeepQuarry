// Command to set the ckey of a mob without requiring VV permission
/client/proc/SetCKey(mob/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
	set category = VERB_CAT_ADMIN_GAME
	set name = "Set CKey"
	set desc = "Mob to teleport"
	if(!admin_can(src, 0))
		to_chat(src, "Only administrators may use this command.")
		return

	var/list/keys = list()
	for(var/mob/playerMob in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		keys += playerMob.client
	var/client/selection = client_ask("a1", PROC_REF(SetCKey), args, 0, /datum/om/prompt/choice, message = "Please, select a player!", title = "Set CKey", choices = sortKey(keys))
	if(isnull(selection))
		return
	if(!selection || !istype(selection))
		return

	log_admin("[key_name(usr)] set ckey of [key_name(M)] to [selection]")
	message_admins("[key_name_admin(usr)] set ckey of [key_name_admin(M)] to [selection]", 1)
	M.ckey = selection.ckey
	feedback_add_details("admin_verb","SCK") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
