//handles setting lastKnownIP and computer_id for use by the ban systems as well as checking for multikeying
/proc/update_Login_details(mob/source)
	//Multikey checks and logging
	if(CONFIG_GET(flag/log_access))
		for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
			if(M == source)	continue
			if( M.key && (M.key != source.key) )
				var/matches
				// IP exemptions for those who are known to live together
				var/list/ip_whitelist = CONFIG_GET(str_list/ip_whitelist)
				if (ip_whitelist[source.key])
					if (ip_whitelist[source.key] == ip_whitelist[M.key])
						continue
				// end
				if( (STATE_GET(M, connection, lastKnownIP) == source.client.address) )
					matches += "IP ([source.client.address])"
				if( (source.client.connection != "web") && (STATE_GET(M, connection, computer_id) == source.client.computer_id) )
					if(matches)	matches += " and "
					matches += "ID ([source.client.computer_id])"
					if(!CONFIG_GET(flag/disable_cid_warn_popup))
						tgui_alert_async(source, "You appear to have logged in with another key this round, which is not permitted. Please contact an administrator if you believe this message to be in error.")
				if(matches)
					if(M.client)
						message_admins("[span_red(span_bold("Notice:"))] [span_blue("[key_name_admin(source)] has the same [matches] as [key_name_admin(M)].")]", 1)
						log_admin_private("Notice: [key_name(source)] has the same [matches] as [key_name(M)].")
					else
						message_admins("[span_red(span_bold("Notice:"))] [span_blue("[key_name_admin(source)] has the same [matches] as [key_name_admin(M)] (no longer logged in). ")]", 1)
						log_admin_private("Notice: [key_name(source)] has the same [matches] as [key_name(M)] (no longer logged in).")

/// Sent when a mob/login() finishes: (client)
ACTION(mob_client_login, client, FIXED, notice = /datum/notice/mob_client_login)

/// From base of /mob/Login(): ()
ACTION(mob_login, FIXED, notice = /datum/notice/mob_login)

