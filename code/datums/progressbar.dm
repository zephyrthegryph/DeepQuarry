#define PROGRESSBAR_HEIGHT 6
#define PROGRESSBAR_ANIMATION_TIME 5

/datum/progressbar
	parent_type = /datum/progress_view
	///The progress bar visual element.
	var/image/bar
	///The target where this progress bar is applied and where it is shown.
	var/atom/bar_loc
	///The mob whose client sees the progress bar.
	var/mob/user
	///The client seeing the progress bar.
	var/client/user_client
	///Effectively the number of steps the progress bar will need to do before reaching completion.
	var/goal = 1
	///Control check to see if the progress was interrupted before reaching its goal.
	var/last_progress = 0
	///Variable to ensure smooth visual stacking on multiple progress bars.
	var/listindex = 0
	///The type of our last value for bar_loc, for debugging
	var/location_type
	///Where to draw the progress bar above the icon
	var/offset_y
	/// animate_fill(): when the client-side fill started, and how long it takes.
	EXPIRY_DECLARE(fill_started)
	var/fill_duration = 0

/datum/progressbar/New(mob/User, goal_number, atom/target, starting_amount)
	. = ..()
	if (!istype(target))
		stack_trace("Invalid target [target] passed in")
		spent(src)
		return
	if(QDELETED(User) || !istype(User))
		stack_trace("/datum/progressbar created with [isnull(User) ? "null" : "invalid"] user")
		spent(src)
		return
	if(!isnum(goal_number))
		stack_trace("/datum/progressbar created with [isnull(User) ? "null" : "invalid"] goal_number")
		spent(src)
		return
	goal = goal_number
	rel_set(src, nameof(bar_loc), target)
	location_type = bar_loc().type

	var/list/icon_offsets = target.get_oversized_icon_offsets()
	var/offset_x = icon_offsets["x"]
	offset_y = icon_offsets["y"]

	bar = image('icons/effects/progressbar.dmi', bar_loc(), "prog_bar_0", pixel_x = offset_x)
	bar.plane = PLANE_PLAYER_HUD //Swap to SET_PLANE_EXPLICIT(bar, LAYER_HUD_ITEM, User) if we ever get the plane update
	bar.appearance_flags = APPEARANCE_UI_IGNORE_ALPHA
	rel_set(src, nameof(user), User)

	var/mob/bar_user = user
	LAZYADDASSOCLIST(bar_user.progressbars, bar_loc, src)
	var/list/bars = bar_user.progressbars[bar_loc]
	listindex = bars.len

	if(user().client)
		rel_set(src, nameof(user_client), user().client)
		add_prog_bar_image_to_client()

	observe(user(), /datum/notice/qdeleting, src, then(PROC_REF(on_user_delete)))
	observe(user(), /datum/notice/mob_logout, src, then(PROC_REF(clean_user_client)))
	observe(user(), /datum/notice/mob_login, src, then(PROC_REF(on_user_login)))

	if(starting_amount)
		update(starting_amount)

/// Phase 1: the bars above it on the same mob slide down to close the gap, and its image (owned,
/// dropped in phase 4) leaves the client. The user's bars are keyed by the target.
/datum/progressbar/lifecycle_unbind()
	var/mob/user = user()
	if(user)
		for(var/pb in user.progressbars?[bar_loc])
			var/datum/progressbar/progress_bar = pb
			if(progress_bar == src || progress_bar.listindex <= listindex)
				continue
			progress_bar.listindex--

			progress_bar.bar.pixel_z = ICON_SIZE_Y + offset_y + (PROGRESSBAR_HEIGHT * (progress_bar.listindex - 1))
			var/dist_to_travel = ICON_SIZE_Y + offset_y + (PROGRESSBAR_HEIGHT * (progress_bar.listindex - 1)) - PROGRESSBAR_HEIGHT
			animate(progress_bar.bar, pixel_z = dist_to_travel, time = PROGRESSBAR_ANIMATION_TIME, easing = SINE_EASING)

		LAZYREMOVEASSOC(user.progressbars, bar_loc, src)

	if(user_client())
		clean_user_client()


