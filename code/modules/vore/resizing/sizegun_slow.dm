#define SIZE_SHRINK 0
#define SIZE_GROW 1

/obj/item/slow_sizegun
	name = "gradual size gun"
	desc = "A highly advanced ray gun, designed for progressive and gradual changing of size. Size trading can be toggled on via alt-clicking."
	icon = 'icons/obj/gun.dmi'
	icon_state = "sizegun-old-0"
	var/base_icon_state = "sizegun-old"
	w_class = ITEMSIZE_NORMAL
	force = 0
	slot_flags = SLOT_BELT
	var/beam_range = 4 // How many tiles away it can scan. Changing this also changes the box size.
	/// The running beam (sizegun_step()): target, user and held-item handles, the target's starting
	/// scale, the beam handle, the outline filter, the box segments and the user's client.
	var/tmp/list/beam_state
	var/sizeshift_mode = SIZE_SHRINK
	var/dorm_size = TRUE
	var/size_increment = 0.01
	// The scan in progress (relation views: a deleted target, user or beam reads null, and the
	// next step still reaches sizegun_finish() to clean up).
	var/atom/current_target
	var/mob/living/scan_user
	var/obj/item/scan_hand
	var/datum/beam/scan_beam_effect
	var/trading = 0
TRACKED(/obj/item/slow_sizegun, sizeshift_mode)

/// Set to true when scanning, to stop multiple scans.
OM_FIELD(/obj/item/slow_sizegun, busy, FALSE, CHANGE_EXPLICIT)
/// The look (the draw sweep: from its template).
/obj/item/slow_sizegun/draw(datum/look/look)
	..()
	look.state("[base_icon_state]-[sizeshift_mode][busy ? "-active" : ""]")

/obj/item/slow_sizegun/proc/should_stop(mob/living/target, mob/living/user, active_hand)
	if(!target || !user || !active_hand || !istype(target) || !istype(user) || !busy)
		return TRUE

	if(user.get_active_hand() != active_hand)
		return TRUE

	if(user.incapacitated(INCAPACITATION_DEFAULT))
		return TRUE

	if(get_dist(user, target) > beam_range)
		return TRUE

	var/unresizable = FALSE
	if(ishuman(target))
		var/mob/living/carbon/human/H = target
		if(istype(H.get_equipped_item(SLOT_ID_GLOVES), /obj/item/clothing/gloves/bluespace))
			unresizable = TRUE
			return

	if(!(target.resizable))
		unresizable = TRUE

	if(unresizable)
		return TRUE

	if(trading == 1 && !(user.resizable))
		return TRUE

	if(!(target.has_large_resize_bounds()) && (target.size_multiplier >= RESIZE_MAXIMUM) && sizeshift_mode == SIZE_GROW)
		return TRUE

	if(target.size_multiplier >= RESIZE_MAXIMUM_DORMS && sizeshift_mode == SIZE_GROW)
		return TRUE

	if(!(target.has_large_resize_bounds()) && (target.size_multiplier <= RESIZE_MINIMUM) && sizeshift_mode == SIZE_SHRINK)
		return TRUE

	if(target.size_multiplier <= RESIZE_MINIMUM_DORMS && sizeshift_mode == SIZE_SHRINK)
		return TRUE

	if(trading == 1 && !(user.has_large_resize_bounds()) && (user.size_multiplier >= RESIZE_MAXIMUM) && sizeshift_mode == SIZE_GROW)
		return TRUE

	if(trading == 1 && user.size_multiplier >= RESIZE_MAXIMUM_DORMS && sizeshift_mode == SIZE_GROW)
		return TRUE

	if(trading == 1 && !(user.has_large_resize_bounds()) && (user.size_multiplier <= RESIZE_MINIMUM) && sizeshift_mode == SIZE_SHRINK)
		return TRUE

	if(trading == 1 && user.size_multiplier <= RESIZE_MINIMUM_DORMS && sizeshift_mode == SIZE_SHRINK)
		return TRUE

	return FALSE

