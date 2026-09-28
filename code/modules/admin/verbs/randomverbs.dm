GLOBAL_VAR_INIT(global_vantag_hud, 0)

ADMIN_VERB(drop_everything, R_ADMIN, "Drop Everything", ADMIN_VERB_NO_DESCRIPTION, ADMIN_CATEGORY_HIDDEN, mob/living/dropee in REGISTRY_MEMBERS(REGISTRY_MOBS))
	om_prompt(src, user, list("message" = "Make [dropee] drop everything?", "title" = "Message", "choices" = list("Yes", "No"), "confirm" = "Yes", "requires" = PROMPT_ADMIN(permissions), "data" = list("dropee" = dropee)), PROC_REF(confirmed))

/datum/admin_verb/drop_everything/proc/confirmed(mob/admin, confirm, datum/om/prompt/ask)
	var/client/user = admin.client
	var/mob/living/dropee = ask.get("dropee")
	if(confirm != "Yes")
		return

	for(var/obj/item/W in dropee)
		if(istype(W, /obj/item/implant/backup) || istype(W, /obj/item/nif))	//There's basically no reason to remove either of these
			continue
		dropee.drop_from_inventory(W)

	dropee.regenerate_icons()

	log_admin("[key_name(user)] made [key_name(dropee)] drop everything!")
	var/msg = "[key_name_admin(user)] made [ADMIN_LOOKUPFLW(dropee)] drop everything!"
	message_admins(msg)
	feedback_add_details("admin_verb","DEVR") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(cmd_admin_prison, R_ADMIN|R_MOD, "Prison", "Send target to prison.", ADMIN_CATEGORY_GAME, mob/target_mob in REGISTRY_MEMBERS(REGISTRY_MOBS))
	if(!length(GLOB.prisonwarp))
		return
	if(ismob(target_mob))
		if(isAI(target_mob))
			tgui_alert_async(user, "The AI can't be sent to prison you jerk!")
			return
		//strip their stuff before they teleport into a cell :downs:
		for(var/obj/item/content_item in target_mob)
			target_mob.drop_from_inventory(content_item)
		//teleport person to cell
		target_mob.status_at_least(EFFECT_PARALYZED, 5)
		target_mob.status_at_least(EFFECT_SLEEPING, 5)
		target_mob.forceMove(pick(GLOB.prisonwarp))
		if(ishuman(target_mob))
			var/mob/living/carbon/human/prisoner = target_mob
			prisoner.equip_to_slot_or_del(new /obj/item/clothing/under/color/prison(prisoner), slot_w_uniform)
			prisoner.equip_to_slot_or_del(new /obj/item/clothing/shoes/orange(prisoner), slot_shoes)
		om_after(target_mob, 5 SECONDS, GLOBAL_PROC_REF(to_chat), target_mob, span_bolddanger("You have been sent to the prison station!"))
		log_admin("[key_name(user)] sent [key_name(target_mob)] to the prison station.")
		message_admins(span_blue("[key_name_admin(user)] sent [key_name_admin(target_mob)] to the prison station."), 1)
		feedback_add_details("admin_verb","PRISON") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

//Allows staff to determine who the newer players are.
ADMIN_VERB(cmd_check_new_players, R_HOLDER, "Check new Players", "Check the account age.", ADMIN_CATEGORY_INVESTIGATE)
	om_prompt(src, user, list("message" = "Age check", "title" = "Show accounts yonger then _____ days", "choices" = list("7","30","All"), "requires" = PROMPT_ADMIN(permissions)), PROC_REF(age_chosen))

/datum/admin_verb/cmd_check_new_players/proc/age_chosen(mob/admin, age, datum/om/prompt/ask)
	var/client/user = admin.client
	if(age == "All")
		age = 9999999
	else
		age = text2num(age)

	var/missing_ages = 0
	var/msg = ""

	var/highlight_special_characters = 1

	for(var/client/current_client in GLOB.clients)
		if(current_client.player_age == "Requires database")
			missing_ages = 1
			continue
		if(current_client.player_age < age)
			msg += "[key_name(current_client, 1, 1, highlight_special_characters)]: account is [current_client.player_age] days old<br>"

	if(missing_ages)
		to_chat(user, "Some accounts did not have proper ages set in their clients. This function requires database to be present.")

	if(msg != "")
		// structured TGUI AdminReport.
		dq_admin_report_html(user, "Player Age Check", msg)
		return
	to_chat(user, "No matches for that age range found.")

ADMIN_VERB_ONLY_CONTEXT_MENU(cmd_admin_subtle_message, R_HOLDER, "Subtle Message", mob/targat_mob in get_mob_with_client_list())
	om_prompt(src, user, list("kind" = "text", "message" = "Message:", "title" = "Subtle PM to [targat_mob.key]", "encode" = FALSE, "requires" = PROMPT_ADMIN(permissions), "data" = list("target" = targat_mob)), PROC_REF(message_entered))

/datum/admin_verb/cmd_admin_subtle_message/proc/message_entered(mob/admin, msg, datum/om/prompt/ask)
	var/client/user = admin.client
	var/mob/targat_mob = ask.get("target")
	if(!(msg[1] == "<" && msg[length(msg)] == ">")) //You can use HTML but only if the whole thing is HTML. Tries to prevent admin 'accidents'.
		msg = sanitize(msg)

	to_chat(targat_mob, span_bold("You hear a voice in your head...") + " " + span_italics("[msg]"))

	log_admin("SubtlePM: [key_name(user)] -> [key_name(targat_mob)] : [msg]")
	msg = span_admin_pm_notice(span_bold(" SubtleMessage: [key_name_admin(user)] -> [key_name_admin(targat_mob)] :") + " [msg]")
	message_admins(msg)
	admin_ticket_log(targat_mob, msg)
	feedback_add_details("admin_verb","SMS") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(cmd_admin_world_narrate, R_FUN|R_EVENT, "Global Narrate", "Globally narrate.", ADMIN_CATEGORY_FUN_NARRATE) // Allows administrators to fluff events a little easier -- TLE
	om_prompt(src, user, list("kind" = "text", "message" = "Message:", "title" = "Enter the text you wish to appear to everyone:", "encode" = FALSE, "requires" = PROMPT_ADMIN(permissions)), PROC_REF(message_entered))

/datum/admin_verb/cmd_admin_world_narrate/proc/message_entered(mob/admin, msg, datum/om/prompt/ask)
	var/client/user = admin.client
	if(!(msg[1] == "<" && msg[length(msg)] == ">")) //You can use HTML but only if the whole thing is HTML. Tries to prevent admin 'accidents'.
		msg = sanitize(msg)
	if (!msg)		// We check both before and after, just in case sanitization ended us up with empty message.
		return

	to_chat(world, "[msg]")
	log_admin("GlobalNarrate: [key_name(user)] : [msg]")
	message_admins(span_blue(span_bold("GlobalNarrate: [key_name_admin(user)] : [msg]<BR>")))
	feedback_add_details("admin_verb","GLN") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(cmd_admin_local_narrate, R_FUN|R_EVENT, "Local Narrate", "Locally narrate.", ADMIN_CATEGORY_FUN_NARRATE)
	om_prompt(src, user, list("kind" = "text", "message" = "Message:", "title" = "Enter the text you wish to appear to everyone within view range:", "encode" = FALSE, "requires" = PROMPT_ADMIN(permissions)), PROC_REF(message_entered))