/mob/Login()
	if(!client)
		return FALSE

	// JOIN_TIMING_LOGIN: what each step of a login costs (playtest 2026-11-08: bind_player, which is this, took 6 s of a round-start join).
	var/list/login_ms = list()
	var/login_started = TICK_USAGE_REAL
	var/login_step = TICK_USAGE_REAL
	mob_state_set_played(TRUE)
	client.persistent_client.set_mob(src)

	registry_join(REGISTRY_PLAYERS, src)
	STATE_SET(src, connection, lastKnownIP, client.address)
	STATE_SET(src, connection, computer_id, client.computer_id)
	log_access("Mob Login: [key_name(src)] was assigned to a [type] ([tag])")
	update_Login_details(src)
	world.update_status()
	login_ms["access, registry, status"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - login_step)
	login_step = TICK_USAGE_REAL

	client_images_clear(client)				//remove the images such as AIs being unable to see runes
	client_screen_clear(client)				//remove hud items just in case
	if(hud_used)
		rel_clear(src, nameof(hud_used)) // remove the owned HUD objects
	new /datum/hud(src)
	login_ms["hud"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - login_step)
	login_step = TICK_USAGE_REAL

	STATE_SET(src, cooldowns, next_move, 1)
	STATE_SET(src, connection, disconnect_time, null) // ition: clear the disconnect time
	sight |= SEE_SELF|SEE_BLACKNESS
	..()
	login_ms["native login"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - login_step)
	login_step = TICK_USAGE_REAL
	verb_store_login(src) // DECLARE_LOGIN_VERB (code/engine/grant_verbs.dm)
	login_ms["login verbs"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - login_step)
	login_step = TICK_USAGE_REAL
	PUBLISH(src, mob_login)
	login_ms["mob_login notice"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - login_step)
	login_step = TICK_USAGE_REAL
	ckey_changed()

	client.perspective = MOB_PERSPECTIVE
	client.eye = src

	add_click_catcher()
	update_client_color()

	// The plane masters live on the hud built above; recalculate_vis() rebuilds what this mob sees through them.
	var/datum/hud/hud = hud_used
	var/datum/plane_holder/plane_holder = new /datum/plane_holder(src) //Not a location, it takes it and saves it.
	rel_set(hud, nameof(hud.plane_holder), plane_holder)
	hud.vis_enabled = list()
	client_screen_add(client, plane_holder.plane_masters)
	if(GLOB.global_vantag_hud)
		STATE_SET(src, mob_misc, vantag_hud, TRUE)
	recalculate_vis()
	login_ms["eye, click catcher, colour, planes, vis"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - login_step)
	login_step = TICK_USAGE_REAL

	// AO support
	var/ao_enabled = client.prefs?.read_preference(/datum/preference/toggle/ambient_occlusion)
	plane_holder.set_ao(VIS_OBJS, ao_enabled)
	plane_holder.set_ao(VIS_MOBS, ao_enabled)

	// Status indicators
	var/status_enabled = TRUE
	plane_holder.set_vis(VIS_STATUS, status_enabled)

	// Write this mob's keybinding profile (default or cyborg) into the skin's macro set.
	client.apply_keybindings()
	login_ms["ao, status, keybindings"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - login_step)
	login_step = TICK_USAGE_REAL


	var/turf/T = get_turf(src)
	if(isturf(T))
		update_client_z(T.z)
	login_ms["client z"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - login_step)
	login_step = TICK_USAGE_REAL
	SSproximity.eye_update(client)
	login_ms["proximity eye"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - login_step)
	login_step = TICK_USAGE_REAL

	if(dq_get_cloaked(src) && dq_get_cloaked_selfimage(src))
		client_images_add(client, dq_get_cloaked_selfimage(src))

	if(client)
		for(var/datum/action/A as anything in persistent_client.player_actions)
			A.Grant(src)
		login_ms["player actions"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - login_step)
		login_step = TICK_USAGE_REAL
		sync_op_abilities()
		abilities_changed()
		login_ms["abilities"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - login_step)
		login_step = TICK_USAGE_REAL

		for(var/datum/callback/CB as anything in persistent_client.post_login_callbacks)
			CB.Invoke()
	login_ms["post-login callbacks"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - login_step)
	login_step = TICK_USAGE_REAL

	log_mob_tag(src, "TAG: [tag] NEW OWNER: [key_name(src)]")
	PUBLISH(src, mob_client_login, client = client)
	login_ms["mob_client_login notice"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - login_step)
	login_step = TICK_USAGE_REAL
	client.init_verbs()
	login_ms["client verbs"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - login_step)
	login_step = TICK_USAGE_REAL

	set_recursive_listening(LISTENING_PLAYER)
	GLOB.tickets.ClientLogin(client, TRUE)

	if(GLOB.custom_event_msg && GLOB.custom_event_msg != "")
		to_chat(src, "<h1 class='alert'>Custom Event</h1>")
		to_chat(src, "<h2 class='alert'>A custom event is taking place. OOC Info:</h2>")
		to_chat(src, span_alert("[GLOB.custom_event_msg]") + "\n")

	// viewing_alternate_appearances is /atom/var/alt_appearances_viewing
	var/list/viewing = dq_get_viewing_alt_appearances(src)
	if(viewing && viewing.len)
		for(var/datum/alternate_appearance/AA in viewing)
			AA.display_to(list(src))

	var/atom/movable/screen/plane_master/augmented/aug = plane_holder.plane_masters[VIS_AUGMENTED]
	aug.apply()
	login_ms["listening, tickets, event, alt appearances, augmented"] = TICK_DELTA_TO_MS(TICK_USAGE_REAL - login_step)
	var/list/login_steps = list()
	for(var/step_name in login_ms)
		login_steps += "[step_name] [round(login_ms[step_name], 0.1)] ms"
	log_world("JOIN_TIMING_LOGIN: [key_name(src)] ([type]): whole [round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - login_started), 0.1)] ms, [jointext(login_steps, ", ")]")