/obj/item/slow_sizegun/afterattack(atom/target, mob/user, proximity_flag)
	// Things that invalidate the scan immediately.
	if(isturf(target))
		for(var/atom/A as anything in target) // If we can't scan the turf, see if we can scan anything on it, to help with aiming.
			if(isliving(A))
				target = A
				break

	if(busy && !(target == current_target))
		to_chat(user, span_warning("\The [src] is already targeting something."))
		return

	if(!isliving(target))
		to_chat(user, span_warning("\the [target] is not a valid target."))
		return

	var/mob/living/L = target

	if(get_dist(target, user) > beam_range)
		to_chat(user, span_warning("You are too far away from \the [target] to affect it. Get closer."))
		return

	if(target == current_target && busy)
		sizegun_finish()
		return

	var/unresizable = FALSE
	if(ishuman(L))
		var/mob/living/carbon/human/H = L
		if(istype(H.get_equipped_item(SLOT_ID_GLOVES), /obj/item/clothing/gloves/bluespace))
			unresizable = TRUE
			return

	if(!(L.resizable))
		unresizable = TRUE

	if(trading == 1 && !(user.resizable))
		unresizable = TRUE

	if(unresizable)
		to_chat(user, span_warning("\the [target] is immune to resizing."))

	// Start the effects
	rel_set(src, nameof(current_target), target)
	var/datum/beam/scan_beam = user.Beam(target, icon = 'icons/effects/beam_vr.dmi', icon_state = "zappy1", time = 6000)
	var/filter = filter(type = "outline", size = 1, color = "#00FF00")
	target.filters += filter
	var/list/box_segments = list()
	if(user.client)
		box_segments = draw_box(target, beam_range, user.client)
		color_box(box_segments, "#00FF00", 5)

	play_sfx(src, SFX_WEAPONS_WAVE, volume = 50)

	var/active_hand = user.get_active_hand()
	var/previous_scale = L.size_multiplier

	// The beam steps every 0.3 s while busy (an every() while busy; S10b: was a stoplag() loop) until
	// should_stop(). The target, user, hand and beam are relation views on the gun, so a deleted
	// target or user still reaches sizegun_finish() and the effects are cleaned up.
	rel_set(src, nameof(scan_user), user)
	rel_set(src, nameof(scan_hand), active_hand)
	rel_set(src, nameof(scan_beam_effect), scan_beam)
	beam_state = list(previous_scale, filter, box_segments, user.client)
	set_busy(TRUE)
	if(should_stop(L, user, active_hand))
		sizegun_finish()

/// One step of the beam (the every() while busy): resize, then stop if it should.
/obj/item/slow_sizegun/proc/sizegun_step(datum/act/timer/A)
	var/list/state = beam_state
	if(!state)
		set_busy(FALSE)
		return
	var/mob/living/L = current_target
	var/mob/living/U = scan_user
	var/active_hand = scan_hand
	if(!L || !U)
		sizegun_finish()
		return
	if(sizeshift_mode == SIZE_SHRINK)
		L.resize((L.size_multiplier - size_increment), uncapped = L.has_large_resize_bounds(), aura_animation = FALSE)
		if(trading == 1)
			U.resize((U.size_multiplier + size_increment), uncapped = U.has_large_resize_bounds(), aura_animation = FALSE)
	else if(sizeshift_mode == SIZE_GROW)
		L.resize((L.size_multiplier + size_increment), uncapped = L.has_large_resize_bounds(), aura_animation = FALSE)
		if(trading == 1)
			U.resize((U.size_multiplier - size_increment), uncapped = U.has_large_resize_bounds(), aura_animation = FALSE)
	if(should_stop(L, U, active_hand))
		sizegun_finish()
		return

/// The beam ends: size-strip the target if it changed enough, then clean up the effects.
/obj/item/slow_sizegun/proc/sizegun_finish()
	var/list/state = beam_state
	var/mob/living/L = current_target
	var/datum/beam/scan_beam = scan_beam_effect
	beam_state = null
	set_busy(FALSE)
	rel_clear(src, nameof(current_target))
	rel_clear(src, nameof(scan_user))
	rel_clear(src, nameof(scan_hand))
	rel_clear(src, nameof(scan_beam_effect))
	if(!state)
		return
	var/previous_scale = state[1]
	var/filter = state[2]
	var/list/box_segments = state[3]
	var/client/C = state[4]

	if(ishuman(L))
		var/mob/living/carbon/human/our_target = L
		var/size_difference = previous_scale - our_target.size_multiplier
		if((size_difference >= 0.3) || (size_difference <= -0.3))
			if(our_target.size_strip_preference == SIZESTRIP_ITEMS)
				our_target.drop_all_clothing(FALSE)
			else if(our_target.size_strip_preference == SIZESTRIP_ALL)
				our_target.drop_all_clothing(TRUE)

	// Now clean up the effects.
	if(scan_beam)
		spent(scan_beam)
	if(L)
		L.filters -= filter
	if(C) // If for some reason they logged out mid-scan the box will be gone anyways.
		delete_box(box_segments, C)

CAPABILITIES(/obj/item/slow_sizegun)
	op("slow_sizegun_mode_self", in_hand(), label("Switch mode"), then(PROC_REF(slow_sizegun_mode_self)))
	op("slow_sizegun_trading_alt", hand(), ungated(), gesture(GESTURE_ALT), label("Toggle size trading"), then(PROC_REF(slow_sizegun_trading_alt)))
	// The beam steps every 0.3 s while busy; sizegun_finish() clears busy, which ends the work.
	every(0.3 SECONDS, then(PROC_REF(sizegun_step)), when = nameof(busy))

