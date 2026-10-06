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
	// Paired remotes: REL_PAIR_LIST with each remote's paired_juke (declared in modules/media/juke_remote.dm, w7).
	var/list/obj/item/juke_remote/remotes
	var/datum/track/current_track

CAPABILITIES(/obj/machinery/media/jukebox)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(playing), wakes_on = list(nameof(playing)))
	climb()
	interface("Jukebox", title = "RetroBox - Space Style")
	op("change_track", ui_act("change_track", arg("change_track")), then(PROC_REF(ui_act_change_track)))
	op("loopmode", ui_act("loopmode", arg("loopmode", num())), then(PROC_REF(ui_act_loopmode)))
	op("volume", ui_act("volume", arg("val", num())), then(PROC_REF(ui_act_volume)))
	op("stop", ui_act("stop"), then(PROC_REF(ui_act_stop)))
	op("play", ui_act("play"), then(PROC_REF(ui_act_play)))
	op("add_new_track", ui_act("add_new_track", arg("artist", schema_text(4096)), arg("duration", num()), arg("genre", schema_text(4096)), arg("lobby", num()), arg("secret", num()), arg("title", schema_text(4096)), arg("url", schema_text(4096))), then(PROC_REF(ui_act_add_new_track)))
	op("remove_new_track", ui_act("remove_new_track", arg("ref")), then(PROC_REF(ui_act_remove_new_track)))
	emag(then(PROC_REF(on_emag)))
	space(SPACE_PANEL, door = nameof(panel_open))
	wires(name = "Jukebox", count = 11, randomize = TRUE, tools = FALSE, status_lines = PROC_REF(wire_lights))
	// its own wires: what each does is heard below (a pulse on a dud may shock), so they are declared bare
	on_wire(WIRE_MAIN_POWER1)
	on_wire(WIRE_JUKEBOX_HACK)
	on_wire(WIRE_SPEEDUP)
	on_wire(WIRE_SPEEDDOWN)
	on_wire(WIRE_REVERSE)
	on_wire(WIRE_START)
	on_wire(WIRE_STOP)
	on_wire(WIRE_PREV)
	on_wire(WIRE_NEXT)
	on_notice(/datum/notice/wire_cut, then(PROC_REF(wire_cut_heard)))
	on_notice(/datum/notice/wire_pulsed, then(PROC_REF(wire_pulse_heard)))

// ALLOW(init/INSTANCE_STATE): takes its built parts, and breaks when it has no tracks to play
/obj/machinery/media/jukebox/Initialize(mapload)
	. = ..()
	default_apply_parts()
	update_icon()
	if(!LAZYLEN(getTracksList()))
		atom_break()

/obj/machinery/media/jukebox/proc/getTracksList()
	return hacked ? SSmedia_tracks.all_tracks : SSmedia_tracks.jukebox_tracks

/obj/machinery/media/jukebox/proc/work_step(datum/act/timer/A)
	if(!operable())
		disconnect_media_source()
		set_playing(0)
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
			rel_set(src, nameof(current_track), tracks[newTrackIndex])
		if(JUKEMODE_RANDOM)
			var/previous_track = current_track()
			do
				rel_set(src, nameof(current_track), pick(tracks))
			while(current_track() == previous_track && tracks.len > 1)
		if(JUKEMODE_REPEAT_SONG)
			rel_set(src, nameof(current_track), current_track())
		if(JUKEMODE_PLAY_ONCE)
			rel_clear(src, nameof(current_track))
			set_playing(0)
			update_icon()
	start_stop_song()

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
	wires_open(src, user)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/media/jukebox/multitool_act(mob/user, obj/item/tool)
	wires_open(src, user)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/media/jukebox/wrench_act(mob/user, obj/item/tool)
	if(playing)
		StopPlaying()
	act_message(user, src, MSG_SELF(span_notice("You [anchored ? "un" : ""]secure %T%.")), \
		MSG_OTHERS(span_warning("%U% has [anchored ? "un" : ""]secured %T%.")))
	set_anchored(!anchored)
	playsound(src, tool.usesound, 50, TRUE)
	power_change()
	update_icon()
	if(!anchored)
		set_playing(FALSE)
		disconnect_media_source()
	else
		update_media_source()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/media/jukebox/power_change()
	set_powered(powered(power_channel) && anchored)

	if(!operable() && playing)
		StopPlaying()
	update_icon()

/obj/machinery/media/jukebox/proc/appearance_live()
	return (operable() && anchored) ? 1 : 0

/obj/machinery/media/jukebox/proc/appearance_suffix()
	if(appearance_live())
		return ""
	return has_stat(BROKEN) ? "-broken" : "-nopower"

