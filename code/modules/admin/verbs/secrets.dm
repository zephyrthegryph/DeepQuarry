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

	is_debugger = check_rights(R_DEBUG)
	is_funmin = check_rights(R_FUN)

DECLARE_UI_STATE(/datum/secrets_menu, ADMIN_STATE(R_HOLDER))

/datum/secrets_menu/tgui_close()
	spent(src)

DECLARE_UI(/datum/secrets_menu, "Secrets")

UI_DATA_REPLACE(/datum/secrets_menu, "is_debugger:num", "is_funmin:num")

#define HIGHLANDER_DELAY_TEXT "40 seconds (crush the hope of a normal shift)"
/datum/secrets_menu/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if((action != "admin_log" && action != "show_admins") && !check_rights(R_ADMIN))
		return FALSE
	return TRUE

UI_ACT(/datum/secrets_menu, "admin_log", ui_act_admin_log)
UI_ACT_PROC(/datum/secrets_menu, ui_act_admin_log)
	// structured TGUI AdminReport.
	if(!GLOB.admin_log.len)
		dq_admin_report_html(holder(), "Admin Logs", "No-one has done anything this round!")
	else
		dq_admin_report_lines(holder(), "Admin Logs", GLOB.admin_log)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "dialog_log", ui_act_dialog_log)
UI_ACT_PROC(/datum/secrets_menu, ui_act_dialog_log)
	SSadmin_verbs.dynamic_invoke_verb(ui.user, /datum/admin_verb/persistent_client_logs)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "show_admins", ui_act_show_admins)
UI_ACT_PROC(/datum/secrets_menu, ui_act_show_admins)
	// structured TGUI AdminReport with typed table.
	if(GLOB.admin_datums)
		var/list/rows = list()
		for(var/ckey in GLOB.admin_datums)
			var/datum/admins/D = GLOB.admin_datums[ckey]
			rows += list(list("[ckey]", D.rank_names()))
		dq_admin_report_table(holder(), "Current admins", list("Ckey", "Rank"), rows)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "show_traitors_and_objectives", ui_act_show_traitors_and_objectives)
UI_ACT_PROC(/datum/secrets_menu, ui_act_show_traitors_and_objectives)
	holder().admin_datum().check_antagonists(ui.user.client)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "show_game_mode", ui_act_show_game_mode)
UI_ACT_PROC(/datum/secrets_menu, ui_act_show_game_mode)
	if (SSticker.mode) tgui_alert_async(holder(), "The game mode is [SSticker.mode.name]")
	else tgui_alert_async(holder(), "For some reason there's a ticker, but not a game mode")

//Buttons for debug.
//tbd

//Buttons for helpful stuff. This is where people land in the tgui
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "list_bombers", ui_act_list_bombers)
UI_ACT_PROC(/datum/secrets_menu, ui_act_list_bombers)
	holder().admin_datum().list_bombers(user)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "list_signalers", ui_act_list_signalers)
UI_ACT_PROC(/datum/secrets_menu, ui_act_list_signalers)
	holder().admin_datum().list_signalers(user)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "list_lawchanges", ui_act_list_lawchanges)
UI_ACT_PROC(/datum/secrets_menu, ui_act_list_lawchanges)
	holder().admin_datum().list_law_changes(user)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "showailaws", ui_act_showailaws)
UI_ACT_PROC(/datum/secrets_menu, ui_act_showailaws)
	holder().admin_datum().list_law_changes(user)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "manifest", ui_act_manifest)
UI_ACT_PROC(/datum/secrets_menu, ui_act_manifest)
	holder().admin_datum().show_manifest(user)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "dna", ui_act_dna)
UI_ACT_PROC(/datum/secrets_menu, ui_act_dna)
	holder().admin_datum().list_dna(user)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "fingerprints", ui_act_fingerprints)
UI_ACT_PROC(/datum/secrets_menu, ui_act_fingerprints)
	holder().admin_datum().list_fingerprints(user)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "prison_warp", ui_act_prison_warp)
