// Mostly a jukebox copy-paste, given the vastly different paths though it seemed worth it.
// Would rather not have a bunch of /machinery baggage on our portable music player.

/obj/item/walkpod/get_mechanics_info(list/additional_information)
	return ..(list("Wearing the headphones is not necessary to listen to music.") + additional_information)

/obj/item/walkpod
	name ="\improper PodZu music player"
	desc = "Portable music player! For when you need to ignore the rest of the world, there's only one choice: PodZu."
	description_fluff = "A prestigious set: The ZuMan music player, and the HeadPods headphones, both 90th anniversary releases! Together they form the PodZu Music Player, famous in the local galactic cluster for pumping sick beats directly into your head."

	icon = 'icons/obj/device.dmi'
	icon_state = "podzu" // podzu_o, headpod, zuman

	var/loop_mode = JUKEMODE_PLAY_ONCE	// Behavior when finished playing a song
	var/tmp/datum/track/current_track	// Current track playing

	var/playing = 0
	var/volume = 1

	var/media_url = ""
	EXPIRY_DECLARE(media_start_time)

	var/obj/item/headpods/deployed_headpods

	w_class = ITEMSIZE_COST_SMALL
	slot_flags = SLOT_BELT

CAPABILITIES(/obj/item/walkpod)
	ref_one(nameof(listener))
	every(2 SECONDS, then(PROC_REF(walkpod_step)), when = nameof(listener))
	op("self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(interaction_item)))
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(interaction_alt)))
	op("walkpod_verb_take_headpods", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Take HeadPods"), needs(carried(), req_empty(nameof(deployed_headpods), because = MSG(walkpod/headpods_deployed))), then(PROC_REF(walkpod_verb_take_headpods)))
	op("stop", ui_act(), then(PROC_REF(ui_act_stop)))
	op("play", ui_act(), then(PROC_REF(ui_act_play)))
	owns_one(nameof(deployed_headpods), /obj/item/headpods)
	interface("Jukebox", title = "PodZu Music Player")
	without("ui_open")
	op("change_track", ui_act("change_track", arg("change_track", schema_ref(/datum/track))), then(PROC_REF(ui_act_change_track)))
	op("loopmode", ui_act("loopmode", arg("loopmode", num())), then(PROC_REF(ui_act_loopmode)))
	op("volume", ui_act("volume", arg("val", num())), then(PROC_REF(ui_act_volume)))

/// Person whomst is listening to us. walkpod_step() checks on them and plays music while set (its every(), gated on it).
/obj/item/walkpod/var/mob/living/listener
MSG_DEF_SELF(walkpod/headpods_deployed, "the HeadPods are already deployed")

// stops listening.
/obj/item/walkpod/on_destroy(force)
	remove_listener()
	..()

// Icon
/obj/item/walkpod/proc/appearance_base()
	return deployed_headpods ? "zuman" : initial(icon_state)

/// The look (the draw sweep: from its template).
/obj/item/walkpod/draw(datum/look/look)
	..()
	look.state("[appearance_base()][listener() ? "_on" : ""]")

// Listener handling
/obj/item/walkpod/proc/check_listener()
	if(loc == listener())
		return TRUE
	return FALSE

/obj/item/walkpod/proc/remove_listener()
	if(playing)
		StopPlaying()
	if(deployed_headpods)
		restore_headpods()
	to_chat(listener(), span_notice("You are no longer wearing the [src]'s headphones."))
	rel_clear(src, nameof(listener))

/obj/item/walkpod/proc/set_listener(mob/living/L)
	if(listener())
		remove_listener()
	rel_set(src, nameof(listener), L)
	to_chat(L, span_notice("You put the [src]'s headphones on and power it up, preparing to listen to some <b>sick tunes</b>."))

/obj/item/walkpod/proc/update_music()
	listener()?.force_music(media_url, media_start_time, volume) // Calling this with "" url (when we aren't playing) helpfully disables forced music

/// Old click_alt.
/obj/item/walkpod/proc/interaction_alt(datum/act/op/A)
	var/mob/living/L = A.actor
	if(L == listener() && check_listener())
		tgui_interact(L)
	else if(loc == L) // at least they're holding it
		to_chat(L, span_warning("Turn on the [src] first."))
	return OP_OK

/// Old attack_self.
/obj/item/walkpod/proc/interaction_self(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!istype(user) || loc != user)
		return OP_OK
	if(!listener())
		set_listener(user)
	tgui_interact(user)
	return OP_OK

// Process ticks to ensure our listener remains valid and we do music-ing
/obj/item/walkpod/proc/walkpod_step(datum/act/timer/A)
	if(!check_headpods())
		restore_headpods()
	if(!check_listener())
		remove_listener()
		return
	if(!playing)
		return
	// If the current track isn't finished playing, let it keep going
	if(current_track() && BEFORE(src, media_start_time + current_track().duration, CLOCK_WORLD))
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
			playing = 0
	start_stop_song()

// Track/music internals
/obj/item/walkpod/proc/start_stop_song()
	if(current_track() && playing)
		media_url = current_track().url
		EXPIRY_STAMP(src, media_start_time, CLOCK_WORLD)
		runechat_message("*&nbsp;[current_track().display()]&nbsp;*", specific_viewers = list(listener()))
	else
		media_url = ""
		media_start_time = 0
	update_music()

/obj/item/walkpod/proc/StopPlaying()
	playing = 0
	start_stop_song()

/obj/item/walkpod/proc/StartPlaying()
	if(!current_track())
		return
	playing = 1
	start_stop_song()

// Advance to the next track - Don't start playing it unless we were already playing
/obj/item/walkpod/proc/NextTrack()
	var/list/tracks = getTracksList()
	if(!tracks.len) return
	var/curTrackIndex = max(1, tracks.Find(current_track()))
	var/newTrackIndex = (curTrackIndex % tracks.len) + 1  // Loop back around if past end
	rel_set(src, nameof(current_track), tracks[newTrackIndex])
	if(playing)
		start_stop_song()

// Unadvance to the notnext track - Don't start playing it unless we were already playing
/obj/item/walkpod/proc/PrevTrack()
	var/list/tracks = getTracksList()
	if(!tracks.len) return
	var/curTrackIndex = max(1, tracks.Find(current_track()))
	var/newTrackIndex = curTrackIndex == 1 ? tracks.len : curTrackIndex - 1
	rel_set(src, nameof(current_track), tracks[newTrackIndex])
	if(playing)
		start_stop_song()

// UI
/obj/item/walkpod/proc/getTracksList()
	return SSmedia_tracks.jukebox_tracks

/obj/item/walkpod/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["playing"] = playing
	data["loop_mode"] = loop_mode
	data["volume"] = volume
	var/list/merged_1 = ui_data_obj_item_walkpod(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/walkpod's window data.
/obj/item/walkpod/proc/ui_data_obj_item_walkpod(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["current_track_ref"] = null
	data["current_track"] = null
	data["current_genre"] = null
	if(current_track())
		data["current_track_ref"] = "\ref[current_track()]"  // Convenient shortcut
		data["current_track"] = current_track().toTguiList()
		data["current_genre"] = current_track().genre
	data["percent"] = (playing && current_track()) ? min(100, round((world.time - media_start_time) / current_track().duration)) : 0;

	var/list/tgui_tracks = list()
	for(var/datum/track/T in getTracksList())
		tgui_tracks.Add(list(T.toTguiList()))
	data["tracks"] = tgui_tracks

	return data

/obj/item/walkpod/proc/ui_act_change_track(datum/act/op/A, change_track)
	if(!isnull(change_track) && !(change_track in getTracksList()))
		return FALSE
	var/datum/track/T = change_track
	if(istype(T))
		rel_set(src, nameof(/obj/item/walkpod::current_track), T)
		StartPlaying()
	return TRUE

/obj/item/walkpod/proc/ui_act_loopmode(datum/act/op/A, loopmode)
	var/newval = loopmode
	loop_mode = sanitize_inlist(newval, list(JUKEMODE_NEXT, JUKEMODE_RANDOM, JUKEMODE_REPEAT_SONG, JUKEMODE_PLAY_ONCE), loop_mode)
	return TRUE

/obj/item/walkpod/proc/ui_act_volume(datum/act/op/A, val)
	var/newval = val
	volume = clamp(newval, 0, 1)
	update_music() // To broadcast volume change without restarting song
	return TRUE

/obj/item/walkpod/proc/ui_act_stop(datum/act/op/A)
	StopPlaying()
	return OP_OK

/obj/item/walkpod/proc/ui_act_play(datum/act/op/A)
	if(current_track() == null)
		to_chat(A.actor, "No track selected.")
	else
		StartPlaying()
	return OP_OK

// Silly verb
/// Old Take HeadPods verb: Grab the pair of HeadPods.
/obj/item/walkpod/proc/walkpod_verb_take_headpods(datum/act/op/A)
	var/mob/living/L = A.actor
	if(!istype(L))
		return
	rel_set(src, nameof(deployed_headpods), new /obj/item/headpods ())
	L.put_in_any_hand_if_possible(deployed_headpods)

/// Old attackby.
/obj/item/walkpod/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(W == deployed_headpods)
		restore_headpods(user)
		return OP_PASS
	return OP_DECLINE

/obj/item/walkpod/proc/restore_headpods(mob/living/potential_holder)
	if(!deployed_headpods)
		return

	if(listener())
		to_chat(listener(), span_notice("The headphone cable reunites the [deployed_headpods] with the [src] by retracting inwards."))

	if(istype(potential_holder))
		potential_holder.unEquip(deployed_headpods, force = TRUE)
	rel_clear(src, nameof(deployed_headpods))

/obj/item/walkpod/proc/check_headpods()
	if(deployed_headpods && deployed_headpods.loc != loc)
		return FALSE
	return TRUE

/obj/item/headpods
	name = "\improper pair of HeadPods"
	desc = "Portable listening in Hi-Fi!"
	icon = 'icons/obj/device.dmi'
	icon_state = "headpods"
	item_state = "headphones_on"
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_HEAD


/// Current track playing (a relation view: null once it is deleted).
/obj/item/walkpod/proc/current_track() as /datum/track
	return current_track

/// Person whomst is listening to us (a relation view: null once it is deleted).
/obj/item/walkpod/proc/listener() as /mob/living
	return listener