/obj/machinery/media/jukebox/proc/appearance_running()
	if(!appearance_live() || !playing)
		return ""
	return emagged ? "emagged" : "running"

/obj/machinery/media/jukebox/proc/appearance_panel()
	return (appearance_live() && panel_open) ? 1 : 0

APPEARANCE_TEMPLATE(/obj/machinery/media/jukebox, "{state_base}{appearance_suffix}")
DECLARE_APPEARANCE(/obj/machinery/media/jukebox, "appearance_running", list(
	"running" = list(APPEARANCE_OVERLAYS = list("jukebox-running")),
	"emagged" = list(APPEARANCE_OVERLAYS = list("jukebox-emagged"))
))
DECLARE_APPEARANCE(/obj/machinery/media/jukebox, "appearance_panel", list("1" = list(APPEARANCE_OVERLAYS = list("panel_open"))))
DECLARE_APPEARANCE(/obj/machinery/media/jukebox/casinojukebox, "appearance_running", list(
	"running" = list(APPEARANCE_OVERLAYS = list("casinojukebox-running")),
	"emagged" = list(APPEARANCE_OVERLAYS = list("casinojukebox-emagged"))
))

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

/obj/machinery/media/jukebox/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()

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

	data["playing"] = playing
	data["loop_mode"] = loop_mode
	data["volume"] = volume
	return data

/obj/machinery/media/jukebox/proc/ui_act_change_track(datum/act/op/A, change_track)
	var/datum/track/T = ui_ref(change_track, getTracksList(), /datum/track)
	if(istype(T))
		rel_set(src, nameof(/obj/item/walkpod::current_track), T)
		StartPlaying()
	return TRUE

/obj/machinery/media/jukebox/proc/ui_act_loopmode(datum/act/op/A, loopmode)
	var/newval = loopmode
	loop_mode = sanitize_inlist(newval, list(JUKEMODE_NEXT, JUKEMODE_RANDOM, JUKEMODE_REPEAT_SONG, JUKEMODE_PLAY_ONCE), loop_mode)
	return TRUE

/obj/machinery/media/jukebox/proc/ui_act_volume(datum/act/op/A, val)
	var/newval = val
	volume = clamp(newval, 0, 1)
	update_music() // To broadcast volume change without restarting song
	return TRUE

/obj/machinery/media/jukebox/proc/ui_act_stop(datum/act/op/A)
	StopPlaying()
	return OP_OK

/obj/machinery/media/jukebox/proc/ui_act_play(datum/act/op/A)
	var/mob/user = A.actor
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
		if(!after_pending(src, "jukebox_emag_explosion"))
			after(src, 1.5 SECONDS, PROC_REF(explode), key = "jukebox_emag_explosion")
	else if(current_track() == null)
		to_chat(user, "No track selected.")
	else
		StartPlaying()
	return TRUE

/obj/machinery/media/jukebox/proc/ui_act_add_new_track(datum/act/op/A, artist, duration, genre, lobby, secret, title, url)
	var/mob/user = A.actor
	SSmedia_tracks.add_track(user, url, title, duration * 10, artist, genre, secret, lobby)

/obj/machinery/media/jukebox/proc/ui_act_remove_new_track(datum/act/op/A, raw_ref)
	var/mob/user = A.actor
	var/datum/track/track_to_remove = ui_ref(raw_ref, getTracksList(), /datum/track)
	if(track_to_remove == current_track() && playing)
		StopPlaying()
	SSmedia_tracks.remove_track(user, track_to_remove)

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

/obj/machinery/media/jukebox/proc/on_emag(datum/act/op/A)
	set_emagged(1)
	StopPlaying()
	visible_message(span_danger("\The [src] makes a fizzling sound."))
	update_icon()
	return OP_OK

/obj/machinery/media/jukebox/proc/StopPlaying()
	set_playing(0)
	set_use_power(USE_POWER_IDLE)
	start_stop_song()

/obj/machinery/media/jukebox/proc/StartPlaying()
	if(!current_track())
		return
	set_playing(1)
	set_use_power(USE_POWER_ACTIVE)
	start_stop_song()

// Advance to the next track - Don't start playing it unless we were already playing
/obj/machinery/media/jukebox/proc/NextTrack()
	var/list/tracks = getTracksList()
	if(!tracks.len) return
	var/curTrackIndex = max(1, tracks.Find(current_track()))
	var/newTrackIndex = (curTrackIndex % tracks.len) + 1  // Loop back around if past end
	rel_set(src, nameof(current_track), tracks[newTrackIndex])
	if(playing)
		start_stop_song()

