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
				if( (M.lastKnownIP == source.client.address) )
					matches += "IP ([source.client.address])"
				if( (source.client.connection != "web") && (M.computer_id == source.client.computer_id) )
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

/mob/Login()
	if(!client)
		return FALSE

	client.persistent_client.set_mob(src)

	registry_join(REGISTRY_PLAYERS, src)
	lastKnownIP	= client.address
	computer_id	= client.computer_id
	log_access("Mob Login: [key_name(src)] was assigned to a [type] ([tag])")
	update_Login_details(src)
	world.update_status()

	client.images = null				//remove the images such as AIs being unable to see runes
	client.screen = list()				//remove hud items just in case
	if(hud_used)
		rel_clear(src, nameof(hud_used)) // remove the owned HUD objects
	new /datum/hud(src)

	next_move = 1
	disconnect_time = null // ition: clear the disconnect time
	sight |= SEE_SELF
	..()
	verb_store_login(src) // DECLARE_LOGIN_VERB (code/datums/om/grant_verbs.dm)
	PUBLISH_LEGACY(src, /datum/notice/mob_login)

	client.perspective = MOB_PERSPECTIVE
	client.eye = src

	add_click_catcher()
	update_client_color()

	if(!plane_holder) //Lazy
		rel_set(src, nameof(plane_holder), new /datum/plane_holder(src)) //Not a location, it takes it and saves it.
	if(!vis_enabled)
		vis_enabled = list()
	client.screen += plane_holder.plane_masters
	if(GLOB.global_vantag_hud)
		vantag_hud = TRUE
	recalculate_vis()

	// AO support
	var/ao_enabled = client.prefs?.read_preference(/datum/preference/toggle/ambient_occlusion)
	plane_holder.set_ao(VIS_OBJS, ao_enabled)
	plane_holder.set_ao(VIS_MOBS, ao_enabled)

	// Status indicators
	var/status_enabled = client.prefs?.read_preference(/datum/preference/toggle/status_indicators)
	plane_holder.set_vis(VIS_STATUS, status_enabled)

	// Write this mob's keybinding profile (default or cyborg) into the skin's macro set.
	client.apply_keybindings()

	if(!client.tooltips)
		client.tooltips = new(client)

	var/turf/T = get_turf(src)
	if(isturf(T))
		update_client_z(T.z)

	if(dq_get_cloaked(src) && dq_get_cloaked_selfimage(src))
		client.images += dq_get_cloaked_selfimage(src)

	if(client)
		for(var/datum/action/A as anything in persistent_client.player_actions)
			A.Grant(src)

		for(var/datum/callback/CB as anything in persistent_client.post_login_callbacks)
			CB.Invoke()

	log_mob_tag(src, "TAG: [tag] NEW OWNER: [key_name(src)]")
	PUBLISH_LEGACY(src, /datum/notice/mob_client_login, client)
	client.init_verbs()

	set_listening(LISTENING_PLAYER)
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
