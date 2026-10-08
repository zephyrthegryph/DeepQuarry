#define CINEMATIC_SOURCE "cinematic"

/**
 * Plays a cinematic, duh. Can be to a select few people, or everyone.
 *
 * cinematic_type - datum typepath to what cinematic you wish to play.
 * watchers - a list of all mobs you are playing the cinematic to. If world, the cinematical will play globally to all players.
 * special_callback - optional callback to be invoked mid-cinematic.
 */
/proc/play_cinematic(datum/cinematic/cinematic_type, watchers, datum/callback/special_callback)
	if(!ispath(cinematic_type, /datum/cinematic))
		CRASH("play_cinematic called with a non-cinematic type. (Got: [cinematic_type])")
	var/datum/cinematic/playing = new cinematic_type(watchers, special_callback)

	if(watchers == world)
		watchers = REGISTRY_MEMBERS(REGISTRY_MOBS)

	playing.start_cinematic(watchers)

	return playing

/// The cinematic screen showed to everyone
/atom/movable/screen/cinematic
	icon = 'icons/effects/station_explosion.dmi'
	icon_state = "station_intact"
	plane = SPLASHSCREEN_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	screen_loc = "BOTTOM,LEFT+50%"
	appearance_flags = APPEARANCE_UI | TILE_BOUND

/// Cinematic datum. Used to show an animation to everyone.
/datum/cinematic
	/// All clients watching the cinematic: a relation list view (a returning player is shown it
	/// again through the mob_client_login hook).
	var/list/client/watching
	/// All mobs who have TRAIT_NO_TRANSFORM set while watching the cinematic: a relation list view.
	var/list/mob/locked
	/// Whether the cinematic is a global cinematic or not
	var/is_global = FALSE
	/// Refernce to the cinematic screen shown to everyohne
	var/atom/movable/screen/cinematic/screen
	/// Callbacks passed that occur during the animation
	var/datum/callback/special_callback
	/// How long for the final screen remains shown
	var/cleanup_time = 30 SECONDS
	/// How long the intro plays before the blast (the blast runs on an after() timer).
	/// Callers that act at the blast wait initial(intro_time).
	var/intro_time = 0
	/// Whether the cinematic turns off ooc when played globally.
	var/stop_ooc = TRUE

CAPABILITIES(/datum/cinematic)
	ref_many(nameof(watching))
	ref_many(nameof(locked))
	owns_one(nameof(screen), /atom/movable/screen/cinematic)
	owns_one(nameof(special_callback), /datum/callback)

/datum/cinematic/New(watcher, datum/callback/special_callback)
	rel_set(src, nameof(screen), new /atom/movable/screen/cinematic(src))
	if(watcher == world)
		is_global = TRUE

	rel_set(src, nameof(special_callback), special_callback)


/// Actually goes through the process of showing the cinematic to the list of watchers.
/datum/cinematic/proc/start_cinematic(list/watchers)
	var/datum/act/play_cinematic/play = ACT_TRY(OM_WORLD, play_cinematic, src)
	if(!play)
		return
	act_done(play)

	// Hook the world's play action to handle what happens when a different cinematic tries to play over us.
	observe(OM_WORLD, /datum/act/play_cinematic, src, instead(then(PROC_REF(handle_replacement_cinematics))))

	// Pause OOC
	// NOT IMPLEMENTED
	var/ooc_toggled = FALSE

	// Place the /atom/movable/screen/cinematic into everyone's screens, and prevent movement.
	for(var/mob/watching_mob in watchers)
		show_to(watching_mob, watching_mob.client)
		observe(watching_mob, /datum/notice/mob_client_login, src, then(PROC_REF(on_watcher_client_login)))
		// Close watcher ui's, too, so they can watch it.
		SStgui.close_user_uis(watching_mob)

	// Actually plays the animation (its later frames run on after() timers; nothing sleeps).
	play_cinematic()

	// Cleans up after it's done playing.
	after(src, intro_time + cleanup_time, PROC_REF(clean_up_cinematic), with = list(ooc_toggled))