// Advance to the next track - Don't start playing it unless we were already playing
/obj/machinery/media/jukebox/proc/PrevTrack()
	var/list/tracks = getTracksList()
	if(!tracks.len) return
	var/curTrackIndex = max(1, tracks.Find(current_track()))
	var/newTrackIndex = curTrackIndex == 1 ? tracks.len : curTrackIndex - 1
	rel_set(src, nameof(current_track), tracks[newTrackIndex])
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

CAPABILITIES(/obj/machinery/media/jukebox/ghost)
	owns_many(nameof(custom_tracks))

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
/obj/machinery/media/jukebox/ghost/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	return
/obj/machinery/media/jukebox/ghost/explode()
	return
/// Draws itself entirely: drop the parent's keyed declarations.
APPEARANCE_NONE(/obj/machinery/media/jukebox/ghost)
DECLARE_APPEARANCE_PROC(/obj/machinery/media/jukebox/ghost, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/media/jukebox/ghost/appearance_overlays()
	. = list()
	if(playing)
		animate(src, alpha = 200, time = 5, loop = -1)
	else
		animate(src, alpha = initial(alpha), time = 10)
// End junk

/// Old attack_ghost: staff get the controls, other ghosts hear what's playing.
/obj/machinery/media/jukebox/ghost/proc/ghost_jukebox_observer_use(mob/observer/dead/M, obj/item/held, datum/interaction/interaction)
	if(!istype(M))
		return TRUE

	if(admin_require(M.client, R_FUN|R_ADMIN, "ghost_jukebox_observer_use", 0))
		interact(M)
	else if(current_track())
		to_chat(M, "\The [src] is playing [current_track().display()].")
	else
		to_chat(M, "\The [src] is not playing any music.")
	return TRUE

/obj/machinery/media/jukebox/ghost/getTracksList()
	return (custom_tracks + ..())

/obj/machinery/media/jukebox/ghost/proc/manual_track_add(mob/user)
	if(!admin_require(user?.client, R_FUN|R_ADMIN, "check_rights in [callee?.proc]"))
		return

	open_request(src, /datum/prompt/text/jukebox_track, PROC_REF(url_entered), answerer = user, title = "Track URL", question = "REQUIRED: Provide URL for track", rights = R_FUN|R_ADMIN, timeout = 0)

/// A custom track being added: what the admin has answered so far is kept on the question.
/datum/prompt/text/jukebox_track
	var/track_url
	var/track_title
	var/track_duration

/datum/prompt/number/jukebox_track
	var/track_url
	var/track_title

/obj/machinery/media/jukebox/ghost/proc/url_entered(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	open_request(src, /datum/prompt/text/jukebox_track, PROC_REF(title_entered), answerer = A.request.answerer, title = "Track Title", question = "REQUIRED: Provide title for track", rights = R_FUN|R_ADMIN, track_url = A.answer.value, timeout = 0)

/obj/machinery/media/jukebox/ghost/proc/title_entered(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/datum/prompt/text/jukebox_track/R = A.request
	open_request(src, /datum/prompt/number/jukebox_track, PROC_REF(duration_entered), answerer = R.answerer, title = "Track Duration", question = "REQUIRED: Provide duration for track (in deciseconds, aka seconds*10)", rights = R_FUN|R_ADMIN, track_url = R.track_url, track_title = A.answer.value, timeout = 0)

/obj/machinery/media/jukebox/ghost/proc/duration_entered(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/datum/prompt/number/jukebox_track/R = A.request
	open_request(src, /datum/prompt/text/jukebox_track, PROC_REF(artist_entered), answerer = R.answerer, title = "Track Artist", question = "Optional: Provide artist for track", rights = R_FUN|R_ADMIN, track_url = R.track_url, track_title = R.track_title, track_duration = A.answer.value, timeout = 0)

/obj/machinery/media/jukebox/ghost/proc/artist_entered(datum/act/request/A)
	var/datum/prompt/text/jukebox_track/R = A.request
	var/artist = A.answer ? A.answer.value : ""
	// So they're obvious and grouped
	var/genre = "! Admin Loaded !"
	rel_add(src, nameof(custom_tracks), new /datum/track(R.track_url, R.track_title, R.track_duration, artist, genre))

/obj/machinery/media/jukebox/ghost/proc/manual_track_remove(mob/user)
	if(!admin_require(user?.client, R_FUN|R_ADMIN, "check_rights in [callee?.proc]"))
		return

	open_request(src, /datum/prompt/text, PROC_REF(manual_track_removal_entered), answerer = user, title = "Remove Track", question = "Input track title or URL to remove (must be exact)", rights = R_FUN|R_ADMIN, timeout = 0)

/obj/machinery/media/jukebox/ghost/proc/manual_track_removal_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/track = A.answer.value
	var/client/C = user.client
	if(!track)
		return

	for(var/datum/track/T in custom_tracks)
		if(T.title == track || T.url == track)
			rel_remove(src, nameof(custom_tracks), T)
			return

	to_chat(C, span_warning("Couldn't find a track matching the specified parameters."))

/obj/machinery/media/jukebox/ghost/vv_get_dropdown()
	. = ..()
	VV_DROPDOWN_OPTION("", "---")
	VV_DROPDOWN_OPTION("add_track", "Add New Track")
	VV_DROPDOWN_OPTION("remove_track", "Remove Track")

VV_TOPIC_ACTION(/obj/machinery/media/jukebox/ghost, "add_track", PROC_REF(vv_topic_add_track))
VV_TOPIC_ACTION(/obj/machinery/media/jukebox/ghost, "remove_track", PROC_REF(vv_topic_remove_track))

/obj/machinery/media/jukebox/ghost/proc/vv_topic_add_track(mob/user, list/args)
	manual_track_add(user)
	user.client?.debug_variables(src)
	return TRUE

/obj/machinery/media/jukebox/ghost/proc/vv_topic_remove_track(mob/user, list/args)
	manual_track_remove(user)
	user.client?.debug_variables(src)
	return TRUE

/obj/machinery/media/jukebox/casinojukebox
	name = "space casino jukebox"
	desc = "A jukebox to play the tracks on the golden goose, jazzy~"
	icon = 'icons/obj/casino_ch.dmi'
	icon_state = "casinojukebox-nopower"
	state_base = "casinojukebox"

	use_power = USE_POWER_OFF

/obj/machinery/media/jukebox/casinojukebox/getTracksList()
	return SSmedia_tracks.casino_tracks

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/media/jukebox/step_start_condition()
	return playing

/// current track (a relation view: it reads null once the target is deleted).
/obj/machinery/media/jukebox/proc/current_track() as /datum/track
	return current_track


// ---- the wires ----


/// The lights hint at the state each wire drives.
/obj/machinery/media/jukebox/proc/wire_lights()
	return list(
		"The power light is [stat & (BROKEN|NOPOWER) ? "off." : "on."]",
		"The parental guidance light is [hacked ? "off." : "on."]",
		"The data light is [wire_is_cut(src, WIRE_REVERSE) ? "hauntingly dark." : "glowing softly."]")

/// A wire cut or mended: the power wire shocks, the hack wire hacks, the playback wires set the speed and direction.
/obj/machinery/media/jukebox/proc/wire_cut_heard(datum/act/A)
	var/datum/notice/wire_cut/N = A
	switch(N.wire)
		if(WIRE_MAIN_POWER1)
			shock(N.user, 90)
		if(WIRE_JUKEBOX_HACK)
			set_hacked(!N.mended)
		if(WIRE_SPEEDUP, WIRE_SPEEDDOWN, WIRE_REVERSE)
			var/newfreq = wire_is_cut(src, WIRE_REVERSE) ? -1 : 1
			if(wire_is_cut(src, WIRE_SPEEDUP))
				newfreq *= 2
			if(wire_is_cut(src, WIRE_SPEEDDOWN))
				newfreq *= 0.5
			freq = newfreq

/// A wire pulsed: each gives a hint of what it does; the playback wires work the player; the duds may shock.
/obj/machinery/media/jukebox/proc/wire_pulse_heard(datum/act/A)
	var/datum/notice/wire_pulsed/N = A
	switch(N.wire)
		if(WIRE_MAIN_POWER1)
			visible_message(span_notice("[icon2html(src, viewers(src))] The power light flickers."))
			shock(N.user, 90)
		if(WIRE_JUKEBOX_HACK)
			visible_message(span_notice("[icon2html(src, viewers(src))] The parental guidance light flickers."))
		if(WIRE_REVERSE)
			visible_message(span_notice("[icon2html(src, viewers(src))] The data light blinks ominously."))
		if(WIRE_SPEEDUP)
			visible_message(span_notice("[icon2html(src, viewers(src))] The speakers squeaks."))
		if(WIRE_SPEEDDOWN)
			visible_message(span_notice("[icon2html(src, viewers(src))] The speakers rumble."))
		if(WIRE_START)
			StartPlaying()
		if(WIRE_STOP)
			StopPlaying()
		if(WIRE_PREV)
			PrevTrack()
		if(WIRE_NEXT)
			NextTrack()
		else
			shock(N.user, 10) // the nothing wires give a chance to shock just for fun