UI_ACT_PROC(/datum/secrets_menu, ui_act_prison_warp)
	for(var/mob/living/carbon/human/H in REGISTRY_MEMBERS(REGISTRY_MOBS))
		var/turf/T = get_turf(H)
		var/security = 0
		if((T in using_map.admin_levels) || registry_has(REGISTRY_PRISONWARPED, H))
		//don't warp them if they aren't ready or are already there
			continue
		H.status_at_least(EFFECT_PARALYZED, 5)
		H.status_at_least(EFFECT_SLEEPING, 5)
		if(H.get_equipped_item(SLOT_ID_ID))
			var/obj/item/card/id/id = H.get_idcard()
			for(var/A in id.GetAccess())
				if(A == ACCESS_SECURITY)
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

UI_ACT(/datum/secrets_menu, "night_shift_set", ui_act_night_shift_set)
UI_ACT_PROC(/datum/secrets_menu, ui_act_night_shift_set)
	var/val = act_ask(holder(), action, params, ui, "a1", /datum/om/prompt/choice/alert, message = "What do you want to set night shift to? This will override the automatic system until set to automatic again.", title = "Night Shift", choices = list("On", "Off", "Automatic"))
	if(isnull(val))
		return
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

UI_ACT(/datum/secrets_menu, "trigger_xenomorph_infestation", ui_act_trigger_xenomorph_infestation)
UI_ACT_PROC(/datum/secrets_menu, ui_act_trigger_xenomorph_infestation)
	GLOB.xenomorphs.attempt_random_spawn()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "trigger_cortical_borer_infestation", ui_act_trigger_cortical_borer_infestation)
UI_ACT_PROC(/datum/secrets_menu, ui_act_trigger_cortical_borer_infestation)
	GLOB.borers.attempt_random_spawn()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "jump_shuttle", ui_act_jump_shuttle)
UI_ACT_PROC(/datum/secrets_menu, ui_act_jump_shuttle)
	var/shuttle_tag = act_ask(holder(), action, params, ui, "a2", /datum/om/prompt/choice, message = "Which shuttle do you want to jump?", title = "Shuttle Choice", choices = SSshuttles.shuttles)
	if(isnull(shuttle_tag))
		return
	if (!shuttle_tag) return

	var/datum/shuttle/S = SSshuttles.shuttles[shuttle_tag]

	var/list/area_choices = return_areas()
	var/origin_area = act_ask(holder(), action, params, ui, "a3", /datum/om/prompt/choice, message = "Which area is the shuttle at now? (MAKE SURE THIS IS CORRECT OR THINGS WILL BREAK)", title = "Area Choice", choices = area_choices)
	if(isnull(origin_area))
		return
	if (!origin_area) return

	var/destination_area = act_ask(holder(), action, params, ui, "a4", /datum/om/prompt/choice, message = "Which area is the shuttle at now? (MAKE SURE THIS IS CORRECT OR THINGS WILL BREAK)", title = "Area Choice", choices = area_choices)
	if(isnull(destination_area))
		return
	if (!destination_area) return

	var/long_jump = act_ask(holder(), action, params, ui, "a5", /datum/om/prompt/choice/alert, message = "Is there a transition area for this jump?", title = "Transition?", choices = list("Yes","No"))
	if(isnull(long_jump))
		return
	if(!long_jump)
		return
	if (long_jump == "Yes")
		var/transition_area = act_ask(holder(), action, params, ui, "a6", /datum/om/prompt/choice, message = "Which area is the transition area? (MAKE SURE THIS IS CORRECT OR THINGS WILL BREAK)", title = "Area Choice", choices = area_choices)
		if(isnull(transition_area))
			return
		if (!transition_area) return

		var/move_duration = act_ask(holder(), action, params, ui, "a7", /datum/om/prompt/number, message = "How many seconds will this jump take?")
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