/datum/admin_verb/cmd_admin_local_narrate/proc/message_entered(mob/admin, msg, datum/om/prompt/ask)
	var/client/user = admin.client
	if(!(msg[1] == "<" && msg[length(msg)] == ">")) //You can use HTML but only if the whole thing is HTML. Tries to prevent admin 'accidents'.
		msg = sanitize(msg)
	if (!msg)		// We check both before and after, just in case sanitization ended us up with empty message.
		return

	for(var/mob/mobs in range(user.eye, user.view))
		to_chat(mobs, span_bold("[msg]"))
	log_admin("LocalNarrate: [key_name(user)] : [msg]")
	message_admins(span_blue(span_bold("LocalNarrate: [key_name_admin(user)] : [msg]<BR>")))
	feedback_add_details("admin_verb","LNR") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!


ADMIN_VERB_AND_CONTEXT_MENU(cmd_admin_direct_narrate, R_FUN|R_EVENT, "Direct Narrate", "Directly narrate the target.", ADMIN_CATEGORY_FUN_NARRATE, mob/target_mob in REGISTRY_MEMBERS(REGISTRY_MOBS))
	om_prompt_sequence(src, user, list(
		target_mob ? null : list("key" = "target", "kind" = "list", "message" = "Direct narrate to who?", "title" = "Active Players", "choices" = get_mob_with_client_list()),
		list("key" = "msg", "kind" = "text", "message" = "Message:", "title" = "Enter the text you wish to appear to your target:", "encode" = FALSE),
	), PROC_REF(narrate_answered), list("requires" = PROMPT_ADMIN(permissions), "data" = list("preset" = target_mob)))

/datum/admin_verb/cmd_admin_direct_narrate/proc/narrate_answered(mob/admin, datum/om/prompt/ask)
	var/client/user = admin.client
	var/mob/target_mob = ask.get("preset") || ask.get("target")
	var/msg = ask.get("msg")
	if(!target_mob)
		return
	if(msg && !(msg[1] == "<" && msg[length(msg)] == ">")) //You can use HTML but only if the whole thing is HTML. Tries to prevent admin 'accidents'.
		msg = sanitize(msg)

	if(!msg)
		return

	to_chat(target_mob, msg)
	log_admin("DirectNarrate: [key_name(user)] to ([target_mob.name]/[target_mob.key]): [msg]")
	msg = span_admin_pm_notice(span_bold(" DirectNarrate: [key_name(user)] to ([target_mob.name]/[target_mob.key]):") + " [msg]<BR>")
	message_admins(msg)
	admin_ticket_log(target_mob, msg)
	feedback_add_details("admin_verb","DIRN") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB_AND_CONTEXT_MENU(cmd_admin_godmode, R_HOLDER, "Toggle Godmode", "Toggle godmode on the target.", ADMIN_CATEGORY_GAME, mob/target_mob in REGISTRY_MEMBERS(REGISTRY_MOBS))
	if(om_has(target_mob, EFFECT_GODMODE))
		target_mob.disable_godmode()

	else if(!om_has(target_mob, EFFECT_GODMODE))
		target_mob.enable_godmode()

	to_chat(user, span_notice("Toggled [om_has(target_mob, EFFECT_GODMODE) ? "ON" : "OFF"]"))

	log_admin("[key_name(user)] has toggled [key_name(target_mob)]'s godmode to [om_has(target_mob, EFFECT_GODMODE) ? "On" : "Off"]")
	var/msg = "[key_name_admin(user)] has toggled [ADMIN_LOOKUPFLW(target_mob)]'s godmode to [om_has(target_mob, EFFECT_GODMODE) ? "On" : "Off"]"
	message_admins(msg)
	admin_ticket_log(target_mob, msg)
	feedback_add_details("admin_verb","GOD_ENABLE") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/proc/cmd_admin_mute(mob/target, mute_type, automute = FALSE, mob/user)
	if(automute)
		if(!CONFIG_GET(flag/automute_on))
			return
	else
		if(!user || !user.client)
			return
		if(!check_rights_for(user.client, R_HOLDER))
			to_chat(user, span_red("Error: cmd_admin_mute: You don't have permission to do this."))
			return
		if(!target.client)
			to_chat(user, span_red("Error: cmd_admin_mute: This mob doesn't have a client tied to it."))
		if(check_rights_for(target.client, R_HOLDER))
			to_chat(user, span_red("Error: cmd_admin_mute: You cannot mute an admin/mod."))
	if(!target.client)
		return
	if(check_rights_for(target.client, R_HOLDER))
		return

	var/muteunmute
	var/mute_string

	switch(mute_type)
		if(MUTE_IC)			mute_string = "IC (say and emote)"
		if(MUTE_OOC)		mute_string = "OOC"
		if(MUTE_LOOC)		mute_string = "LOOC"
		if(MUTE_PRAY)		mute_string = "pray"
		if(MUTE_ADMINHELP)	mute_string = "adminhelp, admin PM and ASAY"
		if(MUTE_DEADCHAT)	mute_string = "deadchat and DSAY"
		if(MUTE_ALL)		mute_string = "everything"
		else				return

	if(automute)
		muteunmute = "auto-muted"
		target.client.prefs.muted |= mute_type
		log_admin("SPAM AUTOMUTE: [muteunmute] [key_name(target)] from [mute_string]")
		message_admins("SPAM AUTOMUTE: [muteunmute] [key_name_admin(target)] from [mute_string].", 1)
		to_chat(target, span_alert("You have been [muteunmute] from [mute_string] by the SPAM AUTOMUTE system. Contact an admin."))
		feedback_add_details("admin_verb","AUTOMUTE") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		return

	if(target.client.prefs.muted & mute_type)
		muteunmute = "unmuted"
		target.client.prefs.muted &= ~mute_type
	else
		muteunmute = "muted"
		target.client.prefs.muted |= mute_type

	log_admin("[key_name(user)] has [muteunmute] [key_name(target)] from [mute_string]")
	message_admins("[key_name_admin(user)] has [muteunmute] [key_name_admin(target)] from [mute_string].", 1)
	to_chat(target, span_alert("You have been [muteunmute] from [mute_string]."))
	feedback_add_details("admin_verb","MUTE") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(cmd_admin_add_random_ai_law, R_ADMIN|R_FUN, "Add Random AI Law", "Adds a random law to the station ai.", ADMIN_CATEGORY_FUN_SILICON)
	om_prompt_sequence(src, user, list(
		list("key" = "sure", "message" = "You sure?", "title" = "Confirm", "choices" = list("Yes", "No"), "confirm" = "Yes"),
		list("key" = "show", "message" = "Show ion message?", "title" = "Message", "choices" = list("Yes", "No")),
	), PROC_REF(law_answered), list("requires" = PROMPT_ADMIN(permissions)))

/datum/admin_verb/cmd_admin_add_random_ai_law/proc/law_answered(mob/admin, datum/om/prompt/ask)
	var/client/user = admin.client
	log_admin("[key_name(user)] has added a random AI law.")
	message_admins("[key_name_admin(user)] has added a random AI law.")

	if(ask.get("show") == "Yes")
		GLOB.command_announcement.Announce("Ion storm detected near \the [station_name()]. Please check all AI-controlled equipment for errors.", "Anomaly Alert", new_sound = ANNOUNCER_MSG_IONSTORM)

	IonStorm(0)
	feedback_add_details("admin_verb","ION") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/*
Allow admins to set players to be able to respawn/bypass 30 min wait, without the admin having to edit variables directly
Ccomp's first proc.
*/

