#define COGBAR_ANIMATION_TIME (0.5 SECONDS)

/**
 * ### Cogbar
 * Represents that the user is busy doing something.
 */
/datum/cogbar
	/// Who's doing the thing
	var/user_handle
	/// The user client
	var/user_client_handle
	/// The visible element to other players
	var/cog_handle
	/// The blank image that overlaps the cog - hides it from the source user
	var/image/blank
	/// The offset of the icon
	var/offset_y
	/// Icon path of the cog
	var/cogicon
	/// The icon state
	var/cogiconstate

/datum/cogbar/New(mob/user, cogicon, cogiconstate)
	src.user_handle = om_handle(user)
	src.user_client_handle = om_handle(user.client)
	src.cogicon = cogicon
	src.cogiconstate = cogiconstate
	var/list/icon_offsets = user.get_oversized_icon_offsets()
	offset_y = icon_offsets["y"]
	if(isnull(cogicon))
		stack_trace("/datum/cogbar was created with a null icon.")
		qdel(src)
		return
	if(isnull(cogiconstate))
		stack_trace("/datum/cogbar was created with a null icon state.")
		qdel(src)
		return

	add_cog_to_user()

	RegisterSignal(user, COMSIG_QDELETING, PROC_REF(on_user_delete))

REF_OWNED(/datum/cogbar, "blank")

/// Phase 1: take the overlay off the user and the blank image (owned, dropped in phase 4) off the client.
/datum/cogbar/lifecycle_unbind()
	var/mob/user = user()
	if(user)
		GLOB.vis_overlays_service.remove_vis_overlay(user, user.managed_vis_overlays)
		user_client()?.images -= blank

/// Adds the cog to the user, visible by other players
/datum/cogbar/proc/add_cog_to_user()
	var/obj/effect/overlay/vis/cog = GLOB.vis_overlays_service.add_vis_overlay(user(),
		icon = cogicon,
		iconstate = cogiconstate,
		plane = ABOVE_PLANE,
		add_appearance_flags = APPEARANCE_UI_IGNORE_ALPHA,
		unique = TRUE,
		alpha = 0,
	)
	cog_handle = om_handle(cog)
	cog.pixel_y = ICON_SIZE_Y + offset_y
	animate(cog, alpha = user().alpha, time = COGBAR_ANIMATION_TIME)

	if(isnull(user_client()))
		return

	blank = image('icons/system/blank_32x32.dmi', cog, "nothing")
	blank.plane = ABOVE_PLANE //Change to SET_PLANE_EXPLICIT(blank, HIGH_GAME_PLANE, user)
	blank.appearance_flags = APPEARANCE_UI_IGNORE_ALPHA
	blank.override = TRUE

	user_client().images += blank

/// Removes the cog from the user
/datum/cogbar/proc/remove()
	if(isnull(cog()))
		qdel(src)
		return

	animate(cog(), alpha = 0, time = COGBAR_ANIMATION_TIME)

	om_qdel_after(src, COGBAR_ANIMATION_TIME)

/// When the user is deleted, remove the cog
/datum/cogbar/proc/on_user_delete(datum/source)
	SIGNAL_HANDLER

	qdel(src)

#undef COGBAR_ANIMATION_TIME

/// LC-refs: the busy mob -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/cogbar/proc/user() as /mob
	return om_resolve(user_handle)

/// LC-refs: the busy mob's client -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/cogbar/proc/user_client() as /client
	return om_resolve(user_client_handle)

/// LC-refs: the cog vis overlay (GLOB.vis_overlays_service owns it) -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/cogbar/proc/cog() as /obj/effect/overlay/vis
	return om_resolve(cog_handle)
