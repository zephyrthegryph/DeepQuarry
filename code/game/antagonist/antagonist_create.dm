/datum/antagonist/proc/create_antagonist(datum/mind/target, move, gag_announcement, preserve_appearance)

	if(!target)
		return

	update_antag_mob(target, preserve_appearance)
	if(!target.current)
		remove_antagonist(target)
		return 0
	if(flags & ANTAG_CHOOSE_NAME)
		after(src, 0.1 SECONDS, PROC_REF(set_antag_name), with = list(target.current))
	if(move)
		place_mob(target.current)
	update_leader()
	create_objectives(target)
	update_icons_added(target)
	greet(target)
	announce_antagonist_spawn()

/datum/antagonist/proc/create_default(mob/source)
	var/mob/living/M
	if(mob_path)
		M = new mob_path(get_turf(source))
	else
		M = new /mob/living/carbon/human(get_turf(source))
	M.real_name = source.real_name
	M.name = M.real_name
	if(!isnull(source.mind))
		source.mind.transfer_to(M)
	M.ckey = source.ckey
	add_antagonist(M.mind, 1, 0, 1) // Equip them and move them to spawn.
	return M

/datum/antagonist/proc/create_id(assignment, mob/living/carbon/human/player, equip = 1)

	var/obj/item/card/id/W = new id_type(player)
	if(!W) return
	if(LAZYLEN(default_access))
		W.access |= default_access
	W.assignment = "[assignment]"
	player.set_id_info(W)
	if(equip) player.equip_to_slot_or_del(W, SLOT_ID_ID)
	return W

/datum/antagonist/proc/create_radio(freq, mob/living/carbon/human/player)
	var/obj/item/radio/R

	switch(freq)
		if(SYND_FREQ)
			R = new/obj/item/radio/headset/syndicate(player)
		if(RAID_FREQ)
			R = new/obj/item/radio/headset/raider(player)
		else
			R = new/obj/item/radio/headset(player)
			R.set_frequency(freq)

	player.equip_to_slot_or_del(R, SLOT_ID_EAR_L)
	return R

/datum/antagonist/proc/create_nuke(atom/paper_spawn_loc, datum/mind/code_owner)

	// Decide on a code.
	var/obj/effect/landmark/nuke_spawn = locate(nuke_spawn_loc ? nuke_spawn_loc : "landmark*Nuclear-Bomb")

	var/code
	if(nuke_spawn)
		var/obj/machinery/nuclearbomb/nuke = new(get_turf(nuke_spawn))
		code = "[rand(10000, 99999)]"
		nuke.r_code = code

	if(code)
		if(!paper_spawn_loc)
			if(leader() && leader().current)
				paper_spawn_loc = get_turf(leader().current)
			else
				paper_spawn_loc = get_turf(locate("landmark*Nuclear-Code"))

		if(paper_spawn_loc)
			// Create and pass on the bomb code paper.
			var/obj/item/paper/P = new(paper_spawn_loc)
			P.set_info("The nuclear authorization code is: <b>[code]</b>")
			P.name = "nuclear bomb code"
			if(leader() && leader().current)
				if(get_turf(P) == get_turf(leader().current))
					leader().current.put_in_hands(P)

		if(!code_owner && leader())
			code_owner = leader()
		if(code_owner)
			code_owner.store_memory(span_bold("Nuclear Bomb Code") + ": [code]", 0, 0)
			to_chat(code_owner.current, "The nuclear authorization code is: <B>[code]</B>")
	else
		message_admins(span_danger("Could not spawn nuclear bomb. Contact a developer."))
		return

	spawned_nuke = code
	return code

/datum/antagonist/proc/greet(datum/mind/player)
	// Makes it harder to miss if you're alt-tabbed or not paying attention.
	if(antag_sound)
		SEND_SOUND(player.current, sound(antag_sound))
	window_flash(player.current.client)

	// Basic intro text.
	to_chat(player.current, span_danger(span_large("You are a [role_text]!")))
	if(leader_welcome_text && player == leader())
		to_chat(player.current, span_notice("[leader_welcome_text]"))
	else
		to_chat(player.current, span_notice("[welcome_text]"))
	if (CONFIG_GET(flag/objectives_disabled))
		to_chat(player.current, span_notice("[antag_text]"))

	if((flags & ANTAG_HAS_NUKE) && !spawned_nuke)
		create_nuke()

	if (!CONFIG_GET(flag/objectives_disabled))
		show_objectives(player)
	return 1

/datum/antagonist/proc/set_antag_name(mob/living/player)
	// Choose a name, if any.
	open_request(src, /datum/prompt/text, PROC_REF(antag_name_chosen), answerer = player, question = "You are a [role_text]. Would you like to change your name to something else?", title = "Name change", max_len = MAX_NAME_LEN, name_text = TRUE, timeout = 0)

/datum/antagonist/proc/antag_name_chosen(datum/act/request/A)
	var/datum/request/R = A.request
	if(!A.answer && R.outcome != REQ_CANCELLED)
		return
	var/mob/living/player = R.answerer
	if(QDELETED(player))
		return
	// Closing the original name prompt supplied a blank answer and still refreshed access.
	var/newname = A.answer ? A.answer.value : ""
	if (newname)
		player.real_name = newname
		player.name = player.real_name
		player.dna.real_name = newname
	if(player.mind) player.mind.name = player.name
	// Update any ID cards.
	update_access(player)
