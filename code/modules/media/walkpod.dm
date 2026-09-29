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

/// Person whomst is listening to us. periodic_step() checks on them and plays music while set (DECLARE_PERIODIC_WHILE).
OM_FIELD_VIEW(/obj/item/walkpod, mob/living, listener, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/item/walkpod, PERIODIC_SLOW, "listener")

// stops listening.
/obj/item/walkpod/on_destroy(force)
	remove_listener()
	..()

// Icon
/obj/item/walkpod/update_icon()
	if(listener())
		if(deployed_headpods)
			icon_state = "zuman_on"
		else
			icon_state = "[initial(icon_state)]_on"
	else
		if(deployed_headpods)
			icon_state = "zuman"
		else
			icon_state = "[initial(icon_state)]"

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
	rel_clear(src, "listener")
	update_icon()

/obj/item/walkpod/proc/set_listener(mob/living/L)
	if(listener())
		remove_listener()
	rel_set(src, "listener", L)
	to_chat(L, span_notice("You put the [src]'s headphones on and power it up, preparing to listen to some <b>sick tunes</b>."))
	update_icon()

/obj/item/walkpod/proc/update_music()
	listener()?.force_music(media_url, media_start_time, volume) // Calling this with "" url (when we aren't playing) helpfully disables forced music

/// Old click_alt.
/obj/item/walkpod/proc/interaction_alt(mob/living/L, obj/item/held, datum/interaction/interaction)
	if(L == listener() && check_listener())
		tgui_interact(L)
	else if(loc == L) // at least they're holding it
		to_chat(L, span_warning("Turn on the [src] first."))
	return TRUE

DECLARE_INTERACTIONS(/obj/item/walkpod, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_ALT(null, PROC_REF(interaction_alt)), \
	INTERACT_VERB("Take HeadPods", PROC_REF(walkpod_verb_take_headpods), REQ_IN_INVENTORY, REQ_FIELD_NOT("deployed_headpods", "the HeadPods are already deployed")), \
)

/// Old attack_self.
/obj/item/walkpod/proc/interaction_self(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(!istype(user) || loc != user)
		return TRUE
	if(!listener())
		set_listener(user)
	tgui_interact(user)
	return TRUE

// Process ticks to ensure our listener remains valid and we do music-ing
/obj/item/walkpod/periodic_step()
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
			rel_set(src, "current_track", tracks[newTrackIndex])
		if(JUKEMODE_RANDOM)
			var/previous_track = current_track()
			do
				rel_set(src, "current_track", pick(tracks))
			while(current_track() == previous_track && tracks.len > 1)
		if(JUKEMODE_REPEAT_SONG)
			rel_set(src, "current_track", current_track())
		if(JUKEMODE_PLAY_ONCE)
			rel_clear(src, "current_track")
			playing = 0
			update_icon()
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
	rel_set(src, "current_track", tracks[newTrackIndex])
	if(playing)
		start_stop_song()

// Unadvance to the notnext track - Don't start playing it unless we were already playing
/obj/item/walkpod/proc/PrevTrack()
	var/list/tracks = getTracksList()
	if(!tracks.len) return
	var/curTrackIndex = max(1, tracks.Find(current_track()))
	var/newTrackIndex = curTrackIndex == 1 ? tracks.len : curTrackIndex - 1
	rel_set(src, "current_track", tracks[newTrackIndex])
	if(playing)
		start_stop_song()

// UI
/obj/item/walkpod/proc/getTracksList()
	return SSmedia_tracks.jukebox_tracks

/obj/item/walkpod/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Jukebox", "PodZu Music Player")
		ui.open()

/obj/item/walkpod/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
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
	data["percent"] = (playing && current_track()) ? min(100, round((world.time - media_start_time) / current_track().duration)) : 0;

	var/list/tgui_tracks = list()
	for(var/datum/track/T in getTracksList())
		tgui_tracks.Add(list(T.toTguiList()))
	data["tracks"] = tgui_tracks

	return data

/obj/item/walkpod/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	switch(action)
		if("change_track")
			var/datum/track/T = locate_in_list(getTracksList(), params["change_track"])
			if(istype(T))
				rel_set(src, "current_track", T)
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
			if(current_track() == null)
				to_chat(ui.user, "No track selected.")
			else
				StartPlaying()
			return TRUE

// Silly verb
/// Old Take HeadPods verb: Grab the pair of HeadPods.
/obj/item/walkpod/proc/walkpod_verb_take_headpods(mob/user, obj/item/held, datum/interaction/interaction)
	var/mob/living/L = user
	if(!istype(L))
		return
	own_set(src, "deployed_headpods", new /obj/item/headpods ())
	L.put_in_any_hand_if_possible(deployed_headpods)
	update_icon()

/// Old attackby.
/obj/item/walkpod/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(W == deployed_headpods)
		restore_headpods(user)
		return INTERACTION_HANDLED_PASS
	return FALSE

/obj/item/walkpod/proc/restore_headpods(mob/living/potential_holder)
	if(!deployed_headpods)
		return

	if(listener())
		to_chat(listener(), span_notice("The headphone cable reunites the [deployed_headpods] with the [src] by retracting inwards."))

	if(istype(potential_holder))
		potential_holder.unEquip(deployed_headpods, force = TRUE)
	own_clear(src, "deployed_headpods", OWN_DELETE)
	update_icon()

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