UI_ACT(/datum/secrets_menu, "launch_shuttle_forced", ui_act_launch_shuttle_forced)
UI_ACT_PROC(/datum/secrets_menu, ui_act_launch_shuttle_forced)
	var/list/valid_shuttles = list()
	for (var/shuttle_tag in SSshuttles.shuttles)
		if (istype(SSshuttles.shuttles[shuttle_tag], /datum/shuttle/autodock))
			valid_shuttles += shuttle_tag

	var/shuttle_tag = act_ask(holder(), action, params, ui, "a8", /datum/om/prompt/choice, message = "Which shuttle's launch do you want to force?", title = "Shuttle Choice", choices = valid_shuttles)
	if(isnull(shuttle_tag))
		return
	if (!shuttle_tag)
		return

	var/datum/shuttle/autodock/S = SSshuttles.shuttles[shuttle_tag]
	if (S.can_force())
		S.force_launch(holder(), user)
		log_and_message_admins("forced the [shuttle_tag] shuttle", holder())
	else
		tgui_alert_async(holder(), "The [shuttle_tag] shuttle launch cannot be forced at this time. It's busy, or hasn't been launched yet.")
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "launch_shuttle", ui_act_launch_shuttle)
UI_ACT_PROC(/datum/secrets_menu, ui_act_launch_shuttle)
	var/list/valid_shuttles = list()
	for (var/shuttle_tag in SSshuttles.shuttles)
		if (istype(SSshuttles.shuttles[shuttle_tag], /datum/shuttle/autodock))
			valid_shuttles += shuttle_tag

	var/shuttle_tag = act_ask(holder(), action, params, ui, "a9", /datum/om/prompt/choice, message = "Which shuttle do you want to launch?", title = "Shuttle Choice", choices = valid_shuttles)
	if(isnull(shuttle_tag))
		return
	if (!shuttle_tag)
		return

	var/datum/shuttle/autodock/S = SSshuttles.shuttles[shuttle_tag]
	if (S.can_launch())
		S.launch(holder(), user)
		log_and_message_admins("launched the [shuttle_tag] shuttle", holder())
	else
		tgui_alert_async(holder(), "The [shuttle_tag] shuttle cannot be launched at this time. It's probably busy.")
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "move_shuttle", ui_act_move_shuttle)
UI_ACT_PROC(/datum/secrets_menu, ui_act_move_shuttle)
	var/confirm = act_ask(holder(), action, params, ui, "a10", /datum/om/prompt/choice/alert, message = "This command directly moves a shuttle from one area to another. DO NOT USE THIS UNLESS YOU ARE DEBUGGING A SHUTTLE AND YOU KNOW WHAT YOU ARE DOING.", title = "Are you sure?", choices = list("Ok", "Cancel"))
	if(isnull(confirm))
		return
	if (confirm != "Ok")
		return

	var/shuttle_tag = act_ask(holder(), action, params, ui, "a11", /datum/om/prompt/choice, message = "Which shuttle do you want to jump?", title = "Shuttle Choice", choices = SSshuttles.shuttles)
	if(isnull(shuttle_tag))
		return
	if (!shuttle_tag) return

	var/datum/shuttle/S = SSshuttles.shuttles[shuttle_tag]

	var/destination_tag = act_ask(holder(), action, params, ui, "a12", /datum/om/prompt/choice, message = "Which landmark do you want to jump to? (IF YOU GET THIS WRONG THINGS WILL BREAK)", title = "Landmark Choice", choices = SSshuttles.registered_shuttle_landmarks)
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

UI_ACT(/datum/secrets_menu, "ghost_mode", ui_act_ghost_mode)
UI_ACT_PROC(/datum/secrets_menu, ui_act_ghost_mode)
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

			var/area/A = get_area(M)
			if(A.requires_power && !A.always_unpowered && A.power_light && (A.z in using_map.player_levels))
				affected_areas |= get_area(M)

	affected_mobs |= holder()
	for(var/area/AffectedArea in affected_areas)
		AffectedArea.power_light = 0
		AffectedArea.power_change()
		after(AffectedArea, rand(2.5 SECONDS, 5 SECONDS), GLOBAL_PROC_REF(chilling_wind_relight), with = list(AffectedArea))

	after(null, 10 SECONDS, GLOBAL_PROC_REF(chilling_wind_stops), with = list(affected_mobs.Copy()))
	affected_mobs.Cut()
	affected_areas.Cut()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "paintball_mode", ui_act_paintball_mode)
