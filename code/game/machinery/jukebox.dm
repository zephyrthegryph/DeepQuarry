//
// Media Player Jukebox
// Rewritten by Leshana from existing Polaris code, merging in D2K5 and N3X15 work
//

/obj/machinery/media/jukebox
	name = "space jukebox"
	desc = "Filled with songs both past and present!"
	icon = 'icons/obj/jukebox.dmi'
	icon_state = "jukebox-nopower"
	var/state_base = "jukebox"
	anchored = TRUE
	density = TRUE
	power_channel = EQUIP
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 100
	circuit = /obj/item/circuitboard/jukebox
	clicksound = SFX_MACHINES_BUTTONBEEP
	volume = 0.5
	maintenance_flags = MACHINE_MAINT_STANDARD

	// Vars for hacking
	var/hacked = 0 // Whether to show the hidden songs or not
	var/freq = 0 // Currently no effect, will return in phase II of mediamanager.
	var/loop_mode = JUKEMODE_PLAY_ONCE			// Behavior when finished playing a song
	// ALLOW(object_keyed_lists): paired remotes add and remove themselves (juke_remote pair/unpair)
	var/list/obj/item/juke_remote/remotes
	var/current_track_handle

/obj/machinery/media/jukebox/Initialize(mapload)
	. = ..()
	default_apply_parts()
	wires = new/datum/wires/jukebox(src)
	update_icon()
	if(!LAZYLEN(getTracksList()))
		stat_add(BROKEN)
	make_climbable()

/obj/machinery/media/jukebox/proc/getTracksList()
	return hacked ? SSmedia_tracks.all_tracks : SSmedia_tracks.jukebox_tracks

/obj/machinery/media/jukebox/machine_step()
	if(!playing)
		return PROCESS_KILL
	if(!operable())
		disconnect_media_source()
		playing = 0
		return PROCESS_KILL
	// If the current track isn't finished playing, let it keep going
	if(current_track() && ELAPSED(src, media_start_time, CLOCK_WORLD) < current_track().duration)
		return
	// Oh... nothing in queue? Well then pick next according to our rules
	var/list/tracks = getTracksList()
	switch(loop_mode)
		if(JUKEMODE_NEXT)
			var/curTrackIndex = max(1, tracks.Find(current_track()))
			var/newTrackIndex = (curTrackIndex % tracks.len) + 1  // Loop back around if past end
			current_track_handle = om_handle(tracks[newTrackIndex])
		if(JUKEMODE_RANDOM)
			var/previous_track = current_track()
			do
				current_track_handle = om_handle(pick(tracks))
			while(current_track() == previous_track && tracks.len > 1)
		if(JUKEMODE_REPEAT_SONG)
			current_track_handle = om_handle(current_track())
		if(JUKEMODE_PLAY_ONCE)
			current_track_handle = null
			playing = 0
			update_icon()
	start_stop_song()
	if(!playing)
		return PROCESS_KILL

// Tells the media manager to start or stop playing based on current settings.
/obj/machinery/media/jukebox/proc/start_stop_song()
	if(current_track() && playing)
		media_url = current_track().url
		EXPIRY_STAMP(src, media_start_time, CLOCK_WORLD)
		audible_message(span_notice("\The [src] begins to play [current_track().display()]."), runemessage = "[current_track().display()]")
	else
		media_url = ""
		media_start_time = 0
	update_music()
	for(var/obj/item/juke_remote/remote as anything in remotes)
		remote.update_music()

/obj/machinery/media/jukebox/proc/set_hacked(newhacked)
	if(hacked == newhacked)
		return
	hacked = newhacked

/obj/machinery/media/jukebox/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/jukebox_fingerprint,
		/datum/interaction/machine_hand/ungated/jukebox_interact,
	)
	..()

/// The old attackby: fingerprinted, then fell through to ..().
/datum/interaction/machine_item/jukebox_fingerprint
	id = "jukebox_fingerprint"
	name = "Use"
	held_type = /obj/item
	effect = /atom/proc/interaction_fingerprint

/obj/machinery/media/jukebox/wirecutter_act(mob/user, obj/item/tool)
	wires.Interact(user)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/media/jukebox/multitool_act(mob/user, obj/item/tool)
	wires.Interact(user)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/media/jukebox/wrench_act(mob/user, obj/item/tool)
	if(playing)
		StopPlaying()
	user.visible_message(span_warning("[user] has [anchored ? "un" : ""]secured \the [src]."), span_notice("You [anchored ? "un" : ""]secure \the [src]."))
	set_anchored(!anchored)
	playsound(src, tool.usesound, 50, TRUE)
	power_change()
	update_icon()
	if(!anchored)
		playing = FALSE
		disconnect_media_source()
	else
		update_media_source()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/media/jukebox/power_change()
	if(!powered(power_channel) || !anchored)
		stat_add(NOPOWER)
	else
		stat_remove(NOPOWER)

	if(!operable() && playing)
		StopPlaying()
	update_icon()

