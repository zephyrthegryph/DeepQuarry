/**********************
 * AWW SHIT IT'S TIME FOR RADIO
 *
 * Concept stolen from D2K5
 * Rewritten by N3X15 for vgstation
 * Adapted by Leshana for VOREStation
 ***********************/

// Uncomment to test the mediaplayer
// #define DEBUG_MEDIAPLAYER

#ifdef DEBUG_MEDIAPLAYER
#define MP_DEBUG(x) to_chat(owner,x)
#warn Please comment out #define DEBUG_MEDIAPLAYER before committing.
#else
#define MP_DEBUG(x)
#endif

// Set up player on login.
/client/New()
	. = ..()
	media = new /datum/media_manager(src) // ALLOW(ownership): /client is not a datum and is the one owner of this by design
	media.open()
	media.update_music()

// Stop media when the round ends. I guess so it doesn't play forever or something (for some reason?)
/hook/roundend/proc/stop_all_media()
	log_world("Stopping all playing media...")
	// Stop all music.
	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(M && M.client)
			M.stop_all_music()
	// The reboot waits out its own round-end delay, so the stop messages reach the clients first.
	return TRUE

// Update when moving between areas.
// TODO - While this direct override might technically be faster, probably better code to use observer or hooks ~Leshana
/area/Entered(mob/M)
	// Note, we cannot call ..() first, because it would update lastarea.
	if(!istype(M) || isEye(M))
		return ..()
	// Optimization, no need to call update_music() if both are null (or same instance, strange as that would be)
	if(M.lastarea?.media_source() == src.media_source())
		return ..()
	if(M.client?.media && !M.client.media.forced)
		M.update_music()
	return ..()

//
// ### Media variable on /client ###
/client
	// Set on Login
	var/datum/media_manager/media = null

/client/verb/change_volume()
	set name = "Set Volume"
	set category = VERB_CAT_OOC_CLIENT_SETTINGS
	set desc = "Set jukebox volume"
	set_new_volume(usr)

/client/proc/set_new_volume(mob/user)
	if(QDELETED(src.media) || !istype(src.media))
		to_chat(user, span_warning("You have no media datum to change, if you're not in the lobby tell an admin."))
		return
	open_request(src, /datum/prompt/number/jukebox_volume, PROC_REF(jukebox_volume_answered), answerer = user, default = media.volume)

/datum/prompt/number/jukebox_volume
	question = "Choose your Jukebox volume."
	title = "Jukebox volume"
	min_value = 0
	max_value = 100
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/number/jukebox_volume/recheck_extra()
	if(QDELETED(answerer))
		return "gone"
	. = ..()
	if(.)
		return
	var/client/player = owner
	if(!istype(player) || QDELETED(player.media) || !istype(player.media, /datum/media_manager))
		return "The media manager is unavailable."

/client/proc/jukebox_volume_answered(datum/act/request/A)
	if(!A.answer)
		if(!isnull(A.request.value) && (QDELETED(media) || !istype(media, /datum/media_manager)))
			to_chat(A.request.answerer, span_warning("You have no media datum to change, if you're not in the lobby tell an admin."))
		return
	var/value = A.answer.value
	value = round(max(0, min(100, value)))
	media.update_volume(value / 100)

//
// ### Media procs on mobs ###
// These are all convenience functions, simple delegations to the media datum on mob.
// But their presense and null checks make other coder's life much easier.
//

/mob/proc/update_music()
	if (client?.media && !client.media.forced)
		client.media.update_music()

/mob/proc/stop_all_music()
	client?.media?.stop_music()

/mob/proc/force_music(url, start, volume=1)
	if (client?.media)
		if(url == "")
			client.media.forced = 0
			client.media.update_music()
		else
			client.media.forced = 1
			client.media.push_music(url, start, volume)
	return

//
// ### Define media source to areas ###
// Each area may have at most one media source that plays songs into that area.
// We keep track of that source so any mob entering the area can lookup what to play.
//
/area
	// For now, only one media source per area allowed
	// Possible Future: turn into a list, then only play the first one that's playing.
	var/tmp/obj/machinery/media/media_source

//
// ### Media Manager Datum
//

