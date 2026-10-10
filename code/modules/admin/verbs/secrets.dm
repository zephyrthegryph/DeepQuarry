ADMIN_VERB(secrets, R_HOLDER, "Secrets", "Abuse harder than you ever have before with this handy dandy semi-misc stuff menu.", ADMIN_CATEGORY_SECRETS)
	var/datum/secrets_menu/tgui = new(user)
	tgui.tgui_interact(user.mob)
	feedback_add_details("admin_verb","S") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/datum/secrets_menu
	var/tmp/client/holder	//client of whoever is using this datum
	var/is_debugger = FALSE
	var/is_funmin = FALSE

/datum/secrets_menu/New(user)//user can either be a client or a mob due to byondcode(tm)
	if (istype(user, /client))
		var/client/user_client = user
		rel_set(src, nameof(holder), user_client) //if its a client, assign it to holder
	else
		var/mob/user_mob = user
		rel_set(src, nameof(holder), user_mob.client) //if its a mob, assign the mob's client to holder

	is_debugger = admin_require(holder(), R_DEBUG, "secrets_menu", TRUE)
	is_funmin = admin_require(holder(), R_FUN, "secrets_menu", TRUE)

/datum/secrets_menu/tgui_close()
	spent(src)

CAPABILITIES(/datum/secrets_menu)
	interface("Secrets", rights = R_HOLDER)
	op("admin_log", ui_act("admin_log"), then(PROC_REF(ui_act_admin_log)))
	op("dialog_log", ui_act("dialog_log"), then(PROC_REF(ui_act_dialog_log)))
	op("show_admins", ui_act("show_admins"), then(PROC_REF(ui_act_show_admins)))
	op("show_traitors_and_objectives", ui_act("show_traitors_and_objectives"), then(PROC_REF(ui_act_show_traitors_and_objectives)))
	op("show_game_mode", ui_act("show_game_mode"), then(PROC_REF(ui_act_show_game_mode)))
	op("list_bombers", ui_act("list_bombers"), then(PROC_REF(ui_act_list_bombers)))
	op("list_signalers", ui_act("list_signalers"), then(PROC_REF(ui_act_list_signalers)))
	op("list_lawchanges", ui_act("list_lawchanges"), then(PROC_REF(ui_act_list_lawchanges)))
	op("showailaws", ui_act("showailaws"), then(PROC_REF(ui_act_showailaws)))
	op("manifest", ui_act("manifest"), then(PROC_REF(ui_act_manifest)))
	op("dna", ui_act("dna"), then(PROC_REF(ui_act_dna)))
	op("fingerprints", ui_act("fingerprints"), then(PROC_REF(ui_act_fingerprints)))
	op("prison_warp", ui_act("prison_warp"), then(PROC_REF(ui_act_prison_warp)))
	op("night_shift_set", ui_act("night_shift_set"), asks(/datum/prompt/choice, fields = list("question" = "What do you want to set night shift to? This will override the automatic system until set to automatic again.", "title" = "Night Shift", "choices" = list("On", "Off", "Automatic"), "buttons" = TRUE, "timeout" = 0), step = "a1"), then(PROC_REF(ui_act_night_shift_set)))
	op("trigger_xenomorph_infestation", ui_act("trigger_xenomorph_infestation"), then(PROC_REF(ui_act_trigger_xenomorph_infestation)))
	op("trigger_cortical_borer_infestation", ui_act("trigger_cortical_borer_infestation"), then(PROC_REF(ui_act_trigger_cortical_borer_infestation)))
	op("jump_shuttle", ui_act("jump_shuttle"), asks(/datum/prompt/choice, fields = list("question" = "Which shuttle do you want to jump?", "title" = "Shuttle Choice", "choices" = computed(PROC_REF(ui_act_jump_shuttle_a2_choices)), "timeout" = 0), step = "a2"), asks(/datum/prompt/choice, fields = list("question" = "Which area is the shuttle at now? (MAKE SURE THIS IS CORRECT OR THINGS WILL BREAK)", "title" = "Area Choice", "choices" = computed(PROC_REF(ui_act_jump_shuttle_a3_choices)), "timeout" = 0), step = "a3"), asks(/datum/prompt/choice, fields = list("question" = "Which area is the shuttle at now? (MAKE SURE THIS IS CORRECT OR THINGS WILL BREAK)", "title" = "Area Choice", "choices" = computed(PROC_REF(ui_act_jump_shuttle_a4_choices)), "timeout" = 0), step = "a4"), asks(/datum/prompt/choice, fields = list("question" = "Is there a transition area for this jump?", "title" = "Transition?", "choices" = list("Yes","No"), "buttons" = TRUE, "timeout" = 0), step = "a5"), asks(/datum/prompt/choice, fields = list("question" = "Which area is the transition area? (MAKE SURE THIS IS CORRECT OR THINGS WILL BREAK)", "title" = "Area Choice", "choices" = computed(PROC_REF(ui_act_jump_shuttle_a6_choices)), "timeout" = 0), step = "a6", when = PROC_REF(jump_has_transition)), asks(/datum/prompt/number, fields = list("question" = "How many seconds will this jump take?", "timeout" = 0), step = "a7", when = PROC_REF(jump_has_transition)), then(PROC_REF(ui_act_jump_shuttle)))
	op("launch_shuttle_forced", ui_act("launch_shuttle_forced"), asks(/datum/prompt/choice, fields = list("question" = "Which shuttle's launch do you want to force?", "title" = "Shuttle Choice", "choices" = computed(PROC_REF(ui_act_launch_shuttle_forced_a8_choices)), "timeout" = 0), step = "a8"), then(PROC_REF(ui_act_launch_shuttle_forced)))
	op("launch_shuttle", ui_act("launch_shuttle"), asks(/datum/prompt/choice, fields = list("question" = "Which shuttle do you want to launch?", "title" = "Shuttle Choice", "choices" = computed(PROC_REF(ui_act_launch_shuttle_a9_choices)), "timeout" = 0), step = "a9"), then(PROC_REF(ui_act_launch_shuttle)))
	op("move_shuttle", ui_act("move_shuttle"), asks(/datum/prompt/choice, fields = list("question" = "This command directly moves a shuttle from one area to another. DO NOT USE THIS UNLESS YOU ARE DEBUGGING A SHUTTLE AND YOU KNOW WHAT YOU ARE DOING.", "title" = "Are you sure?", "choices" = list("Ok", "Cancel"), "buttons" = TRUE, "timeout" = 0), step = "a10"), asks(/datum/prompt/choice, fields = list("question" = "Which shuttle do you want to jump?", "title" = "Shuttle Choice", "choices" = computed(PROC_REF(ui_act_move_shuttle_a11_choices)), "timeout" = 0), step = "a11"), asks(/datum/prompt/choice, fields = list("question" = "Which landmark do you want to jump to? (IF YOU GET THIS WRONG THINGS WILL BREAK)", "title" = "Landmark Choice", "choices" = computed(PROC_REF(ui_act_move_shuttle_a12_choices)), "timeout" = 0), step = "a12"), then(PROC_REF(ui_act_move_shuttle)))
	op("ghost_mode", ui_act("ghost_mode"), then(PROC_REF(ui_act_ghost_mode)))
	op("paintball_mode", ui_act("paintball_mode"), then(PROC_REF(ui_act_paintball_mode)))
	op("power", ui_act("power"), then(PROC_REF(ui_act_power)))
	op("unpower", ui_act("unpower"), then(PROC_REF(ui_act_unpower)))
	op("quickpower", ui_act("quickpower"), then(PROC_REF(ui_act_quickpower)))
	op("gravity", ui_act("gravity"), then(PROC_REF(ui_act_gravity)))
	op("tripleAI", ui_act("tripleAI"), then(PROC_REF(ui_act_tripleai)))
	op("onlyone", ui_act("onlyone"), asks(/datum/prompt/choice, fields = list("question" = "Delay by 40 seconds?", "title" = "There can, in fact, only be one", "choices" = list("Instant!", "40 seconds (crush the hope of a normal shift)"), "buttons" = TRUE, "timeout" = 0), step = "a13"), then(PROC_REF(ui_act_onlyone)))
	op("blackout", ui_act("blackout"), then(PROC_REF(ui_act_blackout)))
	op("partial_blackout", ui_act("partial_blackout"), then(PROC_REF(ui_act_partial_blackout)))
	op("whiteout", ui_act("whiteout"), then(PROC_REF(ui_act_whiteout)))
	op("changebombcap", ui_act("changebombcap"), asks(/datum/prompt/choice, fields = list("question" = "Select the max explosion range", "title" = "Change Bomb Cap", "choices" = list(14, 16, 20, 28, 56, 128), "timeout" = 0), step = "a14"), then(PROC_REF(ui_act_changebombcap)))
	op("alter_narsie", ui_act("alter_narsie"), asks(/datum/prompt/choice, fields = list("question" = "How do you wish for Nar-Sie to interact with its surroundings?", "title" = "NarChoice", "choices" = list("CultStation13", "Nar-Singulo"), "buttons" = TRUE, "timeout" = 0), step = "a15"), then(PROC_REF(ui_act_alter_narsie)))
	op("remove_all_clothing", ui_act("remove_all_clothing"), then(PROC_REF(ui_act_remove_all_clothing)))
	op("remove_internal_clothing", ui_act("remove_internal_clothing"), then(PROC_REF(ui_act_remove_internal_clothing)))
	op("send_strike_team", ui_act("send_strike_team"), then(PROC_REF(ui_act_send_strike_team)))
	op("corgie", ui_act("corgie"), then(PROC_REF(ui_act_corgie)))
	op("monkey", ui_act("monkey"), then(PROC_REF(ui_act_monkey)))
	op("supermatter_cascade", ui_act("supermatter_cascade"), asks(/datum/prompt/choice, fields = list("question" = "You sure you want to destroy the universe and create a large explosion at your location? Misuse of this could result in removal of flags or hilarity.", "title" = "WARNING!", "choices" = list("NO TIME TO EXPLAIN", "Cancel"), "buttons" = TRUE, "timeout" = 0), step = "a16"), then(PROC_REF(ui_act_supermatter_cascade)))
	op("summon_narsie", ui_act("summon_narsie"), asks(/datum/prompt/choice, fields = list("question" = "You sure you want to end the round and summon Nar-Sie at your location? Misuse of this could result in removal of flags or hilarity.", "title" = "WARNING!", "choices" = list("PRAISE SATAN", "Cancel"), "buttons" = TRUE, "timeout" = 0), step = "a17"), then(PROC_REF(ui_act_summon_narsie)))