/client/proc/get_ghosts(notify = 0,what = 2)
	// what = 1, return ghosts ass list.
	// what = 2, return mob list

	var/list/mobs = list()
	var/list/ghosts = list()
	if(!REGISTRY_COUNT(REGISTRY_OBSERVERS))
		if(notify)
			to_chat(src, "There doesn't appear to be any ghosts for you to select.")
		return
	var/list/sortmob = sort_names(REGISTRY_MEMBERS(REGISTRY_OBSERVERS))                           // get the mob list.

	for(var/mob/M in sortmob)
		var/name = M.name
		ghosts[name] = M                                        //get the name of the mob for the popup list
	if(what==1)
		return ghosts
	return mobs

ADMIN_VERB(allow_character_respawn, R_ADMIN|R_MOD|R_FUN, "Allow player to respawn", "Let a player bypass the wait to respawn or allow them to re-enter their corpse.", ADMIN_CATEGORY_GAME)
	om_prompt_sequence(src, user, list(
		list("key" = "target", "kind" = "list", "message" = "Select a ckey to allow to rejoin", "title" = "Allow Respawn Selector", "choices" = GLOB.respawn_timers),
		PROC_REF(ask_impossible),
	), PROC_REF(respawn_allowed), list("requires" = PROMPT_ADMIN(permissions)))

/datum/admin_verb/allow_character_respawn/proc/ask_impossible(mob/admin, datum/om/prompt/ask)
	if(GLOB.respawn_timers[ask.get("target")] == -1) // Their respawn timer is set to -1, which is 'not allowed to respawn'
		return list("key" = "sure", "message" = "Are you sure you wish to allow this individual to respawn? They would normally not be able to.", "title" = "Allow impossible respawn?", "choices" = list("No","Yes"), "confirm" = "Yes")

/datum/admin_verb/allow_character_respawn/proc/respawn_allowed(mob/admin, datum/om/prompt/ask)
	var/client/user = admin.client
	var/target = ask.get("target")
	GLOB.respawn_timers -= target

	var/found_client = FALSE
	for(var/client/current_client as anything in GLOB.clients)
		if(current_client.ckey == target)
			found_client = current_client
			to_chat(current_client, span_boldnotice("You may now respawn. You should roleplay as if you learned nothing about the round during your time with the dead."))
			if(isobserver(current_client.mob))
				var/mob/observer/dead/dead_mob = current_client.mob
				dead_mob.can_reenter_corpse = 1
				to_chat(current_client, span_boldnotice("You can also re-enter your corpse, if you still have one!"))
			break

	if(!found_client)
		to_chat(user, span_notice("The associated client didn't appear to be connected, so they couldn't be notified, but they can now respawn if they reconnect."))

	log_admin("[key_name(user)] allowed [found_client ? key_name(found_client) : target] to bypass the respawn time limit")
	message_admins("Admin [key_name_admin(user)] allowed [found_client ? key_name_admin(found_client) : target] to bypass the respawn time limit")

ADMIN_VERB(toggle_antagHUD_use, R_ADMIN, "Toggle antagHUD usage", "Toggles antagHUD usage for observers.", ADMIN_CATEGORY_SERVER_GAME)
	var/action=""
	if(CONFIG_GET(flag/antag_hud_allowed))
		for(var/mob/observer/dead/dead_mob in user.get_ghosts())
			if(!check_rights_for(dead_mob.client, R_HOLDER))						//Remove the verb from non-admin ghosts
				remove_verb(dead_mob, /mob/observer/dead/verb/toggle_antagHUD)
			if(dead_mob.antagHUD)
				dead_mob.antagHUD = 0						// Disable it on those that have it enabled
				dead_mob.has_enabled_antagHUD = 2				// We'll allow them to respawn
				to_chat(dead_mob, span_boldwarning("The Administrator has disabled AntagHUD "))
		CONFIG_SET(flag/antag_hud_allowed, FALSE)
		to_chat(user, span_boldwarning("AntagHUD usage has been disabled"))
		action = "disabled"
	else
		for(var/mob/observer/dead/dead_mob in user.get_ghosts())
			if(!check_rights_for(dead_mob.client, R_HOLDER))						// Add the verb back for all non-admin ghosts
				add_verb(dead_mob, /mob/observer/dead/verb/toggle_antagHUD)
			to_chat(dead_mob, span_boldnotice("The Administrator has enabled AntagHUD"))	// Notify all observers they can now use AntagHUD
		CONFIG_SET(flag/antag_hud_allowed, TRUE)
		action = "enabled"
		to_chat(user, span_boldnotice("AntagHUD usage has been enabled"))

	log_admin("[key_name(user)] has [action] antagHUD usage for observers")
	message_admins("Admin [key_name_admin(user)] has [action] antagHUD usage for observers")

ADMIN_VERB(toggle_antagHUD_restrictions, R_ADMIN, "Toggle antagHUD Restrictions", "Restricts players that have used antagHUD from being able to join this round.", ADMIN_CATEGORY_SERVER_GAME)
	var/action=""
	if(CONFIG_GET(flag/antag_hud_restricted))
		for(var/mob/observer/dead/dead_mob in user.get_ghosts())
			to_chat(dead_mob, span_boldnotice("The administrator has lifted restrictions on joining the round if you use AntagHUD"))
		action = "lifted restrictions"
		CONFIG_SET(flag/antag_hud_restricted, FALSE)
		to_chat(user, span_boldnotice("AntagHUD restrictions have been lifted"))
	else
		for(var/mob/observer/dead/dead_mob in user.get_ghosts())
			to_chat(dead_mob, span_boldwarning("The administrator has placed restrictions on joining the round if you use AntagHUD"))
			to_chat(dead_mob, span_boldwarning("Your AntagHUD has been disabled, you may choose to re-enabled it but will be under restrictions "))
			dead_mob.antagHUD = 0
			dead_mob.has_enabled_antagHUD = 0
		action = "placed restrictions"
		CONFIG_SET(flag/antag_hud_restricted, TRUE)
		to_chat(user, span_boldwarning("AntagHUD restrictions have been enabled"))

	log_admin("[key_name(user)] has [action] on joining the round if they use AntagHUD")
	message_admins("Admin [key_name_admin(user)] has [action] on joining the round if they use AntagHUD")

