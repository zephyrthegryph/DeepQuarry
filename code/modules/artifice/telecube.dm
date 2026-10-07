/*
 * Home of the telecube.
 */

/datum/category_item/catalogue/anomalous/precursor_a/telecube
	name = "Quantomatically Entangled Digicube"

	desc = "An enigmatic cube that appears superficially similar to a Positronic Cube. \
	However, the similarities hopefully end there, as this device emits no sound during \
	operation or observation. Its alloy composition is unknown, though it is incredibly \
	dense, as it resists any and all forms of radiation.<br>\
	Upon physical contact, however, the device will translocate the offending entity to a \
	matching twin cube, generating no detectable radiation. This process occurs at speeds \
	unmatched even by modern predictions of Bluespace technology, and with no visible power \
	source."

	value = CATALOGUER_REWARD_HARD

// Standard one needs to be smacked onto another one to link together.
/obj/item/telecube
	name = "locus"
	desc = "A strange metallic cube that pulses silently."
	icon = 'icons/obj/props/telecube.dmi'
	icon_state = "cube"
	w_class = ITEMSIZE_NO_CONTAINER // Made impossible to store to help resolve a certain repeated issue that has been happening with these.

	catalogue_data = list(/datum/category_item/catalogue/anomalous/precursor_a/telecube)

	// slowdown = 2.5 // Removes slowdown in exchange for being impossible to store in backpacks.

	throw_range = 2

	var/tmp/obj/item/telecube/mate

	var/start_paired = FALSE
	var/mirror_colors = FALSE

	var/randomize_colors = FALSE

	var/glow_color = "#FFFFFF"
	var/image/glow = null
	var/image/charge = null

	var/cooldown_time = 30 SECONDS
	var/ready = TRUE

// How far the cube will search for things to teleport. 0 = only contacting objects / mobs.
	var/teleport_range = 0 // For all that is holy, do not change this unless you know what you're doing.

	var/omniteleport = FALSE // Will this teleport anchored things too?

// ALLOW(init/INSTANCE_STATE): rolls its colours and makes its paired cube where it is placed
/obj/item/telecube/Initialize(mapload)
	. = ..()

	glow = image("[icon_state]-ready")
	glow.appearance_flags = KEEP_APART
	charge = image("[icon_state]-charging")
	charge.appearance_flags = KEEP_APART

	if(randomize_colors)
		glow_color = rgb(rand(0, 255),rand(0, 255),rand(0, 255))
		color = rgb(rand(30, 255),rand(30, 255),rand(30, 255))

	if(start_paired)
		rel_set(src, nameof(mate), new /obj/item/telecube(src.loc))
		if(mirror_colors)
			mate().glow_color = color
			mate().color = glow_color
		else
			mate().glow_color = glow_color
			mate().color = color
		mate().pair_cube(src)

	update_icon()