/// Cleans up the cinematic after a set timer of it sticking on the end screen.
/datum/cinematic/proc/clean_up_cinematic(was_ooc_toggled = FALSE)
	// NOT IMPLEMENTED
	//if(was_ooc_toggled)
	//	toggle_ooc(TRUE)

	stop_cinematic()

/// Whenever another cinematic starts to play over us, we have the chacne to block it.
/datum/cinematic/proc/handle_replacement_cinematics(datum/act/play_cinematic/play)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/cinematic/other = play.cinematic

	// Stop our's and allow others to play if we're local and it's global
	if(!is_global && other.is_global)
		stop_cinematic()
		return HOOK_DECLINE

	return TRUE

/// Hooked to mob_client_login on each watching mob.
/datum/cinematic/proc/on_watcher_client_login(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/watching_mob = A.target
	var/datum/notice/mob_client_login/event = A
	show_to(watching_mob, event.client)

/// Whenever a mob watching the cinematic logs in, show them the ongoing cinematic
/datum/cinematic/proc/show_to(mob/watching_mob, client/watching_client)

	if(!has_trait_from(watching_mob, TRAIT_NO_TRANSFORM, CINEMATIC_SOURCE))
		lock_mob(watching_mob)

	// Only show the actual cinematic to cliented mobs.
	if(!watching_client || (watching_client in watching))
		return

	rel_add(src, nameof(watching), watching_client)
	watching_mob.overlay_fullscreen("cinematic", /atom/movable/screen/fullscreen/cinematic_backdrop)
	watching_client.screen += screen
	// Clients cannot be hooked; a client that goes away leaves a null the loops skip.

/// Simple helper for playing sounds from the cinematic.
/datum/cinematic/proc/play_cinematic_sound(sound_to_play)
	if(is_global)
		SEND_SOUND(world, sound_to_play)
	else
		for(var/client/watching_client in watching)
			SEND_SOUND(watching_client, sound_to_play)

/// Invoke any special callbacks for actual effects synchronized with animation.
/// (Such as a real nuke explosion happening midway)
/datum/cinematic/proc/invoke_special_callback()
	special_callback?.Invoke()

/// The actual cinematic occurs here.
/datum/cinematic/proc/play_cinematic()
	return

/// Stops the cinematic and removes it from all the viewers.
/datum/cinematic/proc/stop_cinematic()
	for(var/client/viewing_client in watching?.Copy())
		remove_watcher(viewing_client)
	rel_clear(src, nameof(watching))

	for(var/mob/locked_mob in locked?.Copy())
		unlock_mob(locked_mob)

	spent(src)

/// Locks a mob, preventing them from moving, being hurt, or acting
/datum/cinematic/proc/lock_mob(mob/to_lock)
	rel_add(src, nameof(locked), to_lock)
	add_trait(to_lock, TRAIT_NO_TRANSFORM, CINEMATIC_SOURCE)

/// Unlocks a previously locked mob
/datum/cinematic/proc/unlock_mob(mob/locked_mob)
	if(QDELETED(locked_mob))
		return
	remove_trait(locked_mob, TRAIT_NO_TRANSFORM, CINEMATIC_SOURCE)
	unobserve(locked_mob, /datum/notice/mob_client_login, src)

/// Removes the passed client from our watching list.
/datum/cinematic/proc/remove_watcher(client/no_longer_watching)

	if(!(no_longer_watching in watching))
		CRASH("cinematic remove_watcher was passed a client which wasn't watching.")

	// We'll clear the cinematic if they have a mob which has one,
	// but we won't remove TRAIT_NO_TRANSFORM. Wait for the cinematic end to do that.
	no_longer_watching.mob?.clear_fullscreen("cinematic")
	no_longer_watching.screen -= screen

	rel_remove(src, nameof(watching), no_longer_watching)


#undef CINEMATIC_SOURCE