/*
If a guy was gibbed and you want to revive him, this is a good way to do so.
Works kind of like entering the game with a new character. Character receives a new mind if they didn't have one.
Traitors and the like can also be revived with the previous role mostly intact.
/N */
ADMIN_VERB(respawn_character, (R_ADMIN|R_REJUVINATE), "Spawn Character", "(Re)Spawn a client's loaded character.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	om_prompt(user, user, list("kind" = "list", "message" = "Please specify which client's character to spawn.", "title" = "Client", "choices" = GLOB.clients, "requires" = PROMPT_ADMIN(R_ADMIN|R_REJUVINATE)), TYPE_PROC_REF(/client, respawn_client_picked))

/client/proc/respawn_client_picked(mob/admin, client/picked_client, datum/om/prompt/ask)
	respawn_character_proper(picked_client)

/client/proc/respawn_character_proper(client/picked_client)
	if(!istype(picked_client))
		return

	//I frontload all the questions so we don't have a half-done process while you're reading.
	om_prompt_sequence(src, src, list(
		list("key" = "location", "message" = "Please specify where to spawn them.", "title" = "Location", "choices" = list("Right Here", "Arrivals", "Cancel"), "abort" = "Cancel"),
		list("key" = "announce", "message" = "Announce as if they had just arrived?", "title" = "Announce", "choices" = list("No", "Yes", "Cancel"), "abort" = "Cancel"),
		list("key" = "inhabit", "message" = "Put the person into the spawned mob?", "title" = "Inhabit", "choices" = list("Yes", "No", "Cancel"), "abort" = "Cancel"),
		PROC_REF(respawn_ask_record),
		PROC_REF(respawn_ask_job),
		PROC_REF(respawn_ask_equipment),
		PROC_REF(respawn_ask_custom_job),
		PROC_REF(respawn_ask_custom_title),
		PROC_REF(respawn_ask_showy),
		PROC_REF(respawn_ask_pod),
	), PROC_REF(respawn_character_answered), list("requires" = PROMPT_ADMIN(R_ADMIN|R_REJUVINATE), "data" = list("picked" = picked_client)))

/// Their data core record, when they were spawned before (name matching is ugly but mind doesn't persist to look at).
/client/proc/respawn_record(client/picked_client)
	return find_general_record("name", picked_client.prefs.read_preference(/datum/preference/name/real_name))

/// The job the answers so far give them, or null.
/client/proc/respawn_charjob(datum/om/prompt/ask)
	var/datum/data/record/record_found = respawn_record(ask.get("picked"))
	if(record_found)
		if(ask.get("samejob") == "Yes")
			return record_found.fields["real_rank"]
		if(ask.get("samejob") == JOB_ALT_VISITOR)
			return JOB_ALT_VISITOR
	var/pickjob = ask.get("pickjob")
	if(pickjob && pickjob != "-No Job-")
		return pickjob

/client/proc/respawn_ask_record(mob/admin, datum/om/prompt/ask)
	var/datum/data/record/record_found = respawn_record(ask.get("picked"))
	//Found their record, they were spawned previously
	if(record_found)
		return list("key" = "samejob", "message" = "Found [record_found.fields["name"]] in data core. They were [record_found.fields["real_rank"]] this round. Assign same job? They will not be re-added to the manifest/records, either way.", "title" = "Previously spawned", "choices" = list("Yes","Assistant","No"))
	return list("key" = "records", "message" = "No data core entry detected. Would you like add them to the manifest, and sec/med/HR records?", "title" = "Records", "choices" = list("No", "Yes", "Cancel"), "abort" = "Cancel")

//Well you're not reloading their job or they never had one.
/client/proc/respawn_ask_job(mob/admin, datum/om/prompt/ask)
	if(respawn_charjob(ask))
		return null
	return list("key" = "pickjob", "kind" = "list", "message" = "Pick a job to assign them (or none).", "title" = "Job Select", "choices" = SSjob.occupations_by_name.Copy() + "-No Job-", "default" = "-No Job-")

//If you've picked a job by now, you can equip them.
/client/proc/respawn_ask_equipment(mob/admin, datum/om/prompt/ask)
	if(respawn_charjob(ask))
		return list("key" = "equipment", "message" = "Spawn them with equipment?", "title" = "Equipment", "choices" = list("Yes", "No", "Cancel"), "abort" = "Cancel")

/client/proc/respawn_ask_custom_job(mob/admin, datum/om/prompt/ask)
	if(respawn_charjob(ask))
		return list("key" = "custom_job", "message" = "Customise Job Title?", "title" = "Custom Job", "choices" = list("No", "Yes", "Cancel"), "abort" = "Cancel")

/client/proc/respawn_ask_custom_title(mob/admin, datum/om/prompt/ask)
	if(ask.get("custom_job") == "Yes")
		return list("key" = "custom_title", "kind" = "text", "message" = "Choose a Job Title for the character.", "title" = "Job Title", "optional" = TRUE)

/client/proc/respawn_ask_showy(mob/admin, datum/om/prompt/ask)
	if(ask.get("location") == "Right Here")
		return list("key" = "showy", "kind" = "list", "message" = "Showy entrance?", "title" = "Showy", "choices" = list("No", "Telesparks", "Drop Pod", "Fall", "Cancel"), "abort" = "Cancel", "optional" = TRUE)

/client/proc/respawn_ask_pod(mob/admin, datum/om/prompt/ask)
	if(ask.get("showy") == "Drop Pod")
		return list("key" = "pod", "message" = "Destructive drop pods cause damage in a 3x3 and may break turfs. Polite drop pods lightly damage the turfs but won't break through.", "title" = "Drop Pod", "choices" = list("Polite", "Destructive", "Cancel"), "abort" = "Cancel")

/client/proc/respawn_character_answered(mob/admin_mob, datum/om/prompt/ask)
	var/client/picked_client = ask.get("picked")
	var/location = ask.get("location")
	var/announce = ask.get("announce") == "Yes"
	var/inhabit = ask.get("inhabit") == "Yes"
	var/charjob = respawn_charjob(ask)
	var/records = ask.get("records") == "Yes"
	var/equipment = ask.get("equipment") == "Yes"
	var/custom_job = ask.get("custom_job") == "Yes"
	var/custom_job_title = ask.get("custom_title")

	//For logging later
	var/admin = key_name_admin(src)
	var/player_key = picked_client.key
	var/picked_ckey = picked_client.ckey
	var/picked_slot = picked_client.prefs.default_slot

	var/mob/living/carbon/human/new_character
	var/spawnloc
	var/showy

	//Where did you want to spawn them?
	switch(location)
		if("Right Here") //Spawn them on your turf
			spawnloc = get_turf(src.mob)
			showy = ask.get("showy")
			if(showy == "Drop Pod")
				showy = ask.get("pod")

		if("Arrivals") //Spawn them at a latejoin spawnpoint
			if(REGISTRY_COUNT(REGISTRY_LATEJOIN))
				spawnloc = get_turf(pick(REGISTRY_MEMBERS(REGISTRY_LATEJOIN)))
			else if(LAZYLEN(GLOB.latejoin_tram))
				spawnloc = pick(GLOB.latejoin_tram)
			else
				to_chat(src, "This map has no latejoin spawnpoint.")
				return

		else //I have no idea how you're here
			to_chat(src, "Invalid spawn location choice.")
			return

	//Did we actually get a loc to spawn them?
	if(!spawnloc)
		to_chat(src, "Couldn't get valid spawn location.")
		return

	new_character = new(spawnloc)

	if(showy == "Telesparks")
		anim(spawnloc,new_character,'icons/mob/mob.dmi',,"phasein",,new_character.dir)
		playsound(spawnloc, "sparks", 50, 1)
		var/datum/effect/effect/system/spark_spread/spk = new(new_character)
		spk.set_up(5, 0, new_character)
		spk.attach(new_character)
		spk.start()

	//We were able to spawn them, right?
	if(!new_character)
		to_chat(src, "Something went wrong and spawning failed.")
		return

	// mind_scan / resleeve_scan migrated to /datum/preference.
	// Respect admin spawn record choice. There's really not a nice way to do this without butchering copy_to() code for an admin proc
	var/old_mind_scan = picked_client.prefs.read_preference(/datum/preference/toggle/human/mind_scan)
	var/old_body_scan = picked_client.prefs.read_preference(/datum/preference/toggle/human/resleeve_scan)
	if(!records) // Make em false for the copy_to()
		picked_client.prefs.update_preference_by_type(/datum/preference/toggle/human/mind_scan, FALSE)
		picked_client.prefs.update_preference_by_type(/datum/preference/toggle/human/resleeve_scan, FALSE)

	//Write the appearance and whatnot out to the character
	picked_client.prefs.copy_to(new_character)

	// Restore pref state
	picked_client.prefs.update_preference_by_type(/datum/preference/toggle/human/mind_scan, old_mind_scan)
	picked_client.prefs.update_preference_by_type(/datum/preference/toggle/human/resleeve_scan, old_body_scan)

	//Write the appearance and whatnot out to the character
	if(new_character.dna)
		new_character.dna.ResetUIFrom(new_character)
		new_character.sync_dna_traits(TRUE) // Traitgenes Sync traits to genetics if needed
		new_character.sync_organ_dna()
	new_character.sync_addictions() // These are addicitions our profile wants... May as well give them!
	new_character.initialize_vessel()
	if(inhabit)
		new_character.key = player_key
		//Were they any particular special role? If so, copy.
		if(new_character.mind)
			var/datum/antagonist/antag_data = SSantag_job.get_antag_data(new_character.mind.special_role)
			if(antag_data)
				antag_data.add_antagonist(new_character.mind)
				antag_data.place_mob(new_character)
			if(new_character.mind.antag_holder)
				new_character.mind.antag_holder.apply_antags(new_character)

	if(new_character.mind)
		new_character.mind.loaded_from_ckey = picked_ckey
		new_character.mind.loaded_from_slot = picked_slot

	for(var/lang in picked_client.prefs.read_preference(/datum/preference/alternate_languages)) // migrated language pref
		var/datum/language/chosen_language = GLOB.all_languages[lang]
		if(chosen_language)
			if(is_lang_whitelisted(src,chosen_language) || (new_character.species && (chosen_language.name in new_character.species.secondary_langs)))
				new_character.add_language(lang)

	SEND_SIGNAL(new_character, COMSIG_HUMAN_DNA_FINALIZED)

	//If desired, apply equipment.
	if(equipment)
		if(charjob)
			SSjob.equip_rank(new_character, charjob, 1)
			if(new_character.mind)
				new_character.mind.assigned_role = charjob
				new_character.mind.role_alt_title = SSjob.get_player_alt_title(new_character, charjob)
			equip_custom_items(new_character) // readded to enable custom_item.txt

	//If customised job title, modify here.
	if(custom_job && custom_job_title)
		var/character_name = new_character.name
		for(var/obj/item/card/id/player_id in new_character.contents)
			player_id.name = "[character_name]'s ID Card ([custom_job_title])"
			player_id.assignment = custom_job_title
		for(var/obj/item/pda/player_pda in new_character.contents)
			player_pda.name = "PDA-[character_name] ([custom_job_title])"
			player_pda.ownjob = custom_job_title
		new_character.mind.assigned_role = custom_job_title
		new_character.mind.role_alt_title = custom_job_title
		to_chat(new_character, "Your job title has been changed to [custom_job_title].")

	//If desired, add records.
	if(records)
		GLOB.data_core.manifest_inject(new_character)

	//A redraw for good measure
	new_character.regenerate_icons()

	new_character.update_transform()

	//If we're announcing their arrival
	if(announce)
		AnnounceArrival(new_character, new_character.mind.assigned_role, "Common", new_character.z)

	log_admin("[admin] has spawned [player_key]'s character [new_character.real_name].")
	message_admins("[admin] has spawned [player_key]'s character [new_character.real_name].")



	feedback_add_details("admin_verb","RSPCH") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

	// Drop pods and fall
	if(showy == "Polite")
		var/turf/target_turf = get_turf(new_character)
		new /obj/structure/drop_pod/polite(target_turf, new_character)
		to_chat(new_character, span_boldnotice("Please wait for your arrival."))
	else if(showy == "Destructive")
		var/turf/target_turf = get_turf(new_character)
		new /obj/structure/drop_pod(target_turf, new_character)
		to_chat(new_character, span_boldnotice("Please wait for your arrival."))
	else if(showy == "Fall")
		spawn(1) // ALLOW(scheduler): admin verb (allowlist)
			var/initial_x = new_character.pixel_x
			var/initial_y = new_character.pixel_y
			new_character.plane = 1
			new_character.pixel_x = rand(-150, 150)
			new_character.pixel_y = 500 // When you think that pixel_z is height but you are wrong
			new_character.density = FALSE
			new_character.opacity = FALSE
			animate(new_character, pixel_y = initial_y, pixel_x = initial_x , time = 7)
			spawn(7) // ALLOW(scheduler): admin verb (allowlist)
				new_character.end_fall()
		to_chat(new_character, span_boldnotice("You have been fully spawned. Enjoy the game."))

	return new_character

ADMIN_VERB(cmd_admin_add_freeform_ai_law, R_FUN, "Add Custom AI law", "Adds a custom law to a silicon.", ADMIN_CATEGORY_FUN_SILICON)
	om_prompt_sequence(src, user, list(
		list("key" = "law", "kind" = "text", "message" = "Please enter anything you want the AI to do. Anything. Serious.", "title" = "What?", "max_length" = MAX_MESSAGE_LEN),
		list("key" = "show", "message" = "Show ion message?", "title" = "Message", "choices" = list("Yes", "No"), "optional" = TRUE),
	), PROC_REF(law_answered), list("requires" = PROMPT_ADMIN(permissions)))

/datum/admin_verb/cmd_admin_add_freeform_ai_law/proc/law_answered(mob/admin, datum/om/prompt/ask)
	var/client/user = admin.client
	var/input = ask.get("law")
	for(var/mob/living/silicon/ai/target_ai in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if (target_ai.stat == 2)
			to_chat(user, "Upload failed. No signal is being detected from the AI.")
		else if (target_ai.see_in_dark == 0)
			to_chat(user, "Upload failed. Only a faint signal is being detected from the AI, and it is not responding to our requests. It may be low on power.")
		else
			target_ai.add_ion_law(input)
			for(var/mob/living/silicon/ai/found_ai in REGISTRY_MEMBERS(REGISTRY_MOBS))
				to_chat(found_ai, span_warning("... LAWS UPDATED!") + "\n" + input)
				found_ai.show_laws()

	log_admin("Admin [key_name(user)] has added a new AI law - [input]")
	message_admins("Admin [key_name_admin(user)] has added a new AI law - [input]", 1)

	if(ask.get("show") == "Yes")
		GLOB.command_announcement.Announce("Ion storm detected near the [station_name()]. Please check all AI-controlled equipment for errors.", "Anomaly Alert", new_sound = ANNOUNCER_MSG_IONSTORM)
	feedback_add_details("admin_verb","IONC") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB_AND_CONTEXT_MENU(cmd_admin_rejuvenate, R_ADMIN|R_FUN|R_MOD, "Rejuvenate", "Fully restores the target mob.", ADMIN_CATEGORY_GAME, mob/living/target_mob in REGISTRY_MEMBERS(REGISTRY_MOBS))
	if(!target_mob)
		return
	if(!istype(target_mob))
		tgui_alert_async(user, "Cannot revive a ghost")
		return
	if(CONFIG_GET(flag/allow_admin_rev))
		target_mob.revive()

		log_admin("[key_name(user)] healed / revived [key_name(target_mob)]")
		var/msg = span_danger("Admin [key_name_admin(user)] healed / revived [ADMIN_LOOKUPFLW(target_mob)]!")
		message_admins(msg)
		admin_ticket_log(target_mob, msg)
	else
		tgui_alert_async(user, "Admin revive disabled")
	feedback_add_details("admin_verb","REJU") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(cmd_admin_create_centcom_report, R_ADMIN|R_SERVER|R_FUN, "Create Command Report", "Creates a centcom report and sends it globally.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	om_prompt_sequence(src, user, list(
		list("key" = "report", "kind" = "text", "message" = "Please enter anything you want. Anything. Serious.", "title" = "What?", "max_length" = MAX_MESSAGE_LEN, "multiline" = TRUE),
		list("key" = "title", "kind" = "text", "message" = "Pick a title for the report.", "title" = "Title", "encode" = FALSE, "optional" = TRUE),
		list("key" = "announce", "message" = "Should this be announced to the general population?", "title" = "Show world?", "choices" = list("Yes","No")),
	), PROC_REF(report_answered), list("requires" = PROMPT_ADMIN(permissions)))

/datum/admin_verb/cmd_admin_create_centcom_report/proc/report_answered(mob/admin, datum/om/prompt/ask)
	var/client/user = admin.client
	var/input = ask.get("report")
	var/customname = sanitizeSafe(ask.get("title"))
	if(!customname)
		customname = "[using_map.company_name] Update"

	//New message handling
	post_comm_message(customname, replacetext(input, "\n", "<br/>"))

	if(ask.get("announce") == "Yes")
		GLOB.command_announcement.Announce(input, customname, new_sound = ANNOUNCER_MSG_NEW_COMMAND_REPORT, msg_sanitized = 1);
	else
		to_chat(world, span_boldannounce("New [using_map.company_name] Update available at all communication consoles."))
		play_simple_announcement(world, ANNOUNCER_MSG_NEW_COMMAND_REPORT)

	log_admin("[key_name(user)] has created a command report: [input]")
	message_admins("[key_name_admin(user)] has created a command report")
	feedback_add_details("admin_verb","CCR") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB_AND_CONTEXT_MENU(cmd_admin_delete, R_FUN|R_ADMIN, "Delete", "Delete the selected atom.", ADMIN_CATEGORY_GAME, atom/atom_target as obj|mob|turf in _validate_atom(atom_target)) // I don't understand precisely how this fixes the string matching against a substring, but it does - Ater
	user.admin_delete(atom_target)

ADMIN_VERB(cmd_admin_list_open_jobs, R_HOLDER, "List free slots", "Show available job slots.", ADMIN_CATEGORY_INVESTIGATE)
	if(SSjob)
		for(var/datum/job/job in SSjob.occupations)
			to_chat(user, "[job.title]: [job.total_positions]")
	feedback_add_details("admin_verb","LFS") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(cmd_admin_check_contents, R_HOLDER, "Check Contents", "Check the contents of the mob.", ADMIN_CATEGORY_INVESTIGATE, mob/living/living_target in REGISTRY_MEMBERS(REGISTRY_MOBS))
	var/list/content_list = living_target.get_contents()
	for(var/target in content_list)
		to_chat(user, "[target]")
	feedback_add_details("admin_verb","CC") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(toggle_view_range, R_HOLDER, "Change View Range", "Switches between 1x and custom views.", ADMIN_CATEGORY_GAME)
	if(user.view == world.view)
		om_prompt(src, user, list("kind" = "list", "message" = "Select view range:", "title" = "FUCK YE", "choices" = list(1,2,3,4,5,6,7,8,9,10,11,12,13,14,128), "requires" = PROMPT_ADMIN(permissions)), PROC_REF(view_chosen))
		return
	view_chosen(user.mob, world.view)

/datum/admin_verb/toggle_view_range/proc/view_chosen(mob/admin, view, datum/om/prompt/ask)
	var/client/user = admin.client
	user.mob.set_viewsize(view)

	log_admin("[key_name(user)] changed their view range to [view].")
	message_admins(span_blue("[key_name_admin(user)] changed their view range to [view]."))

	feedback_add_details("admin_verb","CVRA") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(admin_call_shuttle, R_ADMIN|R_SERVER, "Call Shuttle", "Calls the emergency shuttel.", ADMIN_CATEGORY_EVENTS)
	if ((!( SSticker ) || !SSemergency_shuttle.location()))
		return

	om_prompt_sequence(src, user, list(
		list("key" = "sure", "message" = "You sure?", "title" = "Confirm", "choices" = list("Yes", "No"), "confirm" = "Yes"),
		SSticker.mode.auto_recall_shuttle ? list("key" = "recall", "kind" = "list", "message" = "The shuttle will just return if you call it. Call anyway?", "title" = "Shuttle Call", "choices" = list("Confirm", "Cancel"), "confirm" = "Confirm") : null,
		list("key" = "kind", "kind" = "list", "message" = "Is this an emergency evacuation or a crew transfer?", "title" = "Shuttle Call", "choices" = list("Emergency", "Crew Transfer")),
	), PROC_REF(call_answered), list("requires" = PROMPT_ADMIN(permissions)))

/datum/admin_verb/admin_call_shuttle/proc/call_answered(mob/admin, datum/om/prompt/ask)
	var/client/user = admin.client
	if(!SSticker || !SSemergency_shuttle.location())
		return
	if(ask.get("recall") == "Confirm")
		SSemergency_shuttle.auto_recall = TRUE	//enable auto-recall
	if (ask.get("kind") == "Emergency")
		SSemergency_shuttle.call_evac()
	else
		SSemergency_shuttle.call_transfer()


	feedback_add_details("admin_verb","CSHUT") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	log_admin("[key_name(user)] admin-called the emergency shuttle.")
	message_admins(span_blue("[key_name_admin(user)] admin-called the emergency shuttle."))

ADMIN_VERB(admin_cancel_shuttle, R_ADMIN|R_FUN, "Cancel Shuttle", "Cancels the emergency shuttel.", ADMIN_CATEGORY_EVENTS)
	om_prompt(src, user, list("message" = "You sure?", "title" = "Confirm", "choices" = list("Yes", "No"), "requires" = PROMPT_ADMIN(permissions)), PROC_REF(cancel_confirmed))

/datum/admin_verb/admin_cancel_shuttle/proc/cancel_confirmed(mob/admin, answer, datum/om/prompt/ask)
	var/client/user = admin.client
	if(answer != "Yes")
		return
	if(!SSticker || !SSemergency_shuttle.can_recall())
		return

	SSemergency_shuttle.recall()
	feedback_add_details("admin_verb","CCSHUT") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	log_admin("[key_name(user)] admin-recalled the emergency shuttle.")
	message_admins(span_blue("[key_name_admin(user)] admin-recalled the emergency shuttle."))

ADMIN_VERB(admin_deny_shuttle, R_ADMIN, "Toggle Deny Shuttle", "Prevents the shuttle from being called.", ADMIN_CATEGORY_EVENTS)
	if (!SSticker)
		return

	SSemergency_shuttle.deny_shuttle = !SSemergency_shuttle.deny_shuttle

	log_admin("[key_name(user)] has [SSemergency_shuttle.deny_shuttle ? "denied" : "allowed"] the shuttle to be called.")
	message_admins("[key_name_admin(user)] has [SSemergency_shuttle.deny_shuttle ? "denied" : "allowed"] the shuttle to be called.")

ADMIN_VERB(everyone_random, R_FUN, "Make Everyone Random", "Make everyone have a random appearance. You can only use this before rounds!", ADMIN_CATEGORY_FUN_DO_NOT)
	if (SSticker && SSticker.mode)
		to_chat(user, "Nope you can't do this, the game's already started. This only works before rounds!")
		return

	if(CONFIG_GET(flag/force_random_names))
		CONFIG_SET(flag/force_random_names, FALSE)
		message_admins("Admin [key_name_admin(user)] has disabled \"Everyone is Special\" mode.")
		to_chat(user, span_userdanger("Disabled."))
		return


	om_prompt(src, user, list("message" = "Do you want to notify the players?", "title" = "Options", "choices" = list("Yes", "No", "Cancel"), "requires" = PROMPT_ADMIN(permissions)), PROC_REF(notify_chosen))

/datum/admin_verb/everyone_random/proc/notify_chosen(mob/admin, notifyplayers, datum/om/prompt/ask)
	var/client/user = admin.client
	if(notifyplayers == "Cancel" || (SSticker && SSticker.mode))
		return

	log_admin("Admin [key_name(user)] has forced the players to have random appearances.")
	message_admins("Admin [key_name_admin(user)] has forced the players to have random appearances.")

	if(notifyplayers == "Yes")
		to_chat(world, span_boldannounce(span_blue("Admin [user.key] has forced the players to have completely random identities!")))

	to_chat(user, span_userdanger(span_italics("Remember: you can always disable the randomness by using the verb again, assuming the round hasn't started yet.")))

	CONFIG_SET(flag/force_random_names, TRUE)
	feedback_add_details("admin_verb","MER") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(toggle_random_events, R_SERVER, "Toggle random events on/off", "Toggles random events such as meteors, black holes, blob (but not space dust) on/off", ADMIN_CATEGORY_SERVER_GAME)
	if(!CONFIG_GET(flag/allow_random_events))
		CONFIG_SET(flag/allow_random_events, TRUE)
		to_chat(user, "Random events enabled")
		message_admins("Admin [key_name_admin(user)] has enabled random events.")
	else
		CONFIG_SET(flag/allow_random_events, FALSE)
		to_chat(user, "Random events disabled")
		message_admins("Admin [key_name_admin(user)] has disabled random events.")
	feedback_add_details("admin_verb","TRE") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(despawn_player, R_ADMIN|R_EVENT, "Cryo Player", "Removes a player from the round as if they'd cryo'd.", ADMIN_CATEGORY_GAME, mob/target_mob in REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS))
	if(!target_mob)
		return

	om_prompt(src, user, list("message" = "Are you sure you want to cryo [target_mob]?", "title" = "Confirmation", "choices" = list("No","Yes"), "requires" = PROMPT_ADMIN(permissions), "data" = list("target" = target_mob)), PROC_REF(cryo_confirmed))