/obj/machinery/media/jukebox/update_icon()
	cut_overlays()
	if(!operable() || !anchored)
		if(has_stat(BROKEN))
			icon_state = "[state_base]-broken"
		else
			icon_state = "[state_base]-nopower"
		return
	icon_state = state_base
	if(playing)
		if(emagged)
			add_overlay("[state_base]-emagged")
		else
			add_overlay("[state_base]-running")
	if (panel_open)
		add_overlay("panel_open")

/obj/machinery/media/jukebox/interact(mob/user)
	if(!operable())
		to_chat(user, "\The [src] doesn't appear to function.")
		return
	tgui_interact(user)

/obj/machinery/media/jukebox/tgui_status(mob/user)
	if(!operable())
		to_chat(user, span_warning("[src] doesn't appear to function."))
		return STATUS_CLOSE
	if(!anchored)
		to_chat(user, span_warning("You must secure [src] first."))
		return STATUS_CLOSE
	. = ..()

/obj/machinery/media/jukebox/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Jukebox", "RetroBox - Space Style")
		ui.open()

/obj/machinery/media/jukebox/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	data["playing"] = playing
	data["loop_mode"] = loop_mode
	data["volume"] = volume
	data["current_track_ref"] = null
	data["current_track"] = null
	data["current_genre"] = null
	if(current_track())
		data["current_track_ref"] = "\ref[current_track()]"  // Convenient shortcut
		data["current_track"] = current_track().toTguiList()
		data["current_genre"] = current_track().genre
	data["percent"] = playing ? min(100, round(world.time - media_start_time) / current_track().duration) : 0;

	var/list/tgui_tracks = list()
	for(var/datum/track/T in getTracksList())
		tgui_tracks.Add(list(T.toTguiList()))
	data["tracks"] = tgui_tracks
	data["admin"] = is_admin(user)

	return data

/obj/machinery/media/jukebox/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	switch(action)
		if("change_track")
			var/datum/track/T = locate_in_list(getTracksList(), params["change_track"])
			if(istype(T))
				current_track_handle = om_handle(T)
				StartPlaying()
			return TRUE
		if("loopmode")
			var/newval = text2num(params["loopmode"])
			loop_mode = sanitize_inlist(newval, list(JUKEMODE_NEXT, JUKEMODE_RANDOM, JUKEMODE_REPEAT_SONG, JUKEMODE_PLAY_ONCE), loop_mode)
			return TRUE
		if("volume")
			var/newval = text2num(params["val"])
			volume = clamp(newval, 0, 1)
			update_music() // To broadcast volume change without restarting song
			return TRUE
		if("stop")
			StopPlaying()
			return TRUE
		if("play")
			if(emagged)
				play_sfx(src, SFX_ITEMS_AIRHORN)
				for(var/mob/living/carbon/M in ohearers(6, src))
					if(M.get_ear_protection() >= 2)
						continue
					M.status_set(EFFECT_SLEEPING, 0)
					M.status_adjust(EFFECT_STUTTERING, 20)
					M.status_adjust(EFFECT_DEAFENED, 30)
					M.deaf_loop.start() // Ear Ringing/Deafness
					M.status_at_least(EFFECT_WEAKENED, 3)
					if(prob(30))
						M.status_at_least(EFFECT_STUNNED, 10)
						M.status_at_least(EFFECT_PARALYZED, 4)
					else
						M.status_adjust(EFFECT_JITTERY, 500)
				om_after_unique(src, 1.5 SECONDS, PROC_REF(explode))
			else if(current_track() == null)
				to_chat(ui.user, "No track selected.")
			else
				StartPlaying()
			return TRUE
		if("add_new_track")
			SSmedia_tracks.add_track(ui.user, params["url"], params["title"], text2num(params["duration"]) * 10, params["artist"], params["genre"], text2num(params["secret"]), text2num(params["lobby"]))
		if("remove_new_track")
			var/datum/track/track_to_remove = locate_in_list(getTracksList(), params["ref"])
			if(track_to_remove == current_track() && playing)
				StopPlaying()
			SSmedia_tracks.remove_track(ui.user, track_to_remove)

/// The old attack_hand: never called ..(), just interacted.
/datum/interaction/machine_hand/ungated/jukebox_interact
	id = "jukebox_interact"
	name = "Use"
	effect = /atom/proc/interaction_interact

