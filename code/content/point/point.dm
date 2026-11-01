#define POINT_TIME (2.5 SECONDS)

/atom/movable/proc/point_at(atom/pointed_atom)
	if(!isturf(loc))
		return

	if (pointed_atom?.loc == src)
		create_point_bubble(pointed_atom)
		return

	var/turf/tile = get_turf(pointed_atom)
	if (!tile)
		return

	var/turf/our_tile = get_turf(src)
	var/obj/visual = new /obj/effect/temp_visual/point(our_tile, invisibility)

	animate(visual, pixel_x = (tile.x - our_tile.x) * world.icon_size + pointed_atom.pixel_x, pixel_y = (tile.y - our_tile.y) * world.icon_size + pointed_atom.pixel_y, time = 1.7, easing = EASE_OUT)

/atom/movable/proc/create_point_bubble(atom/pointed_atom)
	var/mutable_appearance/pointed_atom_appearance = new(pointed_atom.appearance)
	pointed_atom_appearance.blend_mode = BLEND_INSET_OVERLAY
	pointed_atom_appearance.plane = FLOAT_PLANE
	pointed_atom_appearance.layer = FLOAT_LAYER
	pointed_atom_appearance.pixel_x = 0
	pointed_atom_appearance.pixel_y = 0

	var/mutable_appearance/point_visual = mutable_appearance(
		'icons/mob/screen1.dmi',
		"arrow"
	)

	var/image/thought_bubble = look_composed_image(image('icons/effects/effects.dmi', "thought_bubble"), list(pointed_atom_appearance, point_visual))
	thought_bubble.plane = PLANE_RUNECHAT
	thought_bubble.appearance_flags = KEEP_APART
	thought_bubble.pixel_x = 16
	thought_bubble.pixel_y = 32
	thought_bubble.alpha = 200
	thought_bubble.mouse_opacity = MOUSE_OPACITY_TRANSPARENT

	// A look part that takes itself back: the bubble is the holder's look for POINT_TIME.
	look_flash(src, thought_bubble, POINT_TIME)

/obj/effect/temp_visual/point
	name = "pointer"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "arrow"
	plane = ABOVE_PLANE
	duration = POINT_TIME

CAPABILITIES(/obj/effect/temp_visual/point)
	param(nameof(invisibility), pos = 1, apply = PROC_REF(settle_on_turf))

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). The pointer is drawn on the turf, offset as the thing pointed at.
/obj/effect/temp_visual/point/proc/settle_on_turf(set_invis)
	var/atom/old_loc = loc
	abstract_move(get_turf(src))
	set_pixel_x(old_loc.pixel_x)
	set_pixel_y(old_loc.pixel_y)

#undef POINT_TIME

/mob/verb/pointed(atom/A as mob|obj|turf in view())
	set name = "Point To"
	set category = VERB_CAT_OBJECT

	if(istype(A, /obj/effect/temp_visual/point))
		return FALSE

	input_submit(new /datum/input_event/point(src, A))

/mob/proc/_pointed(atom/pointing_at)
	if(client && !(pointing_at in view(client.view, src)))
		return FALSE

	point_at(pointing_at)

	face_atom(pointing_at)
	return TRUE