/// Cryopods by their list name ("name (x,y,z)"): human or robot ones.
/datum/admin_verb/despawn_player/proc/cryopods(robot)
	var/list/pods = list()
	for(var/obj/machinery/cryopod/selected_cryopod in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(!selected_cryopod.control_computer())
			continue //Broken pod w/o computer, move on.
		if(istype(selected_cryopod,/obj/machinery/cryopod/robot) == !!robot)
			pods["[selected_cryopod.name] ([selected_cryopod.x],[selected_cryopod.y],[selected_cryopod.z])"] = selected_cryopod
	return pods

/datum/admin_verb/despawn_player/proc/cryopod_chosen(mob/admin, choice, datum/om/prompt/ask)
	var/mob/target_mob = ask.get("target")
	var/list/pods = cryopods(issilicon(target_mob))
	var/obj/machinery/cryopod/selected_cryopod = pods[choice]
	if(!selected_cryopod)
		return
	target_mob.ghostize()
	selected_cryopod.despawn_occupant(target_mob)

/datum/admin_verb/despawn_player/proc/cryo_confirmed(mob/admin, confirm, datum/om/prompt/ask)
	var/client/user = admin.client
	var/mob/target_mob = ask.get("target")
	if(confirm != "Yes")
		return

	var/list/human_cryopods = list()
	var/list/robot_cryopods = list()

	for(var/obj/machinery/cryopod/selected_cryopod in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(!selected_cryopod.control_computer())
			continue //Broken pod w/o computer, move on.

		var/listname = "[selected_cryopod.name] ([selected_cryopod.x],[selected_cryopod.y],[selected_cryopod.z])"
		if(istype(selected_cryopod,/obj/machinery/cryopod/robot))
			robot_cryopods[listname] = selected_cryopod
		else
			human_cryopods[listname] = selected_cryopod

	//Gotta log this up here before they get ghostized and lose their key or anything.
	log_and_message_admins("admin cryo'd [key_name(target_mob)].", user)
	feedback_add_details("admin_verb","ACRYO") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

	if(ishuman(target_mob))
		om_prompt(src, admin, list("kind" = "list", "message" = "Select a cryopod to use", "title" = "Cryopod Choice", "choices" = human_cryopods, "requires" = PROMPT_ADMIN(permissions), "data" = list("target" = target_mob)), PROC_REF(cryopod_chosen))
		return

	else if(issilicon(target_mob))
		if(isAI(target_mob))
			var/mob/living/silicon/ai/ai = target_mob
			registry_join(REGISTRY_EMPTY_AI_CORES, new /obj/structure/AIcore/deactivated(ai.loc))
			GLOB.global_announcer.autosay("[ai] has been moved to intelligence storage.", "Artificial Intelligence Oversight")
			ai.clear_client()
			return
		else
			om_prompt(src, admin, list("kind" = "list", "message" = "Select a cryopod to use", "title" = "Cryopod Choice", "choices" = robot_cryopods, "requires" = PROMPT_ADMIN(permissions), "data" = list("target" = target_mob)), PROC_REF(cryopod_chosen))
			return

	else if(isliving(target_mob))
		target_mob.ghostize()
		qdel(target_mob) //Bye

ADMIN_VERB(cmd_admin_droppod_spawn, R_SPAWN, "Drop Pod Atom", "Spawn a new atom/movable in a drop pod where you are.", ADMIN_CATEGORY_FUN_DROP_POD, object as text)
	var/list/types = typesof(/atom/movable)
	var/list/matches = new()

	for(var/path in types)
		if(findtext("[path]", object))
			matches += path

	if(!matches.len)
		return

	om_prompt_sequence(src, user, list(
		matches.len == 1 ? null : list("key" = "chosen", "kind" = "list", "message" = "Select a movable type:", "title" = "Spawn in Drop Pod", "choices" = matches),
		list("key" = "podtype", "message" = "Destructive drop pods cause damage in a 3x3 and may break turfs. Polite drop pods lightly damage the turfs but won't break through.", "title" = "Drop Pod", "choices" = list("Polite", "Destructive", "Cancel"), "abort" = "Cancel"),
		list("key" = "autoopen", "message" = "Should the pod open automatically?", "title" = "Drop Pod", "choices" = list("Yes", "No", "Cancel"), "abort" = "Cancel"),
	), PROC_REF(pod_answered), list("requires" = PROMPT_ADMIN(permissions), "data" = list("only" = matches.len == 1 ? matches[1] : null)))

/datum/admin_verb/cmd_admin_droppod_spawn/proc/pod_answered(mob/admin, datum/om/prompt/ask)
	var/client/user = admin.client
	var/chosen = ask.get("only") || ask.get("chosen")
	var/podtype = ask.get("podtype")
	var/autoopen = ask.get("autoopen")
	switch(podtype)
		if("Destructive")
			var/atom/movable/AM = new chosen(user.mob.loc)
			new /obj/structure/drop_pod(get_turf(user.mob), AM, autoopen == "Yes" ? TRUE : FALSE)
		if("Polite")
			var/atom/movable/AM = new chosen(user.mob.loc)
			new /obj/structure/drop_pod/polite(get_turf(user.mob), AM, autoopen == "Yes" ? TRUE : FALSE)

	feedback_add_details("admin_verb","DPA") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(cmd_admin_droppod_deploy, R_SPAWN, "Drop Pod Deploy", "Drop an existing mob where you are in a drop pod.", ADMIN_CATEGORY_FUN_DROP_POD, object as text)
	om_prompt_sequence(src, user, list(
		list("key" = "target", "kind" = "list", "message" = "Select the mob to drop:", "title" = "Mob Picker", "choices" = REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS)),
		list("key" = "podtype", "message" = "Destructive drop pods cause damage in a 3x3 and may break turfs. Polite drop pods lightly damage the turfs but won't break through.", "title" = "Drop Pod", "choices" = list("Polite", "Destructive", "Cancel"), "abort" = "Cancel"),
		list("key" = "autoopen", "message" = "Should the pod open automatically?", "title" = "Drop Pod", "choices" = list("Yes", "No", "Cancel"), "abort" = "Cancel"),
	), PROC_REF(pod_answered), list("requires" = PROMPT_ADMIN(permissions)))

/datum/admin_verb/cmd_admin_droppod_deploy/proc/pod_answered(mob/admin, datum/om/prompt/ask)
	var/client/user = admin.client
	var/mob/living/living_target = ask.get("target")
	var/podtype = ask.get("podtype")
	var/autoopen = ask.get("autoopen")
	switch(podtype)
		if("Destructive")
			new /obj/structure/drop_pod(get_turf(user.mob), living_target, autoopen == "Yes" ? TRUE : FALSE)
		if("Polite")
			new /obj/structure/drop_pod/polite(get_turf(user.mob), living_target, autoopen == "Yes" ? TRUE : FALSE)

	feedback_add_details("admin_verb","DPD") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(toggle_vantag_hud_global, R_EVENT|R_SERVER|R_ADMIN, "Toggle Global Event HUD", "Give everyone the Event HUD.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	GLOB.global_vantag_hud = !GLOB.global_vantag_hud
	if(GLOB.global_vantag_hud)
		for(var/mob/living/living_target in REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS))
			if(living_target.ckey)
				living_target.vantag_hud = TRUE
				living_target.recalculate_vis()

	to_chat(user, span_warning("Global Event HUD has been turned [GLOB.global_vantag_hud ? "on" : "off"]."))



ADMIN_VERB(spawn_character_mob, R_SPAWN, "Spawn Character As Mob", "Spawn a specified ckey as a chosen mob.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	om_prompt_sequence(src, user, list(
		list("key" = "client", "kind" = "list", "message" = "Who are we spawning as a mob?", "title" = "Client", "choices" = GLOB.clients),
		list("key" = "path", "kind" = "text", "message" = "Mob path to spawn as?", "title" = "Mob"),
		PROC_REF(ask_mob_type),
		list("key" = "char_name", "message" = "Spawn mob with their character name?", "title" = "Mob name", "choices" = list("Yes", "No", "Cancel"), "abort" = "Cancel"),
		list("key" = "vorgans", "message" = "Spawn mob with their character's vore organs and prefs?", "title" = "Vore organs", "choices" = list("Yes", "No", "Cancel"), "abort" = "Cancel"),
		list("key" = "flavor", "message" = "Spawn mob with their character's flavor text?", "title" = "Flavor text", "choices" = list("General", "Robot", "Cancel"), "optional" = TRUE),
	), PROC_REF(spawn_answered), list("requires" = PROMPT_ADMIN(permissions)))