DECLARE_APPEARANCE_PROC(/obj/item/telecube, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/telecube/appearance_overlays()
	. = list()
	. += ..()

	if(isturf(loc))
		glow.plane = PLANE_LIGHTING_ABOVE
		charge.plane = PLANE_LIGHTING_ABOVE
	else //So it shows up in inventory looking ok
		glow.plane = initial(glow.plane)
		charge.plane = initial(glow.plane)

	if(glow_color != glow.color)
		glow.color = glow_color
		charge.color = glow_color

	if(!ready)
		. += charge
	else
		. += glow

// its mate collapses into an explosion.
/obj/item/telecube/on_destroy(force)
	if(mate())
		var/turf/T = get_turf(mate())
		mate().visible_message(span_critical("\The [mate()] collapses into itself!"))
		mate().mate = null
		explosion(T,1,3,7)

	..()

/obj/item/telecube/equipped()
	. = ..()
	update_icon()

/obj/item/telecube/dropped(mob/user, equipping, slot)
	. = ..()
	update_icon()

/obj/item/telecube/proc/pair_cube(obj/item/telecube/M)
	if(mate())
		return 0
	else
		rel_set(src, nameof(mate), M)
		update_icon()
		return 1

/obj/item/telecube/proc/teleport_to_mate(atom/movable/A, areaporting = FALSE)
	. = FALSE

	if(!istype(A))
		return .

	if(A == src || A == mate())
		A.visible_message(span_alien("\The [A] distorts and fades, before popping back into existence."))
		fade_and_move(A, null)
		return .

	var/mob/living/L = src.loc

	if(istype(L))
		L << 'sound/effects/singlebeat.ogg'
		L.drop_from_inventory(src)
		forceMove(get_turf(src))

	if(!ready)
		return .

	if((A.anchored && !omniteleport) || !mate())
		A.visible_message(span_alien("\The [A] distorts for a moment, before reforming in the same position."))
		fade_and_move(A, null)
		return .

	var/turf/TLocate = get_turf(mate())

	var/turf/T1 = get_turf(locate(TLocate.x + (A.x - x), TLocate.y + (A.y - y), TLocate.z))

	if(T1)
		A.visible_message(span_alien("\The [A] fades out of existence."))
		fade_and_move(A, T1, TRUE)
		. = TRUE
	else
		return .

	if(teleport_range && !areaporting)
		for(var/atom/movable/M in orange(teleport_range, A))
			teleport_to_mate(M, TRUE)

/obj/item/telecube/proc/swap_with_mate()
	. = FALSE

	if(!mate() || !teleport_range)
		return .

	var/list/objects_near_me = range(teleport_range, get_turf(src))
	var/list/objects_near_mate = range(teleport_range, get_turf(mate()))

	for(var/atom/movable/M in objects_near_me)
		teleport_to_mate(M, TRUE)

	for(var/atom/movable/M1 in objects_near_mate)
		mate().teleport_to_mate(M1, TRUE)

	. = TRUE
	return .

/obj/item/telecube/proc/cooldown(mate_too = FALSE)
	if(!ready)
		return

	ready = FALSE
	update_icon()
	after(src, cooldown_time, PROC_REF(ready))
	if(mate_too && mate())
		mate().cooldown(mate_too = FALSE) //No infinite recursion pls

/obj/item/telecube/proc/ready()
	ready = TRUE
	update_icon()

/// Fades `AM` out, moves it to `T` (if any) once faded, then fades it back in (half a second each).
/obj/item/telecube/proc/fade_and_move(atom/movable/AM, turf/T, announce = FALSE)
	animate_out(AM)
	after(src, 0.5 SECONDS, PROC_REF(fade_back_in), with = list(AM, T, announce))

/obj/item/telecube/proc/fade_back_in(atom/movable/AM, turf/T, announce)
	if(QDELETED(AM))
		return
	AM.filters -= filter(type="blur", size = 2)
	if(T)
		AM.forceMove(T)
	animate_in(AM)
	if(announce)
		AM.visible_message(span_alien("\The [AM] fades into existence."))

/obj/item/telecube/proc/clear_blur(atom/movable/AM)
	if(AM)
		AM.filters -= filter(type="blur", size = 0)

/obj/item/telecube/proc/animate_out(atom/movable/AM)
	//See atom cloak/uncloak animations for comments
	var/atom/movable/target = AM
	var/our_filter_index = target.filters.len+1
	AM.filters += filter(type="blur", size = 0)

	animate(target, alpha = 0, time = 5) //Out
	animate(target.filters[our_filter_index], size = 2, time = 5, flags = ANIMATION_PARALLEL)

/obj/item/telecube/proc/animate_in(atom/movable/AM)
	//See atom cloak/uncloak animations for comments
	var/atom/movable/target = AM
	var/our_filter_index = target.filters.len+1
	AM.filters += filter(type="blur", size = 2)

	animate(target, alpha = 255, time = 5) //In
	animate(target.filters[our_filter_index], size = 0, time = 5, flags = ANIMATION_PARALLEL)
	after(src, 0.5 SECONDS, PROC_REF(clear_blur), with = list(target))

/obj/item/telecube/item_ctrl_click(mob/user)
	if(Adjacent(user) && teleport_to_mate(user))
		cooldown(mate_too = FALSE)

/// Old click_alt.
/obj/item/telecube/proc/interaction_alt(datum/act/op/A)
	var/mob/user = A.actor
	if(Adjacent(user) && swap_with_mate())
		cooldown(mate_too = TRUE)
	return TRUE

/obj/item/telecube/Bump(atom/movable/AM)
	if(teleport_to_mate(AM))
		cooldown(mate_too = FALSE)
	. = ..()

CAPABILITIES(/obj/item/telecube)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), label("Alternate use"), then(PROC_REF(interaction_alt)))

/// Something walked into it (the bump action's notice).
/obj/item/telecube/proc/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	var/atom/movable/M = N.bumper
	if(teleport_to_mate(M))
		cooldown(mate_too = FALSE)

// Subtypes

/obj/item/telecube/mated
	start_paired = TRUE

/obj/item/telecube/randomized
	randomize_colors = TRUE

/obj/item/telecube/randomized/mated
	start_paired = TRUE

/obj/item/telecube/precursor
	glow_color = "#FF1D8E"
	color = "#2F1B26"

/obj/item/telecube/precursor/mated
	start_paired = TRUE

/obj/item/telecube/precursor/mated/zone
	teleport_range = 2

/obj/item/telecube/precursor/mated/mirrorcolor
	mirror_colors = TRUE


/// the mate this refers to (a relation view: null once it is deleted).
/obj/item/telecube/proc/mate() as /obj/item/telecube
	return mate