/// Old attack_self: stop a scan in progress, or swap between growing and shrinking.
/obj/item/slow_sizegun/proc/slow_sizegun_mode_self(datum/act/op/A)
	var/mob/living/user = A.actor
	if(busy)
		sizegun_finish()
	else
		set_sizeshift_mode(!sizeshift_mode)
		to_chat(user, span_notice("\The [src] will now [sizeshift_mode ? "grow" : "shrink"] its targets."))


#undef SIZE_SHRINK
#undef SIZE_GROW


#define ICON_SIZE 32

// Draws a box showing the limits of movement while scanning something.
// Only the client supplied will see the box.
/obj/item/slow_sizegun/proc/draw_box(atom/A, box_size, client/C)
	. = list()
	// Things moved with pixel_[x|y] will move the box, so this is to correct that.
	var/pixel_x_correction = -A.pixel_x
	var/pixel_y_correction = -A.pixel_y

	// First, place the bottom-left corner.
	. += draw_line(A, SOUTHWEST, (-box_size * ICON_SIZE) + pixel_x_correction, (-box_size * ICON_SIZE) + pixel_y_correction, C)

	// Make a line on the bottom, going right.
	for(var/i = 1 to (box_size * 2) - 1)
		var/x_displacement = (-box_size * ICON_SIZE) + (ICON_SIZE * i) + pixel_x_correction
		var/y_displacement = (-box_size * ICON_SIZE) + pixel_y_correction
		. += draw_line(A, SOUTH, x_displacement, y_displacement, C)

	// Bottom-right corner.
	. += draw_line(A, SOUTHEAST, (box_size * ICON_SIZE) + pixel_x_correction, (-box_size * ICON_SIZE) + pixel_y_correction, C)

	// Second line, for the right side going up.
	for(var/i = 1 to (box_size * 2) - 1)
		var/x_displacement = (box_size * ICON_SIZE) + pixel_x_correction
		var/y_displacement = (-box_size * ICON_SIZE) + (ICON_SIZE * i) + pixel_y_correction
		. += draw_line(A, EAST, x_displacement, y_displacement, C)

	// Top-right corner.
	. += draw_line(A, NORTHEAST, (box_size * ICON_SIZE) + pixel_x_correction, (box_size * ICON_SIZE) + pixel_y_correction, C)

	// Third line, for the top, going right.
	for(var/i = 1 to (box_size * 2) - 1)
		var/x_displacement = (-box_size * ICON_SIZE) + (ICON_SIZE * i) + pixel_x_correction
		var/y_displacement = (box_size * ICON_SIZE) + pixel_y_correction
		. += draw_line(A, NORTH, x_displacement, y_displacement, C)

	// Top-left corner.
	. += draw_line(A, NORTHWEST, (-box_size * ICON_SIZE) + pixel_x_correction, (box_size * ICON_SIZE) + pixel_y_correction, C)

	// Fourth and last line, for the left side going up.
	for(var/i = 1 to (box_size * 2) - 1)
		var/x_displacement = (-box_size * ICON_SIZE) + pixel_x_correction
		var/y_displacement = (-box_size * ICON_SIZE) + (ICON_SIZE * i) + pixel_y_correction
		. += draw_line(A, WEST, x_displacement, y_displacement, C)

#undef ICON_SIZE

// Draws an individual segment of the box.
/obj/item/slow_sizegun/proc/draw_line(atom/A, line_dir, line_pixel_x, line_pixel_y, client/C)
	var/image/line = image(icon = 'icons/effects/effects.dmi', loc = A, icon_state = "stripes", dir = line_dir)
	line.pixel_x = line_pixel_x
	line.pixel_y = line_pixel_y
	line.plane = PLANE_FULLSCREEN // It's technically a HUD element but it doesn't need to show above item slots.
	line.appearance_flags = RESET_TRANSFORM|RESET_COLOR|RESET_ALPHA|NO_CLIENT_COLOR|TILE_BOUND
	line.alpha = 125
	C.images += line
	return line

// Removes the box that was generated before from the client.
/obj/item/slow_sizegun/proc/delete_box(list/box_segments, client/C)
	for(var/i in box_segments)
		C.images -= i
		spent(i)

/obj/item/slow_sizegun/proc/color_box(list/box_segments, new_color, new_time)
	for(var/i in box_segments)
		animate(i, color = new_color, time = new_time)

//Alt click to activate size trading

/// Old click_alt: toggle size trading.
/obj/item/slow_sizegun/proc/slow_sizegun_trading_alt(datum/act/op/A)
	var/mob/user = A.actor
	if (trading == 0)
		trading = 1
		to_chat(user, span_notice("\The [src] will now trade your targets size for your own."))
	else
		trading = 0
		to_chat(user, span_notice("\The [src] will no longer trade your targets size for your own."))
	return TRUE
