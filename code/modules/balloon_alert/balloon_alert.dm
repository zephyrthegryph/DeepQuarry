#define BALLOON_TEXT_WIDTH 200
#define BALLOON_TEXT_SPAWN_TIME (0.2 SECONDS)
#define BALLOON_TEXT_FADE_TIME (0.1 SECONDS)
#define BALLOON_TEXT_FULLY_VISIBLE_TIME (0.7 SECONDS)
#define BALLOON_TEXT_TOTAL_LIFETIME(mult) (BALLOON_TEXT_SPAWN_TIME + BALLOON_TEXT_FULLY_VISIBLE_TIME*mult + BALLOON_TEXT_FADE_TIME)
#define BALLOON_TEXT_CHAR_LIFETIME_INCREASE_MULT (0.05)
#define BALLOON_TEXT_CHAR_LIFETIME_INCREASE_MIN 10

/// Creates text that will float from the atom upwards to the viewer.
/atom/proc/balloon_alert(mob/viewer, text)
	SHOULD_NOT_SLEEP(TRUE)

	var/client/viewer_client = viewer?.client
	if(!viewer_client?.prefs?.read_preference(/datum/preference/toggle/runechat_balloon_messages))
		return //no! I don't want that.
	// The text's height is measured on the viewer's client (a round trip): DX-exec answers later.
	dx_measure_text(src, viewer_client, text, null, BALLOON_TEXT_WIDTH, PROC_REF(balloon_alert_perform), viewer, text)

/atom/proc/balloon_alert_visible(message, self_message, blind_message, range = world.view, list/exclude_mobs = null)
	SHOULD_NOT_SLEEP(TRUE)

	var/runechat_enabled

	var/list/hearers = get_mobs_in_view(range, src)
	hearers -= exclude_mobs

	for(var/mob/M in hearers)

		runechat_enabled = M.client?.prefs?.read_preference(/datum/preference/toggle/runechat_mob)

		if(M.client && !runechat_enabled)
			continue

		if(M.is_blind())
			continue

		balloon_alert(M, (M == src && self_message) || message)

/// dx_measure_text() callback: shows the balloon, now that its text's size ("WxH") is known.
/atom/proc/balloon_alert_perform(measured, mob/viewer, text)

	var/client/viewer_client = viewer?.client

	if(!viewer_client?.prefs?.read_preference(/datum/preference/toggle/runechat_balloon_messages))
		return //no! I don't want that.


	if(isnull(viewer_client))
		return

	if(isbelly(src.loc))
		return

	var/bound_width = world.icon_size
	if(ismovable(src))
		var/atom/movable/movable_source = src
		bound_width = movable_source.bound_width
	if(isrobot(src) || isanimal(src))
		bound_width += get_oversized_icon_offsets()["x"]


	var/image/balloon_alert = image(loc = isturf(src) ? src : get_atom_on_turf(src), layer = ABOVE_MOB_LAYER)
	balloon_alert.plane = PLANE_RUNECHAT
	balloon_alert.alpha = 0
	balloon_alert.appearance_flags = RESET_ALPHA|RESET_COLOR|RESET_TRANSFORM
	balloon_alert.maptext = MAPTEXT("<span style='text-align: center; -dm-text-outline: 1px #0005'>[text]</span>")
	balloon_alert.maptext_x = (BALLOON_TEXT_WIDTH - bound_width) * -0.5
	WXH_TO_HEIGHT(measured, balloon_alert.maptext_height)
	balloon_alert.maptext_width = BALLOON_TEXT_WIDTH

	viewer_client?.images += balloon_alert

	var/length_mult = 1 + max(0, length(strip_html_simple(text)) - BALLOON_TEXT_CHAR_LIFETIME_INCREASE_MIN) * BALLOON_TEXT_CHAR_LIFETIME_INCREASE_MULT

	animate(
		balloon_alert,
		pixel_y = world.icon_size * 1.2,
		time = BALLOON_TEXT_TOTAL_LIFETIME(length_mult),
		easing = SINE_EASING | EASE_OUT,
	)

	animate(
		alpha = 255,
		time = BALLOON_TEXT_SPAWN_TIME,
		easing = CUBIC_EASING | EASE_OUT,
		flags = ANIMATION_PARALLEL,
	)

	animate(
		alpha = 0,
		time = BALLOON_TEXT_FULLY_VISIBLE_TIME * length_mult,
		easing = CUBIC_EASING | EASE_IN,
	)

	dq_add_z_update_image(src, balloon_alert) // register with DQ z-image tracker so balloons reposition across z-moves
	after(balloon_alert.loc, BALLOON_TEXT_TOTAL_LIFETIME(length_mult), PROC_REF(forget_balloon_alert), with = list(balloon_alert))
	after(null, BALLOON_TEXT_TOTAL_LIFETIME(length_mult), GLOBAL_PROC_REF(remove_image_from_client), with = list(balloon_alert, viewer_client), keeps_dead = TRUE)

/atom/proc/forget_balloon_alert(image/balloon_alert)
	dq_remove_z_update_image(src, balloon_alert) // paired teardown for dq_add_z_update_image above

#undef BALLOON_TEXT_FADE_TIME
#undef BALLOON_TEXT_FULLY_VISIBLE_TIME
#undef BALLOON_TEXT_SPAWN_TIME
#undef BALLOON_TEXT_TOTAL_LIFETIME
#undef BALLOON_TEXT_WIDTH
#undef BALLOON_TEXT_CHAR_LIFETIME_INCREASE_MULT
#undef BALLOON_TEXT_CHAR_LIFETIME_INCREASE_MIN