UI_ACT_PROC(/datum/secrets_menu, ui_act_paintball_mode)
	for(var/species in GLOB.all_species)
		var/datum/species/S = GLOB.all_species[species]
		dq_set_blood_color(S, "rainbow")
	for(var/obj/effect/decal/cleanable/blood/B in world)
		B.basecolor = "rainbow"
		B.update_icon()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "power", ui_act_power)
UI_ACT_PROC(/datum/secrets_menu, ui_act_power)
	if(!is_funmin)
		return
	log_admin("[key_name(holder())] made all areas powered")
	message_admins(span_adminnotice("[key_name_admin(holder())] made all areas powered"))
	power_restore()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "unpower", ui_act_unpower)
UI_ACT_PROC(/datum/secrets_menu, ui_act_unpower)
	if(!is_funmin)
		return
	log_admin("[key_name(holder())] made all areas unpowered")
	message_admins(span_adminnotice("[key_name_admin(holder())] made all areas unpowered"))
	power_failure()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "quickpower", ui_act_quickpower)
UI_ACT_PROC(/datum/secrets_menu, ui_act_quickpower)
	if(!is_funmin)
		return
	log_admin("[key_name(holder())] made all SMESs powered")
	message_admins(span_adminnotice("[key_name_admin(holder())] made all SMESs powered"))
	power_restore_quick()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "gravity", ui_act_gravity)
UI_ACT_PROC(/datum/secrets_menu, ui_act_gravity)
	GLOB.gravity_is_on = !GLOB.gravity_is_on
	for(var/area/A in world)
		A.gravitychange(GLOB.gravity_is_on)

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

UI_ACT(/datum/secrets_menu, "tripleAI", ui_act_tripleai)
UI_ACT_PROC(/datum/secrets_menu, ui_act_tripleai)
	if(!is_funmin)
		return
	holder().triple_ai()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "onlyone", ui_act_onlyone)
UI_ACT_PROC(/datum/secrets_menu, ui_act_onlyone)
	if(!is_funmin)
		return
	var/response = act_ask(user, action, params, ui, "a13", /datum/om/prompt/choice/alert, message = "Delay by 40 seconds?", title = "There can, in fact, only be one", choices = list("Instant!", HIGHLANDER_DELAY_TEXT))
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

UI_ACT(/datum/secrets_menu, "blackout", ui_act_blackout)
UI_ACT_PROC(/datum/secrets_menu, ui_act_blackout)
	if(!is_funmin)
		return
	message_admins("[key_name_admin(holder())] broke all lights")
	//for(var/obj/machinery/light/L as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/light))
	//	L.break_light_tube()
	//	CHECK_TICK
	lightsout(0,0)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "partial_blackout", ui_act_partial_blackout)
UI_ACT_PROC(/datum/secrets_menu, ui_act_partial_blackout)
	if(!is_funmin)
		return
	message_admins("[key_name_admin(holder())] broke some lights")
	lightsout(1,2)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "whiteout", ui_act_whiteout)
UI_ACT_PROC(/datum/secrets_menu, ui_act_whiteout)
	if(!is_funmin)
		return
	message_admins("[key_name_admin(holder())] fixed all lights")
	for(var/obj/machinery/light/L in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		L.fix()
		CHECK_TICK
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "changebombcap", ui_act_changebombcap)
UI_ACT_PROC(/datum/secrets_menu, ui_act_changebombcap)
	if(!is_funmin)
		return

	var/new_cap = act_ask(holder(), action, params, ui, "a14", /datum/om/prompt/choice, message = "Select the max explosion range", title = "Change Bomb Cap", choices = list(14, 16, 20, 28, 56, 128))
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