/// The /mob/living paths matching the typed text.
/datum/admin_verb/spawn_character_mob/proc/matching_types(text)
	var/list/matches = list()
	for(var/path in typesof(/mob/living))
		if(findtext("[path]", text))
			matches += path
	return matches

/datum/admin_verb/spawn_character_mob/proc/ask_mob_type(mob/admin, datum/om/prompt/ask)
	var/list/matches = matching_types(ask.get("path"))
	if(!matches.len)
		return PROMPT_STOP
	if(matches.len == 1)
		ask.put("type", matches[1])
		return null
	return list("key" = "type", "kind" = "list", "message" = "Select a mob type", "title" = "Select Mob", "choices" = matches)

/datum/admin_verb/spawn_character_mob/proc/spawn_answered(mob/admin, datum/om/prompt/ask)
	var/client/user = admin.client
	var/client/picked_client = ask.get("client")
	var/mob/living/chosen = ask.get("type")
	var/name = ask.get("char_name") == "Yes"
	var/organs = ask.get("vorgans") == "Yes"
	var/flavor = ask.get("flavor")

	var/spawnloc
	if(!user.mob)
		to_chat(user, "Can't spawn them in unless you're in a valid spawn location!")
		return
	spawnloc = get_turf(user.mob)

	var/mob/living/new_mob = new chosen(spawnloc)

	if(!new_mob)
		to_chat(user, "Spawning failed, try again or bully coders")
		return

	if(name)
		var/spawner_name = picked_client.prefs.read_preference(/datum/preference/name/real_name)
		new_mob.real_name = spawner_name
		new_mob.name = spawner_name


	new_mob.key = picked_client.key //Finally put them in the mob
	// migrated flavor_texts/flavour_texts_robot
	if(flavor == "General")
		new_mob.flavor_text = LAZYACCESS(new_mob?.client?.prefs?.read_preference(/datum/preference/flavor_texts), "general")
	if(flavor == "Robot")
		new_mob.flavor_text = LAZYACCESS(new_mob?.client?.prefs?.read_preference(/datum/preference/flavour_texts_robot), "Default")
	if(organs)
		new_mob.copy_from_prefs_vr()
		if(LAZYLEN(new_mob.vore_organs))
			new_mob.vore_selected = new_mob.vore_organs[1]
			if(isanimal(new_mob))
				var/mob/living/simple_mob/new_simple_mob = new_mob
				if(!new_simple_mob.voremob_loaded || !new_simple_mob.vore_active)
					new_simple_mob.init_vore(TRUE)

	log_admin("[key_name_admin(user)] has spawned [new_mob.key] as mob [new_mob.type].")
	message_admins("[key_name_admin(user)] has spawned [new_mob.key] as mob [new_mob.type].", 1)

	to_chat(new_mob, "You've been spawned as a mob! Have fun.")

	feedback_add_details("admin_verb","SCAM") //heh

	return new_mob

