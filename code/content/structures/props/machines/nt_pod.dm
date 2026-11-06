/**
 * This one is a bit more fancy than others. Anything in the contents (PLEASE LIMIT TO ONE THING)
 * will show up inside it! Also if you map in an item on it, it will grab that at mapload and start
 * in the 'closed, full of fluid' state, so you can put a body on it or whatever.
 *
 * As an aghost you can also dragdrop something into it (you have to be ghosted next to it)
 *
 * Possible 'state' options for change_state(state) are:
 * open: Open, no fluid or anything. At the end the contents are ejected.
 * closed: Closed, full of liquid
 * panel_open: Shows panel
 * panel_closed: Unshows panel
 */
// neotheology cloning pod from Eris
/obj/structure/prop/machine/nt_pod
	icon = 'icons/obj/props/decor.dmi'
	icon = 'icons/obj/props/decor32x64.dmi'
	icon_state = "nt_pod"
	bound_height = 64

	var/obj/effect/overlay/vis/outside
	var/obj/effect/overlay/vis/door
	var/obj/effect/overlay/vis/fluid

	var/contents_vis_flags = NONE
	var/contents_original_pixel_y = 0
	var/changing_state = FALSE
	/// The pod is closed on its occupant: the lit top and the liquid shadow show.
	var/pod_sealed = FALSE

/// The look: the sealed pod's top and underside, and the open panel.
/obj/structure/prop/machine/nt_pod/draw(datum/look/look)
	..()
	look.overlay("nt_pod_top_on", when = pod_sealed)
	look.overlay("nt_pod_under", when = pod_sealed)
	look.overlay("nt_pod_panel", when = panel_shown)

/// The pod's visual layers; a mapped pod takes in what stands on its tile (setup hook).
/obj/structure/prop/machine/nt_pod/proc/make_layers(mapload)
	rel_set(src, nameof(outside), add_vis_overlay(icon, "nt_pod_over", ABOVE_MOB_LAYER, MOB_PLANE, unique = TRUE))
	rel_set(src, nameof(door), add_vis_overlay(icon, "nothing", ABOVE_MOB_LAYER, MOB_PLANE, unique = TRUE))
	rel_set(src, nameof(fluid), add_vis_overlay(icon, "nothing", ABOVE_MOB_LAYER, MOB_PLANE, unique = TRUE))

	// Gather up our friends
	if(mapload)
		var/atom/movable/AM = locate_within(loc, /atom/movable)
		AM?.forceMove(src)

/obj/structure/prop/machine/nt_pod/Entered(atom/movable/mover)
	abduct(mover)

/obj/structure/prop/machine/nt_pod/proc/abduct(atom/movable/AM)
	// Save old settings
	contents_vis_flags = AM.vis_flags
	contents_original_pixel_y = AM.pixel_y

	// Arrange
	AM.add_filter("podmask", 1, alpha_mask_filter(render_source = "nt_podmask[REF(src)]", flags = MASK_INVERSE))
	AM.set_pixel_y(12)
	AM.vis_flags = VIS_INHERIT_ID|VIS_INHERIT_DIR
	vis_add(src, AM)
	if(ismob(AM))
		var/mob/M = AM
		buckle_mob(M, GLOB.authority_forced, FALSE)

	// TRAP THEM
	change_state("closed")

/obj/structure/prop/machine/nt_pod/proc/unduct(atom/movable/AM)
	// Geddout
	vis_remove(src, AM)
	if(ismob(AM))
		var/mob/M = AM
		unbuckle_mob(M, TRUE)
	// Cleanup
	AM.remove_filter("podmask")
	AM.forceMove(drop_location())
	AM.vis_flags = contents_vis_flags
	AM.set_pixel_y(contents_original_pixel_y)

CAPABILITIES(/obj/structure/prop/machine/nt_pod)
	setup(PROC_REF(make_layers), mapload = TRUE)
	after_init(0, then(PROC_REF(add_alpha_mask))) // its alpha mask is shown once Initialize() returns (relations proposal D11)
	ref_one(nameof(outside))
	ref_one(nameof(door))
	ref_one(nameof(fluid))
	op("interaction_drag", item(/atom/movable), gesture(GESTURE_DRAG), then(PROC_REF(interaction_drag)))

/// Old MouseDrop_T.
/obj/structure/prop/machine/nt_pod/proc/interaction_drag(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/AM = A.held
	if(contents_count(src))
		return OP_PASS
	if(!ismovable(AM))
		return OP_PASS
	if(!check_rights_for(user.client, R_HOLDER))
		return OP_PASS
	if(changing_state)
		return OP_PASS

	AM.forceMove(src)
	return OP_PASS

/obj/structure/prop/machine/nt_pod/change_state(state)
	. = ..()
	if(changing_state)
		return
	switch(state)
		if("open")
			changing_state = TRUE
			set_pod_sealed(FALSE)

			// Fluid drains
			fluid.icon_state = "nothing"
			flick("nt_pod_emptying", fluid) // 8ds

			// Door opens
			after(src, 0.8 SECONDS, PROC_REF(delayed_flick), with = list(door, "nothing", "nt_pod_opening", 0.9 SECONDS), keeps_dead = TRUE) // 9ds

		if("closed")
			changing_state = TRUE
			outside.layer = ABOVE_MOB_LAYER
			set_pod_sealed(TRUE)

			// Door closes
			door.icon_state = "nt_pod_glass"
			flick("nt_pod_closing", door) // 9ds
			// Fluid fills
			after(src, 0.9 SECONDS, PROC_REF(delayed_flick), with = list(fluid, "nt_pod_liquid", "nt_pod_filling")) // 8ds

		if("panel_open")
			set_panel_shown(TRUE)
		if("panel_closed")
			set_panel_shown(FALSE)

// Old Virology stuff

/obj/structure/prop/machine/nt_pod/proc/delayed_flick(obj/effect/overlay/ovrl, icon_state, flicked, get_out_time)
	if(ovrl) // the overlay may be gone; the pod still has to finish changing state
		ovrl.set_icon_state(icon_state)
		flick(flicked, ovrl)
	// GET OUT
	if(get_out_time)
		after(src, get_out_time, PROC_REF(get_out))
		return
	changing_state = FALSE

/obj/structure/prop/machine/nt_pod/proc/get_out()
	outside.layer = BELOW_MOB_LAYER
	if(contents_count(src))
		for(var/atom/movable/AM as anything in contents)
			unduct(AM)
	changing_state = FALSE

/// The alpha mask that keeps things from sneaking out of the pod.
/obj/structure/prop/machine/nt_pod/proc/add_alpha_mask(datum/act/timer/A)
	var/obj/effect/overlay/vis/mask = new
	mask.set_icon(icon)
	mask.set_icon_state("nt_pod_mask")
	mask.render_target = "*nt_podmask[REF(src)]"
	mask.vis_flags = VIS_INHERIT_ID
	vis_add(src, mask)