/datum/secrets_menu/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["is_debugger"] = is_debugger
	data["is_funmin"] = is_funmin
	return data

#define HIGHLANDER_DELAY_TEXT "40 seconds (crush the hope of a normal shift)"
/datum/secrets_menu/proc/ui_gate(datum/act/op/A)
	var/action = A.window_action()
	if((action != "admin_log" && action != "show_admins") && !admin_can(A.actor?.client, R_ADMIN))
		return FALSE
	return TRUE

/datum/secrets_menu/proc/ui_act_admin_log(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	// structured TGUI AdminReport.
	if(!GLOB.admin_log.len)
		dq_admin_report_html(holder(), "Admin Logs", "No-one has done anything this round!")
	else
		dq_admin_report_lines(holder(), "Admin Logs", GLOB.admin_log)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_dialog_log(datum/act/op/A)
	var/mob/user = A.actor
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/persistent_client_logs)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_show_admins(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	// structured TGUI AdminReport with typed table.
	if(GLOB.admin_datums)
		var/list/rows = list()
		for(var/ckey in GLOB.admin_datums)
			var/datum/admins/D = GLOB.admin_datums[ckey]
			rows += list(list("[ckey]", D.rank_names()))
		dq_admin_report_table(holder(), "Current admins", list("Ckey", "Rank"), rows)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_show_traitors_and_objectives(datum/act/op/A)
	var/mob/user = A.actor
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	holder().admin_datum().check_antagonists(user.client)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_show_game_mode(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if (ticker_mode()) tgui_alert_async(holder(), "The game mode is [ticker_mode().name]")
	else tgui_alert_async(holder(), "For some reason there's a ticker, but not a game mode")

//Buttons for debug.
//tbd

//Buttons for helpful stuff. This is where people land in the tgui
	if(holder())
		log_admin("[key_name(holder())] used secret: show_game_mode.")

/datum/secrets_menu/proc/ui_act_list_bombers(datum/act/op/A)
	var/mob/user = A.actor
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	holder().admin_datum().list_bombers(user)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_list_signalers(datum/act/op/A)
	var/mob/user = A.actor
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	holder().admin_datum().list_signalers(user)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_list_lawchanges(datum/act/op/A)
	var/mob/user = A.actor
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	holder().admin_datum().list_law_changes(user)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_showailaws(datum/act/op/A)
	var/mob/user = A.actor
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	holder().admin_datum().list_law_changes(user)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_manifest(datum/act/op/A)
	var/mob/user = A.actor
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	holder().admin_datum().show_manifest(user)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_dna(datum/act/op/A)
	var/mob/user = A.actor
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	holder().admin_datum().list_dna(user)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_fingerprints(datum/act/op/A)
	var/mob/user = A.actor
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	holder().admin_datum().list_fingerprints(user)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_prison_warp(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	for(var/mob/living/carbon/human/H in REGISTRY_MEMBERS(REGISTRY_MOBS))
		var/turf/T = get_turf(H)
		var/security = 0
		if((T in using_map.admin_levels) || registry_has(REGISTRY_PRISONWARPED, H))
		//don't warp them if they aren't ready or are already there
			continue
		H.status_at_least(STAT_PARALYZED, 5)
		H.status_at_least(STAT_SLEEPING, 5)
		if(H.get_equipped_item(SLOT_ID_ID))
			var/obj/item/card/id/id = H.get_idcard()
			for(var/A2 in id.GetAccess())
				if(A2 == ACCESS_SECURITY)
					security++
		if(!security)
			//strip their stuff before they teleport into a cell :downs:
			for(var/obj/item/W in contents_of(H))
				if(istype(W, /obj/item/organ/external))
					continue
					//don't strip organs
				H.drop_from_inventory(W)
			//teleport person to cell
			H.forceMove(pick(GLOB.prisonwarp))
			H.equip_to_slot_or_del(new /obj/item/clothing/under/color/prison(H), SLOT_ID_UNIFORM)
			H.equip_to_slot_or_del(new /obj/item/clothing/shoes/orange(H), SLOT_ID_SHOES)
		else
			//teleport security person
			H.forceMove(pick(GLOB.prisonsecuritywarp))
		registry_join(REGISTRY_PRISONWARPED, H)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_night_shift_set(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	var/val = A.step_value("a1")
	switch(val)
		if("Automatic")
			if(CONFIG_GET(flag/enable_night_shifts))
				SSnightshift.automatic = TRUE
				SSnightshift.check_nightshift(TRUE)
			else
				SSnightshift.update_nightshift(active = FALSE, announce = TRUE, forced = TRUE)
		if("On")
			SSnightshift.automatic = FALSE
			SSnightshift.update_nightshift(active = TRUE, announce = TRUE, forced = TRUE)
		if("Off")
			SSnightshift.automatic = FALSE
			SSnightshift.update_nightshift(active = FALSE, announce = TRUE, forced = TRUE)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_trigger_xenomorph_infestation(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	GLOB.xenomorphs.attempt_random_spawn()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_trigger_cortical_borer_infestation(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	GLOB.borers.attempt_random_spawn()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_jump_shuttle_a2_choices(datum/act/op/A)
	return shuttles_shuttles()

/datum/secrets_menu/proc/ui_act_jump_shuttle(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	var/shuttle_tag = A.step_value("a2")
	if (!shuttle_tag) return

	var/datum/shuttle/S = shuttles_shuttles()[shuttle_tag]

	var/list/area_choices = return_areas()
	var/origin_area = A.step_value("a3")
	if(isnull(origin_area))
		return
	if (!origin_area) return

	var/destination_area = A.step_value("a4")
	if(isnull(destination_area))
		return
	if (!destination_area) return

	var/long_jump = A.step_value("a5")
	if(isnull(long_jump))
		return
	if(!long_jump)
		return
	if (long_jump == "Yes")
		var/transition_area = A.step_value("a6")
		if(isnull(transition_area))
			return
		if (!transition_area) return

		var/move_duration = A.step_value("a7")
		if(isnull(move_duration))
			return

		S.long_jump(area_choices[origin_area], area_choices[destination_area], area_choices[transition_area], move_duration)
		message_admins(span_notice("[key_name_admin(holder())] has initiated a jump from [origin_area] to [destination_area] lasting [move_duration] seconds for the [shuttle_tag] shuttle"), 1)
		log_admin("[key_name_admin(holder())] has initiated a jump from [origin_area] to [destination_area] lasting [move_duration] seconds for the [shuttle_tag] shuttle")
	else
		S.short_jump(area_choices[origin_area], area_choices[destination_area])
		message_admins(span_notice("[key_name_admin(holder())] has initiated a jump from [origin_area] to [destination_area] for the [shuttle_tag] shuttle"), 1)
		log_admin("[key_name_admin(holder())] has initiated a jump from [origin_area] to [destination_area] for the [shuttle_tag] shuttle")
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_launch_shuttle_forced(datum/act/op/A)
	var/mob/user = A.actor
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	var/list/valid_shuttles = list()
	for (var/shuttle_tag in shuttles_shuttles())
		if (istype(shuttles_shuttles()[shuttle_tag], /datum/shuttle/autodock))
			valid_shuttles += shuttle_tag

	var/shuttle_tag = A.step_value("a8")
	if(isnull(shuttle_tag))
		return
	if (!shuttle_tag)
		return

	var/datum/shuttle/autodock/S = shuttles_shuttles()[shuttle_tag]
	if (S.can_force())
		S.force_launch(holder(), user)
		log_and_message_admins("forced the [shuttle_tag] shuttle", holder())
	else
		tgui_alert_async(holder(), "The [shuttle_tag] shuttle launch cannot be forced at this time. It's busy, or hasn't been launched yet.")
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_launch_shuttle(datum/act/op/A)
	var/mob/user = A.actor
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	var/list/valid_shuttles = list()
	for (var/shuttle_tag in shuttles_shuttles())
		if (istype(shuttles_shuttles()[shuttle_tag], /datum/shuttle/autodock))
			valid_shuttles += shuttle_tag

	var/shuttle_tag = A.step_value("a9")
	if(isnull(shuttle_tag))
		return
	if (!shuttle_tag)
		return

	var/datum/shuttle/autodock/S = shuttles_shuttles()[shuttle_tag]
	if (S.can_launch())
		S.launch(holder(), user)
		log_and_message_admins("launched the [shuttle_tag] shuttle", holder())
	else
		tgui_alert_async(holder(), "The [shuttle_tag] shuttle cannot be launched at this time. It's probably busy.")
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_move_shuttle(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	var/confirm = A.step_value("a10")
	if (confirm != "Ok")
		return

	var/shuttle_tag = A.step_value("a11")
	if(isnull(shuttle_tag))
		return
	if (!shuttle_tag) return

	var/datum/shuttle/S = shuttles_shuttles()[shuttle_tag]

	var/destination_tag = A.step_value("a12")
	if(isnull(destination_tag))
		return
	if (!destination_tag) return
	var/destination_location = SSshuttles.get_landmark(destination_tag)
	if (!destination_location) return

	S.attempt_move(destination_location)
	log_and_message_admins("moved the [shuttle_tag] shuttle", holder())

	// fun! buttons.
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_ghost_mode(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	var/list/affected_mobs = list()
	var/list/affected_areas = list()
	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS))
		if(M.stat == CONSCIOUS && !(M in affected_mobs))
			affected_mobs |= M
			switch(rand(1,4))
				if(1)
					M.show_message(span_notice("You shudder as if cold..."), 1)
				if(2)
					M.show_message(span_notice("You feel something gliding across your back..."), 1)
				if(3)
					M.show_message(span_notice("Your eyes twitch, you feel like something you can't see is here..."), 1)
				if(4)
					M.show_message(span_notice("You notice something moving out of the corner of your eye, but nothing is there..."), 1)

			for(var/obj/W in orange(5,M))
				if(prob(25) && !W.anchored)
					step_rand(W)

			var/area/A2 = get_area(M)
			if(A2.requires_power && !A2.always_unpowered && A2.power_light && (A2.z in using_map.player_levels))
				affected_areas |= get_area(M)

	affected_mobs |= holder()
	for(var/area/AffectedArea in affected_areas)
		AffectedArea.set_channels(AffectedArea.power_equip, FALSE, AffectedArea.power_environ)
		after(AffectedArea, rand(2.5 SECONDS, 5 SECONDS), GLOBAL_PROC_REF(chilling_wind_relight), with = list(AffectedArea))

	after(null, 10 SECONDS, GLOBAL_PROC_REF(chilling_wind_stops), with = list(affected_mobs.Copy()))
	affected_mobs.Cut()
	affected_areas.Cut()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_paintball_mode(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	for(var/species in GLOB.all_species)
		var/datum/species/S = GLOB.all_species[species]
		dq_set_blood_color(S, "rainbow")
	for(var/obj/effect/decal/cleanable/blood/B in world)
		B.set_basecolor("rainbow")
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_power(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	if(!is_funmin)
		return
	log_admin("[key_name(holder())] made all areas powered")
	message_admins(span_adminnotice("[key_name_admin(holder())] made all areas powered"))
	power_restore()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_unpower(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	if(!is_funmin)
		return
	log_admin("[key_name(holder())] made all areas unpowered")
	message_admins(span_adminnotice("[key_name_admin(holder())] made all areas unpowered"))
	power_failure()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_quickpower(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	if(!is_funmin)
		return
	log_admin("[key_name(holder())] made all SMESs powered")
	message_admins(span_adminnotice("[key_name_admin(holder())] made all SMESs powered"))
	power_restore_quick()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_gravity(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	GLOB.gravity_is_on = !GLOB.gravity_is_on
	for(var/area/A2 in world)
		A2.gravitychange(GLOB.gravity_is_on)

	feedback_inc("admin_secrets_fun_used",1)
	feedback_add_details("admin_secrets_fun_used","Grav")
	if(GLOB.gravity_is_on)
		log_admin("[key_name(holder())] toggled gravity on.", 1)
		message_admins(span_notice("[key_name_admin(holder())] toggled gravity on."), 1)
		GLOB.command_announcement.Announce("Gravity generators are again functioning within normal parameters. Sorry for any inconvenience.", ANNOUNCER_MSG_GRAVITY_ON)
	else
		log_admin("[key_name(holder())] toggled gravity off.", 1)
		message_admins(span_notice("[key_name_admin(holder())] toggled gravity off."), 1)
		GLOB.command_announcement.Announce("Feedback surge detected in mass-distributions systems. Artificial gravity has been disabled whilst the system reinitializes. Further failures may result in a gravitational collapse and formation of blackholes. Have a nice day.", ANNOUNCER_MSG_GRAVITY_OFF)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_tripleai(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	if(!is_funmin)
		return
	holder().triple_ai()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_onlyone(datum/act/op/A)
	var/mob/user = A.actor
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	if(!is_funmin)
		return
	var/response = A.step_value("a13")
	if(isnull(response))
		return
	switch(response)
		if("Instant!")
			holder().only_one(FALSE, user)
		if(HIGHLANDER_DELAY_TEXT)
			holder().only_one_delayed(user)
		else
			return
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_blackout(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	if(!is_funmin)
		return
	message_admins("[key_name_admin(holder())] broke all lights")
	//for(var/obj/machinery/light/L as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/light))
	//	L.break_light_tube()
	//	CHECK_TICK
	lightsout(0,0)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_partial_blackout(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	if(!is_funmin)
		return
	message_admins("[key_name_admin(holder())] broke some lights")
	lightsout(1,2)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_whiteout(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	if(!is_funmin)
		return
	message_admins("[key_name_admin(holder())] fixed all lights")
	for(var/obj/machinery/light/L in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		L.fix()
		CHECK_TICK
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_changebombcap(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	if(!is_funmin)
		return

	var/new_cap = A.step_value("a14")
	if(isnull(new_cap))
		return

	if(new_cap)
		GLOB.max_explosion_range = new_cap

	var/range_dev = GLOB.max_explosion_range *0.25
	var/range_high = GLOB.max_explosion_range *0.5
	var/range_low = GLOB.max_explosion_range

	message_admins(span_danger("[key_name_admin(holder())] changed the bomb cap to [range_dev], [range_high], [range_low]"))
	log_admin("[key_name_admin(holder())] changed the bomb cap to [GLOB.max_explosion_range]")
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_alter_narsie(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	var/choice = A.step_value("a15")
	if(choice == "CultStation13")
		log_and_message_admins("has set narsie's behaviour to \"CultStation13\".", holder())
		GLOB.narsie_behaviour = choice
	if(choice == "Nar-Singulo")
		log_and_message_admins("has set narsie's behaviour to \"Nar-Singulo\".", holder())
		GLOB.narsie_behaviour = choice
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_remove_all_clothing(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	for(var/obj/item/clothing/O in world)
		spent(O)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_remove_internal_clothing(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	for(var/obj/item/clothing/under/O in world)
		spent(O)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_send_strike_team(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	holder().strike_team()

	// buttons that are fun for exactly you and nobody else.
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_corgie(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	for(var/mob/living/carbon/human/H in REGISTRY_MEMBERS(REGISTRY_MOBS))
		after(H, 0, TYPE_PROC_REF(/mob/living/carbon/human, corgize))
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_monkey(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	if(!is_funmin)
		return
	message_admins("[key_name_admin(holder())] made everyone into monkeys.")
	log_admin("[key_name_admin(holder())] made everyone into monkeys.")
	for(var/i in REGISTRY_MEMBERS(REGISTRY_MOBS))
		var/mob/living/carbon/human/H = i
		H.monkeyize()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_supermatter_cascade(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	var/choice = A.step_value("a16")
	if(choice == "NO TIME TO EXPLAIN")
		explosion(get_turf(holder().mob), 8, 16, 24, 32, 1)
		SSturf_cascade.start_cascade(get_turf(holder().mob), /turf/unsimulated/wall/supermatter)
		SetUniversalState(/datum/universal_state/supermatter_cascade)
		message_admins("[key_name_admin(holder())] has managed to destroy the universe with a supermatter cascade. Good job, [key_name_admin(holder())]")
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

/datum/secrets_menu/proc/ui_act_summon_narsie(datum/act/op/A)
	var/action = A.window_action()
	if(!ui_gate(A))
		return FALSE
	var/choice = A.step_value("a17")
	if(choice == "PRAISE SATAN")
		new /obj/singularity/narsie/large(get_turf(holder()))
		log_and_message_admins("has summoned Nar-Sie and brought about a new realm of suffering.", holder())
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")
#undef HIGHLANDER_DELAY_TEXT

/proc/chilling_wind_relight(area/A)
	A.set_channels(A.power_equip, TRUE, A.power_environ)

/proc/chilling_wind_stops(list/affected_mobs)
	for(var/mob/M in affected_mobs)
		M.show_message(span_notice("The chilling wind suddenly stops..."), 1)

/// Client of whoever is using this datum (a relation view: null once that is deleted).
/datum/secrets_menu/proc/holder() as /client
	return holder

// The questions' computed fields (asks()).
/datum/secrets_menu/proc/ui_act_jump_shuttle_a3_choices(datum/act/op/A)
	return return_areas()

/datum/secrets_menu/proc/ui_act_jump_shuttle_a4_choices(datum/act/op/A)
	return return_areas()

/datum/secrets_menu/proc/ui_act_jump_shuttle_a6_choices(datum/act/op/A)
	return return_areas()

/datum/secrets_menu/proc/ui_act_launch_shuttle_forced_a8_choices(datum/act/op/A)
	var/list/valid_shuttles = list()
	var/datum/system/shuttles/service = SSshuttles
	for(var/shuttle_tag in service.shuttles)
		if(istype(service.shuttles[shuttle_tag], /datum/shuttle/autodock))
			valid_shuttles += shuttle_tag
	return valid_shuttles

/datum/secrets_menu/proc/ui_act_launch_shuttle_a9_choices(datum/act/op/A)
	var/list/valid_shuttles = list()
	var/datum/system/shuttles/service = SSshuttles
	for(var/shuttle_tag in service.shuttles)
		if(istype(service.shuttles[shuttle_tag], /datum/shuttle/autodock))
			valid_shuttles += shuttle_tag
	return valid_shuttles

/datum/secrets_menu/proc/ui_act_move_shuttle_a11_choices(datum/act/op/A)
	var/datum/system/shuttles/service = SSshuttles
	return service.shuttles

/datum/secrets_menu/proc/ui_act_move_shuttle_a12_choices(datum/act/op/A)
	var/datum/system/shuttles/service = SSshuttles
	return service.registered_shuttle_landmarks



/// The transition questions open only for a jump that has a transition area.
/datum/secrets_menu/proc/jump_has_transition(datum/act/op/A)
	return A.step_value("a5") == "Yes"