/datum/media_manager
	var/url = ""				// URL of currently playing media
	var/start_time = 0			// world.time when it started playing *in the source* (Not when started playing for us)
	var/source_volume = 1		// Volume as set by source. Actual volume = "volume * source_volume"
	var/rate = 1				// Playback speed.  For Fun(tm)
	var/volume = 0.5			// Client's volume modifier. Actual volume = "volume * source_volume"
	var/tmp/client/owner	// Client this is actually running in
	var/forced=0				// If true, current url overrides area media sources
	// media playback via TGUI MediaPlayer hosted in the
	// hidden rpane.mediapanel skin element. The skin element stays
	// invisible (is-visible=false); the TGUI's React bundle loads into
	// it anyway and the HTML5 <audio> element plays audio regardless
	// of CSS visibility. Replaces the legacy browse(player_html) +
	// output("...:SetMusic") JS interop.
	var/datum/tgui_window/media_window
	var/const/WINDOW_ID = "rpane.mediapanel"

CAPABILITIES(/datum/media_manager)
	owns_one(nameof(media_window), /datum/tgui_window)
	interface("MediaPlayer", state = nameof(GLOB.tgui_always_state), pinned = TRUE, preinitialized = TRUE)
	ui_shape(url = schema_text(), start_time = num(), volume = num())

/datum/media_manager/New(client/C)
	ASSERT(istype(C))
	rel_set(src, nameof(owner), C)

/// Owned-child release: the media window is closed as it leaves us (replaced, or disposed at teardown).
/datum/media_manager/on_owned_release(var_name, datum/child)
	if(var_name == "media_window")
		var/datum/tgui_window/window = child
		window.close()
	return ..()

/// /datum/media_manager's window data.
/datum/media_manager/ui_data(datum/act/eval/A)
	var/should_play = TRUE
	if(owner()?.prefs)
		should_play = owner().prefs.read_preference(/datum/preference/toggle/play_jukebox) || url == ""
	return list(
		"url" = should_play ? url : "",
		"start_time" = (world.time - start_time) / 10,
		"volume" = volume * source_volume,
	)

// Actually pop open the player in the background.

/// Renders in the hidden media browser element open() initializes.
/datum/media_manager/ui_window(mob/user)
	return media_window

/datum/media_manager/proc/open()
	if(!owner())
		return
	if(owner().prefs && isnum(owner().prefs.read_preference(/datum/preference/numeric/living/jukebox_volume)))
		volume = owner().prefs.read_preference(/datum/preference/numeric/living/jukebox_volume) / 100

	// Enable the hidden skin element so its BROWSER actually loads our
	// assets — the 1x1 size keeps it invisible regardless of is-visible.
	winset(owner(), WINDOW_ID, "is-disabled=false;is-visible=true")
	rel_set(src, nameof(media_window), new /datum/tgui_window(owner(), WINDOW_ID))
	media_window.initialize(
		assets = list(get_asset_datum(/datum/asset/simple/tgui)),
	)

	tgui_interact(owner().mob)

// Push a fresh state to the React side; it'll re-sync audio src/volume/time.
/datum/media_manager/proc/send_update()
	if(!owner())
		return
	MP_DEBUG(span_green("Sending update to mediapanel ([url], [(world.time - start_time) / 10], [volume * source_volume])..."))
	SStgui.update_uis(src)

/datum/media_manager/proc/push_music(targetURL, targetStartTime, targetVolume)
	if (url != targetURL || abs(targetStartTime - start_time) > 1 || abs(targetVolume - source_volume) > 0.1 /* 10% */)
		url = targetURL
		start_time = targetStartTime
		source_volume = CLAMP(targetVolume, 0, 1)
		send_update()

/datum/media_manager/proc/stop_music()
	push_music("", 0, 1)

/datum/media_manager/proc/update_volume(value)
	volume = value
	send_update()

// Scan for media sources and use them.
/datum/media_manager/proc/update_music()
	var/targetURL = ""
	var/targetStartTime = 0
	var/targetVolume = 0

	if (forced || !owner() || !owner().mob)
		return

	var/area/A = get_area(owner().mob)
	if(!A)
		MP_DEBUG("client=[owner()], mob=[owner().mob] not in an area! loc=[owner().mob.loc].  Aborting.")
		stop_music()
		return
	var/obj/machinery/media/M = A.media_source()
	if(M && M.playing)
		targetURL = M.media_url
		targetStartTime = M.media_start_time
		targetVolume = M.volume
	push_music(targetURL, targetStartTime, targetVolume)

#ifdef DEBUG_MEDIAPLAYER
#undef DEBUG_MEDIAPLAYER
#undef MP_DEBUG
#endif



/// the media_source this refers to (a relation view: null once it is deleted).
/area/proc/media_source() as /obj/machinery/media
	return media_source

/// Client this is actually running in (a relation view: null once it is deleted).
/datum/media_manager/proc/owner() as /client
	return owner