/obj/machinery/media/jukebox/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/machinery/media/jukebox/proc/explode()
	walk_to(src,0)
	src.visible_message(span_danger("\The [src] blows apart!"), 1)

	explosion(src.loc, 0, 0, 1, rand(1,2), 1)

	fx_sparks(src, 3)

	replace_with(src, /obj/effect/decal/cleanable/blood/oil)

/obj/machinery/media/jukebox/emag_act(remaining_charges, mob/user)
	if(!emagged)
		set_emagged(1)
		StopPlaying()
		visible_message(span_danger("\The [src] makes a fizzling sound."))
		update_icon()
		return 1

/obj/machinery/media/jukebox/proc/StopPlaying()
	playing = 0
	MACHINE_SLEEP(src)
	set_use_power(USE_POWER_IDLE)
	update_icon()
	start_stop_song()

/obj/machinery/media/jukebox/proc/StartPlaying()
	if(!current_track())
		return
	playing = 1
	MACHINE_WAKE(src)
	set_use_power(USE_POWER_ACTIVE)
	update_icon()
	start_stop_song()

// Advance to the next track - Don't start playing it unless we were already playing
/obj/machinery/media/jukebox/proc/NextTrack()
	var/list/tracks = getTracksList()
	if(!tracks.len) return
	var/curTrackIndex = max(1, tracks.Find(current_track()))
	var/newTrackIndex = (curTrackIndex % tracks.len) + 1  // Loop back around if past end
	current_track_handle = om_handle(tracks[newTrackIndex])
	if(playing)
		start_stop_song()

// Advance to the next track - Don't start playing it unless we were already playing
/obj/machinery/media/jukebox/proc/PrevTrack()
	var/list/tracks = getTracksList()
	if(!tracks.len) return
	var/curTrackIndex = max(1, tracks.Find(current_track()))
	var/newTrackIndex = curTrackIndex == 1 ? tracks.len : curTrackIndex - 1
	current_track_handle = om_handle(tracks[newTrackIndex])
	if(playing)
		start_stop_song()

//Pre-hacked Jukebox, has the full sond list unlocked
/obj/machinery/media/jukebox/hacked
	name = "DRM free space jukebox"
	desc = "Filled with songs both past and present! Unlocked for your convenience!"
	hacked = 1

// Ghostly jukebox for adminbuse
/obj/machinery/media/jukebox/ghost
	silicon_use = NONE // silicons can't use it
	name = "ghost jukebox"
	desc = "A jukebox from the nether-realms! Spooky."

	plane = PLANE_GHOSTS
	invisibility = INVISIBILITY_OBSERVER
	alpha = 127

	icon_state = "jukebox2-virtual"

	density = FALSE
	hacked = TRUE

	use_power = USE_POWER_OFF
	circuit = null

	var/list/custom_tracks

// Just junk to make it sneaky - I wish a lot more stuff was on /obj/machinery/media instead of /jukebox so I could use that.
/obj/machinery/media/jukebox/ghost/is_incorporeal()
	return TRUE
/obj/machinery/media/jukebox/ghost/audible_message(message, deaf_message, hearing_distance, radio_message, runemessage)
	return
/obj/machinery/media/jukebox/ghost/visible_message(message, blind_message, list/exclude_mobs, range, runemessage)
	return
/// Untouchable: no interactions at all (the old attackby/attack_hand returned); only ghosts use it.
/obj/machinery/media/jukebox/ghost/declare_interactions(list/into)
	into += dq_interaction_from_spec(type, INTERACT_OBSERVER("Use", PROC_REF(ghost_jukebox_observer_use)))
/obj/machinery/media/jukebox/ghost/set_use_power(new_use_power)
	return
/obj/machinery/media/jukebox/ghost/power_change()
	return
/obj/machinery/media/jukebox/ghost/emp_act(severity, recursive)
	return ..()
/obj/machinery/media/jukebox/ghost/emag_act(remaining_charges, mob/user)
	return
/obj/machinery/media/jukebox/ghost/explode()
	return
/obj/machinery/media/jukebox/ghost/update_icon()
	if(playing)
		animate(src, alpha = 200, time = 5, loop = -1)
	else
		animate(src, alpha = initial(alpha), time = 10)
// End junk

/// Old attack_ghost: staff get the controls, other ghosts hear what's playing.
/obj/machinery/media/jukebox/ghost/proc/ghost_jukebox_observer_use(mob/observer/dead/M, obj/item/held, datum/interaction/interaction)
	if(!istype(M))
		return TRUE

	if(check_rights(R_FUN|R_ADMIN, show_msg=0))
		interact(M)
	else if(current_track())
		to_chat(M, "\The [src] is playing [current_track().display()].")
	else
		to_chat(M, "\The [src] is not playing any music.")
	return TRUE