///Called right before the user's Destroy()
/datum/progressbar/proc/on_user_delete(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = A.target

	var/mob/dying_user = source
	dying_user.progressbars = null //We can simply nuke the list and stop worrying about updating other prog bars if the user itself is gone.
	rel_clear(src, nameof(user))
	ended_with(src)

///Removes the progress bar image from the user_client and nulls the variable, if it exists.
/datum/progressbar/proc/clean_user_client(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)

	if(!user_client()) //Disconnected, already gone.
		return
	user_client().images -= bar
	rel_clear(src, nameof(user_client))

///Called by user's Login(), it transfers the progress bar image to the new client.
/datum/progressbar/proc/on_user_login(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)

	if(user_client())
		if(user_client() == user().client) //If this was not client handling I'd condemn this sanity check. But clients are fickle things.
			return
		clean_user_client()
	if(!user().client) //Clients can vanish at any time, the bastards.
		return
	rel_set(src, nameof(user_client), user().client)
	add_prog_bar_image_to_client()

///Adds a smoothly-appearing progress bar image to the player's screen.
/datum/progressbar/proc/add_prog_bar_image_to_client()
	bar.pixel_z = 0
	bar.alpha = 0
	user_client().images += bar
	animate(bar, pixel_z = ICON_SIZE_Y + offset_y + (PROGRESSBAR_HEIGHT * (listindex - 1)), alpha = 255, time = PROGRESSBAR_ANIMATION_TIME, easing = SINE_EASING)

///Updates the progress bar image visually.
/datum/progressbar/proc/update(progress)
	progress = clamp(progress, 0, goal)
	if(progress == last_progress)
		return
	last_progress = progress
	bar.icon_state = "prog_bar_[round(((progress / goal) * 100), 5)]"

/// Fills the bar over `duration` deciseconds as a client-side animation: no server updates.
/datum/progressbar/animate_fill(duration)
	EXPIRY_STAMP(src, fill_started, CLOCK_WORLD)
	fill_duration = max(duration, 1)
	var/step_time = fill_duration / 20
	animate(bar, icon_state = "prog_bar_5", time = step_time, flags = ANIMATION_PARALLEL)
	for(var/pct in 10 to 100 step 5)
		animate(icon_state = "prog_bar_[pct]", time = step_time)

///Called on progress end, be it successful or a failure. Wraps up things to delete the datum and bar.
/// `success` null: judged by the last update().
/datum/progressbar/end_progress(success = null)
	if(fill_duration)
		var/pct = round(clamp((world.time - fill_started) / fill_duration, 0, 1) * 100, 5)
		last_progress = success ? goal : goal * pct / 100
		bar.icon_state = "prog_bar_[success ? 100 : pct]"
	if(success == FALSE || (isnull(success) && last_progress != goal))
		bar.icon_state = "[bar.icon_state]_fail"

	animate(bar, alpha = 0, time = PROGRESSBAR_ANIMATION_TIME)

	expire(PROGRESSBAR_ANIMATION_TIME)

///Progress bars are very generic, and what hangs a ref to them depends heavily on the context in which they're used
///So let's make hunting harddels easier yeah?
/datum/progressbar/proc/dump_harddel_info()
	if(harddel_deets_dumped)
		return
	harddel_deets_dumped = TRUE
	return "Owner's type: [location_type]"

#undef PROGRESSBAR_ANIMATION_TIME
#undef PROGRESSBAR_HEIGHT

/// The atom the bar floats over (a relation view).
/datum/progressbar/proc/bar_loc() as /atom
	return bar_loc

/// The mob whose client sees the bar (a relation view).
/datum/progressbar/proc/user() as /mob
	return user

/// The client seeing the bar (a relation view).
/datum/progressbar/proc/user_client() as /client
	return user_client
