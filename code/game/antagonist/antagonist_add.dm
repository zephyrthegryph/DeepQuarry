/datum/antagonist/proc/add_antagonist(datum/mind/player, ignore_role, do_not_equip, move_to_spawn, do_not_announce, preserve_appearance)

	if(!add_antagonist_mind(player, ignore_role))
		return

	//do this again, just in case
	if(flags & ANTAG_OVERRIDE_JOB)
		player.assigned_role = role_text
	player.special_role = role_text

	if(isobserver(player.current))
		create_default(player.current)
	else
		create_antagonist(player, move_to_spawn, do_not_announce, preserve_appearance)
		if(!do_not_equip)
			equip(player.current)
	return 1

/datum/antagonist/proc/add_antagonist_mind(datum/mind/player, ignore_role, nonstandard_role_type, nonstandard_role_msg)
	if(!istype(player))
		return 0
	if(!player.current)
		return 0
	if(player in current_antagonists)
		return 0
	if(!can_become_antag(player, ignore_role))
		return 0
	rel_add(src, nameof(current_antagonists), player)

	if(faction_verb && player.current)
		grant(player.current, granted_verb(faction_verb), src)

	var/msg = span_notice("Once you decide on a goal to pursue, you can optionally display it to \
		everyone at the end of the shift with the " + span_bold("Set Ambition") + " verb, located in the IC tab.  You can change this at any time, \
		and it otherwise has no bearing on your round.")
	after(player.current, 1 SECOND, GLOBAL_PROC_REF(to_chat), with = list(player.current, msg)) //Added a delay so that this should pop up at the bottom and not the top of the text flood the new antag gets.
	grant(player.current, granted_verb(/mob/living/proc/write_ambition), src)

	if(can_speak_aooc)
		grant(player.current.client, granted_verb(/client/proc/aooc), player)

	// Handle only adding a mind and not bothering with gear etc.
	if(nonstandard_role_type)
		rel_add(src, nameof(faction_members), player)
		to_chat(player.current, span_danger(span_large("You are \a [nonstandard_role_type]!")))
		player.special_role = nonstandard_role_type
		if(nonstandard_role_msg)
			to_chat(player.current, span_notice("[nonstandard_role_msg]"))
		update_icons_added(player)
	return 1

/datum/antagonist/proc/remove_antagonist(datum/mind/player, show_message, implanted)
	if(player.current && faction_verb)
		revoke(player.current, granted_verb(faction_verb), src)
	if(player in current_antagonists)
		to_chat(player.current, span_danger(span_large("You are no longer a [role_text]!")))
		rel_remove(src, nameof(current_antagonists), player)
		rel_remove(src, nameof(faction_members), player)
		player.special_role = null
		update_icons_removed(player)
		player.current.flag_hud_update(SPECIALROLE_HUD)
		if(!is_special_character(player))
			revoke(player.current, granted_verb(/mob/living/proc/write_ambition), src)
			if(player.current.client)
				revoke(player.current.client, granted_verb(/client/proc/aooc), player)
			player.ambitions = ""
		return 1
	return 0