ADMIN_VERB(cmd_admin_z_narrate, (R_ADMIN|R_MOD|R_EVENT), "Z Narrate", "Narrates to your Z level.", ADMIN_CATEGORY_FUN_NARRATE) // Allows administrators to fluff events a little easier -- TLE
	om_prompt(src, user, list("kind" = "text", "message" = "Message:", "title" = "Enter the text you wish to appear to everyone:", "requires" = PROMPT_ADMIN(permissions)), PROC_REF(message_entered))

/datum/admin_verb/cmd_admin_z_narrate/proc/message_entered(mob/admin, msg, datum/om/prompt/ask)
	var/client/user = admin.client
	if(!(msg[1] == "<" && msg[length(msg)] == ">")) //You can use HTML but only if the whole thing is HTML. Tries to prevent admin 'accidents'.
		msg = sanitize(msg)

	if (!msg)
		return

	var/pos_z = get_z(user.mob)
	if (!pos_z)
		return
	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(M.z == pos_z)
			to_chat(M, msg)
	log_admin("ZNarrate: [key_name(user)] : [msg]")
	message_admins(span_blue(span_bold(" ZNarrate: [key_name_admin(user)] : [msg]<BR>")), 1)
	feedback_add_details("admin_verb","GLNA") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB_AND_CONTEXT_MENU(toggle_vantag_hud, R_EVENT|R_ADMIN|R_SERVER, "Give/Remove Event HUD", "Give a mob the event hud, which shows them other people's event preferences, or remove it from them.", ADMIN_CATEGORY_FUN_EVENT_KIT, mob/target in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
	if(target.vantag_hud)
		target.vantag_hud = FALSE
		target.recalculate_vis()
		to_chat(user, "You removed the event HUD from [key_name(target)].")
		to_chat(target, "You no longer have the event HUD.")
	else
		target.vantag_hud = TRUE
		target.recalculate_vis()
		to_chat(user, "You gave the event HUD to [key_name(target)].")
		to_chat(target, "You now have the event HUD.  Icons will appear next to characters indicating if they prefer to be killed(red crosshairs), devoured(belly), or kidnapped(blue crosshairs) by event characters.")
	feedback_add_details("admin_verb","GREHud") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