/obj/machinery/media/jukebox/ghost/getTracksList()
	return (custom_tracks + ..())

/obj/machinery/media/jukebox/ghost/proc/manual_track_add()
	if(!check_rights(R_FUN|R_ADMIN))
		return

	om_flow_start(/datum/om/flow/jukebox_track_add, usr, src)

/// An admin adds a custom track: url, title, duration, then an optional artist.
/datum/om/flow/jukebox_track_add
	name = "jukebox track add"
	var/url
	var/title
	var/duration

/datum/om/flow/jukebox_track_add/start()
	om_ask(actor, /datum/om/prompt/text, PROC_REF(url_entered), title = "Track URL", message = "REQUIRED: Provide URL for track", requires = PROMPT_ADMIN(R_FUN|R_ADMIN))

/datum/om/flow/jukebox_track_add/proc/url_entered(datum/om/prompt/text/ask)
	url = ask.text
	if(!url)
		return
	om_ask(actor, /datum/om/prompt/text, PROC_REF(title_entered), title = "Track Title", message = "REQUIRED: Provide title for track", requires = PROMPT_ADMIN(R_FUN|R_ADMIN))

/datum/om/flow/jukebox_track_add/proc/title_entered(datum/om/prompt/text/ask)
	title = ask.text
	if(!title)
		return
	om_ask(actor, /datum/om/prompt/number, PROC_REF(duration_entered), title = "Track Duration", message = "REQUIRED: Provide duration for track (in deciseconds, aka seconds*10)", requires = PROMPT_ADMIN(R_FUN|R_ADMIN))

/datum/om/flow/jukebox_track_add/proc/duration_entered(datum/om/prompt/number/ask)
	duration = ask.number
	if(!duration)
		return
	om_ask(actor, /datum/om/prompt/text, PROC_REF(artist_entered), title = "Track Artist", message = "Optional: Provide artist for track", cancel_answer = "", requires = PROMPT_ADMIN(R_FUN|R_ADMIN))

/datum/om/flow/jukebox_track_add/proc/artist_entered(datum/om/prompt/text/ask)
	var/obj/machinery/media/jukebox/ghost/jukebox = target
	// So they're obvious and grouped
	var/genre = "! Admin Loaded !"
	LAZYADD(jukebox.custom_tracks, new /datum/track(url, title, duration, ask.text, genre))

/obj/machinery/media/jukebox/ghost/proc/manual_track_remove()
	if(!check_rights(R_FUN|R_ADMIN))
		return

	om_ask(usr, /datum/om/prompt/text, PROC_REF(manual_track_removal_entered), message = "Input track title or URL to remove (must be exact)", title = "Remove Track", requires = PROMPT_ADMIN(R_FUN|R_ADMIN))

/obj/machinery/media/jukebox/ghost/proc/manual_track_removal_entered(datum/om/prompt/text/ask)
	var/mob/user = ask.answerer
	var/track = ask.text
	var/client/C = user.client
	if(!track)
		return

	for(var/datum/track/T in custom_tracks)
		if(T.title == track || T.url == track)
			LAZYREMOVE(custom_tracks, T)
			qdel(T)
			return

	to_chat(C, span_warning("Couldn't find a track matching the specified parameters."))

/obj/machinery/media/jukebox/ghost/vv_get_dropdown()
	. = ..()
	VV_DROPDOWN_OPTION("", "---")
	VV_DROPDOWN_OPTION("add_track", "Add New Track")
	VV_DROPDOWN_OPTION("remove_track", "Remove Track")

/obj/machinery/media/jukebox/ghost/vv_do_topic(list/href_list)
	. = ..()
	IF_VV_OPTION("add_track")
		manual_track_add()
		href_list[VV_HK_DATUM_REFRESH] = "\ref[src]"
	IF_VV_OPTION("remove_track")
		manual_track_remove()
		href_list[VV_HK_DATUM_REFRESH] = "\ref[src]"

/obj/machinery/media/jukebox/casinojukebox
	name = "space casino jukebox"
	desc = "A jukebox to play the tracks on the golden goose, jazzy~"
	icon = 'icons/obj/casino_ch.dmi'
	icon_state = "casinojukebox-nopower"
	state_base = "casinojukebox"

	use_power = USE_POWER_OFF

/obj/machinery/media/jukebox/casinojukebox/getTracksList()
	return SSmedia_tracks.casino_tracks

/// Its declared start condition (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/media/jukebox/step_start_condition()
	return playing

/// LC-refs: current track -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/media/jukebox/proc/current_track() as /datum/track
	return om_resolve(current_track_handle)

DECLARE_REF(/obj/machinery/media/jukebox, "remotes", HELD, null)