UI_ACT(/datum/secrets_menu, "alter_narsie", ui_act_alter_narsie)
UI_ACT_PROC(/datum/secrets_menu, ui_act_alter_narsie)
	var/choice = act_ask(holder(), action, params, ui, "a15", /datum/om/prompt/choice/alert, message = "How do you wish for Nar-Sie to interact with its surroundings?", title = "NarChoice", choices = list("CultStation13", "Nar-Singulo"))
	if(isnull(choice))
		return
	if(choice == "CultStation13")
		log_and_message_admins("has set narsie's behaviour to \"CultStation13\".", holder())
		GLOB.narsie_behaviour = choice
	if(choice == "Nar-Singulo")
		log_and_message_admins("has set narsie's behaviour to \"Nar-Singulo\".", holder())
		GLOB.narsie_behaviour = choice
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "remove_all_clothing", ui_act_remove_all_clothing)
UI_ACT_PROC(/datum/secrets_menu, ui_act_remove_all_clothing)
	for(var/obj/item/clothing/O in world)
		spent(O)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "remove_internal_clothing", ui_act_remove_internal_clothing)
UI_ACT_PROC(/datum/secrets_menu, ui_act_remove_internal_clothing)
	for(var/obj/item/clothing/under/O in world)
		spent(O)
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "send_strike_team", ui_act_send_strike_team)
UI_ACT_PROC(/datum/secrets_menu, ui_act_send_strike_team)
	holder().strike_team()

	// buttons that are fun for exactly you and nobody else.
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "corgie", ui_act_corgie)
UI_ACT_PROC(/datum/secrets_menu, ui_act_corgie)
	for(var/mob/living/carbon/human/H in REGISTRY_MEMBERS(REGISTRY_MOBS))
		after(H, 0, TYPE_PROC_REF(/mob/living/carbon/human, corgize))
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "monkey", ui_act_monkey)
UI_ACT_PROC(/datum/secrets_menu, ui_act_monkey)
	if(!is_funmin)
		return
	message_admins("[key_name_admin(holder())] made everyone into monkeys.")
	log_admin("[key_name_admin(holder())] made everyone into monkeys.")
	for(var/i in REGISTRY_MEMBERS(REGISTRY_MOBS))
		var/mob/living/carbon/human/H = i
		H.monkeyize()
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "supermatter_cascade", ui_act_supermatter_cascade)
UI_ACT_PROC(/datum/secrets_menu, ui_act_supermatter_cascade)
	var/choice = act_ask(holder(), action, params, ui, "a16", /datum/om/prompt/choice/alert, message = "You sure you want to destroy the universe and create a large explosion at your location? Misuse of this could result in removal of flags or hilarity.", title = "WARNING!", choices = list("NO TIME TO EXPLAIN", "Cancel"))
	if(isnull(choice))
		return
	if(choice == "NO TIME TO EXPLAIN")
		explosion(get_turf(holder().mob), 8, 16, 24, 32, 1)
		SSturf_cascade.start_cascade(get_turf(holder().mob), /turf/unsimulated/wall/supermatter)
		SetUniversalState(/datum/universal_state/supermatter_cascade)
		message_admins("[key_name_admin(holder())] has managed to destroy the universe with a supermatter cascade. Good job, [key_name_admin(holder())]")
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")

UI_ACT(/datum/secrets_menu, "summon_narsie", ui_act_summon_narsie)
UI_ACT_PROC(/datum/secrets_menu, ui_act_summon_narsie)
	var/choice = act_ask(holder(), action, params, ui, "a17", /datum/om/prompt/choice/alert, message = "You sure you want to end the round and summon Nar-Sie at your location? Misuse of this could result in removal of flags or hilarity.", title = "WARNING!", choices = list("PRAISE SATAN", "Cancel"))
	if(isnull(choice))
		return
	if(choice == "PRAISE SATAN")
		new /obj/singularity/narsie/large(get_turf(holder()))
		log_and_message_admins("has summoned Nar-Sie and brought about a new realm of suffering.", holder())
	if(holder())
		log_admin("[key_name(holder())] used secret: [action].")
#undef HIGHLANDER_DELAY_TEXT

/proc/chilling_wind_relight(area/A)
	A.power_light = 1
	A.power_change()

/proc/chilling_wind_stops(list/affected_mobs)
	for(var/mob/M in affected_mobs)
		M.show_message(span_notice("The chilling wind suddenly stops..."), 1)

/// Client of whoever is using this datum (a relation view: null once that is deleted).
/datum/secrets_menu/proc/holder() as /client
	return holder
